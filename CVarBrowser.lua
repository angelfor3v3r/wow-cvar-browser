local g_addon_name = ...

-- Localized WoW APIs ---------------------------------------------------------

local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local GetPhysicalScreenSize = GetPhysicalScreenSize
local GetCVarInfo = (C_CVar and C_CVar.GetCVarInfo) or GetCVarInfo
local GetCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local GetCVarDefault = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
local SetCVarNative = (C_CVar and C_CVar.SetCVar) or SetCVar
local ConsoleGetAllCommands = (C_Console and C_Console.GetAllCommands) or ConsoleGetAllCommands
local pairs, ipairs = pairs, ipairs
local type, tostring, tonumber = type, tostring, tonumber
local pcall = pcall
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local sort, concat = table.sort, table.concat

-- Physical pixels per frame unit after scale compensation (~1.0).
-- Anchor offsets on the frame use the same frame units. Cursor screen
-- units convert to frame units by dividing by the region's effective
-- scale, never by this value.
local g_px_per_unit = 1

local MEDIA_PATH = "Interface\\AddOns\\CVarBrowser\\Media\\"
local FONT_REGULAR_PATH = MEDIA_PATH .. "NotoSans-Regular.ttf"
local FONT_SEMIBOLD_PATH = MEDIA_PATH .. "NotoSans-SemiBold.ttf"
-- Mutable layout metrics. apply_ui_scale rewrites the derived widths per
-- preset. Grouped in one table to keep main-chunk locals under the cap.
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
local CATEGORY_NAMES = {
    [0] = "Debug",
    [1] = "Graphics",
    [2] = "Console",
    [3] = "Combat",
    [4] = "Game",
    [5] = "Default",
    [6] = "Net",
    [7] = "Sound",
    [8] = "GM",
    [9] = "Reveal",
    [10] = "None",
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
local FONT_CHECK = create_font("CVarBrowserCheck14", MEDIA_PATH .. "Inter-SemiBold.ttf", 14)

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

-- Inline color escape for the muted "(Default: ...)" suffix in rows.
local MUTED_ESCAPE = format(
    "|cff%02x%02x%02x",
    round(COLORS.muted[1] * 255),
    round(COLORS.muted[2] * 255),
    round(COLORS.muted[3] * 255)
)

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
    -- physical pixel (g_px_per_unit ~ 1). BackdropTemplateMixin has no
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
    top:SetColorTexture(color[1], color[2], color[3], 1)
    top:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
    g_hairline.register(top, "height", target)

    local bottom = snap_texture(target:CreateTexture(nil, "BORDER"))
    bottom:SetColorTexture(color[1], color[2], color[3], 1)
    bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
    g_hairline.register(bottom, "height", target)

    local left = snap_texture(target:CreateTexture(nil, "BORDER"))
    left:SetColorTexture(color[1], color[2], color[3], 1)
    g_hairline.register(left, "border-v", target)

    local right = snap_texture(target:CreateTexture(nil, "BORDER"))
    right:SetColorTexture(color[1], color[2], color[3], 1)
    g_hairline.register(right, "border-vr", target)
    return { top, bottom, left, right }
end

local function create_button(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.active = false
    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints(button)
    button.background:SetColorTexture(
        COLORS.surface[1],
        COLORS.surface[2],
        COLORS.surface[3],
        1
    )
    button.borders = add_border(button, COLORS.border)
    button.label = make_text(button, FONT_BODY, label, COLORS.text)
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.label:SetJustifyH("CENTER")
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self.background:SetColorTexture(
                COLORS.hover[1],
                COLORS.hover[2],
                COLORS.hover[3],
                1
            )
            for _, border in ipairs(self.borders) do
                border:SetColorTexture(
                    COLORS.accent[1],
                    COLORS.accent[2],
                    COLORS.accent[3],
                    1
                )
            end
        end
    end)
    button:SetScript("OnLeave", function(self)
        self.background:SetColorTexture(
            COLORS.surface[1],
            COLORS.surface[2],
            COLORS.surface[3],
            1
        )
        local border_color = self.active and COLORS.accent or COLORS.border
        for _, border in ipairs(self.borders) do
            border:SetColorTexture(
                border_color[1],
                border_color[2],
                border_color[3],
                1
            )
        end
    end)
    return button
end

-- Data / range helpers -------------------------------------------------------

local g_entries = {}
local g_by_name = {}
local g_view = {}
local g_selected = nil
local g_db = nil

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
    local function add(label, value, requested, previous, seen)
        if value == nil then
            return
        end
        local text = format(
            "%s: %s -> %s",
            label,
            tostring(requested or "?"),
            tostring(value)
        )
        if previous ~= nil and previous ~= value then
            text = text .. " (was " .. tostring(previous) .. ")"
        end
        if seen and seen > 1 then
            text = text .. " (" .. seen .. "x)"
        end
        parts[#parts + 1] = text
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
    return #parts > 0 and concat(parts, "; ") or nil
end

local function apply_range(entry)
    local observed = g_db and g_db.observed and g_db.observed[entry.name]
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
    if not g_db or type(g_db.observed) ~= "table" then
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

    local observed = g_db.observed[entry.name]
    if type(observed) ~= "table" then
        observed = {}
        g_db.observed[entry.name] = observed
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
    local default_text = tostring(raw_default or "?")
    if raw_default ~= nil and default_text:match("^%s*$") then
        default_text = "empty"
    end
    if entry.bitfield then
        default_text = format(
            "Bitfield (%d bytes)",
            #tostring(raw_default or "")
        )
    elseif entry.serialized then
        default_text = format(
            "Serialized (%d bytes)",
            #tostring(raw_default or "")
        )
    end
    add("Default: " .. default_text)
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
    g_db = CVarBrowserDB
    for default_key, value in pairs(DB_DEFAULTS) do
        if g_db[default_key] == nil then
            g_db[default_key] = value
        end
    end
    if type(g_db.observed) ~= "table" then
        g_db.observed = {}
    end

    local observed_key_map = {
        maxRequested = "max_requested",
        maxPrevious = "max_previous",
        maxSeen = "max_seen",
        minRequested = "min_requested",
        minPrevious = "min_previous",
        minSeen = "min_seen",
    }
    for _, observed in pairs(g_db.observed) do
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

-- UI objects -----------------------------------------------------------------

local g_frame = nil
local g_titlebar = nil
local g_close_button = nil
local g_scale_button = nil
local g_scale_popup = nil
local g_scale_rows = {}
local g_search_frame = nil
local g_search_box = nil
local g_search_placeholder = nil
local g_changed_button = nil
local g_changed_box = nil
local g_changed_tick = nil
local g_count_text = nil
local g_scroll_frame = nil
local g_scroll_child = nil
local g_scrollbar = nil
local g_scrollbar_thumb = nil
local g_rows = {}
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
local g_scroll_drag = nil

-- Root UI --------------------------------------------------------------------

g_frame = CreateFrame("Frame", "CVarBrowserFrame", UIParent, "BackdropTemplate")
g_frame:SetSize(METRICS.frame_width, METRICS.frame_height)
g_frame:SetPoint("CENTER")
g_frame:SetFrameStrata("DIALOG")
g_frame:SetMovable(true)
g_frame:SetClampedToScreen(true)
g_frame:EnableMouse(true)
g_frame:Hide()
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
apply_backdrop(g_frame, COLORS.background, COLORS.border)
table.insert(UISpecialFrames, "CVarBrowserFrame")

-- Smooth-scroll step for any ScrollFrame. It eases toward self.scroll_target
-- in whole-pixel steps (at least 1px per frame) and stops on the target.
g_frame.smooth_step = function(self, elapsed)
    local target = self.scroll_target
    if not target then
        self:SetScript("OnUpdate", nil)
        return
    end
    local current = self:GetVerticalScroll() or 0
    local diff = target - current
    local px = g_px_per_unit
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
    local px = g_px_per_unit
    local range = scroll:GetVerticalScrollRange() or 0
    local target = clamp(round(value * px) / px, 0, range)
    if smooth and g_db and g_db.smooth_scroll then
        scroll.scroll_target = target
        scroll:SetScript("OnUpdate", g_frame.smooth_step)
        return
    end
    scroll.scroll_target = nil
    scroll:SetScript("OnUpdate", nil)
    scroll:SetVerticalScroll(target)
end

g_titlebar = CreateFrame("Frame", nil, g_frame)
g_titlebar:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 1, -1)
g_titlebar:SetPoint("TOPRIGHT", g_frame, "TOPRIGHT", -1, -1)
g_titlebar:SetHeight(44)
g_titlebar:EnableMouse(true)

do
    local titlebar_border = snap_texture(g_titlebar:CreateTexture(nil, "ARTWORK"))
    titlebar_border:SetColorTexture(
        COLORS.border[1],
        COLORS.border[2],
        COLORS.border[3],
        1
    )
    titlebar_border:SetPoint("BOTTOMLEFT", g_titlebar, "BOTTOMLEFT", 0, 0)
    titlebar_border:SetPoint("BOTTOMRIGHT", g_titlebar, "BOTTOMRIGHT", 0, 0)
    g_hairline.register(titlebar_border, "height")

    local brand_bar = snap_texture(g_titlebar:CreateTexture(nil, "ARTWORK"))
    brand_bar:SetColorTexture(
        COLORS.accent[1],
        COLORS.accent[2],
        COLORS.accent[3],
        1
    )
    brand_bar:SetSize(3, 18)
    brand_bar:SetPoint("LEFT", g_titlebar, "LEFT", 24, 0)

    local title = make_text(g_titlebar, FONT_TITLE, "CVar Browser", COLORS.text)
    title:SetPoint("LEFT", g_titlebar, "LEFT", 39, 0)

    local subtitle = make_text(
        g_titlebar,
        FONT_META,
        "WoW Forever",
        COLORS.muted
    )
    subtitle:SetPoint("LEFT", title, "RIGHT", 12, 0)
    subtitle:SetJustifyV("MIDDLE")
end

g_scale_button = CreateFrame("Button", nil, g_titlebar)
g_scale_button:SetSize(112, 24)
g_scale_button:SetPoint("RIGHT", g_titlebar, "RIGHT", -52, 0)
g_scale_button.background = g_scale_button:CreateTexture(nil, "BACKGROUND")
g_scale_button.background:SetAllPoints(g_scale_button)
g_scale_button.background:SetColorTexture(
    COLORS.surface[1],
    COLORS.surface[2],
    COLORS.surface[3],
    1
)
g_scale_button.borders = add_border(g_scale_button, COLORS.border)
g_scale_button.label = make_text(
    g_scale_button,
    FONT_META,
    "Size: Standard",
    COLORS.muted
)
g_scale_button.label:SetPoint("LEFT", g_scale_button, "LEFT", 4, 0)
g_scale_button.label:SetJustifyH("LEFT")
g_scale_button:SetScript("OnEnter", function(self)
    self.background:SetColorTexture(
        COLORS.hover[1],
        COLORS.hover[2],
        COLORS.hover[3],
        1
    )
    for _, border in ipairs(self.borders) do
        border:SetColorTexture(
            COLORS.accent[1],
            COLORS.accent[2],
            COLORS.accent[3],
            1
        )
    end
    self.label:SetTextColor(
        COLORS.text[1],
        COLORS.text[2],
        COLORS.text[3],
        1
    )
end)
g_scale_button:SetScript("OnLeave", function(self)
    self.background:SetColorTexture(
        COLORS.surface[1],
        COLORS.surface[2],
        COLORS.surface[3],
        1
    )
    for _, border in ipairs(self.borders) do
        border:SetColorTexture(
            COLORS.border[1],
            COLORS.border[2],
            COLORS.border[3],
            1
        )
    end
    self.label:SetTextColor(
        COLORS.muted[1],
        COLORS.muted[2],
        COLORS.muted[3],
        1
    )
end)

g_close_button = CreateFrame("Button", nil, g_titlebar)
g_close_button:SetSize(28, 28)
g_close_button:SetPoint("RIGHT", g_titlebar, "RIGHT", -16, 0)
g_close_button.label = make_text(g_close_button, FONT_TITLE, "×", COLORS.muted)
g_close_button.label:SetPoint("CENTER", g_close_button, "CENTER", 0, 0)
g_close_button:SetScript("OnEnter", function(self)
    self.label:SetTextColor(
        COLORS.error[1],
        COLORS.error[2],
        COLORS.error[3],
        1
    )
end)
g_close_button:SetScript("OnLeave", function(self)
    self.label:SetTextColor(
        COLORS.muted[1],
        COLORS.muted[2],
        COLORS.muted[3],
        1
    )
end)

g_search_frame = CreateFrame("Frame", nil, g_frame, "BackdropTemplate")
g_search_frame:SetSize(300, 32)
g_search_frame:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 24, -58)
apply_backdrop(g_search_frame, COLORS.surface, COLORS.border)

g_search_box = CreateFrame("EditBox", nil, g_search_frame)
g_search_box:SetPoint("TOPLEFT", g_search_frame, "TOPLEFT", 10, 0)
g_search_box:SetPoint("BOTTOMRIGHT", g_search_frame, "BOTTOMRIGHT", -10, 0)
g_search_box:SetAutoFocus(false)
g_search_box:SetFontObject(FONT_BODY)
g_search_box:SetTextColor(
    COLORS.text[1],
    COLORS.text[2],
    COLORS.text[3],
    1
)
g_search_box:SetTextInsets(12, 0, 0, 0)

g_frame.search_icon = g_search_frame:CreateTexture(nil, "ARTWORK")
g_frame.search_icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
g_frame.search_icon:SetSize(14, 14)
g_frame.search_icon:SetPoint("LEFT", g_search_frame, "LEFT", 4, 0)
g_frame.search_icon:SetVertexColor(
    COLORS.muted[1],
    COLORS.muted[2],
    COLORS.muted[3],
    1
)

