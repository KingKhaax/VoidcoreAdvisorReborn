-- Tests of the saved-data layer (Core/Data.lua, the real file) and of the roll log.
-- Loaded by tests/run.lua, which provides test() and near().
local VCA2 = {
    CHAR_DB_NAME = "CharDB2",
    ContentType = {RAID = "RAID", MYTHIC_PLUS = "MYTHIC_PLUS"},
    Difficulty = {RAID_HEROIC = 15},
    SpecInfo = {GetPlayerClassID = function() return 1 end},
    LootPool = {GetItemsForSpec = function() return {1, 2, 3, 4} end}
}
_G.CharDB2 = {obtained = {}, selectedItems = {}, bonusRollLog = {}}
assert(loadfile("Core/Data.lua"))("addon", VCA2)
local Data = VCA2.Data

test("Data: mark and unmark an item", function()
    Data.SetObtained("RAID", 100, 15, 1, 7, true)
    assert(Data.IsObtained("RAID", 100, 15, 1, 7))
    assert(not Data.IsObtained("RAID", 100, 15, 2, 7))
    Data.SetObtained("RAID", 100, 15, 1, 7, false)
    assert(not Data.IsObtained("RAID", 100, 15, 1, 7))
end)
test("Data: key tiers (M+) count tier-less marks for both tiers", function()
    Data.SetObtainedForKeyTier("MYTHIC_PLUS", 5, 23, 1, 9, nil, true)
    assert(Data.IsObtainedForKeyTier("MYTHIC_PLUS", 5, 23, 1, 9, true))
    assert(Data.IsObtainedForKeyTier("MYTHIC_PLUS", 5, 23, 1, 9, false))
    Data.SetObtained("MYTHIC_PLUS", 5, 23, 1, 9, false)
    Data.SetObtainedForKeyTier("MYTHIC_PLUS", 5, 23, 1, 9, true, true)
    assert(Data.IsObtainedForKeyTier("MYTHIC_PLUS", 5, 23, 1, 9, true))
    assert(not Data.IsObtainedForKeyTier("MYTHIC_PLUS", 5, 23, 1, 9, false))
    Data.ClearSourceForKeyTier("MYTHIC_PLUS", 5, 23, nil, true)
    assert(not Data.IsObtainedForKeyTier("MYTHIC_PLUS", 5, 23, 1, 9, true))
end)
test("Data: ClearSource only clears the given source and spec", function()
    Data.SetObtained("RAID", 100, 15, 1, 1, true)
    Data.SetObtained("RAID", 100, 15, 2, 1, true)
    Data.SetObtained("RAID", 101, 15, 1, 1, true)
    Data.ClearSource("RAID", 100, 15, 1)
    assert(not Data.IsObtained("RAID", 100, 15, 1, 1))
    assert(Data.IsObtained("RAID", 100, 15, 2, 1))
    assert(Data.IsObtained("RAID", 101, 15, 1, 1))
    Data.ClearSource("RAID", 100, 15)
    Data.ClearSource("RAID", 101, 15)
    assert(Data.GetTotalObtainedCount() == 0)
end)
test("Data: chosen items are saved as a copy and can be removed one by one", function()
    local set = {[3] = true, [4] = true}
    Data.SaveSelectedItems("RAID", 100, 15, set)
    set[3] = nil
    assert(Data.GetSelectedItems("RAID", 100, 15)[3] == true, "stored copy")
    Data.RemoveSelectedItem("RAID", 100, 15, 3)
    assert(Data.GetSelectedItems("RAID", 100, 15)[3] == nil)
    Data.RemoveSelectedItem("RAID", 100, 15, 4)
    assert(next(Data.GetSelectedItems("RAID", 100, 15)) == nil)
end)
test("Data: the roll log keeps the last 200 entries", function()
    _G.time = os.time
    for i = 1, 205 do
        Data.LogBonusRoll(i, nil, 1, nil)
    end
    local log = Data.GetBonusRollLog()
    assert(#log == 200 and log[1].itemID == 6 and log[200].itemID == 205)
    for i = #log, 1, -1 do
        log[i] = nil
    end
end)
test("Data: a roll stores whether it was a chosen item and the odds it had", function()
    Data.SaveSelectedItems("RAID", 100, 15, {[1] = true})
    Data.SetObtained("RAID", 100, 15, 1, 2, true) -- one of 4 already obtained: pool of 3
    Data.LogBonusRoll(1, nil, 1, {sourceType = "RAID", sourceID = 100, difficultyID = 15})
    local e = Data.GetBonusRollLog()[1]
    assert(e.wanted == true, "wanted")
    assert(near(e.odds, 1 / 3), "odds " .. tostring(e.odds))
    Data.LogBonusRoll(3, nil, 1, {sourceType = "RAID", sourceID = 100, difficultyID = 15})
    assert(Data.GetBonusRollLog()[2].wanted == false)
end)

test("Data: clearing a raid item flags its roll entries so the replay does not bring it back", function()
    local log = Data.GetBonusRollLog()
    for i = #log, 1, -1 do
        log[i] = nil
    end
    log[1] = {itemID = 7, specID = 1, raidInstanceID = 50, difficultyID = 15}  -- heroic roll
    log[2] = {itemID = 7, specID = 1, raidInstanceID = 50, difficultyID = 16}  -- mythic roll of the same item
    log[3] = {itemID = 8, specID = 1, raidInstanceID = 50, difficultyID = 15}  -- another item
    log[4] = {itemID = 7, specID = 1, raidInstanceID = 60, difficultyID = 15}  -- another raid
    Data.NeutralizeRollEntriesForItem(7, "RAID", 100, 15, 50)
    assert(log[1].unmarked == true, "heroic roll flagged")
    assert(not log[2].unmarked, "mythic roll kept")
    assert(not log[3].unmarked, "other item kept")
    assert(not log[4].unmarked, "other raid kept")
    for i = #log, 1, -1 do
        log[i] = nil
    end
end)

test("Data: marks of specializations the character's class does not have are removed, per character", function()
    _G.CharDB2 = {obtained = {}, selectedItems = {}, bonusRollLog = {}}
    Data.SetObtained("RAID", 100, 15, 62, 7, true) -- a mage spec: the character's own
    Data.SetObtained("RAID", 100, 15, 253, 7, true) -- a hunter spec: left by an old bug
    Data.SetObtained("RAID", 100, 15, 0, 7, true) -- a manual mark keeps spec 0
    Data.SetObtainedForKeyTier("MYTHIC_PLUS", 5, 23, 265, 9, true, true) -- tiered key of a foreign spec
    local removed = Data.PruneForeignSpecMarks({[62] = true, [63] = true, [64] = true})
    assert(removed == 2, removed)
    assert(Data.IsObtained("RAID", 100, 15, 62, 7) and Data.IsObtained("RAID", 100, 15, 0, 7))
    assert(not Data.IsObtained("RAID", 100, 15, 253, 7) and not Data.IsObtained("MYTHIC_PLUS", 5, 23, 265, 9))
    assert(_G.CharDB2.foreignSpecBackup["RAID:100:15:253:7"], "kept as a backup")
    assert(Data.PruneForeignSpecMarks({[62] = true}) == 0, "a second run removes nothing")
    assert(Data.PruneForeignSpecMarks({}) == 0, "without knowing the specs, nothing is touched")
end)
