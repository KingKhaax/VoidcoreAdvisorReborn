-- VoidcoreAdvisor: BonusRollConfirm
-- Replaces BonusRollFrame with a custom VCA window positioned at the same
-- screen location (+small offset so the original is still visible behind it).
--
-- Frame level 7 + EnableMouse(true) prevents accidental clicks on the original
-- Roll/Pass buttons (which sit at level 5-6).
--
-- Roll button requires TWO clicks (confirm) â€” this is intentional and critical.
-- Pass button fires immediately (no confirmation).
local addonName, VCA = ...
local L = VCA.L

VCA.BonusRollConfirm = {}
local BRC = VCA.BonusRollConfirm

local isPreview = false
local cachedItemLink = nil -- item link for icon tooltip
local cachedDisplayItemID = nil -- numeric item ID from EJLinkButton.displayItemID
local cachedSpecIcon = nil -- spec icon texture path for |T|t embedding
local cachedSpecName = nil -- spec name for combined spec row text
local cachedSource = nil -- source table for spec list tooltip
local cachedSpecID = nil -- specID used when the window is currently displayed
local oneItemLeft = false -- true when the active spec has a single item left in the pool
local previewTimerStart = nil -- GetTime() when ShowPreview was called (nil in live mode)
local previewTimerDuration = 30 -- seconds; mirrors a typical bonus-roll countdown
local cachedPromptData = nil -- structured payload from SPELL_CONFIRMATION_PROMPT
local isSpecChangePending = false -- true while SetLootSpecialization is in-flight; suppresses Uninject

-- â”€â”€ Guard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function IsEnabled()
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    return gdb and gdb.bonusRollConfirmEnabled == true
end

local function IsConfirmEnabled()
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    return not gdb or gdb.brcConfirmEnabled ~= false
end

-- The bonus roll window has its own theme setting (default: the colors of your class).
local function RollPalette()
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    return VCA.GetPalette(gdb and gdb.rollTheme or "class")
end

local function IsSpecListEnabled()
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    return gdb and gdb.brcSpecListEnabled == true
end

-- Reverse lookup: Voidcache itemID -> { sourceType, sourceID }
-- Built lazily on first call after Constants are loaded.
local cacheItemSourceMap
local function GetSourceFromDisplayItemID(itemID)
    if not itemID then
        return nil
    end
    if not cacheItemSourceMap then
        cacheItemSourceMap = {}
        for instanceID, cid in pairs(VCA.DungeonVoidcacheIDs or {}) do
            cacheItemSourceMap[cid] = {
                sourceType = VCA.ContentType.MYTHIC_PLUS,
                sourceID = instanceID
            }
        end
        for encounterID, cid in pairs(VCA.RaidEncounterCacheIDs or {}) do
            cacheItemSourceMap[cid] = {
                sourceType = VCA.ContentType.RAID,
                sourceID = encounterID
            }
        end
    end
    return cacheItemSourceMap[itemID]
end

-- â”€â”€ Texture-sync helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Maps Enum.ItemCreationContext values from SPELL_CONFIRMATION_PROMPT to a content
-- type and EJ difficulty ID.  For M+/delve contexts, ejDiffID is always
-- VCA.MythicPlusEJDifficulty (23).  For raid contexts, the game difficulty ID
-- coincides with the EJ difficulty ID (14/15/16/17).
local ITEM_CONTEXT_TO_SOURCE = {
    [3] = {
        contentType = VCA.ContentType.RAID,
        ejDiffID = VCA.Difficulty.RAID_NORMAL
    }, -- RaidNormal
    [4] = {
        contentType = VCA.ContentType.RAID,
        ejDiffID = VCA.Difficulty.RAID_LFR
    }, -- RaidFinder
    [5] = {
        contentType = VCA.ContentType.RAID,
        ejDiffID = VCA.Difficulty.RAID_HEROIC
    }, -- RaidHeroic
    [6] = {
        contentType = VCA.ContentType.RAID,
        ejDiffID = VCA.Difficulty.RAID_MYTHIC
    }, -- RaidMythic
    [16] = {
        contentType = VCA.ContentType.MYTHIC_PLUS,
        ejDiffID = VCA.MythicPlusEJDifficulty
    }, -- Mythic Keystone
    [55] = {
        contentType = VCA.ContentType.MYTHIC_PLUS,
        ejDiffID = VCA.MythicPlusEJDifficulty
    } -- Nightmare Prey
}

-- Resolves a complete loot source from a SPELL_CONFIRMATION_PROMPT payload.
-- Returns { sourceType, sourceID, difficultyID, keyLevel } or nil.
local function ResolveSourceFromPromptData(promptData)
    if not (promptData and promptData.displayItemID and promptData.itemContext) then
        return nil
    end
    local mapping = ITEM_CONTEXT_TO_SOURCE[promptData.itemContext]
    if not mapping then
        return nil
    end
    local base = GetSourceFromDisplayItemID(promptData.displayItemID)
    if not base then
        return nil
    end
    local keyLevel = nil
    if mapping.contentType == VCA.ContentType.MYTHIC_PLUS then
        local lvl = promptData.treasureContextLevel
        keyLevel = (lvl and lvl > 0) and lvl or nil
    end
    return {
        sourceType = mapping.contentType,
        sourceID = base.sourceID,
        difficultyID = mapping.ejDiffID,
        keyLevel = keyLevel
    }
end

-- Copies Normal/Pushed/Highlight/Disabled textures from src onto dst so an
-- interceptor button looks identical to the real Blizzard button.

local function SyncButtonAppearance(src, dst)
    local t
    t = src:GetNormalTexture();
    dst:SetNormalTexture(t and t:GetTexture() or nil)
    t = src:GetPushedTexture();
    dst:SetPushedTexture(t and t:GetTexture() or nil)
    t = src:GetHighlightTexture();
    if t then
        dst:SetHighlightTexture(t:GetTexture())
    end
    t = src:GetDisabledTexture();
    if t then
        dst:SetDisabledTexture(t:GetTexture())
    end
end

-- â”€â”€ Custom window â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Offset from BonusRollFrame TOPLEFT so the original peeks from behind.

local win = CreateFrame("Frame", "VCARollWindow", UIParent, "BackdropTemplate")
win:SetFrameLevel(7)
win:EnableMouse(true)
win:EnableMouseMotion(true)
win:SetClampedToScreen(true)
win:Hide()
win:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 3,
    insets = {
        left = 3,
        right = 3,
        top = 3,
        bottom = 3
    }
})
VCA.OnTheme(function() local t = RollPalette().bg; win:SetBackdropColor(t[1], t[2], t[3], 0.97) end)
VCA.OnTheme(function() local t = RollPalette().border; win:SetBackdropBorderColor(t[1], t[2], t[3], 1) end)

-- Thin black line just inside the grey frame, like the stock popup frames.
local winInnerEdge = CreateFrame("Frame", nil, win, "BackdropTemplate")
winInnerEdge:SetPoint("TOPLEFT", win, "TOPLEFT", 3, -3)
winInnerEdge:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -3, 3)
winInnerEdge:SetBackdrop({
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1
})
winInnerEdge:SetBackdropBorderColor(0, 0, 0, 1)

-- Title – hidden in compact layout
local winTitle = win:CreateFontString(nil, "OVERLAY", "VCAFontNormalLarge")
winTitle:SetPoint("TOP", win, "TOP", 0, -14)
VCA.OnTheme(function() winTitle:SetText(RollPalette().hdr .. "VoidcoreAdvisor|r") end)
winTitle:Hide()