g_search_placeholder = make_text(
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
g_frame.regex_chip.underline:SetColorTexture(
    COLORS.accent[1],
    COLORS.accent[2],
    COLORS.accent[3],
    1
)
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

g_changed_button = CreateFrame("Button", nil, g_frame)
g_changed_button:SetSize(160, 32)
g_changed_button:SetPoint("LEFT", g_frame.regex_chip, "RIGHT", 16, 0)
g_changed_button.checked = false

g_changed_box = CreateFrame("Frame", nil, g_changed_button)
g_changed_box:SetSize(18, 18)
g_changed_box:SetPoint("LEFT", g_changed_button, "LEFT", 0, 0)

do
    local changed_box_background = snap_texture(g_changed_box:CreateTexture(nil, "BACKGROUND"))
    changed_box_background:SetAllPoints(g_changed_box)
    changed_box_background:SetColorTexture(
        COLORS.surface[1],
        COLORS.surface[2],
        COLORS.surface[3],
        1
    )
end

add_border(g_changed_box, COLORS.border)

g_changed_tick = make_text(g_changed_box, FONT_CHECK, "✓", COLORS.accent)
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

g_count_text = make_text(g_frame, FONT_META, "", COLORS.muted)
g_count_text:SetPoint("TOPRIGHT", g_frame, "TOPRIGHT", -24, -67)
g_count_text:SetJustifyH("RIGHT")

do
    local function set_chip_active(button, active)
        button.active = active and true or false
        local color = button.active and COLORS.accent or COLORS.border
        for _, border in ipairs(button.borders) do
            border:SetColorTexture(
                color[1],
                color[2],
                color[3],
                1
            )
        end
        button.label:SetTextColor(
            (button.active and COLORS.accent or COLORS.text)[1],
            (button.active and COLORS.accent or COLORS.text)[2],
            (button.active and COLORS.accent or COLORS.text)[3],
            1
        )
        if button.icon_parts then
            local icon_color = button.active and COLORS.accent or COLORS.muted
            for _, part in ipairs(button.icon_parts) do
                part:SetColorTexture(
                    icon_color[1],
                    icon_color[2],
                    icon_color[3],
                    1
                )
            end
        elseif button.icon then
            local icon_color = button.active and COLORS.accent or COLORS.muted
            button.icon:SetTextColor(
                icon_color[1],
                icon_color[2],
                icon_color[3],
                1
            )
        end
    end

    local function filter_count()
        local filters = g_frame.filters
        local count = 0
        if filters.scope ~= "" then
            count = count + 1
        end
        if filters.category ~= "" then
            count = count + 1
        end
        if filters.type ~= "" then
            count = count + 1
        end
        for _ in pairs(filters.has) do
            count = count + 1
        end
        return count
    end

    local function run_command(text)
        local handler = SlashCmdList and SlashCmdList.CVARBROWSER
        if handler then
            handler(text)
        end
    end

    local function create_menu_row(parent, height)
        local row = CreateFrame("Button", nil, parent)
        row:SetHeight(height)
        row.background = snap_texture(row:CreateTexture(nil, "BACKGROUND"))
        row.background:SetAllPoints(row)
        row.background:SetColorTexture(
            COLORS.hover[1],
            COLORS.hover[2],
            COLORS.hover[3],
            1
        )
        row.background:SetAlpha(0)
        row.check = make_text(row, FONT_CHECK, "✓", COLORS.accent)
        row.check:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.check:Hide()
        row.label = make_text(row, FONT_META, "", COLORS.text)
        row.label:SetPoint("LEFT", row, "LEFT", 24, 0)
        row.label:SetWordWrap(false)
        row.note = make_text(row, FONT_META, "", COLORS.muted)
        row.note:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.note:SetJustifyH("RIGHT")
        row:SetScript("OnEnter", function(self)
            if self:IsEnabled() then
                self.background:SetAlpha(1)
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.background:SetAlpha(0)
        end)
        row:SetScript("OnClick", function(self)
            if self.on_click then
                self.on_click()
            end
        end)
        return row
    end

    local function create_popup(width, height)
        local popup = CreateFrame("Frame", nil, g_frame, "BackdropTemplate")
        popup:SetSize(width, height)
        popup:SetFrameLevel(g_frame:GetFrameLevel() + 20)
        popup:Hide()
        apply_backdrop(popup, COLORS.surface, COLORS.border)
        return popup
    end

    local function fit_chip(button, minimum, left_padding)
        button:SetWidth(
            max(
                minimum,
                round(
                    left_padding
                        + button.label:GetStringWidth()
                        + 6
                )
            )
        )
    end

    g_frame.filter_chip = create_button(g_frame, "Filters off", 104, 26)
    g_frame.filter_chip:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 24, -94)
    g_frame.filter_chip.label:SetFontObject(FONT_META)
    g_frame.filter_chip.label:ClearAllPoints()
    g_frame.filter_chip.label:SetPoint(
        "LEFT",
        g_frame.filter_chip,
        "LEFT",
        18,
        0
    )
    g_frame.filter_chip.label:SetJustifyH("LEFT")
    local filter_icon = CreateFrame("Frame", nil, g_frame.filter_chip)
    filter_icon:SetSize(10, 9)
    filter_icon:SetPoint("TOPLEFT", g_frame.filter_chip, "TOPLEFT", 4, -9)
    local filter_icon_parts = {
        { 10, 0 },
        { 6, 4 },
        { 2, 8 },
    }
    for _, part in ipairs(filter_icon_parts) do
        local line = snap_texture(filter_icon:CreateTexture(nil, "ARTWORK"))
        line:SetColorTexture(
            COLORS.muted[1],
            COLORS.muted[2],
            COLORS.muted[3],
            1
        )
        line:SetSize(part[1], 1)
        line:SetPoint("TOPLEFT", filter_icon, "TOPLEFT", 0, -part[2])
    end

    g_frame.sort_chip = create_button(g_frame, "Sort name asc", 150, 26)
    g_frame.sort_chip:SetPoint("LEFT", g_frame.filter_chip, "RIGHT", 8, 0)
    g_frame.sort_chip.label:SetFontObject(FONT_META)
    g_frame.sort_chip.label:ClearAllPoints()
    g_frame.sort_chip.label:SetPoint(
        "LEFT",
        g_frame.sort_chip,
        "LEFT",
        18,
        0
    )
    g_frame.sort_chip.label:SetJustifyH("LEFT")
    g_frame.sort_chip.icon = CreateFrame("Frame", nil, g_frame.sort_chip)
    g_frame.sort_chip.icon:SetSize(10, 10)
    g_frame.sort_chip.icon:SetPoint(
        "TOPLEFT",
        g_frame.sort_chip,
        "TOPLEFT",
        4,
        -8
    )
    g_frame.sort_chip.icon_parts = {}
    local sort_icon_rows = {
        { 2, 0, 1 },
        { 1, 1, 3 },
        { 0, 2, 5 },
        { 2, 3, 1 },
        { 2, 4, 1 },
        { 2, 5, 1 },
        { 2, 6, 1 },
        { 2, 7, 1 },
        { 2, 8, 1 },
        { 2, 9, 1 },
        { 7, 0, 1 },
        { 7, 1, 1 },
        { 7, 2, 1 },
        { 7, 3, 1 },
        { 7, 4, 1 },
        { 7, 5, 1 },
        { 7, 6, 1 },
        { 5, 7, 5 },
        { 6, 8, 3 },
        { 7, 9, 1 },
    }
    for _, row_spec in ipairs(sort_icon_rows) do
        local part = snap_texture(
            g_frame.sort_chip.icon:CreateTexture(nil, "ARTWORK")
        )
        part:SetColorTexture(
            COLORS.muted[1],
            COLORS.muted[2],
            COLORS.muted[3],
            1
        )
        part:SetSize(row_spec[3], 1)
        part:SetPoint(
            "TOPLEFT",
            g_frame.sort_chip.icon,
            "TOPLEFT",
            row_spec[1],
            -row_spec[2]
        )
        g_frame.sort_chip.icon_parts[#g_frame.sort_chip.icon_parts + 1] = part
    end

    g_frame.undo_button = create_button(g_frame, "↩", 30, 26)
    g_frame.undo_button:SetPoint("LEFT", g_frame.sort_chip, "RIGHT", 8, 0)
    g_frame.undo_button.label:SetFontObject(FONT_CHECK)
    g_frame.undo_button.label:ClearAllPoints()
    g_frame.undo_button.label:SetPoint(
        "CENTER",
        g_frame.undo_button,
        "CENTER",
        -1,
        -2
    )

    g_frame.redo_button = create_button(g_frame, "↪", 30, 26)
    g_frame.redo_button:SetPoint("LEFT", g_frame.undo_button, "RIGHT", 8, 0)
    g_frame.redo_button.label:SetFontObject(FONT_CHECK)
    g_frame.redo_button.label:ClearAllPoints()
    g_frame.redo_button.label:SetPoint(
        "CENTER",
        g_frame.redo_button,
        "CENTER",
        -1,
        -2
    )

    g_frame.copy_button = create_button(g_frame, "Copy", 64, 26)
    g_frame.copy_button:SetPoint("LEFT", g_frame.redo_button, "RIGHT", 8, 0)
    g_frame.copy_button.label:SetFontObject(FONT_META)

    g_frame.filter_popup = create_popup(244, 500)
    g_frame.filter_popup:SetPoint(
        "TOPLEFT",
        g_frame.filter_chip,
        "BOTTOMLEFT",
        0,
        -4
    )

    local filter_header = make_text(
        g_frame.filter_popup,
        FONT_META,
        "Filters",
        COLORS.muted
    )
    filter_header:SetPoint("TOPLEFT", g_frame.filter_popup, "TOPLEFT", 8, -8)

    g_frame.filter_clear = create_button(
        g_frame.filter_popup,
        "Clear all",
        70,
        20
    )
    g_frame.filter_clear:SetPoint("TOPRIGHT", g_frame.filter_popup, "TOPRIGHT", -6, -5)
    g_frame.filter_clear.label:SetFontObject(FONT_META)

    g_frame.filter_scroll = CreateFrame(
        "ScrollFrame",
        nil,
        g_frame.filter_popup
    )
    g_frame.filter_scroll:SetPoint("TOPLEFT", g_frame.filter_popup, "TOPLEFT", 4, -30)
    g_frame.filter_scroll:SetPoint(
        "BOTTOMRIGHT",
        g_frame.filter_popup,
        "BOTTOMRIGHT",
        -12,
        4
    )
    g_frame.filter_scroll:EnableMouseWheel(true)
    -- Shared by the list and the whole popup so the wheel works anywhere
    -- over the filter menu.
    local function scroll_filter_list(_, delta)
        -- Chain from the pending target so fast wheel spins accumulate.
        local scroll = g_frame.filter_scroll
        local base = scroll.scroll_target or scroll:GetVerticalScroll() or 0
        g_frame.scroll_frame_to(scroll, base - delta * 40, true)
    end
    g_frame.filter_scroll:SetScript("OnMouseWheel", scroll_filter_list)

    g_frame.filter_scrollbar = CreateFrame("Frame", nil, g_frame.filter_popup)
    g_frame.filter_scrollbar:SetPoint(
        "TOPRIGHT",
        g_frame.filter_popup,
        "TOPRIGHT",
        -4,
        -30
    )
    g_frame.filter_scrollbar:SetPoint(
        "BOTTOMRIGHT",
        g_frame.filter_popup,
        "BOTTOMRIGHT",
        -4,
        4
    )
    g_frame.filter_scrollbar:SetWidth(6)
    local filter_scroll_track = snap_texture(
        g_frame.filter_scrollbar:CreateTexture(nil, "ARTWORK")
    )
    filter_scroll_track:SetColorTexture(
        COLORS.hover[1],
        COLORS.hover[2],
        COLORS.hover[3],
        1
    )
    filter_scroll_track:SetPoint("TOP", g_frame.filter_scrollbar, "TOP", 0, 0)
    filter_scroll_track:SetPoint(
        "BOTTOM",
        g_frame.filter_scrollbar,
        "BOTTOM",
        0,
        0
    )
    filter_scroll_track:SetWidth(4)
    g_frame.filter_scroll_thumb = CreateFrame("Frame", nil, g_frame.filter_scrollbar)
    g_frame.filter_scroll_thumb:SetWidth(6)
    g_frame.filter_scroll_thumb.background = snap_texture(
        g_frame.filter_scroll_thumb:CreateTexture(nil, "ARTWORK")
    )
    g_frame.filter_scroll_thumb.background:SetAllPoints(
        g_frame.filter_scroll_thumb
    )
    g_frame.filter_scroll_thumb.background:SetColorTexture(
        COLORS.muted[1],
        COLORS.muted[2],
        COLORS.muted[3],
        1
    )
    g_frame.filter_scrollbar:Hide()

    g_frame.filter_content = CreateFrame(
        "Frame",
        nil,
        g_frame.filter_scroll
    )
    g_frame.filter_content:SetWidth(220)
    g_frame.filter_content:SetHeight(1)
    g_frame.filter_scroll:SetScrollChild(g_frame.filter_content)
    g_frame.filter_rows = {}

    local function update_filter_scrollbar()
        local range = g_frame.filter_scroll:GetVerticalScrollRange() or 0
        local viewport = g_frame.filter_scroll:GetHeight() or 1
        if range <= 1 then
            g_frame.filter_scrollbar:Hide()
            return
        end
        g_frame.filter_scrollbar:Show()
        local thumb_height = max(24, floor(viewport * viewport / (range + viewport)))
        local max_top = viewport - thumb_height
        local scroll = g_frame.filter_scroll:GetVerticalScroll() or 0
        local top = range > 0 and scroll / range * max_top or 0
        g_frame.filter_scroll_thumb:SetHeight(thumb_height)
        g_frame.filter_scroll_thumb:ClearAllPoints()
        g_frame.filter_scroll_thumb:SetPoint(
            "TOP",
            g_frame.filter_scrollbar,
            "TOP",
            0,
            -top
        )
        g_frame.snap_box(g_frame.filter_scroll_thumb)
    end
    g_frame.filter_scroll:SetScript("OnVerticalScroll", update_filter_scrollbar)
    g_frame.update_filter_scrollbar = update_filter_scrollbar

    g_frame.filter_popup:EnableMouseWheel(true)
    g_frame.filter_popup:SetScript("OnMouseWheel", scroll_filter_list)

    g_frame.sort_popup = create_popup(170, 140)
    g_frame.sort_popup:SetPoint(
        "TOPLEFT",
        g_frame.sort_chip,
        "BOTTOMLEFT",
        0,
        -4
    )
    g_frame.sort_rows = {}

    g_frame.copy_popup = create_popup(170, 140)
    g_frame.copy_popup:SetPoint(
        "TOPLEFT",
        g_frame.copy_button,
        "BOTTOMLEFT",
        0,
        -4
    )
    g_frame.copy_rows = {}

    -- CopyToClipboard is protected for addons, so copying shows the text
    -- highlighted in a focused read-only edit box for the user's Ctrl+C.
    g_frame.copy_box_frame = create_popup(280, 30)
    g_frame.copy_box_frame:SetPoint(
        "TOPLEFT",
        g_frame.copy_button,
        "BOTTOMLEFT",
        0,
        -4
    )
    -- The box only exists while focused, so it wears the focus border like
    -- the search box and value field (DESIGN.md copy box).
    g_frame.copy_box_frame:SetBackdropBorderColor(
        COLORS.accent[1],
        COLORS.accent[2],
        COLORS.accent[3],
        1
    )
    g_frame.copy_box = CreateFrame("EditBox", nil, g_frame.copy_box_frame)
    g_frame.copy_box:SetPoint("TOPLEFT", g_frame.copy_box_frame, "TOPLEFT", 10, 0)
    g_frame.copy_box:SetPoint(
        "BOTTOMRIGHT",
        g_frame.copy_box_frame,
        "BOTTOMRIGHT",
        -10,
        0
    )
    g_frame.copy_box:SetAutoFocus(false)
    g_frame.copy_box:SetFontObject(FONT_BODY)
    g_frame.copy_box:SetTextColor(
        COLORS.text[1],
        COLORS.text[2],
        COLORS.text[3],
        1
    )
    g_frame.copy_box:SetTextInsets(2, 2, 2, 2)
    g_frame.copy_box:SetHighlightColor(
        COLORS.accent[1],
        COLORS.accent[2],
        COLORS.accent[3],
        0.35
    )
    g_frame.copy_box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    g_frame.copy_box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    g_frame.copy_box:SetScript("OnEditFocusLost", function()
        g_frame.copy_box_frame:Hide()
    end)
    g_frame.copy_box:SetScript("OnTextChanged", function(self, user_input)
        if user_input then
            self:SetText(self.copy_text or "")
            self:HighlightText()
        end
    end)
    g_frame.show_copy_box = function(text)
        g_frame.copy_box.copy_text = text
        g_frame.copy_box_frame:Show()
        g_frame.copy_box:SetText(text)
        g_frame.copy_box:SetCursorPosition(0)
        g_frame.copy_box:SetFocus()
        g_frame.copy_box:HighlightText()
        g_frame.snap_box(g_frame.copy_box_frame)
    end

    g_frame.menu_catcher = CreateFrame("Frame", nil, g_frame)
    g_frame.menu_catcher:SetPoint(
        "TOPLEFT",
        g_frame,
        "TOPLEFT",
        0,
        -122
    )
    g_frame.menu_catcher:SetPoint(
        "BOTTOMRIGHT",
        g_frame,
        "BOTTOMRIGHT",
        0,
        0
    )
    g_frame.menu_catcher:SetFrameLevel(g_frame:GetFrameLevel() + 10)
    g_frame.menu_catcher:EnableMouse(true)
    g_frame.menu_catcher:SetScript("OnMouseDown", function()
        g_frame.close_menus()
    end)
    g_frame.menu_catcher:Hide()

    g_frame.close_menus = function()
        g_frame.filter_popup:Hide()
        g_frame.sort_popup:Hide()
        g_frame.copy_popup:Hide()
        g_frame.copy_box_frame:Hide()
        g_frame.menu_catcher:Hide()
    end

    local function take_filter_row()
        local index = (g_frame.filter_row_index or 0) + 1
        g_frame.filter_row_index = index
        local row = g_frame.filter_rows[index]
        if not row then
            row = create_menu_row(g_frame.filter_content, 20)
            g_frame.filter_rows[index] = row
        end
        row:Show()
        row:SetEnabled(true)
        row:SetAlpha(1)
        row.check:Hide()
        row.note:SetText("")
        row.on_click = nil
        return row
    end

    local function place_filter_row(row, y)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", g_frame.filter_content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", g_frame.filter_content, "TOPRIGHT", 0, -y)
    end

    local function add_filter_group(label, y)
        local row = take_filter_row()
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.label:SetText(label)
        row.label:SetTextColor(
            COLORS.muted[1],
            COLORS.muted[2],
            COLORS.muted[3],
            1
        )
        row:SetEnabled(false)
        row:EnableMouse(false)
        place_filter_row(row, y)
        return y + 18
    end

    local function add_filter_option(label, checked, on_click, y)
        local row = take_filter_row()
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 24, 0)
        row.label:SetText(label)
        row.label:SetTextColor(
            COLORS.text[1],
            COLORS.text[2],
            COLORS.text[3],
            1
        )
        if checked then
            row.check:Show()
        end
        row.on_click = on_click
        row:EnableMouse(true)
        place_filter_row(row, y)
        return y + 20
    end

    local function change_filter(field, value)
        g_frame.filters[field] = value
        g_frame.refresh_filter_menu()
        g_frame.update_filter_chip()
        g_frame.rebuild_results()
    end

    local function toggle_has(value)
        local has = g_frame.filters.has
        if has[value] then
            has[value] = nil
        else
            has[value] = true
        end
        g_frame.refresh_filter_menu()
        g_frame.update_filter_chip()
        g_frame.rebuild_results()
    end

    -- One radio option of a single-value filter field (scope/category/type).
    local function add_filter_choice(field, value, label, y)
        return add_filter_option(label, g_frame.filters[field] == value, function()
            change_filter(field, value)
        end, y)
    end

    g_frame.refresh_filter_menu = function()
        local scroll = g_frame.filter_scroll:GetVerticalScroll() or 0
        g_frame.filter_row_index = 0
        local y = 0
        local filters = g_frame.filters

        y = add_filter_group("Scope", y)
        y = add_filter_choice("scope", "", "All", y)
        y = add_filter_choice("scope", "account", "Account", y)
        y = add_filter_choice("scope", "character", "Character", y)
        y = add_filter_choice("scope", "local", "Local", y)

        y = add_filter_group("Category", y)
        y = add_filter_choice("category", "", "All", y)
        local categories = {}
        local seen_categories = {}
        for _, entry in ipairs(g_entries) do
            local category = entry.category
            if category and category ~= "" then
                local category_key = category:lower()
                if not seen_categories[category_key] then
                    seen_categories[category_key] = true
                    categories[#categories + 1] = {
                        value = category_key,
                        label = category,
                    }
                end
            end
        end
        sort(categories, function(a, b)
            return a.label:lower() < b.label:lower()
        end)
        for _, category in ipairs(categories) do
            y = add_filter_choice("category", category.value, category.label, y)
        end

        y = add_filter_group("Type", y)
        y = add_filter_choice("type", "", "All", y)
        local value_types = {
            { "number", "Number" },
            { "text", "Text" },
            { "boolean", "Boolean" },
            { "enum", "Enum" },
            { "list", "List" },
            { "bitfield", "Bitfield" },
            { "serialized", "Serialized" },
        }
        for _, value_type in ipairs(value_types) do
            y = add_filter_choice("type", value_type[1], value_type[2], y)
        end

        y = add_filter_group("Has", y)
        local has_options = {
            { "range", "Range" },
            { "observed", "Observed bounds" },
            { "help", "Help range" },
            { "default", "Default" },
            { "changed", "Differs from default" },
        }
        for _, option in ipairs(has_options) do
            local value = option[1]
            y = add_filter_option(
                option[2],
                filters.has[value] == true,
                function()
                    toggle_has(value)
                end,
                y
            )
        end

        for index = g_frame.filter_row_index + 1, #g_frame.filter_rows do
            g_frame.filter_rows[index]:Hide()
        end
        g_frame.filter_content:SetHeight(max(1, y + 4))
        g_frame.filter_clear:SetEnabled(
            filter_count() > 0 or g_changed_button.checked
        )
        g_frame.filter_clear:SetAlpha(
            (filter_count() > 0 or g_changed_button.checked) and 1 or 0.38
        )
        g_frame.filter_scroll:SetVerticalScroll(
            min(scroll, g_frame.filter_scroll:GetVerticalScrollRange() or 0)
        )
        g_frame.update_filter_scrollbar()
    end

    g_frame.update_filter_chip = function()
        local count = filter_count()
        g_frame.filter_chip.label:SetText(
            count > 0 and ("Filters " .. count) or "Filters off"
        )
        fit_chip(g_frame.filter_chip, 80, 18)
        set_chip_active(g_frame.filter_chip, count > 0)
        g_frame.snap_box(g_frame.filter_chip)
    end

    g_frame.clear_filters = function()
        g_frame.filters.scope = ""
        g_frame.filters.category = ""
        g_frame.filters.type = ""
        g_frame.filters.has = {}
        g_changed_button.checked = false
        g_changed_tick:Hide()
        g_frame.refresh_filter_menu()
        g_frame.update_filter_chip()
        g_frame.rebuild_results()
        g_frame.notify("Filters cleared")
    end

    g_frame.filter_clear:SetScript("OnClick", function()
        g_frame.clear_filters()
    end)

    g_frame.filter_chip:SetScript("OnClick", function()
        if g_frame.filter_popup:IsShown() then
            g_frame.close_menus()
        else
            g_frame.close_menus()
            g_frame.refresh_filter_menu()
            g_frame.menu_catcher:Show()
            g_frame.filter_popup:Show()
            g_frame.snap_box(g_frame.filter_popup)
            g_frame.snap_region_tree(g_frame.filter_popup)
        end
    end)

    g_frame.sort_chip:SetScript("OnClick", function()
        if g_frame.sort_popup:IsShown() then
            g_frame.close_menus()
        else
            g_frame.close_menus()
            g_frame.refresh_sort_menu()
            g_frame.menu_catcher:Show()
            g_frame.sort_popup:Show()
            g_frame.snap_box(g_frame.sort_popup)
            g_frame.snap_region_tree(g_frame.sort_popup)
        end
    end)

    g_frame.copy_button:SetScript("OnClick", function()
        if g_frame.copy_popup:IsShown() then
            g_frame.close_menus()
        elseif g_selected then
            g_frame.close_menus()
            g_frame.refresh_copy_menu()
            g_frame.menu_catcher:Show()
            g_frame.copy_popup:Show()
            g_frame.snap_box(g_frame.copy_popup)
            g_frame.snap_region_tree(g_frame.copy_popup)
        end
    end)

    g_frame.undo_button:SetScript("OnClick", function()
        run_command("undo")
    end)

    g_frame.redo_button:SetScript("OnClick", function()
        run_command("redo")
    end)

    g_frame.apply_sort = function(sort_choice)
        if g_frame.sort_key == sort_choice then
            g_frame.sort_dir = g_frame.sort_dir == "asc" and "desc" or "asc"
        else
            g_frame.sort_key = sort_choice
            g_frame.sort_dir = sort_choice == "changed" and "desc" or "asc"
        end
        g_frame.close_menus()
        g_frame.update_sort_chip()
        g_frame.rebuild_results()
        g_frame.notify("Sorted by " .. g_frame.sort_key .. " " .. g_frame.sort_dir)
    end

    g_frame.refresh_sort_menu = function()
        local labels = {
            name = "Name",
            type = "Type",
            scope = "Scope",
            category = "Category",
            changed = "Changed",
            range = "Range width",
        }
        local keys = { "name", "type", "scope", "category", "changed", "range" }
        for index, sort_option in ipairs(keys) do
            local row = g_frame.sort_rows[index]
            if not row then
                row = create_menu_row(g_frame.sort_popup, 22)
                row:SetPoint(
                    "TOPLEFT",
                    g_frame.sort_popup,
                    "TOPLEFT",
                    0,
                    -(index - 1) * 22 - 4
                )
                row:SetPoint(
                    "TOPRIGHT",
                    g_frame.sort_popup,
                    "TOPRIGHT",
                    0,
                    -(index - 1) * 22 - 4
                )
                g_frame.sort_rows[index] = row
            end
            row:Show()
            row:EnableMouse(true)
            row:SetAlpha(1)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row, "LEFT", 24, 0)
            row.label:SetText(labels[sort_option])
            row.label:SetTextColor(
                COLORS.text[1],
                COLORS.text[2],
                COLORS.text[3],
                1
            )
            row.note:SetText(
                g_frame.sort_key == sort_option and g_frame.sort_dir or ""
            )
            row.check:SetShown(g_frame.sort_key == sort_option)
            row.on_click = function()
                g_frame.apply_sort(sort_option)
            end
        end
    end

    g_frame.update_sort_chip = function()
        g_frame.sort_chip.label:SetText(
            "Sort " .. g_frame.sort_key .. " " .. g_frame.sort_dir
        )
        fit_chip(g_frame.sort_chip, 100, 18)
        set_chip_active(
            g_frame.sort_chip,
            g_frame.sort_key ~= "name" or g_frame.sort_dir ~= "asc"
        )
        g_frame.snap_box(g_frame.sort_chip)
    end

    g_frame.refresh_copy_menu = function()
        local fields = {
            { "value", "Copy value" },
            { "raw", "Copy raw value" },
            { "default", "Copy default" },
            { "name", "Copy name" },
            { "help", "Copy help" },
            { "range", "Copy range" },
        }
        for index, field in ipairs(fields) do
            local copy_key = field[1]
            local row = g_frame.copy_rows[index]
            if not row then
                row = create_menu_row(g_frame.copy_popup, 22)
                row:SetPoint(
                    "TOPLEFT",
                    g_frame.copy_popup,
                    "TOPLEFT",
                    0,
                    -(index - 1) * 22 - 4
                )
                row:SetPoint(
                    "TOPRIGHT",
                    g_frame.copy_popup,
                    "TOPRIGHT",
                    0,
                    -(index - 1) * 22 - 4
                )
                g_frame.copy_rows[index] = row
            end
            row:Show()
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.label:SetText(field[2])
            row.label:SetTextColor(
                COLORS.text[1],
                COLORS.text[2],
                COLORS.text[3],
                1
            )
            row.check:Hide()
            local missing = g_selected == nil
                or (copy_key == "help"
                    and (g_selected.help == nil or g_selected.help == ""))
                or (copy_key == "range" and g_selected.range_text == nil)
            row.note:SetText(
                g_selected ~= nil
                    and copy_key == "help"
                    and (g_selected.help == nil or g_selected.help == "")
                    and "none"
                    or g_selected ~= nil
                        and copy_key == "range"
                        and g_selected.range_text == nil
                        and "none"
                    or ""
            )
            row:SetEnabled(not missing)
            row:SetAlpha(missing and 0.38 or 1)
            row.on_click = function()
                g_frame.close_menus()
                run_command("copy " .. copy_key)
            end
        end
    end

    g_frame.update_copy_button = function()
        local enabled = g_selected ~= nil
        g_frame.copy_button:SetEnabled(enabled)
        g_frame.copy_button:SetAlpha(enabled and 1 or 0.38)
        if not enabled and g_frame.copy_popup:IsShown() then
            g_frame.close_menus()
        end
    end

    g_frame.update_history_controls = function()
        local undo_count = #g_frame.undo_stack
        local redo_count = #g_frame.redo_stack
        g_frame.undo_button:SetEnabled(undo_count > 0)
        g_frame.undo_button:SetAlpha(undo_count > 0 and 1 or 0.38)
        g_frame.redo_button:SetEnabled(redo_count > 0)
        g_frame.redo_button:SetAlpha(redo_count > 0 and 1 or 0.38)
    end

    g_frame.update_regex_chip = function()
        set_chip_active(g_frame.regex_chip, g_frame.regex_enabled == true)
        g_frame.regex_chip.underline:SetShown(
            g_frame.regex_enabled == true
        )
    end

    g_frame.regex_chip:SetScript("OnClick", function()
        g_frame.regex_enabled = not g_frame.regex_enabled
        g_frame.update_regex_chip()
        g_frame.rebuild_results()
    end)

    g_frame.snap_box = function(region)
        if not region or not region:IsShown() then
            return
        end
        local px_per_unit = g_px_per_unit
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

    g_frame.snap_line = function(region)
        if not region or not region:IsShown() then
            return
        end
        local px_per_unit = g_px_per_unit
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
    g_frame.snap_boxes = {
        g_search_frame,
        g_frame.regex_chip,
        g_changed_button,
        g_frame.filter_chip,
        g_frame.sort_chip,
        g_frame.undo_button,
        g_frame.redo_button,
        g_frame.copy_button,
        g_changed_box,
        g_scale_button,
    }

    g_frame.update_filter_chip()
    g_frame.update_sort_chip()
    g_frame.update_regex_chip()
    g_frame.update_copy_button()
    g_frame.update_history_controls()
