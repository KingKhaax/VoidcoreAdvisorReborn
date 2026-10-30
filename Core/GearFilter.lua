local _, VCA = ...

local GearFilter = {}
VCA.GearFilter = GearFilter

local ITEM_CLASS_WEAPON = 2
local ITEM_CLASS_ARMOR = 4
local ARMOR_COSMETIC = 5

local EQUIP_SLOTS = {
    INVTYPE_HEAD = true,
    INVTYPE_NECK = true,
    INVTYPE_SHOULDER = true,
    INVTYPE_CLOAK = true,
    INVTYPE_CHEST = true,
    INVTYPE_ROBE = true,
    INVTYPE_WRIST = true,
    INVTYPE_HAND = true,
    INVTYPE_WAIST = true,
    INVTYPE_LEGS = true,
    INVTYPE_FEET = true,
    INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true,
    INVTYPE_WEAPON = true,
    INVTYPE_SHIELD = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_HOLDABLE = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
    INVTYPE_RELIC = true
}

local cache = {}

function GearFilter.IsGear(itemID)
    local known = cache[itemID]
    if known ~= nil then
        return known
    end
    if not (C_Item and C_Item.GetItemInfoInstant) then
        return nil
    end
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if classID == nil then
        return nil
    end
    local gear = (classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR) and EQUIP_SLOTS[equipLoc] == true
        and not (classID == ITEM_CLASS_ARMOR and subClassID == ARMOR_COSMETIC)
    cache[itemID] = gear
    return gear
end

local function PruneList(list)
    if type(list) ~= "table" then
        return 0, true
    end
    local removed, complete = 0, true
    for i = #list, 1, -1 do
        local gear = GearFilter.IsGear(list[i])
        if gear == false then
            table.remove(list, i)
            removed = removed + 1
        elseif gear == nil then
            complete = false
        end
    end
    return removed, complete
end

local function PruneAll(lists)
    local removed, complete = 0, true
    for _, list in ipairs(lists) do
        local r, c = PruneList(list)
        removed = removed + r
        complete = complete and c
    end
    return removed, complete
end

local function RaidLists(encounter)
    local lists = {}
    for key, value in pairs(encounter) do
        if type(key) == "number" and type(value) == "table" then
            lists[#lists + 1] = value
        end
    end
    for _, group in pairs({encounter.byClass or {}, encounter.bySpec or {}}) do
        for _, perDifficulty in pairs(group) do
            if type(perDifficulty) == "table" then
                for _, list in pairs(perDifficulty) do
                    lists[#lists + 1] = list
                end
            end
        end
    end
    return lists
end

local function DungeonLists(dungeon)
    local lists = {dungeon.all}
    for _, group in pairs({dungeon.byEncounter or {}, dungeon.byClass or {}, dungeon.bySpec or {}}) do
        for _, list in pairs(group) do
            lists[#lists + 1] = list
        end
    end
    return lists
end

function GearFilter.Prune(seasonData)
    if type(seasonData) ~= "table" then
        return 0
    end
    local removed = 0
    for _, encounter in pairs(seasonData.raids or {}) do
        removed = removed + PruneAll(RaidLists(encounter))
    end
    for _, dungeon in pairs(seasonData.dungeons or {}) do
        removed = removed + PruneAll(DungeonLists(dungeon))
    end
    return removed
end

function GearFilter.Run()
    local removed = GearFilter.Prune(VCA.SeasonData)
    if removed > 0 and VCA.LootPool and VCA.LootPool.InvalidateCache then
        VCA.LootPool.InvalidateCache()
    end
    return removed
end

pcall(GearFilter.Run)
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    pcall(GearFilter.Run)
end)
