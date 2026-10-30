-- VoidcoreAdvisor: Detection
-- BONUS_ROLL_RESULT-only detection for Nebulous Voidcore rewards.
local _, VCA = ...

VCA.Detection = {}
local Detection = VCA.Detection

-- -- Internal state -----------------------------------------------------------

local sourceOverride = nil -- optional UI-selected source context
local onDetectedCallback = nil -- function(itemID, source) | nil
local pendingRewards = {}
-- True only while a roll that just happened is being processed (not while old rolls are replayed),
-- so a cycle reset is remembered and announced once, when it really happens.
local liveRoll = false
-- Key level captured at CHALLENGE_MODE_START / CHALLENGE_MODE_COMPLETED, before
-- GetActiveKeystoneInfo() goes stale after the keystone is consumed.
-- Also persisted to SavedVariables so a /reload inside or after a run survives.
local cachedKeyLevel = nil
-- Raid instance context captured at PLAYER_ENTERING_WORLD when inside a current-season
-- eligible raid, so BONUS_ROLL_RESULT can attribute the item without a live GetInstanceInfo().
local cachedRaidInstanceID = nil
local cachedRaidDifficultyID = nil
-- Keystone run log: full source snapshot from CHALLENGE_MODE_START, status updated at
-- CHALLENGE_MODE_COMPLETED / CHALLENGE_MODE_RESET.  Survives zone exit so BONUS_ROLL_RESULT
-- that fires in the open world after leaving the dungeon can still find the right source.
-- Overwritten when a new key starts.  Persisted to SavedVariables to survive /reload.
-- status: "running" | "completed" | "abandoned"
local lastKeystoneRun = nil

local function PersistKeyLevel(level)
    cachedKeyLevel = level
    local db = _G[VCA.CHAR_DB_NAME]
    if db then
        db.cachedKeyLevel = level
    end
end

local function PersistKeystoneRun(run)
    lastKeystoneRun = run
    local db = _G[VCA.CHAR_DB_NAME]
    if db then
        db.lastKeystoneRun = run
    end
end

local function UpdateKeystoneRunStatus(status)
    if not lastKeystoneRun then
        return
    end
    lastKeystoneRun.status = status
    local db = _G[VCA.CHAR_DB_NAME]
    if db and db.lastKeystoneRun then
        db.lastKeystoneRun.status = status
    end
end

local function ClearPersistedKeyLevel()
    cachedKeyLevel = nil
    local db = _G[VCA.CHAR_DB_NAME]
    if db then
        db.cachedKeyLevel = nil
    end
end

local function PersistRaidContext(instanceID, difficultyID)
    cachedRaidInstanceID = instanceID
    cachedRaidDifficultyID = difficultyID
    local db = _G[VCA.CHAR_DB_NAME]
    if db then
        db.cachedRaidInstanceID = instanceID
        db.cachedRaidDifficultyID = difficultyID
    end
end

local function ClearPersistedRaidContext()
    cachedRaidInstanceID = nil
    cachedRaidDifficultyID = nil
    local db = _G[VCA.CHAR_DB_NAME]
    if db then
        db.cachedRaidInstanceID = nil
        db.cachedRaidDifficultyID = nil
    end
end

local function CreateSource(sourceType, sourceID, difficultyID, keyLevel)
    return {
        sourceType = sourceType,
        sourceID = sourceID,
        difficultyID = difficultyID,
        keyLevel = keyLevel
    }
end

local function ResolveCurrentMythicPlusSource()
    local instanceName, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType ~= "party" then
        return nil
    end

    -- 23 = Mythic 0, 8 = Mythic Keystone.
    if difficultyID ~= 23 and difficultyID ~= 8 then
        return nil
    end

    -- Primary: locale-independent InstanceID lookup (requires SeasonData with mapID).
    local sourceID = instanceID and VCA.LootPool and VCA.LootPool.GetSeasonDungeonByInstanceID and
                         VCA.LootPool.GetSeasonDungeonByInstanceID(instanceID)

    -- Fallback: localized name lookup for SeasonData built before mapID support.
    if not sourceID then
        sourceID = VCA.LootPool and VCA.LootPool.GetSeasonDungeonByName and
                       VCA.LootPool.GetSeasonDungeonByName(instanceName)
    end

    if not sourceID then
        return nil
    end

    local keyLevel
    if C_ChallengeMode then
        local level = C_ChallengeMode.GetActiveKeystoneInfo()
        if level and level > 0 then
            keyLevel = level
        end
        -- Fallback: level snapshotted at CHALLENGE_MODE_START / CHALLENGE_MODE_COMPLETED
        -- (and persisted to SavedVariables) before the keystone is consumed.
        if not keyLevel and cachedKeyLevel then
            keyLevel = cachedKeyLevel
        end
    end

    return CreateSource(VCA.ContentType.MYTHIC_PLUS, sourceID, VCA.MythicPlusEJDifficulty, keyLevel)
end

