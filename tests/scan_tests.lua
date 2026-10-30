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
VCA5.Data = {
    IsObtained = function(ct, src, diff, spec, item) return marked[ct .. "|" .. src .. "|" .. diff .. "|" .. spec .. "|" .. item] == true end,
    SetObtained = function(ct, src, diff, spec, item, v) marked[ct .. "|" .. src .. "|" .. diff .. "|" .. spec .. "|" .. item] = v end
}
local equipped = {[1] = 1, [2] = 500, [3] = 2}
local popup
_G.CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
_G.DEFAULT_CHAT_FRAME = {AddMessage = function() end}
_G.GetInventoryItemID = function(_, slot) return equipped[slot] end
_G.NUM_BAG_SLOTS = 0
_G.C_Container = {GetContainerNumSlots = function() return 0 end, GetContainerItemID = function() end}
_G.C_Item = {
    GetItemInfoInstant = function(id) return id, "", "", id == 500 and "INVTYPE_TRINKET" or "INVTYPE_HEAD" end,
    GetItemNameByID = function(id) return "Item" .. id end
}
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(name, text) popup = {dialog = StaticPopupDialogs[name], text = text} end
_G.ACCEPT, _G.CANCEL = "Accept", "Cancel"
assert(loadfile("Core/VoidcacheScan.lua"))("addon", VCA5)
local Scan = VCA5.VoidcacheScan

test("Scan owned: lists the items to mark, skips trinkets and waits for confirmation", function()
    popup = nil
    local n = Scan.Owned()
    assert(n == 3, n)
    assert(popup and popup.text:find("Item1") and popup.text:find("Item2"))
    assert(not popup.text:find("Item500"), "trinkets are skipped")
    assert(next(marked) == nil, "nothing is saved before accepting")
end)
test("Scan owned: accepting saves the marks for the loot spec only", function()
    popup.dialog.OnAccept()
    assert(marked["MYTHIC_PLUS|10|23|70|1"] and marked["MYTHIC_PLUS|10|23|70|2"] and marked["RAID|20|15|70|2"])
    assert(marked["MYTHIC_PLUS|10|23|70|500"] == nil, "trinket is not marked")
    assert(marked["RAID|20|15|70|3"] == nil, "an item you do not have is not marked")
end)
test("Scan owned: cancelling saves nothing", function()
    for k in pairs(marked) do marked[k] = nil end
    Scan.Owned()
    popup.dialog.OnCancel()
    assert(next(marked) == nil)
end)
