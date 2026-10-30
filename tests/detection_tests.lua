-- Tests of the roll detection (Core/Detection.lua) with the real Core/Data.lua.
-- The loot pool is a fake that has NO warm cache: detection must work from the first roll after login.
local VCA8 = {
    CHAR_DB_NAME = "DetCharDB",
    GLOBAL_DB_NAME = "DetDB",
    ContentType = {RAID = "RAID", MYTHIC_PLUS = "MYTHIC_PLUS"},
    MythicPlusEJDifficulty = 23,
    SeasonData = {dungeons = {}, raids = {}},
    SpecInfo = {
        GetPlayerClassID = function() return 10 end,
        GetEffectiveLootSpecID = function() return 71 end
    },
    Theme = {title = "", hdr = ""},
    L = setmetatable({}, {__index = function(_, k) return k end})
}
-- spec 71 can roll items 5001 and 5002, spec 72 items 5001 and 5003
local specPools = {[71] = {5001, 5002}, [72] = {5001, 5003}}
VCA8.LootPool = {
    GetItemsForClass = function() return {5001, 5002, 5003} end,
    GetItemsForSpec = function(_, _, _, _, specID) return specPools[specID] or {} end
}
local frames, hooks = {}, {}
_G.hooksecurefunc = function(name, fn) hooks[name] = fn end
_G.CreateFrame = function()
    local f = setmetatable({}, {__index = function() return function() end end})
    f.SetScript = function(self, name, fn) self[name] = fn end
    frames[#frames + 1] = f
    return f
end
_G.C_Timer = {After = function(_, fn) fn() end}
_G.C_Item = {}
_G.IsInInstance = function() return false end
_G.GetInstanceInfo = function() return "Open world", "none", 0, "", 0, 0, false, 0 end
_G.time = _G.time or os.time
local realPrint = print
_G.DetCharDB = {obtained = {}}
assert(loadfile("Core/Data.lua"))("addon", VCA8)
assert(loadfile("Core/Detection.lua"))("addon", VCA8)
local D, Data = VCA8.Detection, VCA8.Data
local M, DUNGEON, DIFF = VCA8.ContentType.MYTHIC_PLUS, 10, 23
local detected = {}
D.SetOnItemDetectedCallback(function(itemID) detected[#detected + 1] = itemID end)
D.SetActiveSource(M, DUNGEON, DIFF, 12)

local function roll(itemID, specID)
    _G.print = function() end -- the addon chats on a roll
    for _, f in ipairs(frames) do
        if f.OnEvent then
            f.OnEvent(f, "BONUS_ROLL_RESULT", "item", "|Hitem:" .. itemID .. "::::|h[x]|h", 1, specID)
        end
    end
    _G.print = realPrint
end
local function has(specID, itemID, high)
    return Data.IsObtainedForKeyTier(M, DUNGEON, DIFF, specID, itemID, high)
end

test("Detection: a roll is marked at once, without a warm loot cache, for the rolled spec and key tier only", function()
    roll(5001, 71)
    assert(has(71, 5001, true), "marked for the rolled spec on +10 or more")
    assert(not has(71, 5001, false), "not for the lower key tier")
    assert(not has(72, 5001, true), "another spec that can get the item is not marked")
    assert(detected[1] == 5001)
end)
test("Detection: the same roll twice is marked once", function()
    roll(5001, 71)
    assert(#detected == 1)
end)
test("Detection: finishing the pool of a spec resets only that spec", function()
    roll(5001, 72)
    assert(has(72, 5001, true) and has(71, 5001, true))
    roll(5002, 71) -- spec 71 has now rolled 5001 and 5002: its cycle starts over
    assert(not has(71, 5001, true) and not has(71, 5002, true), "spec 71 starts a new cycle")
    assert(has(72, 5001, true), "spec 72 keeps its progress")
end)
test("Detection: the rolls of a finished cycle are not replayed, so a replay never wipes marks again", function()
    Data.SetObtained(M, DUNGEON, DIFF, 71, 5002, true, true) -- a mark made by hand after the reset
    _G.print = function() end
    D.ReplayBonusRollLog(false)
    _G.print = realPrint
    assert(has(71, 5002, true), "the hand mark survives the replay")
    assert(not has(71, 5001, true), "the old roll is not marked again")
end)
test("Detection: a reset is remembered and the player can undo it from the chat link", function()
    assert(DetCharDB.lastReset and next(DetCharDB.lastReset.keys), "the cleared marks were kept")
    _G.print = function() end
    hooks.SetItemRef("vcaundo:reset")
    assert(has(71, 5001, true) and has(71, 5002, true), "the marks are back")
    assert(DetCharDB.lastReset == nil, "undo is used up")
    hooks.SetItemRef("vcaundo:reset") -- a second click does nothing
    hooks.SetItemRef("item:1234") -- other links are ignored
    _G.print = realPrint
    assert(has(71, 5001, true))
end)
