-- VoidcoreAdvisor: DungeonOverview
-- Shown when the Encounter Journal is on the dungeon/instance list view.
-- Displays all current-season M+ dungeons sorted descending by loot percentage,
-- showing the best spec's stats for each dungeon.
--
-- A dungeon is omitted when its best spec has no remaining items to obtain.
-- Sorted by: remainingOdds descending (highest single-item chance first).
local _, VCA = ...
local L = VCA.L

VCA.DungeonOverview = {}
local Overview = VCA.DungeonOverview

-- ── Sizing ────────────────────────────────────────────────────────────────────

local PANEL_WIDTH = 480
local HEADER_H = 56 -- title + subtitle + divider
local COL_HEADER_H = 20 -- column label row
local PADDING = 12 -- inner horizontal padding
local ROW_H = 26 -- height of one dungeon row
local ICON_SIZE = 20 -- spec icon size

-- ── Slot section sizing ───────────────────────────────────────────────────────
local SLOT_BTN_SIZE = 32 -- icon button size (square)
local SLOT_BTN_GAP = 6 -- horizontal gap between buttons
local SLOT_ROWS_GAP = 6 -- vertical gap between the two button rows
local SLOT_SECTION_TITLE_H = 22
local SLOT_SECTION_H = 8 + SLOT_SECTION_TITLE_H + 6 + SLOT_BTN_SIZE + SLOT_ROWS_GAP + SLOT_BTN_SIZE + 10
-- 9 visible dungeon rows in the scroll area (gives headroom so all 8 season dungeons fit without scrolling)
local VISIBLE_ROWS = 9
local SCROLL_AREA_H = VISIBLE_ROWS * (ROW_H + 2)
-- Total panel height: header + col-header area + scroll area + divider + slot section + bottom inset
local PANEL_HEIGHT = HEADER_H + 1 + (COL_HEADER_H + 8) + SCROLL_AREA_H + 2 + SLOT_SECTION_H + 11

-- ── Slot filter state ─────────────────────────────────────────────────────────

-- Ordered list of display slot keys (7 per row × 2 rows = 14 total).
local SLOT_ORDER = {"head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger",
                    "trinket", "weapon", "offhand"}

-- Weapon display slot maps to these LootPool slot keys (includes ranged).
local WEAPON_SUBSLOTS = {"1h", "2h", "ranged"}

-- Returns the LootPool slot key(s) for a display slot key.
local function GetLootSlotKeys(slotKey)
    if slotKey == "weapon" then
        return WEAPON_SUBSLOTS
    end
    return {slotKey}
end

-- Paperdoll texture per display slot.
-- Maps display slot key → inventory slot name for GetInventorySlotInfo().
-- GetInventorySlotInfo returns the correct paperdoll empty-slot texture for every slot.
local SLOT_INV_NAME = {
    head = "HEADSLOT",
    neck = "NECKSLOT",
    shoulder = "SHOULDERSLOT",
    back = "BACKSLOT",
    chest = "CHESTSLOT",
    wrist = "WRISTSLOT",
    hands = "HANDSSLOT",
    waist = "WAISTSLOT",
    legs = "LEGSSLOT",
    feet = "FEETSLOT",
    finger = "FINGER0SLOT",
    trinket = "TRINKET0SLOT",
    weapon = "MAINHANDSLOT",
    offhand = "SECONDARYHANDSLOT"
}

-- ── Column layout (positions relative to row frame LEFT) ─────────────────────
--   [DUNGEON name ........... 200px] [icon 20] [SPEC name .. 100px] [...] [LOOTED 53] [CHANCE 50]

local COL_DUNGEON_X = 0
local COL_DUNGEON_W = 200
local COL_SPEC_ICON_X = 204 -- COL_DUNGEON_W + 4px gap
local COL_SPEC_NAME_X = 228 -- COL_SPEC_ICON_X + ICON_SIZE + 4
local COL_SPEC_NAME_W = 100
-- Right-side columns (offsets from row RIGHT edge):
local COL_LOOTED_R = -(64 + 4) -- pct width + gap; RIGHT edge of obtained label
local COL_LOOTED_W = 53
local COL_PCT_R = 0 -- RIGHT edge of pct label flush with row right
local COL_PCT_W = 64

-- ── Main frame ────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
Overview.frame = frame

frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:Hide()

frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = {
        left = 11,
        right = 12,
        top = 12,
        bottom = 11
    }
})
VCA.OnTheme(function() local t = VCA.Theme.bg; frame:SetBackdropColor(t[1], t[2], t[3], 0.95) end)
VCA.OnTheme(function() local t = VCA.Theme.border; frame:SetBackdropBorderColor(t[1], t[2], t[3], 1) end)

-- ── Anchor helper ─────────────────────────────────────────────────────────────

-- Positions the panel flush against the right edge of EncounterJournal.
function Overview.AnchorToEJ()
    local ej = EncounterJournal
    if not ej then
        return
    end
    if VCA.Panel.ApplyFreePlacement(frame, false) then
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", ej, "TOPRIGHT", 52, 0)
end

-- ── Header ────────────────────────────────────────────────────────────────────

local titleText = frame:CreateFontString(nil, "OVERLAY", "VCAFontNormalLarge")
titleText:SetPoint("TOPLEFT", 18, -16)
VCA.OnTheme(function() titleText:SetText(VCA.TitleText()) end)

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
    frame:Hide()
end)
-- Pin button next to the X, and a draggable title row (the same pinned / free state as the panel).
VCA.Panel.CreatePinButton(frame, closeBtn, function()
    if frame:IsShown() then
        Overview.AnchorToEJ()
    end
end)
VCA.Panel.MakeDraggable(frame, 170)

-- ── Scan button ───────────────────────────────────────────────────────────────

local scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
scanBtn:SetSize(130, 22)
scanBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -38, -30)
scanBtn:SetText(VCA.L["SCAN_BTN"])

local function UpdateScanButton()
    local L = VCA.L
    if VCA.VoidcacheScan.IsRunning() then
        scanBtn:Disable()
        return -- text managed by the progress callback while scanning
    end
    local canScan = VCA.VoidcacheScan.CanScan()
    scanBtn:SetText(L["SCAN_BTN"])
    if canScan then
        scanBtn:Enable()
    else
        scanBtn:Disable()
    end
end

