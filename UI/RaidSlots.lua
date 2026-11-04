-- VoidcoreAdvisor Reborn: RaidSlots
-- The same "select by slot" wishlist the Dungeon Overview has, for the raid overview: a grid of
-- equipment slots at the bottom of the panel. Pressing a slot opens a list with every item of
-- that slot your class can loot in this raid (on the difficulty shown), one line per item;
-- ticking an item chooses it on every boss that drops it, and "Select All" chooses them all.
local _, VCA = ...
local L = VCA.L

local Overview = VCA.RaidOverview
local frame = Overview.frame

-- ── Layout ────────────────────────────────────────────────────────────────────

local PADDING = 12
local SLOT_BTN_SIZE = 32
local SLOT_BTN_GAP = 6
local SLOT_ROWS_GAP = 6
local TITLE_H = 22
local SECTION_H = 8 + TITLE_H + 6 + SLOT_BTN_SIZE + SLOT_ROWS_GAP + SLOT_BTN_SIZE + 10
local BTNS_PER_ROW = 8
Overview.SLOT_SECTION_H = SECTION_H

local SLOT_ORDER = {"head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger",
                    "trinket", "weapon", "offhand", "tokens"}
local WEAPON_SUBSLOTS = {"1h", "2h", "ranged"}
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
-- INVTYPE_* -> slot key (the same grouping the loot tables use for dungeons)
local SLOT_TOKEN_MAP = {
    INVTYPE_HEAD = "head",
    INVTYPE_NECK = "neck",
    INVTYPE_SHOULDER = "shoulder",
    INVTYPE_CLOAK = "back",
    INVTYPE_CHEST = "chest",
    INVTYPE_ROBE = "chest",
    INVTYPE_WRIST = "wrist",
    INVTYPE_HAND = "hands",
    INVTYPE_WAIST = "waist",
    INVTYPE_LEGS = "legs",
    INVTYPE_FEET = "feet",
    INVTYPE_FINGER = "finger",
    INVTYPE_TRINKET = "trinket",
    INVTYPE_WEAPON = "1h",
    INVTYPE_SHIELD = "offhand",
    INVTYPE_WEAPONMAINHAND = "1h",
    INVTYPE_WEAPONOFFHAND = "1h",
    INVTYPE_HOLDABLE = "offhand",
    INVTYPE_2HWEAPON = "2h",
    INVTYPE_RANGED = "ranged",
    INVTYPE_RANGEDRIGHT = "ranged",
    INVTYPE_THROWN = "ranged",
    INVTYPE_RELIC = "ranged"
}

local function LootKeys(slotKey)
    if slotKey == "weapon" then
        return WEAPON_SUBSLOTS
    end
    return {slotKey}
end

-- ── Data ──────────────────────────────────────────────────────────────────────

local slotCache = {}
local function SlotOf(itemID)
    local v = slotCache[itemID]
    if v == nil then
        local equipLoc = select(4, C_Item.GetItemInfoInstant(itemID))
        if equipLoc == nil then
            return nil
        end
        -- Raid tier tokens have no equip slot: they get a group of their own.
        v = SLOT_TOKEN_MAP[equipLoc] or (VCA.GearFilter.IsToken(itemID) and "tokens") or false
        slotCache[itemID] = v
    end
    return v or nil
end

local function Difficulty()
    return Overview.difficultyID or (EJ_GetDifficulty and EJ_GetDifficulty()) or VCA.Difficulty.RAID_NORMAL
end

