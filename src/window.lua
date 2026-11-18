-- CVar Browser. Root window setup, smooth scrolling, the title bar,
-- the search row, and the Changed only toggle.

local g_addon_name, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local CreateFrame = CreateFrame
local min, abs = math.min, math.abs
local insert = table.insert
local UISpecialFrames = UISpecialFrames

-- Shared from earlier files --------------------------------------------------

local g_frame = ns.g_frame
local METRICS = ns.METRICS
local COLORS = ns.COLORS
local FONT_TITLE = ns.FONT_TITLE
local FONT_BODY = ns.FONT_BODY
local FONT_META = ns.FONT_META
local FONT_CHECK = ns.FONT_CHECK
local trim = ns.trim
local clamp = ns.clamp
local round = ns.round
local make_text = ns.make_text
local apply_backdrop = ns.apply_backdrop
local snap_texture = ns.snap_texture
local set_texture_color = ns.set_texture_color
local set_text_color = ns.set_text_color
local g_hairline = ns.g_hairline
local add_border = ns.add_border
local create_button = ns.create_button

g_frame:SetSize(METRICS.frame_width, METRICS.frame_height)
g_frame:SetPoint("CENTER")
g_frame:SetFrameStrata("DIALOG")
g_frame:SetMovable(true)
g_frame:SetClampedToScreen(true)
g_frame:EnableMouse(true)
g_frame:Hide()
apply_backdrop(g_frame, COLORS.background, COLORS.border)
insert(UISpecialFrames, "CVarBrowserFrame")

-- Smooth-scroll step for any ScrollFrame. It eases toward self.scroll_target
-- in whole-pixel steps (at least 1px per frame) and stops on the target.
local function smooth_step(self, elapsed)
    local target = self.scroll_target
    if not target then
        self:SetScript("OnUpdate", nil)
        return
    end
    local current = self:GetVerticalScroll() or 0
    local diff = target - current
    local px = g_frame.px_per_unit
    if abs(diff) * px < 1 then
        self.scroll_target = nil
        self:SetScript("OnUpdate", nil)
        self:SetVerticalScroll(target)
        return
    end
    local step = round(diff * min(1, elapsed * 16) * px) / px
    if step == 0 then
        step = (diff > 0 and 1 or -1) / px
    end
    self:SetVerticalScroll(current + step)
end

-- Scrolls any ScrollFrame to a whole-pixel offset, gliding there when
-- smooth is requested and enabled. Whole-pixel offsets keep row text on
-- the pixel grid against the clip edge. A fractional offset left rows at
-- half pixels that rounded differently depending on the window position.
g_frame.scroll_frame_to = function(scroll, value, smooth)
    local px = g_frame.px_per_unit
    local range = scroll:GetVerticalScrollRange() or 0
    local target = clamp(round(value * px) / px, 0, range)
    if smooth and g_frame.db and g_frame.db.smooth_scroll then
        scroll.scroll_target = target
        scroll:SetScript("OnUpdate", smooth_step)
        return
    end
    scroll.scroll_target = nil
    scroll:SetScript("OnUpdate", nil)
    scroll:SetVerticalScroll(target)
end

