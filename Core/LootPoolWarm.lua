-- VoidcoreAdvisor: LootPoolWarm
-- Cache warmup logic for LootPool.  Loaded after LootPool.lua.
--
-- With static SeasonData the warmup no longer drives any EJ navigation.
-- The process has two phases:
--
--   Phase 1 — Item metadata primer
--     Calls GetItemInfo on every season itemID so the client item cache is
--     populated and C_Item.GetItemSpecInfo returns valid data promptly.
--     Up to PHASE1_BATCH items are primed per tick (0.1 s interval).
--
--   Phase 2 — Class/spec filter cache build
--     Calls the public LootPool.Get*ItemsForClass/Spec functions which write
--     to _cache on success.  If spec metadata is still absent for some items
--     the function does not cache; the pass is retried up to MAX_RETRIES times.
local _, VCA = ...
local LootPool = VCA.LootPool

-- Local alias matching LootPool.lua's CacheKey format (must stay in sync).
local function CacheKey(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...) or 0)
    end
    return table.concat(parts, ":")
end

-- ── Warm state ────────────────────────────────────────────────────────────────

local _warmTicker = nil
local _warmInProgress = false

function LootPool.IsWarmInProgress()
    return _warmInProgress
end

-- Retained for API compatibility; always returns false — EJ is no longer
-- driven during warmup so there is no EJ-pause state.
function LootPool.IsWarmPausedByEJ()
    return false
end

function LootPool.GetWarmStatus()
    return {
        inProgress = _warmInProgress,
        pausedByEJ = false,
        retries = 0
    }
end

-- ── Cache warmup ──────────────────────────────────────────────────────────────