scanBtn:SetScript("OnClick", function()
    local L = VCA.L
    local canScan, reason = VCA.VoidcacheScan.CanScan()
    if not canScan then
        if reason == "COMBAT" then
            DEFAULT_CHAT_FRAME:AddMessage(L["SCAN_UNAVAILABLE_COMBAT"])
        elseif reason == "INSTANCE" then
            DEFAULT_CHAT_FRAME:AddMessage(L["SCAN_UNAVAILABLE_INSTANCE"])
        end
        return
    end
    StaticPopup_Show("VOIDCORE_SCAN_CONFIRM")
end)

VCA.VoidcacheScan.SetProgressCallback(function(specIdx, specCount, _, _, status)
    local L = VCA.L
    if status == "COMPLETE" then
        scanBtn:SetText(L["SCAN_COMPLETE"])
        scanBtn:Disable()
        C_Timer.After(3, UpdateScanButton)
    elseif status == "ABORTED" or status == "COMBAT" then
        scanBtn:SetText(L["SCAN_ABORTED"])
        scanBtn:Disable()
        C_Timer.After(3, UpdateScanButton)
    elseif specIdx then
        scanBtn:SetText(string.format(L["SCAN_PROGRESS"], specIdx, specCount))
        scanBtn:Disable()
    end
end)

local scanBtnStateFrame = CreateFrame("Frame")
scanBtnStateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
scanBtnStateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
scanBtnStateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
scanBtnStateFrame:SetScript("OnEvent", UpdateScanButton)

-- Returns true if any season dungeon has at least one item of this slot selected.
local function IsSlotSelected(slotKey)
    local instanceIDs = VCA.LootPool.GetSeasonDungeonInstanceIDs()
    for _, instanceID in ipairs(instanceIDs) do
        local selected = VCA.Data.GetSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty)
        for _, lootKey in ipairs(GetLootSlotKeys(slotKey)) do
            for _, itemID in ipairs(VCA.LootPool.GetInstanceItemsForSlot(instanceID, lootKey)) do
                if selected[itemID] then
                    return true
                end
            end
        end
    end
    return false
end

local slotButtons = {} -- [slotKey] = { icon = Texture, glow = Texture, border = Frame }

local function UpdateSlotButtonVisual(entry, slotKey)
    if IsSlotSelected(slotKey) then
        entry.icon:SetVertexColor(1, 1, 1, 1)
        entry.glow:SetAlpha(1)
        entry.border:Show()
    else
        entry.icon:SetVertexColor(0.9, 0.9, 0.9, 1.0)
        entry.glow:SetAlpha(0)
        entry.border:Hide()
    end
end

local function RefreshSlotButtons()
    for _, slotKey in ipairs(SLOT_ORDER) do
        if slotButtons[slotKey] then
            UpdateSlotButtonVisual(slotButtons[slotKey], slotKey)
        end
    end
end

-- ── Slot section (always-visible panel at the bottom of frame) ────────────────

local slotSection = CreateFrame("Frame", nil, frame)
slotSection:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 11)
slotSection:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 11)
slotSection:SetHeight(SLOT_SECTION_H)

-- Divider above slot section
local slotDivider = slotSection:CreateTexture(nil, "ARTWORK")
VCA.OnTheme(function() local t = VCA.Theme.border; slotDivider:SetColorTexture(t[1], t[2], t[3], 0.4) end)
slotDivider:SetPoint("TOPLEFT", slotSection, "TOPLEFT", 16, 0)
slotDivider:SetPoint("TOPRIGHT", slotSection, "TOPRIGHT", -16, 0)
slotDivider:SetHeight(1)

-- Title label
local slotTitle = slotSection:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
slotTitle:SetPoint("TOPLEFT", slotSection, "TOPLEFT", PADDING, -8)
VCA.OnTheme(function() slotTitle:SetText(VCA.Theme.hdr .. "" .. L["SLOT_FILTER_TOGGLE"] .. "|r") end)

-- Clear-all button
local slotClearBtn = CreateFrame("Button", nil, slotSection)
slotClearBtn:SetSize(14, 14)
slotClearBtn:SetNormalFontObject("VCAFontNormal")
slotClearBtn:SetText("|cffff4444x|r")
slotClearBtn:SetPoint("TOPRIGHT", slotSection, "TOPRIGHT", -PADDING, -8)

-- Adds all items for a slot to the persisted selection for every season dungeon.
local function SelectSlotItems(slotKey)
    local instanceIDs = VCA.LootPool.GetSeasonDungeonInstanceIDs()
    for _, instanceID in ipairs(instanceIDs) do
        local current = VCA.Data.GetSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty)
        local updated = {}
        for id in pairs(current) do
            updated[id] = true
        end
        for _, lootKey in ipairs(GetLootSlotKeys(slotKey)) do
            for _, itemID in ipairs(VCA.LootPool.GetInstanceItemsForSlot(instanceID, lootKey)) do
                updated[itemID] = true
            end
        end
        VCA.Data.SaveSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty, updated)
    end
    -- Keep Panel's in-memory selection in sync so it doesn't overwrite DB on next context switch.
    if VCA.Panel and VCA.Panel.ReloadItemSelections then
        VCA.Panel.ReloadItemSelections()
    end
end

-- Removes all items for a slot from the persisted selection for every season dungeon.
local function DeselectSlotItems(slotKey)
    local instanceIDs = VCA.LootPool.GetSeasonDungeonInstanceIDs()
    for _, instanceID in ipairs(instanceIDs) do
        local current = VCA.Data.GetSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty)
        local updated = {}
        for id in pairs(current) do
            updated[id] = true
        end
        for _, lootKey in ipairs(GetLootSlotKeys(slotKey)) do
            for _, itemID in ipairs(VCA.LootPool.GetInstanceItemsForSlot(instanceID, lootKey)) do
                updated[itemID] = nil
            end
        end
        VCA.Data.SaveSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty, updated)
    end
    -- Keep Panel's in-memory selection in sync so it doesn't overwrite DB on next context switch.
    if VCA.Panel and VCA.Panel.ReloadItemSelections then
        VCA.Panel.ReloadItemSelections()
    end
end

-- Forward-declare Populate so slot buttons can call it
local Populate

-- Forward-declare BuildMyth1ItemLink so BuildSlotTooltip can call it
local BuildMyth1ItemLink

