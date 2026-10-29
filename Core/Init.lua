-- VoidcoreAdvisor: Init
-- Bootstrap: SavedVariables initialisation, login event handling, and
-- the public slash-command interface.  Loaded last so every other module
-- is available when this code runs.
local addonName, VCA = ...
local L = VCA.L

-- ── SavedVariables defaults ───────────────────────────────────────────────────

local function GetDefaults()
    return {
        schemaVersion = VCA.SCHEMA_VERSION,
        seasonFingerprint = nil,
        obtained = {},
        selectedItems = {}, -- { ["TYPE:sourceID:diffID"] = { [itemID]=true, ... } }
        bonusRollLog = {}, -- raw BONUS_ROLL_RESULT entries for manual verification
        minimized = false,
        overviewMinimized = false
    }
end

local function GetGlobalDefaults()
    return {
        reminderEnabled = true,
        reminderBossEnabled = true,
        showCumulative = true,
        weeklySummary = true,
        bonusRollConfirmEnabled = true,
        brcSpecListEnabled = true,
        brcConfirmEnabled = true,
        theme = "green",
        rollTheme = "class",
        reminderTheme = "class",
        brcDefaultOnV2 = true,
        settingsTheme = "green",
        rollLayout = 1
    }
end

-- Apply any future schema migrations here.
local function MigrateDB(db)
    if db.schemaVersion == VCA.SCHEMA_VERSION then
        return
    end
    if (db.schemaVersion or 1) < 2 then
        -- v1→v2: insert specID=0 segment into obtained keys that lack it.
        VCA.Data.MigrateV1Keys(db)
    end
    db.schemaVersion = VCA.SCHEMA_VERSION
end

local function InitDB()
    -- Account-wide settings DB
    if type(_G[VCA.GLOBAL_DB_NAME]) ~= "table" then
        _G[VCA.GLOBAL_DB_NAME] = GetGlobalDefaults()
    else
        local gdb = _G[VCA.GLOBAL_DB_NAME]
        if gdb.reminderEnabled == nil then
            gdb.reminderEnabled = true
        end
        if gdb.bonusRollConfirmEnabled == nil then
            gdb.bonusRollConfirmEnabled = true
        end
        -- VoidcoreAdvisor Reborn turns the roll confirmation window on by default; apply it once
        -- to saves created while it was off by default.
        if gdb.reminderBossEnabled == nil then
            gdb.reminderBossEnabled = true
        end
        if gdb.weeklySummary == nil then
            gdb.weeklySummary = true
        end
        if gdb.showCumulative == nil then
            gdb.showCumulative = true
        end
        if gdb.brcConfirmEnabled == nil then
            gdb.brcConfirmEnabled = true
        end
        if gdb.theme == "spec" then
            gdb.theme = "class" -- the specialization theme was removed in 2.3.3
        end
        if gdb.rollTheme == nil or (gdb.rollTheme ~= "current" and not VCA.IsTheme(gdb.rollTheme)) then
            gdb.rollTheme = "class"
        end
        if gdb.reminderTheme == nil or (gdb.reminderTheme ~= "current" and not VCA.IsTheme(gdb.reminderTheme)) then
            gdb.reminderTheme = "class"
        end
        if not VCA.IsTheme(gdb.theme) then
            gdb.theme = "green"
        end
        if gdb.settingsTheme == nil or (gdb.settingsTheme ~= "current" and not VCA.IsTheme(gdb.settingsTheme)) then
            gdb.settingsTheme = "green"
        end
        if type(gdb.rollLayout) ~= "number" or gdb.rollLayout < 1 or gdb.rollLayout > 10 then
            gdb.rollLayout = 1
        end
        if not gdb.brcDefaultOnV2 then
            gdb.brcDefaultOnV2 = true
            gdb.bonusRollConfirmEnabled = true
        end
        if gdb.brcSpecListEnabled == nil then
            gdb.brcSpecListEnabled = true
        end
    end

    -- Per-character DB
    if type(_G[VCA.CHAR_DB_NAME]) ~= "table" then
        _G[VCA.CHAR_DB_NAME] = GetDefaults()
    else
        MigrateDB(_G[VCA.CHAR_DB_NAME])
        -- Ensure required top-level keys are present (handles sparse old saves).
        _G[VCA.CHAR_DB_NAME].obtained = _G[VCA.CHAR_DB_NAME].obtained or {}
        _G[VCA.CHAR_DB_NAME].selectedItems = _G[VCA.CHAR_DB_NAME].selectedItems or {}
        _G[VCA.CHAR_DB_NAME].bonusRollLog = _G[VCA.CHAR_DB_NAME].bonusRollLog or {}
        -- seasonFingerprint may be absent in saves from older versions; nil is fine.
        if _G[VCA.CHAR_DB_NAME].minimized == nil then
            _G[VCA.CHAR_DB_NAME].minimized = false
        end
        if _G[VCA.CHAR_DB_NAME].overviewMinimized == nil then
            _G[VCA.CHAR_DB_NAME].overviewMinimized = false
        end
    end