-- Subtitle – hidden in compact layout
local winSubtitle = win:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
winSubtitle:SetPoint("TOP", winTitle, "BOTTOM", 0, -2)
winSubtitle:SetText("|cff888888" .. L["BONUS_ROLL_CONFIRM_SUBTITLE"] .. "|r")
winSubtitle:Hide()

-- Header divider – hidden in compact layout
local winHeaderDiv = win:CreateTexture(nil, "ARTWORK")
VCA.OnTheme(function() local t = RollPalette().border; winHeaderDiv:SetColorTexture(t[1], t[2], t[3], 0.4) end)
winHeaderDiv:SetHeight(1)
winHeaderDiv:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -62)
winHeaderDiv:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, -62)
winHeaderDiv:Hide()

-- Item icon
local winItemIcon = win:CreateTexture(nil, "ARTWORK")
winItemIcon:SetSize(40, 40)
winItemIcon:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -14)
winItemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
winItemIcon:Hide()

-- Epic-quality frame around the item icon
local winItemBorder = win:CreateTexture(nil, "BACKGROUND")
winItemBorder:SetColorTexture(0.64, 0.21, 0.93, 1)
winItemBorder:SetPoint("TOPLEFT", winItemIcon, "TOPLEFT", -2, 2)
winItemBorder:SetPoint("BOTTOMRIGHT", winItemIcon, "BOTTOMRIGHT", 2, -2)

-- Transparent button over the icon for tooltip hit-testing
local winIconBtn = CreateFrame("Button", nil, win)
winIconBtn:SetAllPoints(winItemIcon)
winIconBtn:SetScript("OnEnter", function(self)
    if cachedDisplayItemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if cachedPromptData and cachedPromptData.itemContext then
            -- Use the exact context from SPELL_CONFIRMATION_PROMPT for a correctly
            -- contextualized tooltip (right ilvl, affixes, track, etc.).
            GameTooltip:SetItemByID(cachedDisplayItemID, nil, cachedPromptData.itemContext,
                cachedPromptData.treasureContextLevel)
        else
            -- Preview mode or no prompt data: fall back to plain hyperlink.
            GameTooltip:SetHyperlink(cachedItemLink or ("item:" .. cachedDisplayItemID))
        end
        GameTooltip:Show()
        return
    end
    -- Delegate to EJLinkButton's own OnEnter if available
    local pf = BonusRollFrame and BonusRollFrame.PromptFrame
    local ejBtn = pf and pf.EncounterJournalLinkButton
    if ejBtn then
        local onEnter = ejBtn:GetScript("OnEnter")
        if onEnter then
            onEnter(ejBtn)
        end
    end
end)
winIconBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Item name label
local winItemName = win:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
winItemName:SetPoint("TOPLEFT", winItemIcon, "TOPRIGHT", 8, -2)
winItemName:SetWidth(238)
winItemName:SetJustifyH("LEFT")
winItemName:SetWordWrap(false)

-- Second line of the item name (the part after the colon, e.g. "Presa")
local winItemSub = win:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
winItemSub:SetPoint("TOPLEFT", winItemName, "BOTTOMLEFT", 0, -1)
winItemSub:SetWidth(238)
winItemSub:SetJustifyH("LEFT")
winItemSub:SetWordWrap(true)

-- Voidcore count + cost line (shown below the name lines)
local winVoidcoreInfo = win:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
winVoidcoreInfo:SetPoint("TOPLEFT", winItemSub, "BOTTOMLEFT", 0, -3)

-- "Alijo de Vacio nebuloso: Presa" -> name on the first line (in the quality color), "Presa" under it.
-- The second line says where the roll comes from once that is known (see ApplySourceSub).
local sourceSub

local function SetItemTitle(hex, fullName)
    local name, sub = fullName:match("^([^:]+):%s*(.+)$")
    name = (name or fullName):gsub("%s+$", "")
    winItemName:SetText("|c" .. hex .. name .. "|r")
    if sourceSub then
        winItemSub:SetText(sourceSub)
    else
        winItemSub:SetText(sub and ("|cffcdbfe0" .. sub .. "|r") or "")
    end
end

-- Colors of the second line, the ones of the log parses so the value of a roll reads at a glance:
-- a Mythic+ key goes from grey (+2) to the color of a perfect parse (+10 and above), and a raid
-- difficulty is green (Normal), purple (Heroic) or gold (Mythic).
local KEY_COLORS = {"9d9d9d", "1eff00", "1eff00", "0070ff", "0070ff", "a335ee", "a335ee", "a335ee", "e5cc80"}
local RAID_DIFF_COLORS = {[14] = "1eff00", [15] = "a335ee", [16] = "e5cc80"}

local function KeyLevelColor(level)
    local i = math.min(#KEY_COLORS, math.max(1, (tonumber(level) or 2) - 1))
    return "|cff" .. KEY_COLORS[i]
end

-- Raid: "Boss name (Difficulty)".  Mythic+: "Mythic +10".
local function SourceSubtitle(source)
    if not (source and source.sourceType) then
        return nil
    end
    if source.sourceType == VCA.ContentType.RAID then
        local boss = source.sourceID and EJ_GetEncounterInfo and EJ_GetEncounterInfo(source.sourceID)
        local diff = source.difficultyID and GetDifficultyInfo and GetDifficultyInfo(source.difficultyID)
        if type(boss) ~= "string" or boss == "" then
            boss = nil
        end
        if type(diff) ~= "string" or diff == "" then
            diff = nil
        end
        local diffColor = "|cff" .. (RAID_DIFF_COLORS[source.difficultyID] or "cdbfe0")
        if boss and diff then
            return "|cffcdbfe0" .. boss .. "|r " .. diffColor .. "(" .. diff .. ")|r"
        end
        return boss and ("|cffcdbfe0" .. boss .. "|r") or (diff and (diffColor .. diff .. "|r")) or nil
    elseif source.sourceType == VCA.ContentType.MYTHIC_PLUS then
        local label = (L["DIFFICULTY_MYTHIC_PLUS"] or "Mythic+"):gsub("%s*%+$", "")
        local level = source.keyLevel
        if not level and VCA.Detection and VCA.Detection.GetActiveSource then
            local active = VCA.Detection.GetActiveSource()
            level = active and active.sourceType == VCA.ContentType.MYTHIC_PLUS and active.keyLevel or nil
        end
        if level then
            return KeyLevelColor(level) .. label .. " +" .. level .. "|r"
        end
        return "|cffcdbfe0" .. label .. "|r"
    end
    return nil
end

local function ApplySourceSub(source)
    local text = SourceSubtitle(source)
    sourceSub = text
    if text then
        winItemSub:SetText(text)
    end
end

-- Timer bar  (value mirrored from BonusRollFrame.PromptFrame.Timer.Bar via OnUpdate)
local timerBar = CreateFrame("StatusBar", nil, win)
timerBar:SetHeight(14)
timerBar:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -72)
timerBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, -72)
timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
VCA.OnTheme(function() local t = RollPalette().timer; timerBar:SetStatusBarColor(t[1], t[2], t[3], 1) end)
local timerBorder = timerBar:CreateTexture(nil, "BACKGROUND", nil, -1)
timerBorder:SetColorTexture(0, 0, 0, 1)
timerBorder:SetPoint("TOPLEFT", timerBar, "TOPLEFT", -1, 1)
timerBorder:SetPoint("BOTTOMRIGHT", timerBar, "BOTTOMRIGHT", 1, -1)
timerBar:SetMinMaxValues(0, 1)
timerBar:SetValue(1)

