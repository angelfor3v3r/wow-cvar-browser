-- CVar Browser. Row and detail rendering, filtering and sorting,
-- scanning, and setting values.

local _, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local SetCVarNative = (C_CVar and C_CVar.SetCVar) or SetCVar
local ConsoleGetAllCommands =
    (C_Console and C_Console.GetAllCommands) or ConsoleGetAllCommands
local pairs, ipairs = pairs, ipairs
local type, tostring, tonumber = type, tostring, tonumber
local pcall = pcall
local floor, min, max = math.floor, math.min, math.max
local format, find = string.format, string.find
local sort, concat, remove = table.sort, table.concat, table.remove

-- Shared from earlier files --------------------------------------------------

local g_frame = ns.g_frame
local METRICS = ns.METRICS
local ROW_HEIGHT = ns.ROW_HEIGHT
local ROW_COUNT = ns.ROW_COUNT
local GAUGE_WIDTH = ns.GAUGE_WIDTH
local META_MAX_PARTS = ns.META_MAX_PARTS
local COLORS = ns.COLORS
local trim = ns.trim
local clamp = ns.clamp
local round = ns.round
local hex_to_bitfield = ns.hex_to_bitfield
local display_edit_value = ns.display_edit_value
local default_text = ns.default_text
local ellipsize = ns.ellipsize
local g_entries = ns.g_entries
local parse_range = ns.parse_range
local parse_enum_help = ns.parse_enum_help
local apply_range = ns.apply_range
local read_cvar_value = ns.read_cvar_value
local is_cvar_entry = ns.is_cvar_entry
local record_observed_bound = ns.record_observed_bound
local classify_set_outcome = ns.classify_set_outcome
local UNDO_LIMIT = ns.UNDO_LIMIT
local can_edit = ns.can_edit
local set_texture_color = ns.set_texture_color
local set_text_color = ns.set_text_color
local build_meta_parts = ns.build_meta_parts
local log_change = ns.log_change
local g_search_box = ns.g_search_box
local g_changed_button = ns.g_changed_button
local g_changed_tick = ns.g_changed_tick
local g_count_text = ns.g_count_text
local g_scroll_frame = ns.g_scroll_frame
local g_scroll_child = ns.g_scroll_child
local g_scrollbar = ns.g_scrollbar
local g_scrollbar_thumb = ns.g_scrollbar_thumb
local g_rows = ns.g_rows
local g_detail_name = ns.g_detail_name
local g_detail_meta = ns.g_detail_meta
local g_detail_meta_parts = ns.g_detail_meta_parts
local g_detail_meta_separators = ns.g_detail_meta_separators
local g_detail_help = ns.g_detail_help
local g_detail_edit_frame = ns.g_detail_edit_frame
local g_detail_edit = ns.g_detail_edit
local g_set_button = ns.g_set_button
local g_reset_button = ns.g_reset_button
local g_detail_status = ns.g_detail_status

-- Constants ------------------------------------------------------------------

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

-- Inline color escape for the muted "(Default: ...)" suffix in rows.
local MUTED_ESCAPE = format(
    "|cff%02x%02x%02x",
    round(COLORS.muted[1] * 255),
    round(COLORS.muted[2] * 255),
    round(COLORS.muted[3] * 255)
)

-- Rendering ------------------------------------------------------------------

local function set_status(message, tone)
    g_detail_status:SetText(message or "")
    local color = COLORS.success
    if tone == "error" then
        color = COLORS.error
    elseif tone == "warning" then
        color = COLORS.warning
    end
    set_text_color(g_detail_status, color)
    g_frame.status_token = (g_frame.status_token or 0) + 1
    local token = g_frame.status_token
    if message and message ~= "" then
        C_Timer.After(30, function()
            if g_frame.status_token == token then
                g_detail_status:SetText("")
            end
        end)
    end
end

g_frame.notify = set_status