-- Encounter IDs of the raid on show, in Encounter Journal order (capped, as a safety net).
local function BossIDs()
    local ids = {}
    for idx = 1, 40 do
        local name, _, encounterID = EJ_GetEncounterInfoByIndex(idx)
        if not name then
            break
        end
        if type(encounterID) == "number" then
            ids[#ids + 1] = encounterID
        end
    end
    return ids
end

-- The items of one slot your class can loot in this raid: an ordered list of itemIDs and, for each,
-- the bosses (encounterIDs) that drop it.
local function ItemsForSlot(slotKey)
    local classID = VCA.SpecInfo.GetPlayerClassID()
    local diff = Difficulty()
    local wanted = {}
    for _, k in ipairs(LootKeys(slotKey)) do
        wanted[k] = true
    end
    local ordered, bosses = {}, {}
    for _, encounterID in ipairs(BossIDs()) do
        local data = VCA.SeasonData and VCA.SeasonData.raids and VCA.SeasonData.raids[encounterID]
        local list = data and data.byClass and data.byClass[diff] and data.byClass[diff][classID]
        for _, itemID in ipairs(list or {}) do
            local s = SlotOf(itemID)
            if s and wanted[s] then
                if not bosses[itemID] then
                    bosses[itemID] = {}
                    ordered[#ordered + 1] = itemID
                end
                bosses[itemID][#bosses[itemID] + 1] = encounterID
            end
        end
    end
    return ordered, bosses
end

local function Selected(encounterID)
    return VCA.Data.GetSelectedItems(VCA.ContentType.RAID, encounterID, Difficulty())
end

local function SetItem(encounterID, itemID, on)
    local current = Selected(encounterID)
    local updated = {}
    for id in pairs(current) do
        updated[id] = true
    end
    updated[itemID] = on and true or nil
    VCA.Data.SaveSelectedItems(VCA.ContentType.RAID, encounterID, Difficulty(), updated)
end

local function IsChosen(itemID, bossList)
    for _, encounterID in ipairs(bossList) do
        if Selected(encounterID)[itemID] then
            return true
        end
    end
    return false
end

local function IsSlotSelected(slotKey)
    local items, bosses = ItemsForSlot(slotKey)
    for _, itemID in ipairs(items) do
        if IsChosen(itemID, bosses[itemID]) then
            return true
        end
    end
    return false
end

local function SelectSlot(slotKey, on)
    local items, bosses = ItemsForSlot(slotKey)
    for _, itemID in ipairs(items) do
        for _, encounterID in ipairs(bosses[itemID]) do
            SetItem(encounterID, itemID, on)
        end
    end
end

local function SyncPanel()
    if VCA.Panel and VCA.Panel.ReloadItemSelections then
        VCA.Panel.ReloadItemSelections()
    end
    Overview.Refresh()
end

-- ── Slot section at the bottom of the panel ───────────────────────────────────

local section = CreateFrame("Frame", nil, frame)
section:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 34)
section:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 34)
section:SetHeight(SECTION_H)

local divider = section:CreateTexture(nil, "ARTWORK")
VCA.OnTheme(function()
    local t = VCA.Theme.border
    divider:SetColorTexture(t[1], t[2], t[3], 0.4)
end)
divider:SetPoint("TOPLEFT", section, "TOPLEFT", 16, 0)
divider:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, 0)
divider:SetHeight(1)

local title = section:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
title:SetPoint("TOPLEFT", section, "TOPLEFT", PADDING, -8)
VCA.OnTheme(function()
    title:SetText(VCA.Theme.hdr .. L["SLOT_FILTER_TOGGLE"] .. "|r")
end)

local clearBtn = CreateFrame("Button", nil, section)
clearBtn:SetSize(14, 14)
clearBtn:SetNormalFontObject("VCAFontNormal")
clearBtn:SetText("|cffff4444x|r")
clearBtn:SetPoint("TOPRIGHT", section, "TOPRIGHT", -PADDING, -8)

local slotButtons = {}

local function UpdateSlotVisual(entry, slotKey)
    if IsSlotSelected(slotKey) then
        entry.icon:SetVertexColor(1, 1, 1, 1)
        entry.glow:SetAlpha(1)
        entry.border:Show()
    else
        entry.icon:SetVertexColor(0.9, 0.9, 0.9, 1)
        entry.glow:SetAlpha(0)
        entry.border:Hide()
    end
end

local function RefreshSlotButtons()
    for _, slotKey in ipairs(SLOT_ORDER) do
        if slotButtons[slotKey] then
            UpdateSlotVisual(slotButtons[slotKey], slotKey)
        end
    end
end
-- RaidOverview calls this after it redraws its list.
Overview.RefreshSlots = RefreshSlotButtons

-- ── Item picker ───────────────────────────────────────────────────────────────

local PICKER_W, ROW_H, PAD = 400, 22, 10

local catcher = CreateFrame("Frame", nil, UIParent)
catcher:SetAllPoints(UIParent)
catcher:SetFrameStrata("FULLSCREEN")
catcher:EnableMouse(true)
catcher:Hide()

