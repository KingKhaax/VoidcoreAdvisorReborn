-- VoidcoreAdvisor: Panel
-- The side panel frame.  Anchors to the right edge of EncounterJournal and
-- shows context for the currently-viewed boss or dungeon.
--
-- Layout:
--   ┌────────────────────────────────────────────────────┐
--   │  VoidcoreAdvisor                               [X] │  header
--   │  <source name>                                     │
--   │  Raid Boss  •  2 Nebulous Voidcores                │
--   ├─────────────────────┬──────────────────────────────┤  divider
--   │ LOOT                │ SPEC RANKING                 │  column headers
--   │ ┌──┐ [Item name]  □ │ #1 [icon] SpecName  3/8 37% │
--   │ ┌──┐ [Item name]  □ │ #2 [icon] SpecName  5/8 37% │  rows
--   │ ...                 │ ...                          │
--   └─────────────────────┴──────────────────────────────┘
local _, VCA = ...
local L = VCA.L

VCA.Panel = {}
local Panel = VCA.Panel

-- ── Internal state shared with PanelColumns.lua ───────────────────────────────
-- PanelColumns.lua (loaded after this file) accesses these via Panel._s.
-- Never reassign the tables themselves; use wipe() to clear them.
local _s = {}
Panel._s = _s

-- Selection state
_s.selectedItemIDs = {}
local selectedItemIDs = _s.selectedItemIDs -- local alias for this file's closures
_s.selectedSpecIDs = {}
local selectedSpecIDs = _s.selectedSpecIDs -- local alias for this file's closures

-- ── Sizing ────────────────────────────────────────────────────────────────────

local PANEL_WIDTH = 600
local HEADER_H = 76 -- title + source label + info label + divider
local COL_HEADER_H = 20 -- "LOOT" / "SPEC RANKING" label row
local PADDING = 12 -- inner horizontal padding
local ROW_H = 26 -- height of one item / spec row
local ICON_SIZE = 20 -- inline icon size in rows
local COL_SPLIT = 0.52 -- left column fraction of content width

-- ── Main frame ────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
Panel.frame = frame

frame:SetWidth(PANEL_WIDTH)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:Hide()

frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = {
        left = 1,
        right = 1,
        top = 1,
        bottom = 1
    }
})
VCA.OnTheme(function() local t = VCA.Theme.bg; frame:SetBackdropColor(t[1], t[2], t[3], 0.97) end) -- dark venom green glass
VCA.OnTheme(function() local t = VCA.Theme.border; frame:SetBackdropBorderColor(t[1], t[2], t[3], 1) end)

-- Gold corner brackets (top-left and bottom-right), like the stock frames.
local function CornerBracket(point, dx, dy)
    local h = frame:CreateTexture(nil, "OVERLAY")
    h:SetColorTexture(0.80, 0.70, 0.48, 1)
    h:SetSize(11, 1)
    h:SetPoint(point, frame, point, dx, dy)
    local v = frame:CreateTexture(nil, "OVERLAY")
    v:SetColorTexture(0.80, 0.70, 0.48, 1)
    v:SetSize(1, 11)
    v:SetPoint(point, frame, point, dx, dy)
end
CornerBracket("TOPLEFT", 0, 0)
CornerBracket("BOTTOMRIGHT", 0, 0)

-- ── Anchor helper ─────────────────────────────────────────────────────────────

-- Positions the panel flush against the right edge of EncounterJournal.
-- Safe to call multiple times (ClearAllPoints before re-anchoring).
local function GetPlacement()
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    return gdb and gdb.panelPlacement
end

local function ApplyPlacement(p, f)
    f = f or frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    f:SetSize(p.w, p.h)
end

-- Freezes the current position and size so the window can be moved or resized freely.
-- f is the window (the panel unless an overview asks).
local function Freeze(f)
    f = f or frame
    local x, y = f:GetLeft(), f:GetTop()
    if not (x and y) then
        return nil
    end
    local p = {x = x, y = y, w = f:GetWidth(), h = f:GetHeight()}
    ApplyPlacement(p, f)
    return p
end

local function SavePlacement(f)
    f = f or frame
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    local x, y = f:GetLeft(), f:GetTop()
    if gdb and x and y then
        local w, h = f:GetWidth(), f:GetHeight()
        if f ~= frame then
            -- an overview only gives the position; the size stays the panel's
            local old = gdb.panelPlacement
            w = old and old.w or frame:GetWidth()
            h = old and old.h or frame:GetHeight()
        end
        gdb.panelPlacement = {x = x, y = y, w = w, h = h}
    end
end

-- Pinned (the default): the panel sticks to the right edge of the Adventure Guide and follows it.
-- Free: it keeps the position and size you gave it (the pin button next to the X switches).
function Panel.IsPinned()
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    return not (gdb and gdb.panelFree)
end

-- For the overviews: when the panel is free, puts the window at the saved position (keeping its width;
-- useHeight also takes the saved height).  Returns true when it did.
function Panel.ApplyFreePlacement(f, useHeight)
    local placement = GetPlacement()
    if Panel.IsPinned() or not placement then
        return false
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", placement.x, placement.y)
    if useHeight then
        f:SetHeight(placement.h)
    end
    return true
end

-- Lets a window be dragged by its title row; dragging a pinned window lets it go.
function Panel.MakeDraggable(f, rightInset)
    f:SetMovable(true)
    local handle = CreateFrame("Frame", nil, f)
    handle:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    handle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(rightInset or 70), 0)
    handle:SetHeight(30)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if Panel.IsPinned() then
            Panel.SetPinned(false, f)
        end
        Freeze(f)
        f:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        SavePlacement(f)
    end)
end

function Panel.AnchorToEJ()
    local ej = EncounterJournal
    if not ej then
        return
    end
    local placement = GetPlacement()
    if not Panel.IsPinned() and placement then
        ApplyPlacement(placement)
        return
    end
    frame:SetWidth(PANEL_WIDTH)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", ej, "TOPRIGHT", 52, 0)
    frame:SetPoint("BOTTOMLEFT", ej, "BOTTOMRIGHT", 52, 0)
end

-- ── Header widgets ────────────────────────────────────────────────────────────

-- Title
local titleText = frame:CreateFontString(nil, "OVERLAY", "VCAFontNormalLarge")
titleText:SetPoint("TOPLEFT", 18, -16)
VCA.OnTheme(function() titleText:SetText(VCA.TitleText()) end)

-- X close button (uses the standard Blizzard close button template)
local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
    Panel.SetMinimized(true)
    frame:Hide()
end)

-- Pin button, just left of the X: pinned = stuck to the Adventure Guide, unpinned = free to move.
-- The panel and the two overviews each get one; the state is shared by the three windows.
local pinButtons = {}
local pinWindows = {} -- the windows that re-anchor themselves with their own AnchorToEJ

function Panel.CreatePinButton(owner, closeButton, reanchor)
    local btn = CreateFrame("Button", nil, owner)
    btn:SetSize(22, 22)
    btn:SetPoint("RIGHT", closeButton, "LEFT", 4, 2)
    btn:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    btn:SetScript("OnClick", function()
        Panel.SetPinned(not Panel.IsPinned(), owner)
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(Panel.IsPinned() and L["PANEL_PINNED_TIP"] or L["PANEL_UNPINNED_TIP"], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    pinButtons[#pinButtons + 1] = btn
    if reanchor then
        pinWindows[#pinWindows + 1] = {frame = owner, anchor = reanchor}
    end
    return btn
end

local pinBtn = Panel.CreatePinButton(frame, closeBtn)
Panel.pinBtn = pinBtn

-- Persist item selections when the panel hides (close, navigate away, logout).
frame:SetScript("OnHide", function()
    Panel.ClearPending()
    Panel.SaveItemSelections()
end)

-- Source name (boss or dungeon)
local sourceLabel = frame:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
sourceLabel:SetPoint("TOPLEFT", 18, -42)
sourceLabel:SetPoint("TOPRIGHT", -40, -42)
sourceLabel:SetJustifyH("LEFT")
sourceLabel:SetWordWrap(false)
sourceLabel:SetText("")
Panel.sourceLabel = sourceLabel

-- Content type + Voidcore cost
local infoLabel = frame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
infoLabel:SetPoint("TOPLEFT", 18, -60)
infoLabel:SetJustifyH("LEFT")
infoLabel:SetText("")
Panel.infoLabel = infoLabel

-- Horizontal divider
local divider = frame:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(0.16, 0.25, 0.18, 1)
divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -HEADER_H)
divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -HEADER_H)
divider:SetHeight(1)

-- ── Content area ─────────────────────────────────────────────────────────────
-- Two side-by-side columns below the divider.

local contentArea = CreateFrame("Frame", nil, frame)
contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(HEADER_H + 1))
contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 11)
Panel.contentArea = contentArea

-- ── Column widths ─────────────────────────────────────────────────────────────

-- Recomputed each Refresh so dynamic resizing (future) is easy.
local function ContentWidth()
    return frame:GetWidth() - PADDING * 2
end

local function LeftColWidth()
    return math.floor(ContentWidth() * COL_SPLIT)
end

local function RightColWidth()
    return ContentWidth() - LeftColWidth() - 1 -- 1px for the vertical separator
end

_s.LeftColWidth = LeftColWidth
_s.RightColWidth = RightColWidth

-- ── Column header labels ──────────────────────────────────────────────────────

local lootColHeader = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
lootColHeader:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, -6)
lootColHeader:SetJustifyH("LEFT")
VCA.OnTheme(function() lootColHeader:SetText(VCA.Theme.hdr .. "LOOT|r") end)