local function update_controls()
    local entry = g_frame.selected
    local editable = can_edit(entry)
    -- Reset needs a known default, or it would write an empty value.
    local resettable = editable and entry.default_value ~= nil

    if editable then
        g_detail_edit:Enable()
        g_set_button:Enable()
    else
        g_detail_edit:Disable()
        g_set_button:Disable()
    end
    g_reset_button:SetEnabled(resettable)
    g_detail_edit_frame:SetAlpha(editable and 1 or 0.55)
    g_set_button:SetAlpha(editable and 1 or 0.38)
    g_reset_button:SetAlpha(resettable and 1 or 0.38)

    local name_color = COLORS.text
    if entry and entry.readonly then
        name_color = COLORS.muted
    elseif entry and entry.changed then
        name_color = COLORS.changed
    end
    set_text_color(g_detail_name, name_color)

    if entry and entry.secure and not entry.readonly and InCombatLockdown() then
        set_status("Secure CVars can't change in combat.", "warning")
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
            set_text_color(part, spec.color)
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
    local entry = g_frame.selected
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

-- Merges the help range with the observed bounds into the span a gauge draws
-- and the range sort measures. Either end can come back nil.
local function range_domain(help_min, help_max, observed_min, observed_max)
    local domain_min = help_min
    if observed_min ~= nil
        and (domain_min == nil or observed_min < domain_min) then
        domain_min = observed_min
    end
    local domain_max = help_max
    if observed_max ~= nil
        and (domain_max == nil or observed_max > domain_max) then
        domain_max = observed_max
    end
    return domain_min, domain_max
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

    local domain_min, domain_max =
        range_domain(help_min, help_max, observed_min, observed_max)

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
    set_texture_color(gauge.cursor, cursor_color)
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

-- The row's favorite mark is accent under the pointer, text for a
-- favorite, muted on a hovered or selected row, and hidden otherwise.
g_frame.update_favorite_mark = function(row)
    local entry = row.entry
    if not entry then
        return
    end
    local color = nil
    if row.favorite:IsMouseOver() then
        color = COLORS.accent
    elseif entry.favorite then
        color = COLORS.text
    elseif g_frame.selected == entry or row:IsMouseOver() then
        color = COLORS.muted
    end
    g_frame.paint_diamond(row.favorite.mark, color, entry.favorite)
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
    elseif g_frame.selected == entry then
        name_color = COLORS.accent
    end
    set_text_color(row.name_text, name_color)

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
        local default_display = nil
        if entry.bitfield or entry.serialized then
            default_display = format(
                "%d bytes",
                #tostring(entry.default_value or "")
            )
        else
            default_display = ellipsize(default_text(entry), 14)
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
    set_text_color(row.value_text, value_color)

    local is_selected = g_frame.selected == entry
    row.selected_background:SetShown(is_selected)
    row.selected_bar:SetShown(is_selected)
    row.hover:SetShown(not is_selected and row:IsMouseOver())
    update_gauge(row.gauge, entry)
    g_frame.update_favorite_mark(row)
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
    local top = (scroll / range) * max_top

    g_scrollbar_thumb:SetHeight(thumb_height)
    g_scrollbar_thumb:ClearAllPoints()
    g_scrollbar_thumb:SetPoint("TOP", g_scrollbar, "TOP", 0, -top)
    g_frame.snap_box(g_scrollbar_thumb)
end

local function first_visible_row()
    local offset = g_scroll_frame:GetVerticalScroll() or 0
    -- Use floor, not round, since the partially scrolled-off top row must
    -- still draw.
    local first = floor(offset / ROW_HEIGHT) + 1
    if first < 1 then
        first = 1
    end
    return first
end

