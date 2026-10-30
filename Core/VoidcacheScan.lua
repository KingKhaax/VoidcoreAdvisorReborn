-- VoidcoreAdvisor: VoidcacheScan
-- Scans the Nebulous Voidcache tooltip for each of the player's loot
-- specializations to determine which items are obtainable per spec per
-- dungeon.  Items the player cannot receive with a given spec are then
-- marked as obtained so they no longer appear in the tracker.
--
-- Scanning sequence (outer = spec, inner = dungeon) ensures the same
-- Voidcache item ID is never read on two consecutive tooltip calls, which
-- avoids the client cache returning stale spec data.
--
-- If a tooltip returns fewer than MIN_LINES lines it is retried in-place
-- with a small delay (up to MAX_RETRIES times) before moving on.  Once
-- MIN_LINES is reached the scan continues retrying until two consecutive
-- reads return the same line count, confirming the tooltip has fully loaded.
local _, VCA = ...

VCA.VoidcacheScan = {}
local Scan = VCA.VoidcacheScan

-- ── Tuning constants ──────────────────────────────────────────────────────────

local MAX_RETRIES = 5 -- per (spec, dungeon) pair before giving up
local RETRY_DELAY = 0.35 -- seconds between retries for the same item
local STEP_DELAY = 0.5 -- seconds between successful scan steps (slowed for readable logs)
local SPEC_CHANGE_DELAY = 1.2 -- seconds to wait after SetLootSpecialization
local MIN_LINES = 7 -- minimum tooltip lines required for a valid read

-- ── Logging ───────────────────────────────────────────────────────────────────

