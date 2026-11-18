-- CVar Browser. Size presets and the Size menu popup, pixel snapping, and UI
-- scale.

local _, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local CreateFrame = CreateFrame
local UIParent = UIParent
local GetPhysicalScreenSize = GetPhysicalScreenSize
local ipairs = ipairs
local min, max, abs = math.min, math.max, math.abs

-- Shared from earlier files --------------------------------------------------

local g_frame = ns.g_frame
local FONT_CHECK_PATH = ns.FONT_CHECK_PATH
local FONT_REGULAR_PATH = ns.FONT_REGULAR_PATH
local FONT_SEMIBOLD_PATH = ns.FONT_SEMIBOLD_PATH
local METRICS = ns.METRICS
local ROW_COUNT = ns.ROW_COUNT
local GAUGE_WIDTH = ns.GAUGE_WIDTH
local COLORS = ns.COLORS
local resize_font = ns.resize_font
local FONT_TITLE = ns.FONT_TITLE
local FONT_DETAIL = ns.FONT_DETAIL
local FONT_BODY = ns.FONT_BODY
local FONT_META = ns.FONT_META
local FONT_CHECK = ns.FONT_CHECK
local round = ns.round
local make_text = ns.make_text
local set_texture_color = ns.set_texture_color
local set_text_color = ns.set_text_color
local apply_backdrop = ns.apply_backdrop
local snap_texture = ns.snap_texture
local g_hairline = ns.g_hairline
local g_close_button = ns.g_close_button
local g_scale_button = ns.g_scale_button
local g_scroll_frame = ns.g_scroll_frame
local g_scroll_child = ns.g_scroll_child
local g_scrollbar = ns.g_scrollbar
local g_rows = ns.g_rows
local g_detail_separator = ns.g_detail_separator
local g_detail = ns.g_detail
local g_detail_name = ns.g_detail_name
local g_detail_meta = ns.g_detail_meta
local g_detail_help = ns.g_detail_help
local g_detail_edit_frame = ns.g_detail_edit_frame
local g_set_button = ns.g_set_button
local g_reset_button = ns.g_reset_button
local g_detail_status = ns.g_detail_status

-- Size presets. Auto picks one from the physical screen height.
local LAYOUT_PRESETS = {
    compact = {
        width = 800,
        height = 600,
        detail_height = 124,
        title = 18,
        detail = 13,
        body = 12,
        meta = 10,
        check = 12,
    },
    standard = {
        width = 920,
        height = 680,
        detail_height = 132,
        title = 20,
        detail = 15,
        body = 13,
        meta = 11,
        check = 14,
    },
    large = {
        width = 1040,
        height = 760,
        detail_height = 148,
        title = 23,
        detail = 17,
        body = 15,
        meta = 12,
        check = 16,
    },
}
local LAYOUT_OPTIONS = {
    { value = "auto", label = "Auto" },
    { value = "compact", label = "Compact" },
    { value = "standard", label = "Standard" },
    { value = "large", label = "Large" },
}
local g_scale_popup = nil
local g_scale_rows = {}