end

-- ── Bootstrap event handler ───────────────────────────────────────────────────

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local function IsSafeWarmupContext()
    local inInstance = IsInInstance()
    return inInstance ~= true
end

local _deferredWarmAttempts = 0
local _maxDeferredWarmAttempts = 8

local function StartDeferredWarmup()
    if not IsSafeWarmupContext() then
        return
    end

    VCA.LootPool.WarmCache()
end

local function ScheduleDeferredWarmup(delay)
    C_Timer.After(delay, function()
        if IsSafeWarmupContext() then
            StartDeferredWarmup()
            return
        end

        _deferredWarmAttempts = _deferredWarmAttempts + 1
        if _deferredWarmAttempts < _maxDeferredWarmAttempts then
            -- Keep retrying gently so we eventually warm after leaving instances.
            ScheduleDeferredWarmup(5)
        end
    end)
end

-- Guard so zone transitions after the first world-enter do not re-run startup
-- season validation.
local _hasInitializedWorld = false

initFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= addonName then
            return
        end
        InitDB()
        VCA.ApplyTheme(_G[VCA.GLOBAL_DB_NAME] and _G[VCA.GLOBAL_DB_NAME].theme)
        self:UnregisterEvent("ADDON_LOADED")
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("VoidcoreAdvisor") then
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r |cffff4444" .. L["ORIGINAL_ADDON_LOADED"] .. "|r")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Run only once per session. BuildSeasonFilter is called immediately
        -- (works inside instances); WarmCache is deferred until outside instances.
        if _hasInitializedWorld then
            return
        end
        _hasInitializedWorld = true

        -- Always build the season filter immediately so the Reminder and other
        -- features work even when logging in directly inside an instance.
        VCA.LootPool.BuildSeasonFilter()

        -- Clear per-character data when the season has changed.
        local newFingerprint = VCA.LootPool.GetSeasonFingerprint()
        if newFingerprint then
            local db = _G[VCA.CHAR_DB_NAME]
            if db.seasonFingerprint ~= newFingerprint then
                db.obtained = {}
                db.selectedItems = {}
                db.seasonFingerprint = newFingerprint
                print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["NEW_SEASON_RESET"])
            end
        end

        -- One-time hint for characters that have nothing marked yet.
        do
            local cdb = _G[VCA.CHAR_DB_NAME]
            local gdb = _G[VCA.GLOBAL_DB_NAME]
            if cdb and gdb and not gdb.scanTipShown and next(cdb.obtained or {}) == nil then
                gdb.scanTipShown = true
                C_Timer.After(10, function()
                    print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["SCAN_TIP"])
                end)
            end
        end

        -- Defer the heavy item-cache warmup until outside an instance.
        ScheduleDeferredWarmup(4)

        -- Notify any future UI layer that the backend is ready.
        if VCA.OnBackendReady then
            VCA.OnBackendReady()
        end
    end
end)

-- ── Public API ────────────────────────────────────────────────────────────────

-- Wipe all obtained item data for this character (exposed to slash command
-- and the UI "Reset" button when it is built).
function VCA.ResetObtainedData()
    _G[VCA.CHAR_DB_NAME] = GetDefaults()
end

-- ── Slash commands ────────────────────────────────────────────────────────────

SLASH_VOIDCOREADVISOR1 = "/void"
SLASH_VOIDCOREADVISOR2 = "/voidreborn"

