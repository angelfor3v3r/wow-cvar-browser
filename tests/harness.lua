-- Headless WoW API stub harness for CVarBrowser.lua.
--
-- Run it from the addon folder with `lua tests/harness.lua`. It exits
-- non-zero if any check fails. It covers load, ADDON_LOADED, scan,
-- set/clamp/reset, undo/redo, read-only selection, slash commands, copy,
-- CVAR_UPDATE casing, pattern search, smooth scrolling, the pixel-locked
-- window drag, and main-chunk register headroom. Pixel-level visuals still
-- need an in-game /reload and /cvars.

local SCRIPT_DIR = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local ADDON_PATH = SCRIPT_DIR .. "/../CVarBrowser.lua"

-- Physical px per frame unit that the stubs produce. measure_px_per_unit
-- reads GetScaledRect width (equal to GetWidth here) * physical height /
-- 768 / 100.
local PHYSICAL_WIDTH, PHYSICAL_HEIGHT = 2560, 1440
local PX = PHYSICAL_HEIGHT / 768

local g_failures = 0
local g_checks = 0
local function check(condition, label)
    g_checks = g_checks + 1
    if not condition then
        g_failures = g_failures + 1
        io.stderr:write("FAIL: ", label, "\n")
    end
end

local function on_pixel_grid(value)
    local px = value * PX
    return math.abs(px - math.floor(px + 0.5)) < 1e-6
end

-- Widget stubs ---------------------------------------------------------------

local g_widgets = {}
local g_chat = {}
local g_set_calls = {}
local g_last_focus = nil
local g_methods = {}
local g_widget_mt = {
    __index = function(_, key)
        local method = g_methods[key]
        if method then
            return method
        end
        -- Unmodelled WoW methods (Set*, Enable*, Register*, ...) are no-ops.
        if type(key) == "string" and key:match("^[A-Z]") then
            return function() end
        end
        return nil
    end,
}