local function BuildSlotTooltip(slotKey)
    GameTooltip:AddLine(L["SLOT_" .. slotKey] or slotKey, 0.85, 0.3, 1)
    local classID = VCA.SpecInfo.GetPlayerClassID()
    local instanceIDs = VCA.LootPool.GetSeasonDungeonInstanceIDs()
    local anyShown = false
    for _, instanceID in ipairs(instanceIDs) do
        -- Build class-lootable set for this dungeon
        local dungeonData = VCA.SeasonData and VCA.SeasonData.dungeons[instanceID]
        local classItems = {}
        if dungeonData and dungeonData.byClass and dungeonData.byClass[classID] then
            for _, id in ipairs(dungeonData.byClass[classID]) do
                classItems[id] = true
            end
        end
        -- Collect selected + class-lootable items for this dungeon/slot
        local selected = VCA.Data.GetSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty)
        local rows = {}
        for _, lootKey in ipairs(GetLootSlotKeys(slotKey)) do
            for _, itemID in ipairs(VCA.LootPool.GetInstanceItemsForSlot(instanceID, lootKey)) do
                if selected[itemID] and classItems[itemID] then
                    local bonusedLink = BuildMyth1ItemLink(itemID)
                    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(bonusedLink or itemID)
                    if itemName then
                        rows[#rows + 1] = {
                            name = itemName,
                            quality = itemQuality,
                            texture = itemTexture
                        }
                    end
                end
            end
        end
        if #rows > 0 then
            local dungeonName = EJ_GetInstanceInfo(instanceID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffdddddd" .. (dungeonName or tostring(instanceID)) .. "|r")
            for _, row in ipairs(rows) do
                local iconMarkup = row.texture and ("|T" .. row.texture .. ":14:14:0:0:64:64:4:60:4:60|t ") or "  "
                local nameColored = "|cnIQ" .. (row.quality or 4) .. ":" .. row.name .. "|r"
                GameTooltip:AddLine("  " .. iconMarkup .. nameColored)
            end
            anyShown = true
        end
    end
    if not anyShown then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888" .. (L["SLOT_NONE_SELECTED"] or "Nothing selected") .. "|r")
    end
end

local EQUIP_LOC_ORDER = {
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
    INVTYPE_TRINKET = 12,
    INVTYPE_WEAPON = 13,
    INVTYPE_WEAPONMAINHAND = 13,
    INVTYPE_2HWEAPON = 13,
    INVTYPE_WEAPONOFFHAND = 14,
    INVTYPE_SHIELD = 14,
    INVTYPE_HOLDABLE = 14,
    INVTYPE_RANGED = 15,
    INVTYPE_RANGEDRIGHT = 15
}

local function BuildDungeonTooltip(instanceID)
    local dungeonName = EJ_GetInstanceInfo(instanceID)
    GameTooltip:AddLine(dungeonName or tostring(instanceID), 0.85, 0.3, 1)

    local classID = VCA.SpecInfo.GetPlayerClassID()
    local dungeonData = VCA.SeasonData and VCA.SeasonData.dungeons[instanceID]
    local classItems = {}
    if dungeonData and dungeonData.byClass and dungeonData.byClass[classID] then
        for _, id in ipairs(dungeonData.byClass[classID]) do
            classItems[id] = true
        end
    end

    local selected = VCA.Data.GetSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty)
    local rows = {}
    for itemID in pairs(selected) do
        if classItems[itemID] then
            local bonusedLink = BuildMyth1ItemLink(itemID)
            local itemName, _, itemQuality, _, _, _, _, _, equipLoc, itemTexture = C_Item.GetItemInfo(bonusedLink or itemID)
            if itemName then
                rows[#rows + 1] = {
                    itemName = itemName,
                    itemQuality = itemQuality,
                    equipLoc = equipLoc,
                    itemTexture = itemTexture,
                    sortKey = EQUIP_LOC_ORDER[equipLoc] or 99
                }
            end
        end
    end

    if #rows == 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888" .. (L["SLOT_NONE_SELECTED"] or "Nothing selected") .. "|r")
        return
    end

    table.sort(rows, function(a, b)
        if a.sortKey ~= b.sortKey then
            return a.sortKey < b.sortKey
        end
        return (a.itemName or "") < (b.itemName or "")
    end)

    for _, row in ipairs(rows) do
        local iconMarkup = row.itemTexture and ("|T" .. row.itemTexture .. ":14:14:0:0:64:64:4:60:4:60|t ") or "  "
        local slotText = (row.equipLoc and _G[row.equipLoc] and _G[row.equipLoc] ~= "") and
                             (" |cff888888[" .. _G[row.equipLoc] .. "]|r") or ""
        local nameColored = "|cnIQ" .. (row.itemQuality or 4) .. ":" .. row.itemName .. "|r"
        GameTooltip:AddLine("  " .. iconMarkup .. nameColored .. slotText)
    end
end

-- ── Slot item picker popup ─────────────────────────────────────────────────────────────
local PICKER_W = 300
local PICKER_ROW_H = 22
local PICKER_HDR_H = 18
local PICKER_MAX_H = 320
local PICKER_PAD = 10
local PICKER_ICON_SZ = 16

