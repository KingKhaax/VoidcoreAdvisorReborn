-- VoidcoreAdvisor: PanelColumns
-- Populate and refresh logic for the two panel columns.
-- Loaded after Panel.lua.  Accesses shared widget/state references via
-- Panel._s (a table set up by Panel.lua before this file is loaded).
local _, VCA = ...
local L = VCA.L
local Panel = VCA.Panel
local _s = Panel._s

-- Column-layout constants (must match Panel.lua).
local ROW_H = 26
local PADDING = 12

-- ── Scrollbar ──────────────────────────────────────────────────────────────────

local function UpdateScrollbar()
    local childH = _s.itemScrollChild:GetHeight()
    local frameH = _s.itemScrollFrame:GetHeight()
    if childH <= frameH or frameH <= 0 then
        _s.scrollTrack:Hide()
        _s.scrollThumb:Hide()
        return
    end
    _s.scrollTrack:Show()
    _s.scrollThumb:Show()
    local thumbRatio = frameH / childH
    local thumbH = math.max(20, frameH * thumbRatio)
    _s.scrollThumb:SetHeight(thumbH)
    local scrollRange = childH - frameH
    local current = _s.itemScrollFrame:GetVerticalScroll()
    local trackSpace = frameH - thumbH
    local offset = (current / scrollRange) * trackSpace
    _s.scrollThumb:ClearAllPoints()
    _s.scrollThumb:SetPoint("TOPRIGHT", _s.itemScrollFrame, "TOPRIGHT", 5, -offset)
end

Panel.UpdateScrollbar = UpdateScrollbar

-- ── Populate item column ───────────────────────────────────────────────────────

