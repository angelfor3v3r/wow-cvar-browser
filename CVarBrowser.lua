local addon_name = ...

-- Localized WoW APIs ---------------------------------------------------------

local CreateFrame = CreateFrame
local CreateFont = CreateFont
local UIParent = UIParent
local UISpecialFrames = UISpecialFrames
local SlashCmdList = SlashCmdList
local C_CVar = C_CVar
local C_Console = C_Console
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local IsMouseButtonDown = IsMouseButtonDown
local GetPhysicalScreenSize = GetPhysicalScreenSize
local STANDARD_TEXT_FONT = STANDARD_TEXT_FONT
local GetCVarInfo = GetCVarInfo or (C_CVar and C_CVar.GetCVarInfo)
local GetCVar = GetCVar or (C_CVar and C_CVar.GetCVar)
local GetCVarDefault = GetCVarDefault or (C_CVar and C_CVar.GetCVarDefault)
local SetCVarNative = (C_CVar and C_CVar.SetCVar) or SetCVar
local ConsoleGetAllCommands = ConsoleGetAllCommands
    or (C_Console and C_Console.GetAllCommands)

local pairs, ipairs = pairs, ipairs
local type, tostring, tonumber = type, tostring, tonumber
local pcall, select, unpack = pcall, select, unpack
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local insert, sort, concat = table.insert, table.sort, table.concat

-- Physical pixels represented by one UI unit after scale compensation:
-- pixel is per frame unit, drag is per cursor screen unit, snap is per
-- anchor offset unit. Cursor screen units convert to frame units by
-- dividing by the region's effective scale, never by these values.
local SCALE = {
    pixel = 1,
    drag = 1,
    snap = 1,
}

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local MEDIA_PATH = "Interface\\AddOns\\CVarBrowser\\Media\\"
local FONT_REGULAR_PATH = MEDIA_PATH .. "NotoSans-Regular.ttf"
local FONT_SEMIBOLD_PATH = MEDIA_PATH .. "NotoSans-SemiBold.ttf"

local FRAME_WIDTH = 920
local FRAME_HEIGHT = 680
local ROW_HEIGHT = 22
local ROW_COUNT = 18
local LIST_TOP = 152
local LIST_BOTTOM = 188
local LIST_LEFT = 24
local LIST_RIGHT = 48
local LIST_BOTTOM = 188
local LIST_WIDTH = FRAME_WIDTH - LIST_LEFT - LIST_RIGHT
local LIST_HEIGHT = FRAME_HEIGHT - LIST_TOP - LIST_BOTTOM
local DETAIL_WIDTH = FRAME_WIDTH - 48
local GAUGE_WIDTH = 88
local GAUGE_HEIGHT = 8
local META_MAX_PARTS = 6

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

local function create_font(name, path, size)
    local font = CreateFont(name)
    local ok = pcall(
        font.SetFont,
        font,
        path,
        size,
        ""
    )
    if not ok then
        font:SetFont(STANDARD_TEXT_FONT, size, "")
    end
    return font
end

local FONT_TITLE = create_font("CVarBrowserTitle20", FONT_SEMIBOLD_PATH, 20)
local FONT_DETAIL = create_font("CVarBrowserDetail15", FONT_SEMIBOLD_PATH, 15)
local FONT_BODY = create_font("CVarBrowserBody13", FONT_REGULAR_PATH, 13)
local FONT_META = create_font("CVarBrowserMeta11", FONT_REGULAR_PATH, 11)
local FONT_CHECK = create_font(
    "CVarBrowserCheck14",
    MEDIA_PATH .. "Inter-SemiBold.ttf",
    14
)

local function resize_font(font, path, size)
    local ok = pcall(font.SetFont, font, path, size, "")
    if not ok then
        font:SetFont(STANDARD_TEXT_FONT, size, "")
    end
end

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

local function snap(value)
    return floor(value + 0.5)
end

local function color_escape(color)
    return format(
        "|cff%02x%02x%02x",
        floor(color[1] * 255 + 0.5),
        floor(color[2] * 255 + 0.5),
        floor(color[3] * 255 + 0.5)
    )
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
    bgFile = WHITE_TEXTURE,
    edgeFile = WHITE_TEXTURE,
    tile = false,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

-- Backdrop borders are sized in region units. edgeSize must be 1/px_per_unit
-- region units (px_per_unit = physical px per region unit = effective scale) so
-- the border is exactly one physical pixel. A fixed edgeSize of 1 renders half a
-- physical pixel at fractional scale (rounds to 0 or 2px). apply_ui_scale calls
-- set_backdrop_edge_size to re-apply on scale change.
local backdrop_frames = {}

local function set_backdrop_edge_size(px_per_unit)
    if not px_per_unit or px_per_unit <= 0 then
        px_per_unit = 1
    end
    local edge = 1 / px_per_unit
    for _, bframe in ipairs(backdrop_frames) do
        if bframe.SetBackdropBorderSize then
            bframe:SetBackdropBorderSize(edge)
        end
    end
end