-- Builds an item link with Myth 1/6 bonus IDs injected so tooltips show the
-- correct item level for the Nebulous Voidcore reward track.
BuildMyth1ItemLink = function(itemID)
    local _, itemLink = C_Item.GetItemInfo(itemID)
    if not itemLink then
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
    fields[13] = "35" -- M+ context

    local numBonuses = tonumber(fields[14]) or 0
    local newBonuses = {}
    for bi = 15, 14 + numBonuses do
        if fields[bi] ~= "3524" then
            newBonuses[#newBonuses + 1] = fields[bi]
        end
    end
    for _, b in ipairs(VCA.MythicPlusBonusIDs) do
        newBonuses[#newBonuses + 1] = tostring(b)
    end
    newBonuses[#newBonuses + 1] = tostring(VCA.VoidcoreTrackBonusID)

    for _ = 1, numBonuses do
        table.remove(fields, 15)
    end
    fields[14] = tostring(#newBonuses)
    for i, b in ipairs(newBonuses) do
        table.insert(fields, 14 + i, b)
    end
    return table.concat(fields, ":")
end

-- Click-catcher: transparent full-screen frame that closes the popup when the
-- user clicks anywhere outside it.  Lives at FULLSCREEN strata so the popup
-- (FULLSCREEN_DIALOG) still receives its own clicks normally.
local pickerCatcher = CreateFrame("Frame", nil, UIParent)
pickerCatcher:SetAllPoints(UIParent)
pickerCatcher:SetFrameStrata("FULLSCREEN")
pickerCatcher:EnableMouse(true)
pickerCatcher:Hide()

local pickerPopup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
pickerPopup:SetWidth(PICKER_W)
pickerPopup:SetFrameStrata("FULLSCREEN_DIALOG")
pickerPopup:SetClampedToScreen(true)
pickerPopup:Hide()

pickerPopup:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 24,
    insets = {
        left = 8,
        right = 8,
        top = 8,
        bottom = 8
    }
})
VCA.OnTheme(function() local t = VCA.Theme.bg; pickerPopup:SetBackdropColor(t[1], t[2], t[3], 0.97) end)
VCA.OnTheme(function() local t = VCA.Theme.border; pickerPopup:SetBackdropBorderColor(t[1], t[2], t[3], 1) end)

local function ClosePicker()
    pickerPopup:Hide()
    pickerCatcher:Hide()
end

pickerCatcher:SetScript("OnMouseDown", ClosePicker)

local pickerCloseBtn = CreateFrame("Button", nil, pickerPopup, "UIPanelCloseButton")
pickerCloseBtn:SetSize(20, 20)
pickerCloseBtn:SetPoint("TOPRIGHT", -2, -2)
pickerCloseBtn:SetScript("OnClick", ClosePicker)

local pickerTitle = pickerPopup:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
pickerTitle:SetPoint("TOPLEFT", PICKER_PAD, -PICKER_PAD)
pickerTitle:SetPoint("TOPRIGHT", -(PICKER_PAD + 22), -PICKER_PAD)
pickerTitle:SetJustifyH("LEFT")

-- Divider under the title
local pickerTitleRule = pickerPopup:CreateTexture(nil, "ARTWORK")
VCA.OnTheme(function() local t = VCA.Theme.border; pickerTitleRule:SetColorTexture(t[1], t[2], t[3], 0.4) end)
pickerTitleRule:SetHeight(1)

local pickerScrollFrame = CreateFrame("ScrollFrame", nil, pickerPopup)
local pickerScrollChild = CreateFrame("Frame", nil, pickerScrollFrame)
pickerScrollFrame:SetScrollChild(pickerScrollChild)
pickerScrollFrame:EnableMouseWheel(true)
pickerScrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local maxS = math.max(0, pickerScrollChild:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * PICKER_ROW_H * 3)))
end)

-- ---- Row pools ----

local pickerItemPool = {} -- interactive item rows and the "All" row
local pickerHeaderPool = {} -- dungeon name header rows

local function GetOrCreatePickerItem()
    for _, r in ipairs(pickerItemPool) do
        if not r.frame:IsShown() then
            return r
        end
    end
    local rf = CreateFrame("Button", nil, pickerScrollChild)
    rf:SetHeight(PICKER_ROW_H)
    rf:RegisterForClicks("LeftButtonUp")

    local hl = rf:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(rf)
    hl:SetColorTexture(VCA.Theme.accent[1], VCA.Theme.accent[2], VCA.Theme.accent[3], 0.25)

    local check = rf:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("LEFT", rf, "LEFT", 2, 0)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

    local iconBtn = CreateFrame("Button", nil, rf)
    iconBtn:SetSize(PICKER_ICON_SZ, PICKER_ICON_SZ)
    iconBtn:SetPoint("LEFT", rf, "LEFT", 20, 0)

    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconBtn)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local lbl = rf:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
    lbl:SetPoint("LEFT", iconBtn, "RIGHT", 4, 0)
    lbl:SetPoint("RIGHT", rf, "RIGHT", 0, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)

    local r = {
        frame = rf,
        iconButton = iconBtn,
        check = check,
        icon = iconTex,
        label = lbl
    }
    pickerItemPool[#pickerItemPool + 1] = r
    return r
end

local function GetOrCreatePickerHeader()
    for _, h in ipairs(pickerHeaderPool) do
        if not h:IsShown() then
            return h
        end
    end
    local f = CreateFrame("Frame", nil, pickerScrollChild)
    f:SetHeight(PICKER_HDR_H)
    local lbl = f:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
    lbl:SetAllPoints(f)
    lbl:SetJustifyH("LEFT")
    f.label = lbl
    pickerHeaderPool[#pickerHeaderPool + 1] = f
    return f
end

-- ---- Helpers ----

local pickerCurrentSlot = nil

local function IsItemSelected(instanceID, itemID)
    local sel = VCA.Data.GetSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty)
    return sel[itemID] == true
end

local function ToggleSingleItem(instanceID, itemID)
    local current = VCA.Data.GetSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty)
    local updated = {}
    for id in pairs(current) do
        updated[id] = true
    end
    if current[itemID] then
        updated[itemID] = nil
    else
        updated[itemID] = true
    end
    VCA.Data.SaveSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty, updated)
    if VCA.Panel and VCA.Panel.ReloadItemSelections then
        VCA.Panel.ReloadItemSelections()
    end
end

local function RefreshPickerRows()
    for _, r in ipairs(pickerItemPool) do
        if r.frame:IsShown() then
            if r.isAll then
                local allSelected = IsSlotSelected(pickerCurrentSlot)
                r.check:SetAlpha(allSelected and 1 or 0)
                r.label:SetText(allSelected and (L["SLOT_DESELECT_ALL"] or "Deselect All") or
                                    (L["SLOT_SELECT_ALL"] or "Select All"))
            elseif r.itemID then
                -- Checked if selected in ANY dungeon that carries this item
                local any = false
                if r.instanceIDs then
                    for _, iid in ipairs(r.instanceIDs) do
                        if IsItemSelected(iid, r.itemID) then
                            any = true;
                            break
                        end
                    end
                end
                r.check:SetAlpha(any and 1 or 0)
            end
        end
    end
end