g_scale_popup = CreateFrame("Frame", nil, g_frame, "BackdropTemplate")
g_scale_popup:SetSize(126, #LAYOUT_OPTIONS * 22 + 2)
g_scale_popup:SetPoint("TOPRIGHT", g_scale_button, "BOTTOMRIGHT", 0, -4)
g_scale_popup:SetFrameLevel(g_frame:GetFrameLevel() + 20)
apply_backdrop(g_scale_popup, COLORS.surface, COLORS.border)
g_scale_popup:Hide()
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_scale_popup

-- The Size popup is one more menu, so closing the toolbar menus (Escape, an
-- outside click, another menu opening, the window showing) closes it too.
do
    local close_toolbar_menus = g_frame.close_menus
    g_frame.close_menus = function()
        g_scale_popup:Hide()
        close_toolbar_menus()
    end
end

for index, option in ipairs(LAYOUT_OPTIONS) do
    local row = CreateFrame("Button", nil, g_scale_popup)
    row:SetSize(124, 22)
    row:SetPoint(
        "TOPLEFT",
        g_scale_popup,
        "TOPLEFT",
        1,
        -(1 + (index - 1) * 22)
    )
    local hover = snap_texture(row:CreateTexture(nil, "BACKGROUND"))
    hover:SetAllPoints(row)
    set_texture_color(hover, COLORS.hover)
    hover:Hide()
    row.hover = hover
    local selected_bar = snap_texture(row:CreateTexture(nil, "ARTWORK"))
    set_texture_color(selected_bar, COLORS.accent)
    selected_bar:SetWidth(2)
    selected_bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    selected_bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    selected_bar:Hide()
    row.selected_bar = selected_bar
    row.label = make_text(row, FONT_META, option.label, COLORS.text)
    row.label:SetPoint("LEFT", row, "LEFT", 9, 0)
    row.option = option
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
    end)
    g_scale_rows[#g_scale_rows + 1] = row
end

local function resolve_layout(physical_height)
    local preset_key = g_frame.db and g_frame.db.preset or "auto"
    if preset_key ~= "auto" and LAYOUT_PRESETS[preset_key] then
        return LAYOUT_PRESETS[preset_key]
    end
    if physical_height <= 1080 then
        return LAYOUT_PRESETS.compact
    elseif physical_height >= 1800 then
        return LAYOUT_PRESETS.large
    end
    return LAYOUT_PRESETS.standard
end

-- Snug label fit with 4px text padding from the outline on each side and a
-- caller-supplied floor so tiny buttons never collapse absurdly narrow.
-- Re-run after font resizes.
local function fit_text_button(button, minimum)
    if not button or not button.label then
        return
    end
    local width = button.label:GetStringWidth() + 8
    if minimum and minimum > width then
        width = minimum
    end
    button:SetWidth(round(width))
end

local function update_scale_button()
    local preset_key = g_frame.db and g_frame.db.preset or "auto"
    local label = LAYOUT_OPTIONS[1].label
    for _, row in ipairs(g_scale_rows) do
        local selected = row.option.value == preset_key
        set_text_color(row.label, selected and COLORS.accent or COLORS.text)
        row.selected_bar:SetShown(selected)
        if selected then
            label = row.option.label
        end
    end
    g_scale_button.label:SetText("Size: " .. label)
    fit_text_button(g_scale_button)
end

-- Physical pixels per frame unit, measured rather than assumed. A probe of
-- known unit width reports its GetScaledRect in 768-space screen units, and
-- one screen unit is physicalHeight/768 pixels. Measuring catches clients
-- that compose the parent's scale into the frame despite
-- SetIgnoreParentScale, where one unit renders at parentScale pixels.
local function measure_px_per_unit(physical_height)
    if not g_frame.GetScaledRect then
        return nil
    end
    if not g_frame.px_probe then
        g_frame.px_probe = g_frame:CreateTexture(nil, "ARTWORK")
        g_frame.px_probe:Hide()
    end
    local probe = g_frame.px_probe
    probe:ClearAllPoints()
    probe:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 0, 0)
    probe:SetWidth(100)
    probe:SetHeight(100)
    probe:Show()
    local _, _, scaled_width = probe:GetScaledRect()
    probe:Hide()
    probe:ClearAllPoints()
    if not scaled_width or scaled_width <= 0 then
        return nil
    end
    -- Screen units to physical pixels, at height/768 px per screen unit.
    return scaled_width * physical_height / 768 / 100
end