end

do
    local header = CreateFrame("Frame", nil, g_frame)
    header:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 24, -132)
    header:SetPoint("TOPRIGHT", g_frame, "TOPRIGHT", -48, -132)
    header:SetHeight(16)
    g_frame.snap_lines = { g_titlebar, header }
    local header_border = snap_texture(header:CreateTexture(nil, "ARTWORK"))
    header_border:SetColorTexture(
        COLORS.border[1],
        COLORS.border[2],
        COLORS.border[3],
        1
    )
    header_border:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header_border:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 24, 0)
    g_hairline.register(header_border, "height")

    local header_name = make_text(header, FONT_META, "CVar", COLORS.muted)
    header_name:SetPoint("LEFT", header, "LEFT", 6, 1)

    local header_gauge = make_text(header, FONT_META, "Gauge", COLORS.muted)
    header_gauge:SetPoint("CENTER", header, "CENTER", 0, 1)

    local header_value = make_text(header, FONT_META, "Value", COLORS.muted)
    header_value:SetPoint("RIGHT", header, "RIGHT", -6, 1)
    header_value:SetJustifyH("RIGHT")
end

g_scroll_frame = CreateFrame("ScrollFrame", nil, g_frame)
g_scroll_frame:SetPoint("TOPLEFT", g_frame, "TOPLEFT", METRICS.list_left, -METRICS.list_top)
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
    scrollbar_track:SetColorTexture(
        COLORS.hover[1],
        COLORS.hover[2],
        COLORS.hover[3],
        1
    )
    scrollbar_track:SetPoint("TOP", g_scrollbar, "TOP", 0, 0)
    scrollbar_track:SetPoint("BOTTOM", g_scrollbar, "BOTTOM", 0, 0)
    scrollbar_track:SetWidth(4)
