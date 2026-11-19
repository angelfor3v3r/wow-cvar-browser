-- CVar Browser. The detail pane and the footer key.

local _, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local CreateFrame = CreateFrame
local ipairs = ipairs

-- Shared from earlier files --------------------------------------------------

local g_frame = ns.g_frame
local METRICS = ns.METRICS
local META_MAX_PARTS = ns.META_MAX_PARTS
local COLORS = ns.COLORS
local FONT_DETAIL = ns.FONT_DETAIL
local FONT_BODY = ns.FONT_BODY
local FONT_META = ns.FONT_META
local round = ns.round
local make_text = ns.make_text
local set_texture_color = ns.set_texture_color
local set_text_color = ns.set_text_color
local snap_texture = ns.snap_texture
local g_hairline = ns.g_hairline
local add_border = ns.add_border
local create_button = ns.create_button
local g_detail = nil
local g_detail_name = nil
local g_detail_meta = nil
local g_detail_meta_parts = {}
local g_detail_meta_separators = {}
local g_detail_help = nil
local g_detail_edit_frame = nil
local g_detail_edit = nil
local g_set_button = nil
local g_reset_button = nil
local g_detail_status = nil
local g_key = nil

local g_detail_separator = snap_texture(g_frame:CreateTexture(nil, "ARTWORK"))
set_texture_color(g_detail_separator, COLORS.border)
g_detail_separator:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 24, -496)
g_detail_separator:SetPoint("TOPRIGHT", g_frame, "TOPRIGHT", -24, -496)
g_hairline.register(g_detail_separator, "height")
g_frame.snap_lines[#g_frame.snap_lines + 1] = g_detail_separator

g_detail = CreateFrame("Frame", nil, g_frame)
g_detail:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 24, -504)
g_detail:SetPoint("BOTTOMRIGHT", g_frame, "BOTTOMRIGHT", -24, 44)

g_detail_name = make_text(g_detail, FONT_DETAIL, "", COLORS.text)
g_detail_name:SetPoint("TOPLEFT", g_detail, "TOPLEFT", 0, 0)
g_detail_name:SetWidth(METRICS.detail_width)
g_detail_name:SetJustifyH("LEFT")
g_detail_name:SetWordWrap(false)

g_detail_meta = CreateFrame("Frame", nil, g_detail)
g_detail_meta:SetPoint("TOPLEFT", g_detail_name, "BOTTOMLEFT", 0, -3)
g_detail_meta:SetSize(METRICS.detail_width, 14)

do
    local function create_meta_part(parent)
        local part = make_text(parent, FONT_META, "", COLORS.muted)
        part:SetWordWrap(false)
        part:Hide()
        return part
    end

    local function create_meta_separator(parent)
        local separator = snap_texture(parent:CreateTexture(nil, "ARTWORK"))
        set_texture_color(separator, COLORS.border, 0.7)
        g_hairline.register(separator, "width")
        separator:SetHeight(11)
        separator:Hide()
        return separator
    end

    for index = 1, META_MAX_PARTS do
        g_detail_meta_parts[index] = create_meta_part(g_detail_meta)
        if index > 1 then
            g_detail_meta_separators[index - 1] = create_meta_separator(g_detail_meta)
        end
    end
end

g_detail_help = make_text(g_detail, FONT_BODY, "", COLORS.text)
g_detail_help:SetPoint("TOPLEFT", g_detail_meta, "BOTTOMLEFT", 0, -4)
g_detail_help:SetWidth(METRICS.detail_width)
g_detail_help:SetJustifyH("LEFT")
g_detail_help:SetWordWrap(true)
g_detail_help:SetMaxLines(2)
g_detail_help:Hide()

g_detail_edit_frame = CreateFrame("Frame", nil, g_detail)
g_detail_edit_frame:SetSize(340, 30)
g_detail_edit_frame:SetPoint("BOTTOMLEFT", g_detail, "BOTTOMLEFT", 0, 0)
g_detail_edit_frame.background = g_detail_edit_frame:CreateTexture(
    nil,
    "BACKGROUND"
)
g_detail_edit_frame.background:SetAllPoints(g_detail_edit_frame)
set_texture_color(g_detail_edit_frame.background, COLORS.surface)
g_detail_edit_frame.borders = add_border(g_detail_edit_frame, COLORS.border)

