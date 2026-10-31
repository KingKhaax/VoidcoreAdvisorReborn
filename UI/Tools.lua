-- VoidcoreAdvisor Reborn: Tools
-- Text reports and helpers behind /void cores, next, history, chars, debug, prio, wish
-- and select. Each one opens the Report window so the text can be read and copied.
local _, VCA = ...
local L = VCA.L

local Tools = {}
VCA.Tools = Tools

local function Say(text)
    print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. text)
end

local DIFF_NAMES = {[14] = "Normal", [15] = "Heroic", [16] = "Mythic"}

local function ItemText(itemID, link)
    if link and link ~= "" then
        return link
    end
    return C_Item.GetItemNameByID(itemID) or ("item " .. tostring(itemID))
end

-- The item with its own icon in front of it (for windows that can draw icons).
local function ItemWithIcon(itemID, link)
    local icon = itemID and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    local text = ItemText(itemID, link)
    if icon then
        return "|T" .. icon .. ":16:16:0:0|t " .. text
    end
    return text
end

local function SourceName(sourceType, sourceID)
    if not sourceID then
        return "?"
    end
    if sourceType == VCA.ContentType.RAID then
        return (EJ_GetEncounterInfo(sourceID)) or tostring(sourceID)
    end
    return (EJ_GetInstanceInfo and EJ_GetInstanceInfo(sourceID)) or tostring(sourceID)
end

-- ── /void cores ───────────────────────────────────────────────────────────────

