-- CVar Browser. Slash commands.

local _, ns = ...

-- Localized WoW APIs ---------------------------------------------------------

local SlashCmdList = SlashCmdList
local GetCVarInfo = (C_CVar and C_CVar.GetCVarInfo) or GetCVarInfo
local pairs, ipairs = pairs, ipairs
local type, tostring, tonumber = type, tostring, tonumber
local pcall = pcall
local floor, max = math.floor, math.max
local format = string.format
local sort = table.sort
local date = date

-- Shared from earlier files --------------------------------------------------

local g_frame = ns.g_frame
local DB_DEFAULTS = ns.DB_DEFAULTS
local trim = ns.trim
local chat = ns.chat
local format_observed_range = ns.format_observed_range
local format_observed_evidence = ns.format_observed_evidence
local can_edit = ns.can_edit
local g_search_box = ns.g_search_box
local g_detail_edit = ns.g_detail_edit
local set_status = ns.set_status
local rebuild_view = ns.rebuild_view
local rescan = ns.rescan
local step_history = ns.step_history
local copy_field = ns.copy_field

-- WoW's chat code scans globals named SLASH_<KEY><n> (n = 1, 2, ...)
-- and routes each listed command to SlashCmdList["<KEY>"]. The
-- handler gets the rest of the line after the command word.
SLASH_CVARBROWSER1 = "/cvars"
SLASH_CVARBROWSER2 = "/cb"
SLASH_CVARBROWSER3 = "/cvarbrowser"