-- Resolves the current source when the player is inside a current-season raid.
-- Prefers the cached context snapshotted at zone entry; falls back to a live
-- GetInstanceInfo() call for safety (e.g. if the cache was not yet populated).
-- Returns a partial source with raidInstanceID (EJ) + difficultyID but no sourceID
-- (encounterID is unknown at bonus-roll time).  Detection uses this to scan all
-- encounters in the raid for the item rather than a single encounter lookup.
local function ResolveCurrentRaidSource()
    -- Use the pre-snapshotted context when available.
    if cachedRaidInstanceID and cachedRaidDifficultyID then
        return {
            sourceType = nil,
            sourceID = nil,
            difficultyID = cachedRaidDifficultyID,
            raidInstanceID = cachedRaidInstanceID,
            keyLevel = nil
        }
    end
    -- Fallback: live resolution using WoW mapID → EJ instanceID mapping.
    local instanceName, instanceType, difficultyID, _, _, _, _, mapID = GetInstanceInfo()
    if instanceType ~= "raid" then
        return nil
    end
    if not VCA.EligibleRaidDifficulties or not VCA.EligibleRaidDifficulties[difficultyID] then
        return nil
    end
    if not VCA.LootPool then
        return nil
    end
    local ejInstanceID = (VCA.LootPool.GetSeasonRaidByMapID and VCA.LootPool.GetSeasonRaidByMapID(mapID)) or
                             (VCA.LootPool.GetSeasonRaidByName and VCA.LootPool.GetSeasonRaidByName(instanceName))
    if not ejInstanceID then
        return nil
    end
    return {
        sourceType = nil,
        sourceID = nil,
        difficultyID = difficultyID,
        raidInstanceID = ejInstanceID,
        keyLevel = nil
    }
end

-- Fallback: returns the source from the most recent keystone run when the player
-- is no longer inside the instance (e.g. BONUS_ROLL_RESULT fires in open world).
-- Abandoned runs are excluded; running and completed runs both qualify.
local function ResolveFromLastKeystoneRun()
    if not lastKeystoneRun then
        return nil
    end
    if lastKeystoneRun.status == "abandoned" then
        return nil
    end
    return CreateSource(lastKeystoneRun.sourceType, lastKeystoneRun.sourceID, lastKeystoneRun.difficultyID,
        lastKeystoneRun.keyLevel)
end

-- What the player is really doing (the keystone or raid they are in, or just left) wins over the
-- boss/dungeon open in the panel: the panel only fills in when there is no real context, as
-- in the open world.  Otherwise a roll made on Heroic or on a +5 was filed under whatever
-- Mythic boss or +10 tab was on screen.
local function GetResolvedSource()
    return ResolveCurrentMythicPlusSource() or ResolveCurrentRaidSource() or ResolveFromLastKeystoneRun() or
               sourceOverride
end

local function IsInInstancedContent()
    local inInstance = IsInInstance()
    return inInstance == true
end

local function FindDetectedItem(itemID, source)
    if not source or not itemID then
        return nil
    end

    local classID = VCA.SpecInfo and VCA.SpecInfo.GetPlayerClassID and VCA.SpecInfo.GetPlayerClassID()
    if not classID then
        return nil
    end

    local cachedItemIDs = VCA.LootPool and VCA.LootPool.GetItemsForClass and
                              VCA.LootPool
                                  .GetItemsForClass(source.sourceType, source.sourceID, source.difficultyID,
            classID)

    if not cachedItemIDs then
        return nil
    end

    for _, cachedItemID in ipairs(cachedItemIDs) do
        if cachedItemID == itemID then
            return cachedItemID, source
        end
    end

    return nil
end

-- -- Public: source management ------------------------------------------------

-- Explicitly sets the active source. The UI should call this whenever context
-- changes so BONUS_ROLL_RESULT can be attributed to the correct pool.
function Detection.SetActiveSource(sourceType, sourceID, difficultyID, keyLevel)
    sourceOverride = CreateSource(sourceType, sourceID, difficultyID, keyLevel)
end

function Detection.ClearActiveSource()
    sourceOverride = nil
end

function Detection.GetActiveSource()
    return GetResolvedSource()
end

-- callback = function(itemID, source)
function Detection.SetOnItemDetectedCallback(callback)
    onDetectedCallback = callback
end

-- -- Item detection -----------------------------------------------------------

local function SourceName(source)
    local name
    if source.sourceType == VCA.ContentType.RAID then
        name = EJ_GetEncounterInfo and EJ_GetEncounterInfo(source.sourceID)
    else
        name = EJ_GetInstanceInfo and EJ_GetInstanceInfo(source.sourceID)
    end
    return name or tostring(source.sourceID)
end

-- A reset throws away marks, so keep them and tell the player, with a link that puts them back:
-- no command to type.
local function RememberReset(keys, source, specID)
    local db = _G[VCA.CHAR_DB_NAME]
    if not db or not next(keys) then
        return
    end
    db.lastReset = {time = time(), keys = keys}
    local specName = GetSpecializationInfoByID and (select(2, GetSpecializationInfoByID(specID))) or nil
    local link = "|cff00ccff|Hvcaundo:reset|h" .. VCA.L["CYCLE_RESET_UNDO"] .. "|h|r"
    print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " ..
              string.format(VCA.L["CYCLE_RESET"], specName or tostring(specID), SourceName(source), link))
