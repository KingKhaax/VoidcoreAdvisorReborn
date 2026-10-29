-- VoidcoreAdvisor Reborn: SettingsWindow
-- The addon's own settings window (/void open, or the button of the addon in the game's
-- Options). Side tabs with the same settings that used to live in the Options list; they are
-- saved in the same variables. The window is built the first time it is opened.
local addonName, VCA = ...
local L = VCA.L

local SW = {}
VCA.SettingsWindow = SW

local WIDTH, HEIGHT = 700, 560
local NAV_W = 176
local ROW_H = 54
-- Width of the page content: the window minus the tab column, the margins and the scroll bar.
local PANE_W = WIDTH - NAV_W - 52

local function GDB()
    return _G[VCA.GLOBAL_DB_NAME] or {}
end

local built = false
local frame
local widgets = {} -- everything with an Update() that shows a stored value
local tabs, panes = {}, {}

-- ── Small controls ────────────────────────────────────────────────────────────

local FLAT = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = {left = 1, right = 1, top = 1, bottom = 1}
}

local function Accent()
    return VCA.Theme.accent
end

-- On/off switch tied to a boolean in the account variables.
local function Switch(parent, key, afterChange)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(40, 20)
    b:SetBackdrop(FLAT)
    local knob = b:CreateTexture(nil, "OVERLAY")
    knob:SetSize(14, 14)
    function b.Update()
        local on = GDB()[key] ~= false
        local a = Accent()
        knob:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", b, "RIGHT", -3, 0)
            knob:SetColorTexture(a[1], a[2], a[3], 1)
            b:SetBackdropColor(a[1] * 0.25, a[2] * 0.25, a[3] * 0.25, 1)
            b:SetBackdropBorderColor(a[1], a[2], a[3], 1)
        else
            knob:SetPoint("LEFT", b, "LEFT", 3, 0)
            knob:SetColorTexture(0.3, 0.42, 0.35, 1)
            b:SetBackdropColor(0.02, 0.06, 0.04, 1)
            b:SetBackdropBorderColor(0.16, 0.35, 0.25, 1)
        end
    end
    b:SetScript("OnClick", function()
        GDB()[key] = not (GDB()[key] ~= false)
        b.Update()
        if afterChange then
            afterChange()
        end
    end)
    widgets[#widgets + 1] = b
    return b
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 24)
    b:SetBackdrop(FLAT)
    b:SetBackdropColor(0.07, 0.23, 0.13, 1)
    b:SetBackdropBorderColor(0.16, 0.48, 0.29, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.1, 0.31, 0.18, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.07, 0.23, 0.13, 1)
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- ── Choice list ───────────────────────────────────────────────────────────────
-- One scrolling list shared by the theme selectors and the font selector.
-- entries: { {key=, label=, color={r,g,b} (swatch), path= (font file: the label is written in it)} }
local choiceList