-- X button to clear all spec selections (near the center divider in loot column header)
local clearSpecBtn = CreateFrame("Button", nil, contentArea)
clearSpecBtn:SetSize(14, 14)
clearSpecBtn:SetNormalFontObject("VCAFontNormal")
clearSpecBtn:SetText("|cffff4444x|r")
clearSpecBtn:SetScript("OnClick", function()
    wipe(selectedSpecIDs)
    wipe(selectedItemIDs)
    Panel.SaveItemSelections()
    Panel.RefreshSpecColumn()
    Panel.RefreshItemColumn()
end)
clearSpecBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["CLEAR_SELECTED"])
    GameTooltip:Show()
end)
clearSpecBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
clearSpecBtn:Hide()

-- ── Key level dropdown (M+ only) ─────────────────────────────────────────────
local selectedKeyLevel = 10 -- default to 10+

local keyLevelButton = CreateFrame("Button", nil, contentArea)
keyLevelButton:SetSize(50, 16)
keyLevelButton:SetPoint("LEFT", lootColHeader, "RIGHT", 6, 0)
keyLevelButton:Hide()

local keyLevelText = keyLevelButton:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
keyLevelText:SetAllPoints(keyLevelButton)
keyLevelText:SetJustifyH("LEFT")

local function GetKeyLevelLabel(level)
    return "+" .. level
end

local function GetRewardForKeyLevel(level)
    return VCA.MythicPlusVaultRewards[math.min(level, 10)]
end

_s.GetRewardForKeyLevel = GetRewardForKeyLevel
_s.getSelectedKeyLevel = function()
    return selectedKeyLevel
end

local function UpdateKeyLevelText()
    local reward = GetRewardForKeyLevel(selectedKeyLevel)
    local track = reward and reward.track or "?"
    keyLevelText:SetText("|cffdddddd" .. GetKeyLevelLabel(selectedKeyLevel) .. "|r |cff888888(" .. track .. ")|r")
    -- Resize button to fit text
    keyLevelButton:SetWidth(keyLevelText:GetStringWidth() + 8)
end

local keyLevelMenu = CreateFrame("Frame", nil, keyLevelButton, "BackdropTemplate")
keyLevelMenu:SetFrameStrata("TOOLTIP")
keyLevelMenu:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {
        left = 3,
        right = 3,
        top = 3,
        bottom = 3
    }
})
VCA.OnTheme(function() local t = VCA.Theme.bg; keyLevelMenu:SetBackdropColor(t[1], t[2], t[3], 0.97) end)
VCA.OnTheme(function() local t = VCA.Theme.border; keyLevelMenu:SetBackdropBorderColor(t[1], t[2], t[3], 1) end)
keyLevelMenu:Hide()

local keyLevelOptions = {2, 3, 4, 5, 6, 7, 8, 9, 10}
local menuButtons = {}
for i, level in ipairs(keyLevelOptions) do
    local btn = CreateFrame("Button", nil, keyLevelMenu)
    btn:SetSize(70, 16)
    btn:SetPoint("TOPLEFT", keyLevelMenu, "TOPLEFT", 4, -(4 + (i - 1) * 16))
    local label = btn:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
    label:SetAllPoints(btn)
    label:SetJustifyH("LEFT")
    btn.label = label
    btn.level = level

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(btn)
    highlight:SetColorTexture(VCA.Theme.accent[1], VCA.Theme.accent[2], VCA.Theme.accent[3], 0.25)

    btn:SetScript("OnClick", function(self)
        selectedKeyLevel = self.level
        UpdateKeyLevelText()
        keyLevelMenu:Hide()
        Panel.Refresh()
    end)
    menuButtons[i] = btn
end
keyLevelMenu:SetSize(78, 8 + #keyLevelOptions * 16)

local function ShowKeyLevelMenu()
    for i, btn in ipairs(menuButtons) do
        local level = btn.level
        local reward = GetRewardForKeyLevel(level)
        local track = reward and reward.track or "?"
        local lbl = GetKeyLevelLabel(level) .. "  |cff888888" .. track .. "|r"
        if level == selectedKeyLevel then
            lbl = "|cffffff00" .. lbl .. "|r"
        end
        btn.label:SetText(lbl)
    end
    keyLevelMenu:ClearAllPoints()
    keyLevelMenu:SetPoint("TOPLEFT", keyLevelButton, "BOTTOMLEFT", 0, -2)
    keyLevelMenu:Show()
end

keyLevelButton:SetScript("OnClick", function()
    if keyLevelMenu:IsShown() then
        keyLevelMenu:Hide()
    else
        ShowKeyLevelMenu()
    end
end)

-- Close menu when clicking elsewhere
keyLevelMenu:SetScript("OnShow", function(self)
    self:SetPropagateKeyboardInput(true)
end)
keyLevelMenu:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
        self:Hide()
        self:SetPropagateKeyboardInput(false)
    else
        self:SetPropagateKeyboardInput(true)
    end
end)

local specColHeader = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
specColHeader:SetJustifyH("LEFT")
VCA.OnTheme(function() specColHeader:SetText(VCA.Theme.hdr .. "" .. L["COL_SPEC_RANKING"] .. "|r") end)

-- X button to clear all item selections (near the center divider in spec column header)
local clearItemBtn = CreateFrame("Button", nil, contentArea)
clearItemBtn:SetSize(14, 14)
clearItemBtn:SetNormalFontObject("VCAFontNormal")
clearItemBtn:SetText("|cffff4444x|r")
clearItemBtn:SetScript("OnClick", function()
    wipe(selectedItemIDs)
    Panel.SaveItemSelections()
    Panel.RefreshSpecColumn()
    Panel.RefreshItemColumn()
end)
clearItemBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["CLEAR_SELECTED"])
    GameTooltip:Show()
end)
clearItemBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
clearItemBtn:Hide()

-- "+" button: choose everything your loot spec can still get from this source.
local selectAllBtn = CreateFrame("Button", nil, contentArea)
selectAllBtn:SetSize(14, 14)
selectAllBtn:SetNormalFontObject("VCAFontNormal")
selectAllBtn:SetText("|cff66ff66+|r")
selectAllBtn:SetScript("OnClick", function()
    Panel.SelectAllUseful()
end)
selectAllBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["SELECT_ALL_USEFUL"])
    GameTooltip:AddLine(L["SELECT_ALL_USEFUL_TIP"], nil, nil, nil, true)
    GameTooltip:Show()
end)
selectAllBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Cumulative odds line at the bottom of the spec column (filled by PanelColumns).
local cumLabel = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
cumLabel:SetJustifyH("LEFT")
cumLabel:SetJustifyV("BOTTOM")
cumLabel:SetWordWrap(true)
_s.cumLabel = cumLabel

-- Mark-roll mode: while active, clicking a loot row marks (or unmarks) the item
-- as obtained for every spec, for rolls the addon did not track.
Panel.markMode = false
Panel.pendingMarks = {} -- { [itemID] = true (mark) | false (unmark) }, saved when the bar is pressed again
-- Bar fixed to the bottom of the loot column, so it never collides with the
-- key level selector that sits next to the "LOOT" title on Mythic+ sources.
local MARK_BAR_H = 24
local markModeBtn = CreateFrame("Button", nil, contentArea, "BackdropTemplate")
markModeBtn:SetHeight(MARK_BAR_H)
markModeBtn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1
})
local markModeText = markModeBtn:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
markModeText:SetPoint("LEFT", markModeBtn, "LEFT", 6, 0)
markModeText:SetPoint("RIGHT", markModeBtn, "RIGHT", -6, 0)
markModeText:SetJustifyH("CENTER")
markModeText:SetWordWrap(false)
markModeBtn.text = markModeText
local markHover = markModeBtn:CreateTexture(nil, "HIGHLIGHT")
markHover:SetAllPoints()
local markHovered = false
local function PaintMarkModeButton()
    local t = VCA.Theme
    if Panel.markMode then
        if markHovered then
            markModeBtn:SetBackdropColor(0.30, 0.16, 0.03, 1)
            markModeBtn:SetBackdropBorderColor(1, 0.64, 0.18, 1)
        else
            markModeBtn:SetBackdropColor(0.22, 0.12, 0.02, 1)
            markModeBtn:SetBackdropBorderColor(0.85, 0.5, 0.1, 1)
        end
        markHover:SetColorTexture(1, 0.6, 0.15, 0.1)
    else
        local f = markHovered and 1 or 0.5
        markModeBtn:SetBackdropColor(t.timerBg[1] + (t.timer[1] - t.timerBg[1]) * f,
            t.timerBg[2] + (t.timer[2] - t.timerBg[2]) * f, t.timerBg[3] + (t.timer[3] - t.timerBg[3]) * f, 1)
        markModeBtn:SetBackdropBorderColor(t.accent[1], t.accent[2], t.accent[3], 1)
        markHover:SetColorTexture(t.accent[1], t.accent[2], t.accent[3], 0.18)
    end
end
local function UpdateMarkModeButton()
    PaintMarkModeButton()
    if Panel.markMode then
        local n = 0
        for _ in pairs(Panel.pendingMarks) do
            n = n + 1
        end
        markModeText:SetText("|cffffb347" .. L["MARK_MODE_ACTIVE"] .. (n > 0 and (" (" .. n .. ")") or "") .. "|r")
    else
        markModeText:SetText("+ " .. L["MARK_MODE_BUTTON"])
    end
