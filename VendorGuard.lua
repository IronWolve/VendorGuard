local addonName, ns = ...
local eventFrame = CreateFrame("Frame")
local overlays, hooked = {}, {}
local queued, retryScheduled = false, false
local retryBudget, lastPage = 4, nil
local requested = {}
local defaults = { enabled = true, professionBags = true, tint = true, green = true, showMinimap = true,
    comparisons = true, badges = false }
local colors = { red = { 1, 0.15, 0.12 }, orange = { 1, 0.48, 0.08 },
    yellow = { 1, 0.8, 0.12 }, green = { 0.2, 0.9, 0.4 } }
local badges = { red = "!", orange = "P", yellow = "L", green = "+" }
local headings = { red = "check requirements", orange = "skill / profession warning",
    yellow = "higher level needed", green = "usable now" }
local Refresh, QueueRefresh
local comparisonColors = { gain = { 0.2, 0.9, 0.4 }, loss = { 1, 0.3, 0.25 },
    later = colors.yellow, neutral = { 0.8, 0.8, 0.8 } }

local function Options()
    return ns.options or defaults
end

local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff75c9ffVendorGuard:|r " .. text)
end

local function HideOverlays()
    for _, overlay in pairs(overlays) do overlay:Hide() end
end

local function CreateOverlay(row, button)
    local overlay = CreateFrame("Frame", nil, row)
    overlay:SetAllPoints(row)
    overlay:SetFrameLevel(math.max(row:GetFrameLevel(), button:GetFrameLevel()) + 5)
    overlay:EnableMouse(false)
    overlay.fill = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.fill:SetAllPoints()
    overlay.badgeBackground = overlay:CreateTexture(nil, "OVERLAY")
    overlay.badgeBackground:SetColorTexture(0.03, 0.03, 0.03, 0.95)
    overlay.badgeBackground:SetSize(12, 12)
    overlay.badgeBackground:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    overlay.badge = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.badge:SetAllPoints(overlay.badgeBackground)
    overlay.comparisonLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overlay.comparisonLabel:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -3, -1)
    overlay.comparisonLabel:SetHeight(12)
    overlay.comparisonLabel:SetJustifyH("RIGHT")
    overlay.comparisonLabel:SetWordWrap(false)
    overlays[row] = overlay
    return overlay
end