local function OpenSlotPicker(slotKey, anchorBtn)
    -- If the same button is clicked while open, just close
    if pickerPopup:IsShown() and pickerCurrentSlot == slotKey then
        ClosePicker()
        return
    end
    pickerCurrentSlot = slotKey

    -- Reset pool
    for _, r in ipairs(pickerItemPool) do
        r.frame:Hide()
    end
    for _, h in ipairs(pickerHeaderPool) do
        h:Hide()
    end

    pickerTitle:SetText(VCA.Theme.hdr .. "" .. (L["SLOT_" .. slotKey] or slotKey) .. "|r")

    local childW = PICKER_W - PICKER_PAD * 2
    pickerScrollChild:SetWidth(childW)

    local y = 0

    -- " All" row
    local allRow = GetOrCreatePickerItem()
    allRow.isAll = true
    allRow.instanceID = nil
    allRow.itemID = nil
    allRow.frame:SetWidth(childW)
    allRow.frame:ClearAllPoints()
    allRow.frame:SetPoint("TOPLEFT", pickerScrollChild, "TOPLEFT", 0, -y)
    allRow.icon:Hide()
    allRow.label:SetPoint("LEFT", allRow.frame, "LEFT", 20, 0)
    local allSelected = IsSlotSelected(slotKey)
    allRow.label:SetText(allSelected and (L["SLOT_DESELECT_ALL"] or "Deselect All") or
                             (L["SLOT_SELECT_ALL"] or "Select All"))
    allRow.label:SetTextColor(1, 1, 1, 1)
    allRow.check:SetAlpha(allSelected and 1 or 0)
    allRow.frame:SetScript("OnClick", function()
        if IsSlotSelected(slotKey) then
            DeselectSlotItems(slotKey)
        else
            SelectSlotItems(slotKey)
        end
        RefreshPickerRows()
        RefreshSlotButtons()
        if Populate then
            Populate()
        end
    end)
    allRow.frame:SetScript("OnEnter", nil)
    allRow.frame:SetScript("OnLeave", nil)
    allRow.frame:Show()
    y = y + PICKER_ROW_H + 6 -- extra gap after "All"

    -- Flat deduplicated item list — only items lootable by the player's class.
    -- Each unique itemID gets one row; instanceIDs tracks every dungeon
    -- that carries that item so toggle can act on all of them.
    local classID = VCA.SpecInfo.GetPlayerClassID()
    local instanceIDs = VCA.LootPool.GetSeasonDungeonInstanceIDs()

    -- itemID -> {instanceID, ...}
    local itemInstances = {}
    -- preserve insertion order
    local orderedItems = {}

    for _, instanceID in ipairs(instanceIDs) do
        local dungeonData = VCA.SeasonData and VCA.SeasonData.dungeons[instanceID]
        local classItems = {}
        if dungeonData and dungeonData.byClass and dungeonData.byClass[classID] then
            for _, id in ipairs(dungeonData.byClass[classID]) do
                classItems[id] = true
            end
        end
        for _, lootKey in ipairs(GetLootSlotKeys(slotKey)) do
            for _, itemID in ipairs(VCA.LootPool.GetInstanceItemsForSlot(instanceID, lootKey)) do
                if classItems[itemID] then
                    if not itemInstances[itemID] then
                        itemInstances[itemID] = {}
                        orderedItems[#orderedItems + 1] = itemID
                    end
                    itemInstances[itemID][#itemInstances[itemID] + 1] = instanceID
                end
            end
        end
    end

    for _, itemID in ipairs(orderedItems) do
        local iids = itemInstances[itemID]
        local row = GetOrCreatePickerItem()
        row.isAll = false
        row.instanceID = nil -- not used for flat items
        row.instanceIDs = iids
        row.itemID = itemID
        row.frame:SetWidth(childW)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", pickerScrollChild, "TOPLEFT", 0, -y)

        local bonusedLink = BuildMyth1ItemLink(itemID)
        local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(bonusedLink or itemID)
        if itemTexture then
            row.icon:SetTexture(itemTexture)
            row.icon:Show()
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        else
            row.icon:Hide()
            row.label:SetPoint("LEFT", row.frame, "LEFT", 20, 0)
        end
        if itemName then
            row.label:SetText("|cnIQ" .. (itemQuality or 1) .. ":" .. itemName .. "|r")
        else
            row.label:SetText("|cff888888[" .. itemID .. "]|r")
        end

        -- Check: item selected in any carrying dungeon
        local anySelected = false
        for _, iid in ipairs(iids) do
            if IsItemSelected(iid, itemID) then
                anySelected = true;
                break
            end
        end
        row.check:SetAlpha(anySelected and 1 or 0)

        local capturedItem = itemID
        local capturedIIDs = iids
        row.frame:SetScript("OnClick", function()
            -- Selected if active in ANY dungeon carrying this item
            local isSelected = false
            for _, iid in ipairs(capturedIIDs) do
                if IsItemSelected(iid, capturedItem) then
                    isSelected = true;
                    break
                end
            end
            local targetSelected = not isSelected
            for _, iid in ipairs(capturedIIDs) do
                local current = VCA.Data.GetSelectedItems(VCA.ContentType.MYTHIC_PLUS, iid, VCA.MythicPlusEJDifficulty)
                local updated = {}
                for id in pairs(current) do
                    updated[id] = true
                end
                if targetSelected then
                    updated[capturedItem] = true
                else
                    updated[capturedItem] = nil
                end
                VCA.Data.SaveSelectedItems(VCA.ContentType.MYTHIC_PLUS, iid, VCA.MythicPlusEJDifficulty, updated)
            end
            if VCA.Panel and VCA.Panel.ReloadItemSelections then
                VCA.Panel.ReloadItemSelections()
            end
            RefreshPickerRows()
            if slotButtons[slotKey] then
                UpdateSlotButtonVisual(slotButtons[slotKey], slotKey)
            end
            if Populate then
                Populate()
            end
        end)
        row.frame:SetScript("OnEnter", function(self)
            -- Refresh label color/icon lazily (GetItemInfo may have been empty at open time)
            local bLink = BuildMyth1ItemLink(capturedItem)
            local iName, _, iQuality, _, _, _, _, _, _, iTexture = C_Item.GetItemInfo(bLink or capturedItem)
            if iName then
                row.label:SetText("|cnIQ" .. (iQuality or 1) .. ":" .. iName .. "|r")
                if iTexture and not row.icon:IsShown() then
                    row.icon:SetTexture(iTexture)
                    row.icon:Show()
                    row.label:ClearAllPoints()
                    row.label:SetPoint("LEFT", row.iconButton, "RIGHT", 4, 0)
                end
            end
        end)
        row.iconButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = BuildMyth1ItemLink(capturedItem)
            local shown = false
            if link then
                local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                if ok and GameTooltip:NumLines() and GameTooltip:NumLines() > 0 then
                    shown = true
                end
            end
            if not shown then
                GameTooltip:SetHyperlink("item:" .. capturedItem)
            end
            GameTooltip:Show()
        end)
        row.iconButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row.frame:Show()
        y = y + PICKER_ROW_H + 1
    end

    pickerScrollChild:SetHeight(math.max(y, 1))

    -- Size popup
    local titleH = PICKER_PAD + 20 + 6 -- padding + title + rule gap
    local scrollH = math.min(y, PICKER_MAX_H)
    local totalH = titleH + scrollH + PICKER_PAD
    pickerPopup:SetHeight(totalH)

    pickerTitleRule:ClearAllPoints()
    pickerTitleRule:SetPoint("TOPLEFT", pickerPopup, "TOPLEFT", PICKER_PAD, -(PICKER_PAD + 20 + 3))
    pickerTitleRule:SetPoint("TOPRIGHT", pickerPopup, "TOPRIGHT", -PICKER_PAD, -(PICKER_PAD + 20 + 3))

    pickerScrollFrame:ClearAllPoints()
    pickerScrollFrame:SetPoint("TOPLEFT", pickerPopup, "TOPLEFT", PICKER_PAD, -(titleH))
    pickerScrollFrame:SetPoint("BOTTOMRIGHT", pickerPopup, "BOTTOMRIGHT", -PICKER_PAD, PICKER_PAD)
    pickerScrollFrame:SetVerticalScroll(0)

    -- Anchor above the button, clamped to screen
    pickerPopup:ClearAllPoints()
    pickerPopup:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, 6)

    pickerCatcher:Show()
    pickerPopup:Show()