local function OpenChoiceList(anchor, entries, currentKey, onPick, width)
    width = width or 260
    if not choiceList then
        local f = CreateFrame("Frame", "VCAChoiceList", frame, "BackdropTemplate")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetBackdrop(FLAT)
        f:SetBackdropColor(0.03, 0.08, 0.05, 0.99)
        f:SetBackdropBorderColor(0.85, 0.72, 0.41, 1)
        f:Hide()
        local scroll = CreateFrame("ScrollFrame", "VCAChoiceListScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 6)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(100, 10)
        scroll:SetScrollChild(child)
        f.scroll, f.child, f.buttons = scroll, child, {}
        choiceList = f
    end
    local f = choiceList
    if f:IsShown() and f.owner == anchor then
        f:Hide()
        return
    end
    f.owner = anchor
    local rowH = 24
    local height = math.min(#entries * rowH + 12, 300)
    f:SetSize(width, height)
    f.child:SetWidth(width - 34)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    for i, e in ipairs(entries) do
        local b = f.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, f.child)
            b:SetHeight(rowH)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.12)
            b.sel = b:CreateTexture(nil, "BACKGROUND")
            b.sel:SetAllPoints()
            b.swatch = b:CreateTexture(nil, "ARTWORK")
            b.swatch:SetSize(14, 14)
            b.swatch:SetPoint("LEFT", 8, 0)
            b.fs = b:CreateFontString(nil, "OVERLAY")
            b.fs:SetJustifyH("LEFT")
            b.fs:SetWordWrap(false)
            f.buttons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f.child, "TOPLEFT", 0, -(i - 1) * rowH)
        b:SetPoint("RIGHT", f.child, "RIGHT", 0, 0)
        if e.color then
            b.swatch:SetColorTexture(e.color[1], e.color[2], e.color[3], 1)
            b.swatch:Show()
        else
            b.swatch:Hide()
        end
        b.fs:ClearAllPoints()
        b.fs:SetPoint("LEFT", e.color and 30 or 10, 0)
        b.fs:SetPoint("RIGHT", -6, 0)
        local ok = false
        if e.path then
            ok = b.fs:SetFont(e.path, 13, "") and true or false
        end
        if not ok then
            b.fs:SetFontObject("VCAFontHighlight")
        end
        b.fs:SetText(e.label)
        b.fs:SetTextColor(0.93, 0.95, 0.93)
        if e.key == currentKey then
            b.sel:SetColorTexture(0.85, 0.72, 0.41, 0.25)
        else
            b.sel:SetColorTexture(0, 0, 0, 0)
        end
        b.entryKey = e.key
        b:SetScript("OnClick", function(self)
            f:Hide()
            onPick(self.entryKey)
        end)
        b:Show()
    end
    for i = #entries + 1, #f.buttons do
        f.buttons[i]:Hide()
    end
    f.child:SetHeight(#entries * rowH + 4)
    f.scroll:SetVerticalScroll(0)
    f:Show()
    f:Raise()
end

-- "< theme name >" selector tied to a theme key; withCurrent adds "the theme I use".
-- The arrows step through the themes; the name opens the list with all of them.
local function ThemeSelector(parent, key, withCurrent, afterChange)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(230, 24)
    local keys = {}
    if withCurrent then
        keys[#keys + 1] = "current"
    end
    for _, k in ipairs(VCA.THEME_ORDER) do
        keys[#keys + 1] = k
    end
    local prev = Button(box, "<", 24, nil)
    prev:SetPoint("LEFT", box, "LEFT", 0, 0)
    local nxt = Button(box, ">", 24, nil)
    nxt:SetPoint("RIGHT", box, "RIGHT", 0, 0)
    local mid = CreateFrame("Button", nil, box, "BackdropTemplate")
    mid:SetBackdrop(FLAT)
    mid:SetBackdropColor(0.02, 0.06, 0.04, 1)
    mid:SetBackdropBorderColor(0.16, 0.35, 0.25, 1)
    mid:SetPoint("TOPLEFT", prev, "TOPRIGHT", -1, 0)
    mid:SetPoint("BOTTOMRIGHT", nxt, "BOTTOMLEFT", 1, 0)
    local label = mid:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
    label:SetPoint("LEFT", mid, "LEFT", 8, 0)
    label:SetPoint("RIGHT", mid, "RIGHT", -18, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    local caret = mid:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
    caret:SetPoint("RIGHT", mid, "RIGHT", -6, 0)
    caret:SetText("v")
    mid:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.85, 0.72, 0.41, 1)
    end)
    mid:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.16, 0.35, 0.25, 1)
    end)
    local function IndexOf(value)
        for i, k in ipairs(keys) do
            if k == value then
                return i
            end
        end
        return 1
    end
    function box.Update()
        local v = GDB()[key]
        label:SetText(v == "current" and L["THEME_CURRENT"] or VCA.ThemeLabel(v or keys[1]))
    end
    local function Step(delta)
        local i = (IndexOf(GDB()[key]) - 1 + delta) % #keys + 1
        GDB()[key] = keys[i]
        box.Update()
        if afterChange then
            afterChange()
        end
    end
    prev:SetScript("OnClick", function()
        Step(-1)
    end)
    nxt:SetScript("OnClick", function()
        Step(1)
    end)
    mid:SetScript("OnClick", function()
        local entries = {}
        for _, k in ipairs(keys) do
            local ok, palette = pcall(VCA.GetPalette, k)
            entries[#entries + 1] = {
                key = k,
                label = k == "current" and L["THEME_CURRENT"] or VCA.ThemeLabel(k),
                color = ok and palette and palette.accent or nil
            }
        end
        OpenChoiceList(mid, entries, GDB()[key] or keys[1], function(picked)
            GDB()[key] = picked
            box.Update()
            if afterChange then
                afterChange()
            end
        end, 250)
    end)
    widgets[#widgets + 1] = box
    return box
end

-- ── Layout helpers ────────────────────────────────────────────────────────────

local function NewPane(titleText, subText)
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", NAV_W + 18, -62)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 14)
    local pane = CreateFrame("Frame", nil, scroll)
    pane:SetSize(PANE_W, 10)
    scroll:SetScrollChild(pane)
    pane.scroll = scroll

    -- Slim scroll bar to the right of the page
    local bar = CreateFrame("Slider", nil, scroll)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 12, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 12, 0)
    bar:SetWidth(10)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", bar, "TOP", 0, 0)
    track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    track:SetWidth(4)
    track:SetColorTexture(0, 0, 0, 0.45)
    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(8, 56)
    bar:SetThumbTexture(thumb)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    bar:Hide()
    VCA.OnTheme(function()
        local a = Accent()
        thumb:SetColorTexture(a[1], a[2], a[3], 0.85)
    end)
    bar:SetScript("OnValueChanged", function(_, value)
        scroll:SetVerticalScroll(value)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local lo, hi = bar:GetMinMaxValues()
        bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * 48)))
    end)
    -- Called when the page is shown or its content changes size.
    function scroll.Refresh()
        local max = math.max(0, (pane:GetHeight() or 0) - (scroll:GetHeight() or 0))
        bar:SetMinMaxValues(0, max)
        if bar:GetValue() > max then
            bar:SetValue(max)
        end
        bar:SetShown(max > 0)
    end
    local t = pane:CreateFontString(nil, "OVERLAY", "VCAFontNormalLarge")
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    t:SetText(titleText)
    t:SetTextColor(0.85, 0.72, 0.41)
    local s = pane:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -7)
    s:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    s:SetJustifyH("LEFT")
    s:SetWordWrap(false)
    s:SetText("|cff8fa597" .. subText .. "|r")
    pane.nextY = -58
    scroll:Hide()
    return pane
