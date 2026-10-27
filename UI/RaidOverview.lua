-- VoidcoreAdvisor: RaidOverview
-- Shown when the Encounter Journal is on a raid instance overview page
-- (raid selected, no boss selected). Displays bosses in Encounter Journal order.
local _, VCA = ...
local L = VCA.L

VCA.RaidOverview = {}
local Overview = VCA.RaidOverview

local function GetDifficultyName(diffID)
    if diffID == VCA.Difficulty.RAID_NORMAL then
        return L["DIFFICULTY_NORMAL"] or "Normal"
    elseif diffID == VCA.Difficulty.RAID_HEROIC then
        return L["DIFFICULTY_HEROIC"] or "Heroic"
    elseif diffID == VCA.Difficulty.RAID_MYTHIC then
        return L["DIFFICULTY_MYTHIC"] or "Mythic"
    end
    return "Unknown"
end

local PANEL_WIDTH = 480
local HEADER_H = 56
local COL_HEADER_H = 20
local PADDING = 12
local ROW_H = 26
local ICON_SIZE = 20

local COL_BOSS_X = 0
local COL_BOSS_W = 200
local COL_SPEC_ICON_X = 204
local COL_SPEC_NAME_X = 228
local COL_SPEC_NAME_W = 100
local COL_LOOTED_R = -(64 + 4)
local COL_LOOTED_W = 53
local COL_PCT_R = 0
local COL_PCT_W = 64

local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
Overview.frame = frame

frame:SetWidth(PANEL_WIDTH)
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

function Overview.AnchorToEJ()
    local ej = EncounterJournal
    if not ej then
        return
    end
    if VCA.Panel.ApplyFreePlacement(frame, true) then
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", ej, "TOPRIGHT", 52, 0)
    frame:SetPoint("BOTTOMLEFT", ej, "BOTTOMRIGHT", 52, 0)
end

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
VCA.Panel.MakeDraggable(frame, 150)

local subtitleText = frame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
subtitleText:SetPoint("TOPLEFT", 18, -40)
subtitleText:SetText("|cff888888" .. L["RAID_OVERVIEW_SUBTITLE"] .. "|r")

local raidScanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
raidScanBtn:SetSize(110, 22)
raidScanBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -38, -30)
raidScanBtn:SetText(L["SCAN_BTN"])

local function UpdateRaidScanButton()
    if VCA.VoidcacheScan.IsRaidRunning() then
        raidScanBtn:Disable()
        return
    end
    local canScan = VCA.VoidcacheScan.CanScan()
    raidScanBtn:SetText(L["SCAN_BTN"])
    if canScan then
        raidScanBtn:Enable()
    else
        raidScanBtn:Disable()
    end
end

raidScanBtn:SetScript("OnClick", function()
    local canScan, reason = VCA.VoidcacheScan.CanScan()
    if not canScan then
        if reason == "COMBAT" then
            DEFAULT_CHAT_FRAME:AddMessage(L["SCAN_UNAVAILABLE_COMBAT"])
        elseif reason == "INSTANCE" then
            DEFAULT_CHAT_FRAME:AddMessage(L["SCAN_UNAVAILABLE_INSTANCE"])
        end
        return
    end
    local diffID = Overview.difficultyID or VCA.Difficulty.RAID_MYTHIC
    local diffName = GetDifficultyName(diffID)
    local bodyText = string.format(L["RAID_SCAN_CONFIRM_BODY"], diffName, diffName)
    StaticPopupDialogs["VOIDCORE_RAID_SCAN_CONFIRM"].text =
        L["RAID_SCAN_CONFIRM_TITLE"] .. "\n\n|cffaaaaaa" .. bodyText .. "|r"
    StaticPopup_Show("VOIDCORE_RAID_SCAN_CONFIRM")
end)

StaticPopupDialogs["VOIDCORE_RAID_SCAN_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        VCA.VoidcacheScan.StartRaid(Overview.difficultyID)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3
}

