-- CVar Browser. Shared state on the root frame, constants, fonts, small
-- helpers, CVar data parsing, and saved variables.

local _, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local GetCVarInfo = (C_CVar and C_CVar.GetCVarInfo) or GetCVarInfo
local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local GetCVarDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
local pairs, ipairs = pairs, ipairs
local type, tostring, tonumber = type, tostring, tonumber
local pcall = pcall
local floor, max = math.floor, math.max
local format = string.format
local concat, remove = table.concat, table.remove
local time = time
local CreateFont, STANDARD_TEXT_FONT = CreateFont, STANDARD_TEXT_FONT
local Enum = Enum

-- Shared state ---------------------------------------------------------------

-- The root frame is created first because it also holds the state that
-- every file shares. Files reassign these fields, so they cannot be
-- shared as locals.
local g_frame = CreateFrame("Frame", "CVarBrowserFrame", UIParent, "BackdropTemplate")
-- Saved variables, set by init_db on ADDON_LOADED.
g_frame.db = nil
-- Every scanned entry by canonical and lowercase name.
g_frame.by_name = {}
-- The entries the list shows, filtered and sorted.
g_frame.view = {}
g_frame.selected = nil
-- Physical pixels per frame unit after scale compensation (~1.0).
-- Anchor offsets on the frame use the same frame units. Cursor screen
-- units convert to frame units by dividing by the region's effective
-- scale, never by this value.
g_frame.px_per_unit = 1
-- Search, filter, sort, and history state.
g_frame.regex_enabled = false
g_frame.sort_key = "name"
g_frame.sort_dir = "asc"
g_frame.filters = {
    scope = "",
    category = "",
    type = "",
    has = {},
}
g_frame.undo_stack = {}
g_frame.redo_stack = {}
-- Regions that apply_ui_scale snaps to the pixel grid. Each file appends
-- the widgets it builds. Lines keep every anchor, boxes move their first.
g_frame.snap_lines = {}
g_frame.snap_boxes = {}

-- Every scanned entry in name order. Rescans refill it in place.
local g_entries = {}

-- Constants ------------------------------------------------------------------

local MEDIA_PATH = "Interface\\AddOns\\CVarBrowser\\media\\"
local FONT_REGULAR_PATH = MEDIA_PATH .. "NotoSans-Regular.ttf"
local FONT_SEMIBOLD_PATH = MEDIA_PATH .. "NotoSans-SemiBold.ttf"
local FONT_CHECK_PATH = MEDIA_PATH .. "Inter-SemiBold.ttf"
-- Mutable layout metrics. apply_ui_scale rewrites the derived widths per
-- preset, and other files read them through this one shared table.
local METRICS = {
    frame_width = 920,
    frame_height = 680,
    list_top = 152,
    list_bottom = 188,
    list_left = 24,
    list_right = 48,
    gauge_height = 8,
}
METRICS.list_width = METRICS.frame_width - METRICS.list_left - METRICS.list_right
METRICS.list_height = METRICS.frame_height - METRICS.list_top - METRICS.list_bottom
METRICS.detail_width = METRICS.frame_width - 48
local ROW_HEIGHT = 22
-- Enough pooled rows to cover the tallest preset list (Large is 404px)
-- plus one partially visible row at each edge, so ceil(404 / 22) + 1.
local ROW_COUNT = 20
local GAUGE_WIDTH = 88
-- build_meta_parts can emit up to 8 parts (scope, category, type, default,
-- observed, help range, read-only/locked, secure). Never drop the secure
-- warning.
local META_MAX_PARTS = 8
local COLORS = {
    background = { 0.070588, 0.066667, 0.078431 },
    surface = { 0.101961, 0.094118, 0.109804 },
    hover = { 0.137255, 0.129412, 0.149020 },
    border = { 0.203922, 0.192157, 0.219608 },
    dot = { 0.313725, 0.298039, 0.329412 },
    text = { 0.929412, 0.917647, 0.949020 },
    muted = { 0.603922, 0.572549, 0.623529 },
    accent = { 0.717647, 0.639216, 0.800000 },
    observed = { 0.407843, 0.764706, 0.725490 },
    warning = { 0.878431, 0.658824, 0.341176 },
    success = { 0.388235, 0.788235, 0.541176 },
    error = { 0.878431, 0.415686, 0.447059 },
    changed = { 0.823529, 0.749020, 0.901961 },
}
local BITFIELD_CVARS = {
    closedInfoFrames = true,
}
local DB_DEFAULTS = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
    preset = "auto",
    minimap_angle = 220,
    minimap_hidden = false,
    smooth_scroll = true,
}
-- The change log keeps this many entries in saved variables, oldest first.
local LOG_LIMIT = 200
-- Undo and redo each keep this many steps for the session.
local UNDO_LIMIT = 20

