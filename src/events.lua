-- CVar Browser. Script wiring for the window, list, keyboard, and game
-- events.

local ADDON_NAME, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local UIParent = UIParent
local C_Timer = C_Timer
local IsMouseButtonDown = IsMouseButtonDown
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local IsControlKeyDown, IsShiftKeyDown = IsControlKeyDown, IsShiftKeyDown
local IsAltKeyDown = IsAltKeyDown
local ipairs = ipairs
local type, tonumber = type, tonumber
local pcall = pcall
local floor, max = math.floor, math.max

-- Shared from earlier files --------------------------------------------------

local g_frame = ns.g_frame
local ROW_HEIGHT = ns.ROW_HEIGHT
local ROW_COUNT = ns.ROW_COUNT
local COLORS = ns.COLORS
local trim = ns.trim
local clamp = ns.clamp
local round = ns.round
local g_hairline = ns.g_hairline
local apply_range = ns.apply_range
local read_cvar_value = ns.read_cvar_value
local can_edit = ns.can_edit
local init_db = ns.init_db
local g_titlebar = ns.g_titlebar
local g_close_button = ns.g_close_button
local g_scale_button = ns.g_scale_button
local g_search_frame = ns.g_search_frame
local g_search_box = ns.g_search_box
local g_search_placeholder = ns.g_search_placeholder
local g_changed_button = ns.g_changed_button
local g_scroll_frame = ns.g_scroll_frame
local g_scroll_child = ns.g_scroll_child
local g_scrollbar = ns.g_scrollbar
local g_scrollbar_thumb = ns.g_scrollbar_thumb
local g_rows = ns.g_rows
local g_scale_rows = ns.g_scale_rows
local g_detail_edit_frame = ns.g_detail_edit_frame
local g_detail_edit = ns.g_detail_edit
local g_set_button = ns.g_set_button
local g_reset_button = ns.g_reset_button
local snap_frame_position = ns.snap_frame_position
local apply_ui_scale = ns.apply_ui_scale
local set_layout = ns.set_layout
local toggle_scale_popup = ns.toggle_scale_popup
local update_controls = ns.update_controls
local update_detail = ns.update_detail
local update_scrollbar = ns.update_scrollbar
local update_rows = ns.update_rows
local select_entry = ns.select_entry
local rebuild_view = ns.rebuild_view
local rescan = ns.rescan
local apply_value = ns.apply_value
local reset_value = ns.reset_value
local toggle_changed = ns.toggle_changed
local scroll_rows = ns.scroll_rows

local function scroll_to(value, smooth)
    g_frame.scroll_frame_to(g_scroll_frame, value, smooth)
end

-- Dragging a scrollbar thumb maps cursor travel along the bar onto the
-- scroll range, and the thumb keeps the drag in thumb.drag while it runs.
-- on_stop runs when a drag ends. The first update applies the start
-- offset, which also stops a wheel glide still in progress.
local function wire_thumb_drag(thumb, bar, scroll, on_stop)
    local function stop()
        if thumb.drag and on_stop then
            on_stop()
        end
        thumb.drag = nil
        thumb:SetScript("OnUpdate", nil)
    end

    local function follow()
        local drag = thumb.drag
        -- A release outside the thumb can skip OnMouseUp.
        if not drag or not IsMouseButtonDown("LeftButton") then
            stop()
            return
        end
        local _, cursor_y = GetCursorPosition()
        if cursor_y == drag.last_y then
            return
        end
        drag.last_y = cursor_y
        local scale = g_frame:GetEffectiveScale() or 1
        local delta = (drag.start_y - cursor_y / scale)
            / drag.max_top
            * drag.max_scroll
        g_frame.scroll_frame_to(scroll, drag.start_scroll + delta)
    end

    thumb:EnableMouse(true)
    thumb:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        local scale = g_frame:GetEffectiveScale() or 1
        local _, cursor_y = GetCursorPosition()
        thumb.drag = {
            start_y = cursor_y / scale,
            start_scroll = scroll:GetVerticalScroll() or 0,
            max_top = max(1, bar:GetHeight() - thumb:GetHeight()),
            max_scroll = scroll:GetVerticalScrollRange() or 0,
        }
        thumb:SetScript("OnUpdate", follow)
    end)

    -- Only the left button ends a drag, as on the title bar.
    thumb:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            stop()
        end
    end)
end

-- Releasing the list's thumb settles the list on a whole row.
wire_thumb_drag(g_scrollbar_thumb, g_scrollbar, g_scroll_frame, function()
    local current = g_scroll_frame:GetVerticalScroll() or 0
    scroll_to(round(current / ROW_HEIGHT) * ROW_HEIGHT, true)
end)

