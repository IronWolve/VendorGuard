local _, ns = ...
local button, panel, checkboxes

local function UpdatePosition()
    if not button or not ns.options then return end
    local angle = math.rad(ns.options.minimapAngle or 225)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * (Minimap:GetWidth() / 2 + 8),
        math.sin(angle) * (Minimap:GetHeight() / 2 + 8))
end

local function SyncCheckboxes()
    for _, checkbox in ipairs(checkboxes or {}) do
        checkbox:SetChecked(ns.options[checkbox.option])
    end
end

local function OpenOptions()
    if not panel then
        panel = CreateFrame("Frame", "VendorGuardOptions", UIParent, "BasicFrameTemplateWithInset")
        panel:SetSize(430, 355)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:Hide()
        panel:SetClampedToScreen(true)
        panel:SetMovable(true)
        panel:EnableMouse(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        panel.TitleText:SetText("VendorGuard")
        UISpecialFrames[#UISpecialFrames + 1] = "VendorGuardOptions"
        checkboxes = {}
        local choices = {
            { "enabled", "Enable vendor highlights" },
            { "professionBags", "Warn about unrelated profession bags and tools" },
            { "green", "Show green for usable gear and bags" },
            { "tint", "Tint the whole vendor item box" },
            { "comparisons", "Show stat / DPS comparison labels in vendor" },
            { "badges", "Show small ! / P / L / + symbols on item icons" },
            { "showMinimap", "Show minimap button" },
        }
        for i, choice in ipairs(choices) do
            local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
            checkbox:SetPoint("TOPLEFT", 16, -30 - (i - 1) * 30)
            checkbox.option = choice[1]
            local label = checkbox.Text or checkbox.text
            if not label then
                label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                label:SetPoint("LEFT", checkbox, "RIGHT", 3, 0)
            end
            label:SetText(choice[2])
            checkbox:SetChecked(ns.options[choice[1]])
            checkbox:SetScript("OnClick", function(self)
                ns.options[self.option] = self:GetChecked() == true
                if GameTooltip.vendorGuardSignature then GameTooltip:Hide() end
                ns.UpdateMinimap()
                ns.Refresh()
            end)
            checkboxes[#checkboxes + 1] = checkbox
        end
        local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        legend:SetPoint("TOPLEFT", 22, -255)
        legend:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
        legend:SetJustifyH("LEFT")
        legend:SetText("|cffff2620! Red: restriction|r\n|cffff7a14P/! Orange: skill / profession or lower weapon DPS|r\n|cffffcc20L Yellow: level only|r\n|cff33e666+ Green: usable now (not an upgrade rating)|r\n\n/vg minimap on restores a hidden button.")
    end
    SyncCheckboxes()
    panel:SetShown(not panel:IsShown())
end
ns.OpenOptions = OpenOptions

function ns.UpdateMinimap()
    if not ns.options or not Minimap then return end
    if not button then
        button = CreateFrame("Button", "VendorGuardMinimapButton", Minimap)
        button:SetSize(32, 32)
        button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:RegisterForDrag("LeftButton")
        button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", -1, 1)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetSize(54, 54)
        border:SetPoint("TOPLEFT")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        button:SetScript("OnClick", function(_, mouseButton)
            if button.dragged then button.dragged = false; return end
            if mouseButton == "RightButton" then
                ns.options.enabled = not ns.options.enabled
                GameTooltip:Hide()
                SyncCheckboxes()
                ns.Refresh()
            else
                GameTooltip:Hide()
                OpenOptions()
            end
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("VendorGuard", 0.46, 0.79, 1)
            GameTooltip:AddLine(ns.options.enabled and "Highlights enabled" or "Highlights disabled", 1, 1, 1)
            GameTooltip:AddLine("! Red: restriction", 1, 0.15, 0.12)
            GameTooltip:AddLine("P/! Orange: skill / profession or lower weapon DPS", 1, 0.48, 0.08)
            GameTooltip:AddLine("L Yellow: level only", 1, 0.8, 0.12)
            GameTooltip:AddLine("+ Green: usable gear/bag", 0.2, 0.9, 0.4)
            GameTooltip:AddLine("Left-click: options. Right-click: toggle.", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("Drag to move around the minimap.", 0.9, 0.9, 0.9)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:SetScript("OnDragStart", function(self)
            self.dragged = true
            GameTooltip:Hide()
            self:SetScript("OnUpdate", function()
                local getCursor = C_Cursor and C_Cursor.GetCursorPosition or GetCursorPosition
                local x, y = getCursor()
                local centerX, centerY = Minimap:GetCenter()
                if not centerX or not centerY then return end
                local scale = Minimap:GetEffectiveScale()
                ns.options.minimapAngle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX))
                UpdatePosition()
            end)
        end)
        button:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            C_Timer.After(0, function() self.dragged = false end)
        end)
        Minimap:HookScript("OnSizeChanged", UpdatePosition)
    end
    UpdatePosition()
    button:SetShown(ns.options.showMinimap)
    SyncCheckboxes()
end