VCA.VoidcacheScan.SetRaidProgressCallback(function(specIdx, specCount, _, _, status)
    if status == "COMPLETE" then
        raidScanBtn:SetText(L["SCAN_COMPLETE"])
        raidScanBtn:Disable()
        C_Timer.After(3, UpdateRaidScanButton)
    elseif status == "ABORTED" or status == "COMBAT" then
        raidScanBtn:SetText(L["SCAN_ABORTED"])
        raidScanBtn:Disable()
        C_Timer.After(3, UpdateRaidScanButton)
    elseif specIdx then
        raidScanBtn:SetText(string.format(L["SCAN_PROGRESS"], specIdx, specCount))
        raidScanBtn:Disable()
    end
end)

local raidScanBtnStateFrame = CreateFrame("Frame")
raidScanBtnStateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
raidScanBtnStateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
raidScanBtnStateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
raidScanBtnStateFrame:SetScript("OnEvent", UpdateRaidScanButton)

local loadingText = frame:CreateFontString(nil, "OVERLAY", "VCAFontHighlightSmall")
loadingText:SetPoint("TOPRIGHT", -26, -40)
loadingText:SetJustifyH("RIGHT")
loadingText:Hide()

local loadingAnimFrame = CreateFrame("Frame")
local loadingBaseText = ""
local loadingDots = 0
local loadingElapsed = 0

local function UpdateLoadingText()
    local dots = string.rep(".", loadingDots)
    loadingText:SetText("|cffffff00" .. loadingBaseText .. dots .. "|r")
end

local function SetLoadingState(isLoading, pausedByEJ)
    if not isLoading then
        loadingAnimFrame:SetScript("OnUpdate", nil)
        loadingText:Hide()
        loadingBaseText = ""
        loadingDots = 0
        loadingElapsed = 0
        return
    end

    if pausedByEJ then
        loadingBaseText = L["RAID_OVERVIEW_LOADING_PAUSED"]
    else
        loadingBaseText = L["RAID_OVERVIEW_LOADING"]
    end

    if not loadingText:IsShown() then
        loadingText:Show()
    end
    UpdateLoadingText()

    loadingAnimFrame:SetScript("OnUpdate", function(_, elapsed)
        loadingElapsed = loadingElapsed + elapsed
        if loadingElapsed < 0.45 then
            return
        end
        loadingElapsed = 0
        loadingDots = (loadingDots + 1) % 4
        UpdateLoadingText()
    end)
end

local divider = frame:CreateTexture(nil, "ARTWORK")
VCA.OnTheme(function() local t = VCA.Theme.border; divider:SetColorTexture(t[1], t[2], t[3], 0.4) end)
divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -HEADER_H)
divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -HEADER_H)
divider:SetHeight(1)

local contentArea = CreateFrame("Frame", nil, frame)
contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(HEADER_H + 1))
contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 11)

-- Link to the list of all your characters (same as /void chars).
local charsBtn = CreateFrame("Button", nil, frame)
charsBtn:SetSize(150, 16)
charsBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
charsBtn:SetNormalFontObject("VCAFontNormalSmall")
charsBtn:SetHighlightFontObject("VCAFontHighlightSmall")
charsBtn:SetText(L["OVERVIEW_CHARACTERS"])
charsBtn:GetFontString():SetJustifyH("RIGHT")
charsBtn:SetScript("OnClick", function()
    VCA.Planner.SaveCharacterSummary()
    VCA.Tools.Chars()
end)

local hdrBoss = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
hdrBoss:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING + COL_BOSS_X, -6)
VCA.OnTheme(function() hdrBoss:SetText(VCA.Theme.hdr .. "" .. L["RAID_OVERVIEW_COL_BOSS"] .. "|r") end)

local hdrSpec = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
hdrSpec:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING + COL_SPEC_NAME_X, -6)
VCA.OnTheme(function() hdrSpec:SetText(VCA.Theme.hdr .. "" .. L["DUNGEON_OVERVIEW_COL_SPEC"] .. "|r") end)

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

local colHeaderRule = contentArea:CreateTexture(nil, "ARTWORK")
colHeaderRule:SetColorTexture(0.4, 0.4, 0.4, 0.3)
colHeaderRule:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, -(COL_HEADER_H + 2))
colHeaderRule:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -PADDING, -(COL_HEADER_H + 2))
colHeaderRule:SetHeight(1)

local rows = {}