end

g_scrollbar_thumb = CreateFrame("Frame", nil, g_scrollbar)
g_scrollbar_thumb:SetWidth(8)
g_scrollbar_thumb:EnableMouse(true)
g_scrollbar_thumb.background = snap_texture(
    g_scrollbar_thumb:CreateTexture(nil, "ARTWORK")
)
g_scrollbar_thumb.background:SetAllPoints(g_scrollbar_thumb)
g_scrollbar_thumb.background:SetColorTexture(
    COLORS.muted[1],
    COLORS.muted[2],
    COLORS.muted[3],
    1
)
g_scrollbar_thumb:SetAlpha(1)

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
        track:SetColorTexture(
            COLORS.border[1],
            COLORS.border[2],
            COLORS.border[3],
            1
        )
        -- Every mark sits at whole-pixel offsets from the gauge's top-left
        -- corner. Centering a 1px line or a 3px mark in the 8px gauge put
        -- its edges on half pixels, which drew it 0 or 2px thick depending
        -- on where the row scrolled to.
        track:SetHeight(1)
        track:SetPoint("TOPLEFT", gauge, "TOPLEFT", 0, -3)
        track:SetPoint("TOPRIGHT", gauge, "TOPRIGHT", 0, -3)

        local function make_mark(width, height, color)
            local mark = snap_texture(gauge:CreateTexture(nil, "ARTWORK"))
            mark:SetColorTexture(color[1], color[2], color[3], 1)
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
        hover:SetColorTexture(
            COLORS.hover[1],
            COLORS.hover[2],
            COLORS.hover[3],
            1
        )
        hover:Hide()

        local selected_background = snap_texture(row:CreateTexture(nil, "BACKGROUND"))
        selected_background:SetAllPoints(row)
        selected_background:SetColorTexture(
            COLORS.accent[1],
            COLORS.accent[2],
            COLORS.accent[3],
            0.14
        )
        selected_background:Hide()

        local selected_bar = snap_texture(row:CreateTexture(nil, "ARTWORK"))
        selected_bar:SetColorTexture(
            COLORS.accent[1],
            COLORS.accent[2],
            COLORS.accent[3],
            1
        )
        selected_bar:SetWidth(2)
        selected_bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        selected_bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        selected_bar:Hide()

        local name_text = make_text(row, FONT_BODY, "", COLORS.text)
        name_text:SetPoint("LEFT", row, "LEFT", 6, 0)
        name_text:SetWidth(300)
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
        return row
    end

    for index = 1, ROW_COUNT do
        g_rows[index] = create_row()
    end
end

local g_detail_separator = snap_texture(g_frame:CreateTexture(nil, "ARTWORK"))
g_detail_separator:SetColorTexture(
    COLORS.border[1],
    COLORS.border[2],
    COLORS.border[3],
    1
)
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
        separator:SetColorTexture(
            COLORS.border[1],
            COLORS.border[2],
            COLORS.border[3],
            0.7
        )
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
if g_detail_help.SetMaxLines then
    g_detail_help:SetMaxLines(2)
end
g_detail_help:Hide()

g_detail_edit_frame = CreateFrame("Frame", nil, g_detail)
g_detail_edit_frame:SetSize(340, 30)
g_detail_edit_frame:SetPoint("BOTTOMLEFT", g_detail, "BOTTOMLEFT", 0, 0)
g_detail_edit_frame.background = g_detail_edit_frame:CreateTexture(
    nil,
    "BACKGROUND"
)
g_detail_edit_frame.background:SetAllPoints(g_detail_edit_frame)
g_detail_edit_frame.background:SetColorTexture(
    COLORS.surface[1],
    COLORS.surface[2],
    COLORS.surface[3],
    1
)
g_detail_edit_frame.borders = add_border(g_detail_edit_frame, COLORS.border)

g_detail_edit = CreateFrame("EditBox", nil, g_detail_edit_frame)
g_detail_edit:SetPoint("TOPLEFT", g_detail_edit_frame, "TOPLEFT", 10, 0)
g_detail_edit:SetPoint("BOTTOMRIGHT", g_detail_edit_frame, "BOTTOMRIGHT", -10, 0)
g_detail_edit:SetAutoFocus(false)
g_detail_edit:SetFontObject(FONT_BODY)
g_detail_edit:SetTextColor(
    COLORS.text[1],
    COLORS.text[2],
    COLORS.text[3],
    1
)
g_detail_edit:SetTextInsets(2, 2, 2, 2)

g_set_button = create_button(g_detail, "Set", 64, 30)
g_set_button:SetPoint("LEFT", g_detail_edit_frame, "RIGHT", 8, 0)

g_reset_button = create_button(g_detail, "Reset to default", 132, 30)
g_reset_button:SetPoint("LEFT", g_set_button, "RIGHT", 8, 0)

g_detail_status = make_text(g_detail, FONT_META, "", COLORS.success)
g_detail_status:SetPoint("LEFT", g_reset_button, "RIGHT", 12, 0)
g_detail_status:SetWidth(300)
g_detail_status:SetJustifyH("LEFT")
g_detail_status:SetWordWrap(false)

g_key = CreateFrame("Frame", nil, g_frame)
g_key:SetPoint("BOTTOMLEFT", g_frame, "BOTTOMLEFT", 24, 14)
g_key:SetPoint("BOTTOMRIGHT", g_frame, "BOTTOMRIGHT", -24, 14)
g_key:SetHeight(20)
do
    local key_border = snap_texture(g_key:CreateTexture(nil, "ARTWORK"))
    key_border:SetColorTexture(
        COLORS.border[1],
        COLORS.border[2],
        COLORS.border[3],
        1
    )
    key_border:SetPoint("TOPLEFT", g_key, "TOPLEFT", 0, 0)
    key_border:SetPoint("TOPRIGHT", g_key, "TOPRIGHT", 0, 0)
    g_hairline.register(key_border, "height")
end

