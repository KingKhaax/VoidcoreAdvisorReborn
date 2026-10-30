-- Loads every file of the addon with a fake game API and exercises the commands and windows.
-- Run from the addon folder with:  lua tests/smoke.lua
-- Loads every file of the addon with a fake WoW API to catch load-time errors.
local addonRoot = "./"
local errors = {}

local Dummy = {}
local mt
mt = {
    __index = function(t, k)
        if type(k) == "string" and (k:find("Width") or k:find("Height") or k:find("Left$") or k:find("Top$") or k:find("Scale") or k == "GetVerticalScroll" or k == "GetStringWidth" or k == "GetFrameLevel" or k == "GetAlpha") then
            return function() return 100 end
        end
        if k == "SetScript" then return function(self, name, fn) local t = rawget(self, "_scripts"); if not t then t = {}; rawset(self, "_scripts", t) end; t[name] = fn end end
        if k == "GetScript" then return function(self, name) local t = rawget(self, "_scripts"); return t and t[name] or nil end end
        if k == "GetNormalTexture" or k == "GetPushedTexture" or k == "GetHighlightTexture" then
            return function() return nil end
        end
        if k == "IsShown" or k == "IsVisible" or k == "IsMouseOver" then
            return function() return false end
        end
        if k == "GetText" then return function() return "" end end
        return function(self, ...) return self end
    end,
    __call = function(self, ...) return self end,
    __add = function() return 0 end, __sub = function() return 0 end, __mul = function() return 0 end,
    __div = function() return 0 end, __unm = function() return 0 end, __mod = function() return 0 end,
    __lt = function() return false end, __le = function() return false end,
    __concat = function(a, b) return tostring(type(a) == "table" and "" or a) .. tostring(type(b) == "table" and "" or b) end,
    __len = function() return 0 end,
}
local function NewDummy() return setmetatable({}, mt) end

local G = _G
local store = {}
setmetatable(G, {
    __index = function(t, k)
        if store[k] ~= nil then return store[k] end
        if type(k) == "string" and k:match("^[A-Z_0-9]+$") then store[k] = k return k end
        local d = NewDummy()
        return d
    end,
})

function CreateFrame(kind, name, ...)
    local f = NewDummy()
    if name then _G[name] = f end
    return f
end
function GetLocale() return rawget(_G, "FAKE_LOCALE") or "esES" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
function hooksecurefunc() end
function GetTime() return 0 end
function time() return 0 end
function IsShiftKeyDown() return false end
function CreateAtlasMarkup() return "" end
function InCombatLockdown() return false end
function IsInInstance() return false end
function UnitClass() return "Priest", "PRIEST", 5 end
function GetBuildInfo() return "12.1.5", "99999", "", 120105 end
function GetSpecializationInfoByID() return 62, "Arcane", "", 1 end
UIParent = NewDummy()
CreateFont = function() return NewDummy() end
LibStub = nil
DEFAULT_CHAT_FRAME = NewDummy()
function GetNumSpecializations() return 3 end
function GetSpecializationInfo(i) return 256 + i end
function GetLootSpecialization() return 0 end
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
SOUNDKIT = {RAID_WARNING = 8959}
C_AddOns = {GetAddOnMetadata = function() return "2.1.0" end, IsAddOnLoaded = function() return false end, LoadAddOn = function() end}
C_Item = setmetatable({}, {__index = function() return function() return nil end end})
C_Timer = {After = function(_, fn) end}
Settings = NewDummy()
BonusRollFrame = nil
EncounterJournal = nil
EJ_GetNumTiers = function() return 0 end
EJ_GetCurrentTier = function() return 0 end
ITEM_QUALITY_COLORS = {}
CANCEL = "Cancel"