end

-- Sets the height of a page to its content (or to the given minimum).
local function FinishPane(pane, minHeight)
    pane:SetHeight(math.max(minHeight or 0, -pane.nextY + 14))
end

-- One settings row: bold label, grey hint under it, the control on the right.
local function Row(pane, label, hint, makeControl, below)
    local row = CreateFrame("Frame", nil, pane)
    row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, pane.nextY)
    row:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, pane.nextY)
    row:SetHeight(ROW_H)
    local line = row:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.07, 0.19, 0.12, 1)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    local control = makeControl(row)
    local l = row:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    l:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    l:SetJustifyH("LEFT")
    l:SetText("|cffeeeeee" .. label .. "|r")
    local h
    if hint and hint ~= "" then
        h = row:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
        h:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -8)
        h:SetJustifyH("LEFT")
        h:SetJustifyV("TOP")
        h:SetText("|cff8fa597" .. hint .. "|r")
    end
    -- The control sits on the right; the texts use the space left of it and the row grows
    -- with them, so a long label or hint never runs into the next row.
    local paneW = PANE_W
    local textW = below and paneW or (paneW - control:GetWidth() - 40)
    for _, fs in ipairs({l, h}) do
        fs:SetWidth(textW)
        fs:SetWordWrap(true)
    end
    local textH = 14 + l:GetStringHeight() + (h and (8 + h:GetStringHeight()) or 0)
    local height
    if below then
        height = textH + 10 + control:GetHeight() + 14
        control:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(textH + 10))
    else
        height = math.max(ROW_H + 6, textH + 16)
        control:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        control:SetPoint("TOP", row, "TOP", 0, -(height - control:GetHeight()) / 2 + 2)
    end
    row:SetHeight(height)
    pane.nextY = pane.nextY - height
    return row