local function PopulateItemColumn(sourceType, sourceID, difficultyID, isHighTier)
    _s.HideAllItemRows()

    local classID = VCA.SpecInfo.GetPlayerClassID()
    local trustedItemSet = {}
    local specs = VCA.SpecInfo.GetPlayerSpecs()

    for _, spec in ipairs(specs) do
        local specItemIDs = VCA.LootPool.GetItemsForSpec(sourceType, sourceID, difficultyID, spec.classID, spec.specID)
        for _, id in ipairs(specItemIDs) do
            trustedItemSet[id] = true
        end
    end

    -- Also include class-wide items so that tier tokens / synthesis items are
    -- trusted.  These items appear in the EJ under a class filter but are
    -- excluded by the EJ's per-spec filter, so they land in byClass but not
    -- in bySpec for any individual spec.
    local classWideItemIDs = VCA.LootPool.GetItemsForClass(sourceType, sourceID, difficultyID, classID)
    for _, id in ipairs(classWideItemIDs) do
        trustedItemSet[id] = true
    end

    -- If selected items were persisted from an older dataset for this source,
    -- drop selections that are no longer trusted so they do not force the
    -- entire list into an always-dimmed state.
    local prunedAnySelection = false
    if next(_s.selectedItemIDs) then
        for selID in pairs(_s.selectedItemIDs) do
            if not trustedItemSet[selID] then
                _s.selectedItemIDs[selID] = nil
                prunedAnySelection = true
            end
        end
    end
    if prunedAnySelection then
        Panel.SaveItemSelections()
    end

    -- Build set of item IDs lootable by selected specs (if any).
    local specFilterSet -- nil when no spec filter is active
    if next(_s.selectedSpecIDs) then
        specFilterSet = {}
        for specID in pairs(_s.selectedSpecIDs) do
            local specItemIDs = VCA.LootPool.GetItemsForSpec(sourceType, sourceID, difficultyID, classID, specID)
            for _, id in ipairs(specItemIDs) do
                specFilterSet[id] = true
            end
        end
    end

    -- When items are selected, find which specs can loot ALL of them,
    -- then build a lootable set from those specs to grey out the rest.
    local itemImpliedFilter -- nil when no item selection filter is active
    if next(_s.selectedItemIDs) then
        -- Find specs that can loot every selected item
        local qualifyingSpecs = {}
        for _, spec in ipairs(specs) do
            local specItemIDs = VCA.LootPool.GetItemsForSpec(sourceType, sourceID, difficultyID, classID, spec.specID)
            local idSet = {}
            for _, id in ipairs(specItemIDs) do
                idSet[id] = true
            end
            local coversAll = true
            for selID in pairs(_s.selectedItemIDs) do
                if not idSet[selID] then
                    coversAll = false
                    break
                end
            end
            if coversAll then
                qualifyingSpecs[#qualifyingSpecs + 1] = spec.specID
            end
        end
        -- Build the union of items lootable by qualifying specs
        if #qualifyingSpecs > 0 then
            itemImpliedFilter = {}
            for _, specID in ipairs(qualifyingSpecs) do
                local specItemIDs = VCA.LootPool.GetItemsForSpec(sourceType, sourceID, difficultyID, classID, specID)
                for _, id in ipairs(specItemIDs) do
                    itemImpliedFilter[id] = true
                end
            end
        else
            -- No single spec covers all selected items — only keep selected
            itemImpliedFilter = {}
            for id in pairs(_s.selectedItemIDs) do
                itemImpliedFilter[id] = true
            end
        end
    end

    -- Fetch enriched item data with class filter so the EJ returns only items
    -- relevant to this class (all specs).  Using the class filter ensures the
    -- client has cached data (name, icon) for every item returned.
    local displayItems
    if sourceType == VCA.ContentType.RAID then
        displayItems = VCA.LootPool.GetEncounterItems(sourceID, difficultyID, classID, 0)
    else
        displayItems = VCA.LootPool.GetInstanceItems(sourceID, difficultyID, classID, 0).all
    end

    -- Trust gate: never show raw EJ loot without a trusted class/spec-derived
    -- allow-list. If trustedItemSet is empty, this intentionally yields an
    -- empty view instead of leaking the full dungeon loot table.
    local filteredItems = {}
    for _, item in ipairs(displayItems) do
        if trustedItemSet[item.itemID] then
            filteredItems[#filteredItems + 1] = item
        end
    end
    displayItems = filteredItems

    -- Fallback: if EJ enriched reads are temporarily empty but trusted pools
    -- are already available, build a minimal display list from trusted IDs.
    -- This keeps the loot column usable without weakening the trust gate.
    if #displayItems == 0 and next(trustedItemSet) then
        for itemID in pairs(trustedItemSet) do
            local itemName, itemLink, _, _, _, _, _, _, equipLoc, itemIcon = C_Item.GetItemInfo(itemID)
            if (not itemIcon or itemIcon == 0 or itemIcon == "") and C_Item and C_Item.GetItemInfoInstant then
                local _, _, _, instantEquipLoc, instantIcon = C_Item.GetItemInfoInstant(itemID)
                equipLoc = equipLoc or instantEquipLoc
                itemIcon = itemIcon or instantIcon
            end

            displayItems[#displayItems + 1] = {
                itemID = itemID,
                name = itemName or "",
                link = itemLink or "",
                icon = itemIcon or 0,
                slot = (equipLoc and _G[equipLoc]) or ""
            }
        end
    end

    -- Sort by equipment slot: head first, trinkets last.
    table.sort(displayItems, function(a, b)
        local oa = _s.GetSlotSortOrder(a.itemID)
        local ob = _s.GetSlotSortOrder(b.itemID)
        if oa ~= ob then
            return oa < ob
        end
        return (a.name or "") < (b.name or "")
    end)

    local colW = _s.LeftColWidth()
    local rowTop = 0
    for _, item in ipairs(displayItems) do
        -- An item is considered obtained when it has been won by at least one
        -- of the relevant specs.  When a spec filter is active, only check the
        -- selected spec(s) so that items looted on a different spec appear
        -- lootable again.  With no filter, fall back to the full spec union.
        -- Probability rows track per-spec state independently; this just drives
        -- the visual dim in the item list.
        local obtained = false
        local specsToCheck = next(_s.selectedSpecIDs) and _s.selectedSpecIDs or nil
        for _, spec in ipairs(specs) do
            if not specsToCheck or specsToCheck[spec.specID] then
                if VCA.Data.IsObtainedForKeyTier(sourceType, sourceID, difficultyID, spec.specID, item.itemID,
                    isHighTier) then
                    obtained = true
                    break
                end
            end
        end
        -- Amber state: obtained only under specID=0 (migrated from pre-spec data).
        local obtainedMigrated = not obtained and
                                     VCA.Data.IsObtainedMigrated(sourceType, sourceID, difficultyID, item.itemID)
        -- Marks staged with the "Mark rolled item" bar are shown (dimmed or not) before
        -- they are saved; the stored state stays in realObtained.
        local realObtained, realMigrated = obtained, obtainedMigrated
        local pending = Panel.pendingMarks and Panel.pendingMarks[item.itemID]
        if pending ~= nil then
            obtained = pending
            obtainedMigrated = false
        end
        local row = _s.GetOrCreateItemRow(_s.itemRows, _s.itemScrollChild)
        row.frame:SetWidth(colW - PADDING)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", _s.itemScrollChild, "TOPLEFT", 0, -rowTop)
        row.frame:Show()

        -- Selection highlight
        row.frame.itemID = item.itemID
        row.frame.itemLink = item.link or ""
        row.frame.itemSlot = item.slot or ""
        if _s.selectedItemIDs[item.itemID] then
            row.selHighlight:SetColorTexture(1, 0.75, 0, 0.18)
            row.selHighlight:Show()
        else
            row.selHighlight:Hide()
        end

        -- (OnClick is wired once at row creation inside GetOrCreateItemRow.)

        -- Icon (info.icon is a fileID number in the current EJ API)
        if item.icon and item.icon ~= 0 and item.icon ~= "" then
            row.icon:SetTexture(item.icon)
        else
            row.icon:SetTexture(134400)
        end

        -- Name with quality color and slot.
        local itemName, _, quality = C_Item.GetItemInfo(item.itemID)
        local ejName = (item.name ~= "" and item.name) or nil
        itemName = itemName or ejName or ("Item " .. item.itemID)
        quality = quality or 1
        if sourceType == VCA.ContentType.MYTHIC_PLUS then
            local reward = _s.GetRewardForKeyLevel(_s.getSelectedKeyLevel())
            if reward and reward.bonusID >= 12793 then
                quality = 4 -- Hero/Myth track → Epic
            end
        end
        local slotText = item.slot ~= "" and (" |cff888888[" .. item.slot .. "]|r") or ""
        row.nameLabel:SetText(_s.QualityColor(quality) .. itemName .. "|r" .. slotText)

        -- Quality border on the icon
        if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
            local c = ITEM_QUALITY_COLORS[quality]
            row.iconBorder:SetVertexColor(c.r, c.g, c.b)
            row.iconBorder:Show()
        else
            row.iconBorder:Hide()
        end

        -- Obtained checkbox
        row.checkbox:SetChecked(obtainedMigrated and "migrated" or obtained)
        row.checkbox.itemID = item.itemID
        row.checkbox.itemLink = item.link or ""
        row.checkbox.sourceType = sourceType
        row.checkbox.sourceID = sourceID
        row.checkbox.diffID = difficultyID
        row.checkbox.isHighTier = isHighTier
        row.checkbox.isObtained = realObtained or realMigrated
        -- Obtained loot icon button tooltip: list which specs have it obtained.
        row.checkbox.specs = specs
        row.checkbox:SetScript("OnEnter", function(self)
            local obtainedSpecs = {}
            for _, sp in ipairs(self.specs) do
                if VCA.Data.IsObtainedForKeyTier(self.sourceType, self.sourceID, self.diffID, sp.specID, self.itemID,
                    self.isHighTier) then
                    obtainedSpecs[#obtainedSpecs + 1] = sp
                end
            end
            local migratedObtained = VCA.Data.IsObtainedMigrated(self.sourceType, self.sourceID, self.diffID,
                self.itemID)
            if #obtainedSpecs == 0 and not migratedObtained then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SPEC_PICKER_TITLE"], 1, 1, 1)
            for _, sp in ipairs(obtainedSpecs) do
                if self.sourceType == VCA.ContentType.MYTHIC_PLUS then
                    local levels = VCA.Data.GetAllKeyLevelsForSpec(self.sourceType, self.sourceID, self.diffID,
                        sp.specID, self.itemID)
                    local klText
                    if #levels > 0 then
                        local parts = {}
                        for _, kl in ipairs(levels) do
                            parts[#parts + 1] = "+" .. kl
                        end
                        klText = " |cff888888(" .. table.concat(parts, ", ") .. ")|r"
                    elseif VCA.Data.IsObtainedBareKey(self.sourceType, self.sourceID, self.diffID, sp.specID,
                        self.itemID) then
                        -- Bare key: obtained at unknown key level (pre-tier data or Mythic 0).
                        klText = " |cff888888(" .. L["UNKNOWN_KEYLEVEL"] .. ")|r"
                    else
                        -- Tiered key with no log entry: set manually via the spec picker.
                        klText = " |cff888888(" .. L["MANUAL_ENTRY"] .. ")|r"
                    end
                    GameTooltip:AddLine("|T" .. sp.icon .. ":12:12:0:0:64:64:4:60:4:60|t " .. sp.name .. klText, 0.4,
                        1.0, 0.4)
                else
                    GameTooltip:AddLine("|T" .. sp.icon .. ":12:12:0:0:64:64:4:60:4:60|t " .. sp.name, 0.4, 1.0, 0.4)
                end
            end
            if migratedObtained then
                GameTooltip:AddLine(L["OBTAINED_UNKNOWN_SPEC"], 1.0, 0.7, 0.1)
            end
            GameTooltip:Show()
        end)
        row.checkbox:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row.checkbox:SetScript("OnClick", function(self)
            if self.isObtained then
                -- Clear all specs, any migrated (specID=0) entry, and manual log entries.
                local dungeonData = VCA.SeasonData and VCA.SeasonData.dungeons[self.sourceID]
                if dungeonData and dungeonData.bySpec then
                    for specID in pairs(dungeonData.bySpec) do
                        VCA.Data.SetObtained(self.sourceType, self.sourceID, self.diffID, specID, self.itemID, false)
                    end
                end
                local raidData = VCA.SeasonData and VCA.SeasonData.raids and VCA.SeasonData.raids[self.sourceID]
                if raidData and raidData.bySpec then
                    local specMap = raidData.bySpec[self.diffID]
                    if specMap then
                        for specID in pairs(specMap) do
                            VCA.Data
                                .SetObtained(self.sourceType, self.sourceID, self.diffID, specID, self.itemID, false)
                        end
                    end
                end
                VCA.Data.SetObtained(self.sourceType, self.sourceID, self.diffID, 0, self.itemID, false)
                VCA.Data.RemoveAllManualLogEntriesForItem(self.itemID, self.sourceType, self.sourceID, self.diffID)
                -- Roll entries must not bring the mark back when the log is replayed at login.
                VCA.Data.NeutralizeRollEntriesForItem(self.itemID, self.sourceType, self.sourceID, self.diffID,
                    raidData and raidData.instanceID)
            else
                -- Mark obtained for all eligible specs, log the manual action, and check completion.
                local source = {
                    sourceType = self.sourceType,
                    sourceID = self.sourceID,
                    difficultyID = self.diffID
                }
                local dungeonData = VCA.SeasonData and VCA.SeasonData.dungeons[self.sourceID]
                VCA.Data.PropagateObtainedToAllSpecs(self.sourceType, self.sourceID, self.diffID, self.itemID, nil)
                VCA.Data.SetObtained(self.sourceType, self.sourceID, self.diffID, 0, self.itemID, false)
                if dungeonData and dungeonData.bySpec then
                    for specID, itemList in pairs(dungeonData.bySpec) do
                        for _, id in ipairs(itemList) do
                            if id == self.itemID then
                                if VCA.Detection and VCA.Detection.CheckAndResetIfComplete and not Panel.keepMarks then
                                    VCA.Detection.CheckAndResetIfComplete(source, specID, nil)
                                end
                                break
                            end
                        end
                    end
                end
                local raidData = VCA.SeasonData and VCA.SeasonData.raids and VCA.SeasonData.raids[self.sourceID]
                if raidData and raidData.bySpec then
                    local specMap = raidData.bySpec[self.diffID]
                    if specMap then
                        for specID, itemList in pairs(specMap) do
                            for _, id in ipairs(itemList) do
                                if id == self.itemID then
                                    if VCA.Detection and VCA.Detection.CheckAndResetIfComplete and not Panel.keepMarks then
                                        VCA.Detection.CheckAndResetIfComplete(source, specID, nil)
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
                if _s.selectedItemIDs[self.itemID] then
                    _s.selectedItemIDs[self.itemID] = nil
                    Panel.SaveItemSelections()
                end
            end
            Panel.Refresh()
        end)

        -- Dim row if obtained, filtered out by spec selection, or
        -- not lootable by the specs implied by the item selection.
        local specFiltered = specFilterSet and not specFilterSet[item.itemID]
        local itemFiltered = itemImpliedFilter and not itemImpliedFilter[item.itemID]
        local otherSpec = specFiltered or itemFiltered
        local gotIt = obtained or obtainedMigrated
        -- Dark = you already got it. Red = it will not drop for the spec in use.
        local dimmed = gotIt or otherSpec
        row.frame.dimmed = dimmed
        if gotIt then
            row.nameLabel:SetAlpha(0.4)
            row.iconButton:SetAlpha(0.4)
            row.redShade:Hide()
            row.icon:SetVertexColor(1, 1, 1)
        elseif otherSpec then
            row.nameLabel:SetAlpha(0.6)
            row.iconButton:SetAlpha(0.75)
            row.redShade:Show()
            row.icon:SetVertexColor(1, 0.35, 0.35)
        else
            row.nameLabel:SetAlpha(1)
            row.iconButton:SetAlpha(1)
            row.redShade:Hide()
            row.icon:SetVertexColor(1, 1, 1)
        end

        rowTop = rowTop + ROW_H + 2
    end

    _s.itemScrollChild:SetHeight(math.max(rowTop, 1))

    if #displayItems == 0 then
        -- Show a context-appropriate notice
        local noticeText
        if sourceType == VCA.ContentType.RAID and difficultyID == VCA.Difficulty.RAID_LFR then
            noticeText = L["LFR_NOT_ELIGIBLE"]
        else
            noticeText = L["NO_ITEMS_FOR_SPEC"]
        end
        local noRow = _s.GetOrCreateItemRow(_s.itemRows, _s.itemScrollChild)
        noRow.frame:SetWidth(colW - PADDING)
        noRow.frame:ClearAllPoints()
        noRow.frame:SetPoint("TOPLEFT", _s.itemScrollChild, "TOPLEFT", 0, 0)
        noRow.frame:Show()
        noRow.icon:SetTexture(134400)
        noRow.nameLabel:SetText("|cff888888" .. noticeText .. "|r")
        noRow.nameLabel:SetAlpha(1)
        noRow.iconButton:SetAlpha(0.3)
        noRow.redShade:Hide()
        noRow.icon:SetVertexColor(1, 1, 1)
        noRow.iconBorder:Hide()
        noRow.checkbox:Hide()
        _s.itemScrollChild:SetHeight(ROW_H)
    end

    -- Reset scroll position and update scrollbar
    _s.itemScrollFrame:SetVerticalScroll(0)
    UpdateScrollbar()
end

-- ── Populate spec column ───────────────────────────────────────────────────────

-- "At least one chosen item" odds for the best spec, from your chosen items.
local function UpdateCumulative(rankings, hasSelection, sourceType)
    local label = _s.cumLabel
    local gdb = _G[VCA.GLOBAL_DB_NAME]
    if not label then
        return
    end
    if not hasSelection or (gdb and gdb.showCumulative == false) then
        label:SetText("")
        return
    end
    local best
    for _, r in ipairs(rankings) do
        if not r.noItems and not r.allObtained and r.remainingCount > 0 and r.matchRemainingCount then
            best = r
            break
        end
    end
    if not best then
        label:SetText("")
        return
    end
    local Planner = VCA.Planner
    local total, wanted = best.remainingCount, best.matchRemainingCount
    local text = string.format(L["CUMULATIVE_LINE"], Planner.AtLeastOne(total, wanted, 1) * 100,
        Planner.AtLeastOne(total, wanted, 3) * 100)
    local cost = VCA.Probability.GetVoidcoreCost(sourceType)
    local owned = Planner.OwnedCores()
    local rolls = math.floor(owned / cost)
    if rolls > 0 and rolls ~= 1 and rolls ~= 3 then
        text = text .. string.format(L["CUMULATIVE_OWNED"], owned, Planner.AtLeastOne(total, wanted, rolls) * 100)
    end
    label:SetText("|cffbbbbbb" .. text .. "|r")
end

local function PopulateSpecColumn(sourceType, sourceID, difficultyID, filterItemIDs)
    _s.HideAllSpecRows()

    -- For M+: derive key tier from the selected key level so probability
    -- reflects only items still needed for that tier.
    local isHighTier = nil
    if sourceType == VCA.ContentType.MYTHIC_PLUS then
        isHighTier = _s.getSelectedKeyLevel() >= 10
    end

    local rankings
    if filterItemIDs and #filterItemIDs > 0 then
        rankings = VCA.Probability.RankCurrentPlayerSpecsForItems(filterItemIDs, sourceType, sourceID, difficultyID,
            isHighTier)
    else
        rankings = VCA.Probability.RankCurrentPlayerSpecs(sourceType, sourceID, difficultyID, isHighTier)
    end
    UpdateCumulative(rankings, filterItemIDs ~= nil and #filterItemIDs > 0, sourceType)
    local colW = _s.RightColWidth()
    local rowTop = 0

    local hasSelection = filterItemIDs and #filterItemIDs > 0
    local accent = VCA.Theme.accent
    for _, entry in ipairs(rankings) do
        local row = _s.GetOrCreateSpecRow(_s.specRows, _s.specScrollChild)
        row.frame:SetWidth(colW - PADDING)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", _s.specScrollChild, "TOPLEFT", 0, -rowTop)
        row.frame:Show()

        -- Store specID for click selection
        row.frame.specID = entry.specID

        -- Only the spec you clicked looks selected: a band and a bright edge in the theme color
        row.selHighlight:Hide()
        if _s.selectedSpecIDs[entry.specID] then
            row.bestBg:SetColorTexture(accent[1], accent[2], accent[3], 0.2)
            row.bestEdge:SetColorTexture(accent[1], accent[2], accent[3], 1)
            row.bestBg:Show()
            row.bestEdge:Show()
        else
            row.bestBg:Hide()
            row.bestEdge:Hide()
        end
        -- The best spec is told apart by its gold rank and its figure in the theme color
        local isBest = entry.rank == 1 and not entry.noItems

        -- Rank #
        local rankColor = entry.rank == 1 and "|cffffd24d" or "|cffaaaaaa"
        row.rankLabel:SetText(rankColor .. "#" .. entry.rank .. "|r")

        -- Spec icon
        row.icon:SetTexture(entry.specIcon or 134400)

        -- Spec name
        local nameColor = entry.allObtained and "|cff44ff44" or (entry.noItems and "|cff888888" or "|cffeeeeee")
        local warnPrefix =
            (entry.remainingCount == 1) and (CreateAtlasMarkup("Ping_Wheel_Icon_Warning", 14, 14) .. " ") or ""
        row.nameLabel:SetText(warnPrefix .. nameColor .. (entry.specName or "?") .. "|r")
        if entry.remainingCount == 1 then
            row.warnHitArea.tooltipText = L["REMINDER_WARNING_ONE_ITEM"]
            row.warnHitArea:Show()
        else
            row.warnHitArea:Hide()
        end

        -- Figures and bar: with chosen items the chance is the main figure and the bar shows it;
        -- without them the main figure is obtained/total and the bar shows how many you have.
        local obtainedCount = (entry.baseCount or 0) - (entry.remainingCount or 0)
        local frac
        if entry.noItems then
            row.statsLabel:SetText("|cff888888—|r")
            row.countLabel:SetText("")
            frac = 0
        elseif entry.allObtained then
            row.statsLabel:SetText("|cff44ff44" .. L["ALL_OBTAINED"] .. "|r")
            row.countLabel:SetText("")
            frac = 1
        elseif hasSelection and entry.selectedOdds then
            local pct = math.floor(entry.selectedOdds * 100 + 0.5)
            row.statsLabel:SetText((isBest and "|cff" .. string.format("%02x%02x%02x", accent[1] * 255, accent[2] * 255,
                accent[3] * 255) or "|cffffffff") .. pct .. "%|r")
            row.countLabel:SetText("|cffaaaaaa" .. obtainedCount .. "/" .. entry.baseCount .. "|r")
            frac = entry.selectedOdds
        else
            row.statsLabel:SetText("|cffdddddd" .. obtainedCount .. "/" .. entry.baseCount .. "|r")
            row.countLabel:SetText("")
            frac = (entry.baseCount or 0) > 0 and (obtainedCount / entry.baseCount) or 0
        end
        -- row width minus rank (2+30), gap, icon (28), gap and the column of figures on the right
        local trackW = math.max(40, colW - PADDING - 2 - 30 - 5 - 28 - 8 - 78)
        row.barFill:SetColorTexture(accent[1], accent[2], accent[3], isBest and 1 or 0.85)
        row.barFill:SetWidth(math.max(1, trackW * math.min(1, math.max(0, frac))))
        row.barFill:SetShown(frac > 0)

        rowTop = rowTop + _s.SPEC_ROW_H + 6
    end

    _s.specScrollChild:SetHeight(math.max(rowTop, 1))
end

-- ── Clear-filter button visibility ────────────────────────────────────────────

local function UpdateClearFilterButton()
    if next(_s.selectedSpecIDs) or next(_s.selectedItemIDs) then
        _s.clearSpecBtn:Show()
    else
        _s.clearSpecBtn:Hide()
    end
end

-- ── Refresh item column ────────────────────────────────────────────────────────
-- Updates the item column when spec selection changes.
-- Updates the loot header to indicate spec filtering.

function Panel.RefreshItemColumn()
    local isHighTier = nil
    if Panel.sourceType == VCA.ContentType.MYTHIC_PLUS then
        isHighTier = _s.getSelectedKeyLevel() >= 10
    end
    PopulateItemColumn(Panel.sourceType, Panel.sourceID, Panel.difficultyID, isHighTier)
    local count = 0
    for _ in pairs(_s.selectedSpecIDs) do
        count = count + 1
    end
    if count > 0 then
        local label = count == 1 and L["COL_LOOT_FILTERED"] or string.format(L["COL_LOOT_FILTERED_N"], count)
        _s.lootColHeader:SetText(VCA.Theme.hdr .. "" .. label .. "|r")
    else
        _s.lootColHeader:SetText(VCA.Theme.hdr .. "" .. L["COL_LOOT"] .. "|r")
    end
    UpdateClearFilterButton()
end

-- ── Refresh spec column ────────────────────────────────────────────────────────
-- Updates the spec column based on current item selection:
--   * Items selected  → header shows "SPEC FIT" and ranks by intersection
--   * Nothing selected → normal full-pool rankings

function Panel.RefreshSpecColumn()
    local selectedList = {}
    for id in pairs(_s.selectedItemIDs) do
        selectedList[#selectedList + 1] = id
    end
    if #selectedList > 0 then
        local count = #selectedList
        local label = count == 1 and L["COL_SPEC_FIT"] or (L["COL_SPEC_FIT"] .. "  |cff888888(" .. count .. ")|r")
        _s.specColHeader:SetText(VCA.Theme.hdr .. "" .. label .. "|r")
        PopulateSpecColumn(Panel.sourceType, Panel.sourceID, Panel.difficultyID, selectedList)
    else
        _s.specColHeader:SetText(VCA.Theme.hdr .. "" .. L["COL_SPEC_RANKING"] .. "|r")
        PopulateSpecColumn(Panel.sourceType, Panel.sourceID, Panel.difficultyID)
    end
    UpdateClearFilterButton()
end
