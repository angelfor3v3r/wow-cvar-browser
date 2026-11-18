-- CVar Browser. The list header, scroll frame, scrollbar, pooled
-- rows, favorite toggle, and row tooltip.

local _, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local CreateFrame = CreateFrame
local ipairs = ipairs
local tostring = tostring
local floor, min, max = math.floor, math.min, math.max
local format = string.format

-- Shared from earlier files --------------------------------------------------

local g_frame = ns.g_frame
local METRICS = ns.METRICS
local ROW_HEIGHT = ns.ROW_HEIGHT
local ROW_COUNT = ns.ROW_COUNT
local GAUGE_WIDTH = ns.GAUGE_WIDTH
local COLORS = ns.COLORS
local FONT_BODY = ns.FONT_BODY
local FONT_META = ns.FONT_META
local make_text = ns.make_text
local set_texture_color = ns.set_texture_color
local set_text_color = ns.set_text_color
local snap_texture = ns.snap_texture
local g_hairline = ns.g_hairline
local add_border = ns.add_border
local g_scroll_frame = nil
local g_scroll_child = nil
local g_scrollbar = nil
local g_scrollbar_thumb = nil
local g_rows = {}

do
    local header = CreateFrame("Frame", nil, g_frame)
    header:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 24, -132)
    header:SetPoint("TOPRIGHT", g_frame, "TOPRIGHT", -48, -132)
    header:SetHeight(16)
    g_frame.snap_lines[#g_frame.snap_lines + 1] = header
    local header_border = snap_texture(header:CreateTexture(nil, "ARTWORK"))
    set_texture_color(header_border, COLORS.border)
    header_border:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header_border:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 24, 0)
    g_hairline.register(header_border, "height")

    local header_name = make_text(header, FONT_META, "CVar", COLORS.muted)
    header_name:SetPoint("LEFT", header, "LEFT", 22, 1)

    local header_gauge = make_text(header, FONT_META, "Gauge", COLORS.muted)
    header_gauge:SetPoint("CENTER", header, "CENTER", 0, 1)

    local header_value = make_text(header, FONT_META, "Value", COLORS.muted)
    header_value:SetPoint("RIGHT", header, "RIGHT", -6, 1)
    header_value:SetJustifyH("RIGHT")
end

g_scroll_frame = CreateFrame("ScrollFrame", nil, g_frame)
g_scroll_frame:SetPoint(
    "TOPLEFT",
    g_frame,
    "TOPLEFT",
    METRICS.list_left,
    -METRICS.list_top
)
g_scroll_frame:SetPoint(
    "BOTTOMRIGHT",
    g_frame,
    "BOTTOMRIGHT",
    -METRICS.list_right,
    METRICS.list_bottom
)
g_scroll_frame:EnableMouseWheel(true)

g_scroll_child = CreateFrame("Frame", nil, g_scroll_frame)
g_scroll_child:SetWidth(METRICS.list_width)
g_scroll_child:SetHeight(1)
g_scroll_frame:SetScrollChild(g_scroll_child)

g_scrollbar = CreateFrame("Frame", nil, g_frame)
g_scrollbar:SetPoint("TOPRIGHT", g_frame, "TOPRIGHT", -24, -METRICS.list_top)
g_scrollbar:SetPoint("BOTTOMRIGHT", g_frame, "BOTTOMRIGHT", -24, METRICS.list_bottom)
g_scrollbar:SetWidth(8)
do
    local scrollbar_track = snap_texture(g_scrollbar:CreateTexture(nil, "ARTWORK"))
    set_texture_color(scrollbar_track, COLORS.hover)
    scrollbar_track:SetPoint("TOP", g_scrollbar, "TOP", 0, 0)
    scrollbar_track:SetPoint("BOTTOM", g_scrollbar, "BOTTOM", 0, 0)
    scrollbar_track:SetWidth(4)
end

g_scrollbar_thumb = CreateFrame("Frame", nil, g_scrollbar)
g_scrollbar_thumb:SetWidth(8)
g_scrollbar_thumb.background = snap_texture(
    g_scrollbar_thumb:CreateTexture(nil, "ARTWORK")
)
g_scrollbar_thumb.background:SetAllPoints(g_scrollbar_thumb)
set_texture_color(g_scrollbar_thumb.background, COLORS.muted)