-- Remaining time, centered on the bar.
local timerText = timerBar:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
timerText:SetPoint("CENTER", timerBar, "CENTER", 0, 0)
timerText:SetShadowColor(0, 0, 0, 1)
timerText:SetShadowOffset(1, -1)
local timerBg = timerBar:CreateTexture(nil, "BACKGROUND")
timerBg:SetAllPoints()
VCA.OnTheme(function() local t = RollPalette().timerBg; timerBg:SetColorTexture(t[1], t[2], t[3], 0.8) end)

-- Separator between timer and spec row
local topSep = win:CreateTexture(nil, "ARTWORK")
VCA.OnTheme(function() local t = RollPalette().border; topSep:SetColorTexture(t[1], t[2], t[3], 0.35) end)
topSep:SetHeight(1)
topSep:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -88)
topSep:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, -88)

-- Spec row (centered: |T...|t icon + name + " - " + chance in one FontString)
local specLabel = win:CreateFontString(nil, "OVERLAY", "VCAFontNormal") -- retained as upvalue, hidden
specLabel:Hide()

local specIcon = win:CreateTexture(nil, "ARTWORK") -- retained as upvalue, hidden (icon embedded via |T|t)
specIcon:SetSize(16, 16)

local specName = win:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
specName:SetPoint("TOP", win, "TOP", 0, -100)
specName:SetJustifyH("CENTER")
specName:SetWidth(340)

-- chanceText retained as upvalue, permanently hidden (merged into specName text)
local chanceText = win:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
chanceText:Hide()

-- Odds panel: the chance of one of your chosen items on the left, the chosen items on the right.
local oddsPanel = CreateFrame("Frame", nil, win, "BackdropTemplate")
oddsPanel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1
})
VCA.OnTheme(function()
    local e = RollPalette().border
    oddsPanel:SetBackdropColor(1, 1, 1, 0.05)
    oddsPanel:SetBackdropBorderColor(e[1], e[2], e[3], 0.55)
end)
oddsPanel:Hide()
local oddsPct = oddsPanel:CreateFontString(nil, "OVERLAY", "VCAFontNormalHuge")
oddsPct:SetPoint("TOPLEFT", oddsPanel, "TOPLEFT", 12, -9)
local oddsCaption = oddsPanel:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
oddsCaption:SetPoint("TOPLEFT", oddsPct, "BOTTOMLEFT", 0, -3)
local oddsMessage = oddsPanel:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
oddsMessage:SetPoint("LEFT", oddsPanel, "LEFT", 12, 0)
oddsMessage:SetPoint("RIGHT", oddsPanel, "RIGHT", -12, 0)
oddsMessage:SetJustifyH("CENTER")
local chosenIcons = {}
for i = 1, 5 do
    local t = oddsPanel:CreateTexture(nil, "ARTWORK")
    t:SetSize(24, 24)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t:SetPoint("TOPLEFT", oddsPanel, "TOPLEFT", 150 + (i - 1) * 28, -9)
    t:Hide()
    chosenIcons[i] = t
end
local chosenText = oddsPanel:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
chosenText:SetPoint("TOPLEFT", oddsPanel, "TOPLEFT", 150, -39)
chosenText:SetJustifyH("LEFT")

-- Transparent hit-testing frame over the odds panel for the wanted-items tooltip.
local chanceHitFrame = CreateFrame("Frame", nil, win)
chanceHitFrame:SetAllPoints(oddsPanel)
chanceHitFrame:EnableMouse(true)
chanceHitFrame:Hide()

-- Slot sort order for the wanted-items tooltip (mirrors DungeonOverview).
local CHANCE_TIP_SLOT_ORDER = {
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

-- Builds and shows the wanted-items tooltip for the chance text row.
local function ShowChanceTooltip(owner)
    if not (cachedSource and cachedSource.sourceType and cachedSource.sourceID) then
        return
    end
    if not cachedSpecID then
        return
    end
    local source = cachedSource
    local specID = cachedSpecID

    -- Items lootable by the current spec
    local specItems = VCA.LootPool.GetItemsForSpec(source.sourceType, source.sourceID, source.difficultyID,
        VCA.SpecInfo.GetPlayerClassID(), specID)
    local specItemSet = {}
    for _, itemID in ipairs(specItems) do
        specItemSet[itemID] = true
    end

    -- Wanted items: selected + lootable by this spec + not yet obtained
    local selectedSet = VCA.Data.GetSelectedItems(source.sourceType, source.sourceID, source.difficultyID)
    local rows = {}
    for itemID in pairs(selectedSet) do
        if specItemSet[itemID] and
            not VCA.Data
                .IsObtainedForKeyTier(source.sourceType, source.sourceID, source.difficultyID, specID, itemID, nil) then
            local itemName, _, _, _, _, _, _, _, equipLoc, itemTexture = C_Item.GetItemInfo(itemID)
            if itemName then
                rows[#rows + 1] = {
                    itemName = itemName,
                    itemTexture = itemTexture,
                    equipLoc = equipLoc,
                    sortKey = CHANCE_TIP_SLOT_ORDER[equipLoc] or 99
                }
            end
        end
    end

    if #rows == 0 then
        return
    end

    table.sort(rows, function(a, b)
        if a.sortKey ~= b.sortKey then
            return a.sortKey < b.sortKey
        end
        return (a.itemName or "") < (b.itemName or "")
    end)

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["BONUS_ROLL_WANTED_TOOLTIP_TITLE"], 0.85, 0.3, 1)
    for _, row in ipairs(rows) do
        local iconMarkup = row.itemTexture and ("|T" .. row.itemTexture .. ":14:14:0:0:64:64:4:60:4:60|t ") or "  "
        local nameColored = "|cnIQ4:" .. row.itemName .. "|r"
        local slotText = (row.equipLoc and _G[row.equipLoc] and _G[row.equipLoc] ~= "") and
                             (" |cff888888[" .. _G[row.equipLoc] .. "]|r") or ""
        GameTooltip:AddLine("  " .. iconMarkup .. nameColored .. slotText)
    end
    GameTooltip:Show()
end

chanceHitFrame:SetScript("OnEnter", function(self)
    ShowChanceTooltip(self)
end)
chanceHitFrame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Dynamic loot section (only shown when Detection recognises the source)
local lootSep = win:CreateTexture(nil, "ARTWORK")
VCA.OnTheme(function() local t = RollPalette().border; lootSep:SetColorTexture(t[1], t[2], t[3], 0.35) end)
lootSep:SetHeight(1)
lootSep:Hide()

local lootLine = win:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
lootLine:SetWidth(320)
lootLine:SetJustifyH("CENTER")
lootLine:Hide()

local lootCountLine = win:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
lootCountLine:SetWidth(320)
lootCountLine:SetJustifyH("CENTER")
lootCountLine:Hide()

local warnHeader = win:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
warnHeader:SetWidth(320)
warnHeader:SetJustifyH("CENTER")
warnHeader:Hide()

local warnBody = win:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
warnBody:SetWidth(320)
warnBody:SetJustifyH("CENTER")
warnBody:Hide()