wire_thumb_drag(
    g_frame.filter_scroll_thumb,
    g_frame.filter_scrollbar,
    g_frame.filter_scroll,
    nil
)

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
        if not g_frame.db then
            return
        end
        local point, _, relative_point, x, y = g_frame:GetPoint(1)
        if point then
            g_frame.db.point = point
            g_frame.db.relativePoint = relative_point
            g_frame.db.x = x or 0
            g_frame.db.y = y or 0
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
        local px = g_frame.px_per_unit
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

-- Selects the best match for the search text and returns it. A CVar whose
-- name is exactly the search text wins and scrolls into view. Otherwise it
-- is the top row. "TurnSpeed" used to pick "GamePadTankTurnSpeed", which
-- sorts first.
g_frame.select_best_match = function()
    local query = trim(g_search_box:GetText() or ""):lower()
    local best = g_frame.view[1]
    local exact = g_frame.by_name[query]
    if exact and exact ~= best then
        for position, entry in ipairs(g_frame.view) do
            if entry == exact then
                best = exact
                scroll_to((position - 1) * ROW_HEIGHT, false)
                break
            end
        end
    end
    if best then
        select_entry(best)
    end
    return best
end

g_search_box:SetScript("OnEnterPressed", function(self)
    -- Enter keeps a row picked with the arrow keys. Otherwise it takes the
    -- best match.
    local entry = g_frame.selected
    if self.navigated and entry then
        select_entry(entry)
    else
        entry = g_frame.select_best_match()
    end
    if entry then
        if can_edit(entry) then
            g_detail_edit:SetFocus()
            g_detail_edit:HighlightText()
        end
    else
        self:ClearFocus()
    end
end)

-- Moves the selection for a navigation key and glides the selected row to
-- the top of the list. Returns true when the key was a navigation key.
-- PageUp and PageDown move by the rows the list shows at once.
g_frame.move_selection = function(pressed)
    local page = max(1, floor((g_scroll_frame:GetHeight() or 0) / ROW_HEIGHT))
    local steps = {
        UP = -1,
        DOWN = 1,
        PAGEUP = -page,
        PAGEDOWN = page,
        HOME = -#g_frame.view,
        END = #g_frame.view,
    }
    local step = steps[pressed]
    if not step then
        return false
    end
    if #g_frame.view == 0 then
        return true
    end
    local index = 1
    if g_frame.selected then
        for position, entry in ipairs(g_frame.view) do
            if entry == g_frame.selected then
                index = position
                break
            end
        end
    end
    index = clamp(index + step, 1, #g_frame.view)
    select_entry(g_frame.view[index])
    scroll_to((index - 1) * ROW_HEIGHT, true)
    return true
end

-- The first Escape clears the search text and a second one leaves the box.
g_search_box:SetScript("OnEscapePressed", function(self)
    if (self:GetText() or "") ~= "" then
        self:SetText("")
        return
    end
    self:ClearFocus()
end)

-- Home and End stay with the edit box, where they move the caret.
g_search_box:SetScript("OnKeyDown", function(self, pressed)
    if pressed == "HOME" or pressed == "END" then
        return
    end
    if g_frame.move_selection(pressed) then
        self.navigated = true
    end
end)

-- The history button a shortcut presses, or nil. Ctrl+Z undoes, and Ctrl+Y
-- or Ctrl+Shift+Z redoes.
local function history_button(pressed)
    if (pressed ~= "Z" and pressed ~= "Y")
        or not IsControlKeyDown() or IsAltKeyDown() then
        return nil
    end
    if pressed == "Y" or IsShiftKeyDown() then
        return g_frame.redo_button
    end
    return g_frame.undo_button
end

-- With no edit box focused, the window takes navigation keys and the undo
-- and redo shortcuts while the cursor is over it, and Escape closes a menu
-- or clears the search before it closes the window. Every other key passes
-- through to the game. The client forbids changing propagation in combat,
-- so keys always pass through then (PLAYER_REGEN_DISABLED restores it
-- before lockdown). A shortcut for a disabled button does nothing.
g_frame:EnableKeyboard(true)
g_frame:SetPropagateKeyboardInput(true)
g_frame:SetScript("OnKeyDown", function(self, pressed)
    if InCombatLockdown() then
        return
    end
    local handled = false
    if pressed == "ESCAPE" then
        if g_frame.menu_catcher:IsShown() then
            g_frame.close_menus()
            handled = true
        elseif (g_search_box:GetText() or "") ~= "" then
            g_search_box:SetText("")
            handled = true
        end
    elseif self:IsMouseOver() then
        local button = history_button(pressed)
        if button then
            handled = true
            if button:IsEnabled() then
                button:Click()
            end
        else
            handled = g_frame.move_selection(pressed)
        end
    end
    self:SetPropagateKeyboardInput(not handled)
end)

g_frame:SetScript("OnKeyUp", function(self)
    if not InCombatLockdown() then
        self:SetPropagateKeyboardInput(true)
    end
end)

-- Control tooltips. Hovering asks for one, leaving hands off warm, and a
-- mouse down on an enabled control hides it until the pointer comes back.
for _, control in ipairs({
    g_frame.regex_chip,
    g_frame.filter_chip,
    g_frame.undo_button,
    g_frame.redo_button,
}) do
    control:HookScript("OnEnter", function(self)
        g_frame.request_tooltip(self)
    end)
    control:HookScript("OnLeave", function()
        g_frame.leave_tooltip()
    end)
    control:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() then
            g_frame.hide_tooltip()
        end
    end)