-- Builds the 7x7 favorite diamond from 1px tall textures. The first 12
-- pieces are the outline and the last 5 fill the inside.
g_frame.create_diamond = function(parent)
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(7, 7)
    mark.outline = {}
    mark.interior = {}
    local pieces = {
        { 3, 0, 1 }, { 2, 1, 1 }, { 4, 1, 1 }, { 1, 2, 1 }, { 5, 2, 1 },
        { 0, 3, 1 }, { 6, 3, 1 }, { 1, 4, 1 }, { 5, 4, 1 }, { 2, 5, 1 },
        { 4, 5, 1 }, { 3, 6, 1 },
        { 3, 1, 1 }, { 2, 2, 3 }, { 1, 3, 5 }, { 2, 4, 3 }, { 3, 5, 1 },
    }
    for index, piece in ipairs(pieces) do
        local texture = snap_texture(mark:CreateTexture(nil, "ARTWORK"))
        texture:SetSize(piece[3], 1)
        texture:SetPoint("TOPLEFT", mark, "TOPLEFT", piece[1], -piece[2])
        local list = index <= 12 and mark.outline or mark.interior
        list[#list + 1] = texture
    end
    return mark
end

-- Colors the diamond, or hides it when color is nil. The inside shows only
-- when filled is true. Repainting with the same color and fill is skipped.
g_frame.paint_diamond = function(mark, color, filled)
    mark:SetShown(color ~= nil)
    if not color then
        return
    end
    if mark.painted_color == color and mark.painted_filled == (filled == true) then
        return
    end
    mark.painted_color = color
    mark.painted_filled = filled == true
    for _, texture in ipairs(mark.outline) do
        set_texture_color(texture, color)
    end
    for _, texture in ipairs(mark.interior) do
        set_texture_color(texture, color)
        texture:SetShown(filled == true)
    end
end

-- Row construction helpers are scoped to this block because they are only
-- needed while the pooled rows are built.
do
    local function create_slant_text(parent, text)
        local label = make_text(parent, FONT_META, text, COLORS.muted)
        label:SetAlpha(0.8)
        return label
    end

    local function create_gauge(parent)
        local gauge = CreateFrame("Frame", nil, parent)
        gauge:SetSize(GAUGE_WIDTH, METRICS.gauge_height)

        local track = snap_texture(gauge:CreateTexture(nil, "ARTWORK"))
        set_texture_color(track, COLORS.border)
        -- Every mark sits at whole-pixel offsets from the gauge's top-left
        -- corner. Centering a 1px line or a 3px mark in the 8px gauge put
        -- its edges on half pixels, which drew it 0 or 2px thick depending
        -- on where the row scrolled to.
        track:SetHeight(1)
        track:SetPoint("TOPLEFT", gauge, "TOPLEFT", 0, -3)
        track:SetPoint("TOPRIGHT", gauge, "TOPRIGHT", 0, -3)

        local function make_mark(width, height, color)
            local mark = snap_texture(gauge:CreateTexture(nil, "ARTWORK"))
            set_texture_color(mark, color)
            mark:SetSize(width, height)
            mark.mark_width = width
            mark.mark_height = height
            mark:Hide()
            return mark
        end

        local help_min = make_mark(1, 3, COLORS.muted)
        local help_max = make_mark(1, 3, COLORS.muted)
        local observed_min = make_mark(1, 6, COLORS.observed)
        local observed_max = make_mark(1, 6, COLORS.observed)
        local cursor = make_mark(2, 8, COLORS.text)
        local clamp_mark = make_mark(2, 8, COLORS.warning)
        local dot = make_mark(2, 2, COLORS.dot)
        dot:SetPoint("TOPLEFT", gauge, "TOPLEFT", GAUGE_WIDTH / 2 - 1, -3)

        local open_left = create_slant_text(gauge, "/")
        local open_right = create_slant_text(gauge, "\\")
        open_left:Hide()
        open_right:Hide()

        return {
            frame = gauge,
            track = track,
            help_min = help_min,
            help_max = help_max,
            observed_min = observed_min,
            observed_max = observed_max,
            cursor = cursor,
            clamp = clamp_mark,
            dot = dot,
            open_left = open_left,
            open_right = open_right,
        }
    end

    local function create_row()
        local row = CreateFrame("Button", nil, g_scroll_child)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)

        local hover = snap_texture(row:CreateTexture(nil, "BACKGROUND"))
        hover:SetAllPoints(row)
        set_texture_color(hover, COLORS.hover)
        hover:Hide()

        local selected_background = snap_texture(row:CreateTexture(nil, "BACKGROUND"))
        selected_background:SetAllPoints(row)
        set_texture_color(selected_background, COLORS.accent, 0.14)
        selected_background:Hide()

        local selected_bar = snap_texture(row:CreateTexture(nil, "ARTWORK"))
        set_texture_color(selected_bar, COLORS.accent)
        selected_bar:SetWidth(2)
        selected_bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        selected_bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        selected_bar:Hide()

        local name_text = make_text(row, FONT_BODY, "", COLORS.text)
        name_text:SetPoint("LEFT", row, "LEFT", 22, 0)
        name_text:SetWidth(284)
        name_text:SetJustifyH("LEFT")
        name_text:SetWordWrap(false)

        local gauge = create_gauge(row)
        gauge.frame:SetPoint("CENTER", row, "CENTER", 0, 0)

        local value_text = make_text(row, FONT_BODY, "", COLORS.text)
        value_text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        value_text:SetWidth(300)
        value_text:SetJustifyH("RIGHT")
        value_text:SetWordWrap(false)

        row.hover = hover
        row.selected_background = selected_background
        row.selected_bar = selected_bar
        row.name_text = name_text
        row.value_text = value_text
        row.gauge = gauge

        -- The favorite toggle covers the row's first 22px, left of the name.
        local favorite = CreateFrame("Button", nil, row)
        favorite:SetSize(ROW_HEIGHT, ROW_HEIGHT)
        favorite:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        favorite:SetFrameLevel(row:GetFrameLevel() + 1)
        favorite:RegisterForClicks("LeftButtonUp")
        favorite.mark = g_frame.create_diamond(favorite)
        favorite.mark:SetPoint("TOPLEFT", favorite, "TOPLEFT", 7, -8)
        favorite.mark:Hide()
        row.favorite = favorite
        return row
    end

    for index = 1, ROW_COUNT do
        g_rows[index] = create_row()
    end