end

if hooksecurefunc then
    hooksecurefunc("SetItemRef", function(link)
        if tostring(link) ~= "vcaundo:reset" then
            return
        end
        local db = _G[VCA.CHAR_DB_NAME]
        local reset = db and db.lastReset
        if not (reset and reset.keys) then
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["RESET_NOTHING"])
            return
        end
        VCA.Data.RestoreKeys(reset.keys)
        db.lastReset = nil
        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["RESET_UNDONE"])
        for _, name in ipairs({"Panel", "DungeonOverview", "RaidOverview"}) do
            local window = VCA[name]
            if window and window.Refresh then
                pcall(window.Refresh)
            end
        end
    end)
end

-- Checks whether every item in the spec-specific pool is now obtained for
-- the given key tier.  If so, resets the obtained flags of THAT spec only on this
-- source, so its cycle starts over while the other specs keep their progress.
-- Returns true if a reset was performed.
-- isHighTier: true = ≥10 tier, false = <10 tier, nil = tier-less / non-M+ (full reset)
local function CheckAndResetIfComplete(source, specID, isHighTier)
    if not source or not specID then
        return false
    end

    local classID = VCA.SpecInfo and VCA.SpecInfo.GetPlayerClassID and VCA.SpecInfo.GetPlayerClassID()
    if not classID then
        return false
    end

    local specPool = VCA.LootPool and VCA.LootPool.GetItemsForSpec and
                         VCA.LootPool
                             .GetItemsForSpec(source.sourceType, source.sourceID, source.difficultyID, classID,
            specID)
    if not specPool or #specPool == 0 then
        return false
    end

    for _, itemID in ipairs(specPool) do
        if not VCA.Data.IsObtainedForKeyTier(source.sourceType, source.sourceID, source.difficultyID, specID, itemID,
            isHighTier) then
            return false
        end
    end

    -- All items obtained for this spec+tier: only this spec starts a new cycle. The other
    -- specs keep what they have, because their own pools are not finished.
    local snapshot = liveRoll and
                         VCA.Data.SnapshotSource(source.sourceType, source.sourceID, source.difficultyID, specID,
            isHighTier)
    VCA.Data.ClearSourceForKeyTier(source.sourceType, source.sourceID, source.difficultyID, specID, isHighTier)
    if snapshot then
        RememberReset(snapshot, source, specID)
    end
    return true
end

-- Public wrapper so UI code (PanelColumns) can trigger the same reset check
-- after a manual spec-picker toggle without going through the detection path.
-- source must be a table with sourceType, sourceID, difficultyID fields.
-- isHighTier: true = ≥10 cycle, false = <10 cycle, nil = full / non-M+ reset.
function Detection.CheckAndResetIfComplete(source, specID, isHighTier)
    return CheckAndResetIfComplete(source, specID, isHighTier)
end

-- Item level of the roll being processed, so the chat message can show it.
local activeItemLevel

-- Item level of an item link as the game shows it (nil when unknown).
local function GetLinkItemLevel(link)
    if type(link) ~= "string" or not (C_Item and C_Item.GetDetailedItemLevelInfo) then
        return nil
    end
    local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
    if ok and type(ilvl) == "number" and ilvl > 0 then
        return ilvl
    end
    return nil
end

function Detection.GetItemLevel(link)
    return GetLinkItemLevel(link)
end

-- A raid drop carries the difficulty it dropped on as a bonus ID of its link, so it can be
-- told even when the addon was showing another boss or difficulty when the roll happened.
local LINK_DIFFICULTY_BONUS = {[13333] = 14, [13334] = 15, [13335] = 16}

function Detection.RaidDifficultyFromLink(link)
    if type(link) ~= "string" then
        return nil
    end
    for bonusID in link:gmatch(":(1333%d):") do
        local diffID = LINK_DIFFICULTY_BONUS[tonumber(bonusID)]
        if diffID then
            return diffID
        end
    end
    return nil
end

-- Item level of each raid difficulty, read once from the sample links of the season data.
local raidLevels = {}
local RAID_DIFFICULTIES = {14, 15, 16}

local function RaidDifficultyFromItemLevel(ilvl)
    if not ilvl or not (VCA.SeasonData and VCA.SeasonData.raids) then
        return nil
    end
    local best, bestGap, tie
    for _, diffID in ipairs(RAID_DIFFICULTIES) do
        if not raidLevels[diffID] then
            for _, raidData in pairs(VCA.SeasonData.raids) do
                local level = raidData.bonusByDiff and GetLinkItemLevel(raidData.bonusByDiff[diffID])
                if level then
                    raidLevels[diffID] = level
                    break
                end
            end
        end
        local level = raidLevels[diffID]
        if level then
            local gap = math.abs(level - ilvl)
            if not bestGap or gap < bestGap then
                best, bestGap, tie = diffID, gap, false
            elseif gap == bestGap then
                tie = true
            end
        end
    end
    if best and not tie and bestGap <= 3 then
        return best
    end
    return nil
end