do
    -- Rescans a shown window. Showing a hidden one rescans through OnShow.
    local function refresh()
        if g_frame:IsShown() then
            rescan()
        else
            g_frame:Show()
        end
    end

    -- Finds the CVar a command names, opening the window for it. The list is
    -- only scanned while the window shows, so a hidden window asks the
    -- client whether the name exists first. A typo then prints its error
    -- without opening anything. With no name it returns the selection.
    local function find_target(lower_name, typed_name)
        if not lower_name then
            if g_frame.selected then
                g_frame:Show()
            end
            return g_frame.selected
        end
        local known = g_frame.by_name[lower_name] ~= nil
        if not known and not g_frame:IsShown() and GetCVarInfo then
            local ok, value = pcall(GetCVarInfo, typed_name)
            known = ok and value ~= nil
        end
        if not known then
            return nil
        end
        g_frame:Show()
        return g_frame.by_name[lower_name]
    end

    -- Commands that are the whole line, keyed by the lowercase line. Extra
    -- words after one of these make the line a search instead.
    local exact = {}

    -- Commands that take arguments, keyed by their first word. Each gets the
    -- lowercase line and the line as typed. Returning false hands the line
    -- to the search.
    local worded = {}

    exact.help = function()
        chat(
            "commands: "
                .. "/cvars || /cb, /cvars <name>, refresh, undo, redo, "
                .. "fav [name], log [count||name], clearlog, "
                .. "ranges [name], clearrange <name>, clearranges, "
                .. "sort name||type||scope||category||changed||range [asc||desc], "
                .. "copy [value||raw||default||name||help||range] [cvar], "
                .. "regex [on||off], smooth [on||off], minimap [reset], filters"
        )
    end

    exact.filters = function()
        chat(
            "filters: "
                .. "scope:account||character||local, "
                .. "cat:graphics, "
                .. "type:number||boolean||enum||text||list||bitfield||serialized, "
                .. "has:range||observed||help||default||changed||fav, "
                .. "value:<text>, value:=<exact>, and changed. "
                .. "/cb regex toggles Lua-pattern search."
        )
    end

    exact.undo = function()
        step_history("undo")
    end

    exact.redo = function()
        step_history("redo")
    end

    exact.refresh = refresh
    exact.rescan = refresh

    exact.clearranges = function()
        local count = 0
        if g_frame.db and type(g_frame.db.observed) == "table" then
            for _ in pairs(g_frame.db.observed) do
                count = count + 1
            end
            g_frame.db.observed = {}
        end
        chat(
            format(
                "cleared %d observed range%s",
                count,
                count == 1 and "" or "s"
            )
        )
        refresh()
    end

    exact.clearlog = function()
        local count = g_frame.db and #g_frame.db.log or 0
        if g_frame.db then
            g_frame.db.log = {}
        end
        chat(
            format(
                "cleared %d logged change%s",
                count,
                count == 1 and "" or "s"
            )
        )
    end

    worded.minimap = function(lower)
        if type(g_frame.minimap_button) ~= "table" then
            chat("minimap button unavailable")
            return
        end
        local argument = lower:match("^minimap%s+(%S+)")
        if argument == "reset" then
            if g_frame.db then
                g_frame.db.minimap_angle = DB_DEFAULTS.minimap_angle
            end
            g_frame.minimap_button:update_position()
            chat("minimap angle reset")
        else
            if g_frame.db then
                g_frame.db.minimap_hidden = not g_frame.db.minimap_hidden
            end
            local hidden = g_frame.db and g_frame.db.minimap_hidden
            g_frame.minimap_button:SetShown(not hidden)
            chat("minimap button " .. (hidden and "hidden" or "shown"))
        end
    end

    worded.copy = function(lower, message_text)
        local field = lower:match("^copy%s+(%S+)") or "value"
        local target_name = lower:match("^copy%s+%S+%s+(%S+)")
        local typed_name = message_text:match("^%S+%s+%S+%s+(%S+)")
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
            typed_name = message_text:match("^%S+%s+(%S+)")
            field = "value"
        end
        local entry = find_target(target_name, typed_name)
        if not entry then
            chat(
                target_name and ("unknown CVar " .. target_name)
                    or "no CVar selected to copy"
            )
            return
        end
        copy_field(entry, field)
    end

    worded.sort = function(lower)
        -- Reports to chat as well, since the window may be hidden.
        local function report(chat_text, status_text, tone)
            set_status(status_text, tone)
            chat(chat_text)
        end
        -- Everything after the key counts as the direction, so extra
        -- words report a bad direction rather than a bad key.
        local sort_key, sort_dir = lower:match("^sort%s+(%S+)%s*(.-)$")
        local valid = sort_key == "name"
            or sort_key == "type"
            or sort_key == "scope"
            or sort_key == "category"
            or sort_key == "changed"
            or sort_key == "range"
        if not valid then
            report(
                "sort must be name, type, scope, category, changed, or range",
                "Sort must be name, type, scope, category, changed, or range.",
                "error"
            )
            return
        end
        if sort_dir ~= "" and sort_dir ~= "asc" and sort_dir ~= "desc" then
            report(
                "sort direction must be asc or desc",
                "Sort direction must be asc or desc.",
                "error"
            )
            return
        end
        g_frame.sort_key = sort_key
        if sort_dir == "" then
            sort_dir = sort_key == "changed" and "desc" or "asc"
        end
        g_frame.sort_dir = sort_dir
        g_frame.update_sort_chip()
        rebuild_view()
        local text = sort_key .. " " .. sort_dir
        report("sorted by " .. text, "Sorted by " .. text)
    end

    worded.regex = function(lower)
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
        local state = g_frame.regex_enabled and "on" or "off"
        set_status("Pattern search " .. state)
        chat("pattern search " .. state)
    end

    worded.smooth = function(lower)
        if not g_frame.db then
            return
        end
        local value = lower:match("^smooth%s+(%S+)")
        if value == "on" then
            g_frame.db.smooth_scroll = true
        elseif value == "off" then
            g_frame.db.smooth_scroll = false
        else
            g_frame.db.smooth_scroll = not g_frame.db.smooth_scroll
        end
        chat(
            "smooth scrolling "
                .. (g_frame.db.smooth_scroll and "on" or "off")
        )
    end

    worded.ranges = function(lower)
        local only = lower:match("^ranges%s+(.+)$")
        local names = {}
        if g_frame.db and type(g_frame.db.observed) == "table" then
            for name in pairs(g_frame.db.observed) do
                if not only or name:lower() == only then
                    names[#names + 1] = name
                end
            end
        end
        sort(names)
        if #names == 0 then
            chat("no observed ranges" .. (only and (" for " .. only) or ""))
            return
        end
        chat(
            format(
                "%d observed range%s",
                #names,
                #names == 1 and "" or "s"
            )
        )
        for _, name in ipairs(names) do
            local observed = g_frame.db.observed[name]
            local entry = g_frame.by_name[name]
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
    end

    worded.clearrange = function(_, message_text)
        -- Match case-insensitively but echo the stored or typed casing.
        local clear_name = message_text:match("^%S+%s+(.+)$")
        if not clear_name then
            return false
        end
        local found = nil
        if g_frame.db and type(g_frame.db.observed) == "table" then
            for name in pairs(g_frame.db.observed) do
                if name:lower() == clear_name:lower() then
                    g_frame.db.observed[name] = nil
                    found = name
                    break
                end
            end
        end
        chat(
            found and ("cleared " .. found)
                or ("no observed range for " .. clear_name)
        )
        refresh()
    end

    worded.fav = function(lower, message_text)
        local fav_name = lower:match("^fav%s+(%S+)")
        local entry = find_target(
            fav_name,
            message_text:match("^%S+%s+(%S+)")
        )
        if not entry then
            chat(
                fav_name and ("unknown CVar " .. fav_name)
                    or "no CVar selected"
            )
            return
        end
        g_frame.toggle_favorite(entry)
        local is_favorite = g_frame.db and g_frame.db.favorites[entry.name]
        chat(
            entry.name
                .. (is_favorite and " added to favorites"
                    or " removed from favorites")
        )
    end

    worded.log = function(lower)
        local log = g_frame.db and g_frame.db.log or {}
        local argument = lower:match("^log%s+(%S+)")
        local count = tonumber(argument or "10")
        local shown = {}
        if count then
            for index = max(1, #log - floor(count) + 1), #log do
                shown[#shown + 1] = log[index]
            end
        else
            for _, change in ipairs(log) do
                if tostring(change.name):lower() == argument then
                    shown[#shown + 1] = change
                end
            end
        end
        if #shown == 0 then
            chat(
                "no logged changes"
                    .. ((argument and not count) and (" for " .. argument) or "")
            )
            return
        end
        chat(
            format(
                "%d of %d logged change%s, oldest first",
                #shown,
                #log,
                #log == 1 and "" or "s"
            )
        )
        for _, change in ipairs(shown) do
            local old_text = tostring(change.old or "")
            local new_text = tostring(change.new or "")
            DEFAULT_CHAT_FRAME:AddMessage(
                format(
                    "  %s %s %s: %s -> %s",
                    date("%Y-%m-%d %H:%M", tonumber(change.time) or 0),
                    tostring(change.action or "set"),
                    tostring(change.name),
                    old_text == "" and "empty" or old_text,
                    new_text == "" and "empty" or new_text
                )
            )
        end
    end

    -- Searches for the text and selects the best match, focusing the value
    -- field when that CVar can be edited.
    local function search(message_text)
        g_frame:Show()
        -- OnTextChanged rebuilds only when the text changes, so repeat
        -- the search by hand to reset the list to the top.
        local unchanged = g_search_box:GetText() == message_text
        g_search_box:SetText(message_text)
        if unchanged then
            rebuild_view()
        end
        g_search_box:ClearFocus()
        local best = g_frame.select_best_match()
        if best and can_edit(best) then
            g_detail_edit:SetFocus()
            g_detail_edit:HighlightText()
        end
    end

    SlashCmdList["CVARBROWSER"] = function(message)
        local message_text = trim(message or "")
        local lower = message_text:lower()

        if message_text == "" then
            g_frame:SetShown(not g_frame:IsShown())
            return
        end

        local handler = exact[lower]
        if handler then
            handler()
            return
        end

        handler = worded[lower:match("^%S+")]
        if handler and handler(lower, message_text) ~= false then
            return
        end

        search(message_text)
    end
end