end

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

-- Scrolling under the pointer hides the tooltip and restarts the delay for
-- the row now under it. A glide that runs on after the pointer has moved
-- onto a control leaves that control's tooltip alone.
g_scroll_frame:SetScript("OnVerticalScroll", function(self)
    scroll_rows()
    if not self:IsMouseOver() then
        return
    end
    g_frame.hide_tooltip()
    for _, row in ipairs(g_rows) do
        if row.entry and row:IsMouseOver() then
            g_frame.request_tooltip(row, row.favorite:IsMouseOver())
            break
        end
    end
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

for index = 1, ROW_COUNT do
    local row = g_rows[index]
    row:SetScript("OnClick", function(self)
        g_frame.hide_tooltip()
        if self.entry then
            select_entry(self.entry)
        end
    end)

    row:SetScript("OnEnter", function(self)
        if self.entry and g_frame.selected ~= self.entry then
            self.hover:Show()
        end
        if self.entry then
            g_frame.update_favorite_mark(self)
            g_frame.request_tooltip(self, false)
        end
    end)

    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        g_frame.update_favorite_mark(self)
        g_frame.leave_tooltip()
    end)

    -- The toggle keeps the row's hover fill, since entering it makes the
    -- row itself lose the pointer.
    row.favorite:SetScript("OnEnter", function()
        if row.entry then
            row.hover:SetShown(g_frame.selected ~= row.entry)
            g_frame.update_favorite_mark(row)
            g_frame.request_tooltip(row, true)
        end
    end)

    row.favorite:SetScript("OnLeave", function()
        row.hover:Hide()
        g_frame.update_favorite_mark(row)
        g_frame.leave_tooltip()
    end)

    row.favorite:SetScript("OnClick", function()
        g_frame.hide_tooltip()
        if row.entry then
            g_frame.toggle_favorite(row.entry)
        end
    end)
end

-- A hidden window runs no OnUpdate, so a thumb drag could not poll for the
-- button release until the window shows again. End any thumb drag here.
g_frame:SetScript("OnHide", function()
    g_frame.hide_tooltip()
    for _, thumb in ipairs({ g_scrollbar_thumb, g_frame.filter_scroll_thumb }) do
        thumb.drag = nil
        thumb:SetScript("OnUpdate", nil)
    end
end)

g_frame:SetScript("OnShow", function(self)
    self:Raise()
    g_frame.close_menus()
    apply_ui_scale()
    rescan()
end)

g_frame:SetScript("OnEvent", function(self, event, argument)
    if event == "ADDON_LOADED" then
        if argument ~= ADDON_NAME then
            return
        end
        init_db()
        self:ClearAllPoints()
        -- g_frame.db.x and y were saved as an on-grid anchor by the drag
        -- (rendered pixel locked). Restore them verbatim, since re-rounding
        -- them here on a different grid would fight the drag grid and shift
        -- the frame by a pixel.
        -- snap_frame_position() in apply_ui_scale is the single authoritative
        -- rendered-pixel snap.
        local x = tonumber(g_frame.db.x) or 0
        local y = tonumber(g_frame.db.y) or 0
        local ok = pcall(
            self.SetPoint,
            self,
            g_frame.db.point or "CENTER",
            UIParent,
            g_frame.db.relativePoint or "CENTER",
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
            g_frame.minimap_button:SetShown(not g_frame.db.minimap_hidden)
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "CVAR_UPDATE" then
        -- The payload keeps the caller's casing. g_frame.by_name also keys
        -- lowercase.
        local entry = type(argument) == "string"
            and (g_frame.by_name[argument] or g_frame.by_name[argument:lower()])
        if entry then
            read_cvar_value(entry)
            apply_range(entry)
            update_rows()
            if g_frame.selected == entry and not g_detail_edit:HasFocus() then
                update_detail()
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        -- PLAYER_REGEN_DISABLED fires just before lockdown, the last moment
        -- to make sure no key stays swallowed through combat. Lockdown is
        -- not on yet, so the controls update on the next frame.
        if event == "PLAYER_REGEN_DISABLED" then
            self:SetPropagateKeyboardInput(true)
            C_Timer.After(0, update_controls)
        else
            update_controls()
        end
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