local function apply_backdrop(frame, background, border)
    frame:SetBackdrop(BACKDROP)
    if background then
        frame:SetBackdropColor(
            background[1],
            background[2],
            background[3],
            background[4] or 1
        )
    else
        frame:SetBackdropColor(0, 0, 0, 0)
    end
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    backdrop_frames[#backdrop_frames + 1] = frame
    -- Border size is set to one physical pixel by set_backdrop_edge_size at
    -- layout (it has the measured px-per-region-unit); the initial BACKDROP
    -- edgeSize of 1 is only a placeholder until then.
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

local hairline = { items = {}, scale = 1 }

function hairline.set_size(item)
    local thickness = 1 / hairline.scale
    if item.axis == "height" then
        item.texture:SetHeight(thickness)
    elseif item.axis == "width" then
        item.texture:SetWidth(thickness)
    elseif item.axis == "border-v" then
        -- Vertical border edge: thickness is the width, and the top/bottom
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

function hairline.register(texture, axis, frame)
    local item = { texture = texture, axis = axis, frame = frame }
    hairline.items[#hairline.items + 1] = item
    hairline.set_size(item)
    return texture
end

function hairline.set_scale(scale)
    if not scale or scale <= 0 then
        scale = 1
    end
    hairline.scale = scale
    for _, item in ipairs(hairline.items) do
        hairline.set_size(item)
    end
end

function hairline.set_color(borders, color)
    for _, texture in ipairs(borders) do
        texture:SetColorTexture(color[1], color[2], color[3], 1)
    end
end

local function add_border(frame, color)
    -- Horizontal edges span the full width and own the corners; vertical edges
    -- are inset by the border thickness (handled by hairline's border-v axes) so
    -- edges butt together without overlapping. Overlapping opaque corner
    -- textures double the opacity there (visible on the undo/redo buttons).
    local top = snap_texture(frame:CreateTexture(nil, "BORDER"))
    top:SetColorTexture(color[1], color[2], color[3], 1)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    hairline.register(top, "height", frame)

    local bottom = snap_texture(frame:CreateTexture(nil, "BORDER"))
    bottom:SetColorTexture(color[1], color[2], color[3], 1)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    hairline.register(bottom, "height", frame)

    local left = snap_texture(frame:CreateTexture(nil, "BORDER"))
    left:SetColorTexture(color[1], color[2], color[3], 1)
    hairline.register(left, "border-v", frame)

    local right = snap_texture(frame:CreateTexture(nil, "BORDER"))
    right:SetColorTexture(color[1], color[2], color[3], 1)
    hairline.register(right, "border-vr", frame)
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

local function create_slant_text(parent, text, x, y)
    local label = make_text(parent, FONT_META, text, COLORS.muted)
    label:SetAlpha(0.8)
    label:SetPoint("CENTER", parent, "LEFT", x, y or 0)
    return label
end

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

-- Data / range helpers -------------------------------------------------------

local entries = {}
local by_name = {}
local view = {}
local selected = nil
local db = nil

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

local function read_cvar_value(entry)
    local value
    local default_value
    local scope
    local locked
    local secure
    local readonly

    if GetCVarInfo then
        local count_ok, count = pcall(function()
            return select("#", GetCVarInfo(entry.name))
        end)
        local ok, _, returned_default, account_wide, per_character, c, d, e =
            pcall(GetCVarInfo, entry.name)
        if count_ok and ok then
            default_value = returned_default
            if count >= 7 then
                scope = account_wide and "Account"
                    or (per_character and "Character" or "Local")
                locked = c
                secure = d
                readonly = e
            elseif count >= 4 then
                scope = account_wide and "Account"
                    or (per_character and "Character" or "Local")
            elseif count >= 3 then
                scope = account_wide and "Account" or "Local"
            end
        end
    end

    if GetCVar then
        local ok, fallback = pcall(GetCVar, entry.name)
        if ok then
            value = fallback
        end
    end

    -- Fallback for clients whose GetCVar is absent but GetCVarInfo returns a
    -- value first. On the documented API the first return is the canonical
    -- name, so never use it when it matches the requested name.
    if value == nil and GetCVarInfo then
        local ok, first, fallback_default = pcall(GetCVarInfo, entry.name)
        if ok and first ~= entry.name then
            value = first
        end
        if default_value == nil then
            default_value = fallback_default
        end
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
    if not db or type(db.observed) ~= "table" then
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

    local observed = db.observed[entry.name]
    if type(observed) ~= "table" then
        observed = {}
        db.observed[entry.name] = observed
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
    db = CVarBrowserDB
    for key, value in pairs(DB_DEFAULTS) do
        if db[key] == nil then
            db[key] = value
        end
    end
    if type(db.observed) ~= "table" then
        db.observed = {}
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

-- UI objects -----------------------------------------------------------------

local frame
local titlebar
local close_button
local scale_button
local scale_popup
local scale_rows = {}
local search_frame
local search_box
local search_placeholder
local changed_button
local changed_box
local changed_tick
local changed_label
local count_text
local scroll_frame
local scroll_child
local scrollbar
local scrollbar_track
local scrollbar_thumb
local rows = {}
local detail
local detail_name
local detail_meta
local detail_meta_parts = {}
local detail_meta_separators = {}
local detail_help
local detail_edit_frame
local detail_edit
local set_button
local reset_button
local detail_status
local key
local hint
local scroll_drag

local function create_gauge(parent)
    local gauge = CreateFrame("Frame", nil, parent)
    gauge:SetSize(GAUGE_WIDTH, GAUGE_HEIGHT)

    local track = snap_texture(gauge:CreateTexture(nil, "ARTWORK"))
    track:SetColorTexture(
        COLORS.border[1],
        COLORS.border[2],
        COLORS.border[3],
        1
    )
    track:SetHeight(1)
    track:SetPoint("LEFT", gauge, "LEFT", 0, 0)
    track:SetPoint("RIGHT", gauge, "RIGHT", 0, 0)

    local function make_mark(width, height, color)
        local mark = snap_texture(gauge:CreateTexture(nil, "ARTWORK"))
        mark:SetColorTexture(color[1], color[2], color[3], 1)
        mark:SetSize(width, height)
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
    dot:SetPoint("CENTER", gauge, "CENTER", 0, 0)

    local open_left = create_slant_text(gauge, "/", 0, 0)
    local open_right = create_slant_text(gauge, "\\", GAUGE_WIDTH, 0)
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
    local row = CreateFrame("Button", nil, scroll_child)
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
    hairline.register(separator, "width")
    separator:SetHeight(11)
    separator:Hide()
    return separator
end

local function create_readonly_mark(parent)
    local mark = CreateFrame("Frame", nil, parent)
    mark:SetSize(9, 9)
    -- Full-span outline: the left/right lines run the mark's full height
    -- and the top/bottom lines its full width, so both draw each corner
    -- (solid color; the overlap is invisible). add_border's butt joints,
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
    hairline.register(top, "height", mark)

    local bottom = snap_texture(mark:CreateTexture(nil, "BORDER"))
    bottom:SetColorTexture(
        COLORS.muted[1],
        COLORS.muted[2],
        COLORS.muted[3],
        1
    )
    bottom:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
    hairline.register(bottom, "height", mark)

    local left = snap_texture(mark:CreateTexture(nil, "BORDER"))
    left:SetColorTexture(
        COLORS.muted[1],
        COLORS.muted[2],
        COLORS.muted[3],
        1
    )
    left:SetPoint("TOPLEFT", mark, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", 0, 0)
    hairline.register(left, "width", mark)

    local right = snap_texture(mark:CreateTexture(nil, "BORDER"))
    right:SetColorTexture(
        COLORS.muted[1],
        COLORS.muted[2],
        COLORS.muted[3],
        1
    )
    right:SetPoint("TOPRIGHT", mark, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
    hairline.register(right, "width", mark)
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

-- Flow layout of the hint marks: 4px margins on both sides of the slant
-- group and the dot (the mockup's .key-dot margin). Re-run after font
-- resizes so measured advances never drift from rendered text.
local function layout_hint(hint_frame)
    local x = 0
    hint_frame.first:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
    x = snap(x + hint_frame.first:GetStringWidth()) + 4
    hint_frame.slants:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
    x = snap(x + 14) + 4
    hint_frame.second:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
    x = snap(x + hint_frame.second:GetStringWidth()) + 4
    hint_frame.dot:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
    x = snap(x + 2) + 4
    hint_frame.third:SetPoint("LEFT", hint_frame, "LEFT", x, 0)
    x = snap(x + hint_frame.third:GetStringWidth())
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

-- Root UI --------------------------------------------------------------------

frame = CreateFrame("Frame", "CVarBrowserFrame", UIParent, "BackdropTemplate")
frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:Hide()
frame.regex_enabled = false
frame.sort_key = "name"
frame.sort_dir = "asc"
frame.filters = {
    scope = "",
    category = "",
    type = "",
    has = {},
}
frame.undo_stack = {}
frame.redo_stack = {}
apply_backdrop(frame, COLORS.background, COLORS.border)
insert(UISpecialFrames, "CVarBrowserFrame")

titlebar = CreateFrame("Frame", nil, frame)
titlebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
titlebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
titlebar:SetHeight(44)
titlebar:EnableMouse(true)
titlebar:RegisterForDrag("LeftButton")

local titlebar_border = snap_texture(titlebar:CreateTexture(nil, "ARTWORK"))
titlebar_border:SetColorTexture(
    COLORS.border[1],
    COLORS.border[2],
    COLORS.border[3],
    1
)
titlebar_border:SetPoint("BOTTOMLEFT", titlebar, "BOTTOMLEFT", 0, 0)
titlebar_border:SetPoint("BOTTOMRIGHT", titlebar, "BOTTOMRIGHT", 0, 0)
hairline.register(titlebar_border, "height")

local brand_bar = snap_texture(titlebar:CreateTexture(nil, "ARTWORK"))
brand_bar:SetColorTexture(
    COLORS.accent[1],
    COLORS.accent[2],
    COLORS.accent[3],
    1
)
brand_bar:SetSize(3, 18)
brand_bar:SetPoint("LEFT", titlebar, "LEFT", 24, 0)

local title = make_text(titlebar, FONT_TITLE, "CVar Browser", COLORS.text)
title:SetPoint("LEFT", titlebar, "LEFT", 39, 0)

local subtitle = make_text(
    titlebar,
    FONT_META,
    "WoW Forever",
    COLORS.muted
)
subtitle:SetPoint("LEFT", title, "RIGHT", 12, 0)
subtitle:SetJustifyV("MIDDLE")

scale_button = CreateFrame("Button", nil, titlebar)
scale_button:SetSize(112, 24)
scale_button:SetPoint("RIGHT", titlebar, "RIGHT", -52, 0)
scale_button.background = scale_button:CreateTexture(nil, "BACKGROUND")
scale_button.background:SetAllPoints(scale_button)
scale_button.background:SetColorTexture(
    COLORS.surface[1],
    COLORS.surface[2],
    COLORS.surface[3],
    1
)
scale_button.borders = add_border(scale_button, COLORS.border)
scale_button.label = make_text(
    scale_button,
    FONT_META,
    "Size: Standard",
    COLORS.muted
)
scale_button.label:SetPoint("LEFT", scale_button, "LEFT", 4, 0)
scale_button.label:SetJustifyH("LEFT")
scale_button:SetScript("OnEnter", function(self)
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
scale_button:SetScript("OnLeave", function(self)
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

close_button = CreateFrame("Button", nil, titlebar)
close_button:SetSize(28, 28)
close_button:SetPoint("RIGHT", titlebar, "RIGHT", -16, 0)
close_button.label = make_text(close_button, FONT_TITLE, "×", COLORS.muted)
close_button.label:SetPoint("CENTER", close_button, "CENTER", 0, 0)
close_button:SetScript("OnEnter", function(self)
    self.label:SetTextColor(
        COLORS.error[1],
        COLORS.error[2],
        COLORS.error[3],
        1
    )
end)
close_button:SetScript("OnLeave", function(self)
    self.label:SetTextColor(
        COLORS.muted[1],
        COLORS.muted[2],
        COLORS.muted[3],
        1
    )
end)

search_frame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
search_frame:SetSize(300, 32)
search_frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -58)
apply_backdrop(search_frame, COLORS.surface, COLORS.border)

search_box = CreateFrame("EditBox", nil, search_frame)
search_box:SetPoint("TOPLEFT", search_frame, "TOPLEFT", 10, 0)
search_box:SetPoint("BOTTOMRIGHT", search_frame, "BOTTOMRIGHT", -10, 0)
search_box:SetAutoFocus(false)
search_box:SetFontObject(FONT_BODY)
search_box:SetTextColor(
    COLORS.text[1],
    COLORS.text[2],
    COLORS.text[3],
    1
)
search_box:SetTextInsets(12, 0, 0, 0)

frame.search_icon = search_frame:CreateTexture(nil, "ARTWORK")
frame.search_icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
frame.search_icon:SetSize(14, 14)
frame.search_icon:SetPoint("LEFT", search_frame, "LEFT", 4, 0)
frame.search_icon:SetVertexColor(
    COLORS.muted[1],
    COLORS.muted[2],
    COLORS.muted[3],
    1
)

search_placeholder = make_text(
    search_frame,
    FONT_BODY,
    "Search CVars",
    COLORS.muted
)
search_placeholder:SetPoint("LEFT", search_frame, "LEFT", 22, 0)
search_placeholder:SetJustifyH("LEFT")

frame.regex_chip = create_button(frame, ".*", 26, 26)
frame.regex_chip:SetPoint("LEFT", search_frame, "RIGHT", 16, 0)
frame.regex_chip.label:SetFontObject(FONT_META)
frame.regex_chip.underline = snap_texture(
    frame.regex_chip:CreateTexture(nil, "ARTWORK")
)
frame.regex_chip.underline:SetColorTexture(
    COLORS.accent[1],
    COLORS.accent[2],
    COLORS.accent[3],
    1
)
frame.regex_chip.underline:SetPoint(
    "BOTTOMLEFT",
    frame.regex_chip,
    "BOTTOMLEFT",
    2,
    0
)
frame.regex_chip.underline:SetPoint(
    "BOTTOMRIGHT",
    frame.regex_chip,
    "BOTTOMRIGHT",
    -2,
    0
)
hairline.register(frame.regex_chip.underline, "height")
frame.regex_chip.underline:Hide()

changed_button = CreateFrame("Button", nil, frame)
changed_button:SetSize(160, 32)
changed_button:SetPoint("LEFT", frame.regex_chip, "RIGHT", 16, 0)
changed_button.checked = false

changed_box = CreateFrame("Frame", nil, changed_button)
changed_box:SetSize(18, 18)
changed_box:SetPoint("LEFT", changed_button, "LEFT", 0, 0)

local changed_box_background = snap_texture(changed_box:CreateTexture(nil, "BACKGROUND"))
changed_box_background:SetAllPoints(changed_box)
changed_box_background:SetColorTexture(
    COLORS.surface[1],
    COLORS.surface[2],
    COLORS.surface[3],
    1
)
add_border(changed_box, COLORS.border)

changed_tick = make_text(changed_box, FONT_CHECK, "✓", COLORS.accent)
changed_tick:SetPoint("CENTER", changed_box, "CENTER", 1, 0)
changed_tick:Hide()

changed_label = make_text(
    changed_button,
    FONT_BODY,
    "Changed only",
    COLORS.text
)
changed_label:SetPoint("LEFT", changed_box, "RIGHT", 8, 0)

count_text = make_text(frame, FONT_META, "", COLORS.muted)
count_text:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -67)
count_text:SetJustifyH("RIGHT")

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
        local filters = frame.filters
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
        local popup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        popup:SetSize(width, height)
        popup:SetFrameLevel(frame:GetFrameLevel() + 20)
        popup:Hide()
        apply_backdrop(popup, COLORS.surface, COLORS.border)
        return popup
    end

    local function fit_chip(button, minimum, left_padding)
        button:SetWidth(
            max(
                minimum,
                snap(
                    left_padding
                        + button.label:GetStringWidth()
                        + 6
                )
            )
        )
    end

    frame.filter_chip = create_button(frame, "Filters off", 104, 26)
    frame.filter_chip:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -94)
    frame.filter_chip.label:SetFontObject(FONT_META)
    frame.filter_chip.label:ClearAllPoints()
    frame.filter_chip.label:SetPoint(
        "LEFT",
        frame.filter_chip,
        "LEFT",
        18,
        0
    )
    frame.filter_chip.label:SetJustifyH("LEFT")
    local filter_icon = CreateFrame("Frame", nil, frame.filter_chip)
    filter_icon:SetSize(10, 9)
    filter_icon:SetPoint("TOPLEFT", frame.filter_chip, "TOPLEFT", 4, -9)
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

    frame.sort_chip = create_button(frame, "Sort name asc", 150, 26)
    frame.sort_chip:SetPoint("LEFT", frame.filter_chip, "RIGHT", 8, 0)
    frame.sort_chip.label:SetFontObject(FONT_META)
    frame.sort_chip.label:ClearAllPoints()
    frame.sort_chip.label:SetPoint(
        "LEFT",
        frame.sort_chip,
        "LEFT",
        18,
        0
    )
    frame.sort_chip.label:SetJustifyH("LEFT")
    frame.sort_chip.icon = CreateFrame("Frame", nil, frame.sort_chip)
    frame.sort_chip.icon:SetSize(10, 10)
    frame.sort_chip.icon:SetPoint(
        "TOPLEFT",
        frame.sort_chip,
        "TOPLEFT",
        4,
        -8
    )
    frame.sort_chip.icon_parts = {}
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
            frame.sort_chip.icon:CreateTexture(nil, "ARTWORK")
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
            frame.sort_chip.icon,
            "TOPLEFT",
            row_spec[1],
            -row_spec[2]
        )
        frame.sort_chip.icon_parts[#frame.sort_chip.icon_parts + 1] = part
    end

    frame.undo_button = create_button(frame, "↩", 30, 26)
    frame.undo_button:SetPoint("LEFT", frame.sort_chip, "RIGHT", 8, 0)
    frame.undo_button.label:SetFontObject(FONT_CHECK)
    frame.undo_button.label:ClearAllPoints()
    frame.undo_button.label:SetPoint(
        "CENTER",
        frame.undo_button,
        "CENTER",
        -1,
        -2
    )

    frame.redo_button = create_button(frame, "↪", 30, 26)
    frame.redo_button:SetPoint("LEFT", frame.undo_button, "RIGHT", 8, 0)
    frame.redo_button.label:SetFontObject(FONT_CHECK)
    frame.redo_button.label:ClearAllPoints()
    frame.redo_button.label:SetPoint(
        "CENTER",
        frame.redo_button,
        "CENTER",
        -1,
        -2
    )

    frame.copy_button = create_button(frame, "Copy", 64, 26)
    frame.copy_button:SetPoint("LEFT", frame.redo_button, "RIGHT", 8, 0)
    frame.copy_button.label:SetFontObject(FONT_META)

    frame.filter_popup = create_popup(244, 500)
    frame.filter_popup:SetPoint(
        "TOPLEFT",
        frame.filter_chip,
        "BOTTOMLEFT",
        0,
        -4
    )

    local filter_header = make_text(
        frame.filter_popup,
        FONT_META,
        "Filters",
        COLORS.muted
    )
    filter_header:SetPoint("TOPLEFT", frame.filter_popup, "TOPLEFT", 8, -8)

    frame.filter_clear = create_button(
        frame.filter_popup,
        "Clear all",
        70,
        20
    )
    frame.filter_clear:SetPoint("TOPRIGHT", frame.filter_popup, "TOPRIGHT", -6, -5)
    frame.filter_clear.label:SetFontObject(FONT_META)

    frame.filter_scroll = CreateFrame(
        "ScrollFrame",
        nil,
        frame.filter_popup
    )
    frame.filter_scroll:SetPoint("TOPLEFT", frame.filter_popup, "TOPLEFT", 4, -30)
    frame.filter_scroll:SetPoint(
        "BOTTOMRIGHT",
        frame.filter_popup,
        "BOTTOMRIGHT",
        -12,
        4
    )
    frame.filter_scroll:EnableMouseWheel(true)
    frame.filter_scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(
            clamp((self:GetVerticalScroll() or 0) - delta * 40, 0, range)
        )
    end)

    frame.filter_scrollbar = CreateFrame("Frame", nil, frame.filter_popup)
    frame.filter_scrollbar:SetPoint(
        "TOPRIGHT",
        frame.filter_popup,
        "TOPRIGHT",
        -4,
        -30
    )
    frame.filter_scrollbar:SetPoint(
        "BOTTOMRIGHT",
        frame.filter_popup,
        "BOTTOMRIGHT",
        -4,
        4
    )
    frame.filter_scrollbar:SetWidth(6)
    local filter_scroll_track = snap_texture(
        frame.filter_scrollbar:CreateTexture(nil, "ARTWORK")
    )
    filter_scroll_track:SetColorTexture(
        COLORS.hover[1],
        COLORS.hover[2],
        COLORS.hover[3],
        1
    )
    filter_scroll_track:SetPoint("TOP", frame.filter_scrollbar, "TOP", 0, 0)
    filter_scroll_track:SetPoint(
        "BOTTOM",
        frame.filter_scrollbar,
        "BOTTOM",
        0,
        0
    )
    filter_scroll_track:SetWidth(4)
    frame.filter_scroll_thumb = CreateFrame("Frame", nil, frame.filter_scrollbar)
    frame.filter_scroll_thumb:SetWidth(6)
    frame.filter_scroll_thumb.background = snap_texture(
        frame.filter_scroll_thumb:CreateTexture(nil, "ARTWORK")
    )
    frame.filter_scroll_thumb.background:SetAllPoints(
        frame.filter_scroll_thumb
    )
    frame.filter_scroll_thumb.background:SetColorTexture(
        COLORS.muted[1],
        COLORS.muted[2],
        COLORS.muted[3],
        1
    )
    frame.filter_scrollbar:Hide()

    frame.filter_content = CreateFrame(
        "Frame",
        nil,
        frame.filter_scroll
    )
    frame.filter_content:SetWidth(220)
    frame.filter_content:SetHeight(1)
    frame.filter_scroll:SetScrollChild(frame.filter_content)
    frame.filter_rows = {}

    local function update_filter_scrollbar()
        local range = frame.filter_scroll:GetVerticalScrollRange() or 0
        local viewport = frame.filter_scroll:GetHeight() or 1
        if range <= 1 then
            frame.filter_scrollbar:Hide()
            return
        end
        frame.filter_scrollbar:Show()
        local thumb_height = max(24, floor(viewport * viewport / (range + viewport)))
        local max_top = viewport - thumb_height
        local scroll = frame.filter_scroll:GetVerticalScroll() or 0
        local top = range > 0 and scroll / range * max_top or 0
        frame.filter_scroll_thumb:SetHeight(thumb_height)
        frame.filter_scroll_thumb:ClearAllPoints()
        frame.filter_scroll_thumb:SetPoint(
            "TOP",
            frame.filter_scrollbar,
            "TOP",
            0,
            -top
        )
        if frame.snap_box then
            frame.snap_box(frame.filter_scroll_thumb)
        end
    end
    frame.filter_scroll:SetScript("OnVerticalScroll", update_filter_scrollbar)
    frame.update_filter_scrollbar = update_filter_scrollbar

    frame.filter_popup:EnableMouseWheel(true)
    frame.filter_popup:SetScript("OnMouseWheel", function(self, delta)
        local range = frame.filter_scroll:GetVerticalScrollRange() or 0
        frame.filter_scroll:SetVerticalScroll(
            clamp(
                (frame.filter_scroll:GetVerticalScroll() or 0) - delta * 40,
                0,
                range
            )
        )
    end)

    frame.sort_popup = create_popup(170, 140)
    frame.sort_popup:SetPoint(
        "TOPLEFT",
        frame.sort_chip,
        "BOTTOMLEFT",
        0,
        -4
    )
    frame.sort_rows = {}

    frame.copy_popup = create_popup(170, 140)
    frame.copy_popup:SetPoint(
        "TOPLEFT",
        frame.copy_button,
        "BOTTOMLEFT",
        0,
        -4
    )
    frame.copy_rows = {}

    frame.menu_catcher = CreateFrame("Frame", nil, frame)
    frame.menu_catcher:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        0,
        -122
    )
    frame.menu_catcher:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        0,
        0
    )
    frame.menu_catcher:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.menu_catcher:EnableMouse(true)
    frame.menu_catcher:SetScript("OnMouseDown", function()
        frame.close_menus()
    end)
    frame.menu_catcher:Hide()

    frame.close_menus = function()
        frame.filter_popup:Hide()
        frame.sort_popup:Hide()
        frame.copy_popup:Hide()
        frame.menu_catcher:Hide()
    end

    local function take_filter_row()
        local index = (frame.filter_row_index or 0) + 1
        frame.filter_row_index = index
        local row = frame.filter_rows[index]
        if not row then
            row = create_menu_row(frame.filter_content, 20)
            frame.filter_rows[index] = row
        end
        row:Show()
        row:SetEnabled(true)
        row:SetAlpha(1)
        row.check:Hide()
        row.note:SetText("")
        row.on_click = nil
        return row, index
    end

    local function place_filter_row(row, index, y)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.filter_content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", frame.filter_content, "TOPRIGHT", 0, -y)
    end

    local function add_filter_group(label, y)
        local row, index = take_filter_row()
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
        place_filter_row(row, index, y)
        return y + 18
    end

    local function add_filter_option(value, label, selected, on_click, y)
        local row, index = take_filter_row()
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 24, 0)
        row.label:SetText(label)
        row.label:SetTextColor(
            COLORS.text[1],
            COLORS.text[2],
            COLORS.text[3],
            1
        )
        if selected then
            row.check:Show()
        end
        row.on_click = on_click
        row:EnableMouse(true)
        place_filter_row(row, index, y)
        return y + 20
    end

    local function change_filter(field, value)
        frame.filters[field] = value
        frame.refresh_filter_menu()
        frame.update_filter_chip()
        if frame.rebuild_results then
            frame.rebuild_results()
        end
    end

    local function toggle_has(value)
        local has = frame.filters.has
        if has[value] then
            has[value] = nil
        else
            has[value] = true
        end
        frame.refresh_filter_menu()
        frame.update_filter_chip()
        if frame.rebuild_results then
            frame.rebuild_results()
        end
    end

    frame.refresh_filter_menu = function()
        local scroll = frame.filter_scroll:GetVerticalScroll() or 0
        frame.filter_row_index = 0
        local y = 0
        local filters = frame.filters

        y = add_filter_group("Scope", y)
        y = add_filter_option("", "All", filters.scope == "", function()
            change_filter("scope", "")
        end, y)
        y = add_filter_option(
            "account",
            "Account",
            filters.scope == "account",
            function()
                change_filter("scope", "account")
            end,
            y
        )
        y = add_filter_option(
            "character",
            "Character",
            filters.scope == "character",
            function()
                change_filter("scope", "character")
            end,
            y
        )
        y = add_filter_option(
            "local",
            "Local",
            filters.scope == "local",
            function()
                change_filter("scope", "local")
            end,
            y
        )

        y = add_filter_group("Category", y)
        y = add_filter_option("", "All", filters.category == "", function()
            change_filter("category", "")
        end, y)
        local categories = {}
        local seen_categories = {}
        for _, entry in ipairs(entries) do
            local category = entry.category
            if category and category ~= "" then
                local key = category:lower()
                if not seen_categories[key] then
                    seen_categories[key] = true
                    categories[#categories + 1] = {
                        value = key,
                        label = category,
                    }
                end
            end
        end
        sort(categories, function(a, b)
            return a.label:lower() < b.label:lower()
        end)
        for _, category in ipairs(categories) do
            local value = category.value
            y = add_filter_option(
                value,
                category.label,
                filters.category == value,
                function()
                    change_filter("category", value)
                end,
                y
            )
        end

        y = add_filter_group("Type", y)
        y = add_filter_option("", "All", filters.type == "", function()
            change_filter("type", "")
        end, y)
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
            local value = value_type[1]
            y = add_filter_option(
                value,
                value_type[2],
                filters.type == value,
                function()
                    change_filter("type", value)
                end,
                y
            )
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
                value,
                option[2],
                filters.has[value] == true,
                function()
                    toggle_has(value)
                end,
                y
            )
        end

        for index = frame.filter_row_index + 1, #frame.filter_rows do
            frame.filter_rows[index]:Hide()
        end
        frame.filter_content:SetHeight(max(1, y + 4))
        frame.filter_clear:SetEnabled(
            filter_count() > 0 or changed_button.checked
        )
        frame.filter_clear:SetAlpha(
            (filter_count() > 0 or changed_button.checked) and 1 or 0.38
        )
        frame.filter_scroll:SetVerticalScroll(
            min(scroll, frame.filter_scroll:GetVerticalScrollRange() or 0)
        )
        frame.update_filter_scrollbar()
    end

    frame.update_filter_chip = function()
        local count = filter_count()
        frame.filter_chip.label:SetText(
            count > 0 and ("Filters " .. count) or "Filters off"
        )
        fit_chip(frame.filter_chip, 80, 18)
        set_chip_active(frame.filter_chip, count > 0)
        if frame.snap_box then
            frame.snap_box(frame.filter_chip)
        end
    end

    frame.clear_filters = function()
        frame.filters.scope = ""
        frame.filters.category = ""
        frame.filters.type = ""
        frame.filters.has = {}
        changed_button.checked = false
        changed_tick:Hide()
        frame.refresh_filter_menu()
        frame.update_filter_chip()
        if frame.rebuild_results then
            frame.rebuild_results()
        end
        if frame.notify then
            frame.notify("Filters cleared")
        end
    end

    frame.filter_clear:SetScript("OnClick", function()
        frame.clear_filters()
    end)

    frame.filter_chip:SetScript("OnClick", function()
        if frame.filter_popup:IsShown() then
            frame.close_menus()
        else
            frame.close_menus()
            frame.refresh_filter_menu()
            frame.menu_catcher:Show()
            frame.filter_popup:Show()
            frame.snap_box(frame.filter_popup)
            frame.snap_region_tree(frame.filter_popup)
        end
    end)

    frame.sort_chip:SetScript("OnClick", function()
        if frame.sort_popup:IsShown() then
            frame.close_menus()
        else
            frame.close_menus()
            frame.refresh_sort_menu()
            frame.menu_catcher:Show()
            frame.sort_popup:Show()
            frame.snap_box(frame.sort_popup)
            frame.snap_region_tree(frame.sort_popup)
        end
    end)

    frame.copy_button:SetScript("OnClick", function()
        if frame.copy_popup:IsShown() then
            frame.close_menus()
        elseif selected then
            frame.close_menus()
            frame.refresh_copy_menu()
            frame.menu_catcher:Show()
            frame.copy_popup:Show()
            frame.snap_box(frame.copy_popup)
            frame.snap_region_tree(frame.copy_popup)
        end
    end)

    frame.undo_button:SetScript("OnClick", function()
        run_command("undo")
    end)

    frame.redo_button:SetScript("OnClick", function()
        run_command("redo")
    end)

    frame.apply_sort = function(key)
        if frame.sort_key == key then
            frame.sort_dir = frame.sort_dir == "asc" and "desc" or "asc"
        else
            frame.sort_key = key
            frame.sort_dir = key == "changed" and "desc" or "asc"
        end
        frame.close_menus()
        frame.update_sort_chip()
        if frame.rebuild_results then
            frame.rebuild_results()
        end
        if frame.notify then
            frame.notify(
                "Sorted by " .. frame.sort_key .. " " .. frame.sort_dir
            )
        end
    end

    frame.refresh_sort_menu = function()
        local labels = {
            name = "Name",
            type = "Type",
            scope = "Scope",
            category = "Category",
            changed = "Changed",
            range = "Range width",
        }
        local keys = { "name", "type", "scope", "category", "changed", "range" }
        for index, key in ipairs(keys) do
            local row = frame.sort_rows[index]
            if not row then
                row = create_menu_row(frame.sort_popup, 22)
                row:SetPoint(
                    "TOPLEFT",
                    frame.sort_popup,
                    "TOPLEFT",
                    0,
                    -(index - 1) * 22 - 4
                )
                row:SetPoint(
                    "TOPRIGHT",
                    frame.sort_popup,
                    "TOPRIGHT",
                    0,
                    -(index - 1) * 22 - 4
                )
                frame.sort_rows[index] = row
            end
            row:Show()
            row:EnableMouse(true)
            row:SetAlpha(1)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row, "LEFT", 24, 0)
            row.label:SetText(labels[key])
            row.label:SetTextColor(
                COLORS.text[1],
                COLORS.text[2],
                COLORS.text[3],
                1
            )
            row.note:SetText(
                frame.sort_key == key and frame.sort_dir or ""
            )
            row.check:SetShown(frame.sort_key == key)
            row.on_click = function()
                frame.apply_sort(key)
            end
        end
    end

    frame.update_sort_chip = function()
        frame.sort_chip.label:SetText(
            "Sort " .. frame.sort_key .. " " .. frame.sort_dir
        )
        fit_chip(frame.sort_chip, 100, 18)
        set_chip_active(
            frame.sort_chip,
            frame.sort_key ~= "name" or frame.sort_dir ~= "asc"
        )
        if frame.snap_box then
            frame.snap_box(frame.sort_chip)
        end
    end

    frame.refresh_copy_menu = function()
        local fields = {
            { "value", "Copy value" },
            { "raw", "Copy raw value" },
            { "default", "Copy default" },
            { "name", "Copy name" },
            { "help", "Copy help" },
            { "range", "Copy range" },
        }
        for index, field in ipairs(fields) do
            local key = field[1]
            local row = frame.copy_rows[index]
            if not row then
                row = create_menu_row(frame.copy_popup, 22)
                row:SetPoint(
                    "TOPLEFT",
                    frame.copy_popup,
                    "TOPLEFT",
                    0,
                    -(index - 1) * 22 - 4
                )
                row:SetPoint(
                    "TOPRIGHT",
                    frame.copy_popup,
                    "TOPRIGHT",
                    0,
                    -(index - 1) * 22 - 4
                )
                frame.copy_rows[index] = row
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
            local missing = selected == nil
                or (key == "help"
                    and (selected.help == nil or selected.help == ""))
                or (key == "range" and selected.range_text == nil)
            row.note:SetText(
                selected ~= nil
                    and key == "help"
                    and (selected.help == nil or selected.help == "")
                    and "none"
                    or selected ~= nil
                        and key == "range"
                        and selected.range_text == nil
                        and "none"
                    or ""
            )
            row:SetEnabled(not missing)
            row:SetAlpha(missing and 0.38 or 1)
            row.on_click = function()
                frame.close_menus()
                run_command("copy " .. key)
            end
        end
    end

    frame.update_copy_button = function()
        local enabled = selected ~= nil
        frame.copy_button:SetEnabled(enabled)
        frame.copy_button:SetAlpha(enabled and 1 or 0.38)
        if not enabled then
            frame.copy_popup:Hide()
        end
    end

    frame.update_history_controls = function()
        local undo_count = #(frame.undo_stack or {})
        local redo_count = #(frame.redo_stack or {})
        frame.undo_button:SetEnabled(undo_count > 0)
        frame.undo_button:SetAlpha(undo_count > 0 and 1 or 0.38)
        frame.redo_button:SetEnabled(redo_count > 0)
        frame.redo_button:SetAlpha(redo_count > 0 and 1 or 0.38)
    end

    frame.update_regex_chip = function()
        frame.regex_chip.label:SetText(".*")
        set_chip_active(frame.regex_chip, frame.regex_enabled == true)
        frame.regex_chip.underline:SetShown(
            frame.regex_enabled == true
        )
    end

    frame.regex_chip:SetScript("OnClick", function()
        frame.regex_enabled = not frame.regex_enabled
        frame.update_regex_chip()
        if frame.rebuild_results then
            frame.rebuild_results()
        end
    end)

    frame.snap_box = function(region)
        if not region or not region:IsShown() then
            return
        end
        local effective_scale = SCALE.pixel
        local left = region:GetLeft()
        local top = region:GetTop()
        local width = region:GetWidth()
        local height = region:GetHeight()
        if not effective_scale or effective_scale <= 0
            or not left or not top or not width or not height then
            return
        end
        local snapped_left_px = floor(left * effective_scale + 0.5)
        local snapped_right_px = floor(
            (left + width) * effective_scale + 0.5
        )
        local snapped_top_px = floor(top * effective_scale + 0.5)
        local snapped_bottom_px = floor(
            (top - height) * effective_scale + 0.5
        )
        if snapped_right_px <= snapped_left_px then
            snapped_right_px = snapped_left_px + 1
        end
        if snapped_bottom_px >= snapped_top_px then
            snapped_bottom_px = snapped_top_px - 1
        end
        local snapped_left = snapped_left_px / effective_scale
        local snapped_top = snapped_top_px / effective_scale
        local snapped_width = (snapped_right_px - snapped_left_px)
            / effective_scale
        local snapped_height = (snapped_top_px - snapped_bottom_px)
            / effective_scale
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

    frame.snap_line = function(region)
        if not region or not region:IsShown() then
            return
        end
        local effective_scale = SCALE.pixel
        local top = region:GetTop()
        local height = region:GetHeight()
        if not effective_scale or effective_scale <= 0
            or not top or not height then
            return
        end
        local snapped_top = floor(top * effective_scale + 0.5)
            / effective_scale
        local dy = snapped_top - top
        local snapped_height = max(
            1,
            floor(height * effective_scale + 0.5) / effective_scale
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
    frame.snap_boxes = {
        search_frame,
        frame.regex_chip,
        changed_button,
        frame.filter_chip,
        frame.sort_chip,
        frame.undo_button,
        frame.redo_button,
        frame.copy_button,
        changed_box,
        scale_button,
        detail_edit_frame,
        set_button,
        reset_button,
    }

    frame.update_filter_chip()
    frame.update_sort_chip()
    frame.update_regex_chip()
    frame.update_copy_button()
    frame.update_history_controls()
end

local header = CreateFrame("Frame", nil, frame)
header:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -132)
header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -48, -132)
header:SetHeight(16)
local header_border = snap_texture(header:CreateTexture(nil, "ARTWORK"))
header_border:SetColorTexture(
    COLORS.border[1],
    COLORS.border[2],
    COLORS.border[3],
    1
)
header_border:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
header_border:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 24, 0)
hairline.register(header_border, "height")