SlashCmdList["VOIDCOREADVISOR"] = function(msg)
    local cmd = (msg:match("^%s*(%S+)") or ""):lower()

    if cmd == "reset" then
        VCA.ResetObtainedData()
        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["RESET_CONFIRM"])

    elseif cmd == "count" then
        local count = VCA.Data.GetTotalObtainedCount()
        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. string.format(L["COUNT_FORMAT"], count))

    elseif cmd == "spec" then
        -- Debug: print which spec will be used for loot.
        local specID = VCA.SpecInfo.GetEffectiveLootSpecID()
        local rawID = VCA.SpecInfo.GetRawLootSpecID()
        local suffix = rawID == 0 and L["FOLLOWS_ACTIVE_SPEC"] or ""
        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. string.format(L["SPEC_FORMAT"], specID or "unknown", suffix))

    elseif cmd == "source" then
        -- Debug: print the currently active detection source.
        local src = VCA.Detection.GetActiveSource()
        if src then
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " ..
                      string.format(L["SOURCE_FORMAT"], src.sourceType, src.sourceID, src.difficultyID))
        else
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["NO_ACTIVE_SOURCE"])
        end

    elseif cmd == "rolls" then
        -- Print raw bonus roll event log for manual verification.
        local log = VCA.Data.GetBonusRollLog()
        if #log == 0 then
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["ROLLS_NONE"])
        else
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. string.format(L["ROLLS_HEADER"], #log))
            for i, entry in ipairs(log) do
                local ts = date("%Y-%m-%d %H:%M:%S", entry.timestamp)
                local src = L["ROLLS_UNKNOWN_SOURCE"]
                if entry.sourceType and entry.sourceID and entry.difficultyID then
                    src = entry.sourceType .. ":" .. entry.sourceID .. " diff=" .. entry.difficultyID
                    if entry.keyLevel then
                        src = src .. " key=" .. entry.keyLevel
                    end
                end
                if entry.manual then
                    src = src .. " " .. L["ROLLS_MANUAL"]
                end
                local spec = entry.specID and ("spec=" .. entry.specID) or "spec=?"
                print(string.format("  [%d] %s  %s  %s  %s", i, ts,
                    entry.itemLink or ("itemID=" .. tostring(entry.itemID)), spec, src))
            end
        end

    elseif cmd == "version" then
        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. string.format(L["VERSION_FORMAT"], VCA.VERSION))

    elseif cmd == "tooltips" then
        -- Checks that no raid item loses its effect text in the tooltip.
        if VCA.Panel and VCA.Panel.AuditRaidTooltips then
            VCA.Panel.AuditRaidTooltips()
        end

    elseif cmd == "replaylog" then
        VCA.Detection.ReplayBonusRollLog(true)
        -- Refresh the panel so newly-marked items are immediately hidden.
        if VCA.Panel and VCA.Panel.Refresh then
            VCA.Panel.Refresh()
        end

    elseif cmd == "restore" then
        local mpTime, raidTime = VCA.VoidcacheScan.GetBackupInfo()
        if not mpTime and not raidTime then
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["RESTORE_NO_BACKUP"])
        else
            local ok, result = VCA.VoidcacheScan.RestoreBackup()
            if ok then
                print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. string.format(L["RESTORE_COMPLETE"], result))
                if VCA.DungeonOverview and VCA.DungeonOverview.Refresh then
                    VCA.DungeonOverview.Refresh()
                end
                if VCA.RaidOverview and VCA.RaidOverview.Refresh then
                    VCA.RaidOverview.Refresh()
                end
                if VCA.Panel and VCA.Panel.Refresh then
                    VCA.Panel.Refresh()
                end
            else
                print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["RESTORE_FAILED"])
            end
        end

    elseif cmd == "reminder" then
        -- Force-evaluate the reminder, ignoring the already-shown guard.
        VCA.Reminder.ForceEvaluate()

    elseif cmd == "liveraid" then
        VCA.LiveRaid.Run(true)

    elseif cmd == "scan" then
        -- Reads the Voidcache of every spec to mark the items you already got from
        -- the Voidcores you spent. "/void scan" = Mythic+ dungeons, "/void scan raid [14|15|16]".
        local scan = VCA.VoidcacheScan
        local ok, reason
        local arg = (msg:match("^%s*%S+%s+(%S+)") or ""):lower()
        if arg == "owned" then
            scan.Owned()
            return
        elseif arg == "raid" then
            ok, reason = scan.StartRaid(tonumber(msg:match("^%s*%S+%s+%S+%s+(%d+)")) or VCA.Difficulty.RAID_HEROIC)
        else
            ok, reason = scan.Start()
        end
        if ok == false then
            local text = (reason == "COMBAT" and L["SCAN_UNAVAILABLE_COMBAT"]) or
                             (reason == "INSTANCE" and L["SCAN_UNAVAILABLE_INSTANCE"]) or tostring(reason)
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. text)
        end

    elseif cmd == "panel" then
        VCA.OpenPanel(msg:match("^%s*%S+%s+(.-)%s*$"))

    elseif cmd == "missing" then
        VCA.Missing.Show(msg:match("^%s*%S+%s+(%d+)"))

    elseif cmd == "export" then
        VCA.Transfer.Export()

    elseif cmd == "import" then
        VCA.Transfer.Import()

    elseif cmd == "open" then
        if VCA.OpenOptions then
            VCA.OpenOptions()
        elseif VCA.SettingsWindow then
            VCA.SettingsWindow.Open()
        end

    elseif cmd == "cores" then
        VCA.Tools.Cores(msg:match("^%s*%S+%s+(%d+)"))

    elseif cmd == "next" then
        VCA.Tools.Next(msg:match("^%s*%S+%s+(%d+)"))

    elseif cmd == "history" then
        VCA.Tools.History()

    elseif cmd == "chars" then
        VCA.Planner.SaveCharacterSummary()
        VCA.Tools.Chars()

    elseif cmd == "perf" then
        VCA.Tools.Perf(msg:match("^%s*%S+%s+(%S+)"))

    elseif cmd == "debug" then
        VCA.Tools.Debug()

    elseif cmd == "prio" then
        VCA.Tools.Priority(msg:match("^%s*%S+%s+(.-)%s*$"))

    elseif cmd == "wish" then
        VCA.Tools.Wish(msg:match("^%s*%S+%s+([%d%.]+)"))

    elseif cmd == "select" then
        VCA.Tools.SelectAll((msg:match("^%s*%S+%s+(%S+)") or ""):lower() == "clear")

    elseif cmd == "preview" then
        VCA.ThemePreview.Toggle()

    elseif cmd == "resetpanel" then
        if VCA.Panel and VCA.Panel.ResetPlacement then
            VCA.Panel.ResetPlacement()
        end

    elseif cmd == "theme" then
        local arg = (msg:match("^%s*%S+%s+(%S+)") or ""):lower()
        local gdb = _G[VCA.GLOBAL_DB_NAME]
        if VCA.IsTheme(arg) and gdb then
            gdb.theme = arg
            VCA.ApplyTheme(arg)
            if VCA.Panel and VCA.Panel.Refresh then
                VCA.Panel.Refresh()
            end
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. VCA.ThemeLabel(arg))
        else
            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["HELP_THEME"])
            print("  " .. table.concat(VCA.THEME_ORDER, ", "))
        end

    else
        print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. L["HELP_HEADER"])
        print(L["HELP_RESET"])
        print(L["HELP_COUNT"])
        print(L["HELP_SPEC"])
        print(L["HELP_SOURCE"])
        print(L["HELP_VERSION"])
        print(L["HELP_REPLAYLOG"])
        print(L["HELP_RESTORE"])
        print(L["HELP_SCAN"])
        print(L["HELP_PANEL"])
        print(L["HELP_MISSING"])
        print(L["HELP_EXPORT"])
        print(L["HELP_IMPORT"])
        print(L["HELP_OPEN"])
        print(L["HELP_CORES"])
        print(L["HELP_NEXT"])
        print(L["HELP_HISTORY"])
        print(L["HELP_CHARS"])
        print(L["HELP_PRIO"])
        print(L["HELP_WISH"])
        print(L["HELP_SELECT"])
        print(L["HELP_DEBUG"])
        print(L["HELP_PERF"])
        print(L["HELP_THEME"])
        print("    " .. table.concat(VCA.THEME_ORDER, ", "))
        print(L["HELP_RESETPANEL"])
    end
end