end

-- Row 1: 10 armor slots (head→feet); row 2: finger, trinket, weapon, offhand.
-- Each row is centred independently within the inner content width.
local BTNS_PER_ROW = 10
local innerW = PANEL_WIDTH - 2 * PADDING
local gridTopY = -(8 + SLOT_SECTION_TITLE_H + 6) -- below divider+title+gap

-- Pre-compute per-row button counts so each row can be centred separately.
local rowCounts = {}
for i = 1, #SLOT_ORDER do
    local r = math.floor((i - 1) / BTNS_PER_ROW) + 1
    rowCounts[r] = (rowCounts[r] or 0) + 1
end
local function RowStartX(r)
    local count = rowCounts[r] or BTNS_PER_ROW
    local w = count * SLOT_BTN_SIZE + (count - 1) * SLOT_BTN_GAP
    return PADDING + math.floor((innerW - w) / 2)
end

for i, slotKey in ipairs(SLOT_ORDER) do
    local col = (i - 1) % BTNS_PER_ROW
    local row = math.floor((i - 1) / BTNS_PER_ROW)

    local btn = CreateFrame("Frame", nil, slotSection)
    btn:SetSize(SLOT_BTN_SIZE, SLOT_BTN_SIZE)
    btn:SetPoint("TOPLEFT", slotSection, "TOPLEFT", RowStartX(row + 1) + col * (SLOT_BTN_SIZE + SLOT_BTN_GAP),
        gridTopY - row * (SLOT_BTN_SIZE + SLOT_ROWS_GAP))
    btn:EnableMouse(true)

    -- Purple glow behind the icon (visible when selected)
    local glow = btn:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(btn)
    glow:SetColorTexture(0.45, 0.0, 0.7, 0.85)
    glow:SetAlpha(0)

    -- Slot icon — use the paperdoll empty-slot texture from the game client
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    local invName = SLOT_INV_NAME[slotKey]
    if invName then
        local _, textureName = GetInventorySlotInfo(invName)
        if textureName then
            icon:SetTexture(textureName)
        end
    end
    icon:SetVertexColor(0.9, 0.9, 0.9, 1.0) -- dimmed by default

    -- Hover highlight
    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(btn)
    hover:SetColorTexture(1, 1, 1, 0.18)

    -- Gold border shown when selected
    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2
    })
    border:SetBackdropBorderColor(0.95, 0.78, 0.1, 1)
    border:Hide()

    local entry = {
        icon = icon,
        glow = glow,
        border = border
    }
    slotButtons[slotKey] = entry

    btn:SetScript("OnMouseDown", function(self)
        OpenSlotPicker(slotKey, self)
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        BuildSlotTooltip(slotKey)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

slotClearBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["SLOT_FILTER_CLEAR"])
    GameTooltip:Show()
end)
slotClearBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
-- Confirm popup for Voidcache spec scan
StaticPopupDialogs["VOIDCORE_SCAN_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        VCA.VoidcacheScan.Start()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3
}

-- Confirm popup for clearing slot filters
StaticPopupDialogs["VOIDCORE_CLEAR_SLOT_FILTERS"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        for _, slotKey in ipairs(SLOT_ORDER) do
            if IsSlotSelected(slotKey) then
                DeselectSlotItems(slotKey)
            end
        end
        RefreshSlotButtons()
        if Populate then
            Populate()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3
}

slotClearBtn:SetScript("OnClick", function()
    StaticPopup_Show("VOIDCORE_CLEAR_SLOT_FILTERS",
        L["SLOT_FILTER_CLEAR_CONFIRM"] .. "\n\n|cffaaaaaa" .. L["SLOT_FILTER_CLEAR_CONFIRM_BODY"] .. "|r")
end)

local subtitleText = frame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
subtitleText:SetPoint("TOPLEFT", 18, -40)
subtitleText:SetText("|cff888888" .. L["DUNGEON_OVERVIEW_SUBTITLE"] .. "|r")

local divider = frame:CreateTexture(nil, "ARTWORK")
VCA.OnTheme(function() local t = VCA.Theme.border; divider:SetColorTexture(t[1], t[2], t[3], 0.4) end)
divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -HEADER_H)
divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -HEADER_H)
divider:SetHeight(1)

-- ── Content area ─────────────────────────────────────────────────────────────

local contentArea = CreateFrame("Frame", nil, frame)
contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(HEADER_H + 1))
contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, SLOT_SECTION_H + 11 + 2)

-- ── Column headers ────────────────────────────────────────────────────────────
-- Positioned to align with their corresponding row widgets.
-- Row widgets live inside the scrollFrame which is offset PADDING from contentArea left.
-- Therefore contentArea x = PADDING + row x.

local hdrDungeon = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
hdrDungeon:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING + COL_DUNGEON_X, -6)
VCA.OnTheme(function() hdrDungeon:SetText(VCA.Theme.hdr .. "" .. L["DUNGEON_OVERVIEW_COL_DUNGEON"] .. "|r") end)

local hdrSpec = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
hdrSpec:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING + COL_SPEC_NAME_X, -6)
VCA.OnTheme(function() hdrSpec:SetText(VCA.Theme.hdr .. "" .. L["DUNGEON_OVERVIEW_COL_SPEC"] .. "|r") end)

