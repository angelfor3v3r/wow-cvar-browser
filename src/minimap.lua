-- CVar Browser. The minimap button and the Addon Compartment entry.

local _, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local CreateFrame = CreateFrame
local UIParent = UIParent
local GameTooltip = GameTooltip
local Minimap = Minimap
local GetCursorPosition = GetCursorPosition
local rad, deg = math.rad, math.deg
local cos, sin, atan2 = math.cos, math.sin, math.atan2

-- Shared from earlier files --------------------------------------------------

local g_frame = ns.g_frame

-- Minimap button -------------------------------------------------------------

if Minimap then
    g_frame.minimap_button = CreateFrame(
        "Button",
        "CVarBrowserMinimapButton",
        Minimap
    )
    g_frame.minimap_button:SetSize(32, 32)
    g_frame.minimap_button:SetFrameStrata("MEDIUM")
    g_frame.minimap_button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    g_frame.minimap_button:RegisterForClicks("LeftButtonUp")
    g_frame.minimap_button:RegisterForDrag("LeftButton")
    g_frame.minimap_button:SetMovable(true)

    g_frame.minimap_button.border = g_frame.minimap_button:CreateTexture(
        nil,
        "OVERLAY"
    )
    g_frame.minimap_button.border:SetTexture(
        "Interface\\Minimap\\MiniMap-TrackingBorder"
    )
    g_frame.minimap_button.border:SetSize(54, 54)
    g_frame.minimap_button.border:SetPoint("TOPLEFT")

    -- Named <Button>Icon because minimap-button collectors (Leatrix Plus,
    -- Completao-style drawers, etc.) use this texture for their tile.
    g_frame.minimap_button.icon = g_frame.minimap_button:CreateTexture(
        "CVarBrowserMinimapButtonIcon",
        "ARTWORK"
    )
    g_frame.minimap_button.icon:SetTexture(
        "Interface\\Icons\\INV_Misc_Spyglass_02"
    )
    g_frame.minimap_button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    g_frame.minimap_button.icon:SetSize(20, 20)
    g_frame.minimap_button.icon:SetPoint("CENTER")

    g_frame.minimap_button.update_position = function(self)
        local angle = rad(g_frame.db and g_frame.db.minimap_angle or 220)
        local radius = 80
        self:ClearAllPoints()
        self:SetPoint(
            "CENTER",
            Minimap,
            "CENTER",
            cos(angle) * radius,
            sin(angle) * radius
        )
    end

    -- Follows the cursor around the minimap ring while the button is dragged.
    local function follow_cursor(self)
        local minimap_x, minimap_y = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        if not minimap_x or not scale or scale == 0 then
            return
        end
        local cursor_x, cursor_y = GetCursorPosition()
        cursor_x = cursor_x / scale
        cursor_y = cursor_y / scale
        local angle = deg(atan2(cursor_y - minimap_y, cursor_x - minimap_x))
        if g_frame.db then
            g_frame.db.minimap_angle = angle
        end
        self:update_position()
    end

    g_frame.minimap_button:SetScript("OnClick", function()
        g_frame:SetShown(not g_frame:IsShown())
    end)
    g_frame.minimap_button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("CVar Browser")
        GameTooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
        GameTooltip:Show()
    end)
    g_frame.minimap_button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    g_frame.minimap_button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", follow_cursor)
    end)
    g_frame.minimap_button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:update_position()
    end)
    g_frame.minimap_button:update_position()
end

-- Addon Compartment (Blizzard minimap drawer, also used by collectors) -------

function CVarBrowser_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton ~= "LeftButton" then
        return
    end
    g_frame:SetShown(not g_frame:IsShown())
end

function CVarBrowser_OnAddonCompartmentEnter(_, owner)
    GameTooltip:SetOwner(owner or UIParent, "ANCHOR_LEFT")
    GameTooltip:AddLine("CVar Browser")
    GameTooltip:AddLine("Click to open.", 1, 1, 1)
    GameTooltip:Show()
end

function CVarBrowser_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
