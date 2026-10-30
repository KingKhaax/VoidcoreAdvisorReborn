local _, VCA = ...
local L = VCA.L

local ScanSelect = {}
VCA.ScanSelect = ScanSelect

local WIDTH, HEIGHT, ROW_H = 620, 500, 28
local SWATCH, GAP, COLS = 26, 6, 7

local frame, child, subtitle, applyBtn, title, divider, colorBtn, colorSwatch, colorPanel
local rows = {}
local swatches = {}
local current

local function GDB()
    return _G[VCA.GLOBAL_DB_NAME] or {}
end

local function ThemeKey()
    local key = GDB().scanTheme
    if key == nil or not VCA.IsTheme(key) then
        return "green"
    end
    return key
end

local function Palette(key)
    return VCA.GetPalette(key or ThemeKey())
end

local function TintCheck(check, palette)
    local texture = check:GetCheckedTexture()
    if texture then
        texture:SetVertexColor(palette.accent[1], palette.accent[2], palette.accent[3])
    end
end

local function ApplyPalette()
    local p = Palette()
    frame:SetBackdropColor(p.bg[1], p.bg[2], p.bg[3], 0.97)
    frame:SetBackdropBorderColor(p.border[1], p.border[2], p.border[3], 1)
    title:SetText(p.title .. L["SCAN_SELECT_TITLE"] .. "|r")
    divider:SetColorTexture(p.border[1], p.border[2], p.border[3], 0.5)
    colorSwatch:SetColorTexture(p.accent[1], p.accent[2], p.accent[3], 1)
    colorBtn:SetBackdropBorderColor(p.border[1], p.border[2], p.border[3], 1)
    colorPanel:SetBackdropColor(p.bg[1], p.bg[2], p.bg[3], 0.98)
    colorPanel:SetBackdropBorderColor(p.border[1], p.border[2], p.border[3], 1)
    for _, row in ipairs(rows) do
        TintCheck(row.check, p)
    end
    local selected = ThemeKey()
    for key, swatch in pairs(swatches) do
        local sp = Palette(key)
        swatch:SetBackdropColor(sp.accent[1], sp.accent[2], sp.accent[3], 1)
        if key == selected then
            swatch:SetBackdropBorderColor(1, 1, 1, 1)
        else
            swatch:SetBackdropBorderColor(sp.border[1], sp.border[2], sp.border[3], 1)
        end
    end
end

local function CheckedCount()
    local n = 0
    for i = 1, current and #current.rows or 0 do
        if rows[i].check:GetChecked() then
            n = n + 1
        end
    end
    return n
end

local function UpdateCount()
    local n = CheckedCount()
    applyBtn:SetText(string.format(L["SCAN_SELECT_APPLY"], n))
    applyBtn:SetEnabled(n > 0)
end

local function GetRow(i)
    local row = rows[i]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, child)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    row:EnableMouse(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.04)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(24, 24)
    row.check:SetPoint("LEFT", 2, 0)
    row.check:SetScript("OnClick", UpdateCount)
    TintCheck(row.check, Palette())
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.detail = row:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
    row.detail:SetPoint("RIGHT", -8, 0)
    row.detail:SetWidth(250)
    row.detail:SetJustifyH("RIGHT")
    row.detail:SetWordWrap(false)
    row.name = row:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.detail, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    rows[i] = row
    return row
end

local function SetAll(checked)
    for i = 1, #current.rows do
        rows[i].check:SetChecked(checked)
    end
    UpdateCount()
end

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = {left = 1, right = 1, top = 1, bottom = 1}
}

