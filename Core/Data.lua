-- VoidcoreAdvisor: Data
-- Per-character persistence layer.  Manages which items the character has
-- already received via a Nebulous Voidcore, keyed by source + difficulty.
--
-- Storage key format: "<ContentType>:<sourceID>:<difficultyID>:<itemID>"
-- Example (Heroic raid boss 2532, item 208430):
--   "RAID:2532:15:208430"
-- Example (M+ instanceID 67, item 199388):
--   "MYTHIC_PLUS:67:23:199388"
local _, VCA = ...

VCA.Data = {}
local Data = VCA.Data

-- ── Key construction ──────────────────────────────────────────────────────────
-- Key format: "<ContentType>:<sourceID>:<difficultyID>:<specID>:<itemID>"
-- specID identifies the loot specialization active when the item was obtained.
-- A specID of 0 is used for manual panel overrides (no specific spec context).

function Data.BuildKey(sourceType, sourceID, difficultyID, specID, itemID)
    return sourceType .. ":" .. sourceID .. ":" .. difficultyID .. ":" .. (specID or 0) .. ":" .. itemID
end

-- ── Obtained status ───────────────────────────────────────────────────────────

-- Returns true if this item has been marked as obtained in ANY tier
-- (tier-less, high-tier :H, or low-tier :L).
function Data.IsObtained(sourceType, sourceID, difficultyID, specID, itemID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.obtained then
        return false
    end
    local base = Data.BuildKey(sourceType, sourceID, difficultyID, specID, itemID)
    return db.obtained[base] == true or db.obtained[base .. ":H"] == true or db.obtained[base .. ":L"] == true
end

-- Marks or unmarks an item as obtained for the given specialization.
-- obtained: boolean (true = mark tier-less, false = unmark ALL tier variants)
function Data.SetObtained(sourceType, sourceID, difficultyID, specID, itemID, obtained)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        return
    end
    db.obtained = db.obtained or {}
    local key = Data.BuildKey(sourceType, sourceID, difficultyID, specID, itemID)
    if obtained then
        db.obtained[key] = true
    else
        -- Unmark clears all tier variants so no stale state survives.
        db.obtained[key] = nil
        db.obtained[key .. ":H"] = nil
        db.obtained[key .. ":L"] = nil
    end
end

-- Marks or unmarks an item for a specific key tier.
-- isHighTier = true  → ":H" suffix (≥10)
-- isHighTier = false → ":L" suffix (<10)
-- isHighTier = nil   → tier-less key (unknown tier / non-M+); same as SetObtained(true)
function Data.SetObtainedForKeyTier(sourceType, sourceID, difficultyID, specID, itemID, isHighTier, obtained)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        return
    end
    db.obtained = db.obtained or {}
    local base = Data.BuildKey(sourceType, sourceID, difficultyID, specID, itemID)
    local key = (isHighTier ~= nil) and (base .. (isHighTier and ":H" or ":L")) or base
    if obtained then
        db.obtained[key] = true
    else
        db.obtained[key] = nil
    end
end

-- Toggles the obtained state for the given spec and returns the new state (true/false).
function Data.ToggleObtained(sourceType, sourceID, difficultyID, specID, itemID)
    local current = Data.IsObtained(sourceType, sourceID, difficultyID, specID, itemID)
    Data.SetObtained(sourceType, sourceID, difficultyID, specID, itemID, not current)
    return not current
end

-- Marks itemID as obtained for every loot-spec that can receive it from sourceID.
-- Dungeons: SeasonData.dungeons[sourceID].bySpec is flat { [specID] = {itemIDs} }.
-- Raids:    SeasonData.raids[sourceID].bySpec is nested { [difficultyID] = { [specID] = {itemIDs} } }.
function Data.PropagateObtainedToAllSpecs(sourceType, sourceID, difficultyID, itemID, isHighTier)
    -- Dungeon path (flat bySpec).
    local dungeonData = VCA.SeasonData and VCA.SeasonData.dungeons[sourceID]
    if dungeonData and dungeonData.bySpec then
        for specID, itemList in pairs(dungeonData.bySpec) do
            for _, id in ipairs(itemList) do
                if id == itemID then
                    Data.SetObtainedForKeyTier(sourceType, sourceID, difficultyID, specID, itemID, isHighTier, true)
                    break
                end
            end
        end
        return
    end
    -- Raid path (bySpec nested by difficultyID).
    local raidData = VCA.SeasonData and VCA.SeasonData.raids and VCA.SeasonData.raids[sourceID]
    if not raidData or not raidData.bySpec then
        return
    end
    local specMap = raidData.bySpec[difficultyID]
    if not specMap then
        return
    end
    for specID, itemList in pairs(specMap) do
        for _, id in ipairs(itemList) do
            if id == itemID then
                Data.SetObtainedForKeyTier(sourceType, sourceID, difficultyID, specID, itemID, isHighTier, true)
                break
            end
        end
    end
end

-- ── Pool filtering ────────────────────────────────────────────────────────────

-- Given a flat array of item tables (each must have an `itemID` field),
-- returns a new array containing only items NOT yet obtained for the given spec.
function Data.GetRemainingItems(pool, sourceType, sourceID, difficultyID, specID)
    local remaining = {}
    for _, item in ipairs(pool) do
        if not Data.IsObtained(sourceType, sourceID, difficultyID, specID, item.itemID) then
            remaining[#remaining + 1] = item
        end
    end
    return remaining
end

-- ── Selected items persistence ─────────────────────────────────────────────────

local function SelectionKey(sourceType, sourceID, difficultyID)
    return sourceType .. ":" .. sourceID .. ":" .. difficultyID
end

-- Returns a set { [itemID]=true } of selected items for the given source context.
function Data.GetSelectedItems(sourceType, sourceID, difficultyID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.selectedItems then
        return {}
    end
    local key = SelectionKey(sourceType, sourceID, difficultyID)
    local raw = db.selectedItems[key]
    if type(raw) ~= "table" then
        return {}
    end

    -- Normalize to the canonical set format: { [itemID] = true }.
    -- This also migrates legacy array/string-keyed data and drops invalid entries.
    local normalized = {}
    for k, v in pairs(raw) do
        if v == true then
            local id = tonumber(k)
            if id and id > 0 then
                normalized[id] = true
            end
        else
            local id = tonumber(v)
            if id and id > 0 then
                normalized[id] = true
            end
        end
    end

    if not next(normalized) then
        db.selectedItems[key] = nil
        return {}
    end

    db.selectedItems[key] = normalized
    return normalized
end

-- Saves a set { [itemID]=true } (or nil/empty to clear) for the given source.
function Data.SaveSelectedItems(sourceType, sourceID, difficultyID, selectionSet)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        return
    end
    db.selectedItems = db.selectedItems or {}
    local key = SelectionKey(sourceType, sourceID, difficultyID)
    if not selectionSet or not next(selectionSet) then
        db.selectedItems[key] = nil
    else
        -- Store a copy so the caller's table can be wiped without affecting the DB.
        local copy = {}
        for id in pairs(selectionSet) do
            copy[id] = true
        end
        db.selectedItems[key] = copy
    end
end

-- Removes a single item from the saved selection for the given source.
function Data.RemoveSelectedItem(sourceType, sourceID, difficultyID, itemID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.selectedItems then
        return
    end
    local key = SelectionKey(sourceType, sourceID, difficultyID)
    local set = db.selectedItems[key]
    if not set then
        return
    end
    set[itemID] = nil
    if not next(set) then
        db.selectedItems[key] = nil
    end
end

-- ── Bulk operations ───────────────────────────────────────────────────────────

-- Clears all obtained data for one source + difficulty combination.
-- If specID is provided, only clears data for that specialization.
function Data.ClearSource(sourceType, sourceID, difficultyID, specID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.obtained then
        return
    end
    local prefix = sourceType .. ":" .. sourceID .. ":" .. difficultyID .. ":"
    local specPrefix = specID and (tostring(specID) .. ":") or nil
    for key in pairs(db.obtained) do
        if key:sub(1, #prefix) == prefix then
            local rest = key:sub(#prefix + 1)
            if not specPrefix or rest:sub(1, #specPrefix) == specPrefix then
                db.obtained[key] = nil
            end
        end
    end
end

-- The keys ClearSourceForKeyTier would remove, as { [key] = true }, so a reset can be undone.
function Data.SnapshotSource(sourceType, sourceID, difficultyID, specID, isHighTier)
    local db = _G[VCA.CHAR_DB_NAME]
    local keys = {}
    if not db or not db.obtained then
        return keys
    end
    local prefix = sourceType .. ":" .. sourceID .. ":" .. difficultyID .. ":"
    local specPrefix = specID and (tostring(specID) .. ":") or nil
    local suffix = isHighTier ~= nil and (isHighTier and ":H" or ":L") or nil
    for key in pairs(db.obtained) do
        if key:sub(1, #prefix) == prefix then
            local rest = key:sub(#prefix + 1)
            if (not specPrefix or rest:sub(1, #specPrefix) == specPrefix) and (not suffix or key:sub(-2) == suffix) then
                keys[key] = true
            end
        end
    end
    return keys
end

-- Marks every key of a snapshot as obtained again.
function Data.RestoreKeys(keys)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        return
    end
    db.obtained = db.obtained or {}
    for key in pairs(keys) do
        db.obtained[key] = true
    end
end

-- Older versions marked a roll for every specialization that could get the item, of every class. On a
-- character, a mark for a specialization its own class does not have can never be real, so those are
-- removed (kept in foreignSpecBackup). It only looks at this character's own data and class: another
-- character of the same class has its own marks and is never touched from here.
-- ownSpecs = { [specID] = true }. Returns how many marks were removed.
function Data.PruneForeignSpecMarks(ownSpecs)
    local db = _G[VCA.CHAR_DB_NAME]
    if not (db and db.obtained and ownSpecs and next(ownSpecs)) then
        return 0
    end
    local foreign = {}
    for key in pairs(db.obtained) do
        local specID = tonumber(key:match("^[^:]+:[^:]+:[^:]+:(%d+):%d+"))
        if specID and specID ~= 0 and not ownSpecs[specID] then
            foreign[#foreign + 1] = key
        end
    end
    if #foreign == 0 then
        return 0
    end
    db.foreignSpecBackup = db.foreignSpecBackup or {}
    for _, key in ipairs(foreign) do
        db.foreignSpecBackup[key] = true
        db.obtained[key] = nil
    end
    return #foreign
end

-- Returns the total number of items marked as obtained across all sources.
function Data.GetTotalObtainedCount()
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.obtained then
        return 0
    end
    local count = 0
    for _ in pairs(db.obtained) do
        count = count + 1
    end
    return count
end

-- ── Migration helpers ─────────────────────────────────────────────────────────

-- Returns true if this item has a specID=0 entry (migrated from the pre-spec
-- schema where obtained keys had no specID segment).
function Data.IsObtainedMigrated(sourceType, sourceID, difficultyID, itemID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.obtained then
        return false
    end
    return db.obtained[Data.BuildKey(sourceType, sourceID, difficultyID, 0, itemID)] == true
end

-- One-time migration: rewrites 4-part keys ("TYPE:srcID:diffID:itemID") to
-- 5-part keys with specID=0 ("TYPE:srcID:diffID:0:itemID").
-- Called from Init.lua MigrateDB during the v1→v2 schema upgrade.
function Data.MigrateV1Keys(db)
    if not db.obtained then
        return
    end
    local toAdd = {}
    local toRemove = {}
    for key in pairs(db.obtained) do
        -- Count colons: 4-part key has 3, 5-part has 4.
        local colons = 0
        for _ in key:gmatch(":") do
            colons = colons + 1
        end
        if colons == 3 then
            local t, src, diff, item = key:match("^([^:]+):([^:]+):([^:]+):([^:]+)$")
            if t and src and diff and item then
                toAdd[t .. ":" .. src .. ":" .. diff .. ":0:" .. item] = true
                toRemove[key] = true
            end
        end
    end
    for k in pairs(toRemove) do
        db.obtained[k] = nil
    end
    for k in pairs(toAdd) do
        db.obtained[k] = true
    end
end

-- ── Bonus roll event log ──────────────────────────────────────────────────────
-- Stores raw BONUS_ROLL_RESULT payloads so the player can manually verify
-- item detection after the fact.  Capped at the last 200 rolls.

local BONUS_ROLL_LOG_MAX = 200

-- Records one bonus roll entry.  source may be nil if it could not be resolved.
-- entry = { timestamp, itemID, itemLink, specID, sourceType, sourceID, difficultyID }
function Data.LogBonusRoll(itemID, itemLink, specID, source)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        return
    end
    db.bonusRollLog = db.bonusRollLog or {}
    local log = db.bonusRollLog
    -- Was it one of the items you had chosen? (the choice is removed once it drops)
    local wanted = false
    if source and source.sourceType and source.sourceID and source.difficultyID then
        wanted = Data.GetSelectedItems(source.sourceType, source.sourceID, source.difficultyID)[itemID] == true
    end
    -- The chance this roll had of giving one of the chosen items, from the pool as it was
    -- before the item left it (used by /void history to compare luck with the odds).
    local odds
    pcall(function()
        local classID = VCA.SpecInfo and VCA.SpecInfo.GetPlayerClassID and VCA.SpecInfo.GetPlayerClassID()
        if not (source and source.sourceType and classID and specID) then
            return
        end
        local tier = source.keyLevel and (source.keyLevel >= 10) or nil
        local selected = Data.GetSelectedItems(source.sourceType, source.sourceID, source.difficultyID)
        local total, want = 0, 0
        for _, id in ipairs(VCA.LootPool.GetItemsForSpec(source.sourceType, source.sourceID, source.difficultyID,
            classID, specID)) do
            if not Data.IsObtainedForKeyTier(source.sourceType, source.sourceID, source.difficultyID, specID, id, tier) then
                total = total + 1
                if selected[id] then
                    want = want + 1
                end
            end
        end
        if total > 0 then
            odds = want / total
        end
    end)
    log[#log + 1] = {
        timestamp = time(),
        itemID = itemID,
        itemLink = itemLink,
        itemLevel = VCA.Detection and VCA.Detection.GetItemLevel and VCA.Detection.GetItemLevel(itemLink) or nil,
        wanted = wanted,
        odds = odds,
        specID = specID,
        sourceType = source and source.sourceType or nil,
        sourceID = source and source.sourceID or nil,
        difficultyID = source and source.difficultyID or nil,
        keyLevel = source and source.keyLevel or nil,
        raidInstanceID = source and source.raidInstanceID or nil
    }
    -- Trim to the last N entries.
    while #log > BONUS_ROLL_LOG_MAX do
        table.remove(log, 1)
    end
end

-- Records a manually-checked obtained entry in the roll log so /void rolls
-- reflects manual panel selections.  isHighTier mirrors the tier context of
-- the checkbox that was ticked (nil for raids / non-tiered sources).
function Data.LogManualObtained(itemID, specID, source, isHighTier, itemLink)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        return
    end
    db.bonusRollLog = db.bonusRollLog or {}
    local log = db.bonusRollLog
    log[#log + 1] = {
        timestamp = time(),
        itemID = itemID,
        itemLink = (itemLink ~= nil and itemLink ~= "") and itemLink or nil,
        specID = specID,
        sourceType = source and source.sourceType or nil,
        sourceID = source and source.sourceID or nil,
        difficultyID = source and source.difficultyID or nil,
        keyLevel = nil,
        manual = true,
        isHighTier = isHighTier
    }
    while #log > BONUS_ROLL_LOG_MAX do
        table.remove(log, 1)
    end
end

-- Removes all manual log entries that match the given item + source + spec +
-- tier.  Called when a player unchecks an item in the spec picker.
function Data.RemoveManualLogEntries(itemID, sourceType, sourceID, difficultyID, specID, isHighTier)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.bonusRollLog then
        return
    end
    local log = db.bonusRollLog
    for i = #log, 1, -1 do
        local e = log[i]
        if e.manual and e.itemID == itemID and e.sourceType == sourceType and e.sourceID == sourceID and e.difficultyID ==
            difficultyID and e.specID == specID and e.isHighTier == isHighTier then
            table.remove(log, i)
        end
    end
end

-- Removes all manual log entries for an item + source, regardless of spec or tier.
-- Used when a manual mark is cleared entirely (no spec/tier to filter on).
function Data.RemoveAllManualLogEntriesForItem(itemID, sourceType, sourceID, difficultyID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.bonusRollLog then
        return
    end
    local log = db.bonusRollLog
    for i = #log, 1, -1 do
        local e = log[i]
        if e.manual and e.itemID == itemID and e.sourceType == sourceType and e.sourceID == sourceID and e.difficultyID ==
            difficultyID then
            table.remove(log, i)
        end
    end
end

-- Flags the roll entries of an item that the player cleared by hand, so the replay at login
-- does not mark it again.  A raid roll counts when it belongs to the same raid and
-- difficulty (or its difficulty is unknown); raidInstanceID is the raid's journal id.
-- The entries stay in the log: /void rolls and the history still show the roll.
function Data.NeutralizeRollEntriesForItem(itemID, sourceType, sourceID, difficultyID, raidInstanceID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.bonusRollLog then
        return
    end
    for _, e in ipairs(db.bonusRollLog) do
        if not e.manual and e.itemID == itemID then
            local diff = e.difficultyID
            if VCA.Detection and VCA.Detection.ResolveEntryDifficulty then
                diff = VCA.Detection.ResolveEntryDifficulty(e) or diff
            end
            local sameSource = e.sourceType == sourceType and e.sourceID == sourceID and diff == difficultyID
            local sameRaid = false
            if raidInstanceID and e.raidInstanceID == raidInstanceID then
                sameRaid = diff == nil or diff == difficultyID
            end
            if sameSource or sameRaid then
                e.unmarked = true
            end
        end
    end
end

-- Returns the saved bonus roll log (array, oldest first), or an empty table.
function Data.GetBonusRollLog()
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.bonusRollLog then
        return {}
    end
    return db.bonusRollLog
end

-- Returns true if this item is considered obtained for the given M+ key tier.
-- highTier = true  → "at or above key 10"  (checks :H suffix key)
-- highTier = false → "below key 10"         (checks :L suffix key)
-- Tier-less obtained entries (unknown key level) count as obtained for BOTH tiers.
-- When highTier is nil, behaves identically to IsObtained (union of all variants).
function Data.IsObtainedForKeyTier(sourceType, sourceID, difficultyID, specID, itemID, highTier)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.obtained then
        return false
    end
    local base = Data.BuildKey(sourceType, sourceID, difficultyID, specID, itemID)
    if highTier == nil then
        return db.obtained[base] == true or db.obtained[base .. ":H"] == true or db.obtained[base .. ":L"] == true
    end
    -- Check tier-specific key first (new storage format).
    local tierKey = base .. (highTier and ":H" or ":L")
    if db.obtained[tierKey] then
        return true
    end
    -- Fall back to tier-less key (obtained at unknown key level counts for both tiers).
    return db.obtained[base] == true
end

-- Clears obtained data for one source + difficulty + tier combination.
-- isHighTier = nil  → full clear (same as ClearSource; used for non-M+ resets)
-- isHighTier = true → clears only :H keys (≥10 cycle reset, leaves :L untouched)
-- isHighTier = false → clears only :L keys (<10 cycle reset, leaves :H untouched)
function Data.ClearSourceForKeyTier(sourceType, sourceID, difficultyID, specID, isHighTier)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.obtained then
        return
    end
    if isHighTier == nil then
        Data.ClearSource(sourceType, sourceID, difficultyID, specID)
        return
    end
    local suffix = isHighTier and ":H" or ":L"
    local prefix = sourceType .. ":" .. sourceID .. ":" .. difficultyID .. ":"
    local specPrefix = specID and (tostring(specID) .. ":") or nil
    for key in pairs(db.obtained) do
        if key:sub(1, #prefix) == prefix and key:sub(-2) == suffix then
            local rest = key:sub(#prefix + 1)
            if not specPrefix or rest:sub(1, #specPrefix) == specPrefix then
                db.obtained[key] = nil
            end
        end
    end
end

-- Stores a manually-entered key level for a specific item/source/tier combination.
-- isHighTier: true = ≥10 tier (:H), false = <10 tier (:L), nil = tier-less (non-M+ / unknown).
-- keyLevel: positive integer to record; nil or 0 clears the entry.
function Data.SetManualKeyLevel(sourceType, sourceID, difficultyID, itemID, isHighTier, keyLevel)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db then
        return
    end
    db.manualKeyLevels = db.manualKeyLevels or {}
    local base = sourceType .. ":" .. tostring(sourceID) .. ":" .. difficultyID .. ":" .. itemID
    local key = (isHighTier ~= nil) and (base .. (isHighTier and ":H" or ":L")) or base
    if type(keyLevel) == "number" and keyLevel > 0 then
        db.manualKeyLevels[key] = keyLevel
    else
        db.manualKeyLevels[key] = nil
    end
end

-- Returns the manually-stored key level for an item for a specific tier.
-- isHighTier: true = :H, false = :L, nil = tier-less / legacy key.
-- Returns: number (known level) or nil (no entry for this tier).
function Data.GetManualKeyLevel(sourceType, sourceID, difficultyID, itemID, isHighTier)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.manualKeyLevels then
        return nil
    end
    local base = sourceType .. ":" .. tostring(sourceID) .. ":" .. difficultyID .. ":" .. itemID
    local key = (isHighTier ~= nil) and (base .. (isHighTier and ":H" or ":L")) or base
    local val = db.manualKeyLevels[key]
    return type(val) == "number" and val > 0 and val or nil
end

-- Looks up the keyLevel from the bonus roll log for the given obtained item.
-- Searches newest-first so the most recent detection wins.
-- Returns the keyLevel number, or nil if not found (manually marked or log expired).
function Data.GetKeyLevelFromLog(sourceType, sourceID, difficultyID, specID, itemID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.bonusRollLog then
        return nil
    end
    for i = #db.bonusRollLog, 1, -1 do
        local entry = db.bonusRollLog[i]
        if entry.itemID == itemID and (specID == nil or entry.specID == specID) and entry.sourceType == sourceType and
            entry.sourceID == sourceID and entry.difficultyID == difficultyID then
            return entry.keyLevel -- may itself be nil if not recorded
        end
    end
    return nil
end

-- Returns the effective key level for an item, checking the tier-less manual
-- override first, then falling back to the bonus roll log.
-- Returns nil when the level is unknown.
function Data.GetEffectiveKeyLevel(sourceType, sourceID, difficultyID, specID, itemID)
    local manual = Data.GetManualKeyLevel(sourceType, sourceID, difficultyID, itemID, nil)
    if manual ~= nil then
        return manual
    end
    return Data.GetKeyLevelFromLog(sourceType, sourceID, difficultyID, specID, itemID)
end

-- Returns a sorted array of all unique key levels this item was obtained at for
-- a spec, combining manual entries (all tiers) with all matching log entries.
-- Manual and log data are MERGED — neither blocks the other.
-- Returns {} when no key level information is available.
function Data.GetAllKeyLevelsForSpec(sourceType, sourceID, difficultyID, specID, itemID)
    local db = _G[VCA.CHAR_DB_NAME]
    local seen = {}
    local levels = {}

    -- Collect manual key levels across all tier variants (:H, :L, tier-less legacy).
    if db and db.manualKeyLevels then
        local base = sourceType .. ":" .. tostring(sourceID) .. ":" .. difficultyID .. ":" .. itemID
        for _, key in ipairs({base, base .. ":H", base .. ":L"}) do
            local val = db.manualKeyLevels[key]
            if type(val) == "number" and val > 0 and not seen[val] then
                seen[val] = true
                levels[#levels + 1] = val
            end
        end
    end

    -- Also scan the bonus roll log for this spec (adds levels not already in manual).
    if db and db.bonusRollLog then
        for _, entry in ipairs(db.bonusRollLog) do
            if entry.itemID == itemID and entry.specID == specID and entry.sourceType == sourceType and entry.sourceID ==
                sourceID and entry.difficultyID == difficultyID then
                local kl = entry.keyLevel
                if type(kl) == "number" and kl > 0 and not seen[kl] then
                    seen[kl] = true
                    levels[#levels + 1] = kl
                end
            end
        end
    end

    table.sort(levels)
    return levels
end

-- Returns true if the bare (tier-less) key is set for this spec+item.
-- A bare key means the item was obtained at an unknown key level (pre-tier data,
-- Mythic 0 detection, or any detection where keyLevel was not available).
-- Bare keys count as obtained for BOTH tiers via IsObtainedForKeyTier's fallback.
function Data.IsObtainedBareKey(sourceType, sourceID, difficultyID, specID, itemID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.obtained then
        return false
    end
    local base = Data.BuildKey(sourceType, sourceID, difficultyID, specID, itemID)
    return db.obtained[base] == true
end

-- Returns true if a tier-specific key (:H or :L) exists for this spec+item,
-- WITHOUT the bare-key fallback.  Used to distinguish "manually entered via
-- spec picker" (tiered key, no log level) from "unknown tier" (bare key only).
-- isHighTier: true = check :H, false = check :L, nil = always returns false.
function Data.IsObtainedTiered(sourceType, sourceID, difficultyID, specID, itemID, isHighTier)
    if isHighTier == nil then
        return false
    end
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not db.obtained then
        return false
    end
    local base = Data.BuildKey(sourceType, sourceID, difficultyID, specID, itemID)
    return db.obtained[base .. (isHighTier and ":H" or ":L")] == true
end