-- Right-side headers mirror the row right-anchoring.
-- Row frame right = scrollFrame right = contentArea right - PADDING.
-- So contentArea offset = -PADDING + COL_*_R.

local hdrLooted = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
hdrLooted:SetJustifyH("RIGHT")
hdrLooted:SetWidth(COL_LOOTED_W)
hdrLooted:SetWordWrap(false)
hdrLooted:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -PADDING + COL_LOOTED_R, -6)
VCA.OnTheme(function() hdrLooted:SetText(VCA.Theme.hdr .. "" .. L["DUNGEON_OVERVIEW_COL_LOOTED"] .. "|r") end)

local hdrChance = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
hdrChance:SetJustifyH("RIGHT")
hdrChance:SetWidth(COL_PCT_W)
hdrChance:SetWordWrap(false)
hdrChance:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -PADDING + COL_PCT_R, -6)
VCA.OnTheme(function() hdrChance:SetText(VCA.Theme.hdr .. "" .. L["DUNGEON_OVERVIEW_COL_CHANCE"] .. "|r") end)

-- Horizontal rule below column headers
local colHeaderRule = contentArea:CreateTexture(nil, "ARTWORK")
colHeaderRule:SetColorTexture(0.4, 0.4, 0.4, 0.3)
colHeaderRule:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, -(COL_HEADER_H + 2))
colHeaderRule:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -PADDING, -(COL_HEADER_H + 2))
colHeaderRule:SetHeight(1)

-- ── Row pool ──────────────────────────────────────────────────────────────────

local dungeonRows = {}

local function GetOrCreateDungeonRow(parent)
    for _, row in ipairs(dungeonRows) do
        if not row.frame:IsShown() then
            return row
        end
    end

    local rowFrame = CreateFrame("Frame", nil, parent)
    rowFrame:SetHeight(ROW_H)
    rowFrame:EnableMouse(true)

    -- Dungeon name (left side)
    local dungeonLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    dungeonLabel:SetJustifyH("LEFT")
    dungeonLabel:SetPoint("LEFT", rowFrame, "LEFT", COL_DUNGEON_X, 0)
    dungeonLabel:SetWidth(COL_DUNGEON_W)
    dungeonLabel:SetWordWrap(false)

    -- Spec icon
    local specIcon = rowFrame:CreateTexture(nil, "ARTWORK")
    specIcon:SetSize(ICON_SIZE, ICON_SIZE)
    specIcon:SetPoint("LEFT", rowFrame, "LEFT", COL_SPEC_ICON_X, 0)
    specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Spec name (immediately right of icon)
    local specLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    specLabel:SetJustifyH("LEFT")
    specLabel:SetPoint("LEFT", rowFrame, "LEFT", COL_SPEC_NAME_X, 0)
    specLabel:SetWidth(COL_SPEC_NAME_W)
    specLabel:SetWordWrap(false)

    -- Looted / total (right side, second from right)
    local obtainedLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    obtainedLabel:SetJustifyH("RIGHT")
    obtainedLabel:SetWidth(COL_LOOTED_W)
    obtainedLabel:SetWordWrap(false)
    obtainedLabel:SetPoint("RIGHT", rowFrame, "RIGHT", COL_LOOTED_R, 0)

    -- Chance percentage (rightmost)
    local pctLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    pctLabel:SetJustifyH("RIGHT")
    pctLabel:SetWidth(COL_PCT_W)
    pctLabel:SetWordWrap(false)
    pctLabel:SetPoint("RIGHT", rowFrame, "RIGHT", COL_PCT_R, 0)

    -- Hover highlight texture
    local hoverHighlight = rowFrame:CreateTexture(nil, "HIGHLIGHT")
    hoverHighlight:SetAllPoints(rowFrame)
    hoverHighlight:SetColorTexture(VCA.Theme.accent[1], VCA.Theme.accent[2], VCA.Theme.accent[3], 0.12)

    local row = {
        frame = rowFrame,
        dungeonLabel = dungeonLabel,
        specIcon = specIcon,
        specLabel = specLabel,
        obtainedLabel = obtainedLabel,
        pctLabel = pctLabel
    }
    dungeonRows[#dungeonRows + 1] = row
    return row
end

local function HideAllRows()
    for _, row in ipairs(dungeonRows) do
        row.frame:Hide()
    end
end

-- ── Scroll frame ──────────────────────────────────────────────────────────────

local scrollChild = CreateFrame("Frame", nil, contentArea)
local scrollFrame = CreateFrame("ScrollFrame", nil, contentArea)
scrollFrame:SetScrollChild(scrollChild)

scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetVerticalScroll()
    local maxScroll = math.max(0, scrollChild:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * ROW_H * 3)))
end)

-- ── Populate ──────────────────────────────────────────────────────────────────