local function PriceRegions(slot)
    local prefix = "MerchantItem" .. slot
    local money, currency = _G[prefix .. "MoneyFrame"], _G[prefix .. "AltCurrencyFrame"]
    local regions = {}
    if money and money:IsShown() then
        local hasCoins = false
        for _, denomination in ipairs({ "Gold", "Silver", "Copper" }) do
            local coin = money[denomination .. "Button"] or _G[prefix .. "MoneyFrame" .. denomination .. "Button"]
            if coin then
                hasCoins = true
                if coin:IsShown() then regions[#regions + 1] = coin end
            end
        end
        -- MoneyFrame can span the entire entry even when only one coin is
        -- visible. Its denomination buttons bound the actual price instead.
        if not hasCoins then regions[#regions + 1] = money end
    end
    if currency and currency:IsShown() then regions[#regions + 1] = currency end
    return regions, money or currency
end

local function ShowComparisonLabel(overlay, row, button, comparison, slot)
    local label = overlay.comparisonLabel
    label:Hide()
    if not comparison or not comparison.label then return end
    -- Use only free space on the existing price line. Never change Blizzard's
    -- geometry: scaled GetHeight() values need not equal the value passed to
    -- SetHeight(), and interpreting that rounding as a new base caused growth.
    local right, occupiedRight = row:GetRight(), button:GetRight()
    if not right or not occupiedRight then return end
    local prices, hasPriceFrame = PriceRegions(slot)
    if not hasPriceFrame then return end
    for _, region in ipairs(prices) do
        if region and region:IsShown() then
            local edge = region:GetRight()
            if not edge then return end
            occupiedRight = math.max(occupiedRight, edge)
        end
    end
    -- Three pixels at each edge; the previous nine-pixel reservation hid
    -- signed DPS labels even though the shorter absolute-DPS label fitted.
    local available = right - occupiedRight - 6
    label:SetWidth(0)
    label:SetText(comparison.label)
    local width = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
    local fullWidth = width
    if width + 1 > available and comparison.label:find(" DPS", 1, true) then
        -- Keep the number, sign and unit readable in a compact price row.
        label:SetText(comparison.label:gsub(" DPS", "DPS"))
        width = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
    end
    label:ClearAllPoints()
    if width + 1 <= available then
        label:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -3, -1)
    else
        label:SetText(comparison.label)
        width = fullWidth
        -- Try the unused line between the rendered name and price. Name frames
        -- can be taller than their text; account for vertical justification.
        local name = row.Name or _G["MerchantItem" .. slot .. "Name"]
        if not name or not name.GetStringHeight then return end
        local nameTop, nameBottom = name:GetTop(), name:GetBottom()
        local rowTop, rowBottom = row:GetTop(), row:GetBottom()
        if not nameTop or not nameBottom or not rowTop or not rowBottom then return end
        local textHeight = name:GetStringHeight()
        local justify = name:GetJustifyV()
        local textBottom = justify == "TOP" and nameTop - textHeight
            or justify == "BOTTOM" and nameBottom or (nameTop + nameBottom - textHeight) / 2
        local priceTop = rowBottom
        for _, region in ipairs(prices) do
            if region and region:IsShown() then
                local top = region:GetTop()
                if not top then return end
                priceTop = math.max(priceTop, top)
            end
        end
        local labelTop = math.min(textBottom - 2, rowTop - 1)
        if labelTop - 12 < priceTop + 2 or width + 1 > right - button:GetRight() - 9 then return end
        label:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -3, labelTop - rowTop)
    end
    label:SetWidth(width + 1)
    local color = comparisonColors[comparison.tone]
    label:SetTextColor(color[1], color[2], color[3])
    label:Show()
end

local function ShowResult(row, button, result, comparison, slot)
    local overlay = overlays[row] or CreateOverlay(row, button)
    local color = result and colors[result.status]
    overlay.fill:SetColorTexture(color and color[1] or 0, color and color[2] or 0,
        color and color[3] or 0, color and Options().tint and 0.13 or 0)
    overlay.badgeBackground:SetShown(color ~= nil and Options().badges)
    overlay.badge:SetShown(color ~= nil and Options().badges)
    if color then
        overlay.badge:SetText(result.badge or badges[result.status])
        overlay.badge:SetTextColor(color[1], color[2], color[3])
    end
    ShowComparisonLabel(overlay, row, button, comparison, slot)
    overlay:Show()
end

local function MerchantVisible()
    return MerchantFrame and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1
end

local function RequestData(item)
    if item and item.id and not requested[item.id] and C_Item and C_Item.RequestLoadItemDataByID then
        requested[item.id] = true
        C_Item.RequestLoadItemDataByID(item.id)
    end
end

Refresh = function()
    HideOverlays()
    if not Options().enabled or not MerchantVisible() then return end
    ns.Comparison.Clear()
    local perPage = MERCHANT_ITEMS_PER_PAGE or 10
    local page = MerchantFrame.page or 1
    if page ~= lastPage then
        retryBudget, lastPage = 4, page
    end
    local count = GetMerchantNumItems()
    local player, pending = ns.GetPlayer(), false
    for slot = 1, perPage do
        local index = (page - 1) * perPage + slot
        local row = _G["MerchantItem" .. slot]
        local button = row and (row.ItemButton or _G["MerchantItem" .. slot .. "ItemButton"])
        if index <= count and row and button and button:IsShown() then
            local item = ns.ReadItem(index)
            if item then
                local result = ns.Rules.Evaluate(item, player, Options())
                result = ns.Comparison.WarnLowerDPS(item, result)
                local comparison = ns.Comparison.Get(item, result, Options())
                if result or (comparison and comparison.label) then ShowResult(row, button, result, comparison, slot) end
                if not item.ready then
                    pending = true
                    RequestData(item)
                end
            else
                pending = true
            end
        end
    end
    -- Data events handle late arrivals. A bounded retry covers a tooltip whose data
    -- becomes available without an item-info event, without permanent polling.
    if pending and retryBudget > 0 and not retryScheduled then
        retryBudget = retryBudget - 1
        retryScheduled = true
        C_Timer.After(0.4, function()
            retryScheduled = false
            QueueRefresh()
        end)
    end
end

QueueRefresh = function()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        Refresh()
    end)