local g_titlebar = CreateFrame("Frame", nil, g_frame)
g_titlebar:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 1, -1)
g_titlebar:SetPoint("TOPRIGHT", g_frame, "TOPRIGHT", -1, -1)
g_titlebar:SetHeight(44)
g_titlebar:EnableMouse(true)
g_frame.snap_lines[#g_frame.snap_lines + 1] = g_titlebar

do
    local titlebar_border = snap_texture(
        g_titlebar:CreateTexture(nil, "ARTWORK")
    )
    set_texture_color(titlebar_border, COLORS.border)
    titlebar_border:SetPoint("BOTTOMLEFT", g_titlebar, "BOTTOMLEFT", 0, 0)
    titlebar_border:SetPoint("BOTTOMRIGHT", g_titlebar, "BOTTOMRIGHT", 0, 0)
    g_hairline.register(titlebar_border, "height")

    local brand_bar = snap_texture(g_titlebar:CreateTexture(nil, "ARTWORK"))
    set_texture_color(brand_bar, COLORS.accent)
    brand_bar:SetSize(3, 18)
    brand_bar:SetPoint("LEFT", g_titlebar, "LEFT", 24, 0)

    local title = make_text(g_titlebar, FONT_TITLE, "CVar Browser", COLORS.text)
    title:SetPoint("LEFT", g_titlebar, "LEFT", 39, 0)

    -- The subtitle carries the build. Release zips have the TOC Version and
    -- X-Build ("<hash> <date>") stamped by CI, giving "WoW Forever · v1.0.1
    -- · afaa9bd". A copy of the repository says "dev" instead. The rules
    -- follow DESIGN.md (Subtitle).
    local get_metadata = (C_AddOns and C_AddOns.GetAddOnMetadata)
        or GetAddOnMetadata
    local version = trim(get_metadata and get_metadata(g_addon_name, "Version"))
    local build = trim(get_metadata and get_metadata(g_addon_name, "X-Build"))
    local subtitle_text = "WoW Forever · dev"
    if version ~= "" and version:lower() ~= "dev" then
        subtitle_text = "WoW Forever · v" .. version:gsub("^[vV]", "")
        local hash = build:match("^(%S+)")
        if hash and hash:match("^%x+$") then
            subtitle_text = subtitle_text .. " · " .. hash
        end
    end

    local subtitle = make_text(g_titlebar, FONT_META, subtitle_text, COLORS.muted)
    subtitle:SetPoint("LEFT", title, "RIGHT", 12, 0)
    subtitle:SetJustifyV("MIDDLE")
end

local g_scale_button = create_button(g_titlebar, "Size: Standard", 112, 24)
g_scale_button:SetPoint("RIGHT", g_titlebar, "RIGHT", -52, 0)
g_scale_button.label:SetFontObject(FONT_META)
set_text_color(g_scale_button.label, COLORS.muted)
g_scale_button.label:ClearAllPoints()
g_scale_button.label:SetPoint("LEFT", g_scale_button, "LEFT", 4, 0)
g_scale_button.label:SetJustifyH("LEFT")
g_scale_button:SetScript("OnEnter", function(self)
    set_texture_color(self.background, COLORS.hover)
    g_hairline.set_color(self.borders, COLORS.accent)
    set_text_color(self.label, COLORS.text)
end)
g_scale_button:SetScript("OnLeave", function(self)
    set_texture_color(self.background, COLORS.surface)
    g_hairline.set_color(self.borders, COLORS.border)
    set_text_color(self.label, COLORS.muted)
end)
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_scale_button

local g_close_button = CreateFrame("Button", nil, g_titlebar)
g_close_button:SetSize(28, 28)
g_close_button:SetPoint("RIGHT", g_titlebar, "RIGHT", -16, 0)
g_close_button.label = make_text(g_close_button, FONT_TITLE, "×", COLORS.muted)
g_close_button.label:SetPoint("CENTER", g_close_button, "CENTER", 0, 0)
g_close_button:SetScript("OnEnter", function(self)
    set_text_color(self.label, COLORS.error)
end)
g_close_button:SetScript("OnLeave", function(self)
    set_text_color(self.label, COLORS.muted)
end)

local g_search_frame = CreateFrame("Frame", nil, g_frame, "BackdropTemplate")
g_search_frame:SetSize(300, 32)
g_search_frame:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 24, -58)
apply_backdrop(g_search_frame, COLORS.surface, COLORS.border)
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_search_frame