local header_name = make_text(header, FONT_META, "CVar", COLORS.muted)
header_name:SetPoint("LEFT", header, "LEFT", 6, 1)

local header_gauge = make_text(header, FONT_META, "Gauge", COLORS.muted)
header_gauge:SetPoint("CENTER", header, "CENTER", 0, 1)

local header_value = make_text(header, FONT_META, "Value", COLORS.muted)
header_value:SetPoint("RIGHT", header, "RIGHT", -6, 1)
header_value:SetJustifyH("RIGHT")

scroll_frame = CreateFrame("ScrollFrame", nil, frame)
scroll_frame:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT, -LIST_TOP)
scroll_frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LIST_RIGHT, LIST_BOTTOM)
scroll_frame:EnableMouseWheel(true)

scroll_child = CreateFrame("Frame", nil, scroll_frame)
scroll_child:SetWidth(LIST_WIDTH)
scroll_child:SetHeight(1)
scroll_frame:SetScrollChild(scroll_child)

scrollbar = CreateFrame("Frame", nil, frame)
scrollbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -LIST_TOP)
scrollbar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, LIST_BOTTOM)
scrollbar:SetWidth(8)
scrollbar_track = snap_texture(scrollbar:CreateTexture(nil, "ARTWORK"))
scrollbar_track:SetColorTexture(
    COLORS.hover[1],
    COLORS.hover[2],
    COLORS.hover[3],
    1
)
scrollbar_track:SetPoint("TOP", scrollbar, "TOP", 0, 0)
scrollbar_track:SetPoint("BOTTOM", scrollbar, "BOTTOM", 0, 0)
scrollbar_track:SetWidth(4)