local function snap_frame_position()
    if not g_frame:IsShown() then
        return
    end
    -- Snap the frame's physical-pixel origin to the nearest whole pixel by
    -- shifting the anchor, then re-measure and mop up any residual. GetLeft/
    -- GetTop and SetPoint offsets are both frame units (verified in game, a
    -- +10 offset moved GetLeft by exactly 10 with UIParent at 1.556 px per
    -- unit), so g_frame.px_per_unit converts both ways. Landing the origin on a
    -- whole pixel keeps 1-unit hairlines on exactly one pixel and the font
    -- raster phase stable. A fractional phase is what made the header text
    -- drift between 1px and 2px above the separator after a drag release.
    -- GetScaledRect is not usable here. It returns 768-space screen units
    -- (GetRect times effective scale), not pixels, and its second return is
    -- the bottom edge.
    local px_per_unit = g_frame.px_per_unit
    if not px_per_unit or px_per_unit <= 0 then
        return
    end
    local point, relative_to, relative_point, x, y = g_frame:GetPoint(1)
    if not point then
        return
    end
    x = x or 0
    y = y or 0
    for _ = 1, 2 do
        local left = g_frame:GetLeft()
        local top = g_frame:GetTop()
        if not left or not top then
            return
        end
        local left_px = left * px_per_unit
        local top_px = top * px_per_unit
        local dx_px = round(left_px) - left_px
        local dy_px = round(top_px) - top_px
        if abs(dx_px) < 0.001 and abs(dy_px) < 0.001 then
            break
        end
        x = x + dx_px / px_per_unit
        y = y + dy_px / px_per_unit
        g_frame:ClearAllPoints()
        g_frame:SetPoint(
            point,
            relative_to or UIParent,
            relative_point or "CENTER",
            x,
            y
        )
    end
    if g_frame.db then
        g_frame.db.x = x
        g_frame.db.y = y
    end
end

