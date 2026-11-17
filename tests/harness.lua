-- Headless WoW API stub harness for CVarBrowser.lua.
--
-- Run from the addon folder:  lua tests/harness.lua
-- Exits non-zero on any failed check. Covers load, ADDON_LOADED, scan,
-- set/clamp/reset, undo/redo, read-only selection, slash commands, copy,
-- CVAR_UPDATE casing, pattern search, smooth scrolling, the pixel-locked
-- window drag, and main-chunk register headroom. Visual pixel checks still
-- need an in-game /reload and /cvars.

local script_dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local addon_path = script_dir .. "/../CVarBrowser.lua"

-- Physical px per frame unit the stubs produce: measure_px_per_unit reads
-- GetScaledRect width (== GetWidth here) * physical height / 768 / 100.
local PHYSICAL_WIDTH, PHYSICAL_HEIGHT = 2560, 1440
local PX = PHYSICAL_HEIGHT / 768

local failures = 0
local checks = 0
local function check(condition, label)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        io.stderr:write("FAIL: ", label, "\n")
    end
end

local function on_pixel_grid(value)
    local px = value * PX
    return math.abs(px - math.floor(px + 0.5)) < 1e-6
end

-- Widget stubs ----------------------------------------------------------------

local widgets = {}
local chat = {}
local set_calls = {}
local last_focus