scrollbar_thumb = CreateFrame("Frame", nil, scrollbar)
scrollbar_thumb:SetWidth(8)
scrollbar_thumb:EnableMouse(true)
scrollbar_thumb.background = snap_texture(
    scrollbar_thumb:CreateTexture(nil, "ARTWORK")
)
scrollbar_thumb.background:SetAllPoints(scrollbar_thumb)
scrollbar_thumb.background:SetColorTexture(
    COLORS.muted[1],
    COLORS.muted[2],
    COLORS.muted[3],
    1
)
scrollbar_thumb:SetAlpha(1)

for index = 1, ROW_COUNT do
    rows[index] = create_row()
end

local detail_separator = snap_texture(frame:CreateTexture(nil, "ARTWORK"))
detail_separator:SetColorTexture(
    COLORS.border[1],
    COLORS.border[2],
    COLORS.border[3],
    1
)
detail_separator:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -496)
detail_separator:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -496)
hairline.register(detail_separator, "height")
frame.snap_lines = { titlebar, header, detail_separator }

detail = CreateFrame("Frame", nil, frame)
detail:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -504)
detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 44)

detail_name = make_text(detail, FONT_DETAIL, "", COLORS.text)
detail_name:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, 0)
detail_name:SetWidth(DETAIL_WIDTH)
detail_name:SetJustifyH("LEFT")
detail_name:SetWordWrap(false)