local function apply_ui_scale()
    local _, physical_height = GetPhysicalScreenSize()
    if not physical_height or physical_height <= 0 then
        physical_height = 1440
    end
    local preset = resolve_layout(physical_height)
    if g_frame.SetIgnoreParentScale then
        g_frame:SetIgnoreParentScale(true)
    end
    -- The target is one frame unit == one physical pixel. Screen space is
    -- 768 units over the physical screen, so an effective scale of 768/height
    -- is pixel-perfect wherever SetIgnoreParentScale is honored. Scale
    -- composition is multiplicative, so one corrective pass using the
    -- measured px per unit converges.
    local perfect_scale = 768 / physical_height
    g_frame:SetScale(perfect_scale)
    local px_per_unit = measure_px_per_unit(physical_height)
    if px_per_unit and px_per_unit > 0 and abs(px_per_unit - 1) > 1e-3 then
        g_frame:SetScale((g_frame:GetScale() or perfect_scale) / px_per_unit)
        px_per_unit = measure_px_per_unit(physical_height) or px_per_unit
    end
    if not px_per_unit or px_per_unit <= 0 then
        px_per_unit = 1
    end
    g_frame.px_per_unit = px_per_unit
    g_frame:SetSize(preset.width, preset.height)

    resize_font(FONT_TITLE, FONT_SEMIBOLD_PATH, preset.title)
    resize_font(FONT_DETAIL, FONT_SEMIBOLD_PATH, preset.detail)
    resize_font(FONT_BODY, FONT_REGULAR_PATH, preset.body)
    resize_font(FONT_META, FONT_REGULAR_PATH, preset.meta)
    resize_font(FONT_CHECK, FONT_CHECK_PATH, preset.check)
    g_frame.layout_key_row()
    -- Refit snug text buttons after font sizes settle. The floors are
    -- roughly the button height.
    fit_text_button(g_set_button, 30)
    fit_text_button(g_reset_button, 64)
    fit_text_button(g_frame.copy_button, 30)
    fit_text_button(g_frame.filter_clear, 40)
    fit_text_button(g_close_button, 24)
    fit_text_button(g_frame.undo_button, 24)
    fit_text_button(g_frame.redo_button, 24)

    METRICS.detail_width = preset.width - 48
    METRICS.list_width = preset.width - METRICS.list_left - METRICS.list_right
    METRICS.list_bottom = preset.detail_height + 56
    METRICS.list_height = preset.height - METRICS.list_top - METRICS.list_bottom

    g_scroll_child:SetWidth(METRICS.list_width)
    -- The value column runs from the row's right edge (6px inset) to 10px
    -- short of the centered gauge, and the name column mirrors it but starts
    -- after the 22px favorite toggle. Font strings truncate with an ellipsis
    -- at that width. A fixed character cap cut names off early.
    local column_width = round(METRICS.list_width / 2 - GAUGE_WIDTH / 2 - 16)
    for index = 1, ROW_COUNT do
        g_rows[index].name_text:SetWidth(column_width - 16)
        g_rows[index].value_text:SetWidth(column_width)
    end
    g_scroll_frame:SetPoint(
        "BOTTOMRIGHT",
        g_frame,
        "BOTTOMRIGHT",
        -METRICS.list_right,
        METRICS.list_bottom
    )
    g_scrollbar:SetPoint(
        "BOTTOMRIGHT",
        g_frame,
        "BOTTOMRIGHT",
        -24,
        METRICS.list_bottom
    )

    local separator_y = preset.height - preset.detail_height - 52
    local detail_y = preset.height - preset.detail_height - 44
    g_detail_separator:ClearAllPoints()
    g_detail_separator:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 24, -separator_y)
    g_detail_separator:SetPoint(
        "TOPRIGHT",
        g_frame,
        "TOPRIGHT",
        -24,
        -separator_y
    )
    g_detail:ClearAllPoints()
    g_detail:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 24, -detail_y)
    g_detail:SetPoint("BOTTOMRIGHT", g_frame, "BOTTOMRIGHT", -24, 44)
    g_detail_name:SetWidth(METRICS.detail_width)
    g_detail_help:SetWidth(METRICS.detail_width)
    g_detail_meta:SetSize(METRICS.detail_width, 14)
    g_frame.filter_popup:SetHeight(min(500, preset.height - 136))
    -- The status line runs from 12px after Reset to the detail area's right
    -- edge, which is the window's 24px right padding. The buttons were
    -- refit above, so their widths are current.
    g_detail_status:SetWidth(max(120, METRICS.detail_width - (
        g_detail_edit_frame:GetWidth() + 8
        + g_set_button:GetWidth() + 8
        + g_reset_button:GetWidth() + 12
    )))

    g_frame.update_filter_chip()
    g_frame.update_sort_chip()
    update_scale_button()
    -- Hairlines resize to exactly one physical pixel via the measured
    -- physical-px-per-unit (g_frame.px_per_unit, validated above).
    g_hairline.set_scale(g_frame.px_per_unit)
    snap_frame_position()
    for _, region in ipairs(g_frame.snap_lines) do
        g_frame.snap_line(region)
    end
    for _, region in ipairs(g_frame.snap_boxes) do
        g_frame.snap_box(region)
    end
    g_frame.snap_region_tree(g_frame)
end

local function set_layout(value)
    if g_frame.db then
        g_frame.db.preset = value
    end
    g_frame.close_menus()
end

local function toggle_scale_popup()
    if g_scale_popup:IsShown() then
        g_frame.close_menus()
    else
        g_frame.close_menus()
        g_frame.hide_tooltip()
        update_scale_button()
        g_frame.menu_catcher:Show()
        g_scale_popup:Show()
        g_frame.snap_box(g_scale_popup)
        g_scale_popup:Raise()
    end
end

-- Shared with the files loaded after this one.
ns.g_scale_rows = g_scale_rows
ns.snap_frame_position = snap_frame_position
ns.apply_ui_scale = apply_ui_scale
ns.set_layout = set_layout
ns.toggle_scale_popup = toggle_scale_popup