local VCA = {}
local function run(path)
    local chunk, err = loadfile(addonRoot .. path)
    if not chunk then errors[#errors + 1] = "LOAD " .. path .. ": " .. tostring(err) return end
    local ok, e = xpcall(function() chunk("VoidcoreAdvisorReborn", VCA) end, debug.traceback)
    if not ok then errors[#errors + 1] = "RUN " .. path .. ": " .. tostring(e):sub(1, 400) end
end

for line in io.lines(addonRoot .. "VoidcoreAdvisorReborn.toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua$") then run((line:gsub("\\", "/"))) end
end

-- Exercise a few commands after load
local ok, e = pcall(function()
    VCA.ApplyTheme("purple"); VCA.ApplyTheme("blue"); VCA.ApplyTheme("green")
    assert(VCA.TitleText():find("Voidcore"), "title text")
end)
if not ok then errors[#errors + 1] = "THEME: " .. tostring(e) end

if #errors == 0 then print("SMOKE OK: all files loaded") else
    for _, e in ipairs(errors) do print(e) end
    print("SMOKE FAILED: " .. #errors .. " problems")
end

-- extra checks
local function check(name, fn) local ok, e = xpcall(fn, function(m) return debug.traceback(tostring(m),2) end) print((ok and "ok   " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(e):sub(1, 600)))) end
check("modules exist", function()
    assert(type(VCA.Missing.Show) == "function" and type(VCA.Transfer.Export) == "function" and type(VCA.OpenPanel) == "function")
    assert(type(VCA.Panel.ResetPlacement) == "function" and type(VCA.LiveRaid.Run) == "function")
end)
_G.VoidcoreAdvisorCharDB = {obtained = {["RAID:1:15:62:5"] = true, ["bad key"] = true}}
_G.VoidcoreAdvisorDB = {theme = "green"}
check("Transfer.Export", function() VCA.Transfer.Export() end)
check("OpenPanel without name", function() VCA.OpenPanel("") end)
check("OpenPanel with name", function() VCA.OpenPanel("zzz") end)
check("Missing.Refresh", function() VCA.Missing.Refresh() end)
check("slash theme", function() SlashCmdList["VOIDCOREADVISOR"]("theme purple"); assert(VCA.Theme == VCA.Themes.purple) SlashCmdList["VOIDCOREADVISOR"]("theme green") end)
check("slash help", function() SlashCmdList["VOIDCOREADVISOR"]("") end)
check("slash missing", function() SlashCmdList["VOIDCOREADVISOR"]("missing 16") end)
check("SeasonDataExtra shape", function()
    local e = VCA.SeasonDataExtra and VCA.SeasonDataExtra[1324]
    assert(e and e.instanceID == 1324 and e.mapID == 3095, "entry")
    local r = e.raids[2896]
    assert(r and #r[14] == 10 and #r[15] == 10 and #r[16] == 11, "items")
    local classes, specs = 0, 0
    for _ in pairs(r.byClass[15]) do classes = classes + 1 end
    for _ in pairs(r.bySpec[15]) do specs = specs + 1 end
    assert(classes == 13 and specs == 40, "classes/specs " .. classes .. "/" .. specs)
end)
print("COL_LOOT=" .. tostring(VCA.L["COL_LOOT"]), "forced=" .. tostring(VCA.ForcedLocale))

-- every theme must apply cleanly and define all fields
for _, key in ipairs(VCA.THEME_ORDER) do
    check("theme " .. key, function()
        VCA.ApplyTheme(key)
        local t = VCA.Theme
        for _, f in ipairs({"bg", "border", "accent", "timer", "timerBg"}) do
            assert(type(t[f]) == "table" and #t[f] == 3, f)
            for i = 1, 3 do assert(t[f][i] >= 0 and t[f][i] <= 1, f .. i .. "=" .. tostring(t[f][i])) end
        end
        assert(t.hdr:match("^|cff%x%x%x%x%x%x$") and t.title:match("^|cff%x%x%x%x%x%x$"), "hex")
        assert(VCA.ThemeLabel(key) ~= nil, "label")
    end)
end
check("slash theme old spec name falls back", function() SlashCmdList["VOIDCOREADVISOR"]("theme spec"); SlashCmdList["VOIDCOREADVISOR"]("theme mage"); SlashCmdList["VOIDCOREADVISOR"]("theme nope") end)
check("spec is no longer a theme", function() assert(not VCA.IsTheme("spec")); for _, k in ipairs(VCA.THEME_ORDER) do assert(k ~= "spec") end; assert(VCA.IsTheme("class")) end)
VCA.ApplyTheme("green")
check("slash scan", function() SlashCmdList["VOIDCOREADVISOR"]("scan"); SlashCmdList["VOIDCOREADVISOR"]("scan raid 15") end)

-- ---- outdated-raid notice: world boss entry must be ignored, a real unknown raid must warn
local printed = {}
local realPrint = print
local function runCheck(instances, tierName)
    for k in pairs(printed) do printed[k] = nil end
    function print(...) printed[#printed + 1] = table.concat({...}, " ") end
    EJ_GetNumTiers = function() return 13 end
    EJ_GetCurrentTier = function() return 13 end
    EJ_SelectTier = function() end
    EJ_GetTierInfo = function() return tierName end
    local sel
    EJ_GetInstanceByIndex = function(i) local x = instances[i]; if x then return x.id, x.name end end
    EJ_SelectInstance = function(id) sel = id end
    EJ_IsValidInstanceDifficulty = function() return true end
    EJ_GetInstanceInfo = function(id) for _, x in ipairs(instances) do if x.id == id then return x.name, "", "", "", "", "", 0, "", false, x.map end end end
    IsInInstance = function() return false end
    VCA.LootPool.IsCurrentSeasonRaid = function(id) return id == 1317 end
    VCA.LiveRaid.CheckOutdatedReset = nil
    VCA.LiveRaid.CheckOutdated()
    print = realPrint
    return #printed
end
check("outdated: world boss entry ignored", function()
    local n = runCheck({{id = 1312, name = "Midnight", map = 0}, {id = 1317, name = "Known Raid", map = 3000}}, "Midnight")
    assert(n == 0, "printed " .. n .. ": " .. tostring(printed[1]))
end)
check("outdated: world boss id 1312 ignored even with a map and another tier name", function()
    local n = runCheck({{id = 1312, name = "Midnight", map = 2000}}, "Something else")
    assert(n == 0, "printed " .. n)
end)
check("outdated: world boss with a map is ignored by name", function()
    local n = runCheck({{id = 1312, name = "Midnight", map = 2000}}, "Midnight")
    assert(n == 0, "printed " .. n)
end)
check("outdated: a real unknown raid still warns", function()
    local n = runCheck({{id = 1312, name = "Midnight", map = 0}, {id = 1999, name = "Brand New Raid", map = 3300}}, "Midnight")
    assert(n == 1, "printed " .. n)
    assert(printed[1]:find("Brand New Raid", 1, true) and not printed[1]:find("Midnight", 1, true), printed[1])
    assert(_G.VoidcoreAdvisorDB.warnedRaids and _G.VoidcoreAdvisorDB.warnedRaids[1999], "not remembered")
end)
check("theme preview toggle", function() VCA.ThemePreview.Toggle(); VCA.ThemePreview.Show(); SlashCmdList["VOIDCOREADVISOR"]("preview") end)

-- ---- staged marking: clicks only stage, saving applies, hiding discards
do
    local Panel = VCA.Panel
    local rows, toggled = Panel._s.itemRows, {}
    Panel.RefreshItemColumn = function() end
    local function newRow(id, stored)
        local row = Panel._s.GetOrCreateItemRow(rows, Panel._s.itemScrollChild)
        rawset(row.frame, "IsShown", function() return true end)
        row.frame.itemID = id
        row.checkbox.itemID = id
        row.checkbox.isObtained = stored; row.checkbox.specs = {}; row.checkbox.sourceType = "RAID"; row.checkbox.sourceID = 1; row.checkbox.diffID = 15
        row.checkbox:SetScript("OnClick", function(cb) toggled[id] = true; cb.isObtained = not cb.isObtained end)
        return row
    end
    local r1, r2, r3 = newRow(101, false), newRow(102, true), newRow(103, false)
    local function click(row) row.frame:GetScript("OnClick")(row.frame) end
    check("staged: not in mark mode, a click does not stage", function()
        Panel.markMode = false
        click(r1)
        assert(next(Panel.pendingMarks) == nil)
    end)
    check("staged: click stages a mark and nothing is saved yet", function()
        Panel.markMode = true; Panel.lastMarkItemID = nil
        click(r1)
        assert(Panel.pendingMarks[101] == true, "pending")
        assert(next(toggled) == nil, "saved too early")
    end)
    check("staged: clicking again takes the staged mark back", function()
        click(r1)
        assert(Panel.pendingMarks[101] == nil, "still pending")
    end)
    check("staged: an already obtained item stages an unmark", function()
        click(r2)
        assert(Panel.pendingMarks[102] == false)
        click(r1)
        assert(Panel.pendingMarks[101] == true)
    end)
    check("staged: saving applies only what changed", function()
        Panel.CommitPendingMarks()
        assert(toggled[101] and toggled[102] and not toggled[103], "toggled")
        assert(next(Panel.pendingMarks) == nil, "pending left")
        assert(r1.checkbox.isObtained == true and r2.checkbox.isObtained == false, "states")
    end)
    check("staged: closing the panel discards unsaved marks", function()
        Panel.markMode = true; Panel.lastMarkItemID = nil
        click(r3)
        assert(Panel.pendingMarks[103] == true)
        Panel.ClearPending()
        assert(next(Panel.pendingMarks) == nil and Panel.markMode == false)
        assert(not toggled[103], "saved by mistake")
    end)
end

check("FormatTimer", function()
    assert(VCA.FormatTimer(154) == "2:34", VCA.FormatTimer(154))
    assert(VCA.FormatTimer(59.6) == "1:00", VCA.FormatTimer(59.6))
    assert(VCA.FormatTimer(0) == "0:00" and VCA.FormatTimer(-5) == "0:00" and VCA.FormatTimer(nil) == "0:00")
    assert(VCA.FormatTimer(5) == "0:05" and VCA.FormatTimer(3600) == "60:00")
end)
check("preview countdown runs", function()
    local f = _G.VCAThemePreviewFrame
    local fn = f:GetScript("OnUpdate")
    assert(type(fn) == "function", "no OnUpdate")
    fn(f, 0.5); fn(f, 200)
end)

check("roll window palette follows rollTheme", function()
    _G.VoidcoreAdvisorDB.rollTheme = "fire"
    VCA.ApplyTheme("green")
    assert(VCA.GetPalette("fire") == VCA.Themes.fire)
    assert(VCA.GetPalette("current") == VCA.Theme and VCA.GetPalette(nil) == VCA.Theme)
    assert(VCA.GetPalette("class") ~= nil and VCA.GetPalette("zzz") == VCA.Theme)
    _G.VoidcoreAdvisorDB.rollTheme = "class"
end)
check("preview window starts on the current theme, arrows are not saved", function()
    VCA.ThemePreview.SetTheme("frost"); assert(VCA.ThemePreview.GetTheme() == "frost")
    VCA.ThemePreview.SetTheme("nope"); assert(VCA.ThemePreview.GetTheme() == "current")
    assert(_G.VoidcoreAdvisorDB.previewTheme == nil)
end)

-- ---- reminder in front of raid bosses
do
    local ejInst = VCA.SeasonData.raids[2895].instanceID
    local asked
    VCA.Data.GetSelectedItems = function(st, id, diff) asked = {st, id, diff}; return {} end
    VCA.LootPool.IsSeasonFilterReady = function() return true end
    VCA.LootPool.GetSeasonRaidByMapID = function() return ejInst end
    VCA.LootPool.GetSeasonRaidByName = function() return nil end
    VCA.EligibleRaidDifficulties = {[14] = true, [15] = true, [16] = true}
    C_CurrencyInfo = {GetCurrencyInfo = function() return {quantity = 5} end}
    local names = {[2895] = "Ula'tek", [2888] = "The Twin Fangs"}
    EJ_GetEncounterInfo = function(id) return names[id] end
    EJ_GetCreatureInfo = function(i, id) if id == 2888 and i == 1 then return 1, "Zemxora" end end
    local unit = {name = "Ula'tek", class = "worldboss", dead = false, player = false, exists = true}
    function UnitExists() return unit.exists end
    function UnitIsDead() return unit.dead end
    function UnitIsPlayer() return unit.player end
    function UnitClassification() return unit.class end
    function UnitName() return unit.name end
    local inst = {"Venenoso", "raid", 15, "", 0, 0, false, 3004}
    function GetInstanceInfo() return table.unpack(inst) end
    _G.VoidcoreAdvisorDB = {reminderEnabled = true, reminderBossEnabled = true, theme = "green"}
    local function try(setup)
        asked = nil; unit.name = "Ula'tek"; unit.class = "worldboss"; unit.dead = false; unit.player = false; unit.exists = true
        inst[2] = "raid"; inst[3] = 15
        setup()
        VCA.Reminder.ForceEvaluate()
        VCA.Reminder.EvaluateBoss()
        return asked
    end
    check("boss reminder: targeting a boss looks up its selected items", function()
        local a = try(function() end)
        assert(a and a[1] == "RAID" and a[2] == 2895 and a[3] == 15, a and (a[1] .. a[2]) or "not asked")
    end)
    check("boss reminder: a council creature name finds its encounter", function()
        local a = try(function() unit.name = "Zemxora" end)
        assert(a and a[2] == 2888, a and a[2] or "not asked")
    end)
    check("boss reminder: not a boss (trash) is ignored", function()
        assert(try(function() unit.class = "elite" end) == nil)
    end)
    check("boss reminder: unknown name is ignored", function()
        assert(try(function() unit.name = "Someone Else" end) == nil)
    end)
    check("boss reminder: only inside a raid", function()
        assert(try(function() inst[2] = "party" end) == nil)
    end)
    check("boss reminder: off switch", function()
        _G.VoidcoreAdvisorDB.reminderBossEnabled = false
        assert(try(function() end) == nil)
        _G.VoidcoreAdvisorDB.reminderBossEnabled = true
    end)
end

check("reborn title is gold and uses the palette", function()
    local s = VCA.RebornTitle("|cff8fe36bVoidcore|r|cffffffffAdvisor|r", VCA.Themes.fire)
    assert(s:find(VCA.Themes.fire.title, 1, true) and s:find("|cffffd100Reborn|r", 1, true), s)
end)
check("reminder example opens", function() VCA.Reminder.ShowExample(); VCA.Reminder.Hide() end)

-- ---- new tools
do
    local T = VCA.Tools
    check("Planner.AtLeastOne", function()
        local P = VCA.Planner
        assert(P.AtLeastOne(10, 1, 1) == 0.1 or math.abs(P.AtLeastOne(10, 1, 1) - 0.1) < 1e-9)
        assert(math.abs(P.AtLeastOne(10, 1, 10) - 1) < 1e-9)
        assert(P.AtLeastOne(0, 0, 3) == 0)
        assert(math.abs(P.AtLeastOne(4, 2, 2) - (1 - (2 / 4) * (1 / 3))) < 1e-9)
        assert(math.abs(P.ExpectedRollsForAll(10, 1) - 5.5) < 1e-9)
    end)
    check("Tools.ParseItemIDs", function()
        local ids = T.ParseItemIDs("|Hitem:280617::::|h[x]|h, 281029 id=281215 12 2026")
        assert(#ids == 3, #ids)
    end)
    _G.GetNumSavedInstances = function() return 0 end
    _G.EJ_GetEncounterInfo = function() return "Boss" end
    _G.EJ_GetInstanceInfo = function() return "Place" end
    _G.date = date
    for _, name in ipairs({"Cores", "Next", "History", "Chars", "Debug", "Wish", "Perf"}) do
        check("Tools." .. name, function() T[name]() end)
    end
    check("Tools.Priority list", function() T.Priority("") end)
    check("Tools.Priority set", function() T.Priority("item:280617 bis"); assert(VCA.Planner.GetPriority(280617) == 1) end)
    check("Tools.SelectAll without source", function() T.SelectAll(false) end)
    check("Planner.SaveCharacterSummary", function() VCA.Planner.SaveCharacterSummary() end)
    check("Banner", function() VCA.Banner("hi") end)
end

-- ---- detection: finishing a spec's pool resets every spec of that boss
do
    local D = VCA.Detection
    check("Detection.CheckAndResetIfComplete resets only the spec whose pool is complete", function()
        _G.VoidcoreAdvisorCharDB = {obtained = {}}
        VCA.SpecInfo.GetPlayerClassID = function() return 10 end
        VCA.LootPool.GetItemsForSpec = function() return {1, 2} end
        local src = {sourceType = "RAID", sourceID = 900, difficultyID = 15}
        VCA.Data.SetObtained("RAID", 900, 15, 268, 1, true)
        VCA.Data.SetObtained("RAID", 900, 15, 269, 1, true)
        assert(D.CheckAndResetIfComplete(src, 268, nil) == false, "incomplete")
        assert(VCA.Data.IsObtained("RAID", 900, 15, 269, 1), "kept")
        VCA.Data.SetObtained("RAID", 900, 15, 268, 2, true)
        assert(D.CheckAndResetIfComplete(src, 268, nil) == true, "complete")
        assert(not VCA.Data.IsObtained("RAID", 900, 15, 268, 1), "the finished spec is reset")
        assert(VCA.Data.IsObtained("RAID", 900, 15, 269, 1), "the other spec keeps its marks")
    end)
end

-- ---- settings window
do
    check("Settings window opens every tab", function()
        _G.VoidcoreAdvisorDB.showCumulative = nil
        for i = 1, 4 do VCA.SettingsWindow.Open(i) end
        VCA.SettingsWindow.Toggle()
        VCA.SettingsWindow.Toggle()
        VCA.SettingsWindow.Hide()
    end)
    check("/void open uses the settings window", function()
        SlashCmdList["VOIDCOREADVISOR"]("open")
    end)
end

check("Settings window has the version tab", function()
    VCA.SettingsWindow.Open(5)
    VCA.SettingsWindow.Hide()
end)

check("Bonus roll window preview lays out", function()
    VCA.BonusRollConfirm.ShowPreview()
    VCARollWindow:Hide()
end)

check("Bonus roll window preview lays out in every layout", function()
    for id = 1, VCA.BonusRollConfirm.LAYOUT_COUNT do
        _G.VoidcoreAdvisorDB.rollLayout = id
        assert(VCA.BonusRollConfirm.GetLayoutID() == id)
        VCA.BonusRollConfirm.ShowPreview()
    end
    _G.VoidcoreAdvisorDB.rollLayout = 1
    VCARollWindow:Hide()
end)

check("Settings window follows its own theme", function()
    for _, theme in ipairs({"green", "current", "fire"}) do
        _G.VoidcoreAdvisorDB.settingsTheme = theme
        VCA.ApplyTheme(_G.VoidcoreAdvisorDB.theme)
    end
    _G.VoidcoreAdvisorDB.settingsTheme = "green"
    VCA.SettingsWindow.Open(1)
    VCA.SettingsWindow.Hide()
end)

check("Fonts: list, choose and restore", function()
    local list = VCA.Fonts.List()
    assert(#list >= 5 and list[1] == "Source Sans 3")
    assert(VCA.Fonts.Resolve("Source Sans 3"))
    assert(VCA.Fonts.Resolve("nope") == nil)
    VCA.Fonts.Choose("Arial Narrow")
    assert(VCA.Fonts.Current() == "Arial Narrow")
    VCA.Fonts.Choose("default")
    assert(VCA.Fonts.Current() == nil)
end)
check("Settings window font list opens", function()
    VCA.SettingsWindow.Open(1)
    VCA.SettingsWindow.Hide()
end)

check("Raid overview: the slot section refreshes", function()
    VCA.RaidOverview.RefreshSlots()
    assert(VCA.RaidOverview.SLOT_SECTION_H and VCA.RaidOverview.SLOT_SECTION_H > 60)
end)

check("Replay: a roll without difficulty is marked on its own difficulty only", function()
    local oldInfo = C_Item.GetDetailedItemLevelInfo
    C_Item.GetDetailedItemLevelInfo = function(link)
        if link:find(":7359:") then return 321 end
        if link:find(":7363:") then return 334 end
        if link:find(":7362:") then return 344 end
        return tonumber(link:match("ilvl=(%d+)"))
    end
    local lvl = VCA.Detection.GetItemLevel("x ilvl=334")
    assert(lvl == 334, tostring(lvl))
    assert(VCA.Detection.ResolveEntryDifficulty({itemLink = "x ilvl=334"}) == 15)
    assert(VCA.Detection.ResolveEntryDifficulty({itemLink = "x ilvl=344"}) == 16)
    assert(VCA.Detection.ResolveEntryDifficulty({itemLink = "x ilvl=200"}) == nil, "far level is not guessed")
    assert(VCA.Detection.ResolveEntryDifficulty({difficultyID = 14, itemLink = "x ilvl=344"}) == 14)
    C_Item.GetDetailedItemLevelInfo = oldInfo
end)

check("Replay: the difficulty comes from the item link", function()
    local D = VCA.Detection
    assert(D.RaidDifficultyFromLink("|Hitem:268265::::::::90:269::95:5:6652:13668:13334:12849:13987::::::|h") == 15)
    assert(D.RaidDifficultyFromLink("|Hitem:268253::::::::90:269::96:4:6652:13662:13335:13848::::::|h") == 16)
    assert(D.RaidDifficultyFromLink("|Hitem:193714::::::::90:268::35:6:12801:13440:6652::::::|h") == nil)
    assert(D.ResolveEntryDifficulty({difficultyID = 16, itemLink = "|Hitem:1::::::::90:269::95:2:13334:12849::::::|h"}) == 15,
        "link wins over a wrong saved difficulty")
end)

check("Raid tooltip: an item that loses its effect gets the effect bonus", function()
    local old = _G.C_TooltipInfo
    local oldEquip, oldUse, oldProc = _G.ITEM_SPELL_TRIGGER_ONEQUIP, _G.ITEM_SPELL_TRIGGER_ONUSE, _G.ITEM_SPELL_TRIGGER_ONPROC
    _G.ITEM_SPELL_TRIGGER_ONEQUIP, _G.ITEM_SPELL_TRIGGER_ONUSE, _G.ITEM_SPELL_TRIGGER_ONPROC = "Equip:", "Use:", "Chance on hit:"
    _G.C_TooltipInfo = {
        GetItemByID = function(id)
            return {lines = {{leftText = "Name"}, {leftText = "Equip: does a thing"}}}
        end,
        GetHyperlink = function(link)
            if link:find(":13708:") then
                return {lines = {{leftText = "Name"}, {leftText = "Equip: does a thing"}}}
            end
            return {lines = {{leftText = "Name"}}}
        end
    }
    local sample = "|cnIQ3:|Hitem:999001::::::::90:104::5:1:3524:1:28:7363:::::|h[X]|h|r"
    local link = VCA.Panel.BuildRaidTooltipLink(sample, 15, 1)
    assert(link:find(":13708:"), link)
    -- an item that keeps its effect is left alone
    _G.C_TooltipInfo.GetHyperlink = function() return {lines = {{leftText = "Equip: does a thing"}}} end
    local link2 = VCA.Panel.BuildRaidTooltipLink(sample:gsub("999001", "999002"), 15, 1)
    assert(not link2:find(":13708:"), link2)
    -- tooltip data not available yet: nothing is decided
    _G.C_TooltipInfo.GetHyperlink = function() return nil end
    local link3 = VCA.Panel.BuildRaidTooltipLink(sample:gsub("999001", "999003"), 15, 1)
    assert(not link3:find(":13708:"), link3)
    _G.C_TooltipInfo = old
    _G.ITEM_SPELL_TRIGGER_ONEQUIP, _G.ITEM_SPELL_TRIGGER_ONUSE, _G.ITEM_SPELL_TRIGGER_ONPROC = oldEquip, oldUse, oldProc
end)

check("Report: rich rows with item links", function()
    VCA.Report.Show("Test", "first\n\nsecond item", {rich = true, links = {[3] = "item:19019"}})
    VCA.Report.Show("Test", "only one line", {rich = true})
    VCA.Report.Hide()
end)

check("Panel: pin button toggles between pinned and free", function()
    assert(VCA.Panel.IsPinned(), "pinned by default")
    VCA.Panel.SetPinned(false)
    assert(not VCA.Panel.IsPinned(), "free after unpinning")
    VCA.Panel.SetPinned(true)
    assert(VCA.Panel.IsPinned(), "pinned again")
    VCA.Panel.ResetPlacement()
    assert(VCA.Panel.IsPinned())
end)

check("Overviews share the pin state with the panel", function()
    VCA.Panel.SetPinned(false, VCA.RaidOverview.frame)
    assert(not VCA.Panel.IsPinned())
    VCA.Panel.SetPinned(true)
    assert(VCA.Panel.IsPinned())
    VCA.Panel.SetPinned(false, VCA.DungeonOverview.frame)
    assert(not VCA.Panel.IsPinned())
    VCA.Panel.ResetPlacement()
    assert(VCA.Panel.IsPinned())
end)