g_detail_edit = CreateFrame("EditBox", nil, g_detail_edit_frame)
g_detail_edit:SetPoint("TOPLEFT", g_detail_edit_frame, "TOPLEFT", 10, 0)
g_detail_edit:SetPoint("BOTTOMRIGHT", g_detail_edit_frame, "BOTTOMRIGHT", -10, 0)
g_detail_edit:SetAutoFocus(false)
g_detail_edit:SetFontObject(FONT_BODY)
set_text_color(g_detail_edit, COLORS.text)
g_detail_edit:SetTextInsets(2, 2, 2, 2)

g_set_button = create_button(g_detail, "Set", 64, 30)
g_set_button:SetPoint("LEFT", g_detail_edit_frame, "RIGHT", 8, 0)

g_reset_button = create_button(g_detail, "Reset to default", 132, 30)
g_reset_button:SetPoint("LEFT", g_set_button, "RIGHT", 8, 0)

-- The value field and the Set and Reset buttons snap to the pixel grid on
-- every relayout.
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_detail_edit_frame
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_set_button
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_reset_button

g_detail_status = make_text(g_detail, FONT_META, "", COLORS.success)
g_detail_status:SetPoint("LEFT", g_reset_button, "RIGHT", 12, 0)
g_detail_status:SetJustifyH("LEFT")
g_detail_status:SetWordWrap(false)

g_key = CreateFrame("Frame", nil, g_frame)
g_key:SetPoint("BOTTOMLEFT", g_frame, "BOTTOMLEFT", 24, 14)
g_key:SetPoint("BOTTOMRIGHT", g_frame, "BOTTOMRIGHT", -24, 14)
g_key:SetHeight(20)

do
    local key_border = snap_texture(g_key:CreateTexture(nil, "ARTWORK"))
    set_texture_color(key_border, COLORS.border)
    key_border:SetPoint("TOPLEFT", g_key, "TOPLEFT", 0, 0)
    key_border:SetPoint("TOPRIGHT", g_key, "TOPRIGHT", 0, 0)
    g_hairline.register(key_border, "height")
end