-- Raid difficulty of a roll log entry: the one it saved, or the one its item level points at.
-- Never guesses: nil when neither is known.
function Detection.ResolveEntryDifficulty(entry)
    local fromLink = Detection.RaidDifficultyFromLink(entry.itemLink)
    if fromLink then
        return fromLink
    end
    if entry.difficultyID then
        return entry.difficultyID
    end
    local ilvl = entry.itemLevel or GetLinkItemLevel(entry.itemLink)
    if ilvl and not entry.itemLevel then
        entry.itemLevel = ilvl
    end
    return RaidDifficultyFromItemLevel(ilvl)
end

-- Undoes the marks an older version left on the other raid difficulties for a roll that
-- belongs to keepDiff.  A difficulty stays marked when another log entry (or a manual
-- mark) of the same item backs it.
local function ClearOtherRaidDifficulties(entry, keepDiff, log)
    if not (VCA.SeasonData and VCA.SeasonData.raids and VCA.Data and VCA.Data.SetObtained) then
        return
    end
    for _, diffID in ipairs(RAID_DIFFICULTIES) do
        if diffID ~= keepDiff then
            local backed = false
            for _, other in ipairs(log) do
                if other ~= entry and other.itemID == entry.itemID and not other.unmarked and
                    Detection.ResolveEntryDifficulty(other) == diffID then
                    backed = true
                    break
                end
            end
            if not backed then
                for encounterID, raidData in pairs(VCA.SeasonData.raids) do
                    if raidData.instanceID == entry.raidInstanceID then
                        local specMap = raidData.bySpec and raidData.bySpec[diffID]
                        if specMap then
                            for specID in pairs(specMap) do
                                VCA.Data.SetObtained(VCA.ContentType.RAID, encounterID, diffID, specID, entry.itemID,
                                    false)
                            end
                        end
                        VCA.Data.SetObtained(VCA.ContentType.RAID, encounterID, diffID, 0, entry.itemID, false)
                    end
                end
            end
        end
    end
end

local function OnCandidateItemDetected(itemID, source, specID)
    if not source or not itemID then
        return
    end

    -- Derive the key tier from the source's key level.
    -- Mythic Keystone (diffID 8) always has a keyLevel; Mythic 0 / unknown → nil (tier-less).
    local isHighTier
    if source.keyLevel then
        isHighTier = source.keyLevel >= 10
    end

    if VCA.Data
        .IsObtainedForKeyTier(source.sourceType, source.sourceID, source.difficultyID, specID, itemID, isHighTier) then
        return
    end

    VCA.Data.SetObtainedForKeyTier(source.sourceType, source.sourceID, source.difficultyID, specID, itemID, isHighTier,
        true)

    if onDetectedCallback then
        onDetectedCallback(itemID, source, activeItemLevel)
    end

    CheckAndResetIfComplete(source, specID, isHighTier)
end

local function TryResolveReward(itemID, source, specID)
    local matchedItemID = FindDetectedItem(itemID, source)
    if not matchedItemID then
        return false
    end
    OnCandidateItemDetected(matchedItemID, source, specID)
    return true
end

-- Scans every encounter in raidInstanceID+difficultyID and marks itemID as
-- obtained in each encounter whose class pool contains it.  Used when the
-- encounterID is unknown at bonus-roll time (BONUS_ROLL_RESULT fires without
-- context for which boss the roll was on).
-- Returns true if the item was found and marked in at least one encounter.
local function TryMarkItemInAllRaidEncounters(itemID, raidInstanceID, difficultyID, specID)
    if not (VCA.SeasonData and VCA.SeasonData.raids) then
        return false
    end
    local classID = VCA.SpecInfo and VCA.SpecInfo.GetPlayerClassID and VCA.SpecInfo.GetPlayerClassID()
    if not classID then
        return false
    end
    local anyMarked = false
    for encounterID, raidData in pairs(VCA.SeasonData.raids) do
        if raidData.instanceID == raidInstanceID then
            local source = CreateSource(VCA.ContentType.RAID, encounterID, difficultyID, nil)
            local pool = VCA.LootPool and VCA.LootPool.GetItemsForClass and
                             VCA.LootPool
                                 .GetItemsForClass(VCA.ContentType.RAID, encounterID, difficultyID, classID)
            if pool then
                for _, id in ipairs(pool) do
                    if id == itemID then
                        OnCandidateItemDetected(itemID, source, specID)
                        anyMarked = true
                        break
                    end
                end
            end
        end
    end
    return anyMarked
end

-- The source can point at the boss selected in the Encounter Journal instead of
-- the boss that dropped the roll.  When the item is not in that boss's pool,
-- search the whole raid the boss belongs to.
local function TryRecoverRaidSource(itemID, source, specID)
    if not (source and source.sourceType == VCA.ContentType.RAID and source.sourceID) then
        return false
    end
    local raidData = VCA.SeasonData and VCA.SeasonData.raids and VCA.SeasonData.raids[source.sourceID]
    if not (raidData and raidData.instanceID) then
        return false
    end
    return TryMarkItemInAllRaidEncounters(itemID, raidData.instanceID, source.difficultyID, specID)
end