function Tools.Cores(difficulty)
    difficulty = tonumber(difficulty) or VCA.Difficulty.RAID_HEROIC
    local Planner = VCA.Planner
    local owned = Planner.OwnedCores()
    local rolls, spent = Planner.SpentThisWeek()
    local places = Planner.NextBest(difficulty)

    local raidCores, dungeonCores, raidItems, dungeonItems = 0, 0, 0, 0
    for _, p in ipairs(places) do
        local need = Planner.ExpectedRollsForAll(p.pool, p.remaining)
        if p.kind == "RAID" then
            raidCores = raidCores + need * VCA.VoidcoreCost.RAID
            raidItems = raidItems + p.remaining
        else
            dungeonCores = dungeonCores + need * VCA.VoidcoreCost.MYTHIC_PLUS
            dungeonItems = dungeonItems + p.remaining
        end
    end

    local lines = {
        string.format(L["TOOLS_CORES_OWNED"], owned),
        string.format(L["TOOLS_CORES_SPENT"], spent, rolls),
        ""
    }
    if #places == 0 then
        lines[#lines + 1] = L["TOOLS_NO_SELECTION"]
    else
        lines[#lines + 1] = string.format(L["TOOLS_CORES_NEED_RAID"], DIFF_NAMES[difficulty] or difficulty, raidItems,
            math.ceil(raidCores))
        lines[#lines + 1] = string.format(L["TOOLS_CORES_NEED_DUNGEON"], dungeonItems, math.ceil(dungeonCores))
        lines[#lines + 1] = ""
        local need = math.ceil(raidCores + dungeonCores)
        if need > owned then
            lines[#lines + 1] = string.format(L["TOOLS_CORES_SHORT"], need - owned)
        else
            lines[#lines + 1] = L["TOOLS_CORES_ENOUGH"]
        end
        lines[#lines + 1] = L["TOOLS_CORES_NOTE"]
    end
    VCA.Report.Show(L["TOOLS_CORES_TITLE"], table.concat(lines, "\n"),
        {footer = L["TOOLS_CORES_USAGE"]})
end

-- ── /void next ────────────────────────────────────────────────────────────────

function Tools.Next(difficulty)
    difficulty = tonumber(difficulty) or VCA.Difficulty.RAID_HEROIC
    local places = VCA.Planner.NextBest(difficulty)
    local lines = {string.format(L["TOOLS_NEXT_HEADER"], DIFF_NAMES[difficulty] or difficulty), ""}
    if #places == 0 then
        lines[#lines + 1] = L["TOOLS_NO_SELECTION"]
    end
    for i, p in ipairs(places) do
        local tag = ""
        if p.note == "KILLED" then
            tag = "  " .. L["TOOLS_NEXT_KILLED"]
        elseif p.note == "KEY" then
            tag = "  " .. L["TOOLS_NEXT_KEY"]
        end
        local kind = p.kind == "RAID" and L["CONTENT_RAID_BOSS"] or L["CONTENT_MP_DUNGEON"]
        lines[#lines + 1] = string.format("%d. %s (%s) - %.0f%%  %s%s", i, p.name, kind, p.odds * 100,
            p.spec or "", tag)
        if i >= 25 then
            break
        end
    end
    VCA.Report.Show(L["TOOLS_NEXT_TITLE"], table.concat(lines, "\n"), {footer = L["TOOLS_NEXT_USAGE"]})
end

-- ── /void history ─────────────────────────────────────────────────────────────

function Tools.History()
    local log = VCA.Data.GetBonusRollLog() or {}
    local rolls, wanted, manual = 0, 0, 0
    local tracked = 0 -- rolls that stored whether they were a chosen item (newer entries)
    local expected, withOdds = 0, 0
    local bySource = {}
    for _, e in ipairs(log) do
        if e.manual then
            manual = manual + 1
        else
            rolls = rolls + 1
            if e.wanted ~= nil then
                tracked = tracked + 1
                if e.wanted then
                    wanted = wanted + 1
                end
            end
            if e.odds then
                expected = expected + e.odds
                withOdds = withOdds + 1
            end
            if e.sourceID then
                local name = SourceName(e.sourceType, e.sourceID)
                bySource[name] = (bySource[name] or 0) + 1
            end
        end
    end
    local lines = {string.format(L["TOOLS_HISTORY_TOTAL"], rolls, manual)}
    if rolls > 0 then
        if tracked > 0 then
            lines[#lines + 1] = string.format(L["TOOLS_HISTORY_LUCK"], wanted, tracked, wanted * 100 / tracked)
        end
        if withOdds > 0 then
            lines[#lines + 1] = string.format(L["TOOLS_HISTORY_EXPECTED"], expected, withOdds, wanted)
        end
        local topName, topCount
        for name, count in pairs(bySource) do
            if not topCount or count > topCount then
                topName, topCount = name, count
            end
        end
        lines[#lines + 1] = string.format(L["TOOLS_HISTORY_TOP"], topName, topCount)
    end
    lines[#lines + 1] = ""
    local shown = 0
    local links = {}
    for i = #log, 1, -1 do
        local e = log[i]
        shown = shown + 1
        if shown > 25 then
            break
        end
        lines[#lines + 1] = string.format("%s  %s  -  %s%s", date("%Y/%m/%d %H:%M", e.timestamp or 0),
            ItemWithIcon(e.itemID, e.itemLink), e.sourceID and SourceName(e.sourceType, e.sourceID) or L["TOOLS_HISTORY_UNKNOWN"],
            e.manual and ("  " .. L["TOOLS_HISTORY_MANUAL"]) or (e.wanted and ("  " .. L["TOOLS_HISTORY_WANTED"]) or ""))
        links[#lines] = e.itemLink or (e.itemID and ("item:" .. e.itemID)) or nil
    end
    if #log == 0 then
        lines[#lines + 1] = L["TOOLS_HISTORY_EMPTY"]
    end
    VCA.Report.Show(L["TOOLS_HISTORY_TITLE"], table.concat(lines, "\n"), {footer = L["TOOLS_HISTORY_NOTE"], rich = true, links = links})
end

-- ── /void chars ───────────────────────────────────────────────────────────────

function Tools.Chars()
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    local names = {}
    for name in pairs(gdb and gdb.characters or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    local lines = {}
    for _, name in ipairs(names) do
        local c = gdb.characters[name]
        local heroic = c.raid and c.raid[15] or {}
        local mythic = c.raid and c.raid[16] or {}
        -- The class icon replaces the class name; if this client has no atlas for it, only the name shows.
        local atlas = "classicon-" .. string.lower(c.class or "")
        local icon = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) and
                         (CreateAtlasMarkup(atlas, 16, 16) .. " ") or ""
        lines[#lines + 1] = string.format(L["TOOLS_CHARS_LINE"], icon .. name, c.cores or 0,
            heroic.remaining or 0, heroic.chosen or 0, mythic.remaining or 0, mythic.chosen or 0,
            date("%Y/%m/%d", c.updated or 0))
    end
    if #lines == 0 then
        lines[1] = L["TOOLS_CHARS_EMPTY"]
    end
    VCA.Report.Show(L["TOOLS_CHARS_TITLE"], table.concat(lines, "\n"), {footer = L["TOOLS_CHARS_NOTE"]})
end

-- ── /void debug ───────────────────────────────────────────────────────────────

VCA.DebugLog = VCA.DebugLog or {}

function VCA.LogDebug(text)
    local log = VCA.DebugLog
    log[#log + 1] = date("%H:%M:%S ") .. tostring(text)
    while #log > 30 do
        table.remove(log, 1)
    end
end

local function Count(t)
    local n = 0
    for _ in pairs(t or {}) do
        n = n + 1
    end
    return n
end

function Tools.Debug()
    local gdb = _G[VCA.GLOBAL_DB_NAME] or {}
    local cdb = _G[VCA.CHAR_DB_NAME] or {}
    local version, build, _, toc = GetBuildInfo()
    local specID = VCA.SpecInfo and VCA.SpecInfo.GetEffectiveLootSpecID and VCA.SpecInfo.GetEffectiveLootSpecID()
    local lines = {
        "VoidcoreAdvisor Reborn " .. tostring(VCA.VERSION),
        string.format("WoW %s (%s) interface %s, client language %s", version or "?", build or "?", toc or "?",
            GetLocale()),
        string.format("Class %s, loot spec %s", select(2, UnitClass("player")) or "?", tostring(specID)),
        string.format("Themes: window=%s roll=%s reminder=%s", tostring(gdb.theme), tostring(gdb.rollTheme),
            tostring(gdb.reminderTheme)),
        string.format("Season data: %d raid bosses, %d dungeons, %d extra raids saved", Count(VCA.SeasonData and
            VCA.SeasonData.raids), #(VCA.SeasonData and VCA.SeasonData.dungeonInstanceIDs or {}), Count(gdb.liveRaids)),
        string.format("Saved: %d obtained marks, %d selections, %d roll log entries", Count(cdb.obtained),
            Count(cdb.selectedItems), #(cdb.bonusRollLog or {})),
        string.format("Original VoidcoreAdvisor loaded: %s", tostring(C_AddOns and C_AddOns.IsAddOnLoaded and
            C_AddOns.IsAddOnLoaded("VoidcoreAdvisor") or false)),
        "",
        "Recent messages:"
    }
    if #VCA.DebugLog == 0 then
        lines[#lines + 1] = "(none)"
    end
    for _, text in ipairs(VCA.DebugLog) do
        lines[#lines + 1] = text
    end
    VCA.Report.Show(L["TOOLS_DEBUG_TITLE"], table.concat(lines, "\n"), {footer = L["TOOLS_DEBUG_NOTE"]})
end

-- ── /void perf ────────────────────────────────────────────────────────────────

local ADDON = "VoidcoreAdvisorReborn"

function Tools.Perf(arg)
    local getMem = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    local getCPU = (C_AddOns and C_AddOns.GetAddOnCPUUsage) or GetAddOnCPUUsage
    if (arg or ""):lower() == "reset" and ResetCPUUsage then
        ResetCPUUsage()
        Say(L["TOOLS_PERF_RESET"])
        return
    end
    if UpdateAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
    end
    local lines = {}
    if getMem then
        lines[#lines + 1] = string.format(L["TOOLS_PERF_MEMORY"], getMem(ADDON) / 1024)
    end
    local profiling = GetCVar and GetCVar("scriptProfile") == "1"
    if profiling and getCPU then
        if UpdateAddOnCPUUsage then
            UpdateAddOnCPUUsage()
        end
        lines[#lines + 1] = string.format(L["TOOLS_PERF_CPU"], getCPU(ADDON))
    else
        lines[#lines + 1] = L["TOOLS_PERF_CPU_OFF"]
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L["TOOLS_PERF_HOWTO"]
    VCA.Report.Show(L["TOOLS_PERF_TITLE"], table.concat(lines, "\n"), {footer = L["TOOLS_PERF_NOTE"]})
end

-- ── /void prio ────────────────────────────────────────────────────────────────

local PRIORITY_WORDS = {bis = 1, alt = 2}

local function ItemIDFromText(text)
    return tonumber((text or ""):match("item:(%d+)")) or tonumber((text or ""):match("(%d%d%d%d%d+)"))
end

function Tools.Priority(msg)
    local itemID = ItemIDFromText(msg)
    local word = (msg or ""):lower():match("%f[%a](bis)%f[%A]") or (msg or ""):lower():match("%f[%a](alt)%f[%A]") or
                     ((msg or ""):lower():match("%f[%a]clear%f[%A]") and "clear")
    if itemID and word then
        VCA.Planner.SetPriority(itemID, PRIORITY_WORDS[word])
        Say(string.format(L["TOOLS_PRIO_SET"], ItemText(itemID), word == "clear" and L["TOOLS_PRIO_NONE"] or
            (word == "bis" and "BiS" or "Alt")))
        if VCA.Panel and VCA.Panel.Refresh then
            VCA.Panel.Refresh()
        end
        return
    end
    local cdb = _G[VCA.CHAR_DB_NAME] or {}
    local ids = {}
    for id, p in pairs(cdb.priority or {}) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    local lines = {L["TOOLS_PRIO_HELP"], ""}
    for _, id in ipairs(ids) do
        lines[#lines + 1] = string.format("%s  -  %s", ItemText(id), cdb.priority[id] == 1 and "BiS" or "Alt")
    end
    if #ids == 0 then
        lines[#lines + 1] = L["TOOLS_PRIO_EMPTY"]
    end
    VCA.Report.Show(L["TOOLS_PRIO_TITLE"], table.concat(lines, "\n"))
end

-- ── /void wish (import a list of items) ───────────────────────────────────────

-- Every item ID found in the text: links ("item:123456"), "id=123456" and plain numbers.
-- minGain (optional, in percent): a line that also shows a gain ("+1.8%" or "1.8 %") below
-- it is skipped, so a Droptimizer list can be pasted and only the real upgrades are chosen.
-- Lines without any percentage are kept.
function Tools.ParseItemIDs(text, minGain)
    local ids, seen = {}, {}
    local function add(n)
        n = tonumber(n)
        if n and n >= 10000 and n <= 9999999 and not seen[n] then
            seen[n] = true
            ids[#ids + 1] = n
        end
    end
    for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
        local skip = false
        if minGain and minGain > 0 then
            local gain = line:match("([%+%-]?%d+%.?%d*)%s*%%")
            if gain and tonumber(gain) < minGain then
                skip = true
            end
        end
        if not skip then
            for n in line:gmatch("item:(%d+)") do
                add(n)
            end
            for n in line:gmatch("[Ii][Dd]=(%d+)") do
                add(n)
            end
            -- Plain item IDs; the percentage itself is never read as an ID.
            for n in line:gsub("[%+%-]?%d+%.?%d*%s*%%", " "):gmatch("%f[%d](%d%d%d%d%d%d?%d?)%f[%D]") do
                add(n)
            end
        end
    end
    return ids
end

-- Chooses every given item wherever it drops (raid bosses on Normal/Heroic/Mythic and the
-- season dungeons). Returns how many (item, source) pairs were added.
function Tools.SelectItems(ids)
    local wanted = {}
    for _, id in ipairs(ids) do
        wanted[id] = true
    end
    local added = 0
    local function choose(sourceType, sourceID, diff, itemID)
        local set = VCA.Data.GetSelectedItems(sourceType, sourceID, diff)
        if not set[itemID] then
            set[itemID] = true
            VCA.Data.SaveSelectedItems(sourceType, sourceID, diff, set)
            added = added + 1
        end
    end
    for encounterID, data in pairs(VCA.SeasonData and VCA.SeasonData.raids or {}) do
        for _, diff in ipairs({14, 15, 16}) do
            for _, itemID in ipairs(data[diff] or {}) do
                if wanted[itemID] then
                    choose(VCA.ContentType.RAID, encounterID, diff, itemID)
                end
            end
        end
    end
    for _, instanceID in ipairs(VCA.SeasonData and VCA.SeasonData.dungeonInstanceIDs or {}) do
        local data = VCA.SeasonData.dungeons and VCA.SeasonData.dungeons[instanceID]
        local found = {}
        for _, list in pairs(data and data.bySpec or {}) do
            for _, itemID in ipairs(list) do
                if wanted[itemID] then
                    found[itemID] = true
                end
            end
        end
        for itemID in pairs(found) do
            choose(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty, itemID)
        end
    end
    if VCA.Panel and VCA.Panel.ReloadItemSelections then
        VCA.Panel.ReloadItemSelections()
        VCA.Panel.Refresh()
    end
    return added
end

function Tools.Wish(minGain)
    minGain = tonumber(minGain)
    VCA.Report.Show(L["TOOLS_WISH_TITLE"], "", {
        editable = true,
        button = L["TOOLS_WISH_BUTTON"],
        footer = minGain and string.format(L["TOOLS_WISH_HINT_GAIN"], minGain) or L["TOOLS_WISH_HINT"],
        onAction = function(text)
            local ids = Tools.ParseItemIDs(text, minGain)
            if #ids == 0 then
                Say(L["TOOLS_WISH_NONE"])
                return
            end
            Say(string.format(L["TOOLS_WISH_DONE"], #ids, Tools.SelectItems(ids)))
            VCA.Report.Hide()
        end
    })
end

-- ── /void select ──────────────────────────────────────────────────────────────

function Tools.SelectAll(clear)
    if not (VCA.Panel and VCA.Panel.SelectAllUseful) then
        return
    end
    local n = VCA.Panel.SelectAllUseful(clear)
    if n == nil then
        Say(L["TOOLS_SELECT_NO_SOURCE"])
    elseif clear then
        Say(L["TOOLS_SELECT_CLEARED"])
    else
        Say(string.format(L["TOOLS_SELECT_DONE"], n))
    end
end

-- ── Character summary ─────────────────────────────────────────────────────────

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    pcall(VCA.Planner.SaveCharacterSummary)
end)

-- ── Weekly summary at login ───────────────────────────────────────────────────
-- Once per weekly reset: how many of the items you chose are still missing.

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loginFrame:SetScript("OnEvent", function(self, _, isInitialLogin)
    if not isInitialLogin then
        return
    end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(12, function()
        local gdb = _G[VCA.GLOBAL_DB_NAME]
        if not gdb or gdb.weeklySummary == false then
            return
        end
        local week = VCA.Planner.WeekStart()
        local cdb = _G[VCA.CHAR_DB_NAME]
        if not cdb or (cdb.lastSummaryWeek and math.abs(cdb.lastSummaryWeek - week) < 3600) then
            return
        end
        local _, heroic = VCA.Planner.CountMissing(VCA.Difficulty.RAID_HEROIC)
        local _, mythic = VCA.Planner.CountMissing(VCA.Difficulty.RAID_MYTHIC)
        if heroic + mythic == 0 then
            return
        end
        cdb.lastSummaryWeek = week
        Say(string.format(L["SUMMARY_LOGIN"], heroic, mythic))
    end)
end)