-- Per-spec remaining item counts section
local specListSep = win:CreateTexture(nil, "ARTWORK")
VCA.OnTheme(function() local t = RollPalette().border; specListSep:SetColorTexture(t[1], t[2], t[3], 0.35) end)
specListSep:SetHeight(1)
specListSep:Hide()

local specListHeader = win:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
specListHeader:SetText("|cff888888" .. L["REMINDER_SPEC_LIST_HEADER"] .. "|r")
specListHeader:Hide()

local specListRows = {}
for i = 1, 4 do
    local row = {}
    -- Clickable button; spec icon fills the button face
    row.btn = CreateFrame("Button", nil, win)
    row.btn:SetSize(160, 24)
    -- Chip: an outline (bright for the active loot spec, dim for the others) and a dark fill
    row.edge = row.btn:CreateTexture(nil, "BACKGROUND")
    row.edge:SetAllPoints(row.btn)
    row.bg = row.btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.bg:SetPoint("TOPLEFT", row.btn, "TOPLEFT", 1, -1)
    row.bg:SetPoint("BOTTOMRIGHT", row.btn, "BOTTOMRIGHT", -1, 1)
    row.bg:SetColorTexture(0.04, 0.09, 0.06, 0.95)
    row.glow = row.btn:CreateTexture(nil, "OVERLAY")
    row.glow:SetPoint("CENTER", row.btn, "CENTER", 0, 0)
    row.glow:SetSize(50, 50)
    row.glow:SetAtlas("currency-frame-glow")
    row.glow:Hide()
    row.icon = row.btn:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row.btn, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = row.btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row.btn)
    hl:SetColorTexture(1, 1, 1, 0.2)
    row.label = row.btn:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.count = row.btn:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
    row.count:SetJustifyH("RIGHT")
    row.btn:Hide()
    row.label:Hide()
    row.count:Hide()
    specListRows[i] = row
end

-- Shared: build and show the Loot Protection tooltip from any owner frame
local function ShowSpecListTooltip(owner, anchor)
    if not (cachedSource and cachedSource.sourceType and cachedSource.sourceID) then
        return
    end
    local specs = VCA.SpecInfo.GetPlayerSpecs()
    if not specs or #specs == 0 then
        return
    end
    local selectedSet = VCA.Data.GetSelectedItems(cachedSource.sourceType, cachedSource.sourceID,
        cachedSource.difficultyID)
    GameTooltip:SetOwner(owner, anchor)
    GameTooltip:SetText(L["SPEC_LIST_TOOLTIP_TITLE"], 1, 0.82, 0)
    GameTooltip:AddLine(" ")
    for _, spec in ipairs(specs) do
        local items = VCA.LootPool.GetCachedItemsForSpec(cachedSource.sourceType, cachedSource.sourceID,
            cachedSource.difficultyID, spec.classID, spec.specID)
        if not items then
            items = VCA.LootPool.GetItemsForSpec(cachedSource.sourceType, cachedSource.sourceID,
                cachedSource.difficultyID, spec.classID, spec.specID)
        end
        local pool = items or {}
        local poolSet = {}
        for _, itemID in ipairs(pool) do
            poolSet[itemID] = true
        end
        local remaining = 0
        for _, itemID in ipairs(pool) do
            if not VCA.Data.IsObtained(cachedSource.sourceType, cachedSource.sourceID, cachedSource.difficultyID,
                spec.specID, itemID) then
                remaining = remaining + 1
            end
        end
        local wanted = 0
        if selectedSet then
            for itemID in pairs(selectedSet) do
                if poolSet[itemID] then
                    wanted = wanted + 1
                end
            end
        end
        local _, sName = GetSpecializationInfoByID(spec.specID)
        local iconT = "|T" .. (spec.icon or 134400) .. ":14:14|t"
        local wantedColor = wanted > 0 and "|cffffff00" or "|cff888888"
        local rightStr = wantedColor .. wanted .. " wanted|r |cff888888-  " .. remaining .. " remaining|r"
        GameTooltip:AddDoubleLine(iconT .. " " .. (sName or "?"), rightStr, 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
end

-- Hover frame (kept for HideSpecList compatibility; always hidden now)
local specListHitFrame = CreateFrame("Frame", nil, win)
specListHitFrame:SetPoint("TOP", win, "TOP", 0, -82)
specListHitFrame:SetSize(340, 26)
specListHitFrame:EnableMouse(true)
specListHitFrame:SetScript("OnEnter", function(self)
    ShowSpecListTooltip(self, "ANCHOR_BOTTOMRIGHT")
end)
specListHitFrame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
specListHitFrame:Hide()

-- Spec icon in top-right corner — hover shows Loot Protection tooltip
local specCornerIcon = win:CreateTexture(nil, "ARTWORK")
specCornerIcon:SetSize(28, 28)
specCornerIcon:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, -14)
specCornerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
specCornerIcon:Hide()

local specCornerBtn = CreateFrame("Frame", nil, win)
specCornerBtn:SetSize(28, 28)
specCornerBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, -14)
specCornerBtn:EnableMouse(true)
specCornerBtn:SetScript("OnEnter", function(self)
    ShowSpecListTooltip(self, "ANCHOR_BOTTOMLEFT")
end)
specCornerBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- â”€â”€ Roll button â€” 2-click confirmation (EXTREMELY IMPORTANT) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Pre-built button label strings (atlas markup evaluated once at load time).
local ROLL_BTN_TEXT = CreateAtlasMarkup("lootroll-icon-need", 14, 14) .. " " .. L["BONUS_ROLL_CONFIRM_ROLL"]
local PASS_BTN_TEXT = CreateAtlasMarkup("lootroll-icon-pass", 14, 14) .. " " .. L["BONUS_ROLL_CONFIRM_PASS"]

-- Confirmation question above buttons
local winRollPrompt = win:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
winRollPrompt:SetText(L["BONUS_ROLL_CONFIRM_QUESTION"])
winRollPrompt:Hide()

-- Flat button with a coloured fill, black border and gold label.
local function CreateSkinnedButton(r, g, b)
    local btn = CreateFrame("Button", nil, win, "BackdropTemplate")
    btn:SetHeight(24)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    btn:SetBackdropColor(r, g, b, 1)
    btn:SetBackdropBorderColor(0, 0, 0, 1)
    btn:SetNormalFontObject("VCAFontNormal")
    btn:SetHighlightFontObject("VCAFontHighlight")
    local shine = btn:CreateTexture(nil, "ARTWORK")
    shine:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    shine:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    shine:SetHeight(1)
    shine:SetColorTexture(1, 1, 1, 0.28)
    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.14)
    btn:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(r * 0.7, g * 0.7, b * 0.7, 1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(r, g, b, 1)
    end)
    return btn
end

local function DoRoll()
    BRC.Hide()
    if not isPreview and BonusRollFrame and BonusRollFrame.PromptFrame and BonusRollFrame.PromptFrame.RollButton then
        BonusRollFrame.PromptFrame.RollButton:Click()
    end
end

local function DoPass()
    if isPreview then
        BRC.Uninject()
    elseif BonusRollFrame and BonusRollFrame.PromptFrame and BonusRollFrame.PromptFrame.PassButton then
        BonusRollFrame.PromptFrame.PassButton:Click()
    end
end

BRC.DoRoll = DoRoll
BRC.DoPass = DoPass

