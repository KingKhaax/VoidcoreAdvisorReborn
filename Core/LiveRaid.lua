-- VoidcoreAdvisor: LiveRaid
-- Builds the loot pool of raids that are not in the generated SeasonData by
-- reading the Encounter Journal in-game, the same way VoidcoreAdvisorGen does.
-- The result is stored in VoidcoreAdvisorDB.liveRaids and injected into
-- VCA.SeasonData.raids, so it survives relogs without rescanning.
local addonName, VCA = ...
local L = VCA.L

local LiveRaid = {}
VCA.LiveRaid = LiveRaid

-- Encounter IDs whose raid must be scanned when SeasonData lacks them.
-- 3513 = Kith'ix (The Unbinding of Kith'ix).
local WANTED_ENCOUNTERS = {3513}
local DIFFICULTIES = {14, 15, 16}
local MAX_CLASS_ID = 13
local MAX_ATTEMPTS = 6

local function GetDB()
    local db = _G[VCA.GLOBAL_DB_NAME]
    if type(db) ~= "table" then
        return nil
    end
    db.liveRaids = db.liveRaids or {}
    return db.liveRaids
end

local function Inject(entry)
    VCA.SeasonData = VCA.SeasonData or {}
    VCA.SeasonData.raids = VCA.SeasonData.raids or {}
    for encounterID, data in pairs(entry.raids) do
        if not VCA.SeasonData.raids[encounterID] then
            VCA.SeasonData.raids[encounterID] = data
        end
    end
    VCA.LootPool.AddLiveRaid(entry.instanceID, entry.mapID)
    if VCA.TankTrinkets then
        VCA.TankTrinkets.Run()
    end
end

local function ItemQuality(itemID, link)
    local q = link and link:match("|cnIQ(%d):")
    if q then
        return tonumber(q)
    end
    if C_Item.GetItemQualityByID then
        return C_Item.GetItemQualityByID(itemID)
    end
end

-- Collects the epic item IDs of the currently selected EJ encounter for one
-- loot filter. Returns the sorted list, a sample link, and false when item
-- data was not loaded yet.
local function ReadLoot(classID, specID)
    EJ_SetLootFilter(classID, specID)
    local ids, seen, sample = {}, {}, nil
    for i = 1, EJ_GetNumLoot() do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        local itemID = info and info.itemID
        if itemID and itemID > 0 and not seen[itemID] then
            local quality = ItemQuality(itemID, info.link)
            if quality == nil then
                return nil, nil, false
            end
            if quality >= 4 then
                seen[itemID] = true
                ids[#ids + 1] = itemID
                sample = sample or info.link
            end
        end
    end
    table.sort(ids)
    return ids, sample, true
end

-- Real raids support the Normal/Heroic/Mythic difficulties; world boss entries such
-- as the expansion's own "Midnight" entry do not. The instance must be selected.
-- The entry named after the expansion (the world bosses) is skipped too, and so is
-- anything without a map.
-- Journal entries that are not raids (world bosses of an expansion).
local NOT_RAIDS = {
    [1312] = true -- "Midnight" world bosses
}

local function IsRaidInstance(instanceID, instanceName, tier)
    if instanceID and NOT_RAIDS[instanceID] then
        return false
    end
    if not (EJ_IsValidInstanceDifficulty(14) or EJ_IsValidInstanceDifficulty(15) or EJ_IsValidInstanceDifficulty(16)) then
        return false
    end
    local mapID = instanceID and select(10, EJ_GetInstanceInfo(instanceID))
    if not (mapID and mapID > 0) then
        return false
    end
    local tierName = EJ_GetTierInfo and tier and EJ_GetTierInfo(tier)
    return not (tierName and instanceName == tierName)
end

local function Say(verbose, text)
    if verbose then
        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. text)
    end
end

