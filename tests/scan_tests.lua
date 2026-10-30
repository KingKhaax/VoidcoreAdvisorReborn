local VCA5 = {
    CHAR_DB_NAME = "CharDB",
    ContentType = {RAID = "RAID", MYTHIC_PLUS = "MYTHIC_PLUS"},
    MythicPlusEJDifficulty = 23,
    SeasonData = {
        dungeons = {[10] = {bySpec = {[70] = {1, 500, 2}}}},
        raids = {[20] = {bySpec = {[15] = {[70] = {2, 3}}}}}
    },
    SpecInfo = {GetEffectiveLootSpecID = function() return 70 end},
    L = setmetatable({}, {__index = function(_, k) return k .. " %d" end})
}
local marked = {}
local function key(ct, src, diff, spec, item)
    return ct .. "|" .. src .. "|" .. diff .. "|" .. spec .. "|" .. item
end
VCA5.Data = {
    IsObtained = function(ct, src, diff, spec, item) return marked[key(ct, src, diff, spec, item)] == true end,
    SetObtained = function(ct, src, diff, spec, item, v) marked[key(ct, src, diff, spec, item)] = v end
}
local equipped = {[1] = 1, [2] = 500, [3] = 2}
local shown
VCA5.ScanSelect = {Show = function(rows, header, onApply, onCancel)
    shown = {rows = rows, header = header, onApply = onApply, onCancel = onCancel}
end}
_G.CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
_G.DEFAULT_CHAT_FRAME = {AddMessage = function() end}
_G.GetInventoryItemID = function(_, slot) return equipped[slot] end
_G.NUM_BAG_SLOTS = 0
_G.C_Container = {GetContainerNumSlots = function() return 0 end, GetContainerItemID = function() end}
_G.C_Item = {
    GetItemInfoInstant = function(id) return id, "", "", id == 500 and "INVTYPE_TRINKET" or "INVTYPE_HEAD" end,
    GetItemNameByID = function(id) return "Item" .. id end
}
_G.EJ_GetInstanceInfo = function(id) return "Dungeon" .. id end
_G.EJ_GetEncounterInfo = function(id) return "Boss" .. id end
_G.GetSpecializationInfoByID = function(id) return id, "Spec" .. id end
assert(loadfile("Core/VoidcacheScan.lua"))("addon", VCA5)
local Scan = VCA5.VoidcacheScan

local function rowFor(itemID, source)
    for _, r in ipairs(shown.rows) do
        if r.itemID == itemID and r.source == source then
            return r
        end
    end
end

test("Scan owned: nothing is marked until the player ticks it, and trinkets are not offered", function()
    shown = nil
    Scan.Owned()
    assert(shown, "the selection window is shown")
    assert(next(marked) == nil, "nothing is saved before the player chooses")
    assert(rowFor(1, "Dungeon10") and rowFor(2, "Dungeon10") and rowFor(2, "Boss20"))
    assert(rowFor(500, "Dungeon10") == nil, "trinkets are skipped")
    assert(rowFor(3, "Boss20") == nil, "an item you do not have is not offered")
end)
test("Scan owned: only the ticked rows are saved, for the loot spec only", function()
    shown.onApply(rowFor(2, "Dungeon10").entries)
    assert(marked[key("MYTHIC_PLUS", 10, 23, 70, 2)] == true)
    assert(marked[key("MYTHIC_PLUS", 10, 23, 70, 1)] == nil, "unticked items stay unmarked")
    assert(marked[key("RAID", 20, 15, 70, 2)] == nil, "another boss is a different row")
end)
test("Scan owned: items already marked are not offered again", function()
    shown = nil
    Scan.Owned()
    assert(rowFor(2, "Dungeon10") == nil and rowFor(1, "Dungeon10"))
end)
test("Scan owned: choosing nothing saves nothing", function()
    for k in pairs(marked) do marked[k] = nil end
    Scan.Owned()
    shown.onApply({})
    assert(next(marked) == nil)
end)
test("Scan owned: closing the window saves nothing", function()
    for k in pairs(marked) do marked[k] = nil end
    Scan.Owned()
    shown.onCancel()
    assert(next(marked) == nil)
end)
test("Scan owned: if the window fails to open, nothing is saved", function()
    for k in pairs(marked) do marked[k] = nil end
    local real = VCA5.ScanSelect.Show
    VCA5.ScanSelect.Show = function() error("boom") end
    Scan.Owned()
    VCA5.ScanSelect.Show = real
    assert(next(marked) == nil)
end)

test("Scan tooltip parser: item names are found whatever the marker or the line they start on", function()
    local function lines(...) local t = {} for i, text in ipairs({...}) do t[i] = {leftText = text} end return {lines = t} end
    local tip = lines("Nebulous Voidcache", "a", "b", "c", "d", "|cff00ff00- Sword of Tests|r", "• Helm of Tests", "  Ring of Tests  ", "|TInterface/x:0|t - Cloak of Tests")
    local parsed = Scan.ParseTooltip(tip, #tip.lines)
    assert(parsed["Sword of Tests"] and parsed["Helm of Tests"] and parsed["Ring of Tests"] and parsed["Cloak of Tests"])
    assert(Scan.ParseTooltip(lines("one", "two"), 2) == nil, "a thin tooltip is not read")
end)
