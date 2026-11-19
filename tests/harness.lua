-- Headless WoW API stub harness for the CVar Browser addon.
--
-- Run it from the addon folder with `lua tests/harness.lua`. It exits
-- non-zero if any check fails. It covers load, ADDON_LOADED, scan,
-- set/clamp/reset, undo/redo, the change log, read-only selection, slash
-- commands, copy, CVAR_UPDATE casing, pattern search, the value filter,
-- favorites, the row tooltip, keyboard navigation, smooth scrolling, the
-- pixel-locked window drag, and main-chunk register headroom. Pixel-level
-- visuals still need an in-game /reload and /cvars.

local SCRIPT_DIR = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local ADDON_DIR = SCRIPT_DIR .. "/.."

-- The Lua files in the order the TOC loads them.
local ADDON_FILES = {}
for line in io.lines(ADDON_DIR .. "/CVarBrowser.toc") do
    local file = line:match("^([^#%s][^\r]-%.lua)%s*$")
    if file then
        ADDON_FILES[#ADDON_FILES + 1] = ADDON_DIR .. "/" .. (file:gsub("\\", "/"))
    end
end

-- Runs every TOC file in order with one shared namespace, as the client
-- does. Returns false and the error when a file fails to load or run.
local function load_addon()
    local namespace = {}
    for _, path in ipairs(ADDON_FILES) do
        local chunk, load_err = loadfile(path)
        if not chunk then
            return false, load_err
        end
        local ok, run_err = pcall(chunk, "CVarBrowser", namespace)
        if not ok then
            return false, path .. ": " .. tostring(run_err)
        end
    end
    return true, nil
end

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
function g_methods:Click()
    if self._enabled then
        fire_script(self, "OnClick", "LeftButton")
    end
end
function g_methods:SetPropagateKeyboardInput(propagate)
    self._propagate = propagate
end
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
function g_methods:SetColorTexture(r, g, b) self._color = { r, g, b } end
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
function g_methods:IsMouseOver() return self._mouse_over == true end
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
local g_ctrl_down, g_shift_down = false, false
_G.IsControlKeyDown = function() return g_ctrl_down end
_G.IsShiftKeyDown = function() return g_shift_down end
_G.IsAltKeyDown = function() return false end
local g_timers = {}
_G.C_Timer = {
    After = function(delay, callback)
        g_timers[#g_timers + 1] = { delay = delay, callback = callback }
    end,
}
_G.Enum = { ConsoleCommandType = { Cvar = 0, Command = 1 } }
-- A fixed clock keeps change log times deterministic.
_G.time = function() return 1763467200 end
_G.date = os.date
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
            return cvar.value, cvar.default, false, true, cvar.locked == true,
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

-- Reads the selected CVar's name through the copy box, then closes it.
local function selected_name()
    g_last_focus = nil
    slash("copy name")
    local name = g_last_focus and g_last_focus._text
    if g_last_focus then
        fire_script(g_last_focus, "OnEscapePressed")
    end
    return name
end

-- Load -----------------------------------------------------------------------

do
    check(#ADDON_FILES > 1, "the TOC lists the addon's Lua files: " .. #ADDON_FILES)
    local load_ok, load_err = load_addon()
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
    local camera = g_frame.by_name.cameraDistanceMaxZoomFactor
    check(camera.clamp_at == 2.6, "a clamped set marks the clamp on the gauge")

    g_chat = {}
    slash("Ranges cameraDistanceMaxZoomFactor")
    check(chat_has("1 observed range"), "/cvars ranges <name> lists that CVar (any case)")

    g_chat = {}
    slash("undo")
    check(chat_has("undid cameraDistanceMaxZoomFactor"), "/cvars undo prints to chat")
    call = last_set_call()
    check(call and call[2] == "1.9", "undo restores the previous value")
    check(camera.clamp_at == nil and camera.clamp_side == nil,
        "undo clears the clamp mark of the set it undid")
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

-- Numeric defaults, unknown defaults, and chat pipes -------------------------

do
    -- The client can report a value and its default in different forms.
    g_by_name.secureThing.default = "1.000000"
    slash("refresh")
    check(g_frame.by_name.secureThing and not g_frame.by_name.secureThing.changed,
        "a value equal to its default as a number is not changed")
    g_by_name.secureThing.default = "1"

    g_by_name.extra3.default = nil
    slash("refresh")
    slash("extra3")
    check(g_set_button._enabled and not g_reset_button._enabled,
        "Reset is disabled when the default is unknown")
    local calls_before = #g_set_calls
    fire_script(g_reset_button, "OnClick")
    check(#g_set_calls == calls_before, "Reset sends nothing when the default is unknown")
    g_by_name.extra3.default = "0"
    slash("refresh")

    -- Chat reads a bare pipe as an escape code, so lists use "||".
    for _, command in ipairs({ "help", "filters" }) do
        g_chat = {}
        slash(command)
        local text = (g_chat[1] or "")
            :gsub("^|c%x%x%x%x%x%x%x%xCVarBrowser|r ", "")
            :gsub("||", "")
        check(g_chat[1] ~= nil and not text:find("|", 1, true),
            "/cvars " .. command .. " escapes every pipe")
    end
end

-- Locked CVar ----------------------------------------------------------------

do
    g_by_name.graphicsQuality.locked = true
    slash("refresh")
    g_last_focus = nil
    slash("graphicsQuality")
    check(g_last_focus == nil, "/cvars <name> does not focus a locked CVar's value field")
    local search_box = find_widget(function(w)
        return w._kind == "EditBox" and w._scripts.OnKeyDown ~= nil
    end)
    g_last_focus = nil
    search_box:SetText("graphicsQuality")
    fire_script(search_box, "OnEnterPressed")
    check(g_last_focus == nil, "search Enter does not focus a locked CVar's value field")
    g_by_name.graphicsQuality.locked = nil
    slash("refresh")
    slash("extra")
end

-- Filters chip ---------------------------------------------------------------

do
    -- The client hands offsets back as 32-bit floats, a hair off what was
    -- written. A re-snap must still start from the design offset.
    local label = g_frame.filter_chip.label
    local point, relative_to, relative_point, x, y = label:GetPoint(1)
    label:SetPoint(point, relative_to, relative_point, x + 1e-6, y - 1e-6)
    g_frame.snap_region_tree(g_frame.filter_chip)
    g_frame.snap_region_tree(g_frame.filter_chip)
    check(label.text_snap and label.text_snap.base_x == 18 and label.text_snap.base_y == 0,
        "text snapping keeps the design offset through float rounding")

    g_frame.filters.scope = "account"
    g_frame.update_filter_chip()
    local part = g_frame.filter_chip.icon_parts and g_frame.filter_chip.icon_parts[1]
    check(part ~= nil and part._color[1] == 0.717647,
        "active filters tint the Filters funnel accent")
    g_frame.filters.scope = ""
    g_frame.update_filter_chip()

    -- The filter menu's scrollbar thumb can be dragged.
    fire_script(g_frame.filter_chip, "OnClick")
    local scroll = g_frame.filter_scroll
    local thumb = g_frame.filter_scroll_thumb
    scroll._h = 200
    scroll:SetVerticalScroll(0)
    g_mouse_down = true
    g_cursor_y = 360
    fire_script(thumb, "OnMouseDown", "LeftButton")
    g_cursor_y = 330
    thumb._scripts.OnUpdate(thumb, 1 / 60)
    check(scroll._scroll > 0, "dragging the filter thumb down scrolls the menu")
    fire_script(thumb, "OnMouseUp", "RightButton")
    check(thumb._scripts.OnUpdate ~= nil, "a right-button release keeps the thumb drag")
    fire_script(thumb, "OnMouseUp", "LeftButton")
    check(thumb._scripts.OnUpdate == nil, "releasing the filter thumb ends the drag")
    g_cursor_y = 360
    g_frame.close_menus()

    -- Clear all drops its hover look when it disables under the pointer.
    g_frame.filters.scope = "account"
    fire_script(g_frame.filter_chip, "OnClick")
    local clear = g_frame.filter_clear
    clear._mouse_over = true
    fire_script(clear, "OnEnter")
    check(clear._enabled and clear.background._color[1] == 0.137255,
        "Clear all shows its hover fill")
    fire_script(clear, "OnClick")
    check(not clear._enabled and clear.background._color[1] == 0.101961
        and clear.borders[1]._color[1] == 0.203922,
        "Clear all drops its hover look when it disables under the pointer")
    clear._mouse_over = false
    -- A refresh with the menu open keeps the labels snapped.
    local snapped = true
    for _, row in ipairs(g_frame.filter_rows) do
        if row._shown then
            local _, _, _, x = row.label:GetPoint(1)
            if not (row.label.text_snap and row.label.text_snap.x == x) then
                snapped = false
            end
        end
    end
    check(snapped, "filter labels stay snapped after an in-menu refresh")

    -- A tick that was hidden when the menu opened snaps once it shows.
    local last_row = g_frame.filter_rows[#g_frame.filter_rows]
    for index = #g_timers, 1, -1 do
        g_timers[index] = nil
    end
    last_row.on_click()
    last_row = g_frame.filter_rows[#g_frame.filter_rows]
    check(last_row.check._shown and last_row.check.text_snap == nil,
        "a tick that just showed is not snapped yet")
    for _, timer in ipairs(g_timers) do
        if timer.delay == 0 then
            timer.callback()
        end
    end
    check(last_row.check.text_snap ~= nil, "a tick that just showed snaps a frame later")
    last_row.on_click()
    g_frame.close_menus()
end

-- Secure CVar in combat ------------------------------------------------------

do
    -- PLAYER_REGEN_DISABLED fires before lockdown, so the controls update
    -- on the next frame, once InCombatLockdown is true.
    slash("secureThing")
    for index = #g_timers, 1, -1 do
        g_timers[index] = nil
    end
    fire("PLAYER_REGEN_DISABLED")
    g_in_combat = true
    for _, timer in ipairs(g_timers) do
        if timer.delay == 0 then
            timer.callback()
        end
    end
    check(not g_set_button._enabled, "Set disabled for a secure CVar in combat")
    local status = find_widget(function(w)
        return w._kind == "FontString" and w._text == "Secure CVars can't change in combat."
    end)
    check(status ~= nil, "a secure CVar in combat shows the combat warning")
    g_in_combat = false
    fire("PLAYER_REGEN_ENABLED")
    check(g_set_button._enabled, "Set re-enabled after combat")
    check(status and status._text == "", "leaving combat clears the combat warning")
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
    -- The name starts 16px later (after the favorite toggle) and still ends
    -- 10px short of the gauge.
    check(name_text and name_text._w == expected - 16,
        "name column reaches 10px short of the gauge: "
            .. tostring(name_text and name_text._w) .. " vs " .. (expected - 16))

    local long_value = "a text value well past the old 28-character cap"
    local value_text = find_widget(function(w)
        return w._kind == "FontString" and w._text == long_value
            and w._parent._kind == "Button"
    end)
    check(value_text ~= nil, "unchanged row shows a long value in full")
    check(value_text and value_text._w == expected,
        "value column runs from the right edge to 10px short of the gauge: "
            .. tostring(value_text and value_text._w))

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

    -- A value below an open minimum sits 20% into the track, clear of the
    -- slant, even for a -1 sentinel with a wide range.
    CVarBrowserDB.observed.graphicsQuality = { max = 50 }
    g_by_name.graphicsQuality.value = "-1"
    slash("refresh")
    slash("graphicsQuality")
    local cursor_x = nil
    for _, widget in ipairs(g_widgets) do
        if widget._kind == "FontString" and widget._text == "/" and widget._shown then
            for _, sibling in ipairs(widget._parent._regions) do
                if sibling.mark_width == 2 and sibling.mark_height == 8
                    and sibling._shown then
                    local _, _, _, x = sibling:GetPoint(1)
                    cursor_x = x
                end
            end
        end
    end
    check(cursor_x and math.abs(cursor_x - 17) <= 1,
        "a negative value with an open minimum sits inside the track: "
            .. tostring(cursor_x))
    g_by_name.graphicsQuality.value = "9"
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
        return w._kind == "FontString"
            and w._text == "Press Ctrl+C to copy the name of autoLootDefault"
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

    -- A Copy menu row opens the copy box for the selected CVar.
    fire_script(g_frame.copy_button, "OnClick")
    g_last_focus = nil
    fire_script(g_frame.copy_rows[4], "OnClick")
    check(g_last_focus ~= nil and g_last_focus._text == "autoLootDefault"
        and not g_frame.copy_popup._shown,
        "the Copy name menu row copies the selected name and closes the menu")
    fire_script(g_last_focus, "OnEscapePressed")
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

-- Change log -----------------------------------------------------------------

do
    -- The set, undo, redo, and reset above each logged one change.
    local log = CVarBrowserDB.log
    local actions = {}
    for _, change in ipairs(log) do
        actions[#actions + 1] = change.action
    end
    check(table.concat(actions, ",") == "set,undo,redo,reset",
        "set, undo, redo, and reset are logged in order: " .. table.concat(actions, ","))
    check(log[1] and log[1].name == "cameraDistanceMaxZoomFactor"
        and log[1].old == "1.9" and log[1].new == "2.6"
        and log[1].time == 1763467200,
        "a log entry keeps the name, old and new values, and time")

    g_chat = {}
    slash("log")
    check(chat_has("4 of 4 logged changes"), "/cvars log lists every change")
    check(chat_has("set cameraDistanceMaxZoomFactor: 1.9 %-> 2.6"),
        "/cvars log prints the action, name, and both values")
    g_chat = {}
    slash("log 1")
    check(chat_has("1 of 4 logged changes"), "/cvars log <count> limits the list")
    g_chat = {}
    slash("log CAMERADISTANCEMAXZOOMFACTOR")
    check(chat_has("4 of 4 logged changes"), "/cvars log <name> matches any case")

    -- The log keeps only the newest 200 entries.
    for index = #log + 1, 200 do
        log[index] = { name = "old", action = "set", old = "0", new = "1", time = 0 }
    end
    slash("extra7")
    g_last_focus:SetText("8")
    fire_script(g_last_focus, "OnEnterPressed")
    check(#log == 200 and log[200].name == "extra7" and log[1].action == "undo",
        "a full log drops its oldest entry")

    g_chat = {}
    slash("clearlog")
    check(#CVarBrowserDB.log == 0 and chat_has("cleared 200 logged changes"),
        "/cvars clearlog empties the log")
end

-- value: filter --------------------------------------------------------------

do
    -- extra7 is now 8, so exact 8 matches extra7 and extra8.
    slash("value:=8")
    check(g_count_text._text:match("^2 / 47") ~= nil,
        "value:=8 matches values equal to 8: " .. g_count_text._text)
    -- Substring 5 matches extra5, 15, 25, 35, and the bitfield shown as hex 35.
    slash("value:5")
    check(g_count_text._text:match("^5 / 47") ~= nil,
        "value:5 matches values containing 5, bitfields as hex: " .. g_count_text._text)
    slash("extra")
end

-- Favorites ------------------------------------------------------------------

do
    slash("fav extra30")
    check(CVarBrowserDB.favorites.extra30 == true, "/cvars fav <name> saves a favorite")
    slash("extra")
    check(selected_name() == "extra30", "a favorite pins to the top of the list")
    slash("sort name desc")
    slash("extra")
    check(selected_name() == "extra30", "a favorite stays on top in descending order")
    slash("sort name asc")
    g_chat = {}
    slash("sort")
    check(chat_has("sort must be name"), "bare /cvars sort reports an error in chat")
    local search_box = find_widget(function(w)
        return w._kind == "EditBox" and w._scripts.OnKeyDown ~= nil
    end)
    check(search_box._text ~= "sort", "bare /cvars sort does not search for sort")
    g_chat = {}
    slash("sort name asc extra")
    check(chat_has("sort direction must be asc or desc"),
        "extra words after a valid sort key report a bad direction")
    g_chat = {}
    slash("sort type")
    check(chat_has("sorted by type asc"), "/cvars sort reports in chat")
    -- Chat lines are lowercase fragments after the addon prefix.
    slash("regex on")
    slash("regex off")
    local sentence_case = false
    for _, message in ipairs(g_chat) do
        if message:match("|r %u") then
            sentence_case = true
        end
    end
    check(not sentence_case, "sort and regex chat lines start lowercase")
    slash("sort name asc")
    g_chat = {}
    slash("copy name noSuchCVar")
    check(chat_has("unknown CVar nosuchcvar"), "/cvars copy names an unknown CVar")
    slash("has:fav")
    check(g_count_text._text:match("^1 / 47") ~= nil, "has:fav keeps only favorites")

    slash("fav extra30")
    check(CVarBrowserDB.favorites.extra30 == nil, "/cvars fav toggles a favorite off")
    slash("extra")
    check(selected_name() == "extra1", "an unpinned CVar returns to its sorted place")
end

-- Favorite toggle and row tooltip --------------------------------------------

do
    local function row_for(name)
        return find_widget(function(w)
            return w.favorite ~= nil and w.entry ~= nil and w.entry.name == name
        end)
    end
    local function shown_texts(panel)
        local texts = {}
        for _, region in ipairs(panel._regions) do
            if region._kind == "FontString" and region._shown then
                texts[#texts + 1] = region._text
            end
        end
        return table.concat(texts, "|")
    end
    local timers = {}
    for _, widget in ipairs(g_widgets) do
        if widget._kind == "Frame" and widget._parent == g_frame
            and widget._scripts.OnUpdate then
            timers[#timers + 1] = widget
        end
    end
    check(#timers == 1, "one tooltip timer frame exists: " .. #timers)
    local timer = timers[1]
    local panel = g_frame.tooltip

    slash("extra")
    -- extra15 sits far enough below the selected extra1 that a stray select
    -- on its pooled row (which shows extra14 after the pin) is caught.
    local row = row_for("extra15")
    check(row ~= nil, "rows have a favorite toggle")
    check(row and not row.favorite.mark._shown,
        "a plain row hides its favorite mark")
    fire_script(row.favorite, "OnClick")
    check(CVarBrowserDB.favorites.extra15 == true, "clicking the toggle saves a favorite")
    check(find_widget(function(w)
        return w._kind == "FontString" and w._text == "Added extra15 to favorites"
    end) ~= nil, "clicking the toggle reports it in the status line")
    check(selected_name() == "extra1", "clicking the toggle does not select the row")
    row = row_for("extra15")
    local mark = row and row.favorite.mark
    check(mark and mark._shown and mark.interior[1]._shown
        and mark.outline[1]._color[1] == 0.929412,
        "a favorite shows a filled diamond in the text color")
    row.favorite._mouse_over = true
    fire_script(row.favorite, "OnEnter")
    check(mark.outline[1]._color[1] == 0.717647, "the toggle under the pointer turns accent")
    row.favorite._mouse_over = false
    fire_script(row.favorite, "OnLeave")
    fire_script(row.favorite, "OnClick")
    check(CVarBrowserDB.favorites.extra15 == nil, "a second click removes the favorite")
    g_frame.hide_tooltip()

    row = row_for("extra20")
    row._mouse_over = true
    fire_script(row, "OnEnter")
    check(not panel._shown, "the tooltip waits before it shows")
    timer._scripts.OnUpdate(timer, 0.3)
    check(not panel._shown, "the tooltip is still hidden after 0.3s")
    timer._scripts.OnUpdate(timer, 0.3)
    check(panel._shown, "the tooltip shows after 0.5s")
    check(shown_texts(panel) == "extra20|Value: 20|Default: 0|Range [0, 100]",
        "the tooltip lists name, value, default, and help: " .. shown_texts(panel))
    local point, anchor, relative_point, x, y = panel:GetPoint(1)
    check(point == "TOPLEFT" and anchor == row and relative_point == "BOTTOMLEFT"
        and x == 14 and y == -4, "the tooltip hangs below the row, in line with the name")

    -- Near the window bottom the tooltip flips above the row, unless that
    -- would come within 8px of the window top too.
    local function reshow()
        g_frame.hide_tooltip()
        fire_script(row, "OnEnter")
        timer._scripts.OnUpdate(timer, 0.6)
        local anchor_point = panel:GetPoint(1)
        return anchor_point
    end
    local frame_bottom = g_frame:GetBottom()
    row.GetBottom = function() return frame_bottom + 10 end
    row.GetTop = function() return frame_bottom + 32 end
    check(reshow() == "BOTTOMLEFT", "near the window bottom the tooltip flips above the row")
    g_frame.GetTop = function() return frame_bottom + 60 end
    check(reshow() == "TOPLEFT", "the tooltip stays below when above would reach the window top")
    g_frame.GetTop, row.GetBottom, row.GetTop = nil, nil, nil

    row._mouse_over = false
    fire_script(row, "OnLeave")
    check(not panel._shown, "leaving the row hides the tooltip")
    local next_row = row_for("extra21")
    next_row._mouse_over = true
    fire_script(next_row, "OnEnter")
    check(panel._shown and shown_texts(panel):match("^extra21|") ~= nil,
        "the next row shows at once right after a leave")

    next_row._mouse_over = false
    fire_script(next_row, "OnLeave")
    timer._scripts.OnUpdate(timer, 0.2)
    next_row._mouse_over = true
    next_row.favorite._mouse_over = true
    fire_script(next_row.favorite, "OnEnter")
    check(not panel._shown, "after the grace period the next row waits again")
    timer._scripts.OnUpdate(timer, 0.5)
    check(shown_texts(panel) == "Add to favorites",
        "the toggle's tooltip offers to add a favorite: " .. shown_texts(panel))

    local scroll_frame = find_widget(function(w)
        return w._kind == "ScrollFrame" and w._parent == g_frame
    end)
    scroll_frame._mouse_over = true
    fire_script(scroll_frame, "OnVerticalScroll", 0)
    check(not panel._shown, "scrolling hides the tooltip")
    scroll_frame._mouse_over = false
    next_row._mouse_over = false
    next_row.favorite._mouse_over = false
    g_frame.hide_tooltip()

    -- Control tooltips share the panel and the delay.
    local chip = g_frame.filter_chip
    chip._mouse_over = true
    fire_script(chip, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    check(not panel._shown, "the Filters chip has no tooltip with no filters on")
    fire_script(chip, "OnLeave")
    g_frame.hide_tooltip()
    g_frame.filters.scope = "account"
    g_frame.filters.has.changed = true
    g_frame.filters.has.range = true
    g_frame.update_filter_chip()
    fire_script(chip, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    check(shown_texts(panel) == "Active filters|scope:account, has:range, has:changed",
        "the Filters chip tooltip lists facets in menu order: " .. shown_texts(panel))
    point, anchor, relative_point, x, y = panel:GetPoint(1)
    check(point == "TOPLEFT" and anchor == chip and relative_point == "BOTTOMLEFT"
        and x == 0 and y == -4, "a control tooltip hangs 4px below the control")
    fire_script(chip, "OnMouseDown", "LeftButton")
    check(not panel._shown, "a mouse down on a control hides its tooltip")
    chip._mouse_over = false
    fire_script(chip, "OnLeave")
    g_frame.filters.scope = ""
    g_frame.filters.has = {}
    g_frame.update_filter_chip()
    g_frame.hide_tooltip()

    local saved_undo, saved_redo = g_frame.undo_stack, g_frame.redo_stack
    g_frame.undo_stack = { { name = "extra5", previous = "5" } }
    g_frame.redo_stack = {}
    g_frame.update_history_controls()
    g_frame.undo_button._mouse_over = true
    fire_script(g_frame.undo_button, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    check(shown_texts(panel) == "Undo extra5|Ctrl+Z",
        "the Undo tooltip names the CVar and the shortcut: " .. shown_texts(panel))
    g_frame.undo_button._mouse_over = false
    fire_script(g_frame.undo_button, "OnLeave")
    g_frame.redo_button._mouse_over = true
    fire_script(g_frame.redo_button, "OnEnter")
    check(shown_texts(panel) == "Nothing to redo|Ctrl+Y or Ctrl+Shift+Z",
        "moving to disabled Redo swaps the tooltip at once: " .. shown_texts(panel))
    g_frame.redo_button._mouse_over = false
    fire_script(g_frame.redo_button, "OnLeave")
    g_frame.undo_stack, g_frame.redo_stack = saved_undo, saved_redo
    g_frame.update_history_controls()
    g_frame.hide_tooltip()
end

-- Keyboard navigation --------------------------------------------------------

do
    local search_box = find_widget(function(w)
        return w._kind == "EditBox" and w._scripts.OnKeyDown ~= nil
    end)
    local scroll_frame = find_widget(function(w)
        return w._kind == "ScrollFrame" and w._parent == g_frame
    end)

    -- A 110px list shows 5 rows, so a page is 5 rows.
    scroll_frame._h = 110
    slash("extra")
    fire_script(search_box, "OnKeyDown", "PAGEDOWN")
    check(selected_name() == "extra14", "PageDown in the search box moves one page")
    fire_script(search_box, "OnKeyDown", "END")
    check(selected_name() == "extra14", "End in the search box stays with the caret")

    g_frame._mouse_over = false
    fire_script(g_frame, "OnKeyDown", "END")
    check(selected_name() == "extra14" and g_frame._propagate == true,
        "list keys pass through when the cursor is outside the window")
    g_frame._mouse_over = true
    fire_script(g_frame, "OnKeyDown", "END")
    check(selected_name() == "extra9" and g_frame._propagate == false,
        "End over the window selects the last row and keeps the key")
    fire_script(g_frame, "OnKeyUp", "END")
    check(g_frame._propagate == true, "key up passes keys through again")
    -- Names sort as text, so five rows above extra9 is extra40.
    fire_script(g_frame, "OnKeyDown", "PAGEUP")
    check(selected_name() == "extra40", "PageUp over the window moves one page")
    fire_script(g_frame, "OnKeyDown", "HOME")
    check(selected_name() == "extra1", "Home over the window selects the first row")
    fire_script(g_frame, "OnKeyDown", "W")
    check(g_frame._propagate == true, "other keys pass through to the game")

    g_in_combat = true
    fire_script(g_frame, "OnKeyDown", "END")
    check(selected_name() == "extra1" and g_frame._propagate == true,
        "list keys do nothing in combat")
    g_in_combat = false

    fire_script(g_frame, "OnKeyDown", "ESCAPE")
    check(search_box._text == "" and g_frame._propagate == false,
        "Escape clears the search before it closes the window")
    fire_script(g_frame, "OnKeyUp", "ESCAPE")
    fire_script(g_frame, "OnKeyDown", "ESCAPE")
    check(g_frame._propagate == true, "Escape with an empty search passes through")
    fire_script(g_frame, "OnKeyUp", "ESCAPE")

    search_box:SetText("extra")
    search_box:SetFocus()
    fire_script(search_box, "OnEscapePressed")
    check(search_box._text == "" and search_box._focused,
        "the first Escape in the search box clears its text")
    fire_script(search_box, "OnEscapePressed")
    check(not search_box._focused, "the second Escape leaves the search box")

    -- Undo and redo shortcuts, only over the window.
    slash("extra3")
    g_last_focus:SetText("33")
    fire_script(g_last_focus, "OnEnterPressed")
    g_last_focus:ClearFocus()
    g_frame._mouse_over = true
    g_ctrl_down = true
    g_chat = {}
    fire_script(g_frame, "OnKeyDown", "Z")
    local call = last_set_call()
    check(call and call[1] == "extra3" and call[2] == "3" and g_frame._propagate == false,
        "Ctrl+Z over the window undoes the last set")
    check(#g_chat == 0, "an undo from the window prints nothing to chat")
    fire_script(g_frame, "OnKeyUp", "Z")
    g_shift_down = true
    fire_script(g_frame, "OnKeyDown", "Z")
    call = last_set_call()
    check(call and call[1] == "extra3" and call[2] == "33",
        "Ctrl+Shift+Z over the window redoes")
    fire_script(g_frame, "OnKeyUp", "Z")
    g_shift_down = false
    local calls_before = #g_set_calls
    fire_script(g_frame, "OnKeyDown", "Y")
    check(#g_set_calls == calls_before and g_frame._propagate == false,
        "Ctrl+Y with nothing to redo does nothing and keeps the key")
    fire_script(g_frame, "OnKeyUp", "Y")
    g_ctrl_down = false
    fire_script(g_frame, "OnKeyDown", "Z")
    check(#g_set_calls == calls_before and g_frame._propagate == true,
        "Z without Ctrl passes through")
    fire_script(g_frame, "OnKeyUp", "Z")

    g_frame._mouse_over = false
    scroll_frame._h = 340
    slash("extra")
end

-- Scroll redraw, thumb drags, and tooltip gates -----------------------------

do
    local scroll_frame = find_widget(function(w)
        return w._kind == "ScrollFrame" and w._parent == g_frame
    end)
    local first_row = find_widget(function(w)
        return w.favorite ~= nil and w._parent == scroll_frame._scroll_child
    end)
    local list_thumb = find_widget(function(w)
        return w._kind == "Frame" and w._scripts.OnMouseDown ~= nil
            and w ~= g_frame.filter_scroll_thumb
            and w._parent and w._parent._parent == g_frame
    end)
    local timer = find_widget(function(w)
        return w._kind == "Frame" and w._parent == g_frame
            and w._scripts.OnUpdate ~= nil
    end)
    local panel = g_frame.tooltip
    CVarBrowserDB.smooth_scroll = false
    scroll_frame._h = 110
    slash("extra")

    -- Rows only re-bind when the top row changes.
    scroll_frame:SetVerticalScroll(10)
    fire_script(scroll_frame, "OnVerticalScroll", 10)
    check(first_row.entry and first_row.entry.name == "extra1",
        "scrolling less than a row keeps the top row")
    scroll_frame:SetVerticalScroll(22)
    fire_script(scroll_frame, "OnVerticalScroll", 22)
    check(first_row.entry and first_row.entry.name == "extra10",
        "scrolling a full row moves the top row to the next entry")

    -- Releasing the list thumb settles on a whole row, and a release outside
    -- the thumb still ends the drag.
    check(list_thumb ~= nil, "the list scrollbar thumb exists")
    scroll_frame:SetVerticalScroll(0)
    -- A 110px bar and a 32px thumb make a 3px drag land between rows.
    list_thumb._parent._h = 110
    g_mouse_down = true
    g_cursor_y = 360
    fire_script(list_thumb, "OnMouseDown", "LeftButton")
    check(list_thumb.drag ~= nil, "pressing the list thumb starts a drag")
    g_cursor_y = 357
    list_thumb._scripts.OnUpdate(list_thumb, 1 / 60)
    g_mouse_down = false
    list_thumb._scripts.OnUpdate(list_thumb, 1 / 60)
    check(list_thumb._scripts.OnUpdate == nil and list_thumb.drag == nil,
        "a release outside the list thumb ends the drag")
    -- The 3px drag lands near 41.6. The settle moves it to row 2 (44),
    -- give or take the pixel rounding of the stub's 1.875 px per unit.
    check(math.abs(scroll_frame._scroll - 44) < 1 / PX,
        "the list settles on a whole row after a drag: " .. scroll_frame._scroll)
    g_mouse_down = true
    g_cursor_y = 360

    -- Hiding the window mid-drag ends the drag, since OnUpdate stops.
    fire_script(list_thumb, "OnMouseDown", "LeftButton")
    fire_script(g_frame, "OnHide")
    check(list_thumb.drag == nil and list_thumb._scripts.OnUpdate == nil,
        "hiding the window ends a thumb drag")

    -- No row tooltip during a thumb drag, and no control tooltip with a menu
    -- open.
    first_row._mouse_over = true
    fire_script(list_thumb, "OnMouseDown", "LeftButton")
    fire_script(first_row, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    check(not panel._shown, "rows show no tooltip while the thumb is dragged")
    fire_script(list_thumb, "OnMouseUp", "LeftButton")
    first_row._mouse_over = false
    fire_script(first_row, "OnLeave")
    g_frame.hide_tooltip()
    fire_script(g_frame.sort_chip, "OnClick")
    g_frame.regex_chip._mouse_over = true
    fire_script(g_frame.regex_chip, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    check(not panel._shown, "controls show no tooltip while a menu is open")
    g_frame.close_menus()

    -- The Size popup closes on an outside click or when another menu opens,
    -- and no tooltip shows while it or the copy box is open.
    local size_popup = find_widget(function(w)
        return w.option ~= nil
    end)._parent
    local size_button = find_widget(function(w)
        return w.label and w.label._text and w.label._text:match("^Size: ") ~= nil
    end)
    fire_script(size_button, "OnClick")
    check(size_popup._shown and g_frame.menu_catcher._shown,
        "the Size popup opens with the outside-click catcher")
    first_row._mouse_over = true
    fire_script(first_row, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    check(not panel._shown, "rows show no tooltip while the Size popup is open")
    first_row._mouse_over = false
    fire_script(first_row, "OnLeave")
    fire_script(g_frame.menu_catcher, "OnMouseDown", "LeftButton")
    check(not size_popup._shown, "an outside click closes the Size popup")
    fire_script(size_button, "OnClick")
    fire_script(g_frame.sort_chip, "OnClick")
    check(not size_popup._shown and g_frame.sort_popup._shown,
        "opening another menu closes the Size popup")
    g_frame.close_menus()
    slash("copy name")
    first_row._mouse_over = true
    fire_script(first_row, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    check(not panel._shown, "rows show no tooltip while the copy box is open")
    first_row._mouse_over = false
    fire_script(first_row, "OnLeave")
    fire_script(g_frame.copy_box, "OnEscapePressed")
    g_frame.hide_tooltip()

    -- The title names the pattern search state, off then on.
    local function regex_title()
        fire_script(g_frame.regex_chip, "OnEnter")
        timer._scripts.OnUpdate(timer, 0.6)
        local title = nil
        for _, region in ipairs(panel._regions) do
            if region._kind == "FontString" and region._shown and not title then
                title = region._text
            end
        end
        fire_script(g_frame.regex_chip, "OnLeave")
        g_frame.hide_tooltip()
        return title
    end
    check(regex_title() == "Pattern search off", "the regex chip tooltip says off")
    slash("regex on")
    check(regex_title() == "Pattern search on", "the regex chip tooltip says on")
    slash("regex off")
    -- Turning the chip off under the pointer keeps its hover border.
    fire_script(g_frame.regex_chip, "OnClick")
    fire_script(g_frame.regex_chip, "OnClick")
    check(not g_frame.regex_enabled
        and g_frame.regex_chip.borders[1]._color[1] == 0.717647,
        "turning the regex chip off under the pointer keeps its hover border")
    slash("extra")
    g_frame.regex_chip._mouse_over = false
    fire_script(g_frame.regex_chip, "OnLeave")
    g_frame.hide_tooltip()

    -- A mouse down on disabled Redo leaves its tooltip up, and any undo hides
    -- the stale history tooltip.
    g_frame.redo_stack = {}
    g_frame.update_history_controls()
    g_frame.redo_button._mouse_over = true
    fire_script(g_frame.redo_button, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    fire_script(g_frame.redo_button, "OnMouseDown", "LeftButton")
    check(panel._shown, "a mouse down on disabled Redo keeps its tooltip")
    slash("extra4")
    fire_script(g_frame.redo_button, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    check(panel._shown, "the Redo tooltip is up before the set")
    g_last_focus:SetText("44")
    fire_script(g_last_focus, "OnEnterPressed")
    g_last_focus:ClearFocus()
    check(not panel._shown, "a set hides the history tooltip")
    fire_script(g_frame.redo_button, "OnEnter")
    timer._scripts.OnUpdate(timer, 0.6)
    slash("undo")
    check(not panel._shown, "an undo hides the history tooltip")
    g_frame.redo_button._mouse_over = false
    fire_script(g_frame.redo_button, "OnLeave")
    g_frame.hide_tooltip()

    -- Ctrl+Z with the cursor outside the window reaches the game.
    local calls_before = #g_set_calls
    g_frame._mouse_over = false
    g_ctrl_down = true
    fire_script(g_frame, "OnKeyDown", "Z")
    check(#g_set_calls == calls_before and g_frame._propagate == true,
        "Ctrl+Z outside the window passes through")
    g_ctrl_down = false

    -- Toggling a favorite under the pointer keeps the accent but fills the
    -- diamond.
    slash("extra")
    local mark = first_row.favorite.mark
    first_row.favorite._mouse_over = true
    fire_script(first_row.favorite, "OnEnter")
    local filled_before = mark.interior[1]._shown
    fire_script(first_row.favorite, "OnClick")
    local entry = first_row.entry
    check(entry and entry.favorite and mark.interior[1]._shown and not filled_before,
        "toggling a favorite under the pointer fills its diamond")
    fire_script(first_row.favorite, "OnClick")
    first_row.favorite._mouse_over = false
    fire_script(first_row.favorite, "OnLeave")
    g_frame.hide_tooltip()

    scroll_frame._h = 340
    CVarBrowserDB.smooth_scroll = true
    slash("extra")
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

    -- Snap corrections under 0.01px are noise and leave the anchor alone.
    local probe = g_frame:CreateTexture()
    probe:SetPoint("TOPLEFT", g_frame, "TOPLEFT", 10, -10)
    probe.GetLeft = function() return 100 / PX + 0.001 / PX end
    probe.GetTop = function() return 500 / PX - 0.001 / PX end
    g_frame.snap_box(probe)
    local _, _, _, probe_x, probe_y = probe:GetPoint(1)
    check(probe_x == 10 and probe_y == -10, "a sub-0.01px snap correction is ignored")
    probe.GetLeft = function() return 100 / PX + 0.3 / PX end
    g_frame.snap_box(probe)
    _, _, _, probe_x = probe:GetPoint(1)
    check(math.abs((probe_x - 10) * PX + 0.3) < 1e-6, "a 0.3px snap correction applies")
    probe:Hide()

    -- The Changed only tick snaps the first time it shows.
    local changed_button = button_with_label("Changed only")
    local tick = find_widget(function(w)
        return w._kind == "FontString" and w._text == "✓"
            and w._parent._parent == changed_button
    end)
    check(tick and tick.text_snap == nil, "the Changed only tick starts unsnapped")
    fire_script(changed_button, "OnClick", "LeftButton")
    check(tick and tick._shown and tick.text_snap ~= nil,
        "the Changed only tick snaps when first checked")
    fire_script(changed_button, "OnClick", "LeftButton")
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

-- Repository build -----------------------------------------------------------

do
    g_metadata = { Version = "dev" }
    local ok, err = load_addon()
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
    for _, path in ipairs(ADDON_FILES) do
        local listing = io.popen((luac or "luac") .. ' -l -l -p "' .. path .. '" 2>&1')
        local slots = nil
        if listing then
            slots = tonumber(listing:read("*a"):match("main <.-\n[^\n]-(%d+) slots"))
            listing:close()
        end
        if slots then
            check(
                slots < 190,
                path .. " main chunk uses " .. slots .. " of 200 register slots"
            )
        elseif luac then
            check(false, "register check: could not run " .. luac .. " on " .. path)
        else
            io.stderr:write("note: luac not available; skipped register check\n")
            break
        end
    end
end

print(string.format("%d checks, %d failed", g_checks, g_failures))
os.exit(g_failures == 0 and 0 or 1)