local function new_widget(kind, name, parent)
    local widget = setmetatable({
        _kind = kind,
        _parent = parent,
        _children = {},
        _regions = {},
        _points = {},
        _scripts = {},
        _shown = true,
        _enabled = true,
        _w = 10,
        _h = 10,
        _text = "",
        _scroll = 0,
        _level = 1,
    }, g_widget_mt)
    g_widgets[#g_widgets + 1] = widget
    if parent then
        local list = (kind == "Texture" or kind == "FontString" or kind == "Line")
            and parent._regions or parent._children
        list[#list + 1] = widget
    end
    if name then
        _G[name] = widget
    end
    return widget
end

local function fire_script(widget, name, ...)
    local handler = widget._scripts[name]
    if handler then
        return handler(widget, ...)
    end
end

function g_methods:GetObjectType() return self._kind end
function g_methods:IsObjectType(kind) return self._kind == kind end
function g_methods:CreateTexture() return new_widget("Texture", nil, self) end
function g_methods:CreateFontString() return new_widget("FontString", nil, self) end
function g_methods:CreateLine() return new_widget("Line", nil, self) end
function g_methods:GetChildren() return unpack(self._children) end
function g_methods:GetRegions() return unpack(self._regions) end
function g_methods:GetParent() return self._parent end
function g_methods:SetScript(name, handler) self._scripts[name] = handler end
function g_methods:GetScript(name) return self._scripts[name] end
function g_methods:HookScript(name, handler)
    local previous = self._scripts[name]
    self._scripts[name] = function(...)
        if previous then
            previous(...)
        end
        return handler(...)
    end
end
function g_methods:Show()
    local was_shown = self._shown
    self._shown = true
    if not was_shown then
        fire_script(self, "OnShow")
    end
end
function g_methods:Hide() self._shown = false end
function g_methods:IsShown() return self._shown end
function g_methods:IsVisible() return self._shown end
function g_methods:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end
function g_methods:Enable() self._enabled = true end
function g_methods:Disable() self._enabled = false end
function g_methods:SetEnabled(enabled) self._enabled = enabled and true or false end
function g_methods:IsEnabled() return self._enabled end
function g_methods:SetSize(w, h) self._w, self._h = w, h end
function g_methods:SetWidth(w) self._w = w end
function g_methods:SetHeight(h) self._h = h end
function g_methods:GetWidth() return self._w end
function g_methods:GetHeight() return self._h end
function g_methods:GetSize() return self._w, self._h end
function g_methods:GetLeft() return 100.37 end
function g_methods:GetRight() return 100.37 + self._w end
function g_methods:GetTop() return 500.61 end
function g_methods:GetBottom() return 500.61 - self._h end
function g_methods:GetCenter() return 300.2, 400.7 end
function g_methods:GetRect() return 100.37, 500.61 - self._h, self._w, self._h end
function g_methods:GetScaledRect() return self:GetRect() end
function g_methods:GetEffectiveScale() return 0.7111 end
function g_methods:GetScale() return 1 end
function g_methods:SetPoint(point, relative_to, relative_point, x, y)
    for index, existing in ipairs(self._points) do
        if existing[1] == point then
            self._points[index] = { point, relative_to, relative_point, x, y }
            return
        end
    end
    self._points[#self._points + 1] = { point, relative_to, relative_point, x, y }
end
function g_methods:ClearAllPoints() self._points = {} end
function g_methods:GetNumPoints() return #self._points end
function g_methods:GetPoint(index)
    local p = self._points[index or 1]
    if p then
        return p[1], p[2], p[3], p[4], p[5]
    end
end
function g_methods:SetText(text)
    text = text == nil and "" or tostring(text)
    local changed = text ~= self._text
    self._text = text
    if self._kind == "EditBox" and changed then
        fire_script(self, "OnTextChanged", false)
    end
end
function g_methods:GetText() return self._text end
function g_methods:GetStringWidth() return #self._text * 6.3 end
function g_methods:GetUnboundedStringWidth() return #self._text * 6.3 end
function g_methods:GetStringHeight() return 13 end
function g_methods:GetNumLines() return 1 end
function g_methods:GetFont() return "font", 12, "" end
function g_methods:GetFrameLevel() return self._level end
function g_methods:SetFrameLevel(level) self._level = level end
function g_methods:SetFocus() g_last_focus = self; self._focused = true end
function g_methods:ClearFocus()
    local had_focus = self._focused
    self._focused = false
    if had_focus then
        fire_script(self, "OnEditFocusLost")
    end
end
function g_methods:HasFocus() return self._focused == true end
function g_methods:HighlightText() self._highlighted = true end
function g_methods:IsMouseOver() return false end
function g_methods:SetScrollChild(child) self._scroll_child = child end
function g_methods:GetVerticalScroll() return self._scroll end
function g_methods:GetVerticalScrollRange()
    local child = self._scroll_child
    return child and math.max(0, child._h - self._h) or 0
end
function g_methods:SetVerticalScroll(value)
    self._scroll = value
    fire_script(self, "OnVerticalScroll", value)
end

-- WoW globals ----------------------------------------------------------------

_G.CreateFrame = function(kind, name, parent) return new_widget(kind, name, parent) end
_G.CreateFont = function(name)
    local font = new_widget("Font", name)
    font.SetFont = function() return true end
    return font
end
_G.UIParent = new_widget("Frame", "UIParent")
_G.Minimap = new_widget("Frame", "Minimap")
_G.GameTooltip = new_widget("GameTooltip", "GameTooltip")
_G.DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, message) g_chat[#g_chat + 1] = message end,
}
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.STANDARD_TEXT_FONT = "font"
local g_in_combat = false
_G.InCombatLockdown = function() return g_in_combat end
local g_cursor_x, g_cursor_y = 640, 360
_G.GetCursorPosition = function() return g_cursor_x, g_cursor_y end
_G.GetPhysicalScreenSize = function() return PHYSICAL_WIDTH, PHYSICAL_HEIGHT end
local g_mouse_down = true
_G.IsMouseButtonDown = function() return g_mouse_down end
local g_timers = {}
_G.C_Timer = {
    After = function(delay, callback)
        g_timers[#g_timers + 1] = { delay = delay, callback = callback }
    end,
}
_G.Enum = { ConsoleCommandType = { Cvar = 0, Command = 1 } }
-- TOC metadata. The main load runs as a CI release build, and a second
-- load at the end runs as a repository (dev) build.
local g_metadata = { Version = "1.0.1", ["X-Build"] = "afaa9bd 2026-11-18" }
_G.C_AddOns = {
    GetAddOnMetadata = function(_, field) return g_metadata[field] end,
}
_G.unpack = _G.unpack or table.unpack

-- CVar store. GetCVarInfo returns values in the order verified in game
-- (value, default, account, character, locked, secure, read-only).
local g_cvars = {
    { name = "cameraDistanceMaxZoomFactor", value = "1.9", default = "1.9",
      help = "Max camera zoom (1-2.6)", max = 2.6 },
    { name = "graphicsQuality", value = "7", default = "5", help = "Graphics quality" },
    { name = "autoLootDefault", value = "1", default = "0", help = "Auto loot (0/1)" },
    { name = "closedInfoFrames", value = "5", default = "0", help = "Bitfield" },
    { name = "readOnlyThing", value = "3", default = "3", help = "Read only", readonly = true },
    { name = "secureThing", value = "1", default = "1", help = "Secure", secure = true },
    { name = "aVeryLongConsoleVariableNameThatWasCutOffEarly",
      value = "a text value well past the old 28-character cap",
      default = "a text value well past the old 28-character cap", help = "Long name" },
}
for index = 1, 40 do
    g_cvars[#g_cvars + 1] = {
        name = "extra" .. index,
        value = tostring(index),
        default = "0",
        help = "Range [0, 100]",
    }
end
local g_by_name = {}
for _, cvar in ipairs(g_cvars) do
    g_by_name[cvar.name] = cvar
end

_G.C_Console = {
    GetAllCommands = function()
        local out = {}
        for index, cvar in ipairs(g_cvars) do
            out[#out + 1] = {
                command = cvar.name,
                help = cvar.help,
                category = index % 10,
                commandType = 0,
            }
        end
        out[#out + 1] = { command = "reloadui", help = "", category = 2, commandType = 1 }
        return out
    end,
}
_G.C_CVar = {
    GetCVar = function(name) return g_by_name[name] and g_by_name[name].value end,
    GetCVarInfo = function(name)
        local cvar = g_by_name[name]
        if cvar then
            return cvar.value, cvar.default, false, true, false,
                cvar.secure == true, cvar.readonly == true
        end
    end,
    GetCVarDefault = function(name) return g_by_name[name] and g_by_name[name].default end,
    SetCVar = function(name, value)
        g_set_calls[#g_set_calls + 1] = { name, tostring(value) }
        local cvar = g_by_name[name]
        if not cvar or cvar.readonly then
            return false
        end
        local number = tonumber(value)
        if cvar.max and number and number > cvar.max then
            value = tostring(cvar.max)
        end
        cvar.value = tostring(value)
        return true
    end,
}

-- Helpers --------------------------------------------------------------------

local function find_widget(predicate)
    for _, widget in ipairs(g_widgets) do
        if predicate(widget) then
            return widget
        end
    end
end

local function button_with_label(label)
    local text = find_widget(function(w)
        return w._kind == "FontString" and w._text == label
    end)
    return text and text._parent
end

local function chat_has(pattern)
    for _, message in ipairs(g_chat) do
        if message:find(pattern) then
            return true
        end
    end
    return false
end

local function last_set_call()
    return g_set_calls[#g_set_calls]
end

local function slash(command)
    local ok, err = pcall(SlashCmdList.CVARBROWSER, command)
    check(ok, "slash '" .. command .. "' raised: " .. tostring(err))
end

-- Load -----------------------------------------------------------------------

do
    local chunk = assert(loadfile(ADDON_PATH))
    local load_ok, load_err = pcall(chunk, "CVarBrowser", {})
    check(load_ok, "addon load: " .. tostring(load_err))
    if not load_ok then
        io.stderr:write(g_failures, " failure(s)\n")
        os.exit(1)
    end
end

local g_frame = _G.CVarBrowserFrame
check(g_frame ~= nil, "CVarBrowserFrame global exists")
check(type(SlashCmdList.CVARBROWSER) == "function", "slash handler registered")
check(find_widget(function(w)
    return w._kind == "FontString" and w._text == "WoW Forever · v1.0.1 · afaa9bd"
end) ~= nil, "a release build shows its version and hash in the subtitle")

local function fire(event, ...)
    local ok, err = pcall(g_frame._scripts.OnEvent, g_frame, event, ...)
    check(ok, "event " .. event .. " raised: " .. tostring(err))
end

fire("ADDON_LOADED", "CVarBrowser")
check(type(CVarBrowserDB) == "table", "ADDON_LOADED creates saved variables")
check(CVarBrowserDB.smooth_scroll == true, "smooth scrolling defaults on")
fire("PLAYER_ENTERING_WORLD")

-- Scan -----------------------------------------------------------------------

slash("")
check(g_frame:IsShown(), "bare /cvars opens the browser")
local g_count_text = find_widget(function(w)
    return w._kind == "FontString" and w._text:match("^%d+ / %d+ CVars")
end)
check(g_count_text ~= nil, "count text rendered")
check(g_count_text and g_count_text._text:match("^47 / 47 CVars") ~= nil,
    "scan lists every CVar and skips commands: " .. tostring(g_count_text and g_count_text._text))

local g_set_button = button_with_label("Set")
local g_reset_button = button_with_label("Reset to default")
check(g_set_button ~= nil and g_reset_button ~= nil, "Set and Reset buttons exist")

-- Set / clamp / undo / redo / reset ------------------------------------------

do
    g_last_focus = nil
    slash("cameraDistanceMaxZoomFactor")
    local detail_edit = g_last_focus
    check(detail_edit ~= nil and detail_edit._kind == "EditBox",
        "/cvars <name> focuses the value field")
    check(g_set_button._enabled, "Set enabled for a writable CVar")

    detail_edit:SetText("5")
    fire_script(detail_edit, "OnEnterPressed")
    local call = last_set_call()
    check(call and call[1] == "cameraDistanceMaxZoomFactor" and call[2] == "5",
        "Enter sends SetCVar with the typed value")
    check(g_by_name.cameraDistanceMaxZoomFactor.value == "2.6", "stub clamped to 2.6")
    local observed = CVarBrowserDB.observed.cameraDistanceMaxZoomFactor
    check(type(observed) == "table", "clamp is recorded as an observed bound")

    g_chat = {}
    slash("Ranges cameraDistanceMaxZoomFactor")
    check(chat_has("1 observed range"), "/cvars ranges <name> lists that CVar (any case)")

    slash("undo")
    call = last_set_call()
    check(call and call[2] == "1.9", "undo restores the previous value")
    slash("redo")
    call = last_set_call()
    check(call and call[2] == "2.6", "redo re-applies the clamped value")

    fire_script(g_reset_button, "OnClick")
    call = last_set_call()
    check(call and call[1] == "cameraDistanceMaxZoomFactor" and call[2] == "1.9",
        "Reset sends the default value")

    g_chat = {}
    slash("ClearRange cameraDistanceMaxZoomFactor")
    check(chat_has("cleared cameraDistanceMaxZoomFactor"),
        "clearrange accepts any case and echoes the stored name")
end

-- Read-only selection --------------------------------------------------------

do
    g_last_focus = nil
    slash("readOnlyThing")
    check(g_last_focus == nil, "read-only selection does not focus the value field")
    check(not g_set_button._enabled and not g_reset_button._enabled,
        "Set/Reset disabled for a read-only CVar")
    local calls_before = #g_set_calls
    fire_script(g_set_button, "OnClick")
    check(#g_set_calls == calls_before, "Set does not call SetCVar for read-only")
end

-- Secure CVar in combat ------------------------------------------------------

do
    g_in_combat = true
    fire("PLAYER_REGEN_DISABLED")
    slash("secureThing")
    check(not g_set_button._enabled, "Set disabled for a secure CVar in combat")
    g_in_combat = false
    fire("PLAYER_REGEN_ENABLED")
    check(g_set_button._enabled, "Set re-enabled after combat")
end

-- CVAR_UPDATE casing ---------------------------------------------------------

do
    slash("graphicsQuality")
    g_by_name.graphicsQuality.value = "9"
    fire("CVAR_UPDATE", "GRAPHICSQUALITY")
    check(find_widget(function(w)
        return w._kind == "FontString" and w._text:match("^9 ")
    end) ~= nil, "CVAR_UPDATE with different casing refreshes the row")
end

-- Row columns ----------------------------------------------------------------

do
    local long_name = "aVeryLongConsoleVariableNameThatWasCutOffEarly"
    slash(long_name)
    local name_text = find_widget(function(w)
        return w._kind == "FontString" and w._text == long_name
            and w._parent._kind == "Button"
    end)
    check(name_text ~= nil, "row shows a long CVar name in full (no character cap)")
    local child = find_widget(function(w)
        return w._kind == "ScrollFrame" and w._parent == g_frame
    end)._scroll_child
    local expected = math.floor(child._w / 2 - 44 - 16 + 0.5)
    check(name_text and name_text._w == expected,
        "name column reaches 10px short of the gauge: "
            .. tostring(name_text and name_text._w) .. " vs " .. expected)

    local long_value = "a text value well past the old 28-character cap"
    local value_text = find_widget(function(w)
        return w._kind == "FontString" and w._text == long_value
            and w._parent._kind == "Button"
    end)
    check(value_text ~= nil, "unchanged row shows a long value in full")
    check(value_text and value_text._w == expected,
        "value column mirrors the name column: " .. tostring(value_text and value_text._w))

    -- Gauge marks sit at whole-pixel offsets so they never straddle a pixel
    -- edge and render 0 or 2px thick while scrolling.
    slash("extra")
    local marks, on_grid = 0, true
    for _, widget in ipairs(g_widgets) do
        if widget._kind == "Texture" and widget.mark_width and widget._shown then
            local _, _, _, x, y = widget:GetPoint(1)
            marks = marks + 1
            if not (x and y and x == math.floor(x) and y == math.floor(y)) then
                on_grid = false
            end
        end
    end
    check(marks > 0, "gauge marks are shown for ranged CVars")
    check(on_grid, "every gauge mark is anchored at whole-pixel offsets")

    -- The 1px track runs along row 3 of the 8px gauge.
    local tick = find_widget(function(w)
        return w._kind == "Texture" and w.mark_width == 1 and w._shown
    end)
    local track = nil
    for _, region in ipairs(tick and tick._parent._regions or {}) do
        if region._kind == "Texture" and not region.mark_width then
            track = region
        end
    end
    -- The stubs measure 1.875 physical px per unit, so pixel snapping can
    -- nudge these offsets by a fraction of a unit. The anchor points still
    -- prove the layout (the old code centered the track on LEFT/RIGHT).
    local p1, _, _, x1, y1 = nil, nil, nil, nil, nil
    local p2, y2 = nil, nil
    if track then
        p1, _, _, x1, y1 = track:GetPoint(1)
        p2, _, _, _, y2 = track:GetPoint(2)
    end
    check(p1 == "TOPLEFT" and math.abs(x1) < 1 and math.abs(y1 + 3) < 1
        and p2 == "TOPRIGHT" and math.abs(y2 + 3) < 1,
        "the gauge track is anchored on row 3")

    -- A CVar with no known range shows the 2x2 dot at the gauge center.
    slash("readOnlyThing")
    local dot = find_widget(function(w)
        return w._kind == "Texture" and w.mark_width == 2 and w.mark_height == 2
            and w._shown
    end)
    local dot_point, dot_x, dot_y = nil, nil, nil
    if dot then
        dot_point, _, _, dot_x, dot_y = dot:GetPoint(1)
    end
    check(dot_point == "TOPLEFT" and math.abs(dot_x - 43) < 1 and math.abs(dot_y + 3) < 1,
        "the no-range dot sits at (43, -3)")

    -- An observed max with no minimum draws the open "/" end on whole pixels.
    CVarBrowserDB.observed.graphicsQuality = { max = 9 }
    slash("refresh")
    slash("graphicsQuality")
    local slant = find_widget(function(w)
        if w._kind ~= "FontString" or w._text ~= "/" or not w._shown then
            return false
        end
        for _, sibling in ipairs(w._parent._regions) do
            if sibling.mark_width then
                return true
            end
        end
        return false
    end)
    local slant_point, slant_x, slant_y = nil, nil, nil
    if slant then
        slant_point, _, _, slant_x, slant_y = slant:GetPoint(1)
    end
    check(slant_point == "TOPLEFT" and slant_x == math.floor(slant_x)
        and slant_y == math.floor(slant_y),
        "the open-end slant is placed on whole pixels")
    CVarBrowserDB.observed.graphicsQuality = nil
    slash("refresh")
end

-- Copy -----------------------------------------------------------------------

do
    slash("autoLootDefault")
    g_last_focus = nil
    slash("copy name")
    check(g_last_focus ~= nil and g_last_focus._text == "autoLootDefault"
        and g_last_focus._highlighted, "copy shows the name highlighted in a focused box")
    local status = find_widget(function(w)
        return w._kind == "FontString" and w._text:match("^Press Ctrl%+C to copy name")
    end)
    check(status ~= nil, "copy status tells the user to press Ctrl+C")
    -- The status line ends at the detail area's right edge (the 24px window
    -- padding). Before it come the 340px value field, Set, Reset, and gaps
    -- of 8, 8, and 12px.
    local detail_name = find_widget(function(w)
        return w._kind == "FontString" and w._parent == status._parent
            and w._text == "autoLootDefault"
    end)
    local used = 340 + button_with_label("Set")._w
        + button_with_label("Reset to default")._w + 28
    -- Pixel snapping may move the buttons by under a pixel after layout.
    check(detail_name and math.abs(status._w - (detail_name._w - used)) <= 1,
        "status line runs to the right padding: " .. tostring(status._w))
    local copy_box = g_last_focus
    fire_script(copy_box, "OnEscapePressed")
    check(not copy_box._parent._shown, "Escape closes the copy box")
end

-- Pattern search keeps escaped class letters ---------------------------------

do
    slash("regex on")
    slash("^extra%d")
    check(g_count_text._text:match("^40 / 47") ~= nil,
        "pattern ^extra%d matches the 40 extraN CVars: " .. g_count_text._text)
    slash("^extra%D")
    check(g_count_text._text:match("^0 / 47") ~= nil,
        "pattern ^extra%D (uppercase class) matches none: " .. g_count_text._text)
    slash("regex off")
    slash("extra")
end

-- Search Enter keeps an arrow-key selection ----------------------------------

do
    local search_box = find_widget(function(w)
        return w._kind == "EditBox" and w._scripts.OnKeyDown ~= nil
    end)
    check(search_box ~= nil, "search box exists")
    fire_script(search_box, "OnKeyDown", "DOWN")
    fire_script(search_box, "OnKeyDown", "DOWN")
    fire_script(search_box, "OnEnterPressed")
    g_last_focus = nil
    slash("copy name")
    check(g_last_focus and g_last_focus._text == "extra11",
        "Enter after two DOWN presses keeps the third match selected: "
            .. tostring(g_last_focus and g_last_focus._text))
    fire_script(g_last_focus, "OnEscapePressed")
    slash("extra")
end

-- Smooth scrolling -----------------------------------------------------------

do
    local scroll_frame = find_widget(function(w)
        return w._kind == "ScrollFrame" and w._parent == g_frame
    end)
    check(scroll_frame ~= nil, "list scroll frame exists")
    scroll_frame._h = 340
    fire_script(scroll_frame, "OnScrollRangeChanged", 0, scroll_frame:GetVerticalScrollRange())
    scroll_frame:SetVerticalScroll(0)

    local positions = {}
    local original_set = scroll_frame.SetVerticalScroll
    scroll_frame.SetVerticalScroll = function(self, value)
        positions[#positions + 1] = value
        return original_set(self, value)
    end
    fire_script(scroll_frame, "OnMouseWheel", -1)
    fire_script(scroll_frame, "OnMouseWheel", -1)
    local frames = 0
    while scroll_frame._scripts.OnUpdate and frames < 200 do
        frames = frames + 1
        scroll_frame._scripts.OnUpdate(scroll_frame, 1 / 60)
    end
    scroll_frame.SetVerticalScroll = nil
    check(frames > 1 and frames < 200, "smooth scroll animates over several frames")
    local target = math.floor(2 * 66 * PX + 0.5) / PX
    check(math.abs(scroll_frame._scroll - target) < 1e-9,
        "two wheel notches accumulate to 6 rows: " .. scroll_frame._scroll)
    local all_on_grid, monotonic = true, true
    for index, value in ipairs(positions) do
        if not on_pixel_grid(value) then
            all_on_grid = false
        end
        if index > 1 and value < positions[index - 1] then
            monotonic = false
        end
    end
    check(all_on_grid, "every smooth-scroll step lands on a whole pixel")
    check(monotonic, "smooth scroll never overshoots backwards")

    CVarBrowserDB.smooth_scroll = false
    fire_script(scroll_frame, "OnMouseWheel", 1)
    check(scroll_frame._scripts.OnUpdate == nil, "smooth off scrolls instantly")
    CVarBrowserDB.smooth_scroll = true

    -- Pinned to the bottom across a range change.
    scroll_frame:SetVerticalScroll(scroll_frame:GetVerticalScrollRange())
    fire_script(scroll_frame, "OnScrollRangeChanged", 0, scroll_frame:GetVerticalScrollRange())
    scroll_frame._h = 404
    local new_range = scroll_frame:GetVerticalScrollRange()
    fire_script(scroll_frame, "OnScrollRangeChanged", 0, new_range)
    check(math.abs(scroll_frame._scroll - new_range) < 1e-9,
        "list stays pinned to the bottom when the range shrinks")
    scroll_frame._h = 340
    local grown = scroll_frame:GetVerticalScrollRange()
    fire_script(scroll_frame, "OnScrollRangeChanged", 0, grown)
    check(math.abs(scroll_frame._scroll - grown) < 1e-9,
        "list stays pinned to the bottom when the range grows")
end

-- Size switch ----------------------------------------------------------------

do
    local large_row = find_widget(function(w)
        return w.option and w.option.value == "large"
    end)
    check(large_row ~= nil, "Size menu has a Large row")
    for index = #g_timers, 1, -1 do
        g_timers[index] = nil
    end
    fire_script(large_row, "OnClick", "LeftButton")
    local deferred = nil
    for _, timer in ipairs(g_timers) do
        if timer.delay == 0 then
            deferred = timer.callback
        end
    end
    check(deferred ~= nil, "a size change schedules a second layout pass")
    if deferred then
        local ok, err = pcall(deferred)
        check(ok, "the second layout pass runs: " .. tostring(err))
    end

    -- The Size button fits its label with 4px of padding on each side
    -- (within a unit, since the stubs snap at 1.875 px per unit).
    local size_button = button_with_label("Size: Large")
    local snug = #"Size: Large" * 6.3 + 8
    check(size_button and math.abs(size_button._w - snug) < 1,
        "the Size button is a snug fit: " .. tostring(size_button and size_button._w))
    CVarBrowserDB.preset = "auto"
end

-- Pixel-locked window drag ---------------------------------------------------

do
    local titlebar = find_widget(function(w)
        return w._parent == g_frame and w._scripts.OnMouseDown ~= nil
            and w._scripts.OnMouseUp ~= nil
    end)
    check(titlebar ~= nil, "title bar drag handler exists")
    g_cursor_x, g_cursor_y = 640, 360
    fire_script(titlebar, "OnMouseDown", "LeftButton")
    check(g_frame._scripts.OnUpdate ~= nil, "mouse down starts the drag at once")
    local drag_on_grid, drag_follows = true, true
    local scale = g_frame:GetEffectiveScale()
    for step = 1, 25 do
        g_cursor_x = 640 + step * 1.37
        g_cursor_y = 360 - step * 0.91
        g_frame._scripts.OnUpdate(g_frame, 1 / 60)
        local _, _, _, x, y = g_frame:GetPoint(1)
        if not (x and y and on_pixel_grid(x) and on_pixel_grid(y)) then
            drag_on_grid = false
        end
        -- Cursor screen units convert to frame units through the effective
        -- scale. The stub GetLeft and GetTop are fixed, so the anchor should
        -- follow the cursor delta to within half a physical pixel.
        local expected_x = 100.37 + (g_cursor_x - 640) / scale
        local expected_y = 500.61 + (g_cursor_y - 360) / scale
        if not x or math.abs(x - expected_x) > 0.5 / PX + 1e-9
            or math.abs(y - expected_y) > 0.5 / PX + 1e-9 then
            drag_follows = false
        end
    end
    check(drag_on_grid, "every drag position lands on a whole pixel")
    check(drag_follows, "the dragged window follows the cursor in frame units")
    CVarBrowserDB.point, CVarBrowserDB.relativePoint = nil, nil
    fire_script(titlebar, "OnMouseUp", "LeftButton")
    check(g_frame._scripts.OnUpdate == nil, "mouse up removes the OnUpdate")
    check(CVarBrowserDB.point == "TOPLEFT" and CVarBrowserDB.relativePoint == "BOTTOMLEFT"
        and type(CVarBrowserDB.x) == "number", "mouse up saves the anchor and position")

    -- A release the title bar never sees still ends the drag.
    fire_script(titlebar, "OnMouseDown", "LeftButton")
    CVarBrowserDB.point, CVarBrowserDB.relativePoint = nil, nil
    g_mouse_down = false
    g_frame._scripts.OnUpdate(g_frame, 1 / 60)
    g_mouse_down = true
    check(g_frame._scripts.OnUpdate == nil and CVarBrowserDB.point == "TOPLEFT",
        "releasing the button anywhere stops the drag and saves the anchor")
end

-- Every remaining script handler runs without raising ------------------------

do
    local skip = { OnUpdate = true, OnEvent = true, OnDragStart = true }
    local snapshot = {}
    for index, widget in ipairs(g_widgets) do
        snapshot[index] = widget
    end
    for _, widget in ipairs(snapshot) do
        for name, handler in pairs(widget._scripts) do
            if not skip[name] then
                local range_event = name == "OnScrollRangeChanged"
                local ok, err = pcall(handler, widget,
                    name == "OnMouseWheel" and -1 or range_event and 0 or "LeftButton",
                    range_event and 0 or "x")
                check(ok, "script " .. name .. " raised: " .. tostring(err))
            end
        end
    end
end

-- Repository build -------------------------------------------------------------

do
    g_metadata = { Version = "dev" }
    local ok, err = pcall(assert(loadfile(ADDON_PATH)), "CVarBrowser", {})
    check(ok, "dev build loads: " .. tostring(err))
    check(find_widget(function(w)
        return w._kind == "FontString" and w._text == "WoW Forever · dev"
    end) ~= nil, "a repository build says dev in the subtitle")
end

-- Main-chunk register headroom (Lua 5.1 caps active locals at 200) -----------

do
    -- LUAC names the Lua 5.1 compiler (CI sets LUAC=luac5.1). When LUAC is set,
    -- the register check must run. Without it, a missing luac just skips the
    -- check.
    local luac = os.getenv("LUAC")
    local listing = io.popen((luac or "luac") .. ' -l -l -p "' .. ADDON_PATH .. '" 2>&1')
    local slots = nil
    if listing then
        slots = tonumber(listing:read("*a"):match("main <.-\n[^\n]-(%d+) slots"))
        listing:close()
    end
    if slots then
        check(slots < 190, "main chunk uses " .. slots .. " of 200 register slots")
    elseif luac then
        check(false, "register check: could not run " .. luac)
    else
        io.stderr:write("note: luac not available; skipped register check\n")
    end
end

print(string.format("%d checks, %d failed", g_checks, g_failures))
os.exit(g_failures == 0 and 0 or 1)