-- Last-resort recovery for log entries with only itemID+specID and no source
-- context at all (pre-raid-detection logs).  Searches every SeasonData raid
-- encounter on raidDifficultyID only (a raid roll is marked on the difficulty it was made
-- on, never on all of them; without a known difficulty raids are skipped) first; if found
-- there, returns without checking dungeons (item pools are mutually exclusive).  If not
-- found in raids, falls back to dungeon instances.
-- Returns a descriptor on success so the caller can patch the log entry:
--   { kind="raid",    raidInstanceID=N, difficultyID=D }   — found in a raid
--   { kind="dungeon", sourceType=T, sourceID=N, difficultyID=D } — found in a dungeon
-- Returns nil on failure.
local function TryMarkItemAcrossAllSources(itemID, specID, raidDifficultyID)
    if not (VCA.SeasonData and itemID and specID) then
        return nil
    end
    -- Raid encounters. Pool is disjoint from dungeons, so stop here if found.
    if VCA.SeasonData.raids and raidDifficultyID then
        local foundInRaid = false
        local resolvedRaidInstanceID = nil
        for encounterID, raidData in pairs(VCA.SeasonData.raids) do
            for _, diffID in ipairs({raidDifficultyID}) do
                local pool = raidData[diffID]
                if pool then
                    for _, id in ipairs(pool) do
                        if id == itemID then
                            local source = CreateSource(VCA.ContentType.RAID, encounterID, diffID, nil)
                            OnCandidateItemDetected(itemID, source, specID)
                            if not foundInRaid then
                                foundInRaid = true
                                resolvedRaidInstanceID = raidData.instanceID
                            end
                            break
                        end
                    end
                end
            end
        end
        if foundInRaid then
            return {
                kind = "raid",
                raidInstanceID = resolvedRaidInstanceID,
                difficultyID = raidDifficultyID
            }
        end
    end
    -- Dungeon instances — only reached if the item was not in any raid pool.
    if VCA.SeasonData.dungeons then
        for instanceID, dungeonData in pairs(VCA.SeasonData.dungeons) do
            local pool = dungeonData.all
            if pool then
                for _, id in ipairs(pool) do
                    if id == itemID then
                        local source = CreateSource(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty,
                            nil)
                        OnCandidateItemDetected(itemID, source, specID)
                        return {
                            kind = "dungeon",
                            sourceType = VCA.ContentType.MYTHIC_PLUS,
                            sourceID = instanceID,
                            difficultyID = VCA.MythicPlusEJDifficulty
                        }
                    end
                end
            end
        end
    end
    return nil
end