-- Fonts ----------------------------------------------------------------------

local function resize_font(font, path, size)
    local ok = pcall(font.SetFont, font, path, size, "")
    if not ok then
        font:SetFont(STANDARD_TEXT_FONT, size, "")
    end
end

local function create_font(name, path, size)
    local font = CreateFont(name)
    resize_font(font, path, size)
    return font
end

local FONT_TITLE = create_font("CVarBrowserTitle20", FONT_SEMIBOLD_PATH, 20)
local FONT_DETAIL = create_font("CVarBrowserDetail15", FONT_SEMIBOLD_PATH, 15)
local FONT_BODY = create_font("CVarBrowserBody13", FONT_REGULAR_PATH, 13)
local FONT_META = create_font("CVarBrowserMeta11", FONT_REGULAR_PATH, 11)
local FONT_CHECK = create_font("CVarBrowserCheck14", FONT_CHECK_PATH, 14)

-- Small helpers --------------------------------------------------------------

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clamp(value, low, high)
    if value < low then
        return low
    elseif value > high then
        return high
    end
    return value
end

-- Round half up to the nearest integer. floor keeps negatives correct
-- (-2.6 -> -3), unlike C-style (int)(x + 0.5) truncation toward zero.
local function round(value)
    return floor(value + 0.5)
end

local function bitfield_to_hex(value)
    return (tostring(value or ""):gsub(".", function(character)
        return format("%02X", string.byte(character))
    end))
end