local picker = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
picker:SetWidth(PICKER_W)
picker:SetFrameStrata("FULLSCREEN_DIALOG")
picker:SetClampedToScreen(true)
picker:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1
})
VCA.OnTheme(function()
    local b, e = VCA.Theme.bg, VCA.Theme.border
    picker:SetBackdropColor(b[1], b[2], b[3], 0.98)
    picker:SetBackdropBorderColor(e[1], e[2], e[3], 1)
end)
picker:Hide()

local current -- the slot key the picker shows

local function ClosePicker()
    picker:Hide()
    catcher:Hide()
    current = nil
end
catcher:SetScript("OnMouseDown", ClosePicker)

local pickerTitle = picker:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
pickerTitle:SetPoint("TOPLEFT", PAD, -PAD)
pickerTitle:SetPoint("TOPRIGHT", -(PAD + 22), -PAD)
pickerTitle:SetJustifyH("LEFT")

local closeBtn = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
closeBtn:SetSize(20, 20)
closeBtn:SetPoint("TOPRIGHT", -2, -2)
closeBtn:SetScript("OnClick", ClosePicker)

local scroll = CreateFrame("ScrollFrame", nil, picker)
scroll:SetPoint("TOPLEFT", picker, "TOPLEFT", PAD, -(PAD + 24))
scroll:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -PAD, PAD)
local child = CreateFrame("Frame", nil, scroll)
child:SetWidth(PICKER_W - PAD * 2)
scroll:SetScrollChild(child)
scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * ROW_H * 3)))
end)

-- " (Boss, Boss)": the bosses of this raid that drop the item.
local function BossSuffix(bossList)
    local names = {}
    for _, encounterID in ipairs(bossList) do
        names[#names + 1] = EJ_GetEncounterInfo(encounterID)
    end
    return #names > 0 and (" |cff9d9d9d(" .. table.concat(names, ", ") .. ")|r") or ""
end

local rows = {}
local function GetRow(i)
    local r = rows[i]
    if r then
        return r
    end
    local b = CreateFrame("Button", nil, child)
    b:SetHeight(ROW_H)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.14)
    local check = b:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("LEFT", 2, 0)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 22, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local label = b:CreateFontString(nil, "OVERLAY", "VCAFontNormalSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    label:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    r = {frame = b, check = check, icon = icon, label = label}
    rows[i] = r
    return r
end

local function FillPicker(slotKey)
    local items, bosses = ItemsForSlot(slotKey)
    pickerTitle:SetText(VCA.Theme.hdr .. (L["SLOT_" .. slotKey] or slotKey) .. "|r")
    for _, r in ipairs(rows) do
        r.frame:Hide()
    end
    local n = 0
    local function NextRow()
        n = n + 1
        local r = GetRow(n)
        r.frame:ClearAllPoints()
        r.frame:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(n - 1) * ROW_H - (n > 1 and 6 or 0))
        r.frame:SetPoint("RIGHT", child, "RIGHT", 0, 0)
        r.frame:Show()
        return r
    end

    -- "Select All" / "Deselect All"
    local all = NextRow()
    local anySelected = IsSlotSelected(slotKey)
    all.icon:Hide()
    all.label:ClearAllPoints()
    all.label:SetPoint("LEFT", all.frame, "LEFT", 22, 0)
    all.label:SetPoint("RIGHT", all.frame, "RIGHT", -4, 0)
    all.label:SetText(anySelected and L["SLOT_DESELECT_ALL"] or L["SLOT_SELECT_ALL"])
    all.label:SetTextColor(1, 1, 1)
    all.check:SetAlpha(anySelected and 1 or 0)
    all.frame:SetScript("OnClick", function()
        SelectSlot(slotKey, not IsSlotSelected(slotKey))
        SyncPanel()
        FillPicker(slotKey)
    end)
    all.frame:SetScript("OnEnter", nil)
    all.frame:SetScript("OnLeave", nil)

    for _, itemID in ipairs(items) do
        local r = NextRow()
        local name, link, quality = C_Item.GetItemInfo(itemID)
        local icon = C_Item.GetItemIconByID(itemID)
        r.icon:SetTexture(icon or 134400)
        r.icon:Show()
        r.label:ClearAllPoints()
        r.label:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
        r.label:SetPoint("RIGHT", r.frame, "RIGHT", -4, 0)
        if name then
            r.label:SetText("|cnIQ" .. (quality or 1) .. ":" .. name .. "|r" .. BossSuffix(bosses[itemID]))
        else
            if C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(itemID)
            end
            r.label:SetText("|cff888888[" .. itemID .. "]|r")
        end
        r.label:SetTextColor(1, 1, 1)
        r.check:SetAlpha(IsChosen(itemID, bosses[itemID]) and 1 or 0)
        r.frame:SetScript("OnClick", function()
            local on = not IsChosen(itemID, bosses[itemID])
            for _, encounterID in ipairs(bosses[itemID]) do
                SetItem(encounterID, itemID, on)
            end
            SyncPanel()
            FillPicker(slotKey)
        end)
        r.frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemID)
            GameTooltip:Show()
        end)
        r.frame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    child:SetHeight(n * ROW_H + 10)
    local wanted = math.min(320, n * ROW_H + PAD * 2 + 24 + 10)
    picker:SetHeight(wanted)
    RefreshSlotButtons()
