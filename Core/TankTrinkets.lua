-- VoidcoreAdvisor Reborn: TankTrinkets
-- A tank specialization can loot the damage trinkets of its class that use the same main
-- stat (the Adventure Guide shows them, for example Zul'jin's Guillotine Technique for a
-- Protection Paladin), but the generated loot tables list them only for the damage specs.
-- This adds those trinkets to the pool of the tank spec, once, when the addon loads.
local _, VCA = ...

local TankTrinkets = {}
VCA.TankTrinkets = TankTrinkets

-- Tank spec -> the damage specs of the same class with the same main stat.
TankTrinkets.SIBLINGS = {
    [66] = {70}, -- Protection Paladin  <- Retribution (Strength)
    [73] = {71, 72}, -- Protection Warrior  <- Arms, Fury (Strength)
    [250] = {251, 252}, -- Blood Death Knight  <- Frost, Unholy (Strength)
    [104] = {103}, -- Guardian Druid      <- Feral (Agility)
    [268] = {269}, -- Brewmaster Monk     <- Windwalker (Agility)
    [581] = {577} -- Vengeance Demon Hunter <- Havoc (Agility)
}

local done = setmetatable({}, {__mode = "k"})
local addedBy = {}

function TankTrinkets.IsAdded(specID, itemID)
    return addedBy[specID] ~= nil and addedBy[specID][itemID] == true
end

-- Adds to each tank list of `pools` (map specID -> list of item IDs) the trinkets that its
-- damage siblings have and it lacks. isTrinket(itemID) returns true, false, or nil when the item
-- is not known yet. Returns how many items were added and whether the answer is complete.
function TankTrinkets.Augment(pools, isTrinket)
    if type(pools) ~= "table" or done[pools] then
        return 0, true
    end
    local added, complete = 0, true
    for tankSpec, siblings in pairs(TankTrinkets.SIBLINGS) do
        local tankList = pools[tankSpec]
        if type(tankList) == "table" then
            local have = {}
            for _, id in ipairs(tankList) do
                have[id] = true
            end
            for _, sibling in ipairs(siblings) do
                local list = pools[sibling]
                if type(list) == "table" and list ~= tankList then
                    for _, id in ipairs(list) do
                        if not have[id] then
                            local trinket = isTrinket(id)
                            if trinket == nil then
                                complete = false
                            elseif trinket then
                                tankList[#tankList + 1] = id
                                addedBy[tankSpec] = addedBy[tankSpec] or {}
                                addedBy[tankSpec][id] = true
                                have[id] = true
                                added = added + 1
                            end
                        end
                    end
                end
            end
        end
    end
    if complete then
        done[pools] = true
    end
    return added, complete
end

local slotCache = {}
local function IsTrinketItem(itemID)
    local v = slotCache[itemID]
    if v ~= nil then
        return v
    end
    local equipLoc = select(4, C_Item.GetItemInfoInstant(itemID))
    if equipLoc == nil then
        return nil
    end
    v = equipLoc == "INVTYPE_TRINKET"
    slotCache[itemID] = v
    return v
end

-- Runs over every raid boss (each difficulty) and dungeon of the loaded season data. Safe to
-- call again: lists that were finished are skipped, the others are retried.
function TankTrinkets.Run()
    local sd = VCA.SeasonData
    if not (sd and C_Item and C_Item.GetItemInfoInstant) then
        return 0
    end
    local total = 0
    for _, raid in pairs(sd.raids or {}) do
        for diff, pools in pairs(raid.bySpec or {}) do
            total = total + TankTrinkets.Augment(pools, IsTrinketItem)
        end
    end
    for _, dungeon in pairs(sd.dungeons or {}) do
        total = total + TankTrinkets.Augment(dungeon.bySpec, IsTrinketItem)
    end
    return total
end

pcall(TankTrinkets.Run)
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    pcall(TankTrinkets.Run)
end)