end
ns.Refresh = QueueRefresh

local function OnMerchantHover(button)
    if not Options().enabled or not MerchantVisible() then return end
    if not GameTooltip:IsOwned(button) then return end
    local item = ns.ReadItem(button:GetID())
    if not item then return end
    local result = ns.Rules.Evaluate(item, ns.GetPlayer(), Options())
    result = ns.Comparison.WarnLowerDPS(item, result)
    if not result then return end
    local signature = item.link .. ":" .. (result and result.status or "") .. ":"
        .. (result and table.concat(result.reasons, ":") or "") .. ":" .. tostring(Options().comparisons)
    if GameTooltip.vendorGuardSignature == signature then return end
    GameTooltip.vendorGuardSignature = signature
    if result then
        local color = colors[result.status]
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("VendorGuard: " .. (result.heading or headings[result.status]), color[1], color[2], color[3])
        for _, reason in ipairs(result.reasons) do
            GameTooltip:AddLine(reason, color[1], color[2], color[3], true)
        end
    end
    -- Other addons handle stat-comparison tooltips; our comparison is inline.
    GameTooltip:Show()
end

local function InstallHooks()
    for _, name in ipairs({ "MerchantFrame_Update", "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_UpdateBuybackInfo" }) do
        if not hooked[name] and type(_G[name]) == "function" then
            hooksecurefunc(name, QueueRefresh)
            hooked[name] = true
        end
    end
    if not hooked.hover and type(MerchantItemButton_OnEnter) == "function" then
        hooksecurefunc("MerchantItemButton_OnEnter", OnMerchantHover)
        hooked.hover = true
    end
    if not hooked.tooltip and GameTooltip then
        GameTooltip:HookScript("OnTooltipCleared", function(tooltip) tooltip.vendorGuardSignature = nil end)
        hooked.tooltip = true
    end
end

local function Status()
    local version, build, _, interface = GetBuildInfo()
    Print(("0.3.0-beta.6 | client %s (%s), interface %s | %s | profession bags/tools %s | tint %s | green %s"):format(
        version, build, interface, Options().enabled and "on" or "off",
        Options().professionBags and "on" or "off", Options().tint and "on" or "off", Options().green and "on" or "off"))
    Print("APIs: merchant tooltip " .. tostring(C_TooltipInfo and type(C_TooltipInfo.GetMerchantItem) == "function")
        .. ", item info " .. tostring(C_Item and type(C_Item.GetItemInfo) == "function")
        .. ", profession list " .. tostring(type(GetProfessions) == "function")
        .. "; vendor hooks " .. tostring(hooked.MerchantFrame_Update == true))
    Print("Comparisons " .. (Options().comparisons and "on" or "off"))
end

