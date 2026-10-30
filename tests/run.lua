-- Automated tests for the probability and planner math.
-- Run from the addon folder with:  lua tests/run.lua
-- They load Core/Probability.lua and Core/Planner.lua with a tiny fake of the game API.
local failures, total = 0, 0
local function test(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok then
        print("ok   " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
local function near(a, b)
    return math.abs(a - b) < 1e-9
end

-- Fake pools: spec 1 can roll items 1-4, spec 2 items 3-8.
local pools = {[1] = {1, 2, 3, 4}, [2] = {3, 4, 5, 6, 7, 8}}
local obtained, selected, priorities = {}, {}, {}

local VCA = {
    CHAR_DB_NAME = "CharDB",
    VOIDCORE_CURRENCY_ID = 1,
    ContentType = {RAID = "RAID", MYTHIC_PLUS = "MYTHIC_PLUS"},
    Difficulty = {RAID_HEROIC = 15, RAID_MYTHIC = 16},
    MythicPlusEJDifficulty = 23,
    VoidcoreCost = {RAID = 1, MYTHIC_PLUS = 1},
    SeasonData = {raids = {[100] = {}}, dungeonInstanceIDs = {}},
    SpecInfo = {
        GetPlayerSpecs = function()
            return {{specID = 1, name = "One", classID = 1, icon = 0, role = "DAMAGER", specIndex = 1},
                    {specID = 2, name = "Two", classID = 1, icon = 0, role = "DAMAGER", specIndex = 2}}
        end
    },
    LootPool = {GetItemsForSpec = function(_, _, _, _, specID) return pools[specID] end},
    Data = {
        IsObtainedForKeyTier = function(_, _, _, specID, itemID) return obtained[specID .. ":" .. itemID] == true end,
        GetSelectedItems = function() return selected end,
        GetBonusRollLog = function() return {} end
    }
}
_G.CharDB = {priority = priorities}
_G.time = os.time
_G.EJ_GetEncounterInfo = function() return "Test Boss", nil, nil, nil, nil, 1 end
_G.EJ_GetInstanceInfo = function() return "Test Raid" end

assert(loadfile("Core/Probability.lua"))("addon", VCA)
assert(loadfile("Core/Planner.lua"))("addon", VCA)
local P = VCA.Probability
local Planner = VCA.Planner

test("AtLeastOne: one roll equals 1/pool", function()
    assert(near(Planner.AtLeastOne(10, 1, 1), 0.1))
    assert(near(Planner.AtLeastOne(10, 3, 1), 0.3))
end)
test("AtLeastOne: grows without replacement", function()
    assert(near(Planner.AtLeastOne(4, 2, 2), 1 - (2 / 4) * (1 / 3)))
end)
test("AtLeastOne: certain when more rolls than other items", function()
    assert(near(Planner.AtLeastOne(5, 2, 4), 1))
    assert(near(Planner.AtLeastOne(5, 5, 1), 1))
end)
test("AtLeastOne: nothing wanted or no rolls", function()
    assert(Planner.AtLeastOne(5, 0, 3) == 0)
    assert(Planner.AtLeastOne(5, 2, 0) == 0)
    assert(Planner.AtLeastOne(0, 0, 0) == 0)
end)
test("ExpectedRollsForAll", function()
    assert(near(Planner.ExpectedRollsForAll(10, 1), 5.5))
    assert(near(Planner.ExpectedRollsForAll(10, 10), 10))
end)

test("CalculateForSpec without a choice", function()
    local r = P.CalculateForSpec("RAID", 100, 15, 1, 1)
    assert(r.baseCount == 4 and r.remainingCount == 4 and near(r.remainingOdds, 0.25))
end)
test("CalculateForSpec shrinks the pool when items are obtained", function()
    obtained["1:1"] = true
    local r = P.CalculateForSpec("RAID", 100, 15, 1, 1)
    assert(r.remainingCount == 3 and near(r.remainingOdds, 1 / 3))
    obtained["1:1"] = nil
end)
test("CalculateForSpec with a choice", function()
    local r = P.CalculateForSpec("RAID", 100, 15, 1, 2, nil, {[3] = true, [8] = true})
    assert(r.baseCount == 2 and near(r.remainingOdds, 2 / 6))
end)
test("Ranking: the smaller pool is better", function()
    local ranks = P.RankCurrentPlayerSpecsForItems({3, 4}, "RAID", 100, 15)
    assert(ranks[1].specID == 1 and ranks[2].specID == 2, "order")
    assert(near(ranks[1].selectedOdds, 2 / 4) and near(ranks[2].selectedOdds, 2 / 6))
end)
test("Ranking: when no spec loots every chosen item, the ones covering the most are used", function()
    local ranks = P.RankCurrentPlayerSpecsForItems({1, 5}, "RAID", 100, 15)
    assert(not ranks[1].noItems and ranks[1].matchCount == 1 and ranks[1].selectedOdds > 0)
end)
test("Ranking: a spec that covers fewer chosen items goes last", function()
    local ranks = P.RankCurrentPlayerSpecsForItems({3, 4}, "RAID", 100, 15)
    P.MarkCoverage({{matchCount = 2}, {matchCount = 1}, {matchCount = 0}}, 3)
    local r = {{matchCount = 2}, {matchCount = 1}, {matchCount = 0}}
    P.MarkCoverage(r, 3)
    assert(not r[1].noItems and r[2].noItems and r[3].noItems)
    local none = {{matchCount = 0}}
    P.MarkCoverage(none, 2)
    assert(none[1].noItems)
end)
test("Ranking: obtained items leave the pool", function()
    obtained["1:2"], obtained["1:4"] = true, true
    local ranks = P.RankCurrentPlayerSpecsForItems({3}, "RAID", 100, 15)
    obtained["1:2"], obtained["1:4"] = nil, nil
    assert(ranks[1].specID == 1 and near(ranks[1].selectedOdds, 1 / 2))
end)
test("Priorities: the spec with the best-in-slot items comes first", function()
    -- item 3 is only wanted as an alternative, item 8 is best in slot (spec 2 only)
    priorities[3] = 2
    local ranks = P.RankCurrentPlayerSpecsForItems({3, 8}, "RAID", 100, 15)
    -- only spec 2 can loot both, so it is the only one without noItems
    assert(ranks[1].specID == 2)
    priorities[3] = nil
end)
test("Priority weights", function()
    assert(Planner.Weight(99) == 1)
    Planner.SetPriority(99, 2)
    assert(Planner.Weight(99) == 0.5 and Planner.HasPriorities())
    Planner.SetPriority(99, nil)
    assert(not Planner.HasPriorities())
end)
test("NextBest lists a boss with chosen items", function()
    selected[3], selected[4] = true, true
    local list = Planner.NextBest(15)
    selected[3], selected[4] = nil, nil
    assert(#list == 1 and list[1].name == "Test Boss" and near(list[1].odds, 0.5) and list[1].pool == 4)
end)
test("NextBest is empty without a choice", function()
    assert(#Planner.NextBest(15) == 0)
end)

_G.test, _G.near = test, near
dofile("tests/data_tests.lua")
dofile("tests/tools_tests.lua")
dofile("tests/tank_tests.lua")
dofile("tests/scan_tests.lua")
dofile("tests/gear_tests.lua")

print(string.format("%d tests, %d failed", total, failures))
os.exit(failures == 0 and 0 or 1)