local function ThemeKeys()
    local keys = {"green"}
    for _, key in ipairs(VCA.THEME_ORDER) do
        if key ~= "green" then
            keys[#keys + 1] = key
        end
    end
    return keys
end

local function BuildColorPicker()
    colorBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    colorBtn:SetSize(78, 22)
    colorBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -10)
    colorBtn:SetBackdrop(BACKDROP)
    colorBtn:SetBackdropColor(1, 1, 1, 0.06)
    colorSwatch = colorBtn:CreateTexture(nil, "OVERLAY")
    colorSwatch:SetSize(12, 12)
    colorSwatch:SetPoint("LEFT", 7, 0)
    local label = colorBtn:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
    label:SetPoint("LEFT", colorSwatch, "RIGHT", 6, 0)
    label:SetText(L["SCAN_COLOR"])
    local hover = colorBtn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)

    local keys = ThemeKeys()
    local rowsNeeded = math.ceil(#keys / COLS)
    colorPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    colorPanel:SetSize(COLS * SWATCH + (COLS - 1) * GAP + 24, rowsNeeded * SWATCH + (rowsNeeded - 1) * GAP + 24)
    colorPanel:SetPoint("TOPRIGHT", colorBtn, "BOTTOMRIGHT", 0, -4)
    colorPanel:SetFrameStrata("FULLSCREEN_DIALOG")
    colorPanel:SetBackdrop(BACKDROP)
    colorPanel:Hide()

    for i, key in ipairs(keys) do
        local swatch = CreateFrame("Button", nil, colorPanel, "BackdropTemplate")
        swatch:SetSize(SWATCH, SWATCH)
        swatch:SetPoint("TOPLEFT", colorPanel, "TOPLEFT", 12 + ((i - 1) % COLS) * (SWATCH + GAP),
            -12 - math.floor((i - 1) / COLS) * (SWATCH + GAP))
        swatch:SetBackdrop(BACKDROP)
        swatch:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(VCA.ThemeLabel(key))
            GameTooltip:Show()
        end)
        swatch:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        swatch:SetScript("OnClick", function()
            local gdb = _G[VCA.GLOBAL_DB_NAME]
            if gdb then
                gdb.scanTheme = key
            end
            ApplyPalette()
            colorPanel:Hide()
        end)
        swatches[key] = swatch
    end

    colorBtn:SetScript("OnClick", function()
        colorPanel:SetShown(not colorPanel:IsShown())
    end)
    colorBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["SCAN_COLOR_TOOLTIP"])
        GameTooltip:Show()
    end)
    colorBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function Build()
    frame = CreateFrame("Frame", "VCAScanSelectFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop(BACKDROP)
    frame:Hide()
    tinsert(UISpecialFrames, "VCAScanSelectFrame")

    title = frame:CreateFontString(nil, "OVERLAY", "VCAFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)

    subtitle = frame:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetWidth(WIDTH - 40)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetWordWrap(true)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)

    divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -78)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -78)

    local scroll = CreateFrame("ScrollFrame", "VCAScanSelectScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -84)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 46)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(WIDTH - 50, 10)
    scroll:SetScrollChild(child)

    local allBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    allBtn:SetSize(110, 24)
    allBtn:SetPoint("BOTTOMLEFT", 14, 12)
    allBtn:SetText(L["SCAN_SELECT_ALL"])
    allBtn:SetScript("OnClick", function()
        SetAll(true)
    end)

    local noneBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    noneBtn:SetSize(110, 24)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
    noneBtn:SetText(L["SCAN_SELECT_NONE"])
    noneBtn:SetScript("OnClick", function()
        SetAll(false)
    end)

    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    cancelBtn:SetText(CANCEL)
    cancelBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    applyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyBtn:SetSize(170, 24)
    applyBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -6, 0)
    applyBtn:SetScript("OnClick", function()
        local selected = {}
        for i, data in ipairs(current.rows) do
            if rows[i].check:GetChecked() then
                for _, entry in ipairs(data.entries) do
                    selected[#selected + 1] = entry
                end
            end
        end
        local onApply = current.onApply
        current.done = true
        frame:Hide()
        onApply(selected)
    end)

    BuildColorPicker()
    ApplyPalette()

    frame:SetScript("OnHide", function()
        colorPanel:Hide()
        if current and not current.done then
            current.done = true
            current.onCancel()
        end
    end)
end

function ScanSelect.Show(data, header, onApply, onCancel)
    if not frame then
        Build()
    end
    if current and not current.done then
        current.done = true
        current.onCancel()
    end
    current = {rows = data, onApply = onApply, onCancel = onCancel, done = false}
    ApplyPalette()
    subtitle:SetText(header)
    for i, entry in ipairs(data) do
        local row = GetRow(i)
        row.itemID = entry.itemID
        row.check:SetChecked(false)
        local name, link = C_Item.GetItemInfo(entry.itemID)
        row.icon:SetTexture(C_Item.GetItemIconByID(entry.itemID) or 134400)
        row.name:SetText(link or name or entry.name)
        row.detail:SetText("|cffb8b8c0" .. entry.source .. "  \226\128\162  " .. entry.specText .. "|r")
        row:Show()
    end
    for i = #data + 1, #rows do
        rows[i]:Hide()
    end
    child:SetHeight(math.max(10, #data * ROW_H))
    UpdateCount()
    frame:Show()
end
