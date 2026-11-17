# CVar Browser

A searchable, editable browser for every console variable exposed by the WoW Forever client.

## Install

1. Copy this repository into `Interface/AddOns/CVarBrowser`.
2. Restart the client (or `/reload` if the addon was already loaded).
3. Run `/cvars` or `/cb`.

## Features

- Search CVars by name or help text.
- Live current values, defaults, account/character scope, and category.
- Editable values with clamp/normalization feedback and reset-to-default.
- Undo/redo the last successful set.
- Read-only, secure, changed-only, and observed-bound indicators.
- Learned clamp bounds with listing and clear-one/all.
- Custom 88×8 range gauge per row.
- Draggable minimap button and Addon Compartment entry.
- Saved window position.
- **Auto / Compact / Standard / Large** layout presets. Each preset uses a 1:1 pixel grid and integer font sizes; Auto picks from physical screen height.

## Slash commands

- `/cvars` or `/cb` — toggle the browser
- `/cvars <name>` — open, search, and select a CVar
- `/cvars refresh` — rescan
- `/cvars undo` — undo the last successful set
- `/cvars redo` — redo the last undo
- `/cvars ranges [name]` — list learned clamp bounds, optionally for one CVar
- `/cvars sort name|type|scope|category|changed|range [asc|desc]` — sort rows
- `/cvars copy [value|raw|default|name|help|range] [cvar]` — show the text highlighted in a copy box; press Ctrl+C (addons can't write the clipboard)
- `/cvars minimap` — hide/show the minimap button
- `/cvars minimap reset` — reset its angle
- `/cvars clearranges` — clear learned bounds
- `/cvars clearrange <name>` — clear one learned bound
- `/cvars regex` — toggle Lua-pattern search
- `/cvars smooth [on|off]` — toggle smooth list scrolling (on by default)
- `/cvars filters` — show search-filter syntax
- `/cvars help` — list commands

## GUI controls

The second control row exposes the same filters and sort state as the slash commands: a `Filters` popup (scope, category, type, Has facets), a `Sort` menu with direction, undo/redo buttons, and a `Copy` menu. The `.*` chip toggles regex search. The title-bar `Size` menu offers `Auto`, `Compact`, `Standard`, and `Large`. Each preset renders one UI unit per physical pixel with integer font sizes; `Auto` chooses from physical screen height. The old percentage UI scaling is gone. The minimap button and its angle remain command-only (`/cvars minimap [reset]`).

Status messages clear automatically after 30 seconds; a new status resets the timer. The `Filters` chip shows the active facet count and its popup has `Clear all`.

Search filters are typed into the search box and can be combined:

```text
scope:account category:graphics type:number has:range changed
```

Supported: `scope:account|character|local`, `category:<name>`,
`type:number|boolean|enum|text|list|bitfield|serialized`,
`has:range|observed|help|default|changed`, and the bare token `changed`.
With `/cb regex` enabled, the remaining text is treated as a Lua pattern.
Up/Down in the search box moves the selection; Enter focuses the value field.

Serialized/binary values are shown as `Serialized (N bytes)` and edited as hex.

## Range sources

The client exposes no public table of CVar min/max bounds. `C_Console` help text is parsed when it contains a range, and clamp attempts add learned observed bounds. `C_Settings`/`Settings.GetSetting` only cover settings registered with the Settings UI and do not expose arbitrary CVar bounds, so the addon does not rely on it.

## Development

`mockup/index.html` is the isolated visual mock; serve the folder over HTTP rather than opening it with `file:`.

`DESIGN.md` records the final visual specification.

`lua tests/harness.lua` (Lua 5.1, run from this folder) loads the addon against headless WoW API stubs and checks load, scan, set/clamp/reset, undo/redo, read-only and in-combat secure selection, slash commands, copy, pattern search, smooth scrolling, the pixel-locked drag, and main-chunk register headroom. It exits non-zero on failure. Visual pixel checks still need an in-game `/reload`.