end
-- Saves the staged marks: every item whose staged state differs from the stored one is
-- toggled with the same code as the bag icon, so all specs and the roll log are updated.
local function IsStored(c)
    for _, sp in ipairs(c.specs or {}) do
        if VCA.Data.IsObtainedForKeyTier(c.sourceType, c.sourceID, c.diffID, sp.specID, c.itemID, c.isHighTier) then
            return true
        end
    end
    return VCA.Data.IsObtainedMigrated(c.sourceType, c.sourceID, c.diffID, c.itemID) and true or false
end

local function CommitPendingMarks()
    local staged = {}
    for itemID, want in pairs(Panel.pendingMarks) do
        staged[#staged + 1] = {itemID, want}
    end
    wipe(Panel.pendingMarks)
    -- What you mark by hand stays marked: completing a spec's pool must not trigger the
    -- automatic reset that clears every item of the boss.
    Panel.keepMarks = true
    for _, entry in ipairs(staged) do
        local itemID, want = entry[1], entry[2]
        for _, r in ipairs(_s.itemRows) do
            local cb = r.checkbox
            if r.frame:IsShown() and cb.itemID == itemID then
                -- The row is rebuilt after every toggle, so keep a copy of what it holds now.
                local c = {
                    itemID = itemID,
                    itemLink = cb.itemLink,
                    sourceType = cb.sourceType,
                    sourceID = cb.sourceID,
                    diffID = cb.diffID,
                    isHighTier = cb.isHighTier,
                    isObtained = cb.isObtained,
                    specs = cb.specs
                }
                if (c.isObtained and true or false) ~= want then
                    local toggle = cb:GetScript("OnClick")
                    if toggle then
                        local ok, err = pcall(toggle, cb)
                        if not ok then
                            print(VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r " .. tostring(err))
                        end
                    end
                    -- Safety net: if the normal path left it unchanged, write it for every spec.
                    if IsStored(c) ~= want then
                        for _, sp in ipairs(c.specs or {}) do
                            if want then
                                VCA.Data.SetObtainedForKeyTier(c.sourceType, c.sourceID, c.diffID, sp.specID,
                                    itemID, c.isHighTier, true)
                            else
                                VCA.Data.SetObtained(c.sourceType, c.sourceID, c.diffID, sp.specID, itemID, false)
                            end
                        end
                        if not want then
                            VCA.Data.SetObtained(c.sourceType, c.sourceID, c.diffID, 0, itemID, false)
                        end
                    end
                end
                break
            end
        end
    end
    Panel.keepMarks = false
end

Panel.CommitPendingMarks = CommitPendingMarks

-- Leaves mark mode and forgets anything that was not saved.
function Panel.ClearPending()
    wipe(Panel.pendingMarks)
    Panel.markMode = false
    Panel.lastMarkItemID = nil
    UpdateMarkModeButton()
end

markModeBtn:SetScript("OnClick", function()
    if Panel.markMode then
        CommitPendingMarks()
        Panel.markMode = false
    else
        Panel.markMode = true
    end
    Panel.lastMarkItemID = nil
    UpdateMarkModeButton()
    Panel.RefreshItemColumn()
end)
markModeBtn:SetScript("OnEnter", function(self)
    markHovered = true
    PaintMarkModeButton()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["MARK_MODE_BUTTON"], 1, 1, 1)
    GameTooltip:AddLine(L["MARK_MODE_TIP"], nil, nil, nil, true)
    GameTooltip:AddLine(L["MARK_MODE_SHIFT_TIP"], 0.9, 0.8, 0.4, true)
    GameTooltip:Show()
end)
markModeBtn:SetScript("OnLeave", function()
    markHovered = false
    PaintMarkModeButton()
    GameTooltip:Hide()
end)
markModeBtn:Hide()
UpdateMarkModeButton()
VCA.OnTheme(PaintMarkModeButton)

local lootSpecLabel = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
lootSpecLabel:SetJustifyH("LEFT")
lootSpecLabel:SetText("")

-- ── Voidcache icon button (spec column header, right of loot spec label) ──────
-- EJ difficulty → SetItemByID item-context argument
local _raidDiffToContext = {
    [VCA.Difficulty.RAID_NORMAL] = 3,
    [VCA.Difficulty.RAID_LFR] = 4,
    [VCA.Difficulty.RAID_HEROIC] = 5,
    [VCA.Difficulty.RAID_MYTHIC] = 6
}
-- Currently displayed voidcache item ID; kept in sync by Refresh / ClearContext.
local _currentVoidcacheID = nil

local voidcacheIconBtn = CreateFrame("Button", nil, contentArea)
voidcacheIconBtn:SetSize(16, 16)
voidcacheIconBtn:Hide()

local voidcacheIconTex = voidcacheIconBtn:CreateTexture(nil, "ARTWORK")
voidcacheIconTex:SetAllPoints(voidcacheIconBtn)
voidcacheIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local voidcacheIconHL = voidcacheIconBtn:CreateTexture(nil, "HIGHLIGHT")
voidcacheIconHL:SetAllPoints(voidcacheIconBtn)
voidcacheIconHL:SetColorTexture(1, 1, 1, 0.25)

local function ShowVoidcacheTooltip(owner)
    if not _currentVoidcacheID then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    if Panel.sourceType == VCA.ContentType.MYTHIC_PLUS then
        GameTooltip:SetItemByID(_currentVoidcacheID, nil, 16, selectedKeyLevel)
    elseif Panel.sourceType == VCA.ContentType.RAID then
        local ctx = _raidDiffToContext[Panel.difficultyID]
        if ctx then
            GameTooltip:SetItemByID(_currentVoidcacheID, nil, ctx)
        else
            GameTooltip:SetItemByID(_currentVoidcacheID)
        end
    end
    GameTooltip:Show()
end

voidcacheIconBtn:SetScript("OnEnter", function(self)
    ShowVoidcacheTooltip(self)
end)
voidcacheIconBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Vertical separator between columns
local colSep = contentArea:CreateTexture(nil, "ARTWORK")

-- Expose column header widgets for PanelColumns.lua
_s.lootColHeader = lootColHeader
_s.clearSpecBtn = clearSpecBtn
_s.specColHeader = specColHeader
_s.clearItemBtn = clearItemBtn
colSep:SetColorTexture(0.16, 0.25, 0.18, 1)
colSep:SetWidth(1)

-- Horizontal rule below column headers
local colHeaderRule = contentArea:CreateTexture(nil, "ARTWORK")
colHeaderRule:SetColorTexture(0.4, 0.4, 0.4, 0.3)
colHeaderRule:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, -(COL_HEADER_H + 2))
colHeaderRule:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -PADDING, -(COL_HEADER_H + 2))
colHeaderRule:SetHeight(1)

-- ── Item quality color escape sequence ───────────────────────────────────────
-- Uses |cnIQn: syntax (added in 11.1.5).

local function QualityColor(quality)
    return "|cnIQ" .. (quality or 1) .. ":"
end

_s.QualityColor = QualityColor

-- ── Tooltip: M+ bonus ID injection ──────────────────────────────────────────
-- Builds a modified item hyperlink string with bonus IDs matching the
-- selected key level so the tooltip renders at the correct item level.