function LootPool.WarmCache()
    if not LootPool.IsSeasonFilterReady() then
        LootPool.BuildSeasonFilter()
    end

    if not LootPool.IsSeasonFilterReady() then
        _warmInProgress = false
        return
    end

    _warmInProgress = true

    -- Cancel any in-progress warm ticker from a previous call.
    if _warmTicker then
        _warmTicker:Cancel()
        _warmTicker = nil
    end

    local _cache = LootPool._cache
    local classID = VCA.SpecInfo.GetPlayerClassID()
    local specs = VCA.SpecInfo.GetPlayerSpecs()
    local dungeonIDs = LootPool.GetSeasonDungeonInstanceIDs()
    local difficultyID = VCA.MythicPlusEJDifficulty

    -- ── Phase 1: collect all season item IDs ──────────────────────────────────

    local allItemIDs = {}
    do
        local seen = {}
        for _, instanceID in ipairs(dungeonIDs) do
            local dungeonData = VCA.SeasonData and VCA.SeasonData.dungeons[instanceID]
            if dungeonData then
                for _, itemID in ipairs(dungeonData.all or {}) do
                    if not seen[itemID] then
                        seen[itemID] = true
                        allItemIDs[#allItemIDs + 1] = itemID
                    end
                end
            end
        end
        for _, encounterData in pairs(VCA.SeasonData and VCA.SeasonData.raids or {}) do
            for key2, val in pairs(encounterData) do
                if type(key2) == "number" and type(val) == "table" then
                    for _, itemID in ipairs(val) do
                        if not seen[itemID] then
                            seen[itemID] = true
                            allItemIDs[#allItemIDs + 1] = itemID
                        end
                    end
                end
            end
        end
    end

    -- ── Phase 2 work queue ────────────────────────────────────────────────────
    -- Class entries come before spec entries for the same source so that
    -- GetInstanceItemsForSpec can delegate to the already-built class cache.

    local workQueue = {}
    for _, instanceID in ipairs(dungeonIDs) do
        workQueue[#workQueue + 1] = {
            kind = "dungeon-class",
            instanceID = instanceID,
            difficultyID = difficultyID,
            classID = classID
        }
        workQueue[#workQueue + 1] = {
            kind = "dungeon-enriched",
            instanceID = instanceID,
            difficultyID = difficultyID,
            classID = classID
        }
        for _, spec in ipairs(specs) do
            workQueue[#workQueue + 1] = {
                kind = "dungeon-spec",
                instanceID = instanceID,
                difficultyID = difficultyID,
                classID = spec.classID,
                specID = spec.specID
            }
        end
    end

    for encounterID, encounterData in pairs(VCA.SeasonData and VCA.SeasonData.raids or {}) do
        if type(encounterID) == "number" then
            for raidDiffID in pairs(VCA.EligibleRaidDifficulties) do
                workQueue[#workQueue + 1] = {
                    kind = "raid-class",
                    encounterID = encounterID,
                    difficultyID = raidDiffID,
                    classID = classID,
                    instanceID = encounterData.instanceID
                }
                for _, spec in ipairs(specs) do
                    workQueue[#workQueue + 1] = {
                        kind = "raid-spec",
                        encounterID = encounterID,
                        difficultyID = raidDiffID,
                        classID = spec.classID,
                        specID = spec.specID,
                        instanceID = encounterData.instanceID
                    }
                end
            end
        end
    end

    -- Gentle on purpose: asking the server for hundreds of items per second at login
    -- made the frame rate dip. ~80 items per second finishes in a few seconds.
    local PHASE1_BATCH = 8 -- items per tick
    local PHASE2_BATCH = 2 -- work entries per tick
    local MAX_RETRIES = 3
    local warmRetries = 0
    local phase = 1
    local phase1Idx = 0
    local phase2Idx = 0

    local function IsCached(entry)
        if entry.kind == "dungeon-class" then
            return _cache[CacheKey("iic", entry.instanceID, entry.difficultyID, entry.classID)] ~= nil
        elseif entry.kind == "dungeon-enriched" then
            return _cache[CacheKey("ii", entry.instanceID, entry.difficultyID, entry.classID, 0)] ~= nil
        elseif entry.kind == "dungeon-spec" then
            return _cache[CacheKey("iis", entry.instanceID, entry.difficultyID, entry.classID, entry.specID)] ~= nil
        elseif entry.kind == "raid-class" then
            return _cache[CacheKey("eic", entry.encounterID, entry.difficultyID, entry.classID)] ~= nil
        elseif entry.kind == "raid-spec" then
            return _cache[CacheKey("eis", entry.encounterID, entry.difficultyID, entry.classID, entry.specID)] ~= nil
        end
        return true
    end

    local function ProcessEntry(entry)
        if entry.kind == "dungeon-class" then
            LootPool.GetInstanceItemsForClass(entry.instanceID, entry.difficultyID, entry.classID)
        elseif entry.kind == "dungeon-enriched" then
            LootPool.GetInstanceItems(entry.instanceID, entry.difficultyID, entry.classID)
        elseif entry.kind == "dungeon-spec" then
            LootPool.GetInstanceItemsForSpec(entry.instanceID, entry.difficultyID, entry.classID, entry.specID)
        elseif entry.kind == "raid-class" then
            LootPool.GetEncounterItemsForClass(entry.encounterID, entry.difficultyID, entry.classID, entry.instanceID)
        elseif entry.kind == "raid-spec" then
            LootPool.GetEncounterItemsForSpec(entry.encounterID, entry.difficultyID, entry.classID, entry.specID,
                entry.instanceID)
        end
    end

    local function Finish(success)
        if _warmTicker then
            _warmTicker:Cancel();
            _warmTicker = nil
        end
        _warmInProgress = false
        -- Poke EJHook in case the player opened the journal during warmup.
        if LootPool.IsSeasonFilterReady() and VCA.EJHook and VCA.EJHook.TryReevaluate then
            VCA.EJHook.TryReevaluate()
        end
        -- Replay any saved bonus roll log entries that detection may have missed.
        if success and VCA.Detection and VCA.Detection.ReplayBonusRollLog then
            C_Timer.After(0, function()
                VCA.Detection.ReplayBonusRollLog(false)
            end)
        end
    end

    _warmTicker = C_Timer.NewTicker(0.1, function()
        if phase == 1 then
            -- Prime item metadata in batches.
            for _ = 1, PHASE1_BATCH do
                phase1Idx = phase1Idx + 1
                if phase1Idx > #allItemIDs then
                    phase = 2
                    break
                end
                C_Item.GetItemInfo(allItemIDs[phase1Idx])
            end

        elseif phase == 2 then
            -- Build class/spec caches in batches.
            for _ = 1, PHASE2_BATCH do
                phase2Idx = phase2Idx + 1
                if phase2Idx > #workQueue then
                    -- Full pass complete — check if everything was cached.
                    local allCached = true
                    for _, entry in ipairs(workQueue) do
                        if not IsCached(entry) then
                            allCached = false
                            break
                        end
                    end

                    if allCached then
                        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["WARM_FINISHED"])
                        Finish(true)
                    elseif warmRetries < MAX_RETRIES then
                        warmRetries = warmRetries + 1
                        phase2Idx = 0 -- retry phase 2
                    else
                        Finish(false)
                    end
                    return
                end

                local entry = workQueue[phase2Idx]
                if not IsCached(entry) then
                    ProcessEntry(entry)
                end
            end
        end
    end)
end