end

local function SwitchRow(pane, key, label, hint, afterChange)
    Row(pane, label, hint, function(row)
        return Switch(row, key, afterChange)
    end)
end

-- A theme row: the selector and a Preview button.
local function ThemeRow(pane, key, label, hint, withCurrent, afterChange, onPreview)
    Row(pane, label, hint, function(row)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(230 + 10 + 120, 24)
        local sel = ThemeSelector(box, key, withCurrent, afterChange)
        sel:SetPoint("LEFT", box, "LEFT", 0, 0)
        local preview = Button(box, L["OPTIONS_PREVIEW_REMINDER"], 120, onPreview)
        preview:SetPoint("RIGHT", box, "RIGHT", 0, 0)
        return box
    end, true)
end

-- A preview window opened from here is placed beside this window (or on its left when there is
-- no room on the right), so it never covers the settings.
local function PlaceBeside(frameName)
    local f = _G[frameName]
    if not (f and f:IsShown() and frame and frame:IsShown()) then
        return
    end
    f:ClearAllPoints()
    local w = f:GetWidth() or 400
    if (frame:GetRight() or 0) + 12 + w > (UIParent:GetRight() or 1920) then
        f:SetPoint("TOPRIGHT", frame, "TOPLEFT", -12, 0)
    else
        f:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, 0)
    end
end

-- ── Font selector ─────────────────────────────────────────────────────────────
-- A button that opens the list with every available font, each name written in its own font.

