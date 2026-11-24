# CVar Browser agent rules

## Design ownership

- **Designer owns the look.** `DESIGN.md` is the visual specification, and
  the `designer` agent owns it along with every visual decision: palettes,
  type, layout, gauges, semantic keys, and visual states.
- The main assistant MUST delegate design decisions and `DESIGN.md` edits to
  the `designer` agent, then implements the decided design in `src/`. If the
  designer is unavailable, stop and ask.
- There is no HTML mock. The Lua in `src/` is the only implementation, and
  visuals are checked in game.

## Runtime implementation

- The Lua in `src/` is the shipped implementation, loaded in the TOC's
  order: `core`, `window`, `toolbar`, `list`, `detail`, `layout`,
  `minimap`, `render`, `events`, `commands` (lowercase file names). It is
  Grim plum with a custom gauge/scrollbar/key. Size is selected from
  `Auto`, `Compact` (800×600), `Standard` (920×680), or `Large`
  (1040×760). Every preset renders at one frame unit per physical pixel
  (effective scale 768/physicalHeight, measured as `g_frame.px_per_unit`
  ≈ 1) and uses integer font sizes; Auto picks from
  physical screen height. Do not reintroduce percentage/fractional frame
  scaling.
- Hairline textures registered with `g_hairline` resize to
  `1 / g_frame.px_per_unit`, so borders stay one physical pixel. Boxes, lines,
  the custom title-bar drag, and list scroll offsets are snapped to the
  physical pixel grid; anchor offsets are frame units (verified in game).
  Single-anchor text origins snap a quarter pixel past a whole pixel
  (`TEXT_SNAP_BIAS_PX`): the client flips text to the next pixel right at a
  whole-pixel position and boxes at the half pixel (measured in game), so
  text on exact whole pixels shifts 1px on float noise. Every snapper
  ignores corrections under `SNAP_DEADBAND_PX` (0.01px), keeps the measured
  `px_per_unit`, and compares stored offsets with a tolerance because the
  client returns 32-bit floats. The value field and Set/Reset buttons use
  custom snapped borders, not backdrop edges.
- Smooth scrolling (`/cvars smooth`, on by default) steps in whole pixels via
  `g_frame.scroll_frame_to`; both the list and the filter popup use it.