detail_meta = CreateFrame("Frame", nil, detail)
detail_meta:SetPoint("TOPLEFT", detail_name, "BOTTOMLEFT", 0, -3)
detail_meta:SetSize(DETAIL_WIDTH, 14)

for index = 1, META_MAX_PARTS do
    detail_meta_parts[index] = create_meta_part(detail_meta)
    if index > 1 then
        detail_meta_separators[index - 1] = create_meta_separator(detail_meta)
    end
end

detail_help = make_text(detail, FONT_BODY, "", COLORS.text)
detail_help:SetPoint("TOPLEFT", detail_meta, "BOTTOMLEFT", 0, -4)
detail_help:SetWidth(DETAIL_WIDTH)
detail_help:SetJustifyH("LEFT")
detail_help:SetWordWrap(true)
if detail_help.SetMaxLines then
    detail_help:SetMaxLines(2)
end
detail_help:Hide()

detail_edit_frame = CreateFrame("Frame", nil, detail)
detail_edit_frame:SetSize(340, 30)
detail_edit_frame:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 0, 0)
detail_edit_frame.background = detail_edit_frame:CreateTexture(
    nil,
    "BACKGROUND"
)
detail_edit_frame.background:SetAllPoints(detail_edit_frame)
detail_edit_frame.background:SetColorTexture(
    COLORS.surface[1],
    COLORS.surface[2],
    COLORS.surface[3],
    1
)
detail_edit_frame.borders = add_border(detail_edit_frame, COLORS.border)

detail_edit = CreateFrame("EditBox", nil, detail_edit_frame)
detail_edit:SetPoint("TOPLEFT", detail_edit_frame, "TOPLEFT", 10, 0)
detail_edit:SetPoint("BOTTOMRIGHT", detail_edit_frame, "BOTTOMRIGHT", -10, 0)
detail_edit:SetAutoFocus(false)
detail_edit:SetFontObject(FONT_BODY)
detail_edit:SetTextColor(
    COLORS.text[1],
    COLORS.text[2],
    COLORS.text[3],
    1
)
detail_edit:SetTextInsets(2, 2, 2, 2)

set_button = create_button(detail, "Set", 64, 30)
set_button:SetPoint("LEFT", detail_edit_frame, "RIGHT", 8, 0)

reset_button = create_button(detail, "Reset to default", 132, 30)
reset_button:SetPoint("LEFT", set_button, "RIGHT", 8, 0)

detail_status = make_text(detail, FONT_META, "", COLORS.success)
detail_status:SetPoint("LEFT", reset_button, "RIGHT", 12, 0)
detail_status:SetWidth(300)
detail_status:SetJustifyH("LEFT")
detail_status:SetWordWrap(false)

key = CreateFrame("Frame", nil, frame)
key:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 14)
key:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 14)
key:SetHeight(20)
local key_border = snap_texture(key:CreateTexture(nil, "ARTWORK"))
key_border:SetColorTexture(
    COLORS.border[1],
    COLORS.border[2],
    COLORS.border[3],
    1
)
key_border:SetPoint("TOPLEFT", key, "TOPLEFT", 0, 0)
key_border:SetPoint("TOPRIGHT", key, "TOPRIGHT", 0, 0)
hairline.register(key_border, "height")

local changed_key = make_text(
    key,
    FONT_META,
    "Differs from default",
    COLORS.changed
)
local observed_mark = create_observed_ticks(key)
local observed_label = make_text(
    key,
    FONT_META,
    "Observed bounds",
    COLORS.muted
)
local readonly_mark = create_readonly_mark(key)
local readonly_label = make_text(
    key,
    FONT_META,
    "Read-only",
    COLORS.muted
)
local current_mark = create_current_mark(key)
local current_label = make_text(
    key,
    FONT_META,
    "Current value",
    COLORS.muted
)
hint = create_hint(key)

-- Flow layout of the semantic key: 8px mark-to-label, 16px between
-- entries. Re-run after font resizes so measured advances never drift
-- from rendered text.
local function layout_key_row()
    local key_x = 0
    changed_key:SetPoint("LEFT", key, "LEFT", key_x, 0)
    key_x = snap(key_x + changed_key:GetStringWidth()) + 16

    observed_mark:SetPoint("LEFT", key, "LEFT", key_x, 0)
    key_x = snap(key_x + 12) + 8
    observed_label:SetPoint("LEFT", key, "LEFT", key_x, 0)
    key_x = snap(key_x + observed_label:GetStringWidth()) + 16

    readonly_mark:SetPoint("LEFT", key, "LEFT", key_x, 0)
    key_x = snap(key_x + 9) + 8
    readonly_label:SetPoint("LEFT", key, "LEFT", key_x, 0)
    key_x = snap(key_x + readonly_label:GetStringWidth()) + 16

    current_mark:SetPoint("LEFT", key, "LEFT", key_x, 0)
    key_x = snap(key_x + 2) + 8
    current_label:SetPoint("LEFT", key, "LEFT", key_x, 0)

    layout_hint(hint)
end
layout_key_row()

scale_popup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
scale_popup:SetSize(126, #LAYOUT_OPTIONS * 22 + 2)
scale_popup:SetPoint("TOPRIGHT", scale_button, "BOTTOMRIGHT", 0, -4)
scale_popup:SetFrameLevel(frame:GetFrameLevel() + 20)
apply_backdrop(scale_popup, COLORS.surface, COLORS.border)
scale_popup:Hide()
if frame.snap_boxes then
    frame.snap_boxes[#frame.snap_boxes + 1] = scale_popup
end

for index, option in ipairs(LAYOUT_OPTIONS) do
    local row = CreateFrame("Button", nil, scale_popup)
    row:SetSize(124, 22)
    row:SetPoint(
        "TOPLEFT",
        scale_popup,
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
    scale_rows[#scale_rows + 1] = row
end

local function resolve_layout()
    local preset_key = db and db.preset or "auto"
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
    local preset_key = db and db.preset or "auto"
    local label = "Auto"
    if preset_key ~= "auto" and LAYOUT_PRESETS[preset_key] then
        label = preset_key:sub(1, 1):upper() .. preset_key:sub(2)
    end
    scale_button.label:SetText("Size: " .. label)
    scale_button:SetWidth(max(72, snap(scale_button.label:GetStringWidth() + 10)))
    for _, row in ipairs(scale_rows) do
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
frame.measure_px_per_unit = function(physical_height)
    if not frame.GetScaledRect then
        return nil
    end
    if not frame.px_probe then
        frame.px_probe = frame:CreateTexture(nil, "ARTWORK")
        frame.px_probe:Hide()
    end
    local probe = frame.px_probe
    probe:ClearAllPoints()
    probe:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    probe:SetWidth(100)
    probe:SetHeight(100)
    probe:Show()
    local _, _, scaled_width = probe:GetScaledRect()
    probe:Hide()
    probe:ClearAllPoints()
    if not scaled_width or scaled_width <= 0 then
        return nil
    end
    -- screen units -> physical pixels: one screen unit is height/768 px.
    return scaled_width * physical_height / 768 / 100
end

-- Snug label fit: 4px text padding from the outline on each side, with a
-- caller-supplied floor so tiny buttons never collapse absurdly narrow.
-- A frame field (not a local) because the main chunk is at Lua 5.1's
-- 200-local limit. Re-run after font resizes.
frame.fit_text_button = function(button, minimum)
    if not button or not button.label then
        return
    end
    local width = button.label:GetStringWidth() + 8
    if minimum and minimum > width then
        width = minimum
    end
    button:SetWidth(snap(width))
end

-- Snaps every texture rect in the tree to the pixel grid at rest so edges
-- stay one physical pixel. Text is deliberately not snapped: fonts are
-- monospace at integer sizes, so glyph interiors stay pixel-stable at
-- fractional origins, while snapping would shift labels out of their
-- padding and break alignment.
frame.snap_region_tree = function(region)
    if region.GetChildren then
        for _, child in ipairs({ region:GetChildren() }) do
            frame.snap_region_tree(child)
        end
    end
    if not region.GetRegions or not frame.snap_box then
        return
    end
    for _, sub in ipairs({ region:GetRegions() }) do
        if sub:GetObjectType() == "Texture" then
            if sub.GetNumPoints and sub:GetNumPoints() > 1 then
                frame.snap_line(sub)
            else
                frame.snap_box(sub)
            end
        end
    end
end

local function snap_frame_position()
    if not frame or not frame:IsShown() then
        return
    end
    -- Snap the frame's physical-pixel origin to the nearest whole pixel by
    -- shifting the anchor, then re-measure and mop up any residual. GetLeft/
    -- GetTop are frame units, so SCALE.pixel (physical px per frame unit)
    -- converts them to pixels, and the correction converts back into
    -- UIParent-unit anchor space through SCALE.snap (physical px per
    -- UIParent-unit offset). Landing the origin on a whole pixel keeps
    -- 1-unit hairlines on exactly one pixel and the font raster phase
    -- stable; a fractional phase is what made the header text drift between
    -- 1px and 2px above the separator after a drag release. GetScaledRect is
    -- not usable here: it returns 768-space screen units (GetRect times
    -- effective scale), not pixels, and its second return is the bottom edge.
    local px_per_unit = SCALE.pixel
    local px_per_parent_unit = SCALE.snap
    if not px_per_unit or px_per_unit <= 0
        or not px_per_parent_unit or px_per_parent_unit <= 0 then
        return
    end
    local point, relative_to, relative_point, x, y = frame:GetPoint(1)
    if not point then
        return
    end
    x = x or 0
    y = y or 0
    for _ = 1, 2 do
        local left = frame:GetLeft()
        local top = frame:GetTop()
        if not left or not top then
            return
        end
        local left_px = left * px_per_unit
        local top_px = top * px_per_unit
        local dx_px = floor(left_px + 0.5) - left_px
        local dy_px = floor(top_px + 0.5) - top_px
        if abs(dx_px) < 0.001 and abs(dy_px) < 0.001 then
            break
        end
        x = x + dx_px / px_per_parent_unit
        y = y + dy_px / px_per_parent_unit
        frame:ClearAllPoints()
        frame:SetPoint(
            point,
            relative_to or UIParent,
            relative_point or "CENTER",
            x,
            y
        )
    end
    if db then
        db.x = x
        db.y = y
    end
end

local function apply_ui_scale()
    local preset = resolve_layout()
    if frame.SetIgnoreParentScale then
        frame:SetIgnoreParentScale(true)
    end
    local _, physical_height = GetPhysicalScreenSize()
    if not physical_height or physical_height <= 0 then
        physical_height = 1440
    end
    -- Target: one frame unit == one physical pixel. Screen space is 768 units
    -- over the physical screen, so an effective scale of 768/height is
    -- pixel-perfect wherever SetIgnoreParentScale is honored. Measure the
    -- probe's rendered rect and divide out any residual: clients that
    -- compose the parent's scale into the frame despite SetIgnoreParentScale
    -- land one unit at parentScale pixels, which this cancels exactly
    -- (scale composition is multiplicative, so one corrective pass
    -- converges).
    local perfect_scale = 768 / physical_height
    frame:SetScale(perfect_scale)
    local px_per_unit = frame.measure_px_per_unit(physical_height)
    if px_per_unit and px_per_unit > 0 and abs(px_per_unit - 1) > 1e-3 then
        frame:SetScale((frame:GetScale() or perfect_scale) / px_per_unit)
        px_per_unit = frame.measure_px_per_unit(physical_height) or px_per_unit
    end
    if not px_per_unit or px_per_unit <= 0 then
        px_per_unit = 1
    end
    -- Measured physical px per frame unit (~1.0 after compensation).
    SCALE.pixel = px_per_unit
    -- Cursor screen units to frame units: one screen unit is height/768 px.
    SCALE.drag = physical_height / 768 / px_per_unit
    -- Physical px per UIParent-unit anchor offset (SetPoint offsets on the
    -- frame live in UIParent units). Exact from UIParent's own effective
    -- scale; the old parent:child ratio was only correct while the frame
    -- scale formula above was honored verbatim.
    SCALE.snap = (UIParent:GetEffectiveScale() or 1) * physical_height / 768
    frame:SetSize(preset.width, preset.height)

    resize_font(FONT_TITLE, FONT_SEMIBOLD_PATH, preset.title)
    resize_font(FONT_DETAIL, FONT_SEMIBOLD_PATH, preset.detail)
    resize_font(FONT_BODY, FONT_REGULAR_PATH, preset.body)
    resize_font(FONT_META, FONT_REGULAR_PATH, preset.meta)
    resize_font(
        FONT_CHECK,
        MEDIA_PATH .. "Inter-SemiBold.ttf",
        preset.check
    )
    layout_key_row()
    -- Refit snug text buttons after font sizes settle: labels keep 4px
    -- padding from the outline on each side, with a small floor (roughly
    -- the button height) so tiny buttons never collapse absurdly narrow.
    frame.fit_text_button(set_button, 30)
    frame.fit_text_button(reset_button, 64)
    frame.fit_text_button(frame.copy_button, 30)
    frame.fit_text_button(frame.filter_clear, 40)
    frame.fit_text_button(close_button, 24)
    frame.fit_text_button(frame.undo_button, 24)
    frame.fit_text_button(frame.redo_button, 24)

    DETAIL_WIDTH = preset.width - 48
    LIST_WIDTH = preset.width - LIST_LEFT - LIST_RIGHT
    LIST_BOTTOM = preset.detail_height + 56
    LIST_HEIGHT = preset.height - LIST_TOP - LIST_BOTTOM

    scroll_child:SetWidth(LIST_WIDTH)
    scroll_frame:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -LIST_RIGHT,
        LIST_BOTTOM
    )
    scrollbar:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -24,
        LIST_BOTTOM
    )

    local separator_y = preset.height - preset.detail_height - 52
    local detail_y = preset.height - preset.detail_height - 44
    detail_separator:ClearAllPoints()
    detail_separator:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -separator_y)
    detail_separator:SetPoint(
        "TOPRIGHT",
        frame,
        "TOPRIGHT",
        -24,
        -separator_y
    )
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -detail_y)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 44)
    detail_name:SetWidth(DETAIL_WIDTH)
    detail_help:SetWidth(DETAIL_WIDTH)
    detail_meta:SetSize(DETAIL_WIDTH, 14)
    detail_status:SetWidth(max(120, DETAIL_WIDTH - 554))
    if frame.filter_popup then
        frame.filter_popup:SetHeight(min(500, preset.height - 136))
    end

    frame.update_filter_chip()
    frame.update_sort_chip()
    update_scale_button()
    -- Size every border to exactly one physical pixel via the measured
    -- physical-px-per-unit (SCALE.pixel). GetScaledRect must not be used for
    -- this: it returns 768-space screen units (GetRect times effective
    -- scale), not pixels, which measured 768/height and drew hairlines at
    -- height/768 px (double thickness at common resolutions).
    local px_per_unit = SCALE.pixel
    if not px_per_unit or px_per_unit <= 0 then
        px_per_unit = 1
    end
    hairline.set_scale(px_per_unit)
    set_backdrop_edge_size(px_per_unit)
    snap_frame_position()
    if frame.snap_lines then
        for _, region in ipairs(frame.snap_lines) do
            frame.snap_line(region)
        end
    end
    if frame.snap_boxes then
        for _, region in ipairs(frame.snap_boxes) do
            frame.snap_box(region)
        end
    end
    frame.snap_region_tree(frame)