local function BuildMythicPlusTooltipLink(itemLink)
    local reward = GetRewardForKeyLevel(selectedKeyLevel)
    if not reward then
        return nil
    end

    local itemString = itemLink:match("item[%-?%d:]+")
    if not itemString then
        return nil
    end

    local fields = {}
    for field in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    -- Ensure at least 14 fields (up to numBonusIDs position)
    while #fields < 14 do
        fields[#fields + 1] = ""
    end
    -- Field 13 = context (35 = M+ context)
    fields[13] = "35"

    local numBonuses = tonumber(fields[14]) or 0
    -- Collect existing bonus IDs, stripping 3524 if present
    local newBonuses = {}
    for bi = 15, 14 + numBonuses do
        if fields[bi] ~= "3524" then
            newBonuses[#newBonuses + 1] = fields[bi]
        end
    end

    -- Append the M+ base bonus IDs and the key-level-specific track bonus
    for _, b in ipairs(VCA.MythicPlusBonusIDs) do
        newBonuses[#newBonuses + 1] = tostring(b)
    end
    newBonuses[#newBonuses + 1] = tostring(reward.bonusID)

    -- Remove old bonus entries from fields, insert new ones
    for _ = 1, numBonuses do
        table.remove(fields, 15)
    end
    fields[14] = tostring(#newBonuses)
    for i, b in ipairs(newBonuses) do
        table.insert(fields, 14 + i, b)
    end

    return table.concat(fields, ":")
end

_s.BuildMythicPlusTooltipLink = BuildMythicPlusTooltipLink

-- Tracks the current EJ loot filter so it can be temporarily cleared and
-- restored without depending on a non-existent getter API.
local _ejFilterClassID = 0
local _ejFilterSpecID = 0
hooksecurefunc("EJ_SetLootFilter", function(classID, specID)
    if VCA.LootPool._reentryGuard then
        return
    end
    _ejFilterClassID = classID or 0
    _ejFilterSpecID = specID or 0
end)

-- Returns the item link for a raid item directly from the EJ so the tooltip
-- shows the correct difficulty item level. Temporarily clears the loot filter
-- so all items are visible regardless of the current spec filter, then restores
-- the filter to the player's loot spec.
--
-- _ejFilterClassID/_ejFilterSpecID track explicit EJ_SetLootFilter calls.
-- Blizzard sets the EJ filter internally when the journal opens without calling
-- EJ_SetLootFilter, so those values start at 0/0. When they are 0/0 we seed
-- the restore target from the player's actual class and loot spec so we don't
-- accidentally leave the EJ showing "All Specializations".
local function GetRaidEJItemLink(itemID)
    if not C_EncounterJournal or not C_EncounterJournal.GetLootInfoByIndex then
        return nil
    end
    local savedClass = _ejFilterClassID
    local savedSpec = _ejFilterSpecID
    if savedClass == 0 and savedSpec == 0 then
        savedClass = VCA.SpecInfo.GetPlayerClassID() or 0
        savedSpec = VCA.SpecInfo.GetEffectiveLootSpecID() or 0
    end
    VCA.LootPool._reentryGuard = true
    EJ_SetLootFilter(0, 0)
    local numLoot = EJ_GetNumLoot and EJ_GetNumLoot() or 0
    local result = nil
    for i = 1, numLoot do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID == itemID and info.link and info.link ~= "" then
            result = info.link
            break
        end
    end
    -- Update tracking before restoring so the next call remembers the spec.
    _ejFilterClassID = savedClass
    _ejFilterSpecID = savedSpec
    EJ_SetLootFilter(savedClass, savedSpec)
    VCA.LootPool._reentryGuard = false
    return result
end

-- ── Raid tooltip: keep the item's effect text ─────────────────────────────────
-- Some items show their "Equip:/Use:" effect only when their link carries the extra bonus ID
-- 13708 (real drops of those items have it).  Instead of listing the items by hand, the tooltip
-- data of the built link is compared with the plain item's: when an effect line is lost, the
-- link is rebuilt with 13708 and kept if the effect comes back.  The verdict is remembered.
local EFFECT_BONUS = "13708"
local effectFix = {} -- ["itemID:difficulty"] = true (needs 13708) / false (does not)

local function EffectPrefixes()
    local prefixes = {}
    for _, pair in ipairs({{"ITEM_SPELL_TRIGGER_ONEQUIP", "Equip:"}, {"ITEM_SPELL_TRIGGER_ONUSE", "Use:"},
                           {"ITEM_SPELL_TRIGGER_ONPROC", "Chance on hit:"}}) do
        local value = _G[pair[1]]
        prefixes[#prefixes + 1] = type(value) == "string" and value or pair[2]
    end
    return prefixes
end

-- Number of effect lines in tooltip data; nil while the data is not available yet.
local function CountEffectLines(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        return nil
    end
    local prefixes = EffectPrefixes()
    local count = 0
    for i = 1, #data.lines do
        local line = data.lines[i]
        local text = type(line) == "table" and line.leftText
        if type(text) == "string" then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            for _, prefix in ipairs(prefixes) do
                if text:sub(1, #prefix) == prefix then
                    count = count + 1
                    break
                end
            end
        end
    end
    return count
end

local function TooltipEffectCount(getter, arg)
    if not (C_TooltipInfo and getter) then
        return nil
    end
    local ok, data = pcall(getter, arg)
    if not ok then
        return nil
    end
    return CountEffectLines(data)
end

-- Does this item need the effect bonus on this difficulty?  nil = cannot tell yet.
local function NeedsEffectBonus(itemID, difficultyID, linkWithout, linkWith)
    local key = itemID .. ":" .. difficultyID
    if effectFix[key] ~= nil then
        return effectFix[key]
    end
    if not (C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetHyperlink) then
        return nil
    end
    local base = TooltipEffectCount(C_TooltipInfo.GetItemByID, itemID)
    local plain = TooltipEffectCount(C_TooltipInfo.GetHyperlink, linkWithout)
    if not base or not plain then
        return nil
    end
    local needs = false
    if plain < base then
        local withBonus = TooltipEffectCount(C_TooltipInfo.GetHyperlink, linkWith)
        if not withBonus then
            return nil
        end
        needs = withBonus > plain
    end
    effectFix[key] = needs
    return needs
end

-- Builds a raid item link showing the correct Voidcore reward track and ilvl.
-- Keeps linkLevel (f[10]) for correct ilvl; clears specID (f[11]) which suppresses
-- the "Upgrade Level" display when set.  encounterID defaults to the boss on screen.
local function BuildRaidTooltipLink(itemLink, difficultyID, encounterID)
    local info = VCA.RaidVoidcoreTooltip[difficultyID]
    if not info or not itemLink or itemLink == "" then
        return nil
    end

    local itemString = itemLink:match("item[%-?%d:]+")
    if not itemString then
        return nil
    end

    local fields = {}
    for field in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    while #fields < 14 do
        fields[#fields + 1] = ""
    end

    local numBonuses = tonumber(fields[14]) or 0
    local itemID = tonumber(fields[2])
    local isSpecial = VCA.RaidTooltipExtraBonusItems and VCA.RaidTooltipExtraBonusItems[itemID]

    -- Check for encounter-specific bonus override (keyed by difficulty + encounterID).
    local encounterBonus = VCA.RaidEncounterTooltipBonus and VCA.RaidEncounterTooltipBonus[difficultyID] and
                               VCA.RaidEncounterTooltipBonus[difficultyID][encounterID or Panel.sourceID]

    fields[11] = "" -- clear loot specID; its presence suppresses the track label
    fields[13] = info.ctx

    -- Assembles the link for a bonus list (the fields above are copied, never changed).
    local function assemble(newBonuses)
        local out = {}
        for i, v in ipairs(fields) do
            out[i] = v
        end
        for _ = 1, numBonuses do
            table.remove(out, 15)
        end
        out[14] = tostring(#newBonuses)
        for i, b in ipairs(newBonuses) do
            table.insert(out, 14 + i, b)
        end
        -- Zero numModifiers so source modifier data cannot override the injected rank.
        local numModsPos = 15 + #newBonuses
        if out[numModsPos] then
            out[numModsPos] = "0"
        end
        return table.concat(out, ":")
    end

    -- Bonus list: [tag?, 13708 if the item needs it, track]
    local newBonuses = {}
    if encounterBonus then
        newBonuses = encounterBonus
    elseif isSpecial and difficultyID == VCA.Difficulty.RAID_MYTHIC then
        -- Special items on Mythic use 3524 (original Mythic tag) instead of 13335.
        newBonuses = {"3524", tostring(info.bonus)}
    else
        local without = {}
        if info.tag then
            without[#without + 1] = tostring(info.tag)
        end
        without[#without + 1] = tostring(info.bonus)
        local withEffect = {}
        for i, b in ipairs(without) do
            withEffect[i] = b
        end
        table.insert(withEffect, #withEffect, EFFECT_BONUS) -- before the track, as in the real drops

        if isSpecial or (itemID and NeedsEffectBonus(itemID, difficultyID, assemble(without), assemble(withEffect))) then
            newBonuses = withEffect
        else
            newBonuses = without
        end
    end

    return assemble(newBonuses)
end

Panel.BuildRaidTooltipLink = BuildRaidTooltipLink

-- Checks every item of the season raids on Normal, Heroic and Mythic: reports the ones whose
-- tooltip still loses an effect line.  Item data loads in the background, so it works in
-- rounds.  Run with /void tooltips.
function Panel.AuditRaidTooltips()
    local raids = VCA.SeasonData and VCA.SeasonData.raids
    if not raids then
        return
    end
    local jobs, seen = {}, {}
    for encounterID, raidData in pairs(raids) do
        for _, diffID in ipairs({14, 15, 16}) do
            local sample = raidData.bonusByDiff and raidData.bonusByDiff[diffID]
            local pool = raidData[diffID]
            if sample and type(pool) == "table" then
                for _, itemID in ipairs(pool) do
                    local key = itemID .. ":" .. diffID
                    if not seen[key] then
                        seen[key] = true
                        jobs[#jobs + 1] = {
                            itemID = itemID,
                            diffID = diffID,
                            encounterID = encounterID,
                            link = sample:gsub("item:%d+", "item:" .. itemID, 1)
                        }
                    end
                end
            end
        end
    end
    local title = VCA.Theme.title .. "VoidcoreAdvisor Reborn:|r "
    print(title .. string.format(L["TOOLTIP_AUDIT_START"], #jobs))
    for _, job in ipairs(jobs) do
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(job.itemID)
        end
    end
    local round, fixed, bad, unknown = 0, 0, {}, 0
    local function run()
        round = round + 1
        fixed, bad, unknown = 0, {}, 0
        for _, job in ipairs(jobs) do
            local link = BuildRaidTooltipLink(job.link, job.diffID, job.encounterID)
            local verdict = effectFix[job.itemID .. ":" .. job.diffID]
            if verdict == nil and not (VCA.RaidTooltipExtraBonusItems and VCA.RaidTooltipExtraBonusItems[job.itemID]) and
                not (VCA.RaidEncounterTooltipBonus and VCA.RaidEncounterTooltipBonus[job.diffID] and
                    VCA.RaidEncounterTooltipBonus[job.diffID][job.encounterID]) then
                unknown = unknown + 1
            elseif verdict then
                fixed = fixed + 1
            end
            if link and C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetHyperlink then
                local base = TooltipEffectCount(C_TooltipInfo.GetItemByID, job.itemID)
                local built = TooltipEffectCount(C_TooltipInfo.GetHyperlink, link)
                if base and built and built < base then
                    bad[#bad + 1] = (C_Item.GetItemNameByID(job.itemID) or job.itemID) .. " (" .. job.diffID .. ")"
                end
            end
        end
        if unknown > 0 and round < 4 then
            C_Timer.After(1.5, run)
            return
        end
        print(title .. string.format(L["TOOLTIP_AUDIT_DONE"], fixed, unknown, #bad))
        for i = 1, math.min(#bad, 25) do
            print("  " .. bad[i])
        end
    end
    C_Timer.After(1.5, run)
end

-- ── Tooltip: obtained-spec lines ───────────────────────────────────────────
-- Appends "Obtained as:" spec lines to whatever tooltip is currently open.
-- Called before every GameTooltip:Show() on item icon hover.
local function AppendObtainedSpecLines(rf)
    local specs = rf.checkbox and rf.checkbox.specs
    if not specs or #specs == 0 then
        return
    end
    if not (Panel.sourceType and Panel.sourceID and Panel.difficultyID) then
        return
    end
    local itemID = rf.itemID
    if not itemID then
        return
    end

    local obtainedSpecs = {}
    for _, sp in ipairs(specs) do
        if VCA.Data.IsObtained(Panel.sourceType, Panel.sourceID, Panel.difficultyID, sp.specID, itemID) then
            obtainedSpecs[#obtainedSpecs + 1] = sp
        end
    end
    local migratedObtained = VCA.Data.IsObtainedMigrated(Panel.sourceType, Panel.sourceID, Panel.difficultyID, itemID)
    if #obtainedSpecs == 0 and not migratedObtained then
        return
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["SPEC_PICKER_TITLE"], 1, 1, 1)
    for _, sp in ipairs(obtainedSpecs) do
        GameTooltip:AddLine("|T" .. sp.icon .. ":12:12:0:0:64:64:4:60:4:60|t " .. sp.name, 0.4, 1.0, 0.4)
    end
    if migratedObtained then
        GameTooltip:AddLine(L["OBTAINED_UNKNOWN_SPEC"], 1.0, 0.7, 0.1)
    end
end

-- ── Row pool helpers ──────────────────────────────────────────────────────────
-- We maintain two pools of recycled row frames so we never create more widgets
-- than necessary.
-- itemRows and specRows are exposed in Panel._s so PanelColumns.lua can
-- pass them to GetOrCreateItemRow / GetOrCreateSpecRow.
_s.itemRows = {}
local itemRows = _s.itemRows
_s.specRows = {}
local specRows = _s.specRows

local function GetOrCreateItemRow(pool, parent)
    for _, row in ipairs(pool) do
        if not row.frame:IsShown() then
            return row
        end
    end
    -- Create a new row.  Use Button so WoW always delivers mouse events even
    -- when nested inside a ScrollFrame, where plain Frame hit-testing can be
    -- unreliable.
    local rowFrame = CreateFrame("Button", nil, parent)
    rowFrame:SetHeight(ROW_H)
    rowFrame:RegisterForClicks("LeftButtonUp")

    -- Flash texture (used for detection highlight)
    local flash = rowFrame:CreateTexture(nil, "HIGHLIGHT")
    flash:SetAllPoints(rowFrame)
    flash:SetColorTexture(0, 1, 0, 0)

    -- Selection highlight (golden tint when the user clicks the row)
    local selHighlight = rowFrame:CreateTexture(nil, "BACKGROUND")
    selHighlight:SetAllPoints(rowFrame)
    selHighlight:SetColorTexture(1, 0.75, 0, 0)
    selHighlight:Hide()

    -- Red tint for items your loot spec (or the spec you picked) cannot get from this source.
    local redShade = rowFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    redShade:SetAllPoints(rowFrame)
    redShade:SetColorTexture(0.75, 0.05, 0.05, 0.38)
    redShade:Hide()

    local rowBg = rowFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    rowBg:SetAllPoints(rowFrame)
    rowBg:SetColorTexture(1, 1, 1, 0.04)

    -- Icon housed in its own Button so the tooltip fires only on icon hover.
    local iconButton = CreateFrame("Button", nil, rowFrame)
    iconButton:SetSize(ICON_SIZE, ICON_SIZE)
    iconButton:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)

    local icon = iconButton:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(iconButton)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim default icon border

    local iconBorder = iconButton:CreateTexture(nil, "OVERLAY")
    iconBorder:SetTexture("Interface/Common/WhiteIconFrame")
    iconBorder:SetAllPoints(iconButton)
    iconBorder:Hide()

    local nameLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetPoint("LEFT", iconButton, "RIGHT", 4, 0)
    nameLabel:SetPoint("RIGHT", rowFrame, "RIGHT", -20, 0)
    nameLabel:SetWordWrap(false)

    -- Loot icon button — replaces the CheckButton so we can use a bag icon.
    -- SetChecked / GetChecked shims keep PanelColumns.lua compatible.
    local checkbox = CreateFrame("Button", nil, rowFrame)
    checkbox:SetSize(16, 16)
    checkbox:SetPoint("RIGHT", rowFrame, "RIGHT", 0, 0)

    local checkboxTex = checkbox:CreateTexture(nil, "ARTWORK")
    checkboxTex:SetAllPoints(checkbox)
    checkboxTex:SetTexture("Interface\\Icons\\inv_misc_bag_07")
    checkboxTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    checkbox.tex = checkboxTex

    local checkboxHL = checkbox:CreateTexture(nil, "HIGHLIGHT")
    checkboxHL:SetAllPoints(checkbox)
    checkboxHL:SetColorTexture(1, 1, 1, 0.3)

    checkbox._obtained = false
    function checkbox:SetChecked(v)
        self._obtained = v
        if v == "migrated" then
            -- Amber: obtained but spec unknown (migrated from pre-spec save data).
            self.tex:SetVertexColor(1.0, 0.7, 0.1)
            self.tex:SetAlpha(1)
        elseif v then
            -- Green: obtained with a known spec.
            self.tex:SetVertexColor(0.4, 1.0, 0.4)
            self.tex:SetAlpha(1)
        else
            self.tex:SetVertexColor(1, 1, 1)
            self.tex:SetAlpha(0.30)
        end
    end
    function checkbox:GetChecked()
        return self._obtained
    end
    checkbox:SetChecked(false)

    -- Tooltip on icon hover only
    iconButton:SetScript("OnEnter", function(self)
        local rf = self:GetParent()
        local link = rf.itemLink
        local id = rf.itemID
        if not (link or id) then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

        -- Inject Voidcore reward bonus IDs so the tooltip shows the correct
        -- item level for the Nebulous Voidcore reward track (Myth 1/6).
        if link and link ~= "" then
            local modified
            if Panel.sourceType == VCA.ContentType.MYTHIC_PLUS and rf.itemSlot ~= "" then
                modified = BuildMythicPlusTooltipLink(link)
            elseif Panel.sourceType == VCA.ContentType.RAID then
                modified = BuildRaidTooltipLink(link, Panel.difficultyID)
            end
            if modified then
                local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, modified)
                if ok and GameTooltip:NumLines() and GameTooltip:NumLines() > 0 then
                    AppendObtainedSpecLines(rf)
                    GameTooltip:Show()
                    return
                end
                GameTooltip:ClearLines()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            end
        end

        if link and link ~= "" then
            GameTooltip:SetHyperlink(link)
        elseif id then
            GameTooltip:SetItemByID(id)
        end
        AppendObtainedSpecLines(rf)
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local row = {
        frame = rowFrame,
        flash = flash,
        selHighlight = selHighlight,
        redShade = redShade,
        iconButton = iconButton,
        icon = icon,
        iconBorder = iconBorder,
        nameLabel = nameLabel,
        checkbox = checkbox
    }

    -- Wire the selection click once at creation time so it is never lost when
    -- rows are recycled from the pool.
    rowFrame:SetScript("OnClick", function(self, btn)
        local id = self.itemID
        if not id then
            return
        end
        if Panel.markMode then
            local cb = row.checkbox
            if cb.itemID ~= id then
                return
            end
            -- What the row shows now (a staged mark wins over the stored state).
            local function shown(r)
                local staged = Panel.pendingMarks[r.frame.itemID]
                if staged ~= nil then
                    return staged
                end
                return r.checkbox.isObtained and true or false
            end
            local want = not shown(row)
            local ids = {id}
            if IsShiftKeyDown() and Panel.lastMarkItemID then
                -- Shift+click stages every item between the previous click and this one.
                local from, to
                for i, r in ipairs(pool) do
                    if r.frame:IsShown() then
                        if r.frame.itemID == Panel.lastMarkItemID then
                            from = i
                        end
                        if r == row then
                            to = i
                        end
                    end
                end
                if from and to then
                    ids = {}
                    for i = math.min(from, to), math.max(from, to) do
                        if pool[i].frame:IsShown() and pool[i].frame.itemID then
                            ids[#ids + 1] = pool[i].frame.itemID
                        end
                    end
                end
            end
            for _, itemID in ipairs(ids) do
                for _, r in ipairs(pool) do
                    if r.frame:IsShown() and r.frame.itemID == itemID then
                        local stored = r.checkbox.isObtained and true or false
                        if want == stored then
                            Panel.pendingMarks[itemID] = nil
                        else
                            Panel.pendingMarks[itemID] = want
                        end
                        break
                    end
                end
            end
            Panel.lastMarkItemID = id
            UpdateMarkModeButton()
            Panel.RefreshItemColumn()
            return
        end
        if self.dimmed then
            return
        end
        -- Toggle: click selects, click again deselects.
        if selectedItemIDs[id] then
            selectedItemIDs[id] = nil
        else
            selectedItemIDs[id] = true
        end
        -- Refresh highlight visuals on all visible rows immediately.
        for _, r in ipairs(pool) do
            if r.frame:IsShown() and r.frame.itemID then
                if selectedItemIDs[r.frame.itemID] then
                    r.selHighlight:SetColorTexture(1, 0.75, 0, 0.18)
                    r.selHighlight:Show()
                else
                    r.selHighlight:Hide()
                end
            end
        end
        Panel.RefreshSpecColumn()
        Panel.RefreshItemColumn()
        Panel.SaveItemSelections()
    end)

    pool[#pool + 1] = row
    return row
end

_s.GetOrCreateItemRow = GetOrCreateItemRow

-- Spec ranking row: rank, icon, name and the odds on top, a progress bar underneath.
local SPEC_ROW_H = 46
local SPEC_ICON = 28
_s.SPEC_ROW_H = SPEC_ROW_H

local function GetOrCreateSpecRow(pool, parent)
    for _, row in ipairs(pool) do
        if not row.frame:IsShown() then
            return row
        end
    end
    local rowFrame = CreateFrame("Button", nil, parent)
    rowFrame:SetHeight(SPEC_ROW_H)
    rowFrame:RegisterForClicks("LeftButtonUp")

    -- Soft green band and a bright left edge behind the best spec.
    local bestBg = rowFrame:CreateTexture(nil, "BACKGROUND", nil, -2)
    bestBg:SetAllPoints(rowFrame)
    bestBg:SetColorTexture(1, 1, 1, 0.1)
    bestBg:Hide()
    local bestEdge = rowFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    bestEdge:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 0, 0)
    bestEdge:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 0, 0)
    bestEdge:SetWidth(2)
    bestEdge:Hide()

    -- Selection highlight (tint when the spec is selected)
    local selHighlight = rowFrame:CreateTexture(nil, "BACKGROUND")
    selHighlight:SetAllPoints(rowFrame)
    selHighlight:SetColorTexture(VCA.Theme.accent[1], VCA.Theme.accent[2], VCA.Theme.accent[3], 0)
    selHighlight:Hide()

    local rowLine = rowFrame:CreateTexture(nil, "BORDER")
    rowLine:SetColorTexture(0.12, 0.2, 0.15, 1)
    rowLine:SetHeight(1)
    rowLine:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 0, 0)
    rowLine:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", 0, 0)

    local rankLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    rankLabel:SetJustifyH("RIGHT")
    rankLabel:SetWidth(30)
    rankLabel:SetWordWrap(false)
    rankLabel:SetPoint("LEFT", rowFrame, "LEFT", 2, 0)

    local icon = rowFrame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(SPEC_ICON, SPEC_ICON)
    icon:SetPoint("LEFT", rankLabel, "RIGHT", 5, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local nameLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
    nameLabel:SetPoint("RIGHT", rowFrame, "RIGHT", -70, 0)
    nameLabel:SetWordWrap(false)

    -- Progress bar under the name
    local barTrack = rowFrame:CreateTexture(nil, "BORDER")
    barTrack:SetColorTexture(0.02, 0.06, 0.04, 1)
    barTrack:SetHeight(5)
    barTrack:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 1)
    -- the bar stops before the column on the right, so it never covers the figures
    barTrack:SetPoint("RIGHT", rowFrame, "RIGHT", -78, 0)
    local barFill = rowFrame:CreateTexture(nil, "ARTWORK")
    barFill:SetHeight(5)
    barFill:SetPoint("BOTTOMLEFT", barTrack, "BOTTOMLEFT", 0, 0)

    -- Invisible hit-area for the warning icon (shown only when remainingCount == 1)
    local warnHitArea = CreateFrame("Button", nil, rowFrame)
    warnHitArea:SetSize(18, 18)
    warnHitArea:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 0)
    warnHitArea:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
    warnHitArea:EnableMouse(true)
    warnHitArea:SetScript("OnEnter", function(self)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    warnHitArea:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    warnHitArea:Hide()

    -- Main figure on the right (chance, or obtained/total when nothing is chosen) and a small line under it
    local statsLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormalLarge")
    statsLabel:SetJustifyH("RIGHT")
    statsLabel:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -6, -3)
    local countLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
    countLabel:SetJustifyH("RIGHT")
    countLabel:SetPoint("TOPRIGHT", statsLabel, "BOTTOMRIGHT", 0, -1)

    -- Spec selection click (single-select: selecting a new spec deselects the previous one)
    rowFrame:SetScript("OnClick", function(self, btn)
        local specID = self.specID
        if not specID then
            return
        end
        local wasSelected = selectedSpecIDs[specID]
        wipe(selectedSpecIDs)
        if not wasSelected then
            selectedSpecIDs[specID] = true
        end
        -- Update spec highlight visuals
        for _, r in ipairs(pool) do
            if r.frame:IsShown() and r.frame.specID then
                local a = VCA.Theme.accent
                if selectedSpecIDs[r.frame.specID] then
                    r.bestBg:SetColorTexture(a[1], a[2], a[3], 0.2)
                    r.bestEdge:SetColorTexture(a[1], a[2], a[3], 1)
                    r.bestBg:Show()
                    r.bestEdge:Show()
                else
                    r.bestBg:Hide()
                    r.bestEdge:Hide()
                end
                r.selHighlight:Hide()
            end
        end
        Panel.RefreshItemColumn()
    end)

    local row = {
        frame = rowFrame,
        selHighlight = selHighlight,
        bestBg = bestBg,
        bestEdge = bestEdge,
        rankLabel = rankLabel,
        icon = icon,
        nameLabel = nameLabel,
        statsLabel = statsLabel,
        countLabel = countLabel,
        barTrack = barTrack,
        barFill = barFill,
        warnHitArea = warnHitArea
    }
    pool[#pool + 1] = row
    return row
end

_s.GetOrCreateSpecRow = GetOrCreateSpecRow

local function HideAllItemRows()
    for _, row in ipairs(itemRows) do
        row.frame:Hide()
    end
end

local function HideAllSpecRows()
    for _, row in ipairs(specRows) do
        row.frame:Hide()
    end
end

_s.HideAllItemRows = HideAllItemRows
_s.HideAllSpecRows = HideAllSpecRows

-- ── Slot sort order ───────────────────────────────────────────────────────────
-- Maps INVTYPE_* equip-location strings to a numeric sort priority so the item
-- list reads like the character sheet: head first, trinkets last.
-- Finger/Ring and all weapon sub-types are collapsed into single categories.

local SLOT_SORT_ORDER = {
    -- Synthesis tokens (tier set tokens, Nullcores, etc.) have no equip slot;
    -- sort them first to match EJ ordering.
    INVTYPE_NON_EQUIP_IGNORE = 0,
    INVTYPE_HEAD = 1,
    INVTYPE_NECK = 2,
    INVTYPE_SHOULDER = 3,
    INVTYPE_CLOAK = 4,
    INVTYPE_CHEST = 5,
    INVTYPE_ROBE = 5,
    INVTYPE_WRIST = 6,
    INVTYPE_HAND = 7,
    INVTYPE_WAIST = 8,
    INVTYPE_LEGS = 9,
    INVTYPE_FEET = 10,
    INVTYPE_FINGER = 11,
    -- All weapon / off-hand types grouped together
    INVTYPE_WEAPON = 12,
    INVTYPE_2HWEAPON = 12,
    INVTYPE_WEAPONMAINHAND = 12,
    INVTYPE_WEAPONOFFHAND = 12,
    INVTYPE_HOLDABLE = 12,
    INVTYPE_SHIELD = 12,
    INVTYPE_RANGED = 12,
    INVTYPE_RANGEDRIGHT = 12,
    -- Trinkets last
    INVTYPE_TRINKET = 13
}

local function GetSlotSortOrder(itemID)
    if not itemID then
        return 99
    end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" then
        return 99
    end
    return SLOT_SORT_ORDER[equipLoc] or 99
end

_s.GetSlotSortOrder = GetSlotSortOrder

-- ── Populate item column ──────────────────────────────────────────────────────

local itemScrollChild = CreateFrame("Frame", nil, contentArea)
local itemScrollFrame = CreateFrame("ScrollFrame", nil, contentArea)
itemScrollFrame:SetScrollChild(itemScrollChild)

-- Mouse wheel scrolling
itemScrollFrame:EnableMouseWheel(true)
itemScrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetVerticalScroll()
    local maxScroll = math.max(0, itemScrollChild:GetHeight() - self:GetHeight())
    local step = ROW_H * 3
    local newScroll = math.max(0, math.min(maxScroll, current - delta * step))
    self:SetVerticalScroll(newScroll)
end)

-- Thin scrollbar track + thumb
local scrollTrack = itemScrollFrame:CreateTexture(nil, "BACKGROUND")
scrollTrack:SetWidth(4)
scrollTrack:SetColorTexture(0.1, 0.1, 0.1, 0.4)
scrollTrack:SetPoint("TOPRIGHT", itemScrollFrame, "TOPRIGHT", 5, 0)
scrollTrack:SetPoint("BOTTOMRIGHT", itemScrollFrame, "BOTTOMRIGHT", 5, 0)
scrollTrack:Hide()

local scrollThumb = itemScrollFrame:CreateTexture(nil, "OVERLAY")
scrollThumb:SetWidth(4)
scrollThumb:SetColorTexture(0.6, 0.6, 0.6, 0.6)
scrollThumb:Hide()

-- Expose scroll frame widgets and scrollbar for PanelColumns.lua
_s.itemScrollChild = itemScrollChild
_s.itemScrollFrame = itemScrollFrame
_s.scrollTrack = scrollTrack
_s.scrollThumb = scrollThumb

-- UpdateScrollbar is defined in PanelColumns.lua (loaded after this file).
-- The hook body runs at game time when PanelColumns.lua is already loaded.
itemScrollFrame:HookScript("OnMouseWheel", function()
    Panel.UpdateScrollbar()
end)

-- ── Populate spec column ──────────────────────────────────────────────────────

local specScrollChild = CreateFrame("Frame", nil, contentArea)
local specScrollFrame = CreateFrame("ScrollFrame", nil, contentArea)
specScrollFrame:SetScrollChild(specScrollChild)

_s.specScrollChild = specScrollChild
_s.specScrollFrame = specScrollFrame
-- ── Layout pass ───────────────────────────────────────────────────────────────
-- Recalculates all column/scroll frame positions.  Called on Refresh and on
-- frame resize (if we ever make it resizable).

local function DoLayout()
    local contentH = contentArea:GetHeight() - COL_HEADER_H - 10
    local leftW = LeftColWidth()
    local rightW = RightColWidth()
    local splitX = PADDING + leftW

    -- Column separator
    colSep:ClearAllPoints()
    colSep:SetPoint("TOP", contentArea, "TOPLEFT", splitX, -2)
    colSep:SetPoint("BOTTOM", contentArea, "BOTTOMLEFT", splitX, 2)

    -- Clear-spec-selection button (near center divider, inside loot column)
    clearSpecBtn:ClearAllPoints()
    clearSpecBtn:SetPoint("RIGHT", contentArea, "TOPLEFT", splitX - 4, -6 - (COL_HEADER_H / 2) + 4)

    -- Spec column header position (left col header is already anchored)
    specColHeader:ClearAllPoints()
    specColHeader:SetPoint("TOPLEFT", contentArea, "TOPLEFT", splitX + PADDING, -6)

    -- Clear-item-selection button (just left of center divider)
    clearItemBtn:ClearAllPoints()
    clearItemBtn:SetPoint("RIGHT", contentArea, "TOPLEFT", splitX - 22, -6 - (COL_HEADER_H / 2) + 4)

    selectAllBtn:ClearAllPoints()
    selectAllBtn:SetPoint("RIGHT", contentArea, "TOPLEFT", splitX - 40, -6 - (COL_HEADER_H / 2) + 4)

    cumLabel:ClearAllPoints()
    cumLabel:SetPoint("BOTTOMLEFT", contentArea, "BOTTOMLEFT", splitX + PADDING, 4)
    cumLabel:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -PADDING, 4)
    cumLabel:SetHeight(30)

    -- Voidcache icon (at the far right of the spec column header row)
    voidcacheIconBtn:ClearAllPoints()
    voidcacheIconBtn:SetPoint("RIGHT", contentArea, "TOPRIGHT", -PADDING, -6 - (COL_HEADER_H / 2) + 4)

    -- Loot spec label (right-aligned, to the left of the voidcache icon)
    -- Loot spec (icon + name) on its own line right under the ranking header
    lootSpecLabel:ClearAllPoints()
    lootSpecLabel:SetPoint("TOPLEFT", specColHeader, "BOTTOMLEFT", 0, -9)
    lootSpecLabel:SetPoint("RIGHT", contentArea, "RIGHT", -PADDING, 0)
    lootSpecLabel:SetWordWrap(false)

    -- Item scroll frame
    itemScrollFrame:ClearAllPoints()
    itemScrollFrame:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, -(COL_HEADER_H + 8))
    itemScrollFrame:SetPoint("BOTTOMLEFT", contentArea, "BOTTOMLEFT", PADDING, MARK_BAR_H + 10)
    itemScrollFrame:SetWidth(leftW - PADDING)

    markModeBtn:ClearAllPoints()
    markModeBtn:SetPoint("BOTTOMLEFT", contentArea, "BOTTOMLEFT", PADDING, 6)
    markModeBtn:SetWidth(leftW - PADDING)

    itemScrollChild:SetWidth(leftW - PADDING)

    -- Spec scroll frame
    specScrollFrame:ClearAllPoints()
    specScrollFrame:SetPoint("TOPLEFT", contentArea, "TOPLEFT", splitX + PADDING, -(COL_HEADER_H + 40))
    specScrollFrame:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -PADDING, 38)
    specScrollFrame:SetWidth(rightW - PADDING)

    specScrollChild:SetWidth(rightW - PADDING)
end

-- ── Move and resize ───────────────────────────────────────────────────────────
-- Drag the header to move the panel, drag the corner to resize it. The position
-- and size are remembered; /void resetpanel puts it back next to the journal.

frame:SetMovable(true)
frame:SetResizable(true)
if frame.SetResizeBounds then
    frame:SetResizeBounds(480, 340, 900, 1000)
end

local dragHandle = CreateFrame("Frame", nil, frame)
dragHandle:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
dragHandle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0)
dragHandle:SetHeight(HEADER_H)
dragHandle:EnableMouse(true)
dragHandle:RegisterForDrag("LeftButton")
dragHandle:SetScript("OnDragStart", function()
    -- Dragging a pinned panel lets it go.
    if Panel.IsPinned() then
        Panel.SetPinned(false)
    end
    Freeze()
    frame:StartMoving()
end)
dragHandle:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    SavePlacement()
end)

local grip = CreateFrame("Button", nil, frame)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
grip:SetFrameLevel(frame:GetFrameLevel() + 10)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetScript("OnMouseDown", function()
    if Panel.IsPinned() then
        return
    end
    if Freeze() then
        frame:StartSizing("BOTTOMRIGHT")
    end
end)
grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    SavePlacement()
    DoLayout()
    Panel.Refresh()
end)

frame:SetScript("OnSizeChanged", function()
    if frame:IsShown() then
        DoLayout()
    end
end)

-- Pins the panel to the Adventure Guide (true) or frees it where it is (false).
-- source is the window whose position becomes the free one (the panel unless an overview asks).
function Panel.SetPinned(pinned, source)
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    if not gdb then
        return
    end
    source = source or frame
    if pinned then
        gdb.panelFree = nil
        gdb.panelPlacement = nil
        Panel.AnchorToEJ()
        for _, w in ipairs(pinWindows) do
            w.anchor()
        end
    else
        gdb.panelFree = true
        if Freeze(source) then
            SavePlacement(source)
        end
        Panel.AnchorToEJ()
        for _, w in ipairs(pinWindows) do
            w.anchor()
        end
    end
    Panel.UpdatePinButton()
    if frame:IsShown() then
        DoLayout()
        Panel.Refresh()
    end
end

-- Pin icon (locked / unlocked) and the resize grip, which only a free panel has.
function Panel.UpdatePinButton()
    local pinned = Panel.IsPinned()
    local texture = pinned and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up"
    for _, b in ipairs(pinButtons) do
        b:SetNormalTexture(texture)
    end
    grip:SetShown(not pinned)
end

function Panel.ResetPlacement()
    Panel.SetPinned(true)
end

frame:HookScript("OnShow", function()
    Panel.UpdatePinButton()
end)

-- ── Context update ────────────────────────────────────────────────────────────

-- Persist the current item selection to the char DB.
function Panel.SaveItemSelections()
    if Panel.sourceType and Panel.sourceID and Panel.difficultyID then
        VCA.Data.SaveSelectedItems(Panel.sourceType, Panel.sourceID, Panel.difficultyID, selectedItemIDs)
    end
end

-- Reload in-memory selectedItemIDs from the DB for the current context.
-- Call this whenever an external system (e.g. slot-drawer) modifies the DB
-- directly so the Panel does not overwrite those changes on the next SetContext.
function Panel.ReloadItemSelections()
    if not (Panel.sourceType and Panel.sourceID and Panel.difficultyID) then
        return
    end
    wipe(selectedItemIDs)
    local saved = VCA.Data.GetSelectedItems(Panel.sourceType, Panel.sourceID, Panel.difficultyID)
    for id in pairs(saved) do
        selectedItemIDs[id] = true
    end
end

-- Chooses every item your loot spec can still get from the current source
-- (clear = true empties the choice instead). Returns how many items were chosen,
-- or nil when no boss or dungeon is open.
function Panel.SelectAllUseful(clear)
    if not (Panel.sourceType and Panel.sourceID and Panel.difficultyID) then
        return nil
    end
    wipe(selectedItemIDs)
    local count = 0
    if not clear then
        local specID = VCA.SpecInfo.GetEffectiveLootSpecID()
        local classID = VCA.SpecInfo.GetPlayerClassID()
        local isHighTier = nil
        if Panel.sourceType == VCA.ContentType.MYTHIC_PLUS then
            isHighTier = _s.getSelectedKeyLevel() >= 10
        end
        for _, itemID in ipairs(VCA.LootPool.GetItemsForSpec(Panel.sourceType, Panel.sourceID, Panel.difficultyID,
            classID, specID)) do
            if not VCA.Data.IsObtainedForKeyTier(Panel.sourceType, Panel.sourceID, Panel.difficultyID, specID, itemID,
                isHighTier) then
                selectedItemIDs[itemID] = true
                count = count + 1
            end
        end
    end
    Panel.SaveItemSelections()
    Panel.Refresh()
    return count
end

-- "[Mythic]" style tag shown after the boss or dungeon name, colored by difficulty.
local DIFFICULTY_COLORS = {[17] = "|cff66ccff", [14] = "|cff1eff00", [15] = "|cff0070dd", [16] = "|cffa335ee"}
local function DifficultyTag(sourceType, difficultyID)
    if sourceType == VCA.ContentType.MYTHIC_PLUS then
        return "  |cffff8000[" .. L["DIFFICULTY_MYTHIC_PLUS"] .. "]|r"
    end
    local name = GetDifficultyInfo and GetDifficultyInfo(difficultyID)
    if not name then
        return ""
    end
    return "  " .. (DIFFICULTY_COLORS[difficultyID] or "|cffffffff") .. "[" .. name .. "]|r"
end

function Panel.SetContext(sourceType, sourceID, difficultyID, sourceName, isRaid)
    -- Marks that were not saved belong to the previous source.
    Panel.ClearPending()
    -- Persist outgoing selections before switching context.
    Panel.SaveItemSelections()

    -- Restore saved item selection for this source (spec selection is transient).
    wipe(selectedItemIDs)
    wipe(selectedSpecIDs)
    local saved = VCA.Data.GetSelectedItems(sourceType, sourceID, difficultyID)
    for id in pairs(saved) do
        selectedItemIDs[id] = true
    end
    HideAllItemRows()
    HideAllSpecRows()

    Panel.sourceType = sourceType
    Panel.sourceID = sourceID
    Panel.difficultyID = difficultyID

    VCA.Detection.SetActiveSource(sourceType, sourceID, difficultyID)

    Panel.sourceName = sourceName or "" -- without the difficulty tag (EJHook re-applies it)
    sourceLabel:SetText(Panel.sourceName .. DifficultyTag(sourceType, difficultyID))
    Panel.isRaid = isRaid

    -- Show key level dropdown only for M+ dungeons
    if sourceType == VCA.ContentType.MYTHIC_PLUS then
        UpdateKeyLevelText()
        keyLevelButton:Show()
    else
        keyLevelButton:Hide()
        keyLevelMenu:Hide()
    end

    Panel.Refresh()
end

function Panel.ClearContext()
    Panel.SaveItemSelections()

    VCA.Detection.ClearActiveSource()

    wipe(selectedItemIDs)
    wipe(selectedSpecIDs)
    HideAllItemRows()
    HideAllSpecRows()

    Panel.sourceType = nil
    Panel.sourceID = nil
    Panel.difficultyID = nil
    Panel.isRaid = nil

    sourceLabel:SetText("")
    infoLabel:SetText("")
    lootSpecLabel:SetText("")
    _currentVoidcacheID = nil
    voidcacheIconBtn:Hide()
    lootColHeader:SetText(VCA.Theme.hdr .. "" .. L["COL_LOOT"] .. "|r")
    specColHeader:SetText(VCA.Theme.hdr .. "" .. L["COL_SPEC_RANKING"] .. "|r")
    clearSpecBtn:Hide()
    clearItemBtn:Hide()
    markModeBtn:Hide()
    Panel.markMode = false
    UpdateMarkModeButton()
    keyLevelMenu:Hide()
end

-- ── Refresh ───────────────────────────────────────────────────────────────────

function Panel.Refresh()
    if not frame:IsShown() then
        return
    end
    if not Panel.sourceID then
        return
    end
    markModeBtn:Show()

    -- Update loot spec label
    local lootSpecID = VCA.SpecInfo.GetEffectiveLootSpecID()
    if lootSpecID and lootSpecID > 0 then
        local _, name, _, icon = GetSpecializationInfoByID(lootSpecID)
        if name then
            lootSpecLabel:SetText("|cff888888" .. L["LOOT_SPEC_LABEL"] .. "|r |cffeeeeee" .. name .. "|r")
        else
            lootSpecLabel:SetText("")
        end
    else
        lootSpecLabel:SetText("")
    end

    -- Update voidcache icon
    local newVoidcacheID
    if Panel.sourceType == VCA.ContentType.MYTHIC_PLUS then
        newVoidcacheID = VCA.DungeonVoidcacheIDs and VCA.DungeonVoidcacheIDs[Panel.sourceID]
    elseif Panel.sourceType == VCA.ContentType.RAID then
        newVoidcacheID = VCA.RaidEncounterCacheIDs and VCA.RaidEncounterCacheIDs[Panel.sourceID]
    end
    _currentVoidcacheID = newVoidcacheID
    if newVoidcacheID then
        local texture = select(10, C_Item.GetItemInfo(newVoidcacheID))
        if texture then
            voidcacheIconTex:SetTexture(texture)
            voidcacheIconBtn:Show()
        else
            voidcacheIconBtn:Hide()
        end
    else
        voidcacheIconBtn:Hide()
    end

    -- Update info label with voidcore cost; turn red when the player cannot afford it.
    local cost = VCA.Probability.GetVoidcoreCost(Panel.sourceType)
    local contentTag = Panel.isRaid and L["CONTENT_RAID_BOSS"] or L["CONTENT_MP_DUNGEON"]
    local coreWord = cost == 1 and L["NEBULOUS_VOIDCORE"] or L["NEBULOUS_VOIDCORES"]
    local currInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(VCA.VOIDCORE_CURRENCY_ID)
    local owned = currInfo and currInfo.quantity or 0
    local costColor
    if owned < cost then
        costColor = "|cffff3333" -- red: cannot afford
    elseif cost == 2 then
        costColor = "|cffffff00" -- yellow for raids
    else
        costColor = "|cff00ff00" -- green for M+
    end
    infoLabel:SetText(contentTag .. "  •  " .. costColor .. cost .. " " .. coreWord .. "|r")

    DoLayout()
    Panel.RefreshItemColumn()
    Panel.RefreshSpecColumn()
end

-- ── Detection callback ────────────────────────────────────────────────────────
-- Wired to Detection module: flash the detected item row green, print to chat.

VCA.Detection.SetOnItemDetectedCallback(function(itemID, source, itemLevel)
    -- Chat message (with the item level the roll gave, so a wrong difficulty is easy to spot)
    local itemName = C_Item.GetItemNameByID(itemID) or tostring(itemID)
    if itemLevel then
        itemName = itemName .. " (ilvl " .. itemLevel .. ")"
    end
    print(VCA.Theme.hdr .. "VoidcoreAdvisor Reborn:|r " .. string.format(L["DETECTED_OBTAINED"], "|cnIQ4:" .. itemName .. "|r"))

    -- Remove from saved selections now that it's obtained.
    VCA.Data.RemoveSelectedItem(source.sourceType, source.sourceID, source.difficultyID, itemID)
    selectedItemIDs[itemID] = nil

    -- Flash the item row if panel is open for this source
    if Panel.sourceID == source.sourceID and Panel.sourceType == source.sourceType and Panel.difficultyID ==
        source.difficultyID then
        for _, row in ipairs(itemRows) do
            if row.checkbox.itemID == itemID and row.frame:IsShown() then
                row.flash:SetColorTexture(0, 1, 0, 0.35)
                -- Fade out over ~1.5 s using OnUpdate
                local age = 0
                row.frame:SetScript("OnUpdate", function(self, elapsed)
                    age = age + elapsed
                    local alpha = math.max(0, 0.35 - age * 0.23)
                    row.flash:SetColorTexture(0, 1, 0, alpha)
                    if age >= 1.5 then
                        row.flash:SetColorTexture(0, 1, 0, 0)
                        self:SetScript("OnUpdate", nil)
                    end
                end)
                break
            end
        end
        Panel.Refresh()
    end
end)

-- ── Visibility helpers ────────────────────────────────────────────────────────

function Panel.Show()
    Panel.AnchorToEJ()
    frame:Show()
    Panel.Refresh()
end

function Panel.Hide()
    frame:Hide()
end

function Panel.IsShown()
    return frame:IsShown()
end

function Panel.IsMinimized()
    local db = _G[VCA.CHAR_DB_NAME]
    return db and db.minimized or false
end

function Panel.SetMinimized(val)
    local db = _G[VCA.CHAR_DB_NAME]
    if db then
        db.minimized = val and true or false
    end
end

-- ── Live spec-change / loot-data update ───────────────────────────────────────
-- When the player changes their loot spec setting, or when the EJ finishes
-- loading loot data for a newly selected instance, refresh both columns.

local rowRedrawPending = false
local specChangeFrame = CreateFrame("Frame")
specChangeFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
specChangeFrame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
specChangeFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
specChangeFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
specChangeFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOOT_SPEC_UPDATED" then
        if _currentVoidcacheID and frame:IsShown() then
            -- Bust the tooltip cache using a different voidcache ID so the next
            -- SetItemByID call fetches fresh spec data (same pattern as BonusRollConfirm).
            if C_TooltipInfo and C_TooltipInfo.GetItemByID then
                local bustID = nil
                for _, id in pairs(VCA.DungeonVoidcacheIDs or {}) do
                    if id ~= _currentVoidcacheID then
                        bustID = id;
                        break
                    end
                end
                if not bustID then
                    for _, id in pairs(VCA.RaidEncounterCacheIDs or {}) do
                        if id ~= _currentVoidcacheID then
                            bustID = id;
                            break
                        end
                    end
                end
                if bustID then
                    C_TooltipInfo.GetItemByID(bustID)
                end
            end
            -- Re-show tooltip immediately if it is already open over the icon.
            if GameTooltip:IsShown() and GameTooltip:GetOwner() == voidcacheIconBtn then
                ShowVoidcacheTooltip(voidcacheIconBtn)
            end
        end
        Panel.Refresh()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Retry showing the icon if item data arrived after the initial Refresh.
        local itemID = ...
        -- A row that was waiting for its item data gets redrawn (once, for a burst of items).
        if frame:IsShown() and not rowRedrawPending then
            for _, r in ipairs(itemRows) do
                if r.frame:IsShown() and r.checkbox.itemID == itemID then
                    rowRedrawPending = true
                    C_Timer.After(0.3, function()
                        rowRedrawPending = false
                        if frame:IsShown() then
                            Panel.RefreshItemColumn()
                        end
                    end)
                    break
                end
            end
        end
        if itemID == _currentVoidcacheID and frame:IsShown() and not voidcacheIconBtn:IsShown() then
            local texture = select(10, C_Item.GetItemInfo(itemID))
            if texture then
                voidcacheIconTex:SetTexture(texture)
                voidcacheIconBtn:Show()
            end
        end
    else
        Panel.Refresh()
    end
end)

local zoneResetFrame = CreateFrame("Frame")
zoneResetFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneResetFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneResetFrame:SetScript("OnEvent", function()
    Panel.ClearContext()
    Panel.Hide()
end)