local function GetOrCreateRow(parent)
    for _, row in ipairs(rows) do
        if not row.frame:IsShown() then
            return row
        end
    end

    local rowFrame = CreateFrame("Frame", nil, parent)
    rowFrame:SetHeight(ROW_H)

    local bossLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    bossLabel:SetJustifyH("LEFT")
    bossLabel:SetPoint("LEFT", rowFrame, "LEFT", COL_BOSS_X, 0)
    bossLabel:SetWidth(COL_BOSS_W)
    bossLabel:SetWordWrap(false)

    local specIcon = rowFrame:CreateTexture(nil, "ARTWORK")
    specIcon:SetSize(ICON_SIZE, ICON_SIZE)
    specIcon:SetPoint("LEFT", rowFrame, "LEFT", COL_SPEC_ICON_X, 0)
    specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local specLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    specLabel:SetJustifyH("LEFT")
    specLabel:SetPoint("LEFT", rowFrame, "LEFT", COL_SPEC_NAME_X, 0)
    specLabel:SetWidth(COL_SPEC_NAME_W)
    specLabel:SetWordWrap(false)

    local lootedLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    lootedLabel:SetJustifyH("RIGHT")
    lootedLabel:SetWidth(COL_LOOTED_W)
    lootedLabel:SetWordWrap(false)
    lootedLabel:SetPoint("RIGHT", rowFrame, "RIGHT", COL_LOOTED_R, 0)

    local pctLabel = rowFrame:CreateFontString(nil, "OVERLAY", "VCAFontNormal")
    pctLabel:SetJustifyH("RIGHT")
    pctLabel:SetWidth(COL_PCT_W)
    pctLabel:SetWordWrap(false)
    pctLabel:SetPoint("RIGHT", rowFrame, "RIGHT", COL_PCT_R, 0)

    local hoverHighlight = rowFrame:CreateTexture(nil, "HIGHLIGHT")
    hoverHighlight:SetAllPoints(rowFrame)
    hoverHighlight:SetColorTexture(VCA.Theme.accent[1], VCA.Theme.accent[2], VCA.Theme.accent[3], 0.12)

    -- Thin progress bar along the bottom of the row: items obtained / items wanted.
    local barTrack = rowFrame:CreateTexture(nil, "BORDER")
    barTrack:SetHeight(3)
    barTrack:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 4, 1)
    barTrack:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", -4, 1)
    barTrack:SetColorTexture(1, 1, 1, 0.08)
    local barFill = rowFrame:CreateTexture(nil, "ARTWORK")
    barFill:SetHeight(3)
    barFill:SetPoint("BOTTOMLEFT", rowFrame, "BOTTOMLEFT", 4, 1)
    barFill:Hide()

    local row = {
        barTrack = barTrack,
        barFill = barFill,
        frame = rowFrame,
        bossLabel = bossLabel,
        specIcon = specIcon,
        specLabel = specLabel,
        lootedLabel = lootedLabel,
        pctLabel = pctLabel
    }
    rows[#rows + 1] = row
    return row
end

-- Shown instead of a table full of dashes while no boss has chosen items yet.
local emptyHint = contentArea:CreateFontString(nil, "OVERLAY", "VCAFontHighlight")
emptyHint:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING + 10, -40)
emptyHint:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -PADDING - 10, -40)
emptyHint:SetJustifyH("CENTER")
emptyHint:SetSpacing(4)
emptyHint:SetText("|cffbbbbbb" .. L["RAID_OVERVIEW_EMPTY_HINT"] .. "|r")
emptyHint:Hide()

local function ShowTable(show)
    for _, w in ipairs({hdrBoss, hdrSpec, hdrLooted, hdrChance, colHeaderRule}) do
        w:SetShown(show)
    end
    emptyHint:SetShown(not show)
end

local function HideAllRows()
    for _, row in ipairs(rows) do
        row.frame:Hide()
    end
end

local scrollChild = CreateFrame("Frame", nil, contentArea)
local scrollFrame = CreateFrame("ScrollFrame", nil, contentArea)
scrollFrame:SetScrollChild(scrollChild)

scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetVerticalScroll()
    local maxScroll = math.max(0, scrollChild:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * ROW_H * 3)))
end)