end

local function set_layout(value)
    if db then
        db.preset = value
    end
    apply_ui_scale()
    scale_popup:Hide()
end

local function toggle_scale_popup()
    if scale_popup:IsShown() then
        scale_popup:Hide()
    else
        update_scale_button()
        scale_popup:Show()
        if frame.snap_box then
            frame.snap_box(scale_popup)
        end
        scale_popup:Raise()
    end
end

-- Minimap button -------------------------------------------------------------

if Minimap then
    frame.minimap_button = CreateFrame(
        "Button",
        "CVarBrowserMinimapButton",
        Minimap
    )
    frame.minimap_button:SetSize(32, 32)
    frame.minimap_button:SetFrameStrata("MEDIUM")
    frame.minimap_button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    frame.minimap_button:RegisterForClicks("LeftButtonUp")
    frame.minimap_button:RegisterForDrag("LeftButton")
    frame.minimap_button:SetMovable(true)

    frame.minimap_button.border = frame.minimap_button:CreateTexture(
        nil,
        "OVERLAY"
    )
    frame.minimap_button.border:SetTexture(
        "Interface\\Minimap\\MiniMap-TrackingBorder"
    )
    frame.minimap_button.border:SetSize(54, 54)
    frame.minimap_button.border:SetPoint("TOPLEFT")

    -- Named <Button>Icon: minimap-button collectors (Leatrix Plus,
    -- Completao-style drawers, etc.) use this texture for their tile.
    frame.minimap_button.icon = frame.minimap_button:CreateTexture(
        "CVarBrowserMinimapButtonIcon",
        "ARTWORK"
    )
    frame.minimap_button.icon:SetTexture(
        "Interface\\Icons\\INV_Misc_Spyglass_02"
    )
    frame.minimap_button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.minimap_button.icon:SetSize(20, 20)
    frame.minimap_button.icon:SetPoint("CENTER")

    frame.minimap_button.update_position = function(self)
        local angle = math.rad(db and db.minimap_angle or 220)
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

    frame.minimap_button:SetScript("OnClick", function()
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end)
    frame.minimap_button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("CVar Browser")
        GameTooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
        GameTooltip:Show()
    end)
    frame.minimap_button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame.minimap_button:SetScript("OnDragStart", function(self)
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
            if db then
                db.minimap_angle = angle
            end
            self:update_position()
        end)
    end)
    frame.minimap_button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:update_position()
    end)
    frame.minimap_button:update_position()
end

-- Addon Compartment (Blizzard minimap drawer, also used by collectors) ------

function CVarBrowser_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton ~= "LeftButton" then
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
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
    detail_status:SetText(message or "")
    local color = COLORS.success
    if tone == "error" then
        color = COLORS.error
    elseif tone == "warning" then
        color = COLORS.warning
    end
    detail_status:SetTextColor(color[1], color[2], color[3], 1)
    frame.status_token = (frame.status_token or 0) + 1
    local token = frame.status_token
    if message and message ~= "" and C_Timer then
        C_Timer.After(30, function()
            if frame.status_token == token then
                detail_status:SetText("")
            end
        end)
    end
end

frame.notify = set_status

local function update_controls()
    local entry = selected
    local can_edit = entry ~= nil
        and not entry.readonly
        and not entry.locked
        and not (entry.secure and InCombatLockdown())

    if can_edit then
        detail_edit:Enable()
        set_button:Enable()
        reset_button:Enable()
    else
        detail_edit:Disable()
        set_button:Disable()
        reset_button:Disable()
    end
    detail_edit_frame:SetAlpha(can_edit and 1 or 0.55)
    set_button:SetAlpha(can_edit and 1 or 0.38)
    reset_button:SetAlpha(can_edit and 1 or 0.38)

    if entry and entry.readonly then
        detail_name:SetTextColor(
            COLORS.muted[1],
            COLORS.muted[2],
            COLORS.muted[3],
            1
        )
    elseif entry and entry.changed then
        detail_name:SetTextColor(
            COLORS.changed[1],
            COLORS.changed[2],
            COLORS.changed[3],
            1
        )
    else
        detail_name:SetTextColor(
            COLORS.text[1],
            COLORS.text[2],
            COLORS.text[3],
            1
        )
    end

    if entry and entry.secure and not entry.readonly and InCombatLockdown() then
        set_status("Secure CVar: cannot be changed in combat.", "warning")
    end
    if frame.update_history_controls then
        frame.update_history_controls()
    end
    if frame.update_copy_button then
        frame.update_copy_button()
    end
end

local function update_meta(parts)
    local x = 0
    for index = 1, META_MAX_PARTS do
        local part = detail_meta_parts[index]
        local spec = parts[index]
        if spec then
            if index > 1 then
                x = snap(x + 9)
                local separator = detail_meta_separators[index - 1]
                separator:ClearAllPoints()
                separator:SetPoint("LEFT", detail_meta, "LEFT", x, 0)
                separator:Show()
                x = x + 10
            end
            part:ClearAllPoints()
            part:SetPoint("LEFT", detail_meta, "LEFT", x, 0)
            part:SetText(spec.text)
            part:SetTextColor(
                spec.color[1],
                spec.color[2],
                spec.color[3],
                spec.color[4] or 1
            )
            part:Show()
            x = snap(x + part:GetStringWidth())
        else
            part:Hide()
            if index > 1 and detail_meta_separators[index - 1] then
                detail_meta_separators[index - 1]:Hide()
            end
        end
    end
end

