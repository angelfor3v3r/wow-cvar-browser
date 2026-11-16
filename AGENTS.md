# CVar Browser mockup ownership

- **Designer owns the mock.** Every GUI mockup/design change for this addon is
  owned by the `designer` agent: `mockup/**`, `DESIGN.md`, palettes, type,
  layout, gauges, semantic keys, and visual states.
- The main assistant MUST delegate design decisions and file edits to the
  `designer` agent. It may only start the local server, take screenshots, run
  `node --check`, check browser console/behavior, and report.
- The main assistant MUST NOT make visual/design edits itself. If the designer
  is unavailable, stop and ask.
- No Lua/addon implementation or refactor during mockup work unless explicitly
  requested.

## Runtime implementation

- `CVarBrowser.lua` is the shipped implementation: Grim plum and a custom
  gauge/scrollbar/key. Size is selected from `Auto`, `Compact` (800×600),
  `Standard` (920×680), or `Large` (1040×760). Every preset renders at
  effective scale 1.0 and uses integer font sizes; Auto picks from physical
  screen height. Do not reintroduce percentage/fractional frame scaling.
- Hairline textures registered with `hairline` resize to `1 / effective_scale`,
  so borders stay one physical pixel. Boxes, lines, and drag are snapped to
  the physical pixel grid; text is crisp only because effective scale is 1.0.
  The value field and Set/Reset buttons use custom snapped borders, not
  backdrop edges.
- Slants are font glyphs: gauge open ends use `/` or `\` centered on the
  track edge; the footer key shows both glyphs, `/` and `\`, with a gap.
  Glyph rendering stays crisp at integer font sizes.
- Minimap button lives on `Minimap`, saves `db.minimap_angle`, drags around
  the ring, and toggles the browser on left-click. Keep the button globally
  named and its icon globally named `<Button>Icon`, created last, for
  minimap-button collectors; the TOC also exposes the Addon Compartment.
- Use Lua 5.1-compatible syntax. Custom functions are snake_case; WoW APIs are
  localized at the top; constants and colors live near the top.
- No forward function declarations. Define helpers before callers; wire frame
  scripts after the functions exist.
- Data comes from `C_Console.GetAllCommands` plus `C_CVar` only. No binary
  reverse engineering. `C_CVar.GetCVarInfo` returns canonical name, default,
  account-wide, per-character; read the current value from `C_CVar.GetCVar`.
  Writability is only known from the `C_CVar.SetCVar` result.
- Keep `luac -p CVarBrowser.lua` clean. A headless WoW API stub harness should
  cover load, `ADDON_LOADED`, scan, set/clamp/reset, and read-only selection;
  visual verification still requires an in-game `/reload` and `/cvars`.
