local VCA6 = {L = {}}
local info = {
    [1] = {"INVTYPE_HEAD", 4, 4},
    [2] = {"INVTYPE_TRINKET", 4, 0},
    [3] = {"INVTYPE_2HWEAPON", 2, 1},
    [4] = {"", 15, 5},
    [5] = {"", 15, 2},
    [6] = {"INVTYPE_CLOAK", 4, 5},
    [7] = {"INVTYPE_BODY", 4, 0},
    [8] = {"", 15, 0},
    [9] = {"INVTYPE_FINGER", 4, 0}
}
_G.C_Item = {
    GetItemInfoInstant = function(id)
        local i = info[id]
        if not i then
            return nil
        end
        return id, "", "", i[1], 0, i[2], i[3]
    end
}
_G.CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
assert(loadfile("Core/GearFilter.lua"))("addon", VCA6)
local GF = VCA6.GearFilter

test("Gear filter: armor, trinkets, rings and weapons give item level", function()
    assert(GF.IsGear(1) == true and GF.IsGear(2) == true and GF.IsGear(3) == true and GF.IsGear(9) == true)
end)
test("Gear filter: mounts, pets, shirts and cosmetic armor do not; tokens are not gear but are tokens", function()
    assert(GF.IsGear(4) == false, "mount")
    assert(GF.IsGear(5) == false, "pet")
    assert(GF.IsGear(6) == false, "cosmetic cloak")
    assert(GF.IsGear(7) == false, "shirt")
    assert(GF.IsGear(8) == false, "token is not gear")
    assert(GF.IsToken(8) == true and GF.IsToken(4) == false and GF.IsToken(5) == false and GF.IsToken(1) == false)
    assert(GF.IsToken(999) == nil)
end)
test("Gear filter: raid lists keep tier tokens, except on the Ula'tek encounter, and dungeons never do", function()
    local data = {
        raids = {
            [1] = {instanceID = 5, [15] = {1, 4, 8}, byClass = {[15] = {[1] = {1, 8}}}, bySpec = {}, bonusByDiff = {}},
            [2895] = {instanceID = 5, [15] = {1, 8}, byClass = {}, bySpec = {}, bonusByDiff = {}}
        },
        dungeons = {[10] = {all = {1, 8}, byEncounter = {}, byClass = {}, bySpec = {}}}
    }
    GF.Prune(data)
    assert(table.concat(data.raids[1][15], ",") == "1,8", "token kept, mount removed")
    assert(table.concat(data.raids[1].byClass[15][1], ",") == "1,8")
    assert(table.concat(data.raids[2895][15], ",") == "1", "no token on Ula'tek")
    assert(table.concat(data.dungeons[10].all, ",") == "1", "no tokens in dungeons")
end)
test("Gear filter: an item the client does not know is kept", function()
    assert(GF.IsGear(999) == nil)
    local data = {raids = {[1] = {instanceID = 5, [15] = {1, 999}, byClass = {[15] = {[1] = {1, 999}}}, bySpec = {[15] = {[70] = {1, 999}}}, bonusByDiff = {[15] = "link"}}}, dungeons = {}}
    assert(GF.Prune(data) == 0)
    assert(#data.raids[1][15] == 2)
end)
test("Gear filter: pruning removes only non-gear from raid and dungeon lists", function()
    local data = {
        raids = {[1] = {instanceID = 5, [15] = {1, 4, 5, 2}, byClass = {[15] = {[1] = {1, 4}}}, bySpec = {[15] = {[70] = {2, 8}}}, bonusByDiff = {[15] = "link"}}},
        dungeons = {[10] = {all = {1, 4}, byEncounter = {[7] = {5, 3}}, byClass = {[1] = {1, 6}}, bySpec = {[70] = {2, 8}}}}
    }
    local removed = GF.Prune(data)
    assert(removed == 7, removed) -- the raid token (8) stays; the dungeon one goes
    assert(table.concat(data.raids[1][15], ",") == "1,2")
    assert(table.concat(data.raids[1].byClass[15][1], ",") == "1")
    assert(table.concat(data.raids[1].bySpec[15][70], ",") == "2,8")
    assert(data.raids[1].bonusByDiff[15] == "link" and data.raids[1].instanceID == 5)
    assert(table.concat(data.dungeons[10].all, ",") == "1")
    assert(table.concat(data.dungeons[10].byEncounter[7], ",") == "3")
    assert(table.concat(data.dungeons[10].byClass[1], ",") == "1")
    assert(table.concat(data.dungeons[10].bySpec[70], ",") == "2")
end)

local VCA7 = {L = {}}
assert(loadfile("Core/LiveRaid.lua"))("addon", VCA7)
local Merge = VCA7.LiveRaid.MergeEncounter

test("Audit merge: adds the missing items to every list and never removes any", function()
    local existing = {[15] = {1, 2}, byClass = {[15] = {[1] = {1}}}, bySpec = {[15] = {[70] = {1, 2}}}}
    local live = {[15] = {1, 2, 3}, byClass = {[15] = {[1] = {1, 3}, [2] = {3}}}, bySpec = {[15] = {[70] = {1, 3}, [71] = {3}}}}
    local newIDs = {}
    local added = Merge(existing, live, newIDs)
    assert(added == 1 and newIDs[3] == true, added)
    assert(table.concat(existing[15], ",") == "1,2,3")
    assert(table.concat(existing.byClass[15][1], ",") == "1,3" and table.concat(existing.byClass[15][2], ",") == "3")
    assert(table.concat(existing.bySpec[15][70], ",") == "1,2,3" and table.concat(existing.bySpec[15][71], ",") == "3")
end)
test("Audit merge: nothing missing changes nothing", function()
    local existing = {[15] = {1, 2}, byClass = {[15] = {[1] = {1}}}, bySpec = {[15] = {[70] = {2}}}}
    local live = {[15] = {2, 1}, byClass = {[15] = {[1] = {1}}}, bySpec = {[15] = {[70] = {2}}}}
    assert(Merge(existing, live) == 0)
    assert(table.concat(existing[15], ",") == "1,2")
end)