local rollBtn = CreateSkinnedButton(0.14, 0.42, 0.16)
rollBtn:SetText(ROLL_BTN_TEXT)
rollBtn:SetScript("OnClick", function()
    if IsConfirmEnabled() then
        local text = L["BONUS_ROLL_POPUP_ROLL"]
        if oneItemLeft then
            text = "|cffff6060" .. L["ONE_ITEM_WARN"] .. "|r\n\n" .. text
        end
        StaticPopup_Show("VOIDCORE_BONUS_ROLL", text)
    else
        DoRoll()
    end
end)

-- â”€â”€ Pass button â€” 2-click confirmation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local passBtn = CreateSkinnedButton(0.5, 0.09, 0.09)
passBtn:SetText(PASS_BTN_TEXT)
passBtn:SetScript("OnClick", function()
    if IsConfirmEnabled() then
        StaticPopup_Show("VOIDCORE_BONUS_PASS", L["BONUS_ROLL_POPUP_PASS"])
    else
        DoPass()
    end
end)

-- â”€â”€ Timer mirroring â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Refreshed 10 times per second: the bar and the seconds text do not need every frame.
local timerClock = 0
win:SetScript("OnUpdate", function(_, dt)
    timerClock = timerClock + (dt or 0)
    if timerClock < 0.1 then
        return
    end
    timerClock = 0
    if isPreview then
        if previewTimerStart then
            local elapsed = (GetTime() - previewTimerStart) % previewTimerDuration
            timerBar:SetMinMaxValues(0, previewTimerDuration)
            timerBar:SetValue(previewTimerDuration - elapsed)
            timerText:SetText(VCA.FormatTimer(previewTimerDuration - elapsed))
        end
        return
    end
    -- Timer is the StatusBar widget itself; .Bar is its fill Texture (no GetValue)
    if not (BonusRollFrame and BonusRollFrame.PromptFrame and BonusRollFrame.PromptFrame.Timer) then
        return
    end
    local src = BonusRollFrame.PromptFrame.Timer
    if not src.GetValue then
        return
    end
    local lo, hi = src:GetMinMaxValues()
    timerBar:SetMinMaxValues(lo, hi)
    timerBar:SetValue(src:GetValue())
    timerText:SetText(VCA.FormatTimer(src:GetValue()))
end)

-- Hides per-spec list separator, header and all row widgets.
local function HideSpecList()
    specListSep:Hide()
    specListHeader:Hide()
    specListHitFrame:Hide()
    for i = 1, 4 do
        specListRows[i].btn:Hide()
        specListRows[i].glow:Hide()
        specListRows[i].label:Hide()
        specListRows[i].count:Hide()
    end
end