-- Semantic key and hint. Construction helpers stay scoped to this block.
do
    local function create_slant_marks(parent)
        local marks = CreateFrame("Frame", nil, parent)
        marks:SetSize(14, 8)
        marks.left = make_text(marks, FONT_META, "/", COLORS.muted)
        marks.left:SetAlpha(0.8)
        marks.left:SetPoint("CENTER", marks, "LEFT", 3, 0)
        marks.right = make_text(marks, FONT_META, "\\", COLORS.muted)
        marks.right:SetAlpha(0.8)
        marks.right:SetPoint("CENTER", marks, "LEFT", 11, 0)
        return marks
    end

    local function create_dot(parent)
        local dot = snap_texture(parent:CreateTexture(nil, "ARTWORK"))
        set_texture_color(dot, COLORS.dot)
        dot:SetSize(2, 2)
        return dot
    end

    -- Full-span outline. The left/right lines run the mark's full height
    -- and the top/bottom lines its full width, so both draw each corner
    -- (solid color, so the overlap is invisible). add_border's butt joints,
    -- with the vertical lines inset by their 1px thickness, left this
    -- small box's side lines 1px short in-game.
    local READONLY_EDGES = {
        { "TOPLEFT", "TOPRIGHT", "height" },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
        { "TOPLEFT", "BOTTOMLEFT", "width" },
        { "TOPRIGHT", "BOTTOMRIGHT", "width" },
    }

    local function create_readonly_mark(parent)
        local mark = CreateFrame("Frame", nil, parent)
        mark:SetSize(9, 9)
        for _, edge in ipairs(READONLY_EDGES) do
            local line = snap_texture(mark:CreateTexture(nil, "BORDER"))
            set_texture_color(line, COLORS.muted)
            line:SetPoint(edge[1], mark, edge[1], 0, 0)
            line:SetPoint(edge[2], mark, edge[2], 0, 0)
            g_hairline.register(line, edge[3], mark)
        end
        return mark
    end

    local function create_observed_ticks(parent)
        local mark = CreateFrame("Frame", nil, parent)
        mark:SetSize(12, 8)
        for _, x in ipairs({ 0, 10 }) do
            local tick = snap_texture(mark:CreateTexture(nil, "ARTWORK"))
            set_texture_color(tick, COLORS.observed)
            tick:SetSize(1, 6)
            tick:SetPoint("LEFT", mark, "LEFT", x, 0)
        end
        return mark
    end

    local function create_current_mark(parent)
        local mark = CreateFrame("Frame", nil, parent)
        mark:SetSize(2, 8)
        local line = snap_texture(mark:CreateTexture(nil, "ARTWORK"))
        line:SetAllPoints(mark)
        set_texture_color(line, COLORS.text)
        return mark
    end

    -- Flow layout of the hint marks. 4px margins on both sides of the slant
    -- group and the dot (the mockup's .key-dot margin).
    local function layout_hint(hint_frame)
        local x = 0
        hint_frame.first:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
        x = round(x + hint_frame.first:GetStringWidth()) + 4
        hint_frame.slants:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
        x = round(x + 14) + 4
        hint_frame.second:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
        x = round(x + hint_frame.second:GetStringWidth()) + 4
        hint_frame.dot:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
        x = round(x + 2) + 4
        hint_frame.third:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
        x = round(x + hint_frame.third:GetStringWidth())
        hint_frame:SetWidth(x)
    end

    local function create_hint(parent)
        local hint_frame = CreateFrame("Frame", nil, parent)
        hint_frame:SetHeight(20)
        hint_frame.first = make_text(
            hint_frame,
            FONT_META,
            "Slanted end",
            COLORS.muted
        )
        hint_frame.slants = create_slant_marks(hint_frame)
        hint_frame.second = make_text(
            hint_frame,
            FONT_META,
            "means no limit. Dot",
            COLORS.muted
        )
        hint_frame.dot = create_dot(hint_frame)
        hint_frame.third = make_text(
            hint_frame,
            FONT_META,
            "means no known range.",
            COLORS.muted
        )
        hint_frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
        layout_hint(hint_frame)
        return hint_frame
    end

    -- Semantic key entries in flow order. Each is { region, fixed width or nil
    -- to measure the text, gap after }. 8px mark-to-label, 16px between entries.
    local key_items = {
        { g_frame.create_diamond(g_key), 7, 8 },
        { make_text(g_key, FONT_META, "Favorite", COLORS.muted), nil, 16 },
        { make_text(g_key, FONT_META, "Differs from default", COLORS.changed), nil, 16 },
        { create_observed_ticks(g_key), 12, 8 },
        { make_text(g_key, FONT_META, "Observed bounds", COLORS.muted), nil, 16 },
        { create_readonly_mark(g_key), 9, 8 },
        { make_text(g_key, FONT_META, "Read-only", COLORS.muted), nil, 16 },
        { create_current_mark(g_key), 2, 8 },
        { make_text(g_key, FONT_META, "Current value", COLORS.muted), nil, 0 },
    }
    g_frame.paint_diamond(key_items[1][1], COLORS.text, true)
    local hint = create_hint(g_key)

    -- Re-run after font resizes so measured advances never drift from
    -- rendered text.
    g_frame.layout_key_row = function()
        local key_x = 0
        for index = 1, #key_items do
            local item = key_items[index]
            local region = item[1]
            region:SetPoint("LEFT", g_key, "LEFT", key_x, 0)
            key_x = round(key_x + (item[2] or region:GetStringWidth())) + item[3]
        end
        layout_hint(hint)
    end
    g_frame.layout_key_row()
end

-- Shared with the files loaded after this one.
ns.g_detail_separator = g_detail_separator
ns.g_detail = g_detail
ns.g_detail_name = g_detail_name
ns.g_detail_meta = g_detail_meta
ns.g_detail_meta_parts = g_detail_meta_parts
ns.g_detail_meta_separators = g_detail_meta_separators
ns.g_detail_help = g_detail_help
ns.g_detail_edit_frame = g_detail_edit_frame
ns.g_detail_edit = g_detail_edit
ns.g_set_button = g_set_button
ns.g_reset_button = g_reset_button
ns.g_detail_status = g_detail_status