Populate = function()
    HideAllRows()

    local contentW = frame:GetWidth() - PADDING * 2

    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, -(COL_HEADER_H + 8))
    scrollFrame:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -PADDING, 4)
    scrollChild:SetWidth(contentW)

    -- ── Collect and rank ──────────────────────────────────────────────────────

    local instanceIDs = VCA.LootPool.GetSeasonDungeonInstanceIDs()

    if #instanceIDs == 0 then
        -- Season filter not ready yet (edge case at early login)
        local row = GetOrCreateDungeonRow(scrollChild)
        row.frame:SetWidth(contentW)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        row.frame:Show()
        row.dungeonLabel:SetText("|cff888888" .. L["DUNGEON_OVERVIEW_NO_DATA"] .. "|r")
        row.specIcon:Hide()
        row.specLabel:SetText("")
        row.obtainedLabel:SetText("")
        row.pctLabel:SetText("")
        scrollChild:SetHeight(ROW_H)
        return
    end

    local entries = {}

    for _, instanceID in ipairs(instanceIDs) do
        local name = EJ_GetInstanceInfo(instanceID)
        if name then
            local selectedItems = VCA.Data.GetSelectedItems(VCA.ContentType.MYTHIC_PLUS, instanceID,
                VCA.MythicPlusEJDifficulty)
            local selectedList = {}
            for itemID in pairs(selectedItems) do
                selectedList[#selectedList + 1] = itemID
            end

            local hasSelected = #selectedList > 0
            if hasSelected then
                -- CHANCE should reflect selected-item odds for this dungeon.
                local rankings = VCA.Probability.RankCurrentPlayerSpecsForItems(selectedList,
                    VCA.ContentType.MYTHIC_PLUS, instanceID, VCA.MythicPlusEJDifficulty)

                -- rankings[1] is the best spec by the module sort policy.
                local best = rankings and rankings[1]
                entries[#entries + 1] = {
                    instanceID = instanceID,
                    name = name,
                    specName = best and best.specName,
                    specIcon = best and best.specIcon,
                    baseCount = best and best.baseCount or 0,
                    remainingCount = best and best.remainingCount or 0,
                    remainingOdds = best and best.remainingOdds or 0,
                    hasSelected = true,
                    selectedOdds = best and best.selectedOdds
                }
            else
                entries[#entries + 1] = {
                    instanceID = instanceID,
                    name = name,
                    specName = nil,
                    specIcon = nil,
                    baseCount = 0,
                    remainingCount = 0,
                    remainingOdds = 0,
                    hasSelected = false,
                    selectedOdds = nil
                }
            end
        end
    end

    -- Sort descending by remaining odds (highest single-item chance first).
    -- Tiebreak alphabetically by dungeon name for a stable display.
    table.sort(entries, function(a, b)
        -- Dungeons with selected items sort first.
        if a.hasSelected ~= b.hasSelected then
            return a.hasSelected
        end
        -- Selected dungeons are ordered by selected-item chance descending.
        if a.hasSelected and b.hasSelected then
            local aOdds = a.selectedOdds or 0
            local bOdds = b.selectedOdds or 0
            if aOdds ~= bOdds then
                return aOdds > bOdds
            end
        else
            -- Unselected dungeons: keep existing descending full-pool chance.
            if a.remainingOdds ~= b.remainingOdds then
                return a.remainingOdds > b.remainingOdds
            end
        end
        return (a.name or "") < (b.name or "")
    end)

    -- ── Render rows ───────────────────────────────────────────────────────────

    if #entries == 0 then
        local row = GetOrCreateDungeonRow(scrollChild)
        row.frame:SetWidth(contentW)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        row.frame:Show()
        row.dungeonLabel:SetText("|cff44ff44" .. L["DUNGEON_OVERVIEW_ALL_DONE"] .. "|r")
        row.specIcon:Hide()
        row.specLabel:SetText("")
        row.obtainedLabel:SetText("")
        row.pctLabel:SetText("")
        scrollChild:SetHeight(ROW_H)
        return
    end

    local rowTop = 0
    for _, entry in ipairs(entries) do
        local row = GetOrCreateDungeonRow(scrollChild)
        row.frame:SetWidth(contentW)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -rowTop)
        row.frame:Show()

        -- Dungeon name
        row.dungeonLabel:SetText("|cffdddddd" .. entry.name .. "|r")

        -- Spec icon/name: only show when this dungeon has selected items.
        if entry.hasSelected then
            if entry.specIcon then
                row.specIcon:SetTexture(entry.specIcon)
                row.specIcon:Show()
            else
                row.specIcon:Hide()
            end
            local warnPrefix = (entry.remainingCount == 1) and
                                   (CreateAtlasMarkup("Ping_Wheel_Icon_Warning", 14, 14) .. " ") or ""
            row.specLabel:SetText(warnPrefix .. "|cffaaaaaa" .. (entry.specName or "?") .. "|r")
        else
            row.specIcon:Hide()
            row.specLabel:SetText("|cff888888-|r")
        end

        -- Looted / total  (items already obtained / total pool for this spec)
        local obtained = entry.baseCount - entry.remainingCount
        row.obtainedLabel:SetText("|cff888888" .. obtained .. "/" .. entry.baseCount .. "|r")

        -- Loot chance: selected-item chance if this dungeon has selections,
        -- otherwise show a dash as requested.
        if entry.hasSelected and entry.selectedOdds then
            local pct = math.floor(entry.selectedOdds * 100 + 0.5)
            local pctColor = pct >= 20 and "|cffffff00" or "|cffdddddd"
            row.pctLabel:SetText(pctColor .. pct .. "%|r")
        else
            row.pctLabel:SetText("|cff888888-|r")
        end

        rowTop = rowTop + ROW_H + 2

        local capturedInstanceID = entry.instanceID
        row.frame:SetScript("OnEnter", function(self)
            if capturedInstanceID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                BuildDungeonTooltip(capturedInstanceID)
                GameTooltip:Show()
            end
        end)
        row.frame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row.frame:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and capturedInstanceID then
                Overview.Hide()
                if NavBar_Reset and EncounterJournal and EncounterJournal.navBar then
                    NavBar_Reset(EncounterJournal.navBar)
                end
                if type(EncounterJournal_DisplayInstance) == "function" then
                    EncounterJournal_DisplayInstance(capturedInstanceID)
                end
            end
        end)
    end

    scrollChild:SetHeight(math.max(rowTop, 1))
    scrollFrame:SetVerticalScroll(0)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Overview.Show()
    Overview.AnchorToEJ()
    frame:Show()
    RefreshSlotButtons()
    UpdateScanButton()
    Populate()
end

function Overview.Refresh()
    if frame:IsShown() then
        Populate()
    end
end

function Overview.Hide()
    frame:Hide()
    ClosePicker()
end

function Overview.IsShown()
    return frame:IsShown()
end

function Overview.IsMinimized()
    local db = _G[VCA.CHAR_DB_NAME]
    return db and db.overviewMinimized or false
end

function Overview.SetMinimized(val)
    local db = _G[VCA.CHAR_DB_NAME]
    if db then
        db.overviewMinimized = val and true or false
    end
end

-- ── Auto-refresh on loot spec change ─────────────────────────────────────────

local specChangeFrame = CreateFrame("Frame")
specChangeFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
specChangeFrame:SetScript("OnEvent", function()
    if frame:IsShown() then
        Populate()
    end
end)

-- Show the scan confirmation with the body text at display time.
local scanConfirmFrame = CreateFrame("Frame")
scanConfirmFrame:RegisterEvent("ADDON_LOADED")
scanConfirmFrame:SetScript("OnEvent", function(self, event, name)
    if name == VCA.ADDON_NAME then
        StaticPopupDialogs["VOIDCORE_SCAN_CONFIRM"].text = VCA.L["SCAN_CONFIRM_TITLE"] .. "\n\n|cffaaaaaa" ..
                                                               VCA.L["SCAN_CONFIRM_BODY"] .. "|r"
        self:UnregisterAllEvents()
    end
end)
