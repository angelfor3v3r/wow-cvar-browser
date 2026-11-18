-- CVar Browser. The control row (Filters, Sort, undo and redo, Copy)
-- and its menus.

local _, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local CreateFrame = CreateFrame
local SlashCmdList = SlashCmdList
local pairs, ipairs = pairs, ipairs
local floor, min, max = math.floor, math.min, math.max
local sort, concat = table.sort, table.concat

-- Shared from earlier files --------------------------------------------------

local g_frame = ns.g_frame
local COLORS = ns.COLORS
local FONT_BODY = ns.FONT_BODY
local FONT_META = ns.FONT_META
local FONT_CHECK = ns.FONT_CHECK
local round = ns.round
local make_text = ns.make_text
local apply_backdrop = ns.apply_backdrop
local snap_texture = ns.snap_texture
local set_texture_color = ns.set_texture_color
local set_text_color = ns.set_text_color
local g_hairline = ns.g_hairline
local create_button = ns.create_button
local g_entries = ns.g_entries
local g_changed_button = ns.g_changed_button
local g_changed_tick = ns.g_changed_tick

do
    local function set_chip_active(button, active)
        button.active = active and true or false
        local color = button.active and COLORS.accent or COLORS.border
        g_hairline.set_color(button.borders, color)
        set_text_color(
            button.label,
            button.active and COLORS.accent or COLORS.text
        )
        if button.icon_parts then
            local icon_color = button.active and COLORS.accent or COLORS.muted
            for _, part in ipairs(button.icon_parts) do
                set_texture_color(part, icon_color)
            end
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

    local function set_enabled(button, enabled)
        button:SetEnabled(enabled)
        button:SetAlpha(enabled and 1 or 0.38)
    end

    -- The Has facets in menu order. The Filters chip tooltip lists them in
    -- this order too, since filters.has is an unordered set.
    local HAS_OPTIONS = {
        { "range", "Range" },
        { "observed", "Observed bounds" },
        { "help", "Help range" },
        { "default", "Default" },
        { "changed", "Differs from default" },
        { "favorite", "Favorite" },
    }

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
        set_texture_color(row.background, COLORS.hover)
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
    g_frame.filter_chip.icon_parts = {}
    local filter_icon_parts = {
        { 10, 0 },
        { 6, 4 },
        { 2, 8 },
    }
    for _, part in ipairs(filter_icon_parts) do
        local line = snap_texture(filter_icon:CreateTexture(nil, "ARTWORK"))
        set_texture_color(line, COLORS.muted)
        line:SetSize(part[1], 1)
        line:SetPoint("TOPLEFT", filter_icon, "TOPLEFT", 0, -part[2])
        g_frame.filter_chip.icon_parts[#g_frame.filter_chip.icon_parts + 1] = line
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
        set_texture_color(part, COLORS.muted)
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

    local snap_boxes = g_frame.snap_boxes
    snap_boxes[#snap_boxes + 1] = g_frame.filter_chip
    snap_boxes[#snap_boxes + 1] = g_frame.sort_chip
    snap_boxes[#snap_boxes + 1] = g_frame.undo_button
    snap_boxes[#snap_boxes + 1] = g_frame.redo_button
    snap_boxes[#snap_boxes + 1] = g_frame.copy_button

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
    g_frame.filter_clear:SetPoint(
        "TOPRIGHT",
        g_frame.filter_popup,
        "TOPRIGHT",
        -6,
        -5
    )
    g_frame.filter_clear.label:SetFontObject(FONT_META)

    g_frame.filter_scroll = CreateFrame(
        "ScrollFrame",
        nil,
        g_frame.filter_popup
    )
    g_frame.filter_scroll:SetPoint(
        "TOPLEFT",
        g_frame.filter_popup,
        "TOPLEFT",
        4,
        -30
    )
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
    set_texture_color(filter_scroll_track, COLORS.hover)
    filter_scroll_track:SetPoint("TOP", g_frame.filter_scrollbar, "TOP", 0, 0)
    filter_scroll_track:SetPoint(
        "BOTTOM",
        g_frame.filter_scrollbar,
        "BOTTOM",
        0,
        0
    )
    filter_scroll_track:SetWidth(4)
    g_frame.filter_scroll_thumb = CreateFrame(
        "Frame",
        nil,
        g_frame.filter_scrollbar
    )
    g_frame.filter_scroll_thumb:SetWidth(6)
    g_frame.filter_scroll_thumb.background = snap_texture(
        g_frame.filter_scroll_thumb:CreateTexture(nil, "ARTWORK")
    )
    g_frame.filter_scroll_thumb.background:SetAllPoints(
        g_frame.filter_scroll_thumb
    )
    set_texture_color(g_frame.filter_scroll_thumb.background, COLORS.muted)
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
        local thumb_height = max(
            24,
            floor(viewport * viewport / (range + viewport))
        )
        local max_top = viewport - thumb_height
        local scroll = g_frame.filter_scroll:GetVerticalScroll() or 0
        local top = scroll / range * max_top
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
    g_frame.copy_box:SetPoint(
        "TOPLEFT",
        g_frame.copy_box_frame,
        "TOPLEFT",
        10,
        0
    )
    g_frame.copy_box:SetPoint(
        "BOTTOMRIGHT",
        g_frame.copy_box_frame,
        "BOTTOMRIGHT",
        -10,
        0
    )
    g_frame.copy_box:SetAutoFocus(false)
    g_frame.copy_box:SetFontObject(FONT_BODY)
    set_text_color(g_frame.copy_box, COLORS.text)
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
        g_frame.hide_tooltip()
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
    g_frame.menu_catcher:Hide()

    g_frame.close_menus = function()
        g_frame.filter_popup:Hide()
        g_frame.sort_popup:Hide()
        g_frame.copy_popup:Hide()
        g_frame.copy_box_frame:Hide()
        g_frame.menu_catcher:Hide()
    end

    -- Opens a popup under its chip, or closes the menus if it is already open.
    local function toggle_menu(popup, refresh)
        if popup:IsShown() then
            g_frame.close_menus()
            return
        end
        g_frame.close_menus()
        g_frame.hide_tooltip()
        refresh()
        g_frame.menu_catcher:Show()
        popup:Show()
        g_frame.snap_box(popup)
        g_frame.snap_region_tree(popup)
    end

    g_frame.menu_catcher:SetScript("OnMouseDown", function()
        g_frame.close_menus()
    end)

    local filter_row_index = 0

    local function take_filter_row()
        filter_row_index = filter_row_index + 1
        local index = filter_row_index
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
        set_text_color(row.label, COLORS.muted)
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
        set_text_color(row.label, COLORS.text)
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
        filter_row_index = 0
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
        for _, option in ipairs(HAS_OPTIONS) do
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

        for index = filter_row_index + 1, #g_frame.filter_rows do
            g_frame.filter_rows[index]:Hide()
        end
        g_frame.filter_content:SetHeight(max(1, y + 4))
        set_enabled(
            g_frame.filter_clear,
            filter_count() > 0 or g_changed_button.checked
        )
        g_frame.filter_scroll:SetVerticalScroll(
            min(scroll, g_frame.filter_scroll:GetVerticalScrollRange() or 0)
        )
        update_filter_scrollbar()
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

    local function clear_filters()
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

    g_frame.filter_clear:SetScript("OnClick", clear_filters)

    local function apply_sort(sort_choice)
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

    local function refresh_sort_menu()
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
            set_text_color(row.label, COLORS.text)
            row.note:SetText(
                g_frame.sort_key == sort_option and g_frame.sort_dir or ""
            )
            row.check:SetShown(g_frame.sort_key == sort_option)
            row.on_click = function()
                apply_sort(sort_option)
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

    local function refresh_copy_menu()
        local fields = {
            { "value", "Copy value" },
            { "raw", "Copy raw value" },
            { "default", "Copy default" },
            { "name", "Copy name" },
            { "help", "Copy help" },
            { "range", "Copy range" },
        }
        local selected = g_frame.selected
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
            set_text_color(row.label, COLORS.text)
            row.check:Hide()
            local empty = selected ~= nil
                and ((copy_key == "help"
                        and (selected.help == nil or selected.help == ""))
                    or (copy_key == "range" and selected.range_text == nil))
            local missing = selected == nil or empty
            row.note:SetText(empty and "none" or "")
            set_enabled(row, not missing)
            row.on_click = function()
                g_frame.close_menus()
                run_command("copy " .. copy_key)
            end
        end
    end

    g_frame.update_copy_button = function()
        local enabled = g_frame.selected ~= nil
        set_enabled(g_frame.copy_button, enabled)
        if not enabled and g_frame.copy_popup:IsShown() then
            g_frame.close_menus()
        end
    end

    g_frame.update_history_controls = function()
        local undo_count = #g_frame.undo_stack
        local redo_count = #g_frame.redo_stack
        set_enabled(g_frame.undo_button, undo_count > 0)
        set_enabled(g_frame.redo_button, redo_count > 0)
    end

    -- Control tooltips. Each returns a title, its color, a detail line, and
    -- its color, or nil when the control shows no tooltip.
    g_frame.regex_chip.tooltip_text = function()
        if g_frame.regex_enabled then
            return "Pattern search on", COLORS.text,
                "The search is one Lua pattern, such as ^nameplate or quality$. "
                    .. "Terms like scope:account still filter, and an invalid "
                    .. "pattern matches nothing.",
                COLORS.text
        end
        return "Pattern search off", COLORS.text,
            "Search words match as plain text. Click to read the search as a "
                .. "Lua pattern, such as ^nameplate or quality$.",
            COLORS.text
    end

    -- Lists exactly the facets the chip counts, as search terms.
    g_frame.filter_chip.tooltip_text = function()
        local filters = g_frame.filters
        local terms = {}
        if filters.scope ~= "" then
            terms[#terms + 1] = "scope:" .. filters.scope
        end
        if filters.category ~= "" then
            terms[#terms + 1] = "category:" .. filters.category
        end
        if filters.type ~= "" then
            terms[#terms + 1] = "type:" .. filters.type
        end
        for _, option in ipairs(HAS_OPTIONS) do
            if filters.has[option[1]] then
                terms[#terms + 1] = "has:" .. option[1]
            end
        end
        if #terms == 0 then
            return nil
        end
        return "Active filters", COLORS.text, concat(terms, ", "), COLORS.text
    end

    -- Undo and Redo name the CVar they would change, and keep a tooltip
    -- while disabled so the shortcut stays discoverable.
    local function history_tooltip(stack, verb, empty_title, shortcut)
        local last = stack[#stack]
        if last then
            return verb .. " " .. last.name, COLORS.text, shortcut, COLORS.muted
        end
        return empty_title, COLORS.muted, shortcut, COLORS.muted
    end

    g_frame.undo_button.tooltip_text = function()
        return history_tooltip(
            g_frame.undo_stack,
            "Undo",
            "Nothing to undo",
            "Ctrl+Z"
        )
    end

    g_frame.redo_button.tooltip_text = function()
        return history_tooltip(
            g_frame.redo_stack,
            "Redo",
            "Nothing to redo",
            "Ctrl+Y or Ctrl+Shift+Z"
        )
    end

    g_frame.undo_button:SetMotionScriptsWhileDisabled(true)
    g_frame.redo_button:SetMotionScriptsWhileDisabled(true)

    g_frame.filter_chip:SetScript("OnClick", function()
        toggle_menu(g_frame.filter_popup, g_frame.refresh_filter_menu)
    end)

    g_frame.sort_chip:SetScript("OnClick", function()
        toggle_menu(g_frame.sort_popup, refresh_sort_menu)
    end)

    g_frame.copy_button:SetScript("OnClick", function()
        if g_frame.copy_popup:IsShown() or g_frame.selected then
            toggle_menu(g_frame.copy_popup, refresh_copy_menu)
        end
    end)

    g_frame.undo_button:SetScript("OnClick", function()
        run_command("undo")
    end)

    g_frame.redo_button:SetScript("OnClick", function()
        run_command("redo")
    end)

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

    g_frame.update_filter_chip()
    g_frame.update_sort_chip()
    g_frame.update_regex_chip()
    g_frame.update_copy_button()
    g_frame.update_history_controls()
end