-- Replays saved bonus roll log entries through the detection pipeline.
-- Marks any unmatched items as obtained if they belong to the known pool.
-- Safe to call multiple times; IsObtained guards against double-marking.
-- verbose=true prints per-entry results to chat.
function Detection.ReplayBonusRollLog(verbose)
    local log = VCA.Data and VCA.Data.GetBonusRollLog and VCA.Data.GetBonusRollLog()
    if not log or #log == 0 then
        if verbose then
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_EMPTY"])
        end
        return
    end
    local marked, skipped, nomatch, incomplete = 0, 0, 0, 0
    for i, entry in ipairs(log) do
        activeItemLevel = entry.itemLevel or GetLinkItemLevel(entry.itemLink)
        -- A raid bonus roll has raidInstanceID+difficultyID but no sourceType/sourceID.
        -- Try the all-encounters path before treating the entry as incomplete.
        local linkDiff = Detection.RaidDifficultyFromLink(entry.itemLink)
        if entry.unmarked then
            -- The player cleared this item by hand: do not mark it again.
            skipped = skipped + 1
        elseif linkDiff and (entry.sourceType == VCA.ContentType.RAID or entry.raidInstanceID) and
            entry.difficultyID ~= linkDiff and entry.itemID and entry.specID then
            -- The roll was saved with another difficulty than the one its item dropped on (the
            -- boss open in the panel won over the real one).  Correct it, undo the wrong marks
            -- and mark the real difficulty.
            local raidData = entry.sourceID and VCA.SeasonData and VCA.SeasonData.raids and
                                 VCA.SeasonData.raids[entry.sourceID]
            entry.raidInstanceID = entry.raidInstanceID or (raidData and raidData.instanceID)
            entry.resolvedAllRaidDifficulties = nil
            entry.difficultyID = linkDiff
            if entry.raidInstanceID then
                ClearOtherRaidDifficulties(entry, linkDiff, log)
                if TryMarkItemInAllRaidEncounters(entry.itemID, entry.raidInstanceID, linkDiff, entry.specID) then
                    marked = marked + 1
                else
                    skipped = skipped + 1
                end
            else
                incomplete = incomplete + 1
            end
        elseif not (entry.itemID and entry.sourceType and entry.sourceID and entry.difficultyID and entry.specID) then
            if entry.itemID and entry.raidInstanceID and entry.difficultyID and entry.specID then
                if TryMarkItemInAllRaidEncounters(entry.itemID, entry.raidInstanceID, entry.difficultyID, entry.specID) then
                    marked = marked + 1
                    if verbose then
                        local name = C_Item.GetItemNameByID(entry.itemID) or tostring(entry.itemID)
                        print(string.format(
                            VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_RAID_ALL"],
                            i, name, tostring(entry.specID)))
                    end
                else
                    incomplete = incomplete + 1
                    if verbose then
                        print(string.format(
                            VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_INCOMPLETE"],
                            i, tostring(entry.itemID), tostring(entry.specID), tostring(entry.sourceType),
                            tostring(entry.sourceID), tostring(entry.difficultyID)))
                    end
                end
            else
                -- No raidInstanceID/difficultyID — check if a previous replay
                -- already resolved this entry and stored enough info to skip the
                -- full SeasonData scan.
                if entry.itemID and entry.raidInstanceID and entry.resolvedAllRaidDifficulties and entry.specID then
                    -- Older versions marked these on all three difficulties. Mark only the
                    -- difficulty the roll really had (from its item level) and undo the rest;
                    -- if it cannot be told, leave the entry alone instead of guessing.
                    local diffID = Detection.ResolveEntryDifficulty(entry)
                    local anyMarked = false
                    if diffID then
                        ClearOtherRaidDifficulties(entry, diffID, log)
                        entry.difficultyID = diffID
                        entry.resolvedAllRaidDifficulties = nil
                        anyMarked = TryMarkItemInAllRaidEncounters(entry.itemID, entry.raidInstanceID, diffID,
                            entry.specID)
                    end
                    if anyMarked then
                        marked = marked + 1
                        if verbose then
                            local name = C_Item.GetItemNameByID(entry.itemID) or tostring(entry.itemID)
                            print(string.format(
                                VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_REMARKED"],
                                i, tostring(diffID), name, tostring(entry.specID)))
                        end
                    else
                        incomplete = incomplete + 1
                        if verbose then
                            print(string.format(
                                VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_NOT_IN_POOL"],
                                i, tostring(entry.itemID)))
                        end
                    end
                elseif entry.itemID and entry.specID then
                    -- Full scan — no prior resolution on this entry.
                    local resolved = TryMarkItemAcrossAllSources(entry.itemID, entry.specID,
                        Detection.ResolveEntryDifficulty(entry))
                    if resolved then
                        marked = marked + 1
                        -- Patch the log entry so future replays skip this scan.
                        if resolved.kind == "dungeon" then
                            entry.sourceType = resolved.sourceType
                            entry.sourceID = resolved.sourceID
                            entry.difficultyID = resolved.difficultyID
                        else -- "raid"
                            entry.raidInstanceID = resolved.raidInstanceID
                            entry.difficultyID = resolved.difficultyID
                        end
                        if verbose then
                            local name = C_Item.GetItemNameByID(entry.itemID) or tostring(entry.itemID)
                            print(string.format(
                                VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_ALL_SOURCES"],
                                i, name, tostring(entry.specID)))
                        end
                    else
                        incomplete = incomplete + 1
                        if verbose then
                            print(string.format(
                                VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_INCOMPLETE"],
                                i, tostring(entry.itemID), tostring(entry.specID), tostring(entry.sourceType),
                                tostring(entry.sourceID), tostring(entry.difficultyID)))
                        end
                    end
                else
                    incomplete = incomplete + 1
                    if verbose then
                        print(string.format(
                            VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_INCOMPLETE"],
                            i, tostring(entry.itemID), tostring(entry.specID), tostring(entry.sourceType),
                            tostring(entry.sourceID), tostring(entry.difficultyID)))
                    end
                end
            end
        else
            local source = {
                sourceType = entry.sourceType,
                sourceID = entry.sourceID,
                difficultyID = entry.difficultyID,
                keyLevel = entry.keyLevel
            }
            local isHighTier
            if entry.keyLevel then
                isHighTier = entry.keyLevel >= 10
            end
            local alreadyObtained = VCA.Data.IsObtainedForKeyTier(source.sourceType, source.sourceID,
                source.difficultyID, entry.specID, entry.itemID, isHighTier)
            if alreadyObtained then
                -- If the log entry has a known tier and the existing record is a bare key
                -- (unknown-tier legacy entry), upgrade it to a proper tiered key so that
                -- each tier's cycle can be reset independently going forward.
                if isHighTier ~= nil and
                    VCA.Data
                        .IsObtainedBareKey(source.sourceType, source.sourceID, source.difficultyID, entry.specID,
                        entry.itemID) then
                    if not VCA.Data.IsObtainedTiered(source.sourceType, source.sourceID, source.difficultyID,
                        entry.specID, entry.itemID, isHighTier) then
                        VCA.Data.SetObtainedForKeyTier(source.sourceType, source.sourceID, source.difficultyID,
                            entry.specID, entry.itemID, isHighTier, true)
                        if verbose then
                            local name = C_Item.GetItemNameByID(entry.itemID) or tostring(entry.itemID)
                            print(string.format(
                                VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_UPGRADED"],
                                i, isHighTier and "≥10" or "<10", name, tostring(entry.specID)))
                        end
                    end
                end
                skipped = skipped + 1
                if verbose then
                    local name = C_Item.GetItemNameByID(entry.itemID) or tostring(entry.itemID)
                    print(string.format(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_ALREADY"],
                        i, name, tostring(entry.specID)))
                end
            else
                local classID = VCA.SpecInfo and VCA.SpecInfo.GetPlayerClassID and VCA.SpecInfo.GetPlayerClassID()
                local cachedPool = classID and VCA.LootPool and VCA.LootPool.GetItemsForClass and
                                       VCA.LootPool
                                           .GetItemsForClass(source.sourceType, source.sourceID,
                        source.difficultyID, classID)
                local inPool = false
                if cachedPool then
                    for _, id in ipairs(cachedPool) do
                        if id == entry.itemID then
                            inPool = true;
                            break
                        end
                    end
                end
                if verbose then
                    local name = C_Item.GetItemNameByID(entry.itemID) or tostring(entry.itemID)
                    print(string.format(
                        VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_DETAIL"],
                        i, name, tostring(entry.specID), source.sourceType, tostring(source.sourceID),
                        tostring(classID), cachedPool and tostring(#cachedPool) or "nil", tostring(inPool)))
                end
                if TryResolveReward(entry.itemID, source, entry.specID) then
                    marked = marked + 1
                    -- Detect a cycle reset: if the item we just marked is no longer
                    -- obtained, CheckAndResetIfComplete fired and cleared the pool.
                    if verbose and
                        not VCA.Data
                            .IsObtained(source.sourceType, source.sourceID, source.difficultyID, entry.specID,
                            entry.itemID) then
                        print(string.format(
                            VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_CYCLE_RESET"], i,
                            tostring(entry.specID)))
                    end
                elseif TryRecoverRaidSource(entry.itemID, source, entry.specID) then
                    marked = marked + 1
                else
                    nomatch = nomatch + 1
                end
            end
        end
    end
    activeItemLevel = nil
    if verbose then
        print(string.format(
            VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["REPLAY_DONE"],
            marked, skipped, nomatch, incomplete))
    end
end

local function QueuePendingReward(itemID, source, specID)
    if not itemID then
        return
    end

    pendingRewards[#pendingRewards + 1] = {
        itemID = itemID,
        source = source,
        specID = specID,
        itemLevel = activeItemLevel
    }
end

local function ProcessPendingRewards()
    if #pendingRewards == 0 then
        return
    end

    local remaining = {}
    for _, entry in ipairs(pendingRewards) do
        local source = entry.source or GetResolvedSource()
        local resolved = false
        activeItemLevel = entry.itemLevel
        if source and source.raidInstanceID and not source.sourceType then
            resolved = TryMarkItemInAllRaidEncounters(entry.itemID, source.raidInstanceID, source.difficultyID,
                entry.specID)
        else
            resolved = TryResolveReward(entry.itemID, source, entry.specID) or
                           TryRecoverRaidSource(entry.itemID, source, entry.specID)
        end
        if not resolved then
            remaining[#remaining + 1] = {
                itemID = entry.itemID,
                source = source,
                specID = entry.specID,
                itemLevel = entry.itemLevel
            }
        end
    end

    activeItemLevel = nil
    pendingRewards = remaining
end

local function ProcessRewardItem(itemID, specID, sourceHint)
    if not itemID then
        return
    end

    -- Prefer a source captured at event time; fall back to live resolution.
    local source = sourceHint or GetResolvedSource()

    -- Raid bonus rolls: source has raidInstanceID but no sourceType/sourceID.
    -- Scan all encounters in the raid for the item.
    if source and source.raidInstanceID and not source.sourceType then
        if TryMarkItemInAllRaidEncounters(itemID, source.raidInstanceID, source.difficultyID, specID) then
            return
        end
    elseif TryResolveReward(itemID, source, specID) or TryRecoverRaidSource(itemID, source, specID) then
        return
    end

    -- Queue the reward. Outside a dungeon, attempt to flush immediately.
    -- Inside one, leave it queued until PLAYER_ENTERING_WORLD fires on exit.
    QueuePendingReward(itemID, source, specID)
    if not IsInInstancedContent() then
        ProcessPendingRewards()
    end
end

-- -- Event handlers -----------------------------------------------------------

local handlers = {}

-- Detects and caches the active keystone context.  Called from both
-- CHALLENGE_MODE_START (new key) and PLAYER_ENTERING_WORLD (re-entry).
local function CacheActiveKeystoneRun()
    if not C_ChallengeMode then
        return
    end
    local level = C_ChallengeMode.GetActiveKeystoneInfo()
    if not level or level <= 0 then
        return
    end
    PersistKeyLevel(level)
    local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local sourceID = (instanceID and VCA.LootPool and VCA.LootPool.GetSeasonDungeonByInstanceID and
                         VCA.LootPool.GetSeasonDungeonByInstanceID(instanceID)) or
                         (VCA.LootPool and VCA.LootPool.GetSeasonDungeonByName and
                             VCA.LootPool.GetSeasonDungeonByName(instanceName))
    if sourceID then
        PersistKeystoneRun({
            sourceType = VCA.ContentType.MYTHIC_PLUS,
            sourceID = sourceID,
            difficultyID = VCA.MythicPlusEJDifficulty,
            keyLevel = level,
            status = "running"
        })
    end
    print(string.format(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["KEY_DETECTED"], instanceName or VCA.L["UNKNOWN"], level))
end

function handlers.CHALLENGE_MODE_START()
    CacheActiveKeystoneRun()
end

-- Silent — no message at end-of-run.  Also captures the key level if
-- CHALLENGE_MODE_START was missed (e.g. /reload during the countdown).
function handlers.CHALLENGE_MODE_COMPLETED()
    UpdateKeystoneRunStatus("completed")
    if cachedKeyLevel then
        return
    end
    if not C_ChallengeMode then
        return
    end
    local level = C_ChallengeMode.GetActiveKeystoneInfo()
    if level and level > 0 then
        PersistKeyLevel(level)
    end
end

-- Fired on login and every loading-screen transition.
function handlers.PLAYER_ENTERING_WORLD()
    if IsInInstancedContent() then
        local _, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
        -- On every party instance entry, re-detect an active keystone.
        -- Covers /reload and re-entries; fresh starts are handled by CHALLENGE_MODE_START.
        if instanceType == "party" then
            CacheActiveKeystoneRun()
        end
        -- Snapshot raid context on every zone entry so BONUS_ROLL_RESULT does
        -- not need a live GetInstanceInfo() call.  Also restores after /reload.
        -- Deferred one frame so Init.lua's PLAYER_ENTERING_WORLD (which calls
        -- BuildSeasonFilter) has already run before we check the season filter.
        if instanceType == "raid" and VCA.EligibleRaidDifficulties and VCA.EligibleRaidDifficulties[difficultyID] then
            C_Timer.After(0, function()
                local instanceName2, _, _, difficultyName = GetInstanceInfo()
                local ejInstanceID = (VCA.LootPool and VCA.LootPool.GetSeasonRaidByMapID and
                                         VCA.LootPool.GetSeasonRaidByMapID(instanceID)) or
                                         (VCA.LootPool and VCA.LootPool.GetSeasonRaidByName and
                                             VCA.LootPool.GetSeasonRaidByName(instanceName2))
                if ejInstanceID then
                    PersistRaidContext(ejInstanceID, difficultyID)
                    print(string.format(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.L["RAID_DETECTED"],
                        instanceName2 or VCA.L["UNKNOWN"], difficultyName or tostring(difficultyID)))
                else
                    ClearPersistedRaidContext()
                end
            end)
        else
            -- Entered a non-raid or ineligible instance — clear any stale raid cache
            -- so it does not bleed into M+ or open-world bonus rolls.
            ClearPersistedRaidContext()
        end
    else
        -- Left instance: clear all cached M+ and raid run state.
        ClearPersistedKeyLevel()
        PersistKeystoneRun(nil)
        ClearPersistedRaidContext()
        Detection.ClearActiveSource()
        C_Timer.After(0, ProcessPendingRewards)
    end
end

-- Core detection path. Fires when the player receives a bonus roll result.
function handlers.BONUS_ROLL_RESULT(typeIdentifier, itemLink, quantity, specID)
    if typeIdentifier ~= "item" then
        return
    end
    if type(itemLink) ~= "string" then
        return
    end

    local idStr = itemLink:match("|Hitem:(%d+):")
    local itemID = idStr and tonumber(idStr)
    if not itemID then
        return
    end

    -- specID is provided by the event payload. Fall back to the effective loot
    -- spec only if the event omits it (future-proofing).
    if not specID or specID == 0 then
        specID = VCA.SpecInfo and VCA.SpecInfo.GetEffectiveLootSpecID and VCA.SpecInfo.GetEffectiveLootSpecID()
    end

    -- Capture the source now — GetInstanceInfo() state may change one frame
    -- later (e.g. after run completion), which would cause source resolution to fail.
    local capturedSource = GetResolvedSource()

    -- The boss open in the panel can win over the real one: trust the difficulty the item dropped on.
    local linkDiff = Detection.RaidDifficultyFromLink(itemLink)
    if capturedSource and linkDiff and capturedSource.difficultyID ~= linkDiff and
        (capturedSource.sourceType == VCA.ContentType.RAID or capturedSource.raidInstanceID) then
        local fixed = {}
        for k, v in pairs(capturedSource) do
            fixed[k] = v
        end
        fixed.difficultyID = linkDiff
        capturedSource = fixed
    end

    -- Write a raw log entry immediately for post-hoc auditing if matching fails.
    if VCA.Data and VCA.Data.LogBonusRoll then
        VCA.Data.LogBonusRoll(itemID, itemLink, specID, capturedSource)
    end

    -- Defer one frame so item data is populated before pool lookup.
    local rolledLevel = GetLinkItemLevel(itemLink)
    C_Timer.After(0, function()
        activeItemLevel = rolledLevel
        liveRoll = true
        local ok, err = pcall(ProcessRewardItem, itemID, specID, capturedSource)
        liveRoll = false
        activeItemLevel = nil
        if not ok then
            error(err, 0)
        end
        -- Replay the full log as a safety net: if the pool cache was not warm
        -- when ProcessRewardItem ran, the log entry now has the correct source.
        Detection.ReplayBonusRollLog(false)
    end)
end

-- -- Event frame --------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
        handler(...)
    end
end)
