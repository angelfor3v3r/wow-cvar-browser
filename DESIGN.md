# CVar Browser — UI design

Visual reference: `mockup/index.html` (live HTML mockup). It is the source of
truth for the current GUI direction.

Chosen direction: **Instrument bench**, compact, plum-dark, with muted lilac
accents. The mockup was reviewed against `skill://frontend-design`; the design
below incorporates that critique.

## Goals

- A dense data browser, not a settings page.
- Readable at 13px on a dark, low-glare surface.
- One screen does the whole job: search, inspect, edit, reset.
- Make uncertainty visible: help-derived bounds, observed bounds, changed
  values, read-only CVars, and refused/ignored/clamped sets.
- The per-row gauge is the memorable visual element, not decoration.

## Constraints

- WoW Forever 1.60.1 (interface 11509, 16001), Lua 5.1.
- Runtime: no HTML/CSS, flexbox, border-radius, or web fonts.
- Textures and FontStrings only; 1px borders are drawn with textures.
- Runtime fonts: NotoSans-Regular/SemiBold for chrome and data,
  Inter-SemiBold for the check glyph only. Bundled in `Media/`.
- IBM Plex, Manrope, Space Grotesk, and JetBrains Mono are mock-preview
  only, not runtime.
- No Lua refactor is part of the mockup phase.

## Visual language

Flat near-black with a faint plum cast. 1px hairlines, square corners, no
gloss, no gradients, no drop shadows, no ornate Blizzard chrome. Popups
(menus, the copy box) are a `surface` fill with a 1px border (`border`;
`accent` on the always-focused copy box) and no shadow, matching the
runtime's flat frames. The window renders on a 1:1
pixel grid: one UI unit is one physical screen pixel. The frame's effective
scale is 768 / physical screen height (UI space is 768 units tall), whatever
the client `uiScale` — it is not 1.0 — so every border and separator is
exactly 1 physical pixel and the hairlines stay separable from the meta line
at every size preset. Positions stay on the grid too: the title-bar drag,
single-anchor text origins, and list and popup scroll offsets all land on
whole pixels.

### Primary palette: Grim plum

| Token | Hex | Use |
| --- | --- | --- |
| `background` | `#121114` | Window body |
| `surface` | `#1A181C` | Inputs, buttons, panels |
| `surface_hover` | `#232126` | Hover |
| `border` | `#343138` | Default 1px border |
| `text` | `#EDEAF2` | Primary text |
| `text_muted` | `#9A929F` | Meta, headers, placeholders |
| `accent` | `#B7A3CC` | Selection, focus |
| `observed` | `#68C3B9` | Observed bounds, observed meta |
| `warning` | `#E0A857` | Clamp status, clamp edge cap |
| `success` | `#63C98A` | Accepted/reset status |
| `error` | `#E06A72` | Ignored/refused status |
| `changed` | `#D2BFE6` | Changed CVar name and cursor |
| `--dot` | `#504C54` | Unknown-range dot (gauge and key); fixed across palettes |

The lilac has three quiet steps: `changed` lilac marks values that differ from
default, `accent` lilac marks selection and focus, and `text` stays the
brightest. Neither lilac drifts toward bright purple or fuchsia. The
background is near-neutral so the lilacs are the only chroma in the window;
the observed teal is muted to instrument levels to stay a supporting voice.

This lilac rule is a design-language invariant, not Grim-specific: in every
palette the `changed` highlight and the `accent` are muted lilacs — bright
purple and fuchsia appear nowhere. Palette identity lives in the surfaces,
neutrals, and semantic hues instead. The mockup's alternate palettes are
Void amethyst, Nebula, and Dark orchid, all retuned to the invariant.

### Type

NotoSans-Regular/SemiBold carries everything at runtime: chrome, help, CVar
names, and values. Inter-SemiBold draws the check glyph only. The mockup's
font pickers (Inter, IBM Plex Sans, Manrope, Space Grotesk, JetBrains Mono)
are preview affordances, not runtime fonts.

| Role | Font | Compact | Standard | Large | Weight |
| --- | --- | --- | --- | --- | --- |
| Window title | Noto Sans | 18 | 20 | 23 | SemiBold |
| Detail name | Noto Sans | 13 | 15 | 17 | SemiBold |
| Rows, values, help | Noto Sans | 12 | 13 | 15 | Regular |
| Meta / hints | Noto Sans | 10 | 11 | 12 | Regular |
| CVar names / values | Noto Sans | 12 | 13 | 15 | Regular |
| Check glyph | Inter | 12 | 14 | 16 | SemiBold |

