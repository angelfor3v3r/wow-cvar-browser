# CVar Browser

Search, inspect, edit, and reset every console variable the WoW Forever client exposes.

## Install

1. Download `CVarBrowser-<version>.zip` from the latest GitHub release and extract it into `Interface/AddOns`, so you end up with `Interface/AddOns/CVarBrowser`. Before the first release, or to run unreleased changes, copy this repository into `Interface/AddOns/CVarBrowser` instead.
2. Restart the client, or `/reload` if it is already running.
3. Run `/cvars` or `/cb`.

## Features

- Search CVars by name or help text.
- See each CVar's current value, default, account or character scope, and category.
- Edit values, see when the client clamps or normalizes them, and reset to default.
- Undo and redo successful changes.
- A saved change log of every set, reset, undo, and redo made in the browser.
- Pin favorite CVars so they stay at the top of the list.
- Hover a row to see its full name, value, and help text.
- Markers for read-only, secure, changed, and observed-bound CVars.
- Learned clamp bounds that you can list and clear.
- An 88×8 range gauge on every row.
- A draggable minimap button and an Addon Compartment entry.
- The window remembers its position.
- Auto, Compact, Standard, and Large sizes. Every size draws one UI unit per physical pixel with whole-number font sizes, and Auto picks a size from your physical screen height.

## Slash commands

| Command | What it does |
|---|---|
| `/cvars` or `/cb` | Toggle the browser |
| `/cvars <name>` | Open, search, and select a CVar |
| `/cvars refresh` | Rescan |
| `/cvars undo` | Undo the last successful set |
| `/cvars redo` | Redo the last undo |
| `/cvars ranges [name]` | List learned clamp bounds, for all CVars or one |
| `/cvars fav [name]` | Pin or unpin a CVar, or the selected one |
| `/cvars log [count\|name]` | List logged changes, the last 10 by default, or every change to one CVar |
| `/cvars clearlog` | Clear the change log |
| `/cvars sort name\|type\|scope\|category\|changed\|range [asc\|desc]` | Sort the rows |
| `/cvars copy [value\|raw\|default\|name\|help\|range] [cvar]` | Show the text selected in a copy box so you can press Ctrl+C (addons can't write to the clipboard) |
| `/cvars minimap` | Hide or show the minimap button |
| `/cvars minimap reset` | Reset the minimap button's angle |
| `/cvars clearranges` | Clear all learned bounds |
| `/cvars clearrange <name>` | Clear one learned bound |
| `/cvars regex` | Toggle Lua-pattern search |
| `/cvars smooth [on\|off]` | Toggle smooth list scrolling (on by default) |
| `/cvars filters` | Show the search filter syntax |
| `/cvars help` | List the commands |

## Window controls

The second row of controls mirrors the slash commands. `Filters` opens a popup for scope, category, type, and Has facets. `Sort` picks a sort key and direction. Next come undo and redo, then `Copy`. The `.*` chip toggles regex search, and the `Size` menu in the title bar picks Auto, Compact, Standard, or Large. The minimap button can only be hidden or reset from chat (`/cvars minimap [reset]`).

Status messages clear after 30 seconds, and a new message restarts the timer. The `Filters` chip shows how many facets are active, and its popup has `Clear all`. Hover the `.*` chip or undo and redo for a tooltip. The undo and redo tooltips name the CVar they would change. The `Filters` chip has a tooltip while a facet is on, and it lists the active facets.

You can type filters into the search box and combine them:

```text
scope:account category:graphics type:number has:range changed
```

The supported filters are `scope:account|character|local`, `category:<name>`, `type:number|text|boolean|enum|list|bitfield|serialized`, `has:range|observed|help|default|changed|fav`, `value:<text>` (the current value contains the text), `value:=<text>` (the value is exactly the text), and the bare word `changed`. Values compare as the value field shows them, so bitfields match as hex. With `/cb regex` on, the rest of the text is a Lua pattern.

Bitfield and serialized values show as `Bitfield (N bytes)` or `Serialized (N bytes)`, and you edit them as hex.

## Keyboard

In the search box, Up and Down move the selection by one row and PageUp and PageDown move it by a page. Enter selects that row (or the first match) and focuses the value field. Escape clears the search text first, and a second Escape leaves the box.

When no text box has focus and the cursor is over the window, Up, Down, PageUp, PageDown, Home, and End move the selection, Ctrl+Z undoes, and Ctrl+Y or Ctrl+Shift+Z redoes. Escape closes an open menu, then clears the search, then closes the window. Every other key reaches the game as usual, and in combat the window lets every key through.

## Change log

The change log keeps the newest 200 changes across sessions. It records changes made in the browser, not ones made by the game's options menus or other addons.

## Where ranges come from

The client has no public table of CVar minimum and maximum values. The addon reads a range from the `C_Console` help text when the text has one, and it learns bounds when the client clamps a value you set. `C_Settings` and `Settings.GetSetting` only know settings registered with the Settings UI, so the addon doesn't use them.

## Development

`mockup/index.html` is the standalone visual mock. Serve the repository folder over HTTP and open `/mockup/`, because the mock loads fonts from `media/` and won't work from a `file:` URL. `DESIGN.md` holds the visual specification.

`lua tests/harness.lua` (Lua 5.1, run from the repository folder) loads every Lua file the TOC lists, in order, against headless WoW API stubs. It checks loading, scanning, set/clamp/reset, undo/redo and their shortcuts, the change log, read-only, locked, and in-combat secure selection, slash commands, copy, pattern and value search, favorites, row and control tooltips, keyboard navigation, smooth scrolling and scrollbar drags, the pixel-locked drag, and register headroom in each file, and it exits non-zero on failure. Pixel-level visuals still need an in-game `/reload`.

The addon's Lua lives in `src/`, one file per part of the window, and the TOC loads the files in dependency order. Files share code through the addon namespace. A new file has to be added to the TOC too, and CI checks that the two match.

CI (`.github/workflows/ci.yml`) runs `luac -p` and the harness on every push to `main` and on every pull request. To cut a release, push a tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Tags must be `vMAJOR.MINOR.PATCH` with no leading zeros. Once the tests pass, CI writes the version and an `X-Build` line (short commit hash and commit date) into the TOC, builds `CVarBrowser-<version>.zip`, and publishes a GitHub release with generated notes. The zip has a single `CVarBrowser/` folder holding the TOC, the Lua files in `src/`, `README.md`, and only the fonts the addon loads from `media/`. Releases are immutable once published, so a tag name can't be reused even after its release is deleted, and `v*` tags can't be moved.

The checked-in TOC always says `## Version: dev` (CI checks this). The window's subtitle shows `WoW Forever · v1.0.1 · afaa9bd` for a release build and `WoW Forever · dev` for a copy of the repository.