- Slants are font glyphs: gauge open ends use `/` or `\` centered on the
  track edge; the footer key shows both glyphs, `/` and `\`, with a gap.
  Glyph rendering stays crisp at integer font sizes.
- Favorites live in `g_frame.db.favorites[canonicalName]` and always sort first.
  The row toggle's diamond is drawn from 1px textures
  (`g_frame.create_diamond`) because no bundled font has a star glyph.
- The change log is `g_frame.db.log` (newest 200, oldest first). Only browser
  sets, resets, undos, and redos are logged, not external `CVAR_UPDATE`s.
- The window takes keyboard input only out of combat and, for list keys and
  the Ctrl+Z, Ctrl+Y, and Ctrl+Shift+Z shortcuts, only while the cursor is
  over it. `SetPropagateKeyboardInput` is combat-restricted since 10.1.5, so
  OnKeyUp and `PLAYER_REGEN_DISABLED` restore propagation to true. Never
  leave it false.
- The tooltip is one custom panel (`g_frame.tooltip`), not `GameTooltip`.
  It serves rows, favorite toggles, and toolbar controls that define a
  `tooltip_text` function.
- Minimap button lives on `Minimap`, saves `g_frame.db.minimap_angle`, drags around
  the ring, and toggles the browser on left-click. Keep the button globally
  named and its icon globally named `<Button>Icon`, created last, for
  minimap-button collectors; the TOC also exposes the Addon Compartment.
- Use Lua 5.1-compatible syntax. Custom functions are snake_case; WoW APIs are
  localized at the top; constants and colors live near the top.
- File-scope mutable state and widget handles use a `g_` prefix (`g_frame`,
  `g_search_box`, `g_entries`). UPPERCASE constants, localized
  WoW APIs, and helper functions keep their names, as do locals scoped inside
  `do ... end` construction blocks. `METRICS` stays uppercase: it is a layout
  table whose fields `apply_ui_scale` rewrites. Never reuse a `g_` name for a
  function local or parameter. `tests/harness.lua` follows the same rules:
  shared setup (such as Scan) stays at file scope with `g_` names, and every
  other test section keeps its locals inside its own `do ... end` block.
- Files share code through the addon namespace (`local _, ns = ...`). Each
  file localizes the WoW APIs it uses from globals, imports what earlier
  files define (`local trim = ns.trim`) at the top, and ends with
  `ns.name = name` for what later files use. A file may only use what an
  earlier file exported, so keep the TOC order a dependency order, and
  export only what a later file imports. Shared mutable state (`db`,
  `by_name`, `view`, `selected`, `px_per_unit`, search, filter, sort, and
  undo state) is created on `g_frame` in `core.lua`,
  because a reassigned local cannot be shared. The snap registries
  `g_frame.snap_lines` and `g_frame.snap_boxes` are also created there, and
  each file appends the widgets it builds (never reassign them). New Lua
  files go in `src/` with lowercase names and in the TOC (CI checks that both
  list the same files).
- Initialize every local explicitly (`local x = nil`, or `false`/`0`/`{}`
  when that is its type). Indent `do ... end` bodies one level, and separate
  unrelated statement groups and top-level handlers with a blank line.
- Keep each file's main-chunk register use under 190 of Lua 5.1's 200 slots
  (the harness checks every file). Prefer `do ... end` scoping for
  construction-only locals and `g_frame` fields over new file-scope locals.
- No forward function declarations. Define helpers before callers; wire frame
  scripts after the functions exist.
- Data comes from `C_Console.GetAllCommands` plus `C_CVar` only. No binary
  reverse engineering. `C_CVar.GetCVarInfo` returns value, default,
  account-wide, per-character, locked, secure, read-only (verified in game:
  `uiScale` → `"1"`, `"1.000000"`, …); read the current value from
  `C_CVar.GetCVar`.
  Writability is only known from the `C_CVar.SetCVar` result.
- Keep `luac -p src/*.lua` and `luacheck src` clean and
  `lua tests/harness.lua` passing; CI runs all three on every push to `main`
  and every pull request. A new client global goes in `.luacheckrc`. Add a
  harness check for new behavior, and confirm it fails when the behavior is
  broken. Visual verification still requires an in-game `/reload` and
  `/cvars`.
- Slash commands are handlers in two tables in `commands.lua`: `exact`
  (the whole line) and `worded` (keyed by the first word, returning false
  to fall through to the search). `CVAR_UPDATE` is ignored while the window
  is hidden, because showing it rescans. `apply_range` drops an observed
  bound once the value has passed it. `CVarBrowserDB.version` gates saved
  variable migrations in `init_db`. `clearlog` and `clearranges` wipe saved
  data, so they go through `confirmed` and need sending twice. A value is
  `serialized` (shown as hex) only when it has control bytes or is not
  valid UTF-8.

## Comments and prose

- Write comments in plain, concise sentences a human can skim (the humanizer
  skill's rules). In comment prose, use no semicolons, colons, or em/en
  dashes; use periods, commas, or parentheses instead. Exceptions are a
  `TODO:` marker and colons that belong to code, such as `frame:Show()`.
- README.md follows the same humanizer rules. AGENTS.md and DESIGN.md are
  agent-owned and are not humanized.
- Strings the player reads (status lines, chat lines, tooltips) follow the
  humanizer rules too: plain sentences, no semicolons or em/en dashes.
  Colons are fine only as labels (`Default: 5`, `Type: Number`) and inside
  search syntax (`scope:account`).
- Commit messages follow the humanizer rules too: a plain, concise subject
  and body with no semicolons, colons, or em/en dashes in the prose (code,
  paths, and identifiers in backticks are fine). Never rewrite published
  history to change a message, because release tags and shipped X-Build
  hashes point at those commits.
- Text files use LF line endings (`.gitattributes`); fonts are binary.

## CI and releases

- `.github/workflows/ci.yml` tests on push and pull request. A
  `vMAJOR.MINOR.PATCH` tag (no leading zeros) also packages
  `CVarBrowser-<version>.zip` and publishes an immutable GitHub release. The
  zip holds one `CVarBrowser/` folder with the TOC (`## Version` from the
  tag plus `## X-Build: <hash> <date>`), the TOC's `src/*.lua` files,
  `README.md`, and only the fonts the Lua loads via `MEDIA_PATH .. "<file>"`.
  Change the Package and Verify steps together. The checked-in TOC stays
  `## Version: dev` (CI enforces it); the title-bar subtitle shows the build
  per DESIGN.md. Immutable release tags can never be reused, even after the
  release is deleted.
- The repository only allows GitHub-owned actions, pinned to a full commit
  SHA with a `# vX.Y.Z` comment. A third-party action needs an allowlist
  change in repository settings first. Dependabot bumps the pins weekly.
- `main` and `v*` tags are protected by rulesets: no deletion or force push,
  signed commits on `main`, and tags cannot be moved. Admins can bypass.