Sizes are integers fixed per size preset — no fractional sizes and no
percentage scaling. Rows are 22px; help tracks body size. Standard is the
documented reference and what the mockup renders (row 22, meta 11, help 13,
detail name 15, title 20). The mockup's 13/14/15/16 text-size switch is a
preview stress affordance only, not a runtime control: each step up adds 2px
to the row and 1px to meta and detail name. Numeric values use tabular
figures so columns scan cleanly.

### Spacing

4 / 8 / 12 / 16 / 24px. Window 800×600 / 920×680 / 1040×760 — Compact /
Standard / Large; the mockup renders the Standard reference at 920×680.
Buttons are snug: 4px label padding on each side with per-control floor
widths — Set 30, Reset to default 64, Copy 30, Clear all 40, close 24,
undo/redo 24 — and the floor only applies below the label's natural width.
The title-bar Size box has no floor: it is always label width + 8.

## Size presets

The title-bar **Size** menu offers Auto / Compact / Standard / Large. Size
comes only from these presets; the old percentage-based scaling control is
gone entirely. Every preset renders on the same 1:1 grid, one UI unit per
physical screen pixel (see Visual language), with the integer font sizes
from the type table above.

| Preset | Window | Detail panel | Title / detail / body / meta / check |
| --- | --- | --- | --- |
| Compact | 800×600 | 124px | 18 / 13 / 12 / 10 / 12 |
| Standard | 920×680 | 132px | 20 / 15 / 13 / 11 / 14 |
| Large | 1040×760 | 148px | 23 / 17 / 15 / 12 / 16 |

**Auto** resolves from the physical screen height: 1080px or below picks
Compact, 1800px or above picks Large, everything between picks Standard. The
choice is saved; the default is Auto. The mockup holds the Standard reference
geometry (920×680) in every case — picking a preset there updates the Size
label and menu selection only.

## Layout

```text
┌──────────────────────────────────────────────────────────────────────┐
│  CVar Browser   WoW Forever                       [Size: Auto]   ×   │
├──────────────────────────────────────────────────────────────────────┤
│  [ Search CVars... ] [.*] [ ] Changed only   21 / 21 CVars, 7 range  │
│  [Filters 2][Sort changed] [↩][↪] [Copy]                             │
│  CVar                              Gauge                 Value        │
│  ──────────────────────────────────────────────────────────────────  │
│  assaoFadeOutTo                    ────────┐             50.0        │
│  nameplateMaxDistance         ┌─────┃┃─────┘  45 (Default: 40)      │
│  farclip                              ·                             │
│  ...                                                                  │
│                                                         ▐ scrollbar  │
├──────────────────────────────────────────────────────────────────────┤
│  assaoFadeOutTo                                                      │
│  Account │ Graphics │ Default: 50.0 │ Range help: 0.0 - open         │
│  ASSAO Fade Out To [0.0, ~ ] Distance at which the effect fades out. │
│  [ 50.0                    ] [ Set ] [ Reset to default ]  status    │
├──────────────────────────────────────────────────────────────────────┤
│  Differs from default  ┃┃ Observed bounds  □ Read-only  ┃ Current value │
│  Slanted end [slants] means no limit. Dot [dot] means no known range.  │
└──────────────────────────────────────────────────────────────────────┘
```

The toolbar keeps its row (search, regex toggle, Changed only, count); a
second 26px control row holds filters, sort, history, and copy.
Everything below shifts down 28px: the list header divider sits at y=148,
the list body runs y=152–492, and the scrollbar column spans the new header
divider down to the unchanged detail separator (y=496). Detail and semantic
key geometry is untouched.

## Gauge

88×8px track, one per row. Rows are locally scaled; gauges are not comparable
across rows. Domain is the union of help and observed bounds.

- **Help bounds**: 1×3px muted hairline ticks at min/max; 1px track between.
- **Observed bounds**: 1×6px muted-teal ticks, rows 1–6 of the 8px gauge.
  Draw both when help and observed differ.
- **Current value**: 2px × 8px cursor in primary text; changed lilac when the
  value differs from default.
