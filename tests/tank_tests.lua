-- Tests of the tank trinket rule (Core/TankTrinkets.lua).
local VCA4 = {}
_G.CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
assert(loadfile("Core/TankTrinkets.lua"))("addon", VCA4)
local TT = VCA4.TankTrinkets

local trinkets = {[500] = true, [501] = true} -- 500 and 501 are trinkets, 600 is armor
local function isTrinket(id)
    if id == 999 then
        return nil
    end
    return trinkets[id] == true
end

test("Tank trinkets: a tank gets the damage trinkets of its class, not the armor", function()
    local pools = {[66] = {1, 2}, [70] = {1, 500, 600}, [65] = {700}}
    local added = TT.Augment(pools, isTrinket)
    assert(added == 1, added)
    assert(#pools[66] == 3 and pools[66][3] == 500)
    assert(#pools[70] == 3, "the damage spec is not changed")
end)
test("Tank trinkets: trinkets of a healer spec are not added to the tank", function()
    local pools = {[66] = {1}, [70] = {2}, [65] = {500}}
    TT.Augment(pools, isTrinket)
    assert(#pools[66] == 1)
end)
test("Tank trinkets: every damage spec of the class is used (warrior)", function()
    local pools = {[73] = {}, [71] = {500}, [72] = {501, 600}}
    assert(TT.Augment(pools, isTrinket) == 2)
    assert(#pools[73] == 2)
end)
test("Tank trinkets: an item already in the tank list is not repeated", function()
    local pools = {[66] = {500}, [70] = {500}}
    assert(TT.Augment(pools, isTrinket) == 0 and #pools[66] == 1)
end)
test("Tank trinkets: running twice adds nothing more", function()
    local pools = {[66] = {1}, [70] = {500}}
    TT.Augment(pools, isTrinket)
    assert(TT.Augment(pools, isTrinket) == 0 and #pools[66] == 2)
end)
test("Tank trinkets: unknown items are retried later", function()
    local pools = {[66] = {1}, [70] = {999, 500}}
    local added, complete = TT.Augment(pools, isTrinket)
    assert(complete == false and added == 1)
    local added2, complete2 = TT.Augment(pools, function(id) return id == 999 or trinkets[id] == true end)
    assert(complete2 == true and added2 == 1 and #pools[66] == 3)
end)

test("Tank trinkets: IsAdded tells the trinkets the addon added from the ones the game lists", function()
    local pools = {[66] = {1}, [70] = {500, 1}}
    TT.Augment(pools, isTrinket)
    assert(TT.IsAdded(66, 500) == true)
    assert(TT.IsAdded(66, 1) == false)
    assert(TT.IsAdded(70, 500) == false)
end)