-- Looks for the raid to read in the newest Encounter Journal tiers: the one that
-- contains one of the wanted boss IDs (the dungeon encounter ID is the 7th value
-- of EJ_GetEncounterInfoByIndex, the one BigWigs uses) or, failing that, a raid of
-- the newest tier that the loot data does not know yet.
local function FindRaid(verbose)
    local numTiers = EJ_GetNumTiers()
    local savedTier = EJ_GetCurrentTier()
    local found, fallback
    for tier = numTiers, math.max(1, numTiers - 1), -1 do
        EJ_SelectTier(tier)
        local idx = 1
        while not found do
            local instanceID, instanceName = EJ_GetInstanceByIndex(idx, true)
            if not instanceID then
                break
            end
            EJ_SelectInstance(instanceID)
            local known = VCA.LootPool.IsCurrentSeasonRaid(instanceID)
            Say(verbose, string.format("tier %d: %s (%d)%s", tier, tostring(instanceName), instanceID,
                known and " [in the loot data]" or ""))
            local e = 1
            while true do
                local _, _, journalID, _, _, _, dungeonID = EJ_GetEncounterInfoByIndex(e, instanceID)
                if not journalID then
                    break
                end
                for _, wanted in ipairs(WANTED_ENCOUNTERS) do
                    if dungeonID == wanted or journalID == wanted then
                        found = instanceID
                    end
                end
                e = e + 1
            end
            if not known and tier == numTiers and IsRaidInstance(instanceID, instanceName, tier) then
                fallback = fallback or instanceID
            end
            idx = idx + 1
        end
        if found then
            break
        end
    end
    if savedTier and savedTier > 0 then
        EJ_SelectTier(savedTier)
    end
    return found or fallback
end

-- Returns the entry on success, nil when item data is still loading.
local function ScanInstance(instanceID)
    local savedTier = EJ_GetCurrentTier()
    local savedDiff = EJ_GetDifficulty()

    LiveRaid._scanning = true
    VCA.LootPool._reentryGuard = true
    local ok, entry = pcall(function()
        EJ_SelectInstance(instanceID)
        local mapID = select(10, EJ_GetInstanceInfo(instanceID))
        local result = {instanceID = instanceID, mapID = mapID, raids = {}}

        local encounters = {}
        local e = 1
        while true do
            local _, _, encounterID = EJ_GetEncounterInfoByIndex(e, instanceID)
            if not encounterID then
                break
            end
            encounters[#encounters + 1] = encounterID
            e = e + 1
        end

        for _, encounterID in ipairs(encounters) do
            local data = {instanceID = instanceID, byClass = {}, bySpec = {}, bonusByDiff = {}}
            for _, diff in ipairs(DIFFICULTIES) do
                if EJ_IsValidInstanceDifficulty(diff) then
                    EJ_SetDifficulty(diff)
                    EJ_SelectEncounter(encounterID)

                    local all, sample, complete = ReadLoot(0, 0)
                    if not complete then
                        return nil
                    end
                    data[diff] = all
                    data.bonusByDiff[diff] = sample

                    data.byClass[diff] = {}
                    data.bySpec[diff] = {}
                    for classID = 1, MAX_CLASS_ID do
                        local classIDs, _, classComplete = ReadLoot(classID, 0)
                        if not classComplete then
                            return nil
                        end
                        data.byClass[diff][classID] = classIDs
                        for s = 1, GetNumSpecializationsForClassID(classID) do
                            local specID = GetSpecializationInfoForClassID(classID, s)
                            local specIDs, _, specComplete = ReadLoot(classID, specID)
                            if not specComplete then
                                return nil
                            end
                            data.bySpec[diff][specID] = specIDs
                        end
                    end
                end
            end
            result.raids[encounterID] = data
        end
        return result
    end)
    VCA.LootPool._reentryGuard = false
    LiveRaid._scanning = false

    pcall(function()
        EJ_SelectTier(savedTier)
        EJ_SetDifficulty(savedDiff)
        EJ_SetLootFilter(VCA.SpecInfo.GetPlayerClassID() or 0, VCA.SpecInfo.GetEffectiveLootSpecID() or 0)
    end)

    if ok then
        return entry
    end
end

local function Refresh()
    VCA.LootPool.InvalidateCache()
    VCA.LootPool.BuildSeasonFilter()
    if VCA.Panel and VCA.Panel.Refresh then
        pcall(VCA.Panel.Refresh)
    end
end

local function TryScan(attempt, verbose)
    local store = GetDB()
    if not store then
        return
    end
    if InCombatLockdown() or IsInInstance() then
        Say(verbose, L["LIVE_RAID_NO_ACCESS"])
        C_Timer.After(10, function()
            TryScan(attempt, verbose)
        end)
        return
    end

    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end
    if not EJ_GetNumTiers then
        return
    end

    local instanceID = FindRaid(verbose)
    if not instanceID then
        Say(verbose, L["LIVE_RAID_NOT_FOUND"])
        return
    end
    if store[instanceID] and store[instanceID].raids and not verbose then
        return
    end

    local entry = ScanInstance(instanceID)
    if entry then
        entry.build = select(2, GetBuildInfo())
        store[instanceID] = entry
        Inject(entry)
        Refresh()
        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["LIVE_RAID_ADDED"])
    elseif attempt < MAX_ATTEMPTS then
        Say(verbose, L["LIVE_RAID_RETRY"])
        C_Timer.After(4, function()
            TryScan(attempt + 1, verbose)
        end)
    else
        Say(verbose, L["LIVE_RAID_FAILED"])
    end