-- Renders per-spec remaining-item icon buttons into the window on a single row.
-- Returns the updated dynY after the row.
local function ShowSpecList(source, dynY)
    if not (source and source.sourceType and source.sourceID) then
        HideSpecList()
        return dynY
    end
    local specs = VCA.SpecInfo.GetPlayerSpecs()
    if not (specs and #specs > 0) then
        HideSpecList()
        return dynY
    end

    specListHeader:Hide()
    specListHitFrame:Hide()

    specListSep:Hide()
    dynY = dynY - 12

    -- Chips in two columns: [icon] Name        N (W)
    local CHIP_W, CHIP_H, CHIP_GAP = 160, 24, 8
    local startX = 16

    local activeSpecID = VCA.SpecInfo.GetEffectiveLootSpecID()
    local selectedSet = VCA.Data.GetSelectedItems(source.sourceType, source.sourceID, source.difficultyID)

    for i, spec in ipairs(specs) do
        if i > 4 then
            break
        end
        local row = specListRows[i]

        local items = VCA.LootPool.GetCachedItemsForSpec(source.sourceType, source.sourceID, source.difficultyID,
            spec.classID, spec.specID)
        if not items then
            items = VCA.LootPool.GetItemsForSpec(source.sourceType, source.sourceID, source.difficultyID, spec.classID,
                spec.specID)
        end
        local poolSet = {}
        for _, itemID in ipairs(items or {}) do
            poolSet[itemID] = true
        end
        local remaining = 0
        for _, itemID in ipairs(items or {}) do
            if not VCA.Data.IsObtained(source.sourceType, source.sourceID, source.difficultyID, spec.specID, itemID) then
                remaining = remaining + 1
            end
        end
        local wanted = 0
        if selectedSet then
            for itemID in pairs(selectedSet) do
                if poolSet[itemID] then
                    wanted = wanted + 1
                end
            end
        end

        local col, rowIdx = (i - 1) % 2, math.floor((i - 1) / 2)
        row.btn:ClearAllPoints()
        row.btn:SetPoint("TOPLEFT", win, "TOPLEFT", startX + col * (CHIP_W + CHIP_GAP), dynY - rowIdx * (CHIP_H + 4))
        row.icon:SetTexture(spec.icon or 134400)
        row.glow:Hide()
        local a = RollPalette().accent
        local isActive = spec.specID == activeSpecID
        if isActive then
            row.edge:SetColorTexture(a[1], a[2], a[3], 1)
        else
            row.edge:SetColorTexture(0.2, 0.28, 0.24, 1)
        end

        local remColor = remaining > 0 and "|cffffffff" or "|cff666666"
        local wantedStr = wanted > 0 and (" |cffffff00(" .. wanted .. ")|r") or ""
        row.count:ClearAllPoints()
        row.count:SetPoint("RIGHT", row.btn, "RIGHT", -5, 0)
        row.count:SetText(remColor .. remaining .. "|r" .. wantedStr)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
        local specLabelName = select(2, GetSpecializationInfoByID(spec.specID)) or "?"
        row.label:SetText((isActive and "|cffffffff" or "|cffb9c7bf") .. specLabelName .. "|r")

        -- Capture loop locals for closures
        local capturedSpecID = spec.specID
        local capturedSpecName = select(2, GetSpecializationInfoByID(spec.specID)) or "?"
        row.btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(string.format(L["BRC_SWITCH_SPEC_TIP"], capturedSpecName))

            if cachedSource and cachedSource.sourceType and cachedSource.sourceID then
                local source = cachedSource
                local specItems = VCA.LootPool.GetItemsForSpec(source.sourceType, source.sourceID, source.difficultyID,
                    VCA.SpecInfo.GetPlayerClassID(), capturedSpecID)
                local specItemSet = {}
                for _, itemID in ipairs(specItems) do
                    specItemSet[itemID] = true
                end

                local selectedSet = VCA.Data.GetSelectedItems(source.sourceType, source.sourceID, source.difficultyID)
                local wantedItems = {}
                for itemID in pairs(selectedSet) do
                    if specItemSet[itemID] and
                        not VCA.Data
                            .IsObtainedForKeyTier(source.sourceType, source.sourceID, source.difficultyID,
                            capturedSpecID, itemID, nil) then
                        local itemName, _, _, _, _, _, _, _, equipLoc, itemTexture = C_Item.GetItemInfo(itemID)
                        if itemName then
                            wantedItems[#wantedItems + 1] = {
                                itemName = itemName,
                                itemTexture = itemTexture,
                                equipLoc = equipLoc,
                                sortKey = CHANCE_TIP_SLOT_ORDER[equipLoc] or 99
                            }
                        end
                    end
                end

                if #wantedItems > 0 then
                    table.sort(wantedItems, function(a, b)
                        if a.sortKey ~= b.sortKey then
                            return a.sortKey < b.sortKey
                        end
                        return (a.itemName or "") < (b.itemName or "")
                    end)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L["BONUS_ROLL_WANTED_TOOLTIP_TITLE"], 0.85, 0.3, 1)
                    for _, item in ipairs(wantedItems) do
                        local iconMarkup = item.itemTexture and
                                               ("|T" .. item.itemTexture .. ":14:14:0:0:64:64:4:60:4:60|t ") or "  "
                        local nameColored = "|cnIQ4:" .. item.itemName .. "|r"
                        local slotText = (item.equipLoc and _G[item.equipLoc] and _G[item.equipLoc] ~= "") and
                                             (" |cff888888[" .. _G[item.equipLoc] .. "]|r") or ""
                        GameTooltip:AddLine("  " .. iconMarkup .. nameColored .. slotText)
                    end
                end
            end

            GameTooltip:Show()
        end)
        row.btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row.btn:SetScript("OnClick", function()
            -- Only another spec changes anything: the active one is already your loot spec.
            if capturedSpecID == VCA.SpecInfo.GetEffectiveLootSpecID() then
                return
            end
            isSpecChangePending = true
            SetLootSpecialization(capturedSpecID)
        end)

        row.btn:Show()
        row.label:Show()
        row.count:Show()
    end

    -- Hide unused slots
    for i = (#specs + 1), 4 do
        specListRows[i].btn:Hide()
        specListRows[i].label:Hide()
        specListRows[i].count:Hide()
    end

    local chipRows = math.ceil(math.min(#specs, 4) / 2)
    dynY = dynY - chipRows * (CHIP_H + 4) -- chips and the gap below them
    return dynY
end

-- Lays out, from y downwards: the odds panel, the per-spec chips, the timer and the
-- one-item warning. Returns the y below the last of them. `source` must carry
-- { sourceType, sourceID, difficultyID } or be nil.
-- Where the section below the header starts.  The header is the icon (40) or, when the item name
-- takes two lines, the name plus the cost line, so nothing ever overlaps.
local function HeaderBottomY()
    local nameH = winItemName:GetStringHeight() or 14
    local subH = winItemSub:GetStringHeight() or 0
    local infoH = winVoidcoreInfo:GetStringHeight() or 14
    return -(14 + math.max(40, 2 + nameH + 1 + subH + 3 + infoH) + 12)
end

local function LayoutDynamicSection(source, specID, y)
    topSep:Hide()
    specName:Hide()
    specName:SetText("")
    chanceHitFrame:Hide()
    lootSep:Hide()
    lootLine:Hide()
    lootCountLine:Hide()
    chanceText:Hide()
    warnHeader:Hide()
    warnBody:Hide()
    oddsPct:SetText("")
    oddsCaption:SetText("")
    oddsMessage:SetText("")
    chosenText:SetText("")
    for i = 1, 5 do
        chosenIcons[i]:Hide()
    end
    oneItemLeft = false

    local hasSource = source and source.sourceType and source.sourceID
    local accent = RollPalette().accent

    if hasSource then
        local selectedSet = VCA.Data.GetSelectedItems(source.sourceType, source.sourceID, source.difficultyID)
        local hasSelection = selectedSet and next(selectedSet)
        local probFull = VCA.Probability.CalculateForSpec(source.sourceType, source.sourceID, source.difficultyID,
            VCA.SpecInfo.GetPlayerClassID(), specID, nil)

        local panelH = 36
        local message
        if not hasSelection then
            message = "|cff888888" .. L["BONUS_ROLL_CONFIRM_NO_SELECTED"] .. "|r"
        else
            local prob = VCA.Probability.CalculateForSpec(source.sourceType, source.sourceID, source.difficultyID,
                VCA.SpecInfo.GetPlayerClassID(), specID, nil, selectedSet)
            if prob.noItems then
                message = "|cff888888" .. L["BONUS_ROLL_CONFIRM_NO_ITEMS"] .. "|r"
            elseif prob.allObtained then
                message = "|cff00ff00" .. L["BONUS_ROLL_CONFIRM_ALL_OBTAINED"] .. "|r"
            else
                panelH = 62
                local pct = math.floor((prob.remainingOdds or 0) * 100 + 0.5)
                oddsPct:SetText(string.format("|cff%02x%02x%02x%d%%|r", accent[1] * 255, accent[2] * 255,
                    accent[3] * 255, pct))
                oddsCaption:SetText("|cff93a79a" .. L["BRC_ODDS_CAPTION"] .. "|r")
                -- The chosen items this spec can still give
                local specSet = {}
                for _, itemID in ipairs(VCA.LootPool.GetItemsForSpec(source.sourceType, source.sourceID,
                    source.difficultyID, VCA.SpecInfo.GetPlayerClassID(), specID)) do
                    specSet[itemID] = true
                end
                local wantedIDs = {}
                for itemID in pairs(selectedSet) do
                    if specSet[itemID] and
                        not VCA.Data.IsObtainedForKeyTier(source.sourceType, source.sourceID, source.difficultyID,
                            specID, itemID, nil) then
                        wantedIDs[#wantedIDs + 1] = itemID
                    end
                end
                table.sort(wantedIDs)
                for i = 1, math.min(5, #wantedIDs) do
                    chosenIcons[i]:SetTexture(C_Item.GetItemIconByID(wantedIDs[i]) or 134400)
                    chosenIcons[i]:Show()
                end
                chosenText:SetText("|cff93a79a" .. string.format(L["BRC_CHOSEN_COUNT"], #wantedIDs) .. "|r")
                chanceHitFrame:Show()
            end
        end
        oddsMessage:SetText(message or "")
        oddsPanel:ClearAllPoints()
        oddsPanel:SetPoint("TOPLEFT", win, "TOPLEFT", 16, y)
        oddsPanel:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, y)
        oddsPanel:SetHeight(panelH)
        oddsPanel:Show()
        y = y - panelH - 2

        -- Per-spec chips (clicking one switches your loot specialization)
        if IsSpecListEnabled() then
            y = ShowSpecList(source, y)
        else
            HideSpecList()
        end

        if probFull and probFull.remainingCount == 1 then
            oneItemLeft = true
        end
    else
        oddsPanel:Hide()
        HideSpecList()
    end

    -- Timer bar
    y = y - 8
    timerBar:ClearAllPoints()
    timerBar:SetPoint("TOPLEFT", win, "TOPLEFT", 16, y)
    timerBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -16, y)
    y = y - 14

    -- One-item warning, just above the buttons
    if oneItemLeft then
        if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
            PlaySound(SOUNDKIT.RAID_WARNING)
        end
        y = y - 10
        warnHeader:ClearAllPoints()
        warnHeader:SetPoint("TOP", win, "TOP", 0, y)
        warnHeader:SetText(L["BONUS_ROLL_CONFIRM_WARNING_HEADER"])
        warnHeader:Show()
        y = y - 20
        warnBody:ClearAllPoints()
        warnBody:SetPoint("TOP", win, "TOP", 0, y)
        warnBody:SetText("|cffff6060" .. L["ONE_ITEM_WARN"] .. "|r")
        warnBody:Show()
        y = y - 18 - 4
    end
    return y
end

-- â”€â”€ BRC.Show â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function BRC.Show()
    if not (BonusRollFrame and BonusRollFrame.PromptFrame) then
        return
    end

    local pf = BonusRollFrame.PromptFrame

    cachedDisplayItemID = nil
    cachedItemLink = nil
    local ejBtn = pf.EncounterJournalLinkButton
    -- If SPELL_CONFIRMATION_PROMPT fired before this addon loaded (e.g. after /reload),
    -- pull the active prompt data directly.
    if not cachedPromptData then
        local prompts = GetSpellConfirmationPromptsInfo()
        if prompts then
            for _, entry in pairs(prompts) do
                if entry.currencyID == VCA.VOIDCORE_CURRENCY_ID then
                    cachedPromptData = entry
                    break
                end
            end
        end
    end
    -- SPELL_CONFIRMATION_PROMPT provides displayItemID authoritatively; EJ button is fallback.
    cachedDisplayItemID = (cachedPromptData and cachedPromptData.displayItemID) or (ejBtn and ejBtn.displayItemID)
    if cachedDisplayItemID then
        cachedItemLink = select(2, C_Item.GetItemInfo(cachedDisplayItemID))
    end

    local iName, _, iQuality, _, _, _, _, _, _, iTexture = C_Item.GetItemInfo(cachedDisplayItemID or 0)
    -- If GetItemInfo hasn't cached the item yet (common for delve voidcaches), fall back to
    -- the texture Blizzard already placed on the EncounterJournalLinkButton's NormalTexture.
    if not iTexture and ejBtn then
        local t = ejBtn:GetNormalTexture()
        iTexture = t and t:GetTexture()
    end
    if iTexture then
        winItemIcon:SetTexture(iTexture)
        winItemIcon:Show()
    else
        winItemIcon:Hide()
    end
    if iName then
        local _, _, _, hex = C_Item.GetItemQualityColor(iQuality or 1)
        SetItemTitle(hex, iName)
    elseif pf.Name and pf.Name:GetText() and pf.Name:GetText() ~= "" then
        local bName = pf.Name:GetText()
        SetItemTitle("ffffffff", bName)
    else
        SetItemTitle("ff888888", L["BONUS_ROLL_TITLE"])
    end

    local specID = VCA.SpecInfo.GetEffectiveLootSpecID()
    local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
    cachedSpecIcon = sIcon or 134400
    cachedSpecName = sName or "?"
    cachedSpecID = specID
    specCornerIcon:SetTexture(cachedSpecIcon)
    specCornerIcon:Show()

    rollBtn:SetText(ROLL_BTN_TEXT)
    passBtn:SetText(PASS_BTN_TEXT)

    -- Dynamic loot odds section

    -- Prefer the authoritative source from SPELL_CONFIRMATION_PROMPT; fall back to the
    -- reverse-lookup + live GetInstanceInfo() approach when unavailable (e.g. preview).
    local source = (cachedPromptData and ResolveSourceFromPromptData(cachedPromptData)) or
                       GetSourceFromDisplayItemID(cachedDisplayItemID)
    if source and not source.difficultyID then
        -- Fallback path: GetSourceFromDisplayItemID does not set difficultyID.
        if source.sourceType == VCA.ContentType.MYTHIC_PLUS then
            source.difficultyID = VCA.MythicPlusEJDifficulty
        else
            local _, _, diffID = GetInstanceInfo()
            source.difficultyID = (VCA.EligibleRaidDifficulties[diffID] and diffID) or VCA.Difficulty.RAID_NORMAL
        end
    end
    cachedSource = source
    ApplySourceSub(source)

    -- Voidcore count + cost
    local currInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(VCA.VOIDCORE_CURRENCY_ID)
    local owned = currInfo and currInfo.quantity or 0
    local cost = (cachedPromptData and cachedPromptData.currencyCost) or
                     ((source and source.sourceType == VCA.ContentType.RAID) and VCA.VoidcoreCost.RAID or
                         VCA.VoidcoreCost.MYTHIC_PLUS)
    winVoidcoreInfo:SetText(string.format(L["BONUS_ROLL_CONFIRM_COST"], cost, owned))

    local dynY = LayoutDynamicSection(source, specID, HeaderBottomY())
    local btnW, btnH = 140, 28
    local winH = math.abs(dynY) + 8 + btnH + 16
    win:SetSize(360, winH)

    rollBtn:SetSize(btnW, btnH)
    passBtn:SetSize(btnW, btnH)
    rollBtn:ClearAllPoints()
    passBtn:ClearAllPoints()
    rollBtn:SetPoint("BOTTOM", win, "BOTTOM", -(btnW / 2 + 4), 12)
    passBtn:SetPoint("BOTTOM", win, "BOTTOM", (btnW / 2 + 4), 12)

    win:ClearAllPoints()
    win:SetPoint("CENTER", BonusRollFrame, "CENTER", 0, 0)
    win:SetFrameStrata(BonusRollFrame:GetFrameStrata())
    win:SetFrameLevel(BonusRollFrame:GetFrameLevel() + 10)
    BonusRollFrame:SetAlpha(0)
    local pf = BonusRollFrame.PromptFrame
    if pf then
        if pf.RollButton then
            pf.RollButton:EnableMouse(false)
            pf.RollButton:EnableMouseMotion(false)
        end
        if pf.PassButton then
            pf.PassButton:EnableMouse(false)
            pf.PassButton:EnableMouseMotion(false)
        end
        if pf.EncounterJournalLinkButton then
            pf.EncounterJournalLinkButton:EnableMouse(false)
            pf.EncounterJournalLinkButton:EnableMouseMotion(false)
        end
    end
    if BonusRollFrame.CurrentCountFrame then
        BonusRollFrame.CurrentCountFrame:EnableMouse(false)
        BonusRollFrame.CurrentCountFrame:EnableMouseMotion(false)
    end
    isPreview = false
    win:Show()
end

-- â”€â”€ BRC.Hide / Uninject â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function BRC.Uninject()
    if isSpecChangePending then
        return
    end
    if BonusRollFrame then
        BonusRollFrame:SetAlpha(1)
        local pf = BonusRollFrame.PromptFrame
        if pf then
            if pf.RollButton then
                pf.RollButton:EnableMouse(true)
                pf.RollButton:EnableMouseMotion(true)
            end
            if pf.PassButton then
                pf.PassButton:EnableMouse(true)
                pf.PassButton:EnableMouseMotion(true)
            end
            if pf.EncounterJournalLinkButton then
                pf.EncounterJournalLinkButton:EnableMouse(true)
                pf.EncounterJournalLinkButton:EnableMouseMotion(true)
            end
        end
        if BonusRollFrame.CurrentCountFrame then
            BonusRollFrame.CurrentCountFrame:EnableMouse(true)
            BonusRollFrame.CurrentCountFrame:EnableMouseMotion(true)
        end
    end
    win:Hide()
    StaticPopup_Hide("VOIDCORE_BONUS_ROLL")
    StaticPopup_Hide("VOIDCORE_BONUS_PASS")
    cachedItemLink = nil
    cachedDisplayItemID = nil
    cachedSpecIcon = nil
    cachedSpecName = nil
    cachedSpecID = nil
    cachedSource = nil
    cachedPromptData = nil
    previewTimerStart = nil
end

-- ── Confirmation popups ──────────────────────────────────────────────────────────────────

StaticPopupDialogs["VOIDCORE_BONUS_ROLL"] = {
    text = "%s",
    button1 = L["BONUS_ROLL_CONFIRM_ROLL"],
    button2 = CANCEL,
    OnAccept = function()
        BRC.DoRoll()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3
}

StaticPopupDialogs["VOIDCORE_BONUS_PASS"] = {
    text = "%s",
    button1 = L["BONUS_ROLL_CONFIRM_PASS"],
    button2 = CANCEL,
    OnAccept = function()
        BRC.DoPass()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3
}

BRC.Hide = BRC.Uninject

-- Skyreach +10 Voidcache as a realistic preview stand-in (M+ keystone context).
local PREVIEW_PROMPT_DATA = {
    confirmType = 1,
    currencyCost = 1,
    currencyID = 3418,
    difficultyID = 8,
    displayItemID = 279618,
    duration = 174,
    itemContext = 16,
    spellID = 259072,
    text = "",
    treasureContextLevel = 10
}

function BRC.ShowPreview()
    isPreview = true
    previewTimerStart = GetTime()
    cachedPromptData = PREVIEW_PROMPT_DATA
    cachedDisplayItemID = cachedPromptData.displayItemID
    cachedItemLink = nil

    local iName, _, iQuality, _, _, _, _, _, _, iTexture = C_Item.GetItemInfo(cachedDisplayItemID)
    if iTexture then
        winItemIcon:SetTexture(iTexture)
        winItemIcon:Show()
    else
        winItemIcon:Hide()
    end
    local iHex = iQuality and select(4, C_Item.GetItemQualityColor(iQuality)) or "ffa335ee"
    SetItemTitle(iHex, iName or L["BONUS_ROLL_TITLE"])

    local specID = VCA.SpecInfo.GetEffectiveLootSpecID()
    local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
    cachedSpecIcon = sIcon or 134400
    cachedSpecName = sName or "?"
    cachedSpecID = specID
    specCornerIcon:SetTexture(cachedSpecIcon)
    specCornerIcon:Show()

    rollBtn:SetText(ROLL_BTN_TEXT)
    passBtn:SetText(PASS_BTN_TEXT)

    local currInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(VCA.VOIDCORE_CURRENCY_ID)
    local owned = currInfo and currInfo.quantity or 0

    local source = ResolveSourceFromPromptData(cachedPromptData)
    if not source then
        -- Fallback if Skyreach is not in the current season pool.
        source = GetSourceFromDisplayItemID(cachedDisplayItemID)
        if source then
            source.difficultyID = VCA.MythicPlusEJDifficulty
        end
    end
    cachedSource = source
    ApplySourceSub(source)

    local cost = (cachedPromptData and cachedPromptData.currencyCost) or
                     ((source and source.sourceType == VCA.ContentType.RAID) and VCA.VoidcoreCost.RAID or
                         VCA.VoidcoreCost.MYTHIC_PLUS)
    winVoidcoreInfo:SetText(string.format(L["BONUS_ROLL_CONFIRM_COST"], cost, owned))

    local dynY = LayoutDynamicSection(source, specID, HeaderBottomY())
    local btnW, btnH = 140, 28
    local winH = math.abs(dynY) + 8 + btnH + 16
    win:SetSize(360, winH)

    rollBtn:SetSize(btnW, btnH)
    passBtn:SetSize(btnW, btnH)
    rollBtn:ClearAllPoints()
    passBtn:ClearAllPoints()
    rollBtn:SetPoint("BOTTOM", win, "BOTTOM", -(btnW / 2 + 4), 12)
    passBtn:SetPoint("BOTTOM", win, "BOTTOM", (btnW / 2 + 4), 12)

    win:ClearAllPoints()
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    win:Show()
end

-- â”€â”€ One-time hooks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local hooksDone = false
local function SetupHooks()
    if hooksDone or not BonusRollFrame then
        return
    end
    BonusRollFrame:HookScript("OnShow", function()
        if IsEnabled() then
            BRC.Show()
        end
    end)
    BonusRollFrame:HookScript("OnHide", BRC.Uninject)
    hooksDone = true
end

-- â”€â”€ Events â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
eventFrame:RegisterEvent("BONUS_ROLL_STARTED")
eventFrame:RegisterEvent("BONUS_ROLL_ACTIVATE")
eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        SetupHooks()
    elseif event == "ADDON_LOADED" then
        if (...) == "Blizzard_UIPanels_Game" then
            SetupHooks()
        end
    elseif event == "SPELL_CONFIRMATION_PROMPT" then
        local spellID = ...
        local prompts = GetSpellConfirmationPromptsInfo()
        if prompts then
            for _, entry in pairs(prompts) do
                if entry.spellID == spellID and entry.currencyID == VCA.VOIDCORE_CURRENCY_ID then
                    cachedPromptData = entry
                    break
                end
            end
        end
    elseif event == "BONUS_ROLL_STARTED" then
        if IsEnabled() then
            SetupHooks()
            BRC.Show()
        end
    elseif event == "PLAYER_LOOT_SPEC_UPDATED" then
        if win:IsShown() then
            if isPreview then
                BRC.ShowPreview()
            else
                BRC.Show()
            end
            -- Bust the tooltip cache by requesting a different voidcache item
            -- through C_TooltipInfo.  WoW returns stale spec data when the same
            -- item ID is read on two consecutive tooltip calls; reading a
            -- different ID in between forces a fresh fetch for our item the next
            -- time the user hovers the icon (mirrors VoidcacheScan's alternating
            -- item-ID strategy documented in its header comment).
            if C_TooltipInfo and C_TooltipInfo.GetItemByID then
                local bustID = nil
                for _, id in pairs(VCA.DungeonVoidcacheIDs or {}) do
                    if id ~= cachedDisplayItemID then
                        bustID = id
                        break
                    end
                end
                if not bustID then
                    for _, id in pairs(VCA.RaidEncounterCacheIDs or {}) do
                        if id ~= cachedDisplayItemID then
                            bustID = id
                            break
                        end
                    end
                end
                if bustID then
                    C_TooltipInfo.GetItemByID(bustID)
                end
            end
            -- If the tooltip is already open over the icon, re-request the real
            -- item now that the cache has been busted.
            if GameTooltip:IsShown() and GameTooltip:GetOwner() == winIconBtn then
                local link = cachedItemLink or (cachedDisplayItemID and ("item:" .. cachedDisplayItemID))
                if link then
                    GameTooltip:SetHyperlink(link)
                end
            end
        end
        -- Defer clearing the flag so any BonusRollFrame:OnHide that Blizzard fires
        -- as part of its own PLAYER_LOOT_SPEC_UPDATED handling is still suppressed.
        C_Timer.After(0, function()
            isSpecChangePending = false
        end)
    elseif event == "BONUS_ROLL_ACTIVATE" or event == "BONUS_ROLL_RESULT" then
        BRC.Uninject()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- If our window is open and the icon is still hidden, try again now the
        -- item data has arrived from the server.
        local itemID = ...
        if win:IsShown() and itemID == cachedDisplayItemID and not winItemIcon:IsShown() then
            local _, _, iQuality, _, _, _, _, _, _, iTexture = C_Item.GetItemInfo(itemID)
            if iTexture then
                winItemIcon:SetTexture(iTexture)
                winItemIcon:Show()
                if not iQuality then
                    return
                end
                local _, _, _, hex = C_Item.GetItemQualityColor(iQuality)
                if hex then
                    local iName = C_Item.GetItemInfo(itemID)
                    if iName then
                        SetItemTitle(hex, iName)
                    end
                end
            end
        end
    end
end)