local methods = {}
local widget_mt = {
    __index = function(_, key)
        local method = methods[key]
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
    }, widget_mt)
    widgets[#widgets + 1] = widget
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

function methods:GetObjectType() return self._kind end
function methods:IsObjectType(kind) return self._kind == kind end
function methods:CreateTexture() return new_widget("Texture", nil, self) end
function methods:CreateFontString() return new_widget("FontString", nil, self) end
function methods:CreateLine() return new_widget("Line", nil, self) end
function methods:GetChildren() return unpack(self._children) end
function methods:GetRegions() return unpack(self._regions) end
function methods:GetParent() return self._parent end
function methods:SetScript(name, handler) self._scripts[name] = handler end
function methods:GetScript(name) return self._scripts[name] end
function methods:HookScript(name, handler)
    local previous = self._scripts[name]
    self._scripts[name] = function(...)
        if previous then
            previous(...)
        end
        return handler(...)
    end
end
function methods:Show()
    local was_shown = self._shown
    self._shown = true
    if not was_shown then
        fire_script(self, "OnShow")
    end
end
function methods:Hide() self._shown = false end
function methods:IsShown() return self._shown end
function methods:IsVisible() return self._shown end
function methods:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end
function methods:Enable() self._enabled = true end
function methods:Disable() self._enabled = false end
function methods:SetEnabled(enabled) self._enabled = enabled and true or false end
function methods:IsEnabled() return self._enabled end
function methods:SetSize(w, h) self._w, self._h = w, h end
function methods:SetWidth(w) self._w = w end
function methods:SetHeight(h) self._h = h end
function methods:GetWidth() return self._w end
function methods:GetHeight() return self._h end
function methods:GetSize() return self._w, self._h end
function methods:GetLeft() return 100.37 end
function methods:GetRight() return 100.37 + self._w end
function methods:GetTop() return 500.61 end
function methods:GetBottom() return 500.61 - self._h end
function methods:GetCenter() return 300.2, 400.7 end
function methods:GetRect() return 100.37, 500.61 - self._h, self._w, self._h end
function methods:GetScaledRect() return self:GetRect() end
function methods:GetEffectiveScale() return 0.7111 end
function methods:GetScale() return 1 end
function methods:SetPoint(point, relative_to, relative_point, x, y)
    for index, existing in ipairs(self._points) do
        if existing[1] == point then
            self._points[index] = { point, relative_to, relative_point, x, y }
            return
        end
    end
    self._points[#self._points + 1] = { point, relative_to, relative_point, x, y }
end
function methods:ClearAllPoints() self._points = {} end
function methods:GetNumPoints() return #self._points end
function methods:GetPoint(index)
    local p = self._points[index or 1]
    if p then
        return p[1], p[2], p[3], p[4], p[5]
    end
end
function methods:SetText(text)
    text = text == nil and "" or tostring(text)
    local changed = text ~= self._text
    self._text = text
    if self._kind == "EditBox" and changed then
        fire_script(self, "OnTextChanged", false)
    end
end
function methods:GetText() return self._text end
function methods:GetStringWidth() return #self._text * 6.3 end
function methods:GetUnboundedStringWidth() return #self._text * 6.3 end
function methods:GetStringHeight() return 13 end
function methods:GetNumLines() return 1 end
function methods:GetFont() return "font", 12, "" end
function methods:GetFrameLevel() return self._level end
function methods:SetFrameLevel(level) self._level = level end
function methods:SetFocus() last_focus = self; self._focused = true end
function methods:ClearFocus()
    local had_focus = self._focused
    self._focused = false
    if had_focus then
        fire_script(self, "OnEditFocusLost")
    end
end
function methods:HasFocus() return self._focused == true end
function methods:HighlightText() self._highlighted = true end
function methods:IsMouseOver() return false end
function methods:SetScrollChild(child) self._scroll_child = child end
function methods:GetVerticalScroll() return self._scroll end
function methods:GetVerticalScrollRange()
    local child = self._scroll_child
    return child and math.max(0, child._h - self._h) or 0
end
function methods:SetVerticalScroll(value)
    self._scroll = value
    fire_script(self, "OnVerticalScroll", value)
end

-- WoW globals -----------------------------------------------------------------

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
    AddMessage = function(_, message) chat[#chat + 1] = message end,
}
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.STANDARD_TEXT_FONT = "font"
local in_combat = false
_G.InCombatLockdown = function() return in_combat end
local cursor_x, cursor_y = 640, 360
_G.GetCursorPosition = function() return cursor_x, cursor_y end
_G.GetPhysicalScreenSize = function() return PHYSICAL_WIDTH, PHYSICAL_HEIGHT end
_G.IsMouseButtonDown = function() return true end
_G.C_Timer = { After = function() end }
_G.Enum = { ConsoleCommandType = { Cvar = 0, Command = 1 } }
_G.unpack = _G.unpack or table.unpack

-- CVar store. GetCVarInfo follows the client verified in game: value,
-- default, account, character, locked, secure, read-only.
local cvars = {
    { name = "cameraDistanceMaxZoomFactor", value = "1.9", default = "1.9",
      help = "Max camera zoom (1-2.6)", max = 2.6 },
    { name = "graphicsQuality", value = "7", default = "5", help = "Graphics quality" },
    { name = "autoLootDefault", value = "1", default = "0", help = "Auto loot (0/1)" },
    { name = "closedInfoFrames", value = "5", default = "0", help = "Bitfield" },
    { name = "readOnlyThing", value = "3", default = "3", help = "Read only", readonly = true },
    { name = "secureThing", value = "1", default = "1", help = "Secure", secure = true },
}
for index = 1, 40 do
    cvars[#cvars + 1] = {
        name = "extra" .. index,
        value = tostring(index),
        default = "0",
        help = "Range 0-100",
    }
end
local by_name = {}
for _, cvar in ipairs(cvars) do
    by_name[cvar.name] = cvar
end

_G.C_Console = {
    GetAllCommands = function()
        local out = {}
        for index, cvar in ipairs(cvars) do
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
    GetCVar = function(name) return by_name[name] and by_name[name].value end,
    GetCVarInfo = function(name)
        local cvar = by_name[name]
        if cvar then
            return cvar.value, cvar.default, false, true, false,
                cvar.secure == true, cvar.readonly == true
        end
    end,
    GetCVarDefault = function(name) return by_name[name] and by_name[name].default end,
    SetCVar = function(name, value)
        set_calls[#set_calls + 1] = { name, tostring(value) }
        local cvar = by_name[name]
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

-- Helpers -------------------------------------------------------------------

local function find_widget(predicate)
    for _, widget in ipairs(widgets) do
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
    for _, message in ipairs(chat) do
        if message:find(pattern) then
            return true
        end
    end
    return false
end

local function last_set_call()
    return set_calls[#set_calls]
end

local function slash(command)
    local ok, err = pcall(SlashCmdList.CVARBROWSER, command)
    check(ok, "slash '" .. command .. "' raised: " .. tostring(err))
end

-- Load --------------------------------------------------------------------------

local chunk = assert(loadfile(addon_path))
local load_ok, load_err = pcall(chunk, "CVarBrowser", {})
check(load_ok, "addon load: " .. tostring(load_err))
if not load_ok then
    io.stderr:write(failures, " failure(s)\n")
    os.exit(1)
end

local frame = _G.CVarBrowserFrame
check(frame ~= nil, "CVarBrowserFrame global exists")
check(type(SlashCmdList.CVARBROWSER) == "function", "slash handler registered")

local function fire(event, ...)
    local ok, err = pcall(frame._scripts.OnEvent, frame, event, ...)
    check(ok, "event " .. event .. " raised: " .. tostring(err))
end

fire("ADDON_LOADED", "CVarBrowser")
check(type(CVarBrowserDB) == "table", "ADDON_LOADED creates saved variables")
check(CVarBrowserDB.smooth_scroll == true, "smooth scrolling defaults on")
fire("PLAYER_ENTERING_WORLD")

-- Scan ----------------------------------------------------------------------

slash("")
check(frame:IsShown(), "bare /cvars opens the browser")
local count_text = find_widget(function(w)
    return w._kind == "FontString" and w._text:match("^%d+ / %d+ CVars")
end)
check(count_text ~= nil, "count text rendered")
check(count_text and count_text._text:match("^46 / 46 CVars") ~= nil,
    "scan lists every CVar and skips commands: " .. tostring(count_text and count_text._text))

-- Set / clamp / undo / redo / reset ------------------------------------------

local set_button = button_with_label("Set")
local reset_button = button_with_label("Reset to default")
check(set_button ~= nil and reset_button ~= nil, "Set and Reset buttons exist")

last_focus = nil
slash("cameraDistanceMaxZoomFactor")
local detail_edit = last_focus
check(detail_edit ~= nil and detail_edit._kind == "EditBox",
    "/cvars <name> focuses the value field")
check(set_button._enabled, "Set enabled for a writable CVar")

detail_edit:SetText("5")
fire_script(detail_edit, "OnEnterPressed")
local call = last_set_call()
check(call and call[1] == "cameraDistanceMaxZoomFactor" and call[2] == "5",
    "Enter sends SetCVar with the typed value")
check(by_name.cameraDistanceMaxZoomFactor.value == "2.6", "stub clamped to 2.6")
local observed = CVarBrowserDB.observed.cameraDistanceMaxZoomFactor
check(type(observed) == "table", "clamp is recorded as an observed bound")

chat = {}
slash("Ranges cameraDistanceMaxZoomFactor")
check(chat_has("1 observed range"), "/cvars ranges <name> lists that CVar (any case)")

slash("undo")
call = last_set_call()
check(call and call[2] == "1.9", "undo restores the previous value")
slash("redo")
call = last_set_call()
check(call and call[2] == "2.6", "redo re-applies the clamped value")

fire_script(reset_button, "OnClick")
call = last_set_call()
check(call and call[1] == "cameraDistanceMaxZoomFactor" and call[2] == "1.9",
    "Reset sends the default value")

chat = {}
slash("ClearRange cameraDistanceMaxZoomFactor")
check(chat_has("cleared cameraDistanceMaxZoomFactor"),
    "clearrange accepts any case and echoes the stored name")

-- Read-only selection -------------------------------------------------------

last_focus = nil
slash("readOnlyThing")
check(last_focus == nil, "read-only selection does not focus the value field")
check(not set_button._enabled and not reset_button._enabled,
    "Set/Reset disabled for a read-only CVar")
local calls_before = #set_calls
fire_script(set_button, "OnClick")
check(#set_calls == calls_before, "Set does not call SetCVar for read-only")

-- Secure CVar in combat -----------------------------------------------------

in_combat = true
fire("PLAYER_REGEN_DISABLED")
slash("secureThing")
check(not set_button._enabled, "Set disabled for a secure CVar in combat")
in_combat = false
fire("PLAYER_REGEN_ENABLED")
check(set_button._enabled, "Set re-enabled after combat")

-- CVAR_UPDATE casing --------------------------------------------------------

slash("graphicsQuality")
by_name.graphicsQuality.value = "9"
fire("CVAR_UPDATE", "GRAPHICSQUALITY")
check(find_widget(function(w)
    return w._kind == "FontString" and w._text:match("^9 ")
end) ~= nil, "CVAR_UPDATE with different casing refreshes the row")

-- Copy ----------------------------------------------------------------------

slash("autoLootDefault")
last_focus = nil
slash("copy name")
check(last_focus ~= nil and last_focus._text == "autoLootDefault"
    and last_focus._highlighted, "copy shows the name highlighted in a focused box")
check(find_widget(function(w)
    return w._kind == "FontString" and w._text:match("^Press Ctrl%+C to copy name")
end) ~= nil, "copy status tells the user to press Ctrl+C")
local copy_box = last_focus
fire_script(copy_box, "OnEscapePressed")
check(not copy_box._parent._shown, "Escape closes the copy box")

-- Pattern search keeps escaped class letters --------------------------------

slash("regex on")
slash("^extra%d")
check(count_text._text:match("^40 / 46") ~= nil,
    "pattern ^extra%d matches the 40 extraN CVars: " .. count_text._text)
slash("^extra%D")
check(count_text._text:match("^0 / 46") ~= nil,
    "pattern ^extra%D (uppercase class) matches none: " .. count_text._text)
slash("regex off")
slash("extra")

-- Search Enter keeps an arrow-key selection ------------------------------------

local search_box = find_widget(function(w)
    return w._kind == "EditBox" and w._scripts.OnKeyDown ~= nil
end)
check(search_box ~= nil, "search box exists")
fire_script(search_box, "OnKeyDown", "DOWN")
fire_script(search_box, "OnKeyDown", "DOWN")
fire_script(search_box, "OnEnterPressed")
last_focus = nil
slash("copy name")
check(last_focus and last_focus._text == "extra11",
    "Enter after two DOWN presses keeps the third match selected: "
        .. tostring(last_focus and last_focus._text))
fire_script(last_focus, "OnEscapePressed")
slash("extra")

-- Smooth scrolling ----------------------------------------------------------

local scroll_frame = find_widget(function(w)
    return w._kind == "ScrollFrame" and w._parent == frame
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

-- Pixel-locked window drag --------------------------------------------------

local titlebar = find_widget(function(w)
    return w._parent == frame and w._scripts.OnDragStart ~= nil
end)
check(titlebar ~= nil, "title bar drag handler exists")
cursor_x, cursor_y = 640, 360
fire_script(titlebar, "OnDragStart")
check(frame._scripts.OnUpdate ~= nil, "drag installs an OnUpdate")
local drag_on_grid, drag_follows = true, true
local scale = frame:GetEffectiveScale()
for step = 1, 25 do
    cursor_x = 640 + step * 1.37
    cursor_y = 360 - step * 0.91
    frame._scripts.OnUpdate(frame, 1 / 60)
    local _, _, _, x, y = frame:GetPoint(1)
    if not (x and y and on_pixel_grid(x) and on_pixel_grid(y)) then
        drag_on_grid = false
    end
    -- Cursor screen units convert to frame units by the effective scale;
    -- the stub GetLeft/GetTop are fixed, so the anchor tracks the cursor
    -- delta to within half a physical pixel.
    local expected_x = 100.37 + (cursor_x - 640) / scale
    local expected_y = 500.61 + (cursor_y - 360) / scale
    if not x or math.abs(x - expected_x) > 0.5 / PX + 1e-9
        or math.abs(y - expected_y) > 0.5 / PX + 1e-9 then
        drag_follows = false
    end
end
check(drag_on_grid, "every drag position lands on a whole pixel")
check(drag_follows, "the dragged window follows the cursor in frame units")
fire_script(titlebar, "OnDragStop")
check(frame._scripts.OnUpdate == nil, "drag stop removes the OnUpdate")
check(type(CVarBrowserDB.x) == "number" and type(CVarBrowserDB.y) == "number",
    "drag stop saves the position")

-- Every remaining script handler runs without raising -------------------------

local skip = { OnUpdate = true, OnEvent = true, OnDragStart = true }
local snapshot = {}
for index, widget in ipairs(widgets) do
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

-- Main-chunk register headroom (Lua 5.1 caps active locals at 200) -----------

-- LUAC names the Lua 5.1 compiler (CI sets LUAC=luac5.1). When it is set
-- explicitly the register check is mandatory; otherwise a missing luac only
-- skips it.
local luac = os.getenv("LUAC")
local listing = io.popen((luac or "luac") .. ' -l -l -p "' .. addon_path .. '" 2>&1')
local slots
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

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