local function update_detail()
    local entry = selected
    if not entry then
        detail_name:SetText("")
        update_meta({})
        detail_help:SetText("")
        detail_help:Hide()
        detail_edit:SetText("")
        set_status("")
        update_controls()
        return
    end

    detail_name:SetText(entry.name)
    update_meta(build_meta_parts(entry))

    if entry.help and entry.help ~= "" then
        detail_help:SetText(entry.help)
        detail_help:Show()
    else
        detail_help:SetText("")
        detail_help:Hide()
    end

    detail_edit:SetText(display_edit_value(entry, entry.value))
    set_status("")
    update_controls()
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

    local minimums = {}
    local maximums = {}
    if help_min ~= nil then
        minimums[#minimums + 1] = help_min
    end
    if observed_min ~= nil then
        minimums[#minimums + 1] = observed_min
    end
    if help_max ~= nil then
        maximums[#maximums + 1] = help_max
    end
    if observed_max ~= nil then
        maximums[#maximums + 1] = observed_max
    end

    if value == nil or (#minimums == 0 and #maximums == 0) then
        gauge.dot:Show()
        return
    end

    local domain_min
    local domain_max
    for _, bound in ipairs(minimums) do
        if domain_min == nil or bound < domain_min then
            domain_min = bound
        end
    end
    for _, bound in ipairs(maximums) do
        if domain_max == nil or bound > domain_max then
            domain_max = bound
        end
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

    local function position(bound)
        return clamp(
            (bound - domain_min) / (domain_max - domain_min) * GAUGE_WIDTH,
            0,
            GAUGE_WIDTH
        )
    end

    gauge.track:Show()

    if help_min ~= nil then
        gauge.help_min:SetPoint(
            "CENTER",
            gauge.frame,
            "LEFT",
            position(help_min),
            0
        )
        gauge.help_min:Show()
    end
    if help_max ~= nil then
        gauge.help_max:SetPoint(
            "CENTER",
            gauge.frame,
            "LEFT",
            position(help_max),
            0
        )
        gauge.help_max:Show()
    end
    if observed_min ~= nil then
        gauge.observed_min:SetPoint(
            "CENTER",
            gauge.frame,
            "LEFT",
            position(observed_min),
            0
        )
        gauge.observed_min:Show()
    end
    if observed_max ~= nil then
        gauge.observed_max:SetPoint(
            "CENTER",
            gauge.frame,
            "LEFT",
            position(observed_max),
            0
        )
        gauge.observed_max:Show()
    end

    local cursor_x = position(value)
    local cursor_color = entry.changed and COLORS.changed or COLORS.text
    gauge.cursor:SetColorTexture(
        cursor_color[1],
        cursor_color[2],
        cursor_color[3],
        1
    )
    gauge.cursor:SetPoint("CENTER", gauge.frame, "LEFT", cursor_x, 0)
    gauge.cursor:Show()

    if entry.clamp_at ~= nil then
        local clamp_x = position(entry.clamp_at)
        if entry.clamp_side == "low" then
            clamp_x = max(0, clamp_x - 2)
        else
            clamp_x = min(GAUGE_WIDTH, clamp_x + 2)
        end
        gauge.clamp:SetPoint("CENTER", gauge.frame, "LEFT", clamp_x, 0)
        gauge.clamp:Show()
    end

    if open_left then
        gauge.open_left:Show()
    end
    if open_right then
        gauge.open_right:Show()
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
    row.name_text:SetText(ellipsize(entry.name, 34))

    local name_color = COLORS.text
    if entry.readonly then
        name_color = COLORS.muted
    elseif entry.changed then
        name_color = COLORS.changed
    elseif selected == entry then
        name_color = COLORS.accent
    end
    row.name_text:SetTextColor(
        name_color[1],
        name_color[2],
        name_color[3],
        1
    )

    local raw_value = tostring(entry.value or "?")
    local value_text
    if entry.bitfield and entry.value ~= nil then
        value_text = format("Bitfield (%d bytes)", #raw_value)
    elseif entry.serialized and entry.value ~= nil then
        value_text = format("Serialized (%d bytes)", #raw_value)
    else
        value_text = ellipsize(raw_value, 28)
    end
    if entry.changed then
        local raw_default = entry.default_value
        local default_text = tostring(raw_default or "?")
        if raw_default ~= nil and default_text:match("^%s*$") then
            default_text = "empty"
        end
        local default_display
        if entry.bitfield or entry.serialized then
            default_display = format("%d bytes", #tostring(raw_default or ""))
        else
            default_display = ellipsize(default_text, 14)
        end
        value_text = value_text
            .. " "
            .. color_escape(COLORS.muted)
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

    if selected == entry then
        row.selected_background:Show()
        row.selected_bar:Show()
    else
        row.selected_background:Hide()
        row.selected_bar:Hide()
    end
    update_gauge(row.gauge, entry)
end

local function update_scrollbar()
    local range = scroll_frame:GetVerticalScrollRange() or 0
    local viewport = scroll_frame:GetHeight() or LIST_HEIGHT
    if range <= 1 then
        scrollbar:Hide()
        return
    end

    scrollbar:Show()
    local content = range + viewport
    local thumb_height = max(32, floor(viewport * viewport / content))
    local max_top = viewport - thumb_height
    local scroll = scroll_frame:GetVerticalScroll() or 0
    local top = range > 0 and (scroll / range) * max_top or 0

    scrollbar_thumb:SetHeight(thumb_height)
    scrollbar_thumb:ClearAllPoints()
    scrollbar_thumb:SetPoint("TOP", scrollbar, "TOP", 0, -top)
    if frame.snap_box then
        frame.snap_box(scrollbar_thumb)
    end
end

local function update_rows()
    local total = #view
    scroll_child:SetHeight(max(1, total * ROW_HEIGHT))
    local offset = scroll_frame:GetVerticalScroll() or 0
    local first = floor(offset / ROW_HEIGHT + 0.5) + 1
    if first < 1 then
        first = 1
    end

    for index = 1, ROW_COUNT do
        local row = rows[index]
        local entry = view[first + index - 1]
        local y = -((first + index - 2) * ROW_HEIGHT)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", scroll_child, "TOPRIGHT", 0, y)
        render_row(row, entry)
    end
    update_scrollbar()
end

local function select_entry(entry)
    selected = entry
    update_detail()
    update_rows()
end

local function rebuild_view()
    local query = trim(search_box:GetText() or ""):lower()
    local only_changed = changed_button.checked
    local terms = {}
    local filter_scope
    local filter_category
    local filter_type
    local filter_has
    for token in query:gmatch("%S+") do
        local key, value = token:match("^([%w_]+):(.+)$")
        if key == "scope" then
            filter_scope = value
        elseif key == "category" or key == "cat" then
            filter_category = value
        elseif key == "type" then
            filter_type = value
        elseif key == "has" then
            filter_has = value
        elseif token == "changed" then
            only_changed = true
        else
            terms[#terms + 1] = token
        end
    end
    local pattern = concat(terms, " ")
    local use_pattern = frame.regex_enabled == true
    local visual_filters = frame.filters or {}
    local visual_has = visual_filters.has or {}

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
            and infer_value_type(entry):lower() ~= visual_filters.type then
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
            and infer_value_type(entry):lower() ~= filter_type then
            return false
        end
        if filter_has then
            if filter_has == "range" and not entry.range_text then
                return false
            elseif filter_has == "observed"
                and entry.range_source ~= "observed" then
                return false
            elseif filter_has == "help"
                and not entry.help_range then
                return false
            elseif filter_has == "default"
                and entry.default_value == nil then
                return false
            elseif filter_has == "changed"
                and not entry.changed then
                return false
            end
        end
        return true
    end

    local range_count = 0
    view = {}

    for _, entry in ipairs(entries) do
        if matches_filters(entry) and matches_text(entry) then
            view[#view + 1] = entry
            if entry.range_text then
                range_count = range_count + 1
            end
        end
    end

    local sort_key = frame.sort_key or "name"
    local sort_dir = frame.sort_dir or "asc"
    if sort_key ~= "name" or sort_dir ~= "asc" then
        local function sort_value(entry, key)
            if key == "type" then
                return infer_value_type(entry):lower()
            elseif key == "scope" then
                return (entry.scope or ""):lower()
            elseif key == "category" then
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
        sort(view, function(a, b)
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

    if selected then
        local still_visible = false
        for _, entry in ipairs(view) do
            if entry == selected then
                still_visible = true
                break
            end
        end
        if not still_visible then
            selected = nil
        end
    end
    if not selected and #view > 0 then
        selected = view[1]
    end

    count_text:SetText(
        format(
            "%d / %d CVars, %d with range",
            #view,
            #entries,
            range_count
        )
    )
    scroll_frame:SetVerticalScroll(0)
    update_rows()
    update_detail()
end

frame.rebuild_results = rebuild_view

local function rescan()
    local selected_name = selected and selected.name
    by_name = {}
    for index = #entries, 1, -1 do
        entries[index] = nil
    end
    view = {}
    selected = nil

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
            if not by_name[name] then
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
                by_name[name] = entry
                by_name[entry.name_lower] = entry
                entries[#entries + 1] = entry
            end
        end
    end

    sort(entries, function(a, b)
        return a.name_lower < b.name_lower
    end)

    selected = selected_name and by_name[selected_name] or nil
    if frame.filter_popup and frame.filter_popup:IsShown() then
        frame.refresh_filter_menu()
    end
    rebuild_view()
    set_status(format("Loaded %d CVars.", #entries))
end

local function apply_value()
    local entry = selected
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
    local requested = detail_edit:GetText() or ""
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
        local undo = frame.undo_stack or {}
        frame.undo_stack = undo
        undo[#undo + 1] = {
            name = entry.name,
            previous = previous,
        }
        if #undo > 20 then
            table.remove(undo, 1)
        end
        frame.redo_stack = {}
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
    if not detail_edit:HasFocus() then
        update_detail()
    else
        if actual ~= nil then
            detail_edit:SetText(display_edit_value(entry, actual))
            detail_edit:HighlightText()
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
    if not selected or selected.readonly then
        return
    end
    detail_edit:SetText(
        display_edit_value(selected, selected.default_value)
    )
    apply_value()
end

local function toggle_changed()
    changed_button.checked = not changed_button.checked
    if changed_button.checked then
        changed_tick:Show()
    else
        changed_tick:Hide()
    end
    if frame.filter_popup and frame.filter_popup:IsShown() then
        frame.refresh_filter_menu()
    end
    rebuild_view()
end

local function scroll_to(value)
    local range = scroll_frame:GetVerticalScrollRange() or 0
    scroll_frame:SetVerticalScroll(clamp(value, 0, range))
end

local function handle_scrollbar_drag_start()
    local scale = frame:GetEffectiveScale() or 1
    local _, cursor_y = GetCursorPosition()
    scroll_drag = {
        start_y = cursor_y / scale,
        start_scroll = scroll_frame:GetVerticalScroll() or 0,
        max_top = max(1, scrollbar:GetHeight() - scrollbar_thumb:GetHeight()),
        max_scroll = scroll_frame:GetVerticalScrollRange() or 0,
    }
    scrollbar_thumb:SetScript("OnUpdate", function()
        if not scroll_drag or not IsMouseButtonDown("LeftButton") then
            scrollbar_thumb:SetScript("OnUpdate", nil)
            scroll_drag = nil
            return
        end
        local current_scale = frame:GetEffectiveScale() or 1
        local _, current_y = GetCursorPosition()
        local delta = (scroll_drag.start_y - current_y / current_scale)
            / scroll_drag.max_top
            * scroll_drag.max_scroll
        scroll_to(scroll_drag.start_scroll + delta)
    end)
end

local function stop_scrollbar_drag()
    scroll_drag = nil
    scrollbar_thumb:SetScript("OnUpdate", nil)
end

-- Wiring ---------------------------------------------------------------------

titlebar:SetScript("OnDragStart", function()
    frame:StartMoving()
end)
titlebar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    -- Snap the anchor to whole pixels once on release. During the drag the
    -- frame glides smoothly (no per-frame snapping), which avoids the shimmer
    -- and border breaks that per-frame repositioning caused. This matches the
    -- proven drag model used across the other addons.
    snap_frame_position()
    if not db then
        return
    end
    local point, _, relative_point, x, y = frame:GetPoint(1)
    if point then
        db.point = point
        db.relativePoint = relative_point
        db.x = x or 0
        db.y = y or 0
    end
end)

close_button:SetScript("OnClick", function()
    frame:Hide()
end)

scale_button:SetScript("OnClick", toggle_scale_popup)
for _, row in ipairs(scale_rows) do
    row:SetScript("OnClick", function(self)
        set_layout(self.option.value)
    end)
end

search_box:SetScript("OnTextChanged", function(self)
    search_placeholder:SetShown(
        (self:GetText() or "") == "" and not self:HasFocus()
    )
    rebuild_view()
end)
search_box:SetScript("OnEditFocusGained", function()
    search_frame:SetBackdropBorderColor(
        COLORS.accent[1],
        COLORS.accent[2],
        COLORS.accent[3],
        1
    )
    -- The caret blinks where the placeholder starts; hide it while typing.
    search_placeholder:Hide()
end)
search_box:SetScript("OnEditFocusLost", function()
    search_frame:SetBackdropBorderColor(
        COLORS.border[1],
        COLORS.border[2],
        COLORS.border[3],
        1
    )
    if (search_box:GetText() or "") == "" then
        search_placeholder:Show()
    end
end)
search_box:SetScript("OnEnterPressed", function(self)
    if #view > 0 then
        select_entry(view[1])
        if not view[1].readonly
            and not (view[1].secure and InCombatLockdown()) then
            detail_edit:SetFocus()
            detail_edit:HighlightText()
        end
    else
        self:ClearFocus()
    end
end)
search_box:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
search_box:SetScript("OnKeyDown", function(_, key)
    if key ~= "UP" and key ~= "DOWN" then
        return
    end
    if #view == 0 then
        return
    end
    local index = 1
    if selected then
        for position, entry in ipairs(view) do
            if entry == selected then
                index = position
                break
            end
        end
    end
    if key == "DOWN" then
        index = min(index + 1, #view)
    else
        index = max(index - 1, 1)
    end
    select_entry(view[index])
    scroll_to((index - 1) * ROW_HEIGHT)
end)

changed_button:SetScript("OnClick", toggle_changed)

detail_edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
detail_edit:SetScript("OnEnterPressed", function(self)
    apply_value()
    self:HighlightText()
end)
detail_edit:SetScript("OnEditFocusGained", function()
    hairline.set_color(detail_edit_frame.borders, COLORS.accent)
end)
detail_edit:SetScript("OnEditFocusLost", function()
    hairline.set_color(detail_edit_frame.borders, COLORS.border)
end)

set_button:SetScript("OnClick", apply_value)
reset_button:SetScript("OnClick", reset_value)

scroll_frame:SetScript("OnVerticalScroll", function()
    update_rows()
end)
scroll_frame:SetScript("OnMouseWheel", function(self, delta)
    scroll_to(
        (self:GetVerticalScroll() or 0)
            - delta * ROW_HEIGHT * 3
    )
end)
scroll_frame:SetScript("OnSizeChanged", function(self, width)
    scroll_child:SetWidth(width)
    update_scrollbar()
end)

scrollbar_thumb:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
        handle_scrollbar_drag_start()
    end
end)
scrollbar_thumb:SetScript("OnMouseUp", stop_scrollbar_drag)

for index = 1, ROW_COUNT do
    local row = rows[index]
    row:SetScript("OnClick", function(self)
        if self.entry then
            select_entry(self.entry)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.entry and selected ~= self.entry then
            self.hover:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
    end)
end

frame:SetScript("OnShow", function(self)
    self:Raise()
    scale_popup:Hide()
    apply_ui_scale()
    rescan()
end)
frame:SetScript("OnEvent", function(self, event, argument)
    if event == "ADDON_LOADED" then
        if argument ~= addon_name then
            return
        end
        init_db()
        self:ClearAllPoints()
        -- db.x/db.y were saved as an on-grid anchor by the drag (rendered pixel
        -- locked). Restore them verbatim; re-rounding them here on a different
        -- grid would fight the drag grid and shift the frame a pixel.
        -- snap_frame_position() in apply_ui_scale is the single authoritative
        -- rendered-pixel snap.
        local x = tonumber(db.x) or 0
        local y = tonumber(db.y) or 0
        local ok = pcall(
            self.SetPoint,
            self,
            db.point or "CENTER",
            UIParent,
            db.relativePoint or "CENTER",
            x,
            y
        )
        if not ok then
            self:ClearAllPoints()
            self:SetPoint("CENTER")
        end
        apply_ui_scale()
        if type(frame.minimap_button) == "table" then
            frame.minimap_button:update_position()
            frame.minimap_button:SetShown(not db.minimap_hidden)
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "CVAR_UPDATE" then
        local entry = argument and by_name[argument]
        if entry then
            read_cvar_value(entry)
            apply_range(entry)
            update_rows()
            if selected == entry and not detail_edit:HasFocus() then
                update_detail()
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        update_controls()
    elseif event == "UI_SCALE_CHANGED"
        or event == "DISPLAY_SIZE_CHANGED" then
        apply_ui_scale()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if self:IsShown() then
            rescan()
        end
    end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("CVAR_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UI_SCALE_CHANGED")
frame:RegisterEvent("DISPLAY_SIZE_CHANGED")

-- Slash commands -------------------------------------------------------------

SLASH_CVARBROWSER1 = "/cvars"
SLASH_CVARBROWSER2 = "/cb"
SLASH_CVARBROWSER3 = "/cvarbrowser"
SlashCmdList["CVARBROWSER"] = function(message)
    local message_text = trim(message or "")
    local lower = message_text:lower()

    if lower == "minimap" or lower:match("^minimap%s+") then
        if type(frame.minimap_button) ~= "table" then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r minimap button unavailable"
            )
            return
        end
        local argument = lower:match("^minimap%s+(%S+)")
        if argument == "reset" then
            if db then
                db.minimap_angle = 220
            end
            frame.minimap_button:update_position()
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r minimap angle reset"
            )
        else
            if db then
                db.minimap_hidden = not db.minimap_hidden
            end
            local hidden = db and db.minimap_hidden
            frame.minimap_button:SetShown(not hidden)
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r minimap button "
                    .. (hidden and "hidden" or "shown")
            )
        end
        return
    end

    if lower == "copy" or lower:match("^copy%s+") then
        if not frame:IsShown() then
            frame:Show()
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
        local entry = selected
        if target_name then
            entry = by_name[target_name]
        end
        if not entry then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r no CVar selected to copy"
            )
            return
        end
        local value
        if field == "name" then
            value = entry.name
        elseif field == "default" then
            value = entry.default_value
        elseif field == "help" then
            value = entry.help or entry.help_raw
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
        if CopyToClipboard then
            CopyToClipboard(tostring(value))
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r CopyToClipboard unavailable"
            )
            return
        end
        set_status("Copied " .. field .. ": " .. entry.name)
        return
    end

    if lower == "help" then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffB7A3CCCVarBrowser|r commands: "
                .. "/cvars | /cb, /cvars <name>, refresh, undo, redo, "
                .. "ranges [name], clearrange <name>, clearranges, "
                .. "sort name|type|scope|category|changed|range [asc|desc], "
                .. "copy [value|raw|default|name|help|range] [cvar], "
                .. "regex [on|off], minimap [reset], filters"
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
        frame.sort_key = sort_key
        if sort_dir == "" then
            sort_dir = sort_key == "changed" and "desc" or "asc"
        end
        frame.sort_dir = sort_dir
        frame.update_sort_chip()
        rebuild_view()
        set_status("Sorted by " .. sort_key .. " " .. sort_dir)
        return
    end

    if lower == "regex" or lower:match("^regex%s+") then
        local value = lower:match("^regex%s+(%S+)")
        if value == "on" then
            frame.regex_enabled = true
        elseif value == "off" then
            frame.regex_enabled = false
        else
            frame.regex_enabled = not frame.regex_enabled
        end
        frame.update_regex_chip()
        rebuild_view()
        local text = "Pattern search "
            .. (frame.regex_enabled and "on" or "off")
        set_status(text)
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffB7A3CCCVarBrowser|r " .. text
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

    if lower == "undo" then
        local undo = frame.undo_stack or {}
        local last = undo[#undo]
        if not last or last.previous == nil then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r nothing to undo"
            )
            return
        end
        if not frame:IsShown() then
            frame:Show()
        end
        local entry = by_name[last.name]
        if not entry then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r CVar no longer exists: "
                    .. last.name
            )
            return
        end
        if entry.readonly or entry.locked
            or (entry.secure and InCombatLockdown()) then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r cannot undo " .. last.name
                    .. " in its current state"
            )
            return
        end
        local current = entry.value
        undo[#undo] = nil
        local ok, result = pcall(SetCVarNative, last.name, last.previous)
        if not ok or result == false then
            undo[#undo + 1] = last
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r undo refused for " .. last.name
            )
            set_status("Undo refused: " .. last.name, "error")
            return
        end
        read_cvar_value(entry)
        if entry.value ~= last.previous then
            undo[#undo + 1] = last
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r undo did not stick for "
                    .. last.name
            )
            set_status("Undo did not stick: " .. last.name, "error")
            return
        end
        local redo = frame.redo_stack or {}
        frame.redo_stack = redo
        redo[#redo + 1] = {
            name = last.name,
            previous = current,
        }
        apply_range(entry)
        select_entry(entry)
        update_rows()
        update_detail()
        local text = format(
            "Undid %s; restored %s",
            last.name,
            display_edit_value(entry, entry.value)
        )
        set_status(text)
        DEFAULT_CHAT_FRAME:AddMessage("|cffB7A3CCCVarBrowser|r " .. text)
        return
    end

    if lower == "redo" then
        local redo = frame.redo_stack or {}
        local last = redo[#redo]
        if not last or last.previous == nil then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r nothing to redo"
            )
            return
        end
        if not frame:IsShown() then
            frame:Show()
        end
        local entry = by_name[last.name]
        if not entry then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r CVar no longer exists: "
                    .. last.name
            )
            return
        end
        if entry.readonly or entry.locked
            or (entry.secure and InCombatLockdown()) then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r cannot redo " .. last.name
                    .. " in its current state"
            )
            return
        end
        local current = entry.value
        redo[#redo] = nil
        local ok, result = pcall(SetCVarNative, last.name, last.previous)
        if not ok or result == false then
            redo[#redo + 1] = last
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r redo refused for " .. last.name
            )
            set_status("Redo refused: " .. last.name, "error")
            return
        end
        read_cvar_value(entry)
        if entry.value ~= last.previous then
            redo[#redo + 1] = last
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffB7A3CCCVarBrowser|r redo did not stick for "
                    .. last.name
            )
            set_status("Redo did not stick: " .. last.name, "error")
            return
        end
        local undo = frame.undo_stack or {}
        frame.undo_stack = undo
        undo[#undo + 1] = {
            name = last.name,
            previous = current,
        }
        if #undo > 20 then
            table.remove(undo, 1)
        end
        apply_range(entry)
        select_entry(entry)
        update_rows()
        update_detail()
        local text = format(
            "Redid %s; now %s",
            last.name,
            display_edit_value(entry, entry.value)
        )
        set_status(text)
        DEFAULT_CHAT_FRAME:AddMessage("|cffB7A3CCCVarBrowser|r " .. text)
        return
    end

    if lower == "refresh" or lower == "rescan" then
        if frame:IsShown() then
            rescan()
        else
            frame:Show()
        end
        return
    end

    if lower == "ranges" then
        local only = message_text:match("^ranges%s+(.+)$")
        only = only and trim(only):lower() or nil
        local names = {}
        if db and type(db.observed) == "table" then
            for name in pairs(db.observed) do
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
            local observed = db.observed[name]
            local entry = by_name[name]
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
        if db and type(db.observed) == "table" then
            for _ in pairs(db.observed) do
                count = count + 1
            end
            db.observed = {}
        end
        DEFAULT_CHAT_FRAME:AddMessage(
            format(
                "|cffB7A3CCCVarBrowser|r cleared %d observed range%s",
                count,
                count == 1 and "" or "s"
            )
        )
        if frame:IsShown() then
            rescan()
        else
            frame:Show()
        end
        return
    end

    local clear_name = message_text:match("^clearrange%s+(.+)$")
    if clear_name then
        clear_name = trim(clear_name)
        local found = false
        if db and type(db.observed) == "table" then
            for name in pairs(db.observed) do
                if name:lower() == clear_name:lower() then
                    db.observed[name] = nil
                    found = true
                    break
                end
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffB7A3CCCVarBrowser|r "
                .. (found and "cleared " or "no observed range for ")
                .. clear_name
        )
        if frame:IsShown() then
            rescan()
        else
            frame:Show()
        end
        return
    end

    if message_text ~= "" then
        if not frame:IsShown() then
            frame:Show()
        end
        search_box:SetText(message_text)
        search_box:ClearFocus()
        rebuild_view()
        if #view > 0 then
            select_entry(view[1])
            if not view[1].readonly
                and not (view[1].secure and InCombatLockdown()) then
                detail_edit:SetFocus()
                detail_edit:HighlightText()
            end
        end
        return
    end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