local function FontRow(pane)
    Row(pane, L["SETTINGS_FONT_LABEL"], L["SETTINGS_FONT_TIP"], function(row)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(330, 24)
        local btn = Button(box, "", 250, nil)
        btn:SetPoint("LEFT", box, "LEFT", 0, 0)
        local nameText = btn:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
        nameText:SetPoint("LEFT", btn, "LEFT", 10, 0)
        nameText:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        local caret = btn:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
        caret:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        caret:SetText("v")
        local count = box:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
        count:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 2, -6)
        function box.Update()
            nameText:SetText(VCA.Fonts.Current() or L["SETTINGS_FONT_DEFAULT"])
            count:SetText("|cff8fa597" .. string.format(L["SETTINGS_FONT_COUNT"], #VCA.Fonts.List()) .. "|r")
        end
        btn:SetScript("OnClick", function()
            local entries = {{key = "default", label = L["SETTINGS_FONT_DEFAULT"]}}
            for _, name in ipairs(VCA.Fonts.List()) do
                entries[#entries + 1] = {key = name, label = name, path = VCA.Fonts.Resolve(name)}
            end
            OpenChoiceList(btn, entries, VCA.Fonts.Current() or "default", function(picked)
                VCA.Fonts.Choose(picked)
                box.Update()
            end, 300)
        end)
        widgets[#widgets + 1] = box
        return box
    end, true)
end

-- ── Text size ─────────────────────────────────────────────────────────────────
-- [-] 100% [+]: makes the text of the addon bigger or smaller (reopen open windows to see it all).

local function TextSizeRow(pane)
    Row(pane, L["SETTINGS_TEXTSIZE_LABEL"], L["SETTINGS_TEXTSIZE_TIP"], function(row)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(330, 24)
        local minus = Button(box, "-", 30, nil)
        minus:SetPoint("LEFT", box, "LEFT", 0, 0)
        local value = box:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
        value:SetPoint("LEFT", minus, "RIGHT", 0, 0)
        value:SetWidth(70)
        value:SetJustifyH("CENTER")
        local plus = Button(box, "+", 30, nil)
        plus:SetPoint("LEFT", value, "RIGHT", 0, 0)
        local reset = Button(box, L["SETTINGS_TEXTSIZE_RESET"], 110, nil)
        reset:SetPoint("LEFT", plus, "RIGHT", 12, 0)
        function box.Update()
            value:SetText(math.floor(VCA.Fonts.GetScale() * 100 + 0.5) .. "%")
            minus:SetAlpha(VCA.Fonts.CanScale(-1) and 1 or 0.4)
            plus:SetAlpha(VCA.Fonts.CanScale(1) and 1 or 0.4)
        end
        local function change(newScale)
            VCA.Fonts.SetScale(newScale)
            box.Update()
        end
        minus:SetScript("OnClick", function()
            change(VCA.Fonts.GetScale() - 0.1)
        end)
        plus:SetScript("OnClick", function()
            change(VCA.Fonts.GetScale() + 0.1)
        end)
        reset:SetScript("OnClick", function()
            change(1)
        end)
        widgets[#widgets + 1] = box
        return box
    end)
end

local function ApplyAndRefresh()
    VCA.ApplyTheme(GDB().theme)
    if VCA.Panel and VCA.Panel.Refresh then
        VCA.Panel.Refresh()
    end
end

-- ── Tabs ──────────────────────────────────────────────────────────────────────

local TOOLS = {
    {"SETTINGS_TOOL_MISSING", "/void missing", "missing", "VCAMissingFrame"},
    {"SETTINGS_TOOL_NEXT", "/void next", "next", "VCAReportFrame"},
    {"SETTINGS_TOOL_CORES", "/void cores", "cores", "VCAReportFrame"},
    {"SETTINGS_TOOL_HISTORY", "/void history", "history", "VCAReportFrame"},
    {"SETTINGS_TOOL_WISH", "/void wish", "wish", "VCAReportFrame"},
    {"SETTINGS_TOOL_RESET", "/void resetpanel", "resetpanel"}
}

local function BuildPanes()
    local general = NewPane(L["SETTINGS_TAB_GENERAL"], L["SETTINGS_SUB_GENERAL"])
    ThemeRow(general, "theme", L["OPTIONS_THEME"], L["OPTIONS_THEME_TOOLTIP"], false, ApplyAndRefresh, function()
        VCA.ThemePreview.Toggle()
        PlaceBeside("VCAThemePreviewFrame")
    end)
    SwitchRow(general, "showCumulative", L["OPTIONS_CUMULATIVE"], L["OPTIONS_CUMULATIVE_TOOLTIP"], function()
        if VCA.Panel and VCA.Panel.Refresh then
            VCA.Panel.Refresh()
        end
    end)
    SwitchRow(general, "weeklySummary", L["OPTIONS_SUMMARY"], L["OPTIONS_SUMMARY_TOOLTIP"])
    FontRow(general)
    TextSizeRow(general)

    local reminder = NewPane(L["OPTIONS_CAT_REMINDER"], L["SETTINGS_SUB_REMINDER"])
    SwitchRow(reminder, "reminderEnabled", L["OPTIONS_REMINDER_ENABLE"], L["OPTIONS_REMINDER_TOOLTIP"])
    SwitchRow(reminder, "reminderBossEnabled", L["OPTIONS_REMINDER_BOSS"], L["OPTIONS_REMINDER_BOSS_TOOLTIP"])
    ThemeRow(reminder, "reminderTheme", L["OPTIONS_REMINDER_THEME"], L["OPTIONS_REMINDER_THEME_TOOLTIP"], true,
        ApplyAndRefresh, function()
            if VoidcoreAdvisorReminder and VoidcoreAdvisorReminder:IsShown() then
                VCA.Reminder.Hide()
            else
                VCA.Reminder.ShowExample()
                PlaceBeside("VoidcoreAdvisorReminder")
            end
        end)

    local roll = NewPane(L["OPTIONS_CAT_BONUS_ROLL"], L["SETTINGS_SUB_ROLL"])
    SwitchRow(roll, "bonusRollConfirmEnabled", L["OPTIONS_BONUS_ROLL_CONFIRM"], L["OPTIONS_BONUS_ROLL_CONFIRM_TOOLTIP"])
    SwitchRow(roll, "brcConfirmEnabled", L["OPTIONS_BRC_CONFIRM"], L["OPTIONS_BRC_CONFIRM_TOOLTIP"])
    SwitchRow(roll, "brcSpecListEnabled", L["OPTIONS_BRC_SPEC_LIST"], L["OPTIONS_BRC_SPEC_LIST_TOOLTIP"])
    ThemeRow(roll, "rollTheme", L["OPTIONS_ROLL_THEME"], L["OPTIONS_ROLL_THEME_TOOLTIP"], true, ApplyAndRefresh,
        function()
            if VCARollWindow and VCARollWindow:IsShown() then
                VCA.BonusRollConfirm.Hide()
            else
                VCA.BonusRollConfirm.ShowPreview()
                PlaceBeside("VCARollWindow")
            end
        end)

    Row(roll, L["OPTIONS_ROLL_MOVE"], L["OPTIONS_ROLL_MOVE_TIP"], function(row)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(230 + 10 + 120, 24)
        local move = Button(box, L["OPTIONS_ROLL_MOVE_BTN"], 230, function()
            if not (VCARollWindow and VCARollWindow:IsShown()) then
                VCA.BonusRollConfirm.ShowPreview()
            end
        end)
        move:SetPoint("LEFT", box, "LEFT", 0, 0)
        local reset = Button(box, L["OPTIONS_ROLL_RESET_BTN"], 120, VCA.BonusRollConfirm.ResetPosition)
        reset:SetPoint("RIGHT", box, "RIGHT", 0, 0)
        return box
    end, true)

    local tools = NewPane(L["SETTINGS_TAB_TOOLS"], L["SETTINGS_SUB_TOOLS"])
    for i, tool in ipairs(TOOLS) do
        local b = CreateFrame("Button", nil, tools, "BackdropTemplate")
        b:SetSize(218, 54)
        b:SetBackdrop(FLAT)
        b:SetBackdropColor(0.04, 0.09, 0.06, 1)
        b:SetBackdropBorderColor(0.09, 0.25, 0.17, 1)
        local col, rowIdx = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", tools, "TOPLEFT", col * 228, -58 - rowIdx * 62)
        local n = b:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
        n:SetPoint("TOPLEFT", 10, -7)
        n:SetWidth(198)
        n:SetJustifyH("LEFT")
        n:SetWordWrap(false)
        n:SetText("|cffeeeeee" .. L[tool[1]] .. "|r")
        local c = b:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
        -- anchored to the bottom of the square, so the command stays inside whatever the font size
        c:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 10, 8)
        c:SetWidth(198)
        c:SetJustifyH("LEFT")
        c:SetWordWrap(false)
        c:SetText("|cffd9b968" .. tool[2] .. "|r")
        b:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.85, 0.72, 0.41, 1)
        end)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.09, 0.25, 0.17, 1)
        end)
        b:SetScript("OnClick", function()
            local handler = SlashCmdList and SlashCmdList["VOIDCOREADVISOR"]
            if handler then
                handler(tool[3])
                -- the window it opens goes beside this one, never on top of it
                if tool[4] then
                    PlaceBeside(tool[4])
                end
            end
        end)
    end
    -- Version: what you have, what it adds and who made it. Every block is placed from the real
    -- height of the one above, so nothing overlaps whatever the font or the language.
    local ver = NewPane(L["SETTINGS_TAB_VERSION"], L["SETTINGS_SUB_VERSION"])
    local paneW = PANE_W
    local y = -58
    local function Block(fs, gap)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", ver, "TOPLEFT", 0, y)
        y = y - fs:GetStringHeight() - (gap or 8)
    end
    local function Text(template, text, width)
        local fs = ver:CreateFontString(nil, "OVERLAY", template)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetSpacing(5)
        if width then
            fs:SetWidth(width)
        end
        fs:SetText(text)
        return fs
    end
    Block(Text("VCAFontNormalHuge", "|cffeeeeeeVoidcoreAdvisor Reborn|r  |cffd9b968" .. tostring(VCA.VERSION) .. "|r"), 20)
    Block(Text("VCAFontNormal", "|cffd9b968" .. L["VERSION_NOTES_TITLE"] .. "|r"), 8)
    Block(Text("VCAFontHighlightSmall", "|cffdddddd" .. L["VERSION_NOTES"] .. "|r", paneW), 22)
    Block(Text("VCAFontNormal", "|cffd9b968" .. L["VERSION_CREDITS_TITLE"] .. "|r"), 8)
    Block(Text("VCAFontHighlightSmall", "|cffdddddd" .. L["VERSION_CREDITS"] .. "|r", paneW), 22)

    -- The address you can select and copy (the text cannot be edited): label above, box below
    Block(Text("VCAFontHighlightSmall", "|cff8fa597" .. L["VERSION_LINK_CURSE"] .. "|r", paneW), 6)
    local box = CreateFrame("EditBox", nil, ver, "BackdropTemplate")
    box:SetSize(paneW, 22)
    box:SetPoint("TOPLEFT", ver, "TOPLEFT", 0, y)
    y = y - 22 - 10
    local url = "https://www.curseforge.com/wow/addons/voidcoreadvisor-reborn"
    box:SetBackdrop(FLAT)
    box:SetBackdropColor(0.02, 0.06, 0.04, 1)
    box:SetBackdropBorderColor(0.16, 0.35, 0.25, 1)
    box:SetFontObject("ChatFontSmall")
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    box:SetText(url)
    box:SetCursorPosition(0)
    box:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(url)
            self:SetCursorPosition(0)
        end
    end)
    box:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    ver.nextY = y
    FinishPane(general)
    FinishPane(reminder)
    FinishPane(roll)
    FinishPane(tools, 250)
    FinishPane(ver)
    return {general, reminder, roll, tools, ver}