-- Semantic key and hint. Construction helpers stay scoped to this block, and
-- apply_ui_scale re-runs g_frame.layout_key_row after font resizes.
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
        dot:SetColorTexture(
            COLORS.dot[1],
            COLORS.dot[2],
            COLORS.dot[3],
            1
        )
        dot:SetSize(2, 2)
        return dot
    end

    local function create_readonly_mark(parent)
        local mark = CreateFrame("Frame", nil, parent)
        mark:SetSize(9, 9)
        -- Full-span outline. The left/right lines run the mark's full height
        -- and the top/bottom lines its full width, so both draw each corner
        -- (solid color, so the overlap is invisible). add_border's butt joints,
        -- with the vertical lines inset by their 1px thickness, left this
        -- small box's side lines 1px short in-game.
        local top = snap_texture(mark:CreateTexture(nil, "BORDER"))
        top:SetColorTexture(
            COLORS.muted[1],
            COLORS.muted[2],
            COLORS.muted[3],
            1
        )
        top:SetPoint("TOPLEFT", mark, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", mark, "TOPRIGHT", 0, 0)
        g_hairline.register(top, "height", mark)

        local bottom = snap_texture(mark:CreateTexture(nil, "BORDER"))
        bottom:SetColorTexture(
            COLORS.muted[1],
            COLORS.muted[2],
            COLORS.muted[3],
            1
        )
        bottom:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
        g_hairline.register(bottom, "height", mark)

        local left = snap_texture(mark:CreateTexture(nil, "BORDER"))
        left:SetColorTexture(
            COLORS.muted[1],
            COLORS.muted[2],
            COLORS.muted[3],
            1
        )
        left:SetPoint("TOPLEFT", mark, "TOPLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", 0, 0)
        g_hairline.register(left, "width", mark)

        local right = snap_texture(mark:CreateTexture(nil, "BORDER"))
        right:SetColorTexture(
            COLORS.muted[1],
            COLORS.muted[2],
            COLORS.muted[3],
            1
        )
        right:SetPoint("TOPRIGHT", mark, "TOPRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
        g_hairline.register(right, "width", mark)
        return mark
    end

    local function create_observed_ticks(parent)
        local mark = CreateFrame("Frame", nil, parent)
        mark:SetSize(12, 8)
        local first = mark:CreateTexture(nil, "ARTWORK")
        first:SetColorTexture(
            COLORS.observed[1],
            COLORS.observed[2],
            COLORS.observed[3],
            1
        )
        first:SetSize(1, 6)
        first:SetPoint("LEFT", mark, "LEFT", 0, 0)
        local second = mark:CreateTexture(nil, "ARTWORK")
        second:SetColorTexture(
            COLORS.observed[1],
            COLORS.observed[2],
            COLORS.observed[3],
            1
        )
        second:SetSize(1, 6)
        second:SetPoint("LEFT", mark, "LEFT", 10, 0)
        return mark
    end

    local function create_current_mark(parent)
        local mark = CreateFrame("Frame", nil, parent)
        mark:SetSize(2, 8)
        local line = mark:CreateTexture(nil, "ARTWORK")
        line:SetAllPoints(mark)
        line:SetColorTexture(
            COLORS.text[1],
            COLORS.text[2],
            COLORS.text[3],
            1
        )
        return mark
    end

    -- Flow layout of the hint marks. 4px margins on both sides of the slant
    -- group and the dot (the mockup's .key-dot margin). Re-run after font
    -- resizes so measured advances never drift from rendered text.
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
        { make_text(g_key, FONT_META, "Differs from default", COLORS.changed), nil, 16 },
        { create_observed_ticks(g_key), 12, 8 },
        { make_text(g_key, FONT_META, "Observed bounds", COLORS.muted), nil, 16 },
        { create_readonly_mark(g_key), 9, 8 },
        { make_text(g_key, FONT_META, "Read-only", COLORS.muted), nil, 16 },
        { create_current_mark(g_key), 2, 8 },
        { make_text(g_key, FONT_META, "Current value", COLORS.muted), nil, 0 },
    }
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

g_scale_popup = CreateFrame("Frame", nil, g_frame, "BackdropTemplate")
g_scale_popup:SetSize(126, #LAYOUT_OPTIONS * 22 + 2)
g_scale_popup:SetPoint("TOPRIGHT", g_scale_button, "BOTTOMRIGHT", 0, -4)
g_scale_popup:SetFrameLevel(g_frame:GetFrameLevel() + 20)
apply_backdrop(g_scale_popup, COLORS.surface, COLORS.border)
g_scale_popup:Hide()
-- The detail controls are created after the chips block, so they join the
-- snap list here once they exist.
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_detail_edit_frame
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_set_button
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_reset_button
g_frame.snap_boxes[#g_frame.snap_boxes + 1] = g_scale_popup

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
    hover:SetColorTexture(
        COLORS.hover[1],
        COLORS.hover[2],
        COLORS.hover[3],
        1
    )
    hover:Hide()
    row.hover = hover
    local selected_bar = snap_texture(row:CreateTexture(nil, "ARTWORK"))
    selected_bar:SetColorTexture(
        COLORS.accent[1],
        COLORS.accent[2],
        COLORS.accent[3],
        1
    )
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

local function resolve_layout()
    local preset_key = g_db and g_db.preset or "auto"
    if preset_key ~= "auto" and LAYOUT_PRESETS[preset_key] then
        return LAYOUT_PRESETS[preset_key], preset_key
    end
    local ok, _, physical_height = pcall(GetPhysicalScreenSize)
    if not ok or not physical_height or physical_height <= 0 then
        physical_height = UIParent:GetHeight() or 1440
    end
    if physical_height <= 1080 then
        return LAYOUT_PRESETS.compact, "compact"
    elseif physical_height >= 1800 then
        return LAYOUT_PRESETS.large, "large"
    end
    return LAYOUT_PRESETS.standard, "standard"
end

local function update_scale_button()
    local preset_key = g_db and g_db.preset or "auto"
    local label = "Auto"
    if preset_key ~= "auto" and LAYOUT_PRESETS[preset_key] then
        label = preset_key:sub(1, 1):upper() .. preset_key:sub(2)
    end
    g_scale_button.label:SetText("Size: " .. label)
    -- Snug fit with 4px of padding on each side, like the other text
    -- buttons.
    g_scale_button:SetWidth(round(g_scale_button.label:GetStringWidth() + 8))
    for _, row in ipairs(g_scale_rows) do
        if row.option.value == preset_key then
            row.label:SetTextColor(
                COLORS.accent[1],
                COLORS.accent[2],
                COLORS.accent[3],
                1
            )
            row.selected_bar:Show()
        else
            row.label:SetTextColor(
                COLORS.text[1],
                COLORS.text[2],
                COLORS.text[3],
                1
            )
            row.selected_bar:Hide()
        end
    end
end

-- Physical pixels per frame unit, measured rather than assumed. A probe of
-- known unit width reports its GetScaledRect in 768-space screen units, and
-- one screen unit is physicalHeight/768 pixels. Measuring catches clients
-- that compose the parent's scale into the frame despite
-- SetIgnoreParentScale, where one unit renders at parentScale pixels.
g_frame.measure_px_per_unit = function(physical_height)
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

-- Snug label fit with 4px text padding from the outline on each side and a
-- caller-supplied floor so tiny buttons never collapse absurdly narrow.
-- A frame field (not a local) to keep main-chunk register headroom.
-- Re-run after font resizes.
g_frame.fit_text_button = function(button, minimum)
    if not button or not button.label then
        return
    end
    local width = button.label:GetStringWidth() + 8
    if minimum and minimum > width then
        width = minimum
    end
    button:SetWidth(round(width))
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

local function snap_frame_position()
    if not g_frame or not g_frame:IsShown() then
        return
    end
    -- Snap the frame's physical-pixel origin to the nearest whole pixel by
    -- shifting the anchor, then re-measure and mop up any residual. GetLeft/
    -- GetTop and SetPoint offsets are both frame units (verified in game, a
    -- +10 offset moved GetLeft by exactly 10 with UIParent at 1.556 px per
    -- unit), so g_px_per_unit converts both ways. Landing the origin on a
    -- whole pixel keeps 1-unit hairlines on exactly one pixel and the font
    -- raster phase stable. A fractional phase is what made the header text
    -- drift between 1px and 2px above the separator after a drag release.
    -- GetScaledRect is not usable here. It returns 768-space screen units
    -- (GetRect times effective scale), not pixels, and its second return is
    -- the bottom edge.
    local px_per_unit = g_px_per_unit
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
    if g_db then
        g_db.x = x
        g_db.y = y
    end
end

local function apply_ui_scale()
    local preset = resolve_layout()
    if g_frame.SetIgnoreParentScale then
        g_frame:SetIgnoreParentScale(true)
    end
    local _, physical_height = GetPhysicalScreenSize()
    if not physical_height or physical_height <= 0 then
        physical_height = 1440
    end
    -- The target is one frame unit == one physical pixel. Screen space is
    -- 768 units over the physical screen, so an effective scale of 768/height
    -- is pixel-perfect wherever SetIgnoreParentScale is honored. Measure the
    -- probe's rendered rect and divide out any residual. Clients that
    -- compose the parent's scale into the frame despite SetIgnoreParentScale
    -- land one unit at parentScale pixels, which this cancels exactly
    -- (scale composition is multiplicative, so one corrective pass
    -- converges).
    local perfect_scale = 768 / physical_height
    g_frame:SetScale(perfect_scale)
    local px_per_unit = g_frame.measure_px_per_unit(physical_height)
    if px_per_unit and px_per_unit > 0 and abs(px_per_unit - 1) > 1e-3 then
        g_frame:SetScale((g_frame:GetScale() or perfect_scale) / px_per_unit)
        px_per_unit = g_frame.measure_px_per_unit(physical_height) or px_per_unit
    end
    if not px_per_unit or px_per_unit <= 0 then
        px_per_unit = 1
    end
    -- Measured physical px per frame unit (~1.0 after compensation).
    g_px_per_unit = px_per_unit
    g_frame:SetSize(preset.width, preset.height)

    resize_font(FONT_TITLE, FONT_SEMIBOLD_PATH, preset.title)
    resize_font(FONT_DETAIL, FONT_SEMIBOLD_PATH, preset.detail)
    resize_font(FONT_BODY, FONT_REGULAR_PATH, preset.body)
    resize_font(FONT_META, FONT_REGULAR_PATH, preset.meta)
    resize_font(
        FONT_CHECK,
        MEDIA_PATH .. "Inter-SemiBold.ttf",
        preset.check
    )
    g_frame.layout_key_row()
    -- Refit snug text buttons after font sizes settle. Labels keep 4px
    -- padding from the outline on each side, with a small floor (roughly
    -- the button height) so tiny buttons never collapse absurdly narrow.
    g_frame.fit_text_button(g_set_button, 30)
    g_frame.fit_text_button(g_reset_button, 64)
    g_frame.fit_text_button(g_frame.copy_button, 30)
    g_frame.fit_text_button(g_frame.filter_clear, 40)
    g_frame.fit_text_button(g_close_button, 24)
    g_frame.fit_text_button(g_frame.undo_button, 24)
    g_frame.fit_text_button(g_frame.redo_button, 24)

    METRICS.detail_width = preset.width - 48
    METRICS.list_width = preset.width - METRICS.list_left - METRICS.list_right
    METRICS.list_bottom = preset.detail_height + 56
    METRICS.list_height = preset.height - METRICS.list_top - METRICS.list_bottom

    g_scroll_child:SetWidth(METRICS.list_width)
    -- Name and value columns run from the row edges (6px inset) to 10px
    -- short of the centered gauge, and the font string truncates with an
    -- ellipsis at that width. A fixed character cap cut names off early.
    local column_width = round(METRICS.list_width / 2 - GAUGE_WIDTH / 2 - 16)
    for index = 1, ROW_COUNT do
        g_rows[index].name_text:SetWidth(column_width)
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
    -- physical-px-per-unit (g_px_per_unit, validated above). GetScaledRect
    -- must not be used for this. It returns 768-space screen units (GetRect
    -- times effective scale), not pixels, which drew hairlines at
    -- height/768 px (double thickness at common resolutions).
    g_hairline.set_scale(g_px_per_unit)
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
    if g_db then
        g_db.preset = value
    end
    g_scale_popup:Hide()
end

local function toggle_scale_popup()
    if g_scale_popup:IsShown() then
        g_scale_popup:Hide()
    else
        update_scale_button()
        g_scale_popup:Show()
        g_frame.snap_box(g_scale_popup)
        g_scale_popup:Raise()
    end
end

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
        local angle = math.rad(g_db and g_db.minimap_angle or 220)
        local radius = 80
        self:ClearAllPoints()
        self:SetPoint(
            "CENTER",
            Minimap,
            "CENTER",
            math.cos(angle) * radius,
            math.sin(angle) * radius
        )
    end

    g_frame.minimap_button:SetScript("OnClick", function()
        if g_frame:IsShown() then
            g_frame:Hide()
        else
            g_frame:Show()
        end
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
        self:SetScript("OnUpdate", function(self)
            local minimap_x, minimap_y = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            if not minimap_x or not scale or scale == 0 then
                return
            end
            local cursor_x, cursor_y = GetCursorPosition()
            cursor_x = cursor_x / scale
            cursor_y = cursor_y / scale
            local angle = math.deg(
                math.atan2(cursor_y - minimap_y, cursor_x - minimap_x)
            )
            if g_db then
                g_db.minimap_angle = angle
            end
            self:update_position()
        end)
    end)
    g_frame.minimap_button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:update_position()
    end)
    g_frame.minimap_button:update_position()
end

-- Addon Compartment (Blizzard minimap drawer, also used by collectors) ------

function CVarBrowser_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton ~= "LeftButton" then
        return
    end
    if g_frame:IsShown() then
        g_frame:Hide()
    else
        g_frame:Show()
    end
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

-- Render ---------------------------------------------------------------------

local function set_status(message, tone)
    g_detail_status:SetText(message or "")
    local color = COLORS.success
    if tone == "error" then
        color = COLORS.error
    elseif tone == "warning" then
        color = COLORS.warning
    end
    g_detail_status:SetTextColor(color[1], color[2], color[3], 1)
    g_frame.status_token = (g_frame.status_token or 0) + 1
    local token = g_frame.status_token
    if message and message ~= "" and C_Timer then
        C_Timer.After(30, function()
            if g_frame.status_token == token then
                g_detail_status:SetText("")
            end
        end)
    end
end

g_frame.notify = set_status

local function update_controls()
    local entry = g_selected
    local can_edit = entry ~= nil
        and not entry.readonly
        and not entry.locked
        and not (entry.secure and InCombatLockdown())

    if can_edit then
        g_detail_edit:Enable()
        g_set_button:Enable()
        g_reset_button:Enable()
    else
        g_detail_edit:Disable()
        g_set_button:Disable()
        g_reset_button:Disable()
    end
    g_detail_edit_frame:SetAlpha(can_edit and 1 or 0.55)
    g_set_button:SetAlpha(can_edit and 1 or 0.38)
    g_reset_button:SetAlpha(can_edit and 1 or 0.38)

    if entry and entry.readonly then
        g_detail_name:SetTextColor(
            COLORS.muted[1],
            COLORS.muted[2],
            COLORS.muted[3],
            1
        )
    elseif entry and entry.changed then
        g_detail_name:SetTextColor(
            COLORS.changed[1],
            COLORS.changed[2],
            COLORS.changed[3],
            1
        )
    else
        g_detail_name:SetTextColor(
            COLORS.text[1],
            COLORS.text[2],
            COLORS.text[3],
            1
        )
    end

    if entry and entry.secure and not entry.readonly and InCombatLockdown() then
        set_status("Secure CVar: cannot be changed in combat.", "warning")
    end
    g_frame.update_history_controls()
    g_frame.update_copy_button()
end

local function update_meta(parts)
    local x = 0
    for index = 1, META_MAX_PARTS do
        local part = g_detail_meta_parts[index]
        local spec = parts[index]
        if spec then
            if index > 1 then
                x = round(x + 9)
                local separator = g_detail_meta_separators[index - 1]
                separator:ClearAllPoints()
                separator:SetPoint("LEFT", g_detail_meta, "LEFT", x, 0)
                separator:Show()
                x = x + 10
            end
            part:ClearAllPoints()
            part:SetPoint("LEFT", g_detail_meta, "LEFT", x, 0)
            part:SetText(spec.text)
            part:SetTextColor(
                spec.color[1],
                spec.color[2],
                spec.color[3],
                spec.color[4] or 1
            )
            part:Show()
            x = round(x + part:GetStringWidth())
        else
            part:Hide()
            if index > 1 and g_detail_meta_separators[index - 1] then
                g_detail_meta_separators[index - 1]:Hide()
            end
        end
    end
end

local function update_detail()
    local entry = g_selected
    if not entry then
        g_detail_name:SetText("")
        update_meta({})
        g_detail_help:SetText("")
        g_detail_help:Hide()
        g_detail_edit:SetText("")
        set_status("")
        update_controls()
        return
    end

    g_detail_name:SetText(entry.name)
    update_meta(build_meta_parts(entry))

    if entry.help and entry.help ~= "" then
        g_detail_help:SetText(entry.help)
        g_detail_help:Show()
    else
        g_detail_help:SetText("")
        g_detail_help:Hide()
    end

    g_detail_edit:SetText(display_edit_value(entry, entry.value))
    set_status("")
    update_controls()
end

-- Gauge x offset of bound within [domain_min, domain_min + GAUGE_WIDTH /
-- scale]. Top-level so rendering a row allocates no closure.
local function gauge_x(bound, domain_min, scale)
    return clamp((bound - domain_min) * scale, 0, GAUGE_WIDTH)
end

-- Puts a gauge mark (or slant glyph) of size width x height centered on x,
-- rounded to whole pixels so it never straddles a pixel edge. Vertically
-- it centers in the gauge, rounding an odd gap down so odd heights center
-- on the track row (row 3).
local function place_gauge_mark(gauge, mark, x, width, height)
    -- Cap at the last track column so a 1px tick at x = GAUGE_WIDTH lands
    -- on the track instead of one pixel past it.
    local left = min(round(x - width / 2), GAUGE_WIDTH - 1)
    local top = floor((METRICS.gauge_height - height) / 2)
    mark:ClearAllPoints()
    mark:SetPoint("TOPLEFT", gauge.frame, "TOPLEFT", left, -top)
end

local function update_gauge(gauge, entry)
    local value = entry and tonumber(entry.value)
    local help_min = entry and entry.help_min
    local help_max = entry and entry.help_max
    local observed = entry and entry.observed
    local observed_min = observed and tonumber(observed.min)
    local observed_max = observed and tonumber(observed.max)

    gauge.track:Hide()
    gauge.help_min:Hide()
    gauge.help_max:Hide()
    gauge.observed_min:Hide()
    gauge.observed_max:Hide()
    gauge.cursor:Hide()
    gauge.clamp:Hide()
    gauge.dot:Hide()
    gauge.open_left:Hide()
    gauge.open_right:Hide()

    local domain_min = help_min
    if observed_min ~= nil and (domain_min == nil or observed_min < domain_min) then
        domain_min = observed_min
    end
    local domain_max = help_max
    if observed_max ~= nil and (domain_max == nil or observed_max > domain_max) then
        domain_max = observed_max
    end

    if value == nil or (domain_min == nil and domain_max == nil) then
        gauge.dot:Show()
        return
    end

    local open_left = domain_min == nil
    local open_right = domain_max == nil
    if domain_min == nil then
        domain_min = min(0, domain_max)
    end
    if domain_max == nil then
        local upper = max(value, 0, domain_min + 1, 1)
        domain_max = upper * 1.25
    end
    if domain_max <= domain_min then
        domain_max = domain_min + 1
    end
    local scale = GAUGE_WIDTH / (domain_max - domain_min)

    gauge.track:Show()

    if help_min ~= nil then
        local mark = gauge.help_min
        place_gauge_mark(gauge, mark, gauge_x(help_min, domain_min, scale),
            mark.mark_width, mark.mark_height)
        mark:Show()
    end
    if help_max ~= nil then
        local mark = gauge.help_max
        place_gauge_mark(gauge, mark, gauge_x(help_max, domain_min, scale),
            mark.mark_width, mark.mark_height)
        mark:Show()
    end
    if observed_min ~= nil then
        local mark = gauge.observed_min
        place_gauge_mark(gauge, mark, gauge_x(observed_min, domain_min, scale),
            mark.mark_width, mark.mark_height)
        mark:Show()
    end
    if observed_max ~= nil then
        local mark = gauge.observed_max
        place_gauge_mark(gauge, mark, gauge_x(observed_max, domain_min, scale),
            mark.mark_width, mark.mark_height)
        mark:Show()
    end

    local cursor_x = gauge_x(value, domain_min, scale)
    local cursor_color = entry.changed and COLORS.changed or COLORS.text
    gauge.cursor:SetColorTexture(
        cursor_color[1],
        cursor_color[2],
        cursor_color[3],
        1
    )
    place_gauge_mark(gauge, gauge.cursor, cursor_x,
        gauge.cursor.mark_width, gauge.cursor.mark_height)
    gauge.cursor:Show()

    if entry.clamp_at ~= nil then
        local clamp_x = gauge_x(entry.clamp_at, domain_min, scale)
        if entry.clamp_side == "low" then
            clamp_x = max(0, clamp_x - 2)
        else
            clamp_x = min(GAUGE_WIDTH, clamp_x + 2)
        end
        place_gauge_mark(gauge, gauge.clamp, clamp_x,
            gauge.clamp.mark_width, gauge.clamp.mark_height)
        gauge.clamp:Show()
    end

    -- Slant glyphs center on the track ends. Their size follows the current
    -- font, so measure it each time they show.
    if open_left then
        local glyph = gauge.open_left
        place_gauge_mark(gauge, glyph, 0, round(glyph:GetStringWidth()),
            round(glyph:GetStringHeight()))
        glyph:Show()
    end
    if open_right then
        local glyph = gauge.open_right
        place_gauge_mark(gauge, glyph, GAUGE_WIDTH, round(glyph:GetStringWidth()),
            round(glyph:GetStringHeight()))
        glyph:Show()
    end
end

local function render_row(row, entry)
    if not entry then
        row.entry = nil
        row:Hide()
        return
    end
    row:Show()
    row.entry = entry
    row.name_text:SetText(entry.name)

    local name_color = COLORS.text
    if entry.readonly then
        name_color = COLORS.muted
    elseif entry.changed then
        name_color = COLORS.changed
    elseif g_selected == entry then
        name_color = COLORS.accent
    end
    row.name_text:SetTextColor(
        name_color[1],
        name_color[2],
        name_color[3],
        1
    )

    local raw_value = tostring(entry.value or "?")
    local value_text = nil
    if entry.bitfield and entry.value ~= nil then
        value_text = format("Bitfield (%d bytes)", #raw_value)
    elseif entry.serialized and entry.value ~= nil then
        value_text = format("Serialized (%d bytes)", #raw_value)
    elseif entry.changed then
        -- Leave room for the "(Default: ...)" suffix on changed rows.
        value_text = ellipsize(raw_value, 28)
    else
        value_text = (raw_value:gsub("[\r\n]+", " "))
    end
    if entry.changed then
        local raw_default = entry.default_value
        local default_text = tostring(raw_default or "?")
        if raw_default ~= nil and default_text:match("^%s*$") then
            default_text = "empty"
        end
        local default_display = nil
        if entry.bitfield or entry.serialized then
            default_display = format("%d bytes", #tostring(raw_default or ""))
        else
            default_display = ellipsize(default_text, 14)
        end
        value_text = value_text
            .. " "
            .. MUTED_ESCAPE
            .. "(Default: "
            .. default_display
            .. ")|r"
    end
    row.value_text:SetText(value_text)
    local value_color = entry.readonly and COLORS.muted or COLORS.text
    row.value_text:SetTextColor(
        value_color[1],
        value_color[2],
        value_color[3],
        1
    )

    local is_selected = g_selected == entry
    row.selected_background:SetShown(is_selected)
    row.selected_bar:SetShown(is_selected)
    row.hover:SetShown(not is_selected and row:IsMouseOver())
    update_gauge(row.gauge, entry)
end

local function update_scrollbar()
    local range = g_scroll_frame:GetVerticalScrollRange() or 0
    local viewport = g_scroll_frame:GetHeight() or METRICS.list_height
    if range <= 1 then
        g_scrollbar:Hide()
        return
    end

    g_scrollbar:Show()
    local content = range + viewport
    local thumb_height = max(32, floor(viewport * viewport / content))
    local max_top = viewport - thumb_height
    local scroll = g_scroll_frame:GetVerticalScroll() or 0
    local top = range > 0 and (scroll / range) * max_top or 0

    g_scrollbar_thumb:SetHeight(thumb_height)
    g_scrollbar_thumb:ClearAllPoints()
    g_scrollbar_thumb:SetPoint("TOP", g_scrollbar, "TOP", 0, -top)
    g_frame.snap_box(g_scrollbar_thumb)
end

local function update_rows()
    local total = #g_view
    g_scroll_child:SetHeight(max(1, total * ROW_HEIGHT))
    local offset = g_scroll_frame:GetVerticalScroll() or 0
    -- Use floor, not round, since the partially scrolled-off top row must
    -- still draw.
    local first = floor(offset / ROW_HEIGHT) + 1
    if first < 1 then
        first = 1
    end

    for index = 1, ROW_COUNT do
        local row = g_rows[index]
        local entry = g_view[first + index - 1]
        local y = -((first + index - 2) * ROW_HEIGHT)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", g_scroll_child, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", g_scroll_child, "TOPRIGHT", 0, y)
        render_row(row, entry)
    end
    update_scrollbar()
end

local function select_entry(entry)
    g_selected = entry
    update_detail()
    update_rows()
end

local function rebuild_view()
    local query = trim(g_search_box:GetText() or "")
    local use_pattern = g_frame.regex_enabled == true
    local only_changed = g_changed_button.checked
    local terms = {}
    local filter_scope = nil
    local filter_category = nil
    local filter_type = nil
    local filter_has = nil
    for raw_token in query:gmatch("%S+") do
        local token = raw_token:lower()
        local token_key, value = token:match("^([%w_]+):(.+)$")
        if token_key == "scope" then
            filter_scope = value
        elseif token_key == "category" or token_key == "cat" then
            filter_category = value
        elseif token_key == "type" then
            filter_type = value
        elseif token_key == "has" then
            filter_has = value
        elseif token == "changed" then
            only_changed = true
        else
            -- Pattern mode lowercases only literal letters, since %S/%D/%W/%A
            -- would invert into %s/%d/%w/%a if the class letter changed.
            terms[#terms + 1] = use_pattern
                and (raw_token:gsub("(%%?)(%a)", function(escape, letter)
                    return escape == "" and letter:lower() or nil
                end))
                or token
        end
    end
    local pattern = concat(terms, " ")
    local visual_filters = g_frame.filters
    local visual_has = visual_filters.has

    local function has_state(entry, facet)
        if facet == "range" then
            return entry.range_text ~= nil
        elseif facet == "observed" then
            return entry.range_source == "observed"
        elseif facet == "help" then
            return entry.help_range ~= nil
        elseif facet == "default" then
            return entry.default_value ~= nil
        elseif facet == "changed" then
            return entry.changed
        end
        return true
    end

    local function matches_text(entry)
        if pattern == "" then
            return true
        end
        if use_pattern then
            local ok_name, name_match = pcall(
                string.find,
                entry.name_lower,
                pattern
            )
            if ok_name and name_match then
                return true
            end
            if entry.help_lower then
                local ok_help, help_match = pcall(
                    string.find,
                    entry.help_lower,
                    pattern
                )
                return ok_help and help_match ~= nil
            end
            return false
        end
        for _, term in ipairs(terms) do
            if not entry.name_lower:find(term, 1, true)
                and not (entry.help_lower
                    and entry.help_lower:find(term, 1, true)) then
                return false
            end
        end
        return true
    end

    local function matches_filters(entry)
        if only_changed and not entry.changed then
            return false
        end
        if visual_filters.scope
            and visual_filters.scope ~= ""
            and (entry.scope or ""):lower() ~= visual_filters.scope then
            return false
        end
        if visual_filters.category
            and visual_filters.category ~= ""
            and (entry.category or ""):lower()
                ~= visual_filters.category then
            return false
        end
        if visual_filters.type
            and visual_filters.type ~= ""
            and entry.type_key ~= visual_filters.type then
            return false
        end
        for facet, enabled in pairs(visual_has) do
            if enabled and not has_state(entry, facet) then
                return false
            end
        end
        if filter_scope
            and not (entry.scope or ""):lower():find(
                filter_scope,
                1,
                true
            ) then
            return false
        end
        if filter_category
            and not (entry.category or ""):lower():find(
                filter_category,
                1,
                true
            ) then
            return false
        end
        if filter_type
            and entry.type_key ~= filter_type then
            return false
        end
        if filter_has and not has_state(entry, filter_has) then
            return false
        end
        return true
    end

    local range_count = 0
    g_view = {}

    for _, entry in ipairs(g_entries) do
        -- Inferred once per rebuild, and filters and the type sort reuse it.
        entry.type_key = infer_value_type(entry):lower()
        if matches_filters(entry) and matches_text(entry) then
            g_view[#g_view + 1] = entry
            if entry.range_text then
                range_count = range_count + 1
            end
        end
    end

    local sort_key = g_frame.sort_key or "name"
    local sort_dir = g_frame.sort_dir or "asc"
    if sort_key ~= "name" or sort_dir ~= "asc" then
        local function sort_value(entry, token_key)
            if token_key == "type" then
                return entry.type_key
            elseif token_key == "scope" then
                return (entry.scope or ""):lower()
            elseif token_key == "category" then
                return (entry.category or ""):lower()
            end
            return entry.name_lower
        end
        local function range_width(entry)
            local minimum = entry.help_min
            local maximum = entry.help_max
            local observed = entry.observed
            if observed then
                local observed_min = tonumber(observed.min)
                local observed_max = tonumber(observed.max)
                if observed_min ~= nil
                    and (minimum == nil or observed_min < minimum) then
                    minimum = observed_min
                end
                if observed_max ~= nil
                    and (maximum == nil or observed_max > maximum) then
                    maximum = observed_max
                end
            end
            if minimum ~= nil and maximum ~= nil then
                return maximum - minimum
            end
            return nil
        end
        sort(g_view, function(a, b)
            if sort_key == "changed" then
                if a.changed ~= b.changed then
                    if sort_dir == "desc" then
                        return a.changed
                    end
                    return b.changed
                end
            elseif sort_key == "range" then
                local a_width = range_width(a)
                local b_width = range_width(b)
                if a_width == nil and b_width ~= nil then
                    return false
                elseif a_width ~= nil and b_width == nil then
                    return true
                elseif a_width ~= nil and b_width ~= nil
                    and a_width ~= b_width then
                    if sort_dir == "desc" then
                        return a_width > b_width
                    end
                    return a_width < b_width
                end
            else
                local a_value = sort_value(a, sort_key)
                local b_value = sort_value(b, sort_key)
                if a_value ~= b_value then
                    if sort_dir == "desc" then
                        return a_value > b_value
                    end
                    return a_value < b_value
                end
            end
            return a.name_lower < b.name_lower
        end)
    end

    if g_selected then
        local still_visible = false
        for _, entry in ipairs(g_view) do
            if entry == g_selected then
                still_visible = true
                break
            end
        end
        if not still_visible then
            g_selected = nil
        end
    end
    if not g_selected and #g_view > 0 then
        g_selected = g_view[1]
    end

    g_count_text:SetText(
        format(
            "%d / %d CVars, %d with range",
            #g_view,
            #g_entries,
            range_count
        )
    )
    g_scroll_frame.scroll_target = nil
    g_scroll_frame:SetVerticalScroll(0)
    update_rows()
    update_detail()
end

g_frame.rebuild_results = rebuild_view

local function rescan()
    local selected_name = g_selected and g_selected.name
    g_by_name = {}
    for index = #g_entries, 1, -1 do
        g_entries[index] = nil
    end
    g_view = {}
    g_selected = nil

    local ok, commands = pcall(ConsoleGetAllCommands)
    if not ok or type(commands) ~= "table" then
        rebuild_view()
        set_status(
            "CVar list unavailable: " .. tostring(commands),
            "error"
        )
        return
    end

    for _, info in pairs(commands) do
        if is_cvar_entry(info) then
            local name = info.command
            if not g_by_name[name] then
                local help = info.help
                local category = info.category
                if type(category) == "number" then
                    category = CATEGORY_NAMES[category] or tostring(category)
                end
                local entry = {
                    name = name,
                    name_lower = name:lower(),
                    help = help,
                    help_lower = help and help:lower() or nil,
                    category = category,
                }
                entry.help_range, entry.help_min, entry.help_max =
                    parse_range(help)
                entry.help_enum = parse_enum_help(help)
                read_cvar_value(entry)
                apply_range(entry)
                g_by_name[name] = entry
                g_by_name[entry.name_lower] = entry
                g_entries[#g_entries + 1] = entry
            end
        end
    end

    sort(g_entries, function(a, b)
        return a.name_lower < b.name_lower
    end)

    g_selected = selected_name and g_by_name[selected_name] or nil
    if g_frame.filter_popup:IsShown() then
        g_frame.refresh_filter_menu()
    end
    rebuild_view()
    set_status(format("Loaded %d CVars.", #g_entries))
end

local function apply_value()
    local entry = g_selected
    if not entry then
        return
    end
    if entry.readonly then
        set_status("This CVar is read-only.", "error")
        return
    end
    if entry.locked then
        set_status("This CVar is locked.", "error")
        return
    end
    if entry.secure and InCombatLockdown() then
        set_status("Secure CVar: cannot be changed in combat.", "error")
        return
    end

    local previous = entry.value
    local requested = g_detail_edit:GetText() or ""
    if entry.bitfield or entry.serialized then
        local decoded = hex_to_bitfield(requested)
        if decoded == nil then
            set_status(
                "Bitfield/serialized value must be an even-length hex string.",
                "error"
            )
            return
        end
        requested = decoded
    end
    local ok, result = pcall(SetCVarNative, entry.name, requested)
    if not ok then
        set_status("SetCVar error: " .. tostring(result), "error")
        return
    end
    if result == false then
        set_status("SetCVar refused (read-only/secure/invalid).", "error")
        return
    end

    read_cvar_value(entry)
    local actual = entry.value
    if actual ~= nil and previous ~= nil and actual ~= previous then
        local undo = g_frame.undo_stack
        undo[#undo + 1] = {
            name = entry.name,
            previous = previous,
        }
        if #undo > 20 then
            table.remove(undo, 1)
        end
        g_frame.redo_stack = {}
    end
    local learned = record_observed_bound(entry, requested, previous)
    if learned then
        apply_range(entry)
    end
    if learned and actual ~= nil then
        local requested_number = tonumber(requested)
        local actual_number = tonumber(actual)
        if requested_number and actual_number then
            entry.clamp_at = actual_number
            entry.clamp_side = requested_number > actual_number and "high" or "low"
        end
    else
        entry.clamp_at = nil
        entry.clamp_side = nil
    end

    update_rows()
    if not g_detail_edit:HasFocus() then
        update_detail()
    else
        if actual ~= nil then
            g_detail_edit:SetText(display_edit_value(entry, actual))
            g_detail_edit:HighlightText()
        end
        update_meta(build_meta_parts(entry))
        update_controls()
    end

    local outcome = classify_set_outcome(requested, previous, actual, learned)
    local requested_display = display_edit_value(entry, requested)
    local actual_display = display_edit_value(entry, actual)
    local refused = result == nil
        and actual == previous
        and requested ~= previous
    if refused then
        set_status(
            format(
                "Refused: %s stays %s (read-only/secure/invalid)",
                entry.name,
                actual_display
            ),
            "error"
        )
    elseif outcome == "unverified" then
        set_status(
            format("Set %s; read-back unavailable", entry.name),
            "warning"
        )
    elseif outcome == "accepted" then
        set_status(format("Set %s = %s", entry.name, actual_display))
    elseif outcome == "ignored" then
        set_status(
            format("Ignored: %s stays %s", entry.name, actual_display),
            "error"
        )
    elseif outcome == "clamped" then
        set_status(
            format(
                "%s clamped to %s (asked %s)",
                entry.name,
                actual_display,
                requested_display
            ),
            "warning"
        )
    else
        set_status(
            format(
                "%s normalized to %s",
                entry.name,
                actual_display
            ),
            "warning"
        )
    end
end

local function reset_value()
    if not g_selected or g_selected.readonly then
        return
    end
    g_detail_edit:SetText(
        display_edit_value(g_selected, g_selected.default_value)
    )
    apply_value()
end

local function toggle_changed()
    g_changed_button.checked = not g_changed_button.checked
    if g_changed_button.checked then
        g_changed_tick:Show()
    else
        g_changed_tick:Hide()
    end
    if g_frame.filter_popup:IsShown() then
        g_frame.refresh_filter_menu()
    end
    rebuild_view()
end

local function scroll_to(value, smooth)
    g_frame.scroll_frame_to(g_scroll_frame, value, smooth)
end

local function handle_scrollbar_drag_start()
    local scale = g_frame:GetEffectiveScale() or 1
    local _, cursor_y = GetCursorPosition()
    g_scroll_drag = {
        start_y = cursor_y / scale,
        start_scroll = g_scroll_frame:GetVerticalScroll() or 0,
        max_top = max(1, g_scrollbar:GetHeight() - g_scrollbar_thumb:GetHeight()),
        max_scroll = g_scroll_frame:GetVerticalScrollRange() or 0,
    }
    g_scrollbar_thumb:SetScript("OnUpdate", function()
        if not g_scroll_drag or not IsMouseButtonDown("LeftButton") then
            g_scrollbar_thumb:SetScript("OnUpdate", nil)
            g_scroll_drag = nil
            return
        end
        local current_scale = g_frame:GetEffectiveScale() or 1
        local _, current_y = GetCursorPosition()
        local delta = (g_scroll_drag.start_y - current_y / current_scale)
            / g_scroll_drag.max_top
            * g_scroll_drag.max_scroll
        scroll_to(g_scroll_drag.start_scroll + delta)
    end)
end

local function stop_scrollbar_drag()
    -- Settle on a whole row so the top row is never left half-clipped.
    if g_scroll_drag then
        local current = g_scroll_frame:GetVerticalScroll() or 0
        scroll_to(round(current / ROW_HEIGHT) * ROW_HEIGHT, true)
    end
    g_scroll_drag = nil
    g_scrollbar_thumb:SetScript("OnUpdate", nil)
end

-- Wiring ---------------------------------------------------------------------

-- Custom drag instead of StartMoving, which glides the frame through
-- sub-pixel positions, so text and hairlines shimmered by 1px mid-drag.
-- Each update places the top-left on a whole physical pixel instead.
-- SetPoint offsets are frame units (verified in game), and relative to
-- UIParent's BOTTOMLEFT they equal GetLeft/GetTop directly. The drag
-- starts on mouse down. RegisterForDrag waited for the cursor to travel
-- the client's drag threshold first, which felt sticky.
do
    local function stop_window_drag()
        if not g_frame.drag then
            return
        end
        g_frame.drag = nil
        g_frame:SetScript("OnUpdate", nil)
        -- Mop up any clamp-to-screen residue and persist the anchor.
        snap_frame_position()
        if not g_db then
            return
        end
        local point, _, relative_point, x, y = g_frame:GetPoint(1)
        if point then
            g_db.point = point
            g_db.relativePoint = relative_point
            g_db.x = x or 0
            g_db.y = y or 0
        end
    end

    local function update_window_drag(self)
        local drag = self.drag
        -- A release outside the title bar can skip OnMouseUp.
        if not IsMouseButtonDown("LeftButton") then
            stop_window_drag()
            return
        end
        local current_scale = self:GetEffectiveScale()
        local px = g_px_per_unit
        local x, y = GetCursorPosition()
        local left = round((x / current_scale - drag.x) * px) / px
        local top = round((y / current_scale - drag.y) * px) / px
        if left ~= drag.left or top ~= drag.top then
            drag.left = left
            drag.top = top
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end

    g_titlebar:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        local scale = g_frame:GetEffectiveScale()
        local cursor_x, cursor_y = GetCursorPosition()
        g_frame.drag = {
            x = cursor_x / scale - g_frame:GetLeft(),
            y = cursor_y / scale - g_frame:GetTop(),
        }
        g_frame:SetScript("OnUpdate", update_window_drag)
    end)

    g_titlebar:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            stop_window_drag()
        end
    end)
end

g_close_button:SetScript("OnClick", function()
    g_frame:Hide()
end)

-- Re-lays out the window after a size or screen change. The client only
-- recomputes frame rects for the new size on its next layout pass, so the
-- pixel snapping in the same frame measured stale rects and left parts off
-- the grid (picking the same size again fixed it). A second pass on the
-- next frame snaps against the settled rects. Rows redraw both times
-- because the gauge glyph offsets depend on the font size.
local function relayout()
    apply_ui_scale()
    update_rows()
    C_Timer.After(0, function()
        if g_frame:IsShown() then
            apply_ui_scale()
            update_rows()
        end
    end)
end

g_scale_button:SetScript("OnClick", toggle_scale_popup)
for _, row in ipairs(g_scale_rows) do
    row:SetScript("OnClick", function(self)
        set_layout(self.option.value)
        relayout()
    end)
end

g_search_box:SetScript("OnTextChanged", function(self)
    g_search_placeholder:SetShown(
        (self:GetText() or "") == "" and not self:HasFocus()
    )
    self.navigated = false
    rebuild_view()
end)
g_search_box:SetScript("OnEditFocusGained", function()
    g_search_frame:SetBackdropBorderColor(
        COLORS.accent[1],
        COLORS.accent[2],
        COLORS.accent[3],
        1
    )
    -- The caret blinks where the placeholder starts, so hide it while typing.
    g_search_placeholder:Hide()
end)
g_search_box:SetScript("OnEditFocusLost", function()
    g_search_frame:SetBackdropBorderColor(
        COLORS.border[1],
        COLORS.border[2],
        COLORS.border[3],
        1
    )
    if (g_search_box:GetText() or "") == "" then
        g_search_placeholder:Show()
    end
end)
g_search_box:SetScript("OnEnterPressed", function(self)
    -- Enter keeps a row picked with the arrow keys. Otherwise it takes the
    -- top match.
    local entry = self.navigated and g_selected or g_view[1]
    if entry then
        select_entry(entry)
        if not entry.readonly
            and not (entry.secure and InCombatLockdown()) then
            g_detail_edit:SetFocus()
            g_detail_edit:HighlightText()
        end
    else
        self:ClearFocus()
    end
end)
g_search_box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
g_search_box:SetScript("OnKeyDown", function(self, pressed)
    if pressed ~= "UP" and pressed ~= "DOWN" then
        return
    end
    if #g_view == 0 then
        return
    end
    local index = 1
    if g_selected then
        for position, entry in ipairs(g_view) do
            if entry == g_selected then
                index = position
                break
            end
        end
    end
    if pressed == "DOWN" then
        index = min(index + 1, #g_view)
    else
        index = max(index - 1, 1)
    end
    self.navigated = true
    select_entry(g_view[index])
    scroll_to((index - 1) * ROW_HEIGHT, true)
end)

g_changed_button:SetScript("OnClick", toggle_changed)

g_detail_edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
g_detail_edit:SetScript("OnEnterPressed", function(self)
    apply_value()
    self:HighlightText()
end)
g_detail_edit:SetScript("OnEditFocusGained", function()
    g_hairline.set_color(g_detail_edit_frame.borders, COLORS.accent)
end)
g_detail_edit:SetScript("OnEditFocusLost", function()
    g_hairline.set_color(g_detail_edit_frame.borders, COLORS.border)
end)

g_set_button:SetScript("OnClick", apply_value)
g_reset_button:SetScript("OnClick", reset_value)

g_scroll_frame:SetScript("OnVerticalScroll", function()
    update_rows()
end)
g_scroll_frame:SetScript("OnMouseWheel", function(self, delta)
    -- Chain from the pending target so fast wheel spins accumulate.
    local base = self.scroll_target or self:GetVerticalScroll() or 0
    scroll_to(base - delta * ROW_HEIGHT * 3, true)
end)
g_scroll_frame:SetScript("OnSizeChanged", function(self, width)
    g_scroll_child:SetWidth(width)
    update_scrollbar()
end)

-- Size changes resize the list in several layout steps, so the range can
-- shrink then grow again. If the list was at the bottom, keep it pinned
-- there. Otherwise only pull an offset (and any pending smooth target)
-- back inside a shrunken range so no empty strip shows.
g_scroll_frame:SetScript("OnScrollRangeChanged", function(self, _, y_range)
    y_range = y_range or self:GetVerticalScrollRange() or 0
    local current = self:GetVerticalScroll() or 0
    local last_range = self.last_range
    local was_at_bottom = last_range and last_range > 0
        and current >= last_range - 0.5
    self.last_range = y_range
    if self.scroll_target and self.scroll_target > y_range then
        self.scroll_target = y_range
    end
    if was_at_bottom or current > y_range then
        scroll_to(y_range)
    else
        update_scrollbar()
    end
end)

g_scrollbar_thumb:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
        handle_scrollbar_drag_start()
    end
end)
g_scrollbar_thumb:SetScript("OnMouseUp", stop_scrollbar_drag)

for index = 1, ROW_COUNT do
    local row = g_rows[index]
    row:SetScript("OnClick", function(self)
        if self.entry then
            select_entry(self.entry)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.entry and g_selected ~= self.entry then
            self.hover:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
    end)
end

g_frame:SetScript("OnShow", function(self)
    self:Raise()
    g_scale_popup:Hide()
    g_frame.close_menus()
    apply_ui_scale()
    rescan()
end)

g_frame:SetScript("OnEvent", function(self, event, argument)
    if event == "ADDON_LOADED" then
        if argument ~= g_addon_name then
            return
        end
        init_db()
        self:ClearAllPoints()
        -- g_db.x/y were saved as an on-grid anchor by the drag (rendered pixel
        -- locked). Restore them verbatim, since re-rounding them here on a
        -- different grid would fight the drag grid and shift the frame by a
        -- pixel.
        -- snap_frame_position() in apply_ui_scale is the single authoritative
        -- rendered-pixel snap.
        local x = tonumber(g_db.x) or 0
        local y = tonumber(g_db.y) or 0
        local ok = pcall(
            self.SetPoint,
            self,
            g_db.point or "CENTER",
            UIParent,
            g_db.relativePoint or "CENTER",
            x,
            y
        )
        if not ok then
            self:ClearAllPoints()
            self:SetPoint("CENTER")
        end
        apply_ui_scale()
        if type(g_frame.minimap_button) == "table" then
            g_frame.minimap_button:update_position()
            g_frame.minimap_button:SetShown(not g_db.minimap_hidden)
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "CVAR_UPDATE" then
        -- The payload keeps the caller's casing. g_by_name also keys
        -- lowercase.
        local entry = type(argument) == "string"
            and (g_by_name[argument] or g_by_name[argument:lower()])
        if entry then
            read_cvar_value(entry)
            apply_range(entry)
            update_rows()
            if g_selected == entry and not g_detail_edit:HasFocus() then
                update_detail()
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        update_controls()
    elseif event == "UI_SCALE_CHANGED"
        or event == "DISPLAY_SIZE_CHANGED" then
        relayout()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if self:IsShown() then
            rescan()
        end
    end
end)

g_frame:RegisterEvent("ADDON_LOADED")
g_frame:RegisterEvent("CVAR_UPDATE")
g_frame:RegisterEvent("PLAYER_REGEN_DISABLED")
g_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
g_frame:RegisterEvent("PLAYER_ENTERING_WORLD")
g_frame:RegisterEvent("UI_SCALE_CHANGED")
g_frame:RegisterEvent("DISPLAY_SIZE_CHANGED")

-- Slash commands -------------------------------------------------------------

-- WoW's chat code scans globals named SLASH_<KEY><n> (n = 1, 2, ...)
-- and routes each listed command to SlashCmdList["<KEY>"]. The
-- handler gets the rest of the line after the command word.
SLASH_CVARBROWSER1 = "/cvars"
SLASH_CVARBROWSER2 = "/cb"
SLASH_CVARBROWSER3 = "/cvarbrowser"

do
    -- Undo and redo are mirror images. Pop one stack, re-apply its previous
    -- value, and push the value it replaced onto the other stack.
    local function step_history(verb)
        local is_undo = verb == "undo"
        local from = is_undo and g_frame.undo_stack or g_frame.redo_stack
        local last = from[#from]
        if not last then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r nothing to " .. verb
            )
            return
        end
        if not g_frame:IsShown() then
            g_frame:Show()
        end
        local entry = g_by_name[last.name]
        if not entry then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r CVar no longer exists: " .. last.name
            )
            return
        end
        if entry.readonly or entry.locked
            or (entry.secure and InCombatLockdown()) then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r cannot " .. verb .. " " .. last.name
                    .. " in its current state"
            )
            return
        end
        local title = is_undo and "Undo" or "Redo"
        local current = entry.value
        from[#from] = nil
        local ok, result = pcall(SetCVarNative, last.name, last.previous)
        if not ok or result == false then
            from[#from + 1] = last
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r " .. verb .. " refused for " .. last.name
            )
            set_status(title .. " refused: " .. last.name, "error")
            return
        end
        read_cvar_value(entry)
        if entry.value ~= last.previous then
            from[#from + 1] = last
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r " .. verb .. " did not stick for "
                    .. last.name
            )
            set_status(title .. " did not stick: " .. last.name, "error")
            return
        end
        local to = is_undo and g_frame.redo_stack or g_frame.undo_stack
        to[#to + 1] = {
            name = last.name,
            previous = current,
        }
        if not is_undo and #to > 20 then
            table.remove(to, 1)
        end
        apply_range(entry)
        select_entry(entry)
        local text = format(
            is_undo and "Undid %s; restored %s" or "Redid %s; now %s",
            last.name,
            display_edit_value(entry, entry.value)
        )
        set_status(text)
        DEFAULT_CHAT_FRAME:AddMessage("|cffB7A3CCCVarBrowser|r " .. text)
    end

    SlashCmdList["CVARBROWSER"] = function(message)
        local message_text = trim(message or "")
        local lower = message_text:lower()

        if lower == "minimap" or lower:match("^minimap%s+") then
            if type(g_frame.minimap_button) ~= "table" then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffB7A3CCCVarBrowser|r minimap button unavailable"
                )
                return
            end
            local argument = lower:match("^minimap%s+(%S+)")
            if argument == "reset" then
                if g_db then
                    g_db.minimap_angle = 220
                end
                g_frame.minimap_button:update_position()
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffB7A3CCCVarBrowser|r minimap angle reset"
                )
            else
                if g_db then
                    g_db.minimap_hidden = not g_db.minimap_hidden
                end
                local hidden = g_db and g_db.minimap_hidden
                g_frame.minimap_button:SetShown(not hidden)
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffB7A3CCCVarBrowser|r minimap button "
                        .. (hidden and "hidden" or "shown")
                )
            end
            return
        end

        if lower == "copy" or lower:match("^copy%s+") then
            if not g_frame:IsShown() then
                g_frame:Show()
            end
            local field = lower:match("^copy%s+(%S+)") or "value"
            local target_name = lower:match("^copy%s+%S+%s+(%S+)")
            local known = {
                value = true,
                raw = true,
                default = true,
                name = true,
                help = true,
                range = true,
            }
            if not known[field] then
                target_name = field
                field = "value"
            end
            local entry = g_selected
            if target_name then
                entry = g_by_name[target_name]
            end
            if not entry then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffB7A3CCCVarBrowser|r no CVar selected to copy"
                )
                return
            end
            local value = nil
            if field == "name" then
                value = entry.name
            elseif field == "default" then
                value = entry.default_value
            elseif field == "help" then
                value = entry.help
            elseif field == "range" then
                value = entry.range_text
            elseif field == "raw" then
                value = entry.value
            else
                value = display_edit_value(entry, entry.value)
            end
            if value == nil or value == "" then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffB7A3CCCVarBrowser|r nothing to copy for "
                        .. entry.name
                )
                return
            end
            g_frame.close_menus()
            g_frame.show_copy_box(tostring(value))
            set_status("Press Ctrl+C to copy " .. field .. ": " .. entry.name)
            return
        end

        if lower == "help" then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r commands: "
                    .. "/cvars | /cb, /cvars <name>, refresh, undo, redo, "
                    .. "ranges [name], clearrange <name>, clearranges, "
                    .. "sort name|type|scope|category|changed|range [asc|desc], "
                    .. "copy [value|raw|default|name|help|range] [cvar], "
                    .. "regex [on|off], smooth [on|off], minimap [reset], filters"
            )
            return
        end

        local sort_key, sort_dir = lower:match("^sort%s+(%S+)%s*(%S*)$")
        if sort_key then
            local valid = sort_key == "name"
                or sort_key == "type"
                or sort_key == "scope"
                or sort_key == "category"
                or sort_key == "changed"
                or sort_key == "range"
            if not valid then
                set_status(
                    "Sort must be name, type, scope, category, changed, or range.",
                    "error"
                )
                return
            end
            if sort_dir ~= "" and sort_dir ~= "asc" and sort_dir ~= "desc" then
                set_status("Sort direction must be asc or desc.", "error")
                return
            end
            g_frame.sort_key = sort_key
            if sort_dir == "" then
                sort_dir = sort_key == "changed" and "desc" or "asc"
            end
            g_frame.sort_dir = sort_dir
            g_frame.update_sort_chip()
            rebuild_view()
            set_status("Sorted by " .. sort_key .. " " .. sort_dir)
            return
        end

        if lower == "regex" or lower:match("^regex%s+") then
            local value = lower:match("^regex%s+(%S+)")
            if value == "on" then
                g_frame.regex_enabled = true
            elseif value == "off" then
                g_frame.regex_enabled = false
            else
                g_frame.regex_enabled = not g_frame.regex_enabled
            end
            g_frame.update_regex_chip()
            rebuild_view()
            local text = "Pattern search "
                .. (g_frame.regex_enabled and "on" or "off")
            set_status(text)
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r " .. text
            )
            return
        end

        if lower == "smooth" or lower:match("^smooth%s+") then
            local value = lower:match("^smooth%s+(%S+)")
            if value == "on" then
                g_db.smooth_scroll = true
            elseif value == "off" then
                g_db.smooth_scroll = false
            else
                g_db.smooth_scroll = not g_db.smooth_scroll
            end
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r smooth scrolling "
                    .. (g_db.smooth_scroll and "on" or "off")
            )
            return
        end

        if lower == "filters" then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r filters: "
                    .. "scope:account|character|local, "
                    .. "cat:graphics, "
                    .. "type:number|boolean|enum|text|list|bitfield|serialized, "
                    .. "has:range|observed|help|default|changed; "
                    .. "changed; /cb regex for Lua-pattern search"
            )
            return
        end

        if lower == "undo" or lower == "redo" then
            step_history(lower)
            return
        end

        if lower == "refresh" or lower == "rescan" then
            if g_frame:IsShown() then
                rescan()
            else
                g_frame:Show()
            end
            return
        end

        if lower == "ranges" or lower:match("^ranges%s+") then
            local only = lower:match("^ranges%s+(.+)$")
            only = only and trim(only) or nil
            local names = {}
            if g_db and type(g_db.observed) == "table" then
                for name in pairs(g_db.observed) do
                    if not only or name:lower() == only then
                        names[#names + 1] = name
                    end
                end
            end
            sort(names)
            if #names == 0 then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffB7A3CCCVarBrowser|r no observed ranges"
                        .. (only and (" for " .. only) or "")
                )
                return
            end
            DEFAULT_CHAT_FRAME:AddMessage(
                format(
                    "|cffB7A3CCCVarBrowser|r %d observed range%s",
                    #names,
                    #names == 1 and "" or "s"
                )
            )
            for _, name in ipairs(names) do
                local observed = g_db.observed[name]
                local entry = g_by_name[name]
                local range = format_observed_range(observed) or "?"
                local evidence = format_observed_evidence(observed) or "clamp"
                DEFAULT_CHAT_FRAME:AddMessage(
                    format(
                        "  %s: %s [clamp] %s",
                        name,
                        range,
                        evidence
                    )
                )
                if entry and entry.help_range then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        format("    help: %s", entry.help_range)
                    )
                end
            end
            return
        end

        if lower == "clearranges" then
            local count = 0
            if g_db and type(g_db.observed) == "table" then
                for _ in pairs(g_db.observed) do
                    count = count + 1
                end
                g_db.observed = {}
            end
            DEFAULT_CHAT_FRAME:AddMessage(
                format(
                    "|cffB7A3CCCVarBrowser|r cleared %d observed range%s",
                    count,
                    count == 1 and "" or "s"
                )
            )
            if g_frame:IsShown() then
                rescan()
            else
                g_frame:Show()
            end
            return
        end

        if lower:match("^clearrange%s+.") then
            -- Match case-insensitively but echo the stored or typed casing.
            local clear_name = trim(message_text:match("^%S+%s+(.+)$"))
            local found = nil
            if g_db and type(g_db.observed) == "table" then
                for name in pairs(g_db.observed) do
                    if name:lower() == clear_name:lower() then
                        g_db.observed[name] = nil
                        found = name
                        break
                    end
                end
            end
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r "
                    .. (found and ("cleared " .. found)
                        or ("no observed range for " .. clear_name))
            )
            if g_frame:IsShown() then
                rescan()
            else
                g_frame:Show()
            end
            return
        end

        if message_text ~= "" then
            if not g_frame:IsShown() then
                g_frame:Show()
            end
            g_search_box:SetText(message_text)
            g_search_box:ClearFocus()
            rebuild_view()
            if #g_view > 0 then
                select_entry(g_view[1])
                if not g_view[1].readonly
                    and not (g_view[1].secure and InCombatLockdown()) then
                    g_detail_edit:SetFocus()
                    g_detail_edit:HighlightText()
                end
            end
            return
        end

        if g_frame:IsShown() then
            g_frame:Hide()
        else
            g_frame:Show()
        end
    end
end
