# CVar Browser agent rules

## Mockup ownership

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
  `Standard` (920×680), or `Large` (1040×760). Every preset renders at one
  frame unit per physical pixel (effective scale 768/physicalHeight, measured
  as `g_px_per_unit` ≈ 1) and uses integer font sizes; Auto picks from
  physical screen height. Do not reintroduce percentage/fractional frame
  scaling.
- Hairline textures registered with `g_hairline` resize to
  `1 / g_px_per_unit`, so borders stay one physical pixel. Boxes, lines,
  single-anchor text origins, the custom title-bar drag, and list scroll
  offsets are snapped to the physical pixel grid; anchor offsets are frame
  units (verified in game). The value field and Set/Reset buttons use custom
  snapped borders, not backdrop edges.
- Smooth scrolling (`/cvars smooth`, on by default) steps in whole pixels via
  `g_frame.scroll_frame_to`; both the list and the filter popup use it.
- Slants are font glyphs: gauge open ends use `/` or `\` centered on the
  track edge; the footer key shows both glyphs, `/` and `\`, with a gap.
  Glyph rendering stays crisp at integer font sizes.
- Minimap button lives on `Minimap`, saves `g_db.minimap_angle`, drags around
  the ring, and toggles the browser on left-click. Keep the button globally
  named and its icon globally named `<Button>Icon`, created last, for
  minimap-button collectors; the TOC also exposes the Addon Compartment.
- Use Lua 5.1-compatible syntax. Custom functions are snake_case; WoW APIs are
  localized at the top; constants and colors live near the top.
- File-scope mutable state and widget handles use a `g_` prefix (`g_db`,
  `g_frame`, `g_selected`, `g_search_box`). UPPERCASE constants, localized
  WoW APIs, and helper functions keep their names, as do locals scoped inside
  `do ... end` construction blocks. `METRICS` stays uppercase: it is a layout
  table whose fields `apply_ui_scale` rewrites. Never reuse a `g_` name for a
  function local or parameter. `tests/harness.lua` follows the same rules:
  shared setup (such as Scan) stays at file scope with `g_` names, and every
  other test section keeps its locals inside its own `do ... end` block.
- Initialize every local explicitly (`local x = nil`, or `false`/`0`/`{}`
  when that is its type). Indent `do ... end` bodies one level, and separate
  unrelated statement groups and top-level handlers with a blank line.
- Keep main-chunk register use under 190 of Lua 5.1's 200 slots (the harness
  enforces it). Prefer `do ... end` scoping for construction-only locals and
  `g_frame` fields over new file-scope locals.
- No forward function declarations. Define helpers before callers; wire frame
  scripts after the functions exist.
- Data comes from `C_Console.GetAllCommands` plus `C_CVar` only. No binary
  reverse engineering. `C_CVar.GetCVarInfo` returns value, default,
  account-wide, per-character, locked, secure, read-only (verified in game:
  `uiScale` → `"1"`, `"1.000000"`, …); read the current value from
  `C_CVar.GetCVar`.
  Writability is only known from the `C_CVar.SetCVar` result.
- Keep `luac -p CVarBrowser.lua` clean and `lua tests/harness.lua` passing;
  CI runs both on every push to `main` and every pull request. Add a harness
  check for new behavior, and confirm it fails when the behavior is broken.
  Visual verification still requires an in-game `/reload` and `/cvars`.

## Comments and prose

- Write comments in plain, concise sentences a human can skim (the humanizer
  skill's rules). In comment prose, use no semicolons, colons, or em/en
  dashes; use periods, commas, or parentheses instead. Exceptions are a
  `TODO:` marker and colons that belong to code, such as `frame:Show()`.
- README.md follows the same humanizer rules. AGENTS.md and DESIGN.md are
  agent-owned and are not humanized.
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
  tag plus `## X-Build: <hash> <date>`), `CVarBrowser.lua`, `README.md`, and
  only the fonts the Lua loads via `MEDIA_PATH .. "<file>"`. Change the
  Package and Verify steps together. The checked-in TOC stays
  `## Version: dev` (CI enforces it); the title-bar subtitle shows the build
  per DESIGN.md. Immutable release tags can never be reused, even after the
  release is deleted.
- The repository only allows GitHub-owned actions, pinned to a full commit
  SHA with a `# vX.Y.Z` comment. A third-party action needs an allowlist
  change in repository settings first. Dependabot bumps the pins weekly.
- `main` and `v*` tags are protected by rulesets: no deletion or force push,
  signed commits on `main`, and tags cannot be moved. Admins can bypass.