end

local TAB_ICONS = {
    "Interface\\Icons\\INV_Misc_Gear_01",
    "Interface\\Icons\\INV_Misc_Bell_01",
    "Interface\\Icons\\INV_Misc_Dice_02",
    "Interface\\Icons\\INV_Misc_Book_09",
    "Interface\\Icons\\INV_Scroll_03"
}

local function SelectTab(index)
    if choiceList then
        choiceList:Hide()
    end
    for i, pane in ipairs(panes) do
        pane.scroll:SetShown(i == index)
        if i == index then
            pane.scroll:SetVerticalScroll(0)
            pane.scroll.Refresh()
            -- once more after the window has been laid out
            C_Timer.After(0.05, pane.scroll.Refresh)
        end
        tabs[i].selected = i == index
        tabs[i].Paint()
    end
    for _, w in ipairs(widgets) do
        w.Update()
    end
end

local function Build()
    built = true
    frame = CreateFrame("Frame", "VCASettingsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop(FLAT)
    frame:Hide()

    -- Title bar
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", 14, -9)
    icon:SetTexture("Interface\\Icons\\INV_Enchant_VoidSphere")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = frame:CreateFontString(nil, "OVERLAY", "VCAFontNormalHuge")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    VCA.OnTheme(function()
        title:SetText(VCA.RebornTitle("VoidcoreAdvisor", VCA.GetPalette("current")))
    end)
    local version = frame:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
    version:SetPoint("TOPRIGHT", -46, -22)
    version:SetText("|cff8fa597" .. string.format(L["SETTINGS_VERSION"], tostring(VCA.VERSION)) .. "|r")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -50)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -50)

    -- Side tabs
    local navBg = frame:CreateTexture(nil, "BACKGROUND")
    navBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -51)
    navBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    navBg:SetWidth(NAV_W)
    local navLine = frame:CreateTexture(nil, "ARTWORK")
    navLine:SetWidth(1)
    navLine:SetPoint("TOPLEFT", frame, "TOPLEFT", NAV_W + 1, -51)
    navLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", NAV_W + 1, 1)

    panes = BuildPanes()
    local names = {L["SETTINGS_TAB_GENERAL"], L["SETTINGS_TAB_REMINDER"], L["SETTINGS_TAB_ROLL"],
                   L["SETTINGS_TAB_TOOLS"], L["SETTINGS_TAB_VERSION"]}
    for i, name in ipairs(names) do
        local tab = CreateFrame("Button", nil, frame)
        tab:SetSize(NAV_W - 1, 38)
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -52 - (i - 1) * 40)
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local edge = tab:CreateTexture(nil, "ARTWORK")
        edge:SetWidth(3)
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("BOTTOMLEFT")
        local ico = tab:CreateTexture(nil, "ARTWORK")
        ico:SetSize(22, 22)
        ico:SetPoint("LEFT", 14, 0)
        ico:SetTexture(TAB_ICONS[i])
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local fs = tab:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
        fs:SetPoint("LEFT", ico, "RIGHT", 10, 0)
        -- Never wider than the tab: a long name is cut with "..." instead of running into the page.
        fs:SetWidth(NAV_W - 14 - 22 - 10 - 10)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetText(name)
        function tab.Paint()
            local a = Accent()
            if tab.selected then
                bg:SetColorTexture(a[1], a[2], a[3], 0.16)
                edge:SetColorTexture(a[1], a[2], a[3], 1)
                fs:SetTextColor(1, 1, 1)
            else
                bg:SetColorTexture(0, 0, 0, 0)
                edge:SetColorTexture(0, 0, 0, 0)
                fs:SetTextColor(0.8, 0.88, 0.83)
            end
        end
        tab:SetScript("OnClick", function()
            SelectTab(i)
        end)
        tab:SetScript("OnEnter", function(self)
            if not self.selected then
                bg:SetColorTexture(1, 1, 1, 0.05)
            end
        end)
        tab:SetScript("OnLeave", function()
            tab.Paint()
        end)
        tabs[i] = tab
    end

    VCA.OnTheme(function()
        local b, e, a = VCA.Theme.bg, VCA.Theme.border, Accent()
        frame:SetBackdropColor(b[1], b[2], b[3], 0.98)
        frame:SetBackdropBorderColor(e[1], e[2], e[3], 1)
        rule:SetColorTexture(e[1], e[2], e[3], 0.7)
        navLine:SetColorTexture(e[1], e[2], e[3], 0.7)
        navBg:SetColorTexture(0, 0, 0, 0.28)
        for _, tab in ipairs(tabs) do
            tab.Paint()
        end
        for _, w in ipairs(widgets) do
            w.Update()
        end
    end)
    SelectTab(1)
end

-- ── Public ────────────────────────────────────────────────────────────────────

-- Escape closes this window like any other, except when it was opened from the game's own
-- Options panel: closing that panel must leave the addon window open.
local function SetEscapeCloses(on)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "VCASettingsFrame" then
            table.remove(UISpecialFrames, i)
        end
    end
    if on then
        tinsert(UISpecialFrames, "VCASettingsFrame")
    end
end

-- index (optional): 1 General, 2 Reminder, 3 Bonus roll, 4 Tools
function SW.Open(index)
    if not built then
        Build()
    end
    SetEscapeCloses(not (SettingsPanel and SettingsPanel:IsShown()))
    SelectTab(tonumber(index) or 1)
    frame:Show()
    frame:Raise()
end

function SW.Toggle()
    if built and frame:IsShown() then
        frame:Hide()
    else
        SW.Open()
    end
end

function SW.Hide()
    if built then
        frame:Hide()
    end
end