local function Log(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9090ff[VCA Scan]|r " .. tostring(msg))
end

-- ── Combat-interrupt frame ────────────────────────────────────────────────────

local _combatFrame = CreateFrame("Frame")

-- ── Scan state ────────────────────────────────────────────────────────────────
-- nil when idle, table when a scan is running.

local _state = nil
local _raidState = nil

-- ── Progress callbacks ────────────────────────────────────────────────────────
-- Signature: fn(specIdx, specCount, dungeonIdx, dungeonCount, status)
--   During scan: specIdx/specCount/dungeonIdx/dungeonCount are numbers, status is nil.
--   On finish:   all four numbers are nil, status is "COMPLETE", "ABORTED", or "COMBAT".

local _progressCallback = nil
local _raidProgressCallback = nil

function Scan.SetProgressCallback(fn)
    _progressCallback = fn
end

function Scan.SetRaidProgressCallback(fn)
    _raidProgressCallback = fn
end

-- Chat progress: one line each time the scan passes a multiple of 10 %, with the steps done.
-- state.lastMark remembers the last percentage written.
local function LogStepProgress(state, done, total)
    if not (state and total and total > 0) then
        return
    end
    local mark = math.floor(done / total * 10) * 10
    if mark > (state.lastMark or 0) then
        state.lastMark = mark
        Log(string.format(VCA.L["SCAN_PROGRESS_PCT"], mark, done, total))
    end
end

local function NotifyProgress(specIdx, specCount, dungeonIdx, dungeonCount, status)
    if _progressCallback then
        _progressCallback(specIdx, specCount, dungeonIdx, dungeonCount, status)
    end
end

local function NotifyRaidProgress(specIdx, specCount, encounterIdx, encounterCount, status)
    if _raidProgressCallback then
        _raidProgressCallback(specIdx, specCount, encounterIdx, encounterCount, status)
    end
end

-- ── Tooltip parsing ───────────────────────────────────────────────────────────

local function StripColorCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Reads tooltip data from C_TooltipInfo and collects item names from line 7+.
-- Each item line is prefixed with "- " which is stripped to get the bare name.
-- Returns a { [itemName] = true } set, or nil when the data is missing or thin.
local function ParseVoidcacheTooltip(tooltipData, numLines)
    if numLines < MIN_LINES then
        return nil
    end
    local items = {}
    for i, lineData in ipairs(tooltipData.lines) do
        local text = lineData.leftText
        if text then
            -- Item entries start at line 7, each prefixed with "- "
            if i >= 7 then
                local clean = StripColorCodes(text)
                if clean:sub(1, 2) == "- " then
                    local itemName = clean:sub(3):match("^(.-)%s*$")
                    if itemName and itemName ~= "" then
                        items[itemName] = true
                    end
                end
            end
        end
    end
    return items
end

local function PoolStatus(parsed, nameCache)
    if parsed == nil then
        return "UNREADABLE"
    end
    if next(nameCache) == nil or next(parsed) == nil then
        return "OK"
    end
    for name in pairs(nameCache) do
        if parsed[name] then
            return "OK"
        end
    end
    return "MISMATCH"
end

local function ReportScan(doneKey, marked, stats, hintKey)
    local L = VCA.L
    Log(string.format(L[doneKey], marked, stats.pools - stats.unreadable - stats.mismatch, stats.pools))
    if stats.unreadable > 0 then
        Log(string.format(L["SCAN_UNREADABLE"], stats.unreadable))
    end
    if stats.mismatch > 0 then
        Log(string.format(L["SCAN_MISMATCH"], stats.mismatch))
    end
    if stats.uncached > 0 then
        Log(string.format(L["SCAN_UNCACHED"], stats.uncached))
    end
    if marked == 0 then
        Log(L[hintKey])
    else
        Log(L["SCAN_UNDO_HINT"])
    end
end

local function CollectPool(specID, sourceType, sourceID, diffID, nameCache, seen, pending)
    for itemName, itemID in pairs(nameCache) do
        if not seen[itemName] and not (VCA.TankTrinkets and VCA.TankTrinkets.IsAdded(specID, itemID))
            and not VCA.Data.IsObtained(sourceType, sourceID, diffID, specID, itemID) then
            pending[#pending + 1] = {
                sourceType = sourceType,
                sourceID = sourceID,
                specID = specID,
                itemID = itemID,
                name = itemName
            }
        end
    end
end

local function UniqueNames(pending)
    local seen, names = {}, {}
    for _, entry in ipairs(pending) do
        if not seen[entry.itemID] then
            seen[entry.itemID] = true
            names[#names + 1] = entry.name
        end
    end
    return names
end

local function SourceLabel(entry)
    local name
    if entry.sourceType == VCA.ContentType.RAID then
        name = EJ_GetEncounterInfo(entry.sourceID)
    else
        name = EJ_GetInstanceInfo(entry.sourceID)
    end
    return name or ("#" .. entry.sourceID)
end

local function SpecLabel(specID)
    return select(2, GetSpecializationInfoByID(specID)) or tostring(specID)
end

local function BuildRows(pending)
    local byKey, rows = {}, {}
    for _, entry in ipairs(pending) do
        local key = entry.sourceType .. ":" .. entry.sourceID .. ":" .. entry.itemID
        local row = byKey[key]
        if not row then
            row = {itemID = entry.itemID, name = entry.name, source = SourceLabel(entry), specs = {}, entries = {}}
            byKey[key] = row
            rows[#rows + 1] = row
        end
        row.entries[#row.entries + 1] = entry
        row.specs[#row.specs + 1] = SpecLabel(entry.specID)
    end
    table.sort(rows, function(x, y)
        if x.source ~= y.source then
            return x.source < y.source
        end
        return x.name < y.name
    end)
    for _, row in ipairs(rows) do
        table.sort(row.specs)
        row.specText = table.concat(row.specs, ", ")
    end
    return rows
end

local function ConfirmMarks(pending, headerKey, onAccept)
    if #pending == 0 then
        onAccept({})
        return
    end
    local L = VCA.L
    local header = string.format(L[headerKey], #UniqueNames(pending))
    local ok = pcall(VCA.ScanSelect.Show, BuildRows(pending), header, onAccept, function()
        Log(L["SCAN_CANCELLED"])
    end)
    if not ok then
        Log(L["SCAN_UI_ERROR"])
    end
end

-- ── Name cache ────────────────────────────────────────────────────────────────

-- Returns { [localizedName] = itemID } for every item a specific spec can get
-- from the dungeon's Voidcache.  Relies on the item cache being warm.
local function BuildDungeonNameCache(instanceID, specID, missingSet)
    local dungeonData = VCA.SeasonData and VCA.SeasonData.dungeons[instanceID]
    if not dungeonData then
        return {}
    end
    local itemIDs = (dungeonData.bySpec and dungeonData.bySpec[specID]) or {}
    local nameCache = {}
    local missing = 0
    for _, itemID in ipairs(itemIDs) do
        local name = C_Item.GetItemInfo(itemID)
        if name and name ~= "" then
            nameCache[name] = itemID
        else
            missing = missing + 1
            missingSet[itemID] = true
        end
    end
    return nameCache
end

-- ── Public: availability check ────────────────────────────────────────────────

-- Returns true (or false, reason) indicating whether a scan can start now.
-- reason is "COMBAT" or "INSTANCE".
function Scan.CanScan()
    if InCombatLockdown() then
        return false, "COMBAT"
    end
    local _, instanceType = IsInInstance()
    if instanceType and instanceType ~= "none" then
        return false, "INSTANCE"
    end
    return true
end

function Scan.IsRunning()
    return _state ~= nil and _state.running == true
end

-- ── Abort ─────────────────────────────────────────────────────────────────────

local function AbortScan(reason)
    if not _state then
        return
    end
    _state.running = false

    -- Unregister guards before restoring loot spec so the restore call
    -- does not re-trigger the PLAYER_LOOT_SPEC_UPDATED handler.
    _combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    _combatFrame:UnregisterEvent("PLAYER_LOOT_SPEC_UPDATED")

    -- Restore the player's original loot spec.
    if _state.originalLootSpec ~= nil then
        SetLootSpecialization(_state.originalLootSpec)
    end

    NotifyProgress(nil, nil, nil, nil, reason or "ABORTED")
    _state = nil
end

-- ── Result application ────────────────────────────────────────────────────────

local function FinalizeScan()
    if not _state then
        return
    end

    local results = _state.results -- [specID][instanceID] = { [name]=true }
    local nameCaches = _state.nameCaches -- [specID][instanceID] = { [name]=itemID }
    local specs = _state.specs -- { {specID=N, index=I}, ... }

    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        AbortScan("NO_DB")
        return
    end

    local diffID = VCA.MythicPlusEJDifficulty
    local contentType = VCA.ContentType.MYTHIC_PLUS

    local stats = {
        pools = 0,
        unreadable = 0,
        mismatch = 0,
        uncached = 0
    }
    for _ in pairs(_state.missing) do
        stats.uncached = stats.uncached + 1
    end

    local instanceIDs = VCA.LootPool.GetSeasonDungeonInstanceIDs()
    local pending = {}

    for _, specEntry in ipairs(specs) do
        local specID = specEntry.specID
        local specResults = results[specID] or {}
        local specCaches = nameCaches[specID] or {}

        for _, instanceID in ipairs(instanceIDs) do
            local nameCache = specCaches[instanceID] or {}
            local specItems = specResults[instanceID]
            local status = PoolStatus(specItems, nameCache)
            stats.pools = stats.pools + 1

            if status == "OK" then
                CollectPool(specID, contentType, instanceID, diffID, nameCache, specItems, pending)
            elseif status == "UNREADABLE" then
                stats.unreadable = stats.unreadable + 1
            else
                stats.mismatch = stats.mismatch + 1
            end
        end
    end

    ConfirmMarks(pending, "SCAN_SELECT_HEADER", function(selected)
        if #pending > 0 and #selected == 0 then
            Log(VCA.L["SCAN_NOTHING_SELECTED"])
            return
        end
        db.obtained = db.obtained or {}
        db.obtainedBackup = db.obtainedBackup or {}
        db.obtainedBackup.mythicPlus = {}
        db.obtainedBackup.mythicPlusTime = time()
        for key, val in pairs(db.obtained) do
            if key:sub(1, 12) == "MYTHIC_PLUS:" then
                db.obtainedBackup.mythicPlus[key] = val
            end
        end
        for _, entry in ipairs(selected) do
            VCA.Data.SetObtained(contentType, entry.sourceID, diffID, entry.specID, entry.itemID, true)
        end
        ReportScan("SCAN_DONE", #UniqueNames(selected), stats, "SCAN_HINT_DUNGEON")
        if VCA.DungeonOverview and VCA.DungeonOverview.Refresh then
            VCA.DungeonOverview.Refresh()
        end
    end)

    -- 3. Restore original loot spec.
    _combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    _combatFrame:UnregisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    SetLootSpecialization(_state.originalLootSpec or 0)

    NotifyProgress(nil, nil, nil, nil, "COMPLETE")

    -- Refresh any open panels.
    if VCA.DungeonOverview and VCA.DungeonOverview.Refresh then
        VCA.DungeonOverview.Refresh()
    end

    _state = nil
end

-- ── Scan step ─────────────────────────────────────────────────────────────────

local ScanStep -- forward declaration

ScanStep = function()
    if not _state or not _state.running then
        return
    end

    -- All specs done → apply results.
    if _state.specIdx > #_state.specs then
        FinalizeScan()
        return
    end

    local specEntry = _state.specs[_state.specIdx]
    local dungeonEntry = _state.dungeons[_state.dungeonIdx]

    -- Set loot spec at the start of each new spec pass (first dungeon, no retries).
    if _state.dungeonIdx == 1 and _state.retries == 0 then
        if not _state.specSwitchDone then
            -- Request the spec change and wait for it to apply before reading tooltips.
            _state.expectingSpecChange = true
            SetLootSpecialization(specEntry.specID)
            _state.specSwitchDone = true
            C_Timer.After(SPEC_CHANGE_DELAY, ScanStep)
            return
        end
        -- Spec change has been applied; clear flag so the next spec gets its own delay.
        _state.expectingSpecChange = false
        _state.specSwitchDone = false
    end

    -- Read the Voidcache tooltip via C_TooltipInfo (pure data call, no frame needed).
    local tooltipData = C_TooltipInfo.GetItemByID(dungeonEntry.voidcacheID, nil, 16, 10)
    local numLines = (tooltipData and tooltipData.lines) and #tooltipData.lines or 0
    local parsed = ParseVoidcacheTooltip(tooltipData, numLines)

    if not parsed then
        -- Phase 1: tooltip not yet ready (< MIN_LINES) — retry in place.
        _state.retries = _state.retries + 1
        if _state.retries <= MAX_RETRIES then
            C_Timer.After(RETRY_DELAY, ScanStep)
            return
        end
        parsed = nil
    else
        -- Phase 2: tooltip has MIN_LINES+ lines — keep reading until two
        -- consecutive reads return the same line count (tooltip is stable).
        if _state.stableLines == nil then
            -- First good read — record baseline and re-read.
            _state.stableLines = numLines
            _state.stableParsed = parsed
            _state.retries = 0
            C_Timer.After(RETRY_DELAY, ScanStep)
            return
        elseif numLines ~= _state.stableLines then
            -- Line count still changing — update baseline and retry.
            _state.stableLines = numLines
            _state.stableParsed = parsed
            _state.retries = _state.retries + 1
            if _state.retries <= MAX_RETRIES then
                C_Timer.After(RETRY_DELAY, ScanStep)
                return
            end
            -- Timed out waiting for stability — use the last good read.
            parsed = _state.stableParsed
        end
        -- else: line count matches previous read — tooltip is stable, proceed.
    end

    _state.results[specEntry.specID] = _state.results[specEntry.specID] or {}
    _state.results[specEntry.specID][dungeonEntry.instanceID] = parsed
    _state.retries = 0
    _state.stableLines = nil
    _state.stableParsed = nil

    -- Advance position.
    _state.dungeonIdx = _state.dungeonIdx + 1
    if _state.dungeonIdx > #_state.dungeons then
        _state.dungeonIdx = 1
        _state.specIdx = _state.specIdx + 1
    end

    LogStepProgress(_state, (_state.specIdx - 1) * #_state.dungeons + (_state.dungeonIdx - 1),
        #_state.specs * #_state.dungeons)

    -- Notify progress (may call into DungeonOverview to update button text).
    NotifyProgress(_state.specIdx, #_state.specs, _state.dungeonIdx, #_state.dungeons, nil)

    C_Timer.After(STEP_DELAY, ScanStep)
end

-- ── Public: start ─────────────────────────────────────────────────────────────

function Scan.Start()
    local canScan, reason = Scan.CanScan()
    if not canScan then
        return false, reason
    end
    if Scan.IsRunning() then
        return false, "RUNNING"
    end
    if not VCA.SeasonData then
        return false, "NO_SEASON_DATA"
    end

    -- Build spec list from the current player's available specializations.
    local numSpecs = GetNumSpecializations()
    local specs = {}
    for i = 1, numSpecs do
        local specID = GetSpecializationInfo(i)
        if specID and specID > 0 then
            specs[#specs + 1] = {
                specID = specID,
                index = i
            }
        end
    end
    if #specs == 0 then
        return false, "NO_SPECS"
    end

    -- Build dungeon list restricted to dungeons that have a known Voidcache ID.
    local instanceIDs = VCA.LootPool.GetSeasonDungeonInstanceIDs()
    local dungeons = {}
    for _, instanceID in ipairs(instanceIDs) do
        local voidcacheID = VCA.DungeonVoidcacheIDs and VCA.DungeonVoidcacheIDs[instanceID]
        if voidcacheID then
            dungeons[#dungeons + 1] = {
                instanceID = instanceID,
                voidcacheID = voidcacheID
            }
        end
    end
    if #dungeons == 0 then
        return false, "NO_DUNGEONS"
    end

    -- Pre-build name caches per spec (requires item cache to be warm).
    Log(string.format(VCA.L["SCAN_STARTING"], #specs, #dungeons))
    local nameCaches = {} -- [specID][instanceID] = { [name]=itemID }
    local missing = {}
    for _, specEntry in ipairs(specs) do
        nameCaches[specEntry.specID] = {}
        for _, dungeonEntry in ipairs(dungeons) do
            nameCaches[specEntry.specID][dungeonEntry.instanceID] =
                BuildDungeonNameCache(dungeonEntry.instanceID, specEntry.specID, missing)
        end
    end

    -- Initialise state.
    _state = {
        running = true,
        specs = specs,
        dungeons = dungeons,
        specIdx = 1,
        dungeonIdx = 1,
        retries = 0,
        stableLines = nil,
        stableParsed = nil,
        specSwitchDone = false,
        expectingSpecChange = false,
        results = {},
        nameCaches = nameCaches,
        missing = missing,
        originalLootSpec = GetLootSpecialization()
    }

    -- Register guards.
    _combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    _combatFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")

    -- Fire initial progress notification, then begin.
    NotifyProgress(1, #specs, 1, #dungeons, nil)
    C_Timer.After(0, ScanStep)

    return true
end

-- ── Combat guard ──────────────────────────────────────────────────────────────

_combatFrame:SetScript("OnEvent", function(self, event)
    if not _state or not _state.running then
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        AbortScan("COMBAT")
    elseif event == "PLAYER_LOOT_SPEC_UPDATED" then
        if not _state.expectingSpecChange then
            Log(VCA.L["SCAN_ABORTED_SPEC"])
            AbortScan("ABORTED")
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- RAID SCAN
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Raid name cache ───────────────────────────────────────────────────────────

local function BuildEncounterNameCache(encounterID, specID, diffID, missingSet)
    local raidData = VCA.SeasonData and VCA.SeasonData.raids[encounterID]
    if not raidData then
        return {}
    end
    local specItems = raidData.bySpec and raidData.bySpec[diffID] and raidData.bySpec[diffID][specID] or {}
    local nameCache = {}
    for _, itemID in ipairs(specItems) do
        local name = C_Item.GetItemInfo(itemID)
        if name and name ~= "" then
            nameCache[name] = itemID
        else
            missingSet[itemID] = true
        end
    end
    return nameCache
end

-- ── Raid abort ────────────────────────────────────────────────────────────────

local _raidCombatFrame = CreateFrame("Frame")

local function AbortRaidScan(reason)
    if not _raidState then
        return
    end
    _raidState.running = false
    _raidCombatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    _raidCombatFrame:UnregisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    if _raidState.originalLootSpec ~= nil then
        SetLootSpecialization(_raidState.originalLootSpec)
    end
    NotifyRaidProgress(nil, nil, nil, nil, reason or "ABORTED")
    _raidState = nil
end

-- ── Raid finalize ─────────────────────────────────────────────────────────────

local function FinalizeRaidScan()
    if not _raidState then
        return
    end
    local results = _raidState.results -- [specID][encounterID] = { [name]=true }
    local nameCaches = _raidState.nameCaches -- [specID][encounterID] = { [name]=itemID }
    local specs = _raidState.specs

    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        AbortRaidScan("NO_DB")
        return
    end

    local diffID = _raidState.difficultyID
    local contentType = VCA.ContentType.RAID

    local stats = {
        pools = 0,
        unreadable = 0,
        mismatch = 0,
        uncached = 0
    }
    for _ in pairs(_raidState.missing) do
        stats.uncached = stats.uncached + 1
    end

    local pending = {}
    for _, specEntry in ipairs(specs) do
        local specID = specEntry.specID
        local specResults = results[specID] or {}
        local specCaches = nameCaches[specID] or {}

        for encounterID, nameCache in pairs(specCaches) do
            local seenItems = specResults[encounterID]
            local status = PoolStatus(seenItems, nameCache)
            stats.pools = stats.pools + 1
            if status == "OK" then
                CollectPool(specID, contentType, encounterID, diffID, nameCache, seenItems, pending)
            elseif status == "UNREADABLE" then
                stats.unreadable = stats.unreadable + 1
            else
                stats.mismatch = stats.mismatch + 1
            end
        end
    end

    ConfirmMarks(pending, "SCAN_SELECT_HEADER", function(selected)
        if #pending > 0 and #selected == 0 then
            Log(VCA.L["SCAN_NOTHING_SELECTED"])
            return
        end
        db.obtained = db.obtained or {}
        db.obtainedBackup = db.obtainedBackup or {}
        db.obtainedBackup.raid = {}
        db.obtainedBackup.raidTime = time()
        db.obtainedBackup.raidDiffID = diffID
        for key, val in pairs(db.obtained) do
            if key:sub(1, 5) == "RAID:" then
                local _, kDiff = key:match("^RAID:%d+:(%d+):")
                if tonumber(kDiff) == diffID then
                    db.obtainedBackup.raid[key] = val
                end
            end
        end
        for _, entry in ipairs(selected) do
            VCA.Data.SetObtained(contentType, entry.sourceID, diffID, entry.specID, entry.itemID, true)
        end
        ReportScan("RAID_SCAN_DONE", #UniqueNames(selected), stats, "SCAN_HINT_RAID")
        if VCA.RaidOverview and VCA.RaidOverview.Refresh then
            VCA.RaidOverview.Refresh()
        end
    end)

    -- 3. Restore original loot spec.
    _raidCombatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    _raidCombatFrame:UnregisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    SetLootSpecialization(_raidState.originalLootSpec or 0)

    NotifyRaidProgress(nil, nil, nil, nil, "COMPLETE")

    if VCA.RaidOverview and VCA.RaidOverview.Refresh then
        VCA.RaidOverview.Refresh()
    end

    _raidState = nil
end

-- ── Raid scan step ────────────────────────────────────────────────────────────

local RaidScanStep

RaidScanStep = function()
    if not _raidState or not _raidState.running then
        return
    end

    if _raidState.specIdx > #_raidState.specs then
        FinalizeRaidScan()
        return
    end

    local specEntry = _raidState.specs[_raidState.specIdx]
    local encounterEntry = _raidState.encounters[_raidState.encounterIdx]

    -- Spec change at the start of each new spec pass.
    if _raidState.encounterIdx == 1 and _raidState.retries == 0 then
        if not _raidState.specSwitchDone then
            _raidState.expectingSpecChange = true
            SetLootSpecialization(specEntry.specID)
            _raidState.specSwitchDone = true
            C_Timer.After(SPEC_CHANGE_DELAY, RaidScanStep)
            return
        end
        _raidState.expectingSpecChange = false
        _raidState.specSwitchDone = false
    end

    local tooltipData = C_TooltipInfo.GetItemByID(encounterEntry.voidcacheID, nil, 6)
    local numLines = (tooltipData and tooltipData.lines) and #tooltipData.lines or 0
    local parsed = ParseVoidcacheTooltip(tooltipData, numLines)

    if not parsed then
        -- Phase 1: tooltip not yet ready (< MIN_LINES) — retry in place.
        _raidState.retries = _raidState.retries + 1
        if _raidState.retries <= MAX_RETRIES then
            C_Timer.After(RETRY_DELAY, RaidScanStep)
            return
        end
        parsed = nil
    else
        -- Phase 2: tooltip has MIN_LINES+ lines — keep reading until two
        -- consecutive reads return the same line count (tooltip is stable).
        if _raidState.stableLines == nil then
            -- First good read — record baseline and re-read.
            _raidState.stableLines = numLines
            _raidState.stableParsed = parsed
            _raidState.retries = 0
            C_Timer.After(RETRY_DELAY, RaidScanStep)
            return
        elseif numLines ~= _raidState.stableLines then
            -- Line count still changing — update baseline and retry.
            _raidState.stableLines = numLines
            _raidState.stableParsed = parsed
            _raidState.retries = _raidState.retries + 1
            if _raidState.retries <= MAX_RETRIES then
                C_Timer.After(RETRY_DELAY, RaidScanStep)
                return
            end
            -- Timed out waiting for stability — use the last good read.
            parsed = _raidState.stableParsed
        end
        -- else: line count matches previous read — tooltip is stable, proceed.
    end

    _raidState.results[specEntry.specID] = _raidState.results[specEntry.specID] or {}
    _raidState.results[specEntry.specID][encounterEntry.encounterID] = parsed
    _raidState.retries = 0
    _raidState.stableLines = nil
    _raidState.stableParsed = nil

    -- Advance.
    _raidState.encounterIdx = _raidState.encounterIdx + 1
    if _raidState.encounterIdx > #_raidState.encounters then
        _raidState.encounterIdx = 1
        _raidState.specIdx = _raidState.specIdx + 1
    end

    LogStepProgress(_raidState, (_raidState.specIdx - 1) * #_raidState.encounters + (_raidState.encounterIdx - 1),
        #_raidState.specs * #_raidState.encounters)

    NotifyRaidProgress(_raidState.specIdx, #_raidState.specs, _raidState.encounterIdx, #_raidState.encounters, nil)
    C_Timer.After(STEP_DELAY, RaidScanStep)
end

-- ── Public: start raid scan ───────────────────────────────────────────────────

function Scan.IsRaidRunning()
    return _raidState ~= nil and _raidState.running == true
end

function Scan.StartRaid(difficultyID)
    difficultyID = difficultyID or VCA.Difficulty.RAID_MYTHIC
    local canScan, reason = Scan.CanScan()
    if not canScan then
        return false, reason
    end
    if Scan.IsRaidRunning() then
        return false, "RUNNING"
    end
    if not VCA.SeasonData then
        return false, "NO_SEASON_DATA"
    end

    local numSpecs = GetNumSpecializations()
    local specs = {}
    for i = 1, numSpecs do
        local specID = GetSpecializationInfo(i)
        if specID and specID > 0 then
            specs[#specs + 1] = {
                specID = specID,
                index = i
            }
        end
    end
    if #specs == 0 then
        return false, "NO_SPECS"
    end

    -- Build encounter list from RaidEncounterCacheIDs.
    local encounters = {}
    if VCA.RaidEncounterCacheIDs then
        for encounterID, voidcacheID in pairs(VCA.RaidEncounterCacheIDs) do
            encounters[#encounters + 1] = {
                encounterID = encounterID,
                voidcacheID = voidcacheID
            }
        end
    end
    if #encounters == 0 then
        return false, "NO_ENCOUNTERS"
    end
    -- Sort for deterministic order.
    table.sort(encounters, function(a, b)
        return a.encounterID < b.encounterID
    end)

    -- Pre-build name caches.
    Log(string.format(VCA.L["RAID_SCAN_STARTING"], #specs, #encounters, difficultyID))
    local nameCaches = {}
    local missing = {}
    for _, specEntry in ipairs(specs) do
        nameCaches[specEntry.specID] = {}
        for _, enc in ipairs(encounters) do
            nameCaches[specEntry.specID][enc.encounterID] =
                BuildEncounterNameCache(enc.encounterID, specEntry.specID, difficultyID, missing)
        end
    end

    _raidState = {
        running = true,
        specs = specs,
        encounters = encounters,
        difficultyID = difficultyID,
        specIdx = 1,
        encounterIdx = 1,
        retries = 0,
        stableLines = nil,
        stableParsed = nil,
        specSwitchDone = false,
        expectingSpecChange = false,
        results = {},
        nameCaches = nameCaches,
        missing = missing,
        originalLootSpec = GetLootSpecialization()
    }

    _raidCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    _raidCombatFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")

    NotifyRaidProgress(1, #specs, 1, #encounters, nil)
    C_Timer.After(0, RaidScanStep)
    return true
end

-- ── Raid combat guard ─────────────────────────────────────────────────────────

_raidCombatFrame:SetScript("OnEvent", function(self, event)
    if not _raidState or not _raidState.running then
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        AbortRaidScan("COMBAT")
    elseif event == "PLAYER_LOOT_SPEC_UPDATED" then
        if not _raidState.expectingSpecChange then
            Log(VCA.L["RAID_SCAN_ABORTED_SPEC"])
            AbortRaidScan("ABORTED")
        end
    end
end)

-- ── Public: restore from backup ───────────────────────────────────────────────

-- Rolls back db.obtained to the snapshot taken just before the last scan
-- finalized.  contentType: "mythicplus", "raid", or nil to restore both.
-- Returns true, restoredCount on success; false, reason on failure.
function Scan.RestoreBackup(contentType)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        return false, "NO_DB"
    end
    local backup = db.obtainedBackup
    if not backup then
        return false, "NO_BACKUP"
    end

    local wantMP = not contentType or contentType == "mythicplus"
    local wantRaid = not contentType or contentType == "raid"

    if wantMP and not backup.mythicPlus then
        wantMP = false
    end
    if wantRaid and not backup.raid then
        wantRaid = false
    end
    if not wantMP and not wantRaid then
        return false, "NO_BACKUP"
    end

    db.obtained = db.obtained or {}
    local restoredCount = 0

    if wantMP then
        for key in pairs(db.obtained) do
            if key:sub(1, 12) == "MYTHIC_PLUS:" then
                db.obtained[key] = nil
            end
        end
        for key, val in pairs(backup.mythicPlus) do
            db.obtained[key] = val
            restoredCount = restoredCount + 1
        end
    end

    if wantRaid then
        local diffID = backup.raidDiffID or VCA.Difficulty.RAID_MYTHIC
        for key in pairs(db.obtained) do
            if key:sub(1, 5) == "RAID:" then
                local _, kDiff = key:match("^RAID:%d+:(%d+):")
                if tonumber(kDiff) == diffID then
                    db.obtained[key] = nil
                end
            end
        end
        for key, val in pairs(backup.raid) do
            db.obtained[key] = val
            restoredCount = restoredCount + 1
        end
    end

    return true, restoredCount
end

-- Returns the timestamps (Unix epoch) of the last M+ and raid backups,
-- or nil for each if that backup does not exist yet.
function Scan.GetBackupInfo()
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.obtainedBackup then
        return nil, nil
    end
    return db.obtainedBackup.mythicPlusTime, db.obtainedBackup.raidTime
end

-- Marks, for the current loot specialization only, every pool item the character has equipped or in
-- its bags. For items bought with Voidcores before the addon saw the roll, when the Voidcache
-- tooltip does not drop them. It cannot tell a Voidcore roll from a normal drop.
function Scan.Owned()
    local owned = {}
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then
            owned[id] = true
        end
    end
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                owned[id] = true
            end
        end
    end

    local specID = VCA.SpecInfo.GetEffectiveLootSpecID()
    local pending = {}
    local function Collect(sourceType, sourceID, diffID, itemList)
        for _, itemID in ipairs(itemList or {}) do
            if owned[itemID] and select(4, C_Item.GetItemInfoInstant(itemID)) ~= "INVTYPE_TRINKET"
                and not VCA.Data.IsObtained(sourceType, sourceID, diffID, specID, itemID) then
                pending[#pending + 1] = {
                    sourceType = sourceType,
                    sourceID = sourceID,
                    diffID = diffID,
                    specID = specID,
                    itemID = itemID,
                    name = C_Item.GetItemNameByID(itemID) or tostring(itemID)
                }
            end
        end
    end

    for instanceID, dungeon in pairs(VCA.SeasonData.dungeons) do
        Collect(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty,
            dungeon.bySpec and dungeon.bySpec[specID])
    end
    for encounterID, raid in pairs(VCA.SeasonData.raids) do
        for diffID, specMap in pairs(raid.bySpec or {}) do
            Collect(VCA.ContentType.RAID, encounterID, diffID, specMap[specID])
        end
    end

    if #pending == 0 then
        Log(string.format(VCA.L["SCAN_OWNED_DONE"], 0))
        return 0
    end
    ConfirmMarks(pending, "SCAN_SELECT_HEADER_OWNED", function(selected)
        if #selected == 0 then
            Log(VCA.L["SCAN_NOTHING_SELECTED"])
            return
        end
        for _, entry in ipairs(selected) do
            VCA.Data.SetObtained(entry.sourceType, entry.sourceID, entry.diffID, entry.specID, entry.itemID, true)
        end
        Log(string.format(VCA.L["SCAN_OWNED_DONE"], #UniqueNames(selected)))
        Log(VCA.L["SCAN_UNDO_HINT"])
    end)
    return #pending
end