local function RankCurrentPlayerSpecsForItemsCached(itemIDs, sourceType, sourceID, difficultyID)
    local specs = VCA.SpecInfo.GetPlayerSpecs()
    local selectedSet = {}
    for _, id in ipairs(itemIDs) do
        selectedSet[id] = true
    end

    local results = {}
    for _, spec in ipairs(specs) do
        local allSpecItemIDs = VCA.LootPool.GetCachedItemsForSpec(sourceType, sourceID, difficultyID, spec.classID,
            spec.specID)
        if not allSpecItemIDs then
            allSpecItemIDs = VCA.LootPool.GetItemsForSpec(sourceType, sourceID, difficultyID, spec.classID, spec.specID)
        end
        if not allSpecItemIDs then
            return nil
        end

        local matchCount = 0
        local remainingCount = 0
        local matchRemainingCount = 0
        for _, itemID in ipairs(allSpecItemIDs) do
            if selectedSet[itemID] then
                matchCount = matchCount + 1
            end
            if not VCA.Data.IsObtained(sourceType, sourceID, difficultyID, spec.specID, itemID) then
                remainingCount = remainingCount + 1
                if selectedSet[itemID] then
                    matchRemainingCount = matchRemainingCount + 1
                end
            end
        end

        local baseCount = #allSpecItemIDs
        local selectedCount = #itemIDs
        results[#results + 1] = {
            specID = spec.specID,
            specName = spec.name,
            specIcon = spec.icon,
            specRole = spec.role,
            specIndex = spec.specIndex,
            baseCount = baseCount,
            remainingCount = remainingCount,
            matchCount = matchCount,
            matchRemainingCount = matchRemainingCount,
            selectedOdds = remainingCount > 0 and (matchRemainingCount / remainingCount) or 0,
            allObtained = baseCount > 0 and remainingCount == 0,
            noItems = false -- set below by MarkCoverage
        }
    end
    VCA.Probability.MarkCoverage(results, #itemIDs)

    table.sort(results, function(a, b)
        if a.noItems ~= b.noItems then
            return not a.noItems
        end
        if a.allObtained ~= b.allObtained then
            return not a.allObtained
        end
        if a.remainingCount ~= b.remainingCount then
            return a.remainingCount < b.remainingCount
        end
        if a.baseCount ~= b.baseCount then
            return a.baseCount < b.baseCount
        end
        return a.specID < b.specID
    end)

    for i, r in ipairs(results) do
        r.rank = i
    end
    return results
end

local function Populate()
    HideAllRows()
    ShowTable(true)

    local contentW = frame:GetWidth() - PADDING * 2
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, -(COL_HEADER_H + 8))
    -- leave room for the "select by slot" section (UI/RaidSlots.lua) and the characters link
    scrollFrame:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -PADDING, 40 + (Overview.SLOT_SECTION_H or 0))
    scrollChild:SetWidth(contentW)

    local instanceID = Overview.instanceID
    local difficultyID = Overview.difficultyID or (EJ_GetDifficulty() or VCA.Difficulty.RAID_NORMAL)
    if not instanceID or instanceID == 0 then
        SetLoadingState(false, false)
        scrollChild:SetHeight(1)
        return
    end

    local entries = {}
    local selectedBossCount = 0
    local cacheReadyBossCount = 0
    local idx = 1
    while true do
        local bossName, _, encounterID = EJ_GetEncounterInfoByIndex(idx)
        if not bossName then
            break
        end
        local selectedSet = VCA.Data.GetSelectedItems(VCA.ContentType.RAID, encounterID, difficultyID)
        local selectedList = {}
        for itemID in pairs(selectedSet) do
            selectedList[#selectedList + 1] = itemID
        end

        local hasSelected = #selectedList > 0
        if hasSelected then
            selectedBossCount = selectedBossCount + 1
            local rankings = RankCurrentPlayerSpecsForItemsCached(selectedList, VCA.ContentType.RAID, encounterID,
                difficultyID)
            local best = rankings and rankings[1] or nil
            local selectedOdds = best and best.selectedOdds or nil
            local baseCount = best and best.baseCount or 0
            local remainingCount = best and best.remainingCount or 0
            if best then
                cacheReadyBossCount = cacheReadyBossCount + 1
            end

            entries[#entries + 1] = {
                order = idx,
                name = bossName,
                hasSelected = true,
                hasRanking = best ~= nil,
                specName = best and best.specName or nil,
                specIcon = best and best.specIcon or nil,
                baseCount = baseCount,
                remainingCount = remainingCount,
                selectedOdds = selectedOdds
            }
        else
            entries[#entries + 1] = {
                order = idx,
                name = bossName,
                hasSelected = false,
                hasRanking = false,
                specName = nil,
                specIcon = nil,
                baseCount = 0,
                remainingCount = 0,
                selectedOdds = nil
            }
        end

        idx = idx + 1
    end

    if selectedBossCount == 0 and #entries > 0 then
        ShowTable(false)
        SetLoadingState(false, false)
        scrollChild:SetHeight(1)
        return
    end

    local waitingForCache = selectedBossCount > 0 and cacheReadyBossCount < selectedBossCount
    local pausedByEJ = waitingForCache and VCA.LootPool.IsWarmPausedByEJ and VCA.LootPool.IsWarmPausedByEJ() or false
    SetLoadingState(waitingForCache, pausedByEJ)

    if #entries == 0 then
        local row = GetOrCreateRow(scrollChild)
        row.frame:SetWidth(contentW)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        row.frame:Show()
        row.bossLabel:SetText("|cff888888" .. L["RAID_OVERVIEW_NO_DATA"] .. "|r")
        row.specIcon:Hide()
        row.specLabel:SetText("")
        row.lootedLabel:SetText("")
        row.pctLabel:SetText("")
        row.barFill:Hide()
        scrollChild:SetHeight(ROW_H)
        return
    end

    table.sort(entries, function(a, b)
        return a.order < b.order
    end)

    local rowTop = 0
    for _, entry in ipairs(entries) do
        local row = GetOrCreateRow(scrollChild)
        row.frame:SetWidth(contentW)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -rowTop)
        row.frame:Show()

        row.bossLabel:SetText("|cffdddddd" .. entry.name .. "|r")

        if entry.hasSelected and entry.hasRanking then
            if entry.specIcon then
                row.specIcon:SetTexture(entry.specIcon)
                row.specIcon:Show()
            else
                row.specIcon:Hide()
            end
            local warnPrefix = (entry.remainingCount == 1) and
                                   (CreateAtlasMarkup("Ping_Wheel_Icon_Warning", 14, 14) .. " ") or ""
            row.specLabel:SetText(warnPrefix .. "|cffaaaaaa" .. (entry.specName or "?") .. "|r")

            if entry.baseCount > 0 then
                local obtained = entry.baseCount - entry.remainingCount
                row.lootedLabel:SetText("|cff888888" .. obtained .. "/" .. entry.baseCount .. "|r")

                local frac = obtained / entry.baseCount
                local fill = math.max(1, (contentW - 8) * math.min(1, frac))
                local t = VCA.Theme.accent
                row.barFill:SetColorTexture(t[1], t[2], t[3], 0.9)
                row.barFill:SetWidth(fill)
                row.barFill:SetShown(frac > 0)

                local pct = math.floor((entry.selectedOdds or 0) * 100 + 0.5)
                local pctColor = pct >= 20 and "|cffffff00" or "|cffdddddd"
                row.pctLabel:SetText(pctColor .. pct .. "%|r")
            else
                row.lootedLabel:SetText("|cff888888-|r")
                row.pctLabel:SetText("|cff888888-|r")
                row.barFill:Hide()
            end
        else
            row.barFill:Hide()
            row.specIcon:Hide()
            row.specLabel:SetText("|cff888888-|r")
            row.lootedLabel:SetText("|cff888888-|r")
            row.pctLabel:SetText("|cff888888-|r")
        end

        rowTop = rowTop + ROW_H + 2
    end

    scrollChild:SetHeight(math.max(rowTop, 1))
    scrollFrame:SetVerticalScroll(0)
    if Overview.RefreshSlots then
        Overview.RefreshSlots()
    end
end

function Overview.Show(instanceID, difficultyID)
    Overview.instanceID = instanceID
    Overview.difficultyID = difficultyID
    Overview.AnchorToEJ()
    frame:Show()
    Populate()
end

function Overview.Hide()
    SetLoadingState(false, false)
    frame:Hide()
end

function Overview.IsShown()
    return frame:IsShown()
end

function Overview.Refresh()
    if frame:IsShown() then
        Populate()
    end
end

local refreshFrame = CreateFrame("Frame")
refreshFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
refreshFrame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
refreshFrame:SetScript("OnEvent", function()
    if frame:IsShown() then
        Populate()
    end
end)