end

-- Tooltip panel for rows, favorite toggles, and the toolbar controls that
-- carry a tooltip_text function. It shows after the pointer rests for 0.5s.
-- Within 0.1s of leaving a target, or while the panel is up, the next
-- target shows at once.
do
    local panel = CreateFrame("Frame", nil, g_frame)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(false)
    panel:Hide()
    panel.background = snap_texture(panel:CreateTexture(nil, "BACKGROUND"))
    panel.background:SetAllPoints(panel)
    set_texture_color(panel.background, COLORS.surface)
    add_border(panel, COLORS.border)

    -- Name, value, default, and help, each { font, max lines, gap above }.
    local line_specs = {
        { FONT_BODY, 2, 0 },
        { FONT_BODY, 4, 2 },
        { FONT_BODY, 2, 2 },
        { FONT_META, 8, 6 },
    }
    local lines = {}
    for index, spec in ipairs(line_specs) do
        local line = make_text(panel, spec[1], "", COLORS.text)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
        line:SetSpacing(2)
        line:SetMaxLines(spec[2])
        line.gap = spec[3]
        lines[index] = line
    end

    -- What the tooltip prints for a value. Line breaks become spaces, a
    -- blank value reads empty, and binary values show their size.
    local function describe(entry, raw)
        local text = tostring(raw or "")
        if entry.bitfield then
            return format("Bitfield (%d bytes)", #text)
        elseif entry.serialized then
            return format("Serialized (%d bytes)", #text)
        elseif text:match("^%s*$") then
            return "empty"
        end
        return (text:gsub("[\r\n]+", " "))
    end

    local function set_line(line, text, color, font)
        line:SetFontObject(font)
        line:SetText(text)
        set_text_color(line, color)
        line:Show()
    end

    -- Fills the lines for a row, or for its favorite toggle.
    local function fill_row(entry, over_toggle)
        if over_toggle then
            set_line(
                lines[1],
                entry.favorite and "Remove from favorites" or "Add to favorites",
                COLORS.text,
                FONT_META
            )
            return
        end
        local name_color = COLORS.text
        if entry.readonly then
            name_color = COLORS.muted
        elseif entry.changed then
            name_color = COLORS.changed
        end
        set_line(lines[1], entry.name, name_color, FONT_BODY)
        set_line(
            lines[2],
            "Value: " .. describe(entry, entry.value),
            COLORS.text,
            FONT_BODY
        )
        if entry.changed then
            set_line(
                lines[3],
                "Default: " .. describe(entry, entry.default_value),
                COLORS.muted,
                FONT_BODY
            )
        end
        if entry.help and not entry.help:match("^%s*$") then
            set_line(lines[4], entry.help, COLORS.text, FONT_META)
        end
    end

    -- Wraps every shown line at the widest one (capped at 320) and sizes the
    -- panel around them. Width 0 lets each line report its unwrapped width.
    -- Returns the panel height.
    local function fit_panel()
        local widest = 0
        for _, line in ipairs(lines) do
            if line:IsShown() then
                line:SetWidth(0)
                widest = max(widest, line:GetStringWidth() or 0)
            end
        end
        local width = min(320, floor(widest + 0.999))
        local y = 8
        local first = true
        for _, line in ipairs(lines) do
            if line:IsShown() then
                if not first then
                    y = y + line.gap
                end
                first = false
                line:SetWidth(width)
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -y)
                y = y + floor((line:GetStringHeight() or 0) + 0.999)
            end
        end
        local height = y + 8
        panel:SetSize(width + 16, height)
        return height
    end

    -- Shows the panel for a row or a control at once. A control carries a
    -- tooltip_text function that returns a title and a detail line with
    -- their colors, or nil for no tooltip.
    local function show_now(target, over_toggle)
        for _, line in ipairs(lines) do
            line:Hide()
        end
        panel:ClearAllPoints()
        if target.tooltip_text then
            local title, title_color, detail, detail_color = target.tooltip_text()
            if not title then
                panel:Hide()
                return
            end
            set_line(lines[1], title, title_color, FONT_BODY)
            set_line(lines[4], detail, detail_color, FONT_META)
            fit_panel()
            -- Controls sit near the window top, so the panel always hangs
            -- below, sharing the control's left edge.
            panel:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -4)
            panel:Show()
            return
        end
        if not target.entry then
            return
        end
        fill_row(target.entry, over_toggle)
        local height = fit_panel()
        -- Below the row with the text in line with the row name, or above
        -- it when the panel would come within 8px of the window bottom.
        if (target:GetBottom() or 0) - 4 - height
            < (g_frame:GetBottom() or 0) + 8 then
            panel:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 14, 4)
        else
            panel:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 14, -4)
        end
        panel:Show()
    end

    -- Counts down the show delay and the grace period after a leave.
    local timer = CreateFrame("Frame", nil, g_frame)
    timer:Hide()
    timer:SetScript("OnUpdate", function(self, elapsed)
        if self.target then
            self.wait = self.wait - elapsed
            if self.wait <= 0 then
                local target = self.target
                self.target = nil
                if target:IsMouseOver() then
                    show_now(
                        target,
                        target.favorite ~= nil and target.favorite:IsMouseOver()
                    )
                end
            end
        end
        self.grace = max(0, (self.grace or 0) - elapsed)
        if not self.target and self.grace == 0 then
            self:Hide()
        end
    end)

    g_frame.tooltip = panel

    -- Hides the panel at once, so the next target waits the full delay.
    g_frame.hide_tooltip = function()
        panel:Hide()
        timer.target = nil
        timer.grace = 0
        timer:Hide()
    end

    -- The pointer left a row, a toggle, or a control. The next target shows
    -- at once within 0.1s.
    g_frame.leave_tooltip = function()
        timer.target = nil
        if panel:IsShown() then
            panel:Hide()
            timer.grace = 0.1
            timer:Show()
        end
    end

    -- Asks for the tooltip of a row (over_toggle when the pointer is on its
    -- favorite toggle) or of a control with a tooltip_text function. Rows
    -- wait out a thumb drag, and controls show nothing while a menu is open.
    g_frame.request_tooltip = function(target, over_toggle)
        if target.tooltip_text then
            if g_frame.menu_catcher:IsShown() then
                return
            end
        elseif not target.entry or g_scrollbar_thumb.drag then
            return
        end
        if panel:IsShown() or (timer.grace or 0) > 0 then
            timer.target = nil
            show_now(target, over_toggle)
            return
        end
        timer.target = target
        timer.wait = 0.5
        timer:Show()
    end
end

-- Shared with the files loaded after this one.
ns.g_scroll_frame = g_scroll_frame
ns.g_scroll_child = g_scroll_child
ns.g_scrollbar = g_scrollbar
ns.g_scrollbar_thumb = g_scrollbar_thumb
ns.g_rows = g_rows