end

local function OpenPicker(slotKey, anchor)
    if picker:IsShown() and current == slotKey then
        ClosePicker()
        return
    end
    current = slotKey
    picker:ClearAllPoints()
    picker:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -4, 6)
    FillPicker(slotKey)
    scroll:SetVerticalScroll(0)
    catcher:Show()
    picker:Show()
end

-- ── Slot buttons ──────────────────────────────────────────────────────────────

local gridW = BTNS_PER_ROW * SLOT_BTN_SIZE + (BTNS_PER_ROW - 1) * SLOT_BTN_GAP
local gridTopY = -(8 + TITLE_H + 6)

for i, slotKey in ipairs(SLOT_ORDER) do
    local col = (i - 1) % BTNS_PER_ROW
    local row = math.floor((i - 1) / BTNS_PER_ROW)
    local inRow = math.min(BTNS_PER_ROW, #SLOT_ORDER - row * BTNS_PER_ROW) -- each row is centered
    local btn = CreateFrame("Frame", nil, section)
    btn:SetSize(SLOT_BTN_SIZE, SLOT_BTN_SIZE)
    btn:SetPoint("TOP", section, "TOP", (col - (inRow - 1) / 2) * (SLOT_BTN_SIZE + SLOT_BTN_GAP),
        gridTopY - row * (SLOT_BTN_SIZE + SLOT_ROWS_GAP))
    btn:EnableMouse(true)

    local glow = btn:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(btn)
    glow:SetColorTexture(0.45, 0.0, 0.7, 0.85)
    glow:SetAlpha(0)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    local invName = SLOT_INV_NAME[slotKey]
    if invName and GetInventorySlotInfo then
        local _, textureName = GetInventorySlotInfo(invName)
        if textureName then
            icon:SetTexture(textureName)
        end
    end
    if slotKey == "tokens" then
        icon:SetTexture("Interface/Icons/INV_Misc_Coin_01")
    end
    icon:SetVertexColor(0.9, 0.9, 0.9, 1)

    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(btn)
    hover:SetColorTexture(1, 1, 1, 0.18)

    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    border:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2})
    border:SetBackdropBorderColor(0.95, 0.78, 0.1, 1)
    border:Hide()

    slotButtons[slotKey] = {icon = icon, glow = glow, border = border}

    btn:SetScript("OnMouseDown", function(self)
        OpenPicker(slotKey, self)
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["SLOT_" .. slotKey] or slotKey, 0.85, 0.3, 1)
        local items, bosses = ItemsForSlot(slotKey)
        local chosen = 0
        for _, itemID in ipairs(items) do
            if IsChosen(itemID, bosses[itemID]) then
                chosen = chosen + 1
            end
        end
        GameTooltip:AddLine(chosen .. " / " .. #items, 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

clearBtn:SetScript("OnClick", function()
    for _, slotKey in ipairs(SLOT_ORDER) do
        SelectSlot(slotKey, false)
    end
    ClosePicker()
    SyncPanel()
end)
clearBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["SLOT_FILTER_CLEAR"])
    GameTooltip:Show()
end)
clearBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

frame:HookScript("OnHide", ClosePicker)
frame:HookScript("OnShow", RefreshSlotButtons)