local function hex_to_bitfield(text)
    local hex = (text or ""):gsub("%s+", "")
    if hex == "" then
        return ""
    end
    if #hex % 2 ~= 0 or hex:find("[^%x]") then
        return nil
    end
    return (hex:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end

local function display_edit_value(entry, value)
    if entry and (entry.bitfield or entry.serialized) then
        return bitfield_to_hex(value)
    end
    return tostring(value or "")
end

-- The default as text, "?" when unknown and "empty" when blank.
local function default_text(entry)
    local raw = entry.default_value
    if raw == nil then
        return "?"
    end
    local text = tostring(raw)
    if text:match("^%s*$") then
        return "empty"
    end
    return text
end

local function ellipsize(text, maximum)
    text = tostring(text or ""):gsub("[\r\n]+", " ")
    if #text > maximum then
        return text:sub(1, maximum - 3) .. "..."
    end
    return text
end

local function make_text(parent, font, text, color)
    local text_object = parent:CreateFontString(nil, "ARTWORK")
    text_object:SetFontObject(font)
    text_object:SetText(text or "")
    if color then
        text_object:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    return text_object
end

-- Colors a texture or font string from a COLORS entry. Alpha defaults to the
-- color's own fourth value, then 1.
local function set_texture_color(texture, color, alpha)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function set_text_color(text_object, color, alpha)
    text_object:SetTextColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = false,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local function apply_backdrop(target, background, border)
    target:SetBackdrop(BACKDROP)
    if background then
        target:SetBackdropColor(
            background[1],
            background[2],
            background[3],
            background[4] or 1
        )
    else
        target:SetBackdropColor(0, 0, 0, 0)
    end
    target:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    -- edgeSize 1 is one physical pixel because one frame unit is about one
    -- physical pixel (g_frame.px_per_unit ~ 1). BackdropTemplateMixin has no
    -- border-size setter to compensate further.
end

local function snap_texture(texture)
    if texture.SetSnapToPixelGrid then
        pcall(texture.SetSnapToPixelGrid, texture, true)
    end
    if texture.SetTexelSnappingBias then
        pcall(texture.SetTexelSnappingBias, texture, 0)
    end
    return texture
end

local g_hairline = { items = {}, scale = 1 }

function g_hairline.set_size(item)
    local thickness = 1 / g_hairline.scale
    if item.axis == "height" then
        item.texture:SetHeight(thickness)
    elseif item.axis == "width" then
        item.texture:SetWidth(thickness)
    elseif item.axis == "border-v" then
        -- Vertical border edge. Thickness is the width, and the top/bottom
        -- anchor insets equal the thickness so it butts against the horizontal
        -- edges without overlapping (overlap doubles opacity at the corners).
        item.texture:SetWidth(thickness)
        item.texture:ClearAllPoints()
        item.texture:SetPoint("TOPLEFT", item.frame, "TOPLEFT", 0, -thickness)
        item.texture:SetPoint("BOTTOMLEFT", item.frame, "BOTTOMLEFT", 0, thickness)
    elseif item.axis == "border-vr" then
        item.texture:SetWidth(thickness)
        item.texture:ClearAllPoints()
        item.texture:SetPoint("TOPRIGHT", item.frame, "TOPRIGHT", 0, -thickness)
        item.texture:SetPoint("BOTTOMRIGHT", item.frame, "BOTTOMRIGHT", 0, thickness)
    end
end

function g_hairline.register(texture, axis, owner)
    local item = { texture = texture, axis = axis, frame = owner }
    g_hairline.items[#g_hairline.items + 1] = item
    g_hairline.set_size(item)
    return texture
end

function g_hairline.set_scale(scale)
    if not scale or scale <= 0 then
        scale = 1
    end
    g_hairline.scale = scale
    for _, item in ipairs(g_hairline.items) do
        g_hairline.set_size(item)
    end
end

function g_hairline.set_color(borders, color)
    for _, texture in ipairs(borders) do
        texture:SetColorTexture(color[1], color[2], color[3], 1)
    end
end

local function add_border(target, color)
    -- Horizontal edges span the full width and own the corners. Vertical
    -- edges are inset by the border thickness (handled by hairline's
    -- border-v axes) so edges butt together without overlapping. Overlapping
    -- opaque corner textures double the opacity there (visible on the
    -- undo/redo buttons).
    local top = snap_texture(target:CreateTexture(nil, "BORDER"))
    set_texture_color(top, color)
    top:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
    g_hairline.register(top, "height", target)

    local bottom = snap_texture(target:CreateTexture(nil, "BORDER"))
    set_texture_color(bottom, color)
    bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
    g_hairline.register(bottom, "height", target)

    local left = snap_texture(target:CreateTexture(nil, "BORDER"))
    set_texture_color(left, color)
    g_hairline.register(left, "border-v", target)

    local right = snap_texture(target:CreateTexture(nil, "BORDER"))
    set_texture_color(right, color)
    g_hairline.register(right, "border-vr", target)
    return { top, bottom, left, right }
end

-- Moves a region's first anchor so its rect lands on whole physical
-- pixels, and resizes it to whole pixels unless it is text.
g_frame.snap_box = function(region)
    if not region or not region:IsShown() then
        return
    end
    local px_per_unit = g_frame.px_per_unit
    local left = region:GetLeft()
    local top = region:GetTop()
    local width = region:GetWidth()
    local height = region:GetHeight()
    if not px_per_unit or px_per_unit <= 0
        or not left or not top or not width or not height then
        return
    end
    local snapped_left_px = round(left * px_per_unit)
    local snapped_right_px = round((left + width) * px_per_unit)
    local snapped_top_px = round(top * px_per_unit)
    local snapped_bottom_px = round((top - height) * px_per_unit)
    if snapped_right_px <= snapped_left_px then
        snapped_right_px = snapped_left_px + 1
    end
    if snapped_bottom_px >= snapped_top_px then
        snapped_bottom_px = snapped_top_px - 1
    end
    local snapped_left = snapped_left_px / px_per_unit
    local snapped_top = snapped_top_px / px_per_unit
    local snapped_width = (snapped_right_px - snapped_left_px)
        / px_per_unit
    local snapped_height = (snapped_top_px - snapped_bottom_px)
        / px_per_unit
    local dx = snapped_left - left
    local dy = snapped_top - top
    local point, relative_to, relative_point, x, y = region:GetPoint(1)
    if point then
        region:ClearAllPoints()
        region:SetPoint(
            point,
            relative_to,
            relative_point,
            (x or 0) + dx,
            (y or 0) + dy
        )
    end
    if region:GetObjectType() ~= "FontString"
        and (snapped_width ~= width or snapped_height ~= height) then
        region:SetSize(snapped_width, snapped_height)
    end
end

-- Moves every anchor of a horizontal line onto a whole physical pixel and
-- rounds its height, keeping at least one pixel.
g_frame.snap_line = function(region)
    if not region or not region:IsShown() then
        return
    end
    local px_per_unit = g_frame.px_per_unit
    local top = region:GetTop()
    local height = region:GetHeight()
    if not px_per_unit or px_per_unit <= 0
        or not top or not height then
        return
    end
    local snapped_top = round(top * px_per_unit) / px_per_unit
    local dy = snapped_top - top
    local snapped_height = max(
        1,
        round(height * px_per_unit) / px_per_unit
    )
    local saved_points = {}
    for index = 1, region:GetNumPoints() do
        local point, relative_to, relative_point, x, y =
            region:GetPoint(index)
        if point then
            saved_points[#saved_points + 1] = {
                point,
                relative_to,
                relative_point,
                x or 0,
                (y or 0) + dy,
            }
        end
    end
    region:ClearAllPoints()
    for _, saved in ipairs(saved_points) do
        region:SetPoint(
            saved[1],
            saved[2],
            saved[3],
            saved[4],
            saved[5]
        )
    end
    if snapped_height ~= height then
        region:SetHeight(snapped_height)
    end
end

-- Snaps every texture rect in the tree to the pixel grid at rest so edges
-- stay one physical pixel, and moves single-anchor text origins onto whole
-- pixels. Text left at a half-pixel offset (centered or right-anchored
-- labels with odd/fractional widths) rounds either way depending on the
-- frame's absolute position, so it shifted 1px while dragging (seen in
-- game on the "Value" header). The shift here is under half a pixel, so
-- padding is unaffected. Each snap starts from the label's design offset
-- (remembered unless code re-anchored it since), so repeated relayouts
-- with changing text never accumulate drift. Multi-anchor text is left
-- alone. snap_box only rewrites the first anchor.
g_frame.snap_region_tree = function(region)
    if region.GetChildren then
        for _, child in ipairs({ region:GetChildren() }) do
            g_frame.snap_region_tree(child)
        end
    end
    if not region.GetRegions then
        return
    end
    for _, sub in ipairs({ region:GetRegions() }) do
        local kind = sub:GetObjectType()
        if kind == "Texture" then
            if sub.GetNumPoints and sub:GetNumPoints() > 1 then
                g_frame.snap_line(sub)
            else
                g_frame.snap_box(sub)
            end
        elseif kind == "FontString" and sub:GetNumPoints() == 1 then
            local point, relative_to, relative_point, x, y = sub:GetPoint(1)
            local last = sub.text_snap
            if last and last.x == x and last.y == y then
                x, y = last.base_x, last.base_y
                sub:SetPoint(point, relative_to, relative_point, x, y)
            end
            g_frame.snap_box(sub)
            local _, _, _, snapped_x, snapped_y = sub:GetPoint(1)
            sub.text_snap = {
                base_x = x or 0,
                base_y = y or 0,
                x = snapped_x,
                y = snapped_y,
            }
        end
    end
end

local function create_button(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.active = false
    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints(button)
    set_texture_color(button.background, COLORS.surface)
    button.borders = add_border(button, COLORS.border)
    button.label = make_text(button, FONT_BODY, label, COLORS.text)
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.label:SetJustifyH("CENTER")
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            set_texture_color(self.background, COLORS.hover)
            g_hairline.set_color(self.borders, COLORS.accent)
        end
    end)
    button:SetScript("OnLeave", function(self)
        set_texture_color(self.background, COLORS.surface)
        g_hairline.set_color(
            self.borders,
            self.active and COLORS.accent or COLORS.border
        )
    end)
    return button
end

-- Data / range helpers -------------------------------------------------------

local RANGE_NUMBER = "[%+%-]?%d[%d,]*%.?%d*"

local function parse_range_number(value)
    value = trim(value)
    local number_text = value:match("^(" .. RANGE_NUMBER .. ")")
    if not number_text
        or not value:match("^" .. RANGE_NUMBER .. "%s*[%%%a]*$") then
        return nil
    end
    local number = tonumber((number_text:gsub(",", "")))
    if number == nil then
        return nil
    end
    return number, value
end

local function parse_range_symbol(value)
    value = trim(value)
    local lower = value:lower()
    if lower == "pi" or lower == "~" or lower == "inf"
        or lower == "infinity" then
        return value
    end
    return nil
end

local function parse_range_content(content)
    content = trim(content)
    content = content:gsub("%s+to%s+", " - ")
        :gsub("%s+through%s+", " - ")
        :gsub("%s*%.%.%s*", " - ")
        :gsub("–", "-")
        :gsub("—", "-")

    local minimum_text = content:match("^min[%s:=]*(" .. RANGE_NUMBER .. ")$")
    if minimum_text then
        local minimum, text = parse_range_number(minimum_text)
        if minimum then
            return "min " .. text, minimum, nil
        end
    end
    local maximum_text = content:match("^max[%s:=]*(" .. RANGE_NUMBER .. ")$")
    if maximum_text then
        local maximum, text = parse_range_number(maximum_text)
        if maximum then
            return "max " .. text, nil, maximum
        end
    end
    local min_part, max_part = content:match(
        "min[%s:=]*(" .. RANGE_NUMBER .. ").-max[%s:=]*(" .. RANGE_NUMBER .. ")"
    )
    if min_part and max_part then
        local minimum, min_text = parse_range_number(min_part)
        local maximum, max_text = parse_range_number(max_part)
        if minimum and maximum and minimum <= maximum then
            return min_text .. " - " .. max_text, minimum, maximum
        end
    end

    local parts = {}
    local start = 1
    while true do
        local comma = content:find(",%s", start)
        if not comma then
            parts[#parts + 1] = content:sub(start)
            break
        end
        parts[#parts + 1] = content:sub(start, comma - 1)
        start = comma + 1
        while content:sub(start, start):match("%s") do
            start = start + 1
        end
    end

    if #parts == 2 then
        local minimum, minimum_text = parse_range_number(parts[1])
        local maximum, maximum_text = parse_range_number(parts[2])
        if minimum and maximum and minimum <= maximum then
            return minimum_text .. " - " .. maximum_text, minimum, maximum
        end
        local minimum_symbol = parse_range_symbol(parts[1])
        local maximum_symbol = parse_range_symbol(parts[2])
        if minimum and maximum_symbol then
            return minimum_text .. " - " .. maximum_symbol, minimum, nil
        end
        if maximum and minimum_symbol then
            return minimum_symbol .. " - " .. maximum_text, nil, maximum
        end
        return nil
    end

    local minimum_text, maximum_text = content:match(
        "^(" .. RANGE_NUMBER .. ")%,(" .. RANGE_NUMBER .. ")$"
    )
    if minimum_text then
        local minimum = parse_range_number(minimum_text)
        local maximum = parse_range_number(maximum_text)
        if minimum and maximum and minimum <= maximum then
            return minimum_text .. " - " .. maximum_text, minimum, maximum
        end
    end

    minimum_text, maximum_text = content:match(
        "^(" .. RANGE_NUMBER .. ")%s*%-%s*(" .. RANGE_NUMBER .. ")$"
    )
    if minimum_text then
        local minimum = parse_range_number(minimum_text)
        local maximum = parse_range_number(maximum_text)
        if minimum and maximum and minimum <= maximum then
            return minimum_text .. " - " .. maximum_text, minimum, maximum
        end
    end

    return nil
end

local function parse_range(help)
    if type(help) ~= "string" or help == "" then
        return nil
    end
    for content in help:gmatch("%[([^%]]+)%]") do
        local range, minimum, maximum = parse_range_content(content)
        if range then
            return range, minimum, maximum
        end
    end
    for content in help:gmatch("%(([^%)]+)%)") do
        local range, minimum, maximum = parse_range_content(content)
        if range then
            return range, minimum, maximum
        end
    end
    return nil
end

local function parse_enum_help(help)
    if type(help) ~= "string" or help == "" then
        return nil
    end
    local options = {}
    for value, label in help:gmatch(
        "([%+%-]?%d+)%s*[=:]%s*([%a][%w%s%./%-]*)"
    ) do
        label = trim(label:gsub("[,;].*$", ""))
        if label ~= "" and #label <= 32 then
            options[#options + 1] = value .. " = " .. label
        end
    end
    if #options >= 2 then
        return options
    end
    return nil
end

local function format_observed_range(observed)
    if type(observed) ~= "table" then
        return nil
    end
    if observed.min and observed.max then
        return tostring(observed.min) .. " - " .. tostring(observed.max)
    elseif observed.min then
        return tostring(observed.min) .. "+"
    elseif observed.max then
        return "<= " .. tostring(observed.max)
    end
    return nil
end

local function format_observed_evidence(observed)
    if type(observed) ~= "table" then
        return nil
    end
    local parts = {}
    -- Reads like "max 2.6 (asked 5, was 1.9, 3x)".
    local function add(label, value, requested, previous, seen)
        if value == nil then
            return
        end
        local notes = { "asked " .. tostring(requested or "?") }
        if previous ~= nil and previous ~= value then
            notes[#notes + 1] = "was " .. tostring(previous)
        end
        if seen and seen > 1 then
            notes[#notes + 1] = seen .. "x"
        end
        parts[#parts + 1] = format(
            "%s %s (%s)",
            label,
            tostring(value),
            concat(notes, ", ")
        )
    end
    add(
        "max",
        observed.max,
        observed.max_requested,
        observed.max_previous,
        observed.max_seen
    )
    add(
        "min",
        observed.min,
        observed.min_requested,
        observed.min_previous,
        observed.min_seen
    )
    return #parts > 0 and concat(parts, ", ") or nil
end

local function apply_range(entry)
    local db = g_frame.db
    local observed = db and db.observed and db.observed[entry.name]
    entry.observed = observed
    local observed_text = format_observed_range(observed)
    if observed_text then
        entry.range_text = observed_text
        entry.range_source = "observed"
    else
        entry.range_text = entry.help_range
        entry.range_source = entry.range_text and "help" or nil
    end
end

local function infer_value_type(entry)
    if entry.bitfield then
        return "Bitfield"
    elseif entry.serialized then
        return "Serialized"
    elseif entry.help_enum then
        return "Enum"
    end
    local value = entry.value
    if value == nil then
        return "Unknown"
    end
    value = tostring(value)
    if value == "0" or value == "1"
        or value == "true" or value == "false" then
        return "Boolean"
    end
    if tonumber(value) then
        return "Number"
    end
    if value:find("[,;]") or value:find("%s") then
        return "List"
    end
    return "Text"
end

local function read_cvar_value(entry)
    local value = nil
    local default_value = nil
    local scope = nil
    local locked = nil
    local secure = nil
    local readonly = nil

    local info_first = nil
    if GetCVarInfo then
        local ok, first, returned_default, account_wide, per_character, c, d, e =
            pcall(GetCVarInfo, entry.name)
        if ok and first ~= nil then
            info_first = first
            default_value = returned_default
            scope = account_wide and "Account"
                or (per_character and "Character" or "Local")
            locked = c
            secure = d
            readonly = e
        end
    end

    if GetCVar then
        local ok, fallback = pcall(GetCVar, entry.name)
        if ok then
            value = fallback
        end
    end

    -- GetCVarInfo's first return is the value too (verified in game). Use
    -- it if GetCVar is unavailable or returned nothing.
    if value == nil then
        value = info_first
    end

    if default_value == nil and GetCVarDefault then
        local ok, fallback = pcall(GetCVarDefault, entry.name)
        if ok then
            default_value = fallback
        end
    end

    entry.value = value
    entry.default_value = default_value
    entry.scope = scope
    entry.scope_lower = scope and scope:lower() or ""
    entry.locked = locked
    entry.secure = secure
    entry.readonly = readonly
    entry.changed = value ~= nil
        and default_value ~= nil
        and value ~= default_value
    entry.bitfield = BITFIELD_CVARS[entry.name] == true
    entry.serialized = false
    if not entry.bitfield and value ~= nil then
        local text = tostring(value)
        if text:find("[%z\1-\31\127-\255]") then
            entry.serialized = true
        end
    end
    -- Filters and the type sort read this on every rebuild, so it is
    -- inferred once per value change rather than per keystroke.
    entry.type_key = infer_value_type(entry):lower()
end

-- Whether the value field, Set, and Reset can change this CVar right now.
local function can_edit(entry)
    return entry ~= nil
        and not entry.readonly
        and not entry.locked
        and not (entry.secure and InCombatLockdown())
end

local function is_cvar_entry(info)
    if type(info) ~= "table" or type(info.command) ~= "string" then
        return false
    end
    local command_type = info.commandType
    if command_type ~= nil then
        if type(command_type) == "string" then
            return command_type:lower() == "cvar"
        end
        local cvar_type = Enum
            and Enum.ConsoleCommandType
            and Enum.ConsoleCommandType.Cvar
        return cvar_type ~= nil and command_type == cvar_type
    end
    if not GetCVarInfo then
        return false
    end
    local ok, value = pcall(GetCVarInfo, info.command)
    return ok and value ~= nil
end

local function record_observed_bound(entry, requested_text, previous_text)
    if not g_frame.db or type(g_frame.db.observed) ~= "table" then
        return false
    end
    local requested = tonumber(requested_text)
    local actual = tonumber(entry.value)
    local previous = tonumber(previous_text)
    if not requested or not actual or not previous then
        return false
    end
    if actual == requested or actual == previous then
        return false
    end

    if entry.help_min and entry.help_max then
        if requested >= entry.help_min and requested <= entry.help_max then
            return false
        end
    elseif entry.help_min then
        if requested >= entry.help_min then
            return false
        end
    elseif entry.help_max then
        if requested <= entry.help_max then
            return false
        end
    end

    local observed = g_frame.db.observed[entry.name]
    if type(observed) ~= "table" then
        observed = {}
        g_frame.db.observed[entry.name] = observed
    end

    if requested > actual then
        if observed.max == actual then
            observed.max_seen = (observed.max_seen or 0) + 1
        else
            observed.max = actual
            observed.max_seen = 1
        end
        observed.max_requested = requested_text
        observed.max_previous = previous_text
    else
        if observed.min == actual then
            observed.min_seen = (observed.min_seen or 0) + 1
        else
            observed.min = actual
            observed.min_seen = 1
        end
        observed.min_requested = requested_text
        observed.min_previous = previous_text
    end
    return true
end

local function classify_set_outcome(requested_text, previous_text, actual_text, learned)
    if actual_text == nil then
        return "unverified"
    end
    local requested = tonumber(requested_text)
    local previous = tonumber(previous_text)
    local actual = tonumber(actual_text)
    local same_as_request = actual_text == requested_text
        or (requested ~= nil and actual ~= nil and requested == actual)
    local same_as_previous = actual_text == previous_text
        or (actual ~= nil and previous ~= nil and actual == previous)
    if same_as_request then
        return "accepted"
    elseif same_as_previous then
        return "ignored"
    elseif learned then
        return "clamped"
    end
    return "normalized"
end

local function build_meta_parts(entry)
    local parts = {}
    local function add(text, color)
        if text and text ~= "" then
            parts[#parts + 1] = {
                text = text,
                color = color or COLORS.muted,
            }
        end
    end

    add(entry.scope)
    add(entry.category)
    add("Type: " .. infer_value_type(entry))
    local raw_default = entry.default_value
    if entry.bitfield then
        add(format("Default: Bitfield (%d bytes)", #tostring(raw_default or "")))
    elseif entry.serialized then
        add(format("Default: Serialized (%d bytes)", #tostring(raw_default or "")))
    else
        add("Default: " .. default_text(entry))
    end
    if entry.range_text and entry.range_source == "help" then
        add("Range help: " .. entry.range_text)
    end
    if entry.observed then
        local evidence = format_observed_evidence(entry.observed)
        if evidence then
            add("Observed: " .. evidence, COLORS.observed)
        elseif entry.range_text and entry.range_source == "observed" then
            add("Observed range: " .. entry.range_text, COLORS.observed)
        end
    end
    if entry.help_range and entry.range_source == "observed"
        and entry.help_range ~= entry.range_text then
        add("Help range: " .. entry.help_range)
    end
    if entry.readonly then
        add("Read-only")
    elseif entry.locked then
        add("Locked")
    end
    if entry.secure then
        add("Secure: locked in combat", COLORS.warning)
    end
    return parts
end

-- Saved variables ------------------------------------------------------------

local function init_db()
    if type(CVarBrowserDB) ~= "table" then
        CVarBrowserDB = {}
    end
    local db = CVarBrowserDB
    g_frame.db = db
    for default_key, value in pairs(DB_DEFAULTS) do
        if db[default_key] == nil then
            db[default_key] = value
        end
    end
    if type(db.observed) ~= "table" then
        db.observed = {}
    end
    -- Favorites are keyed by the CVar's canonical name.
    if type(db.favorites) ~= "table" then
        db.favorites = {}
    end
    if type(db.log) ~= "table" then
        db.log = {}
    end

    local observed_key_map = {
        maxRequested = "max_requested",
        maxPrevious = "max_previous",
        maxSeen = "max_seen",
        minRequested = "min_requested",
        minPrevious = "min_previous",
        minSeen = "min_seen",
    }
    for _, observed in pairs(db.observed) do
        if type(observed) == "table" then
            for old_key, new_key in pairs(observed_key_map) do
                if observed[old_key] ~= nil and observed[new_key] == nil then
                    observed[new_key] = observed[old_key]
                    observed[old_key] = nil
                end
            end
            if type(observed.max) == "string" then
                observed.max = tonumber(observed.max) or observed.max
            end
            if type(observed.min) == "string" then
                observed.min = tonumber(observed.min) or observed.min
            end
        end
    end
end

-- Appends one accepted change to the saved change log. Values are stored as
-- the value field shows them (hex for bitfields), shortened so a long
-- serialized value cannot bloat the saved variables.
local function log_change(entry, action, previous, actual)
    if not g_frame.db then
        return
    end
    local log = g_frame.db.log
    log[#log + 1] = {
        name = entry.name,
        action = action,
        old = ellipsize(display_edit_value(entry, previous), 120),
        new = ellipsize(display_edit_value(entry, actual), 120),
        time = time(),
    }
    while #log > LOG_LIMIT do
        remove(log, 1)
    end
end

-- Shared with the files loaded after this one.
ns.g_frame = g_frame
ns.g_entries = g_entries
ns.FONT_REGULAR_PATH = FONT_REGULAR_PATH
ns.FONT_SEMIBOLD_PATH = FONT_SEMIBOLD_PATH
ns.FONT_CHECK_PATH = FONT_CHECK_PATH
ns.METRICS = METRICS
ns.ROW_HEIGHT = ROW_HEIGHT
ns.ROW_COUNT = ROW_COUNT
ns.GAUGE_WIDTH = GAUGE_WIDTH
ns.META_MAX_PARTS = META_MAX_PARTS
ns.COLORS = COLORS
ns.DB_DEFAULTS = DB_DEFAULTS
ns.UNDO_LIMIT = UNDO_LIMIT
ns.resize_font = resize_font
ns.FONT_TITLE = FONT_TITLE
ns.FONT_DETAIL = FONT_DETAIL
ns.FONT_BODY = FONT_BODY
ns.FONT_META = FONT_META
ns.FONT_CHECK = FONT_CHECK
ns.trim = trim
ns.clamp = clamp
ns.round = round
ns.hex_to_bitfield = hex_to_bitfield
ns.display_edit_value = display_edit_value
ns.default_text = default_text
ns.ellipsize = ellipsize
ns.make_text = make_text
ns.set_texture_color = set_texture_color
ns.set_text_color = set_text_color
ns.apply_backdrop = apply_backdrop
ns.snap_texture = snap_texture
ns.g_hairline = g_hairline
ns.add_border = add_border
ns.create_button = create_button
ns.parse_range = parse_range
ns.parse_enum_help = parse_enum_help
ns.format_observed_range = format_observed_range
ns.format_observed_evidence = format_observed_evidence
ns.apply_range = apply_range
ns.read_cvar_value = read_cvar_value
ns.can_edit = can_edit
ns.is_cvar_entry = is_cvar_entry
ns.record_observed_bound = record_observed_bound
ns.classify_set_outcome = classify_set_outcome
ns.build_meta_parts = build_meta_parts
ns.init_db = init_db
ns.log_change = log_change