end

-- Warns once per session about raids of the newest tier that the loot data does
-- not know, so the player understands why the panel is missing there.
local warnedOutdated = false
local function CheckOutdated()
    if warnedOutdated or InCombatLockdown() or IsInInstance() or not EJ_GetNumTiers then
        return
    end
    local savedTier = EJ_GetCurrentTier()
    -- Each unknown raid is announced once, ever (not at every login).
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    local already = gdb and gdb.warnedRaids
    local unknown, unknownIDs = {}, {}
    EJ_SelectTier(EJ_GetNumTiers())
    local idx = 1
    while true do
        local instanceID, name = EJ_GetInstanceByIndex(idx, true)
        if not instanceID then
            break
        end
        if not VCA.LootPool.IsCurrentSeasonRaid(instanceID) and not (already and already[instanceID]) then
            EJ_SelectInstance(instanceID)
            if IsRaidInstance(instanceID, name, EJ_GetNumTiers()) then
                unknown[#unknown + 1] = name or tostring(instanceID)
                unknownIDs[#unknownIDs + 1] = instanceID
            end
        end
        idx = idx + 1
    end
    if savedTier and savedTier > 0 then
        EJ_SelectTier(savedTier)
    end
    if #unknown > 0 then
        warnedOutdated = true
        if gdb then
            gdb.warnedRaids = gdb.warnedRaids or {}
            for _, id in ipairs(unknownIDs) do
                gdb.warnedRaids[id] = true
            end
        end
        local text = string.format(L["DATA_OUTDATED"], table.concat(unknown, ", "))
        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. text)
        if VCA.Banner then
            VCA.Banner(text)
        end
    end
end

LiveRaid.CheckOutdated = CheckOutdated

-- /void liveraid: force a scan and report what happened.
function LiveRaid.Run(verbose)
    TryScan(1, verbose)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= addonName then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        -- Raids shipped with the addon (Core/SeasonDataExtra.lua).
        for _, entry in pairs(VCA.SeasonDataExtra or {}) do
            Inject(entry)
        end
        local store = GetDB()
        if store then
            for _, entry in pairs(store) do
                if type(entry) == "table" and entry.raids then
                    Inject(entry)
                end
            end
        end
    else
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(8, function()
            TryScan(1)
        end)
        C_Timer.After(25, CheckOutdated)
    end
end)