- **Open bound**: a single font glyph at the open end — `/` for a missing
  minimum, `\` for a missing maximum — centered on the track edge. No cap and
  no stroke texture.
- **Pixel grid**: every drawn mark is an unrotated, integer-snapped texture —
  track 88×1 on row 3, help ticks 1×3 (rows 2–4), observed ticks 1×6
  (rows 1–6), cursor and clamp cap 2×8. A w×h mark centers on its value's
  x: left edge `round(x − w/2)`, capped at the last track column (87) so a
  tick at the max lands on the track; top `floor((8 − h)/2)`. Open ends
  are font glyphs, not textures. The mockup draws the track and marks as
  SVG rects with the same placement, under `shape-rendering: crispEdges`
  at 1x; its SVG slashes stand in for the runtime glyphs.
- **No bounds**: blank track plus one centered 2px `--dot` dot.
- **Clamp**: 2px amber edge cap beside the cursor; amber status line. Clamp is
  transient, not a stored observed bound.
- Empty gauge has an accessible label/title.

## Components

- **Root**: `BackdropTemplate`, 1px border, `DIALOG` strata, movable, clamped.
- **Title bar**: 44px drag region; title, subtitle, boxed `Size` menu button
  (exactly `round(label width + 8)` × 24px — the label 4px from each edge,
  no minimum width — 1px `border`, `surface` fill, muted, its right edge
  12px before the close, custom `×` close fitted to 24×28px). The box label
  is title-bar meta — `Size: Auto` or `Size: <preset>` — pinned to the meta
  size (11px at Standard) with nowrap; the box tracks its label at every
  text size, so the label stays on one line and the right edge holds still
  while the box grows or shrinks leftward. Hover or open state raises the box to
  `surface_hover` with an accent border and primary text. Click opens the
  size menu: a 126px popup right-aligned under the box, 22px rows Auto /
  Compact / Standard / Large. The current preset is accent text behind a 2px
  accent left bar — the selected-row language, not a tick. Picking a preset
  applies it and closes the menu; Escape or an outside click closes it too.
- **Search**: custom dark edit box, accent focus border, placeholder. The
  magnifier is 14×14 at 4px from the box's left edge, vertically centered;
  the caret and text start at x=22 (icon right edge + 4px gap). The
  placeholder hides while the box has focus and returns on blur when the
  box is empty.
- **Regex toggle**: compact `.*` chip flush against the search box (the search
  row is 300px wide to make room). Off = muted; on = accent text and border
  with a 2px accent underline along the chip's bottom edge. Underline, not
  fill: it is a mode of the search box, not a filter. Tooltip states the
  behavior.
- **Changed only**: custom 18px checkbox with drawn tick; whole row clickable.
  The button is a borderless hit area — [18px box][8px gap][`Changed only`]
  text — and the tick sits 1px right of the box's geometric center (the
  runtime anchors its ✓ glyph at the center + 1px). The box frame is a
  uniform 1px border on all four sides, integer-snapped — fractional
  placement/scale is what produced the 1px-left, 2px-elsewhere frame in
  game.
- **Count**: `visible / total CVars, N with range`, muted, right aligned.
  Empty result set reads `0 / N CVars` and the list shows a muted empty
  state: "No CVars match. Clear filters or change the search."
- **Control row** (26px, directly under the toolbar): four grouped controls,
  8px gaps. Every control is 26px tall, so the row reads as one band (the
  detail row's buttons stay 30px). All controls are `surface` fills with 1px
  `border`, square corners, 11px labels; hover raises to `surface_hover` +
  accent border.
  - **Filters chip**: 10×9 funnel glyph at 4px from the chip's left edge +
    one label string at x=18 (icon + 4px gap): `Filters off` at rest,
    `Filters <count>` (e.g. `Filters 2`) when filters are on — a single
    text run with an ordinary space, no separate summary slot. Width is
    `18 + label + 6` (6px right padding), 80px minimum. The label is `text`
    and the glyph `muted` at rest; with filters on, label, glyph, and border
    all turn accent. Hover raises only the fill and border. Tooltip
    lists the active facets as `scope:account, has:changed`. Click opens the
    filter menu below the chip.
  - **Filter menu**: popup panel (`surface`, 1px border, no radius),
    grouped rows with 11px muted group labels — Scope (All / Account /
    Character / Local), Category (All + the categories present in the
    list), Type (All / Number / Text / Boolean / Enum / List / Bitfield /
    Serialized, a fixed list; see Value type), Has (Range / Observed
    bounds / Help range / Default / Differs from default). Scope, category,
    and type are single-select; Has is multi-select and ANDs. Checked rows
    show the same drawn tick as the checkbox. The header reads `Filters`
    with a right-aligned **Clear all** button (disabled when nothing is
    active); Clear all resets the four facets and Changed only, not the
    search text or regex mode. Menu stays open while toggling so several
    facets can be set in one pass; its scroll position holds across
    re-renders so a toggle never yanks the list back to the top.
  - **Popup height rule**: no popup may exceed the window. The control
    row's menus open at y=130 in the 678px content box and are capped at
    536px tall (12px of air above the window edge); taller content — the
    filter menu at its natural ~686px — scrolls inside the panel over an
    8px muted thumb in the list-scrollbar language. The wheel glides the
    panel 40px per notch (see Scrolling). The control row's menu
    rows are a fixed 24px with nowrap labels, so reachability is identical
    at 13/14/15/16 text sizes: the Has group always ends up behind the same
    ~150px of scroll and every row is reachable in all cases. Opening upward
    is not an option — the control row sits near the window's top edge.
  - **Sort chip**: 10×10 sort glyph at 4px from the chip's left edge + one
    label string at x=18 (icon + 4px gap): `Sort <key> <dir>`, e.g.
    `Sort name asc` or `Sort changed desc`, a single text run with ordinary
    spaces. Width is `18 + label + 6`, 100px minimum. Colors follow the
    Filters chip: `text` label and `muted` glyph at the default sort (name
    asc); label, glyph, and border accent otherwise. Click opens the sort
    menu: Name, Type, Scope,
    Category, Changed, Range width — the six keys of `/cvars sort`. The
    active row is ticked and its direction shown in a muted trailing note.
  - **Undo / Redo**: two snug icon buttons (24×26px minimum) carrying the
    undo/redo arrows and tooltips with the shortcuts. The arrow glyphs sit
    1px left and 2px below the button's center — the arrow ink sits
    top-right in its em box — and the mockup's 12×12 SVG marks carry the
    same offset from the button's center (a font glyph's ink center moves
    with each font's metrics; the marks are drawn, not glyphs). Disabled
    uses the existing `.btn` disabled treatment
    (38% opacity, no hover). Undo is disabled with an empty edit history;
    Redo is disabled with an empty redo stack. A Set or Reset clears the
    redo stack. Undo/redo restore the previous/next value of the edited
    CVar and select its row.
  - **Copy**: `Copy` button opening a compact menu — Copy value, Copy raw
    value, Copy default, Copy name, Copy help, Copy range — mirroring
    `/cvars copy`. `value` is the text the value field edits (hex for
    serialized and bitfield values); `raw` is the stored string. Help/range
    rows are disabled with a muted `none` note when the CVar has none. The
    whole button is disabled when no row is selected. Addons cannot write
    the clipboard (`CopyToClipboard` is protected), so a copy row closes the
    menus and opens the copy box.
  - **Copy box**: a 280×30 popup in the copy menu's slot — TOPLEFT on the
    Copy button's BOTTOMLEFT, 4px down. `surface` fill, a 1px `accent`
    border, and no shadow. The accent border is there because the box only
    exists while its text has focus, so it matches the focused search box
    and value field. Inside, one edit box inset 10px from each side (2px
    text insets, so text starts 12px in), in the body font, body size,
    `text` color. It holds the copied text focused and fully highlighted —
    highlight `accent` at 35% — with the caret at the start, so long text
    shows its beginning. The status line
    reads `Press Ctrl+C to copy <field>: <cvar name>`, where field is the
    `/cvars copy` key (`value`, `raw`, `default`, `name`, `help`, `range`).
    Escape, Enter, or losing focus closes it, and closing the menus closes
    it too. Typing changes nothing: the text snaps back and stays
    highlighted. A field with no text (a blank default) opens no box; the
    runtime says `nothing to copy for <cvar>` in chat (the mockup uses the
    status line).
- **List header**: 11px muted labels raised 1px — center offset +1 in the
  16px header band — for 3px clearance above the separator, whose 1px line
  runs along the band's bottom to the scrollbar column's right edge — the
  same right end as the detail separator, so the two separators bracket the
  scrollbar.
- **Rows**: 22px; selected rows get the accent fill + 2px left accent bar.
  The `surface_hover` fill shows only while the pointer is over a row that
  is not selected: selecting the hovered row clears it, and after a scroll
  it follows whatever row is now under the pointer, never the row that used
  to be there. The partly scrolled-off top row is always drawn: the first
  drawn row is `floor(offset / 22)`, so a mid-row offset clips that row at
  the list edge instead of leaving an empty strip.
- **Gauge column**: 88px gauge centered in the middle column.
- **Value column**: current value in text; changed rows append a muted
  `(Default: N)`, no strikethrough; a blank default reads `(Default: empty)`.
  The detail meta repeats `Default: N` as the canonical home for defaults,
  `Default: empty` when the default is blank. Binary values never show
  their bytes in the row: a bitfield (`closedInfoFrames`) reads
  `Bitfield (N bytes)`, a serialized value (any control or high byte) reads
  `Serialized (N bytes)`, and their changed default reads
  `(Default: N bytes)`. The meta line says `Default: Bitfield (N bytes)` or
  `Default: Serialized (N bytes)`.
- **Scrollbar**: 8px flat slider in the right gutter, hidden when not needed.
  The 8px track column spans exactly between the top list divider and the
  detail separator — flush at both ends — and its right edge is flush with
  both separators' right ends. 4px track centered in the column; the 8px thumb
  fills the column. Thumb size from track height × clientHeight /
  scrollHeight; position maps `scrollTop` over the track column. Dragging
  the thumb moves the list 1:1 with the cursor, on whole pixels and with no
  easing (mockup: pointer capture); releasing it glides to the nearest
  whole row, a multiple of 22px clamped into the range, so the top row is
  never left half-clipped. The thumb is a single solid muted texture at
  alpha 1.0 in every state — fully opaque, so the track never shows through
  (no separate translucent frame); muted, not accent, because accent marks
  selection and focus only. The thumb rect is integer-snapped: x = column
  x, width = 8, right edge flush with the separators' right ends. The list
  header's 1px divider extends to the scrollbar's right edge, closing the
  gutter gap under the thumb. The mockup's 8px right gutter is intentional.
- **Detail**: separator, name, meta, help (max 2 lines), value edit
  (340×30), Set, Reset to default, status.
- **Meta line**: up to 8 parts, muted unless noted, split by 1px `border`
  separators with 9px of air on each side, in this order: scope, category,
  `Type: <type>` (see Value type),
  `Default: <default>`, `Range help: <range>` when help sets the range,
  `Observed: <evidence>` in `observed` teal when sets have been observed,
  `Help range: <range>` when the range comes from observation and help says
  something different, `Read-only` or `Locked`, and `Secure: locked in
  combat` in `warning`. Empty parts are skipped. Range help and Help range
  never appear together, so the fullest line is exactly 8 parts: nothing
  caps it lower, and the Secure part is never dropped.
- **Value type**: one inferred type drives the meta line's `Type:` part,
  the Type filter (`type:` term), and the type sort. The first rule that
  matches wins: Bitfield (a known bitfield CVar, `closedInfoFrames`),
  Serialized (the value holds a control or high byte), Enum (the help text
  holds at least two `N = label` or `N: label` pairs, labels starting with
  a letter and at most 32 characters), Unknown (no value), Boolean (`0`,
  `1`, `true`, `false`), Number, List (the value contains `,`, `;`, or
  whitespace), else Text. Unknown has no filter row.
- **Status**: one line beside the edit row, semantic tone (success, warning,
  error). Status is transient: every message — errors included — clears 30
  seconds after it appears. A new message replaces the old one and restarts
  the 30s; an empty message clears immediately. Expiry is uniform on
  purpose: the status line reports what just happened, it never holds state
  that outlives the next look.
- **Semantic key**: glossary marks with plain-language labels: changed lilac
  text = differs from default; tally ticks (12×8: two 1×6 ticks 10px apart,
  rows 1–6) = observed
  bounds; hollow square (9×9, 1px lines) = read-only; cursor (2×8) = current
  value. Entries sit 16px apart, marks 8px from their labels. The hint shows
  the marks inline as the runtime draws them: two font glyphs `/ \` in a
  14px group and the 2px `--dot` dot identical to the unknown-range dot.
  Copy: "Slanted end [slants] means no limit. Dot [dot] means no known
  range." Clamp and refused outcomes are stated by the status line when they
  happen.

## States

| State | Visual |
| --- | --- |
| Normal row | text primary; value text; cursor text |
| Hover | `surface_hover` fill on the unselected row under the pointer; never on the selected row |
| Selected | accent-tinted fill + 2px left accent bar |
| Changed CVar | name in `changed`; value text; muted `(Default: N)`; cursor `changed` |
| Help range | 3px muted ticks; meta `Range help` |
| Observed range | 6px muted-teal ticks; meta `Observed` in teal |
| Open bound | slanted end at that side (no limit) |
| Unknown range | blank track + centered dot |
| Clamped | amber status; amber edge cap; no row tint |
| Ignored/refused | red status; no row tint |
| Read-only | muted name; input/Set/Reset disabled; meta `Read-only`; hollow key mark |
| Locked | input/Set/Reset disabled; meta `Locked`; name keeps its color |
| Secure | meta `Secure: locked in combat` in warning, in and out of combat |
| Secure in combat | Set/Reset disabled; warning status |
| Selected changed row | accent selection bar; changed name stays changed lilac |
| Filters active | Filters chip label `Filters N`, glyph, and border in accent; tooltip lists facets |
| Sort non-default | Sort chip label, glyph, and border in accent |
| Regex on | `.*` chip accent text/border with accent bottom underline |
| Undo/redo unavailable | icon button at 38% opacity, no hover, no click |
| Copy unavailable | Copy button disabled (no selection) |
| Copy field missing | menu row disabled with muted `none` note |
| Copy box open | 280×30 box under Copy, `accent` border, text highlighted; status `Press Ctrl+C to copy <field>: <cvar>` |
| Empty result set | muted empty-state line in the list; count `0 / N CVars` |
| Menu open | popup below its chip or box; the opener keeps its accent border while open |

## Interaction

- `/cvars` / `/cb` toggle the window; `/cvars <name>` opens, searches,
  selects, and focuses the value field; `/cvars refresh` rescans; `/cvars
  undo` / `/cvars redo`; `/cvars ranges`; `/cvars regex`; `/cvars filters`;
  `/cvars sort name|type|scope|category|changed|range`; `/cvars minimap
  [reset]`; `/cvars copy [value|raw|default|name|help|range] [cvar]` opens
  the copy box with that field (see Copy box); `/cvars smooth [on|off]`
  sets smooth scrolling (no argument flips it); `/cvars clearranges` clears
  observed bounds; `/cvars clearrange <name>` clears one.
- Search filters by name or help text and supports `scope:`, `category:`,
  `type:`, `has:`, and `changed` filters. Up/Down moves the selection
  through the results and glides the selected row to the top of the list.
  Enter selects the row picked with Up/Down — or, with no arrow navigation
  since the search text last changed, the first result — then focuses the
  value field (unless the CVar is read-only, locked, or secure in combat).
  With no results Enter leaves the search box. The filter and sort chips
  are the visual face of these command filters: selecting facets in the
  filter menu is equivalent to typing the same `scope:`/`type:`/`has:`
  terms, and both routes combine into one filter set. The regex chip
  switches the search box between literal and regular-expression matching
  (an invalid pattern simply matches nothing).
- Filter menu: click the Filters chip to open; the menu stays open while
  facets toggle so several can be set in one pass. Scope/category/type are
  single-select (picking one replaces the previous); Has facets are
  multi-select and AND together with everything else. Clear all resets all
  facets and Changed only in one action; search text and regex mode stay.
  Escape or an outside click closes any open menu.
- Sort menu: click a sort key to sort by it; clicking the active key flips
  asc/desc. Selecting `changed` starts desc (changed rows first); the other
  keys start asc. Keys compare lowercase (type sorts by the value type's
  name); the direction flips only the key, and ties always fall back to
  name ascending. Rows with no range width sort last in both directions.
  The chip always shows the live `key dir`.
- Size menu: click the Size box in the title bar and pick Auto, Compact,
  Standard, or Large to apply that preset — window geometry and the integer
  font sizes change with it, and the choice is saved. Auto resolves by
  physical screen height (see Size presets).
- Undo/redo: every accepted Set or Reset pushes one history entry and
  clears the redo stack. Undo restores the previous value (selecting that
  row); redo re-applies it. Disabled buttons cannot fire. Shortcuts:
  Ctrl+Z, Ctrl+Y, Ctrl+Shift+Z — not intercepted while an edit box has
  focus, so native text undo keeps working.
- Copy: a menu row closes the menus and opens the copy box holding the
  selected CVar's value, raw value, default, name, help, or range text; the
  status line asks for Ctrl+C. Disabled with no selection.
- Minimap: command-only, no window controls. `/cvars minimap` toggles the
  minimap icon; `/cvars minimap reset` snaps the icon back to its default
  position. The hidden state persists for the session.
- Bitfield and serialized values edit as hex in the value field: two
  uppercase digits per byte, so status lines show hex too. Set ignores
  whitespace; an odd-length or non-hex entry fails with `Bitfield/serialized
  value must be an even-length hex string.`
- Click a row to select. Edit the value; Enter or Set applies.
- Escape closes when no edit box has focus.
- Wheel and scrollbar scroll the list (see Scrolling); the scrollbar thumb
  must track the viewport exactly, including after font, size, or filter
  changes.

## Scrolling

Smooth scrolling is on by default; `/cvars smooth [on|off]` sets it. Every
offset, list and filter popup, smooth or not, is a whole pixel.

- **Easing**: a smooth scroll sets a target and glides to it. Each frame
  moves `round(diff × min(1, elapsed × 16))` px toward the target, at least
  1px, and the last step lands exactly on the target. With smooth off, the
  same requests jump straight to the target.
- **List wheel**: 3 rows (66px) per notch. Each notch adds onto the pending
  target rather than the current offset, so a fast spin accumulates.
- **Thumb drag**: the list follows the thumb 1:1 while held, with no
  easing. On release it glides to the nearest whole row (a multiple of
  22px, clamped into the range).
- **Up/Down in search**: glides so the newly selected row sits at the top
  of the list, clamped at the bottom of the range.
- **Search, filter, Changed only, regex, or sort change**: the list jumps
  instantly to the top and any pending glide is dropped. Setting or
  resetting a value keeps the offset.
- **Filter popup wheel**: glides 40px per notch, accumulating the same way.
- **Range change** (a size preset resizing the list): a list scrolled to the
  bottom stays pinned to the bottom; otherwise the offset and any pending
  target are only clamped into the new range.

## Mockup controls

Open `mockup/index.html` through the local HTTP server (not `file:`; Chrome
blocks local font loading from file URLs). Controls:

- Four palettes: Void amethyst, Grim plum (default), Nebula, Dark orchid.
- UI font: Inter, IBM Plex Sans, Manrope, Space Grotesk, Noto Sans (default).
- Data font: Same as UI (default) or JetBrains Mono.
- Text size: 13 (default) / 14 / 15 / 16. Its row-height change also
  exercises the Scrolling range-change rule; wheel steps and the drag
  settle use the current row height.
- Smooth scroll toggle (default on): the `/cvars smooth` setting. Wheel
  deltas count as one notch per 100px (or 3 lines).
- Size menu in the title bar: Auto (default) / Compact / Standard / Large,
  with the selected preset marked in accent behind the accent left bar. The
  mockup stays at the 920×680 Standard reference — it does not re-render the
  Compact or Large layouts.
- 8px grid overlay and Reset.
- **States** scenario bar — one click per acceptance state, each resetting
  the window to a known base first and noting the change in the status line
  (which auto-clears after 30s like every status message):
  - *Active filters*: `scope:account, type:number, has:changed` set in the
    filter menu; the Filters chip reads `Filters 3` in accent.
  - *Active sort*: the sort chip reads `Sort changed desc` in accent.
  - *Undo & redo disabled*: edit history cleared; both icon buttons dimmed.
  - *Copy disabled*: an unmatched search empties the list — empty state
    line, count `0 / N CVars`, Copy disabled, detail cleared.
  - *Default*: everything at rest.

The mockup has no external dependencies. It is intentionally interactive:
Set, Reset, clamp, ignored, read-only, search, regex, filter, sort,
undo/redo, copy, size, and scrollbar states can be exercised
without touching `CVarBrowser.lua`.

## Implementation notes

- Use `CreateFrame(..., "BackdropTemplate")` for bordered surfaces.
- Use `CreateFont` + `SetFontObject`; fall back to `STANDARD_TEXT_FONT` if a
  bundled TTF cannot be loaded.
- Row recycling (visible rows only) keeps large CVar lists cheap: 20 pooled
  rows cover the tallest list plus a partly visible row at each edge, and
  the first drawn row is `floor(offset / ROW_HEIGHT) + 1`.
- All colors and sizes live in `COLORS`, `BODY_FONT_SIZE`, `ROW_HEIGHT`, etc.
- No binary reverse engineering; only documented client Lua APIs.