local function update_rows()
    local view = g_frame.view
    g_scroll_child:SetHeight(max(1, #view * ROW_HEIGHT))
    local first = first_visible_row()
    g_scroll_frame.first_row = first

    for index = 1, ROW_COUNT do
        local row = g_rows[index]
        local entry = view[first + index - 1]
        local y = -((first + index - 2) * ROW_HEIGHT)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", g_scroll_child, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", g_scroll_child, "TOPRIGHT", 0, y)
        render_row(row, entry)
    end
    update_scrollbar()
end

-- Scrolling inside one row changes no row content. Redraw the rows only when
-- the first visible row moved, otherwise refresh the hover state and the
-- scrollbar thumb.
local function scroll_rows()
    if first_visible_row() ~= g_scroll_frame.first_row then
        update_rows()
        return
    end
    for index = 1, ROW_COUNT do
        local row = g_rows[index]
        row.hover:SetShown(g_frame.selected ~= row.entry and row:IsMouseOver())
        g_frame.update_favorite_mark(row)
    end
    update_scrollbar()
end

local function select_entry(entry)
    g_frame.selected = entry
    update_detail()
    update_rows()
end

-- Pass keep_scroll to stay at the current offset (a favorite toggle).
-- Otherwise the list jumps back to the top for the new results.
local function rebuild_view(keep_scroll)
    g_frame.hide_tooltip()
    local query = trim(g_search_box:GetText() or "")
    local use_pattern = g_frame.regex_enabled == true
    local only_changed = g_changed_button.checked
    local terms = {}
    local filter_scope = nil
    local filter_category = nil
    local filter_type = nil
    local filter_has = nil
    local filter_value = nil
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
        elseif token_key == "value" then
            filter_value = value
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
    -- Most patterns that cannot compile fail on an empty subject too, so
    -- they match nothing without a pcall per entry. The rest still fail
    -- safely inside matches_text.
    local pattern_valid = not use_pattern or pcall(find, "", pattern)
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
        elseif facet == "fav" or facet == "favorite" then
            return entry.favorite
        end
        return true
    end

    local function matches_text(entry)
        if pattern == "" then
            return true
        end
        if use_pattern then
            if not pattern_valid then
                return false
            end
            local ok_name, name_match = pcall(find, entry.name_lower, pattern)
            if ok_name and name_match then
                return true
            end
            if entry.help_lower then
                local ok_help, help_match = pcall(
                    find,
                    entry.help_lower,
                    pattern
                )
                return ok_help and help_match ~= nil
            end
            return false
        end
        for _, term in ipairs(terms) do
            if not find(entry.name_lower, term, 1, true)
                and not (entry.help_lower
                    and find(entry.help_lower, term, 1, true)) then
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
            and entry.scope_lower ~= visual_filters.scope then
            return false
        end
        if visual_filters.category
            and visual_filters.category ~= ""
            and entry.category_lower ~= visual_filters.category then
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
            and not find(entry.scope_lower, filter_scope, 1, true) then
            return false
        end
        if filter_category
            and not find(entry.category_lower, filter_category, 1, true) then
            return false
        end
        if filter_type
            and entry.type_key ~= filter_type then
            return false
        end
        if filter_has and not has_state(entry, filter_has) then
            return false
        end
        if filter_value then
            -- Compare against what the value field shows (hex for bitfields).
            local shown = display_edit_value(entry, entry.value):lower()
            local exact = filter_value:match("^=(.*)$")
            if exact then
                return shown == exact
            end
            return find(shown, filter_value, 1, true) ~= nil
        end
        return true
    end

    local view = {}
    g_frame.view = view
    local favorites = g_frame.db and g_frame.db.favorites
    local selected = g_frame.selected
    local selected_visible = false
    local range_count = 0
    local has_favorite = false

    for _, entry in ipairs(g_entries) do
        entry.favorite = favorites ~= nil and favorites[entry.name] == true
        if matches_filters(entry) and matches_text(entry) then
            view[#view + 1] = entry
            if entry == selected then
                selected_visible = true
            end
            if entry.favorite then
                has_favorite = true
            end
            if entry.range_text then
                range_count = range_count + 1
            end
        end
    end

    local sort_key = g_frame.sort_key or "name"
    local sort_dir = g_frame.sort_dir or "asc"
    -- Favorites pin above every other row in both directions. The sort key
    -- only orders rows within the pinned and unpinned groups.
    if has_favorite or sort_key ~= "name" or sort_dir ~= "asc" then
        local function sort_value(entry, token_key)
            if token_key == "type" then
                return entry.type_key
            elseif token_key == "scope" then
                return entry.scope_lower
            elseif token_key == "category" then
                return entry.category_lower
            end
            return entry.name_lower
        end
        -- Widths are measured once here so the comparator only looks them up.
        local widths = {}
        if sort_key == "range" then
            for _, entry in ipairs(view) do
                local observed = entry.observed
                local low, high = range_domain(
                    entry.help_min,
                    entry.help_max,
                    observed and tonumber(observed.min),
                    observed and tonumber(observed.max)
                )
                if low ~= nil and high ~= nil then
                    widths[entry] = high - low
                end
            end
        end
        sort(view, function(a, b)
            if a.favorite ~= b.favorite then
                return a.favorite
            end
            if sort_key == "changed" then
                if a.changed ~= b.changed then
                    if sort_dir == "desc" then
                        return a.changed
                    end
                    return b.changed
                end
            elseif sort_key == "range" then
                local a_width = widths[a]
                local b_width = widths[b]
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

    if not selected_visible then
        g_frame.selected = nil
    end
    if not g_frame.selected and #g_frame.view > 0 then
        g_frame.selected = g_frame.view[1]
    end

    g_count_text:SetText(
        format(
            "%d / %d CVars, %d with range",
            #g_frame.view,
            #g_entries,
            range_count
        )
    )
    g_scroll_frame.scroll_target = nil
    if keep_scroll ~= true then
        g_scroll_frame:SetVerticalScroll(0)
    end
    update_rows()
    update_detail()
end

g_frame.rebuild_results = rebuild_view

g_frame.toggle_favorite = function(entry)
    if not g_frame.db then
        return
    end
    local added = not g_frame.db.favorites[entry.name]
    g_frame.db.favorites[entry.name] = added or nil
    rebuild_view(true)
    set_status(
        format(
            added and "Added %s to favorites" or "Removed %s from favorites",
            entry.name
        )
    )
end

local function rescan()
    local selected_name = g_frame.selected and g_frame.selected.name
    g_frame.by_name = {}
    for index = #g_entries, 1, -1 do
        g_entries[index] = nil
    end
    g_frame.view = {}
    g_frame.selected = nil

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
            if not g_frame.by_name[name] then
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
                    category_lower = category and category:lower() or "",
                }
                entry.help_range, entry.help_min, entry.help_max =
                    parse_range(help)
                entry.help_enum = parse_enum_help(help)
                read_cvar_value(entry)
                apply_range(entry)
                g_frame.by_name[name] = entry
                g_frame.by_name[entry.name_lower] = entry
                g_entries[#g_entries + 1] = entry
            end
        end
    end

    sort(g_entries, function(a, b)
        return a.name_lower < b.name_lower
    end)

    g_frame.selected = selected_name and g_frame.by_name[selected_name] or nil
    if g_frame.filter_popup:IsShown() then
        g_frame.refresh_filter_menu()
    end
    rebuild_view()
    set_status(format("Loaded %d CVars.", #g_entries))
end

-- The Set button and Enter pass no action (the click handler's first
-- argument is the button), so anything but "reset" logs as a set.
local function apply_value(action)
    local entry = g_frame.selected
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
        set_status("Secure CVars can't change in combat.", "error")
        return
    end

    local previous = entry.value
    local requested = g_detail_edit:GetText() or ""
    if entry.bitfield or entry.serialized then
        local decoded = hex_to_bitfield(requested)
        if decoded == nil then
            set_status(
                "Bitfield and serialized values take hex with an even number of digits.",
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
        set_status("SetCVar refused it (read-only, secure, or invalid).", "error")
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
        if #undo > UNDO_LIMIT then
            remove(undo, 1)
        end
        g_frame.redo_stack = {}
        -- The Undo and Redo tooltips name the top of each stack.
        g_frame.hide_tooltip()
        log_change(
            entry,
            action == "reset" and "reset" or "set",
            previous,
            actual
        )
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
                "%s refused it and stays %s (read-only, secure, or invalid)",
                entry.name,
                actual_display
            ),
            "error"
        )
    elseif outcome == "unverified" then
        set_status(
            format("Set %s, but its value could not be read back", entry.name),
            "warning"
        )
    elseif outcome == "accepted" then
        set_status(format("Set %s = %s", entry.name, actual_display))
    elseif outcome == "ignored" then
        set_status(
            format("%s ignored it and stays %s", entry.name, actual_display),
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
    local entry = g_frame.selected
    if not entry or entry.readonly then
        return
    end
    if entry.default_value == nil then
        set_status("This CVar has no known default.", "error")
        return
    end
    g_detail_edit:SetText(
        display_edit_value(entry, entry.default_value)
    )
    apply_value("reset")
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

-- Shared with the files loaded after this one.
ns.set_status = set_status
ns.update_controls = update_controls
ns.update_detail = update_detail
ns.update_scrollbar = update_scrollbar
ns.update_rows = update_rows
ns.scroll_rows = scroll_rows
ns.select_entry = select_entry
ns.rebuild_view = rebuild_view
ns.rescan = rescan
ns.apply_value = apply_value
ns.reset_value = reset_value
ns.toggle_changed = toggle_changed