local g_search_box = CreateFrame("EditBox", nil, g_search_frame)
g_search_box:SetPoint("TOPLEFT", g_search_frame, "TOPLEFT", 10, 0)
g_search_box:SetPoint("BOTTOMRIGHT", g_search_frame, "BOTTOMRIGHT", -10, 0)
g_search_box:SetAutoFocus(false)
g_search_box:SetFontObject(FONT_BODY)
set_text_color(g_search_box, COLORS.text)
g_search_box:SetTextInsets(12, 0, 0, 0)

do
    local search_icon = g_search_frame:CreateTexture(nil, "ARTWORK")
    search_icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    search_icon:SetSize(14, 14)
    search_icon:SetPoint("LEFT", g_search_frame, "LEFT", 4, 0)
    search_icon:SetVertexColor(
        COLORS.muted[1],
        COLORS.muted[2],
        COLORS.muted[3],
        1
    )
end

local g_search_placeholder = make_text(
    g_search_frame,
    FONT_BODY,
    "Search CVars",
    COLORS.muted
)
g_search_placeholder:SetPoint("LEFT", g_search_frame, "LEFT", 22, 0)
g_search_placeholder:SetJustifyH("LEFT")

g_frame.regex_chip = create_button(g_frame, ".*", 26, 26)
g_frame.regex_chip:SetPoint("LEFT", g_search_frame, "RIGHT", 16, 0)
g_frame.regex_chip.label:SetFontObject(FONT_META)
g_frame.regex_chip.underline = snap_texture(
    g_frame.regex_chip:CreateTexture(nil, "ARTWORK")
)
set_texture_color(g_frame.regex_chip.underline, COLORS.accent)
g_frame.regex_chip.underline:SetPoint(
    "BOTTOMLEFT",
    g_frame.regex_chip,
    "BOTTOMLEFT",
    2,
    0
)
g_frame.regex_chip.underline:SetPoint(
    "BOTTOMRIGHT",
    g_frame.regex_chip,
    "BOTTOMRIGHT",
    -2,
    0
)
g_hairline.register(g_frame.regex_chip.underline, "height")
g_frame.regex_chip.underline:Hide()
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_frame.regex_chip

local g_changed_button = CreateFrame("Button", nil, g_frame)
g_changed_button:SetSize(160, 32)
g_changed_button:SetPoint("LEFT", g_frame.regex_chip, "RIGHT", 16, 0)
g_changed_button.checked = false
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_changed_button

local g_changed_box = CreateFrame("Frame", nil, g_changed_button)
g_changed_box:SetSize(18, 18)
g_changed_box:SetPoint("LEFT", g_changed_button, "LEFT", 0, 0)
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_changed_box

do
    local changed_box_background = snap_texture(
        g_changed_box:CreateTexture(nil, "BACKGROUND")
    )
    changed_box_background:SetAllPoints(g_changed_box)
    set_texture_color(changed_box_background, COLORS.surface)
end

add_border(g_changed_box, COLORS.border)

local g_changed_tick = make_text(g_changed_box, FONT_CHECK, "✓", COLORS.accent)
g_changed_tick:SetPoint("CENTER", g_changed_box, "CENTER", 1, 0)
g_changed_tick:Hide()

do
    local changed_label = make_text(
        g_changed_button,
        FONT_BODY,
        "Changed only",
        COLORS.text
    )
    changed_label:SetPoint("LEFT", g_changed_box, "RIGHT", 8, 0)
end

local g_count_text = make_text(g_frame, FONT_META, "", COLORS.muted)
g_count_text:SetPoint("TOPRIGHT", g_frame, "TOPRIGHT", -24, -67)
g_count_text:SetJustifyH("RIGHT")

-- Shared with the files loaded after this one.
ns.g_titlebar = g_titlebar
ns.g_close_button = g_close_button
ns.g_scale_button = g_scale_button
ns.g_search_frame = g_search_frame
ns.g_search_box = g_search_box
ns.g_search_placeholder = g_search_placeholder
ns.g_changed_button = g_changed_button
ns.g_changed_tick = g_changed_tick
ns.g_count_text = g_count_text