local function DebugItem(index)
    if not MerchantVisible() then Print("Open a vendor's Merchant tab first."); return end
    if not index or index < 1 or index % 1 ~= 0 or index > GetMerchantNumItems() then
        Print("Use /vg debug N with an item index in this vendor's current filtered list."); return
    end
    local item = ns.ReadItem(index)
    if not item then Print("Item data is still loading."); return end
    local player = ns.GetPlayer()
    local result = ns.Rules.Evaluate(item, player, Options())
    result = ns.Comparison.WarnLowerDPS(item, result)
    local comparison = ns.Comparison.Get(item, result, Options())
    Print(("Item %s | %s | class/subclass %s/%s | level %s/%s | ready %s | merchant usable %s | result %s"):format(
        tostring(item.id), item.name or "loading", tostring(item.classID), tostring(item.subclassID),
        tostring(player.level), tostring(item.requiredLevel), tostring(item.ready),
        tostring(item.merchantUsable), result and result.status or "unmarked"))
    Print("Vendor label: " .. (comparison and comparison.label or "none")
        .. "; comparisons " .. (Options().comparisons and "on" or "off")
        .. (comparison and comparison.note and ("; " .. comparison.note) or ""))
    for _, line in ipairs(item.lines) do
        local function Color(c)
            return c and ("%.2f,%.2f,%.2f"):format(c.r, c.g, c.b) or "none"
        end
        Print(("type %s | L %s [%s] | R %s [%s]"):format(tostring(line.type),
            ns.Rules.CleanText(line.leftText), Color(line.leftColor),
            ns.Rules.CleanText(line.rightText), Color(line.rightColor)))
    end
end

SLASH_VENDORGUARD1 = "/vg"
SLASH_VENDORGUARD2 = "/vendorguard"
SlashCmdList.VENDORGUARD = function(message)
    local command, argument = message:lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "on" or command == "off" then
        Options().enabled = command == "on"
    elseif (command == "bags" or command == "tint" or command == "green" or command == "minimap"
            or command == "compare" or command == "badges")
            and (argument == "on" or argument == "off") then
        local keys = { bags = "professionBags", tint = "tint", green = "green", minimap = "showMinimap",
            compare = "comparisons", badges = "badges" }
        Options()[keys[command]] = argument == "on"
    elseif command == "options" or command == "" then
        ns.OpenOptions(); return
    elseif command == "debug" then
        DebugItem(tonumber(argument)); return
    elseif command == "status" then
        Status(); return
    else
        Print("Red ! = restriction; orange P/! = skill/profession or lower weapon DPS; yellow L = level only; green + = usable gear/bag (not an upgrade rating).")
        Print("/vg options, /vg on|off, /vg bags|tint|green|minimap|compare|badges on|off, /vg status, /vg debug N")
        return
    end
    -- Let Blizzard rebuild its tooltip on the next hover after settings changes.
    if GameTooltip and GameTooltip.vendorGuardSignature then GameTooltip:Hide() end
    QueueRefresh()
    ns.UpdateMinimap()
    Status()
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            if type(VendorGuardDB) ~= "table" then VendorGuardDB = {} end
            VendorGuardDB.pawn = nil
            for key, value in pairs(defaults) do
                if type(VendorGuardDB[key]) ~= "boolean" then VendorGuardDB[key] = value end
            end
            ns.options = VendorGuardDB
            if type(ns.options.minimapAngle) ~= "number" then ns.options.minimapAngle = 225 end
            ns.UpdateMinimap()
        end
        InstallHooks()
    elseif event == "MERCHANT_CLOSED" then
        HideOverlays()
        ns.Comparison.Clear(true)
        requested, lastPage = {}, nil
        return
    elseif event == "MERCHANT_SHOW" then
        retryBudget, requested, lastPage = 4, {}, nil
        InstallHooks()
    elseif event == "PLAYER_ENTERING_WORLD" then
        InstallHooks()
        ns.UpdateMinimap()
    end
    if MerchantFrame and MerchantFrame:IsShown() then QueueRefresh() end
end)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "MERCHANT_SHOW", "MERCHANT_CLOSED",
        "MERCHANT_UPDATE", "MERCHANT_FILTER_ITEM_UPDATE", "GET_ITEM_INFO_RECEIVED", "TOOLTIP_DATA_UPDATE",
        "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "BAG_UPDATE_DELAYED" }) do
    eventFrame:RegisterEvent(event)
end
InstallHooks()
