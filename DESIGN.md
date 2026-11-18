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
  Inter-SemiBold (`FONT_CHECK`) for the ✓ ↩ ↪ glyphs only. Bundled in
  `Media/`. No bundled font has ★ U+2605, ☆ U+2606, ✦ U+2726, or ♥ U+2665
  (checked with fontTools), so the favorite mark is drawn from 1px
  textures, like the funnel and sort icons. Inter's ◆ U+25C6 / ◇ U+25C7
  were rejected: glyph ink drifts with font metrics (the undo/redo offsets
  show the cost) and antialiased diagonals would sit beside pixel-drawn
  icons.
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
│  CVar Browser   WoW Forever · v1.0.0 · afaa9bd    [Size: Auto]   ×   │
├──────────────────────────────────────────────────────────────────────┤
│  [ Search CVars... ] [.*] [ ] Changed only   21 / 21 CVars, 7 range  │
│  [Filters 2][Sort changed] [↩][↪] [Copy]                             │
│    CVar                            Gauge                 Value        │
│  ──────────────────────────────────────────────────────────────────  │
│  ◆ farclip                            ·       10000 (Default: 1000)  │
│  ◆ nameplateMaxDistance       ┌─────┃┃─────┘  45 (Default: 40)      │
│    assaoFadeOutTo                  ────────┐             50.0        │
│  ◇ giQuality       (hovered row)   ├───┃────┤      4 (Default: 3)    │
│  ...                                                                  │
│                                                         ▐ scrollbar  │
├──────────────────────────────────────────────────────────────────────┤
│  assaoFadeOutTo                                                      │
│  Account │ Graphics │ Default: 50.0 │ Range help: 0.0 - open         │
│  ASSAO Fade Out To [0.0, ~ ] Distance at which the effect fades out. │
│  [ 50.0                    ] [ Set ] [ Reset to default ]  status    │
├──────────────────────────────────────────────────────────────────────┤
│  ◆ Favorite  Differs from default  ┃┃ Observed bounds  □ Read-only … │
│  Slanted end [slants] means no limit. Dot [dot] means no known range.  │
└──────────────────────────────────────────────────────────────────────┘
```

`◆` is a favorite (filled mark); `◇` is the hollow mark the hovered or
selected row shows when it is not a favorite. Favorites sit above every
other row.

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
- **Title bar**: 44px drag region; title, subtitle (see Subtitle), boxed `Size` menu button
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
- **Subtitle**: the existing title-bar FontString — `FONT_META`,
  `COLORS.muted`, `LEFT` on the title's `RIGHT` at (+12, 0), justify-V
  middle, nowrap, natural width — now carries the addon version. Only its
  text changes; font, colour, anchor, and offsets are unchanged, and it has
  no tooltip or hover state. The separator is a middle dot with one space
  each side, `" · "` (Lua `" \194\183 "`, U+00B7). The text comes from
  `C_AddOns.GetAddOnMetadata(addonName, "Version")` and `"X-Build"`,
  each trimmed of surrounding whitespace:
  - **Release** (CI-stamped TOC, e.g. `## Version: 1.0.0`, `## X-Build:
    afaa9bd 2026-11-18`): `WoW Forever · v<version> · <hash>` →
    `WoW Forever · v1.0.0 · afaa9bd`. `<version>` is the TOC value with one
    leading `v`/`V` stripped, so it never reads `vv`. `<hash>` is X-Build's
    first whitespace-delimited token, used as-is (CI writes 7 lowercase hex
    characters). The build date is not shown.
  - **Dev** (Version missing, empty, or `dev` in any case — the repository
    TOC): `WoW Forever · dev`.
  - **Release without a usable hash** (X-Build missing, or its first token
    is not all hex): `WoW Forever · v<version>`, no trailing separator.

  Truncation: none. The visible content is bounded (semver plus 7 hex), so
  the subtitle stays on one line at its natural width at every preset with
  wide clearance before the Size box (approximate Noto Sans widths in
  title-bar pixels; clearance is subtitle right edge to Size box left edge):

  | Preset | Meta size | Subtitle span (release) | Size box left | Clearance |
  | --- | --- | --- | --- | --- |
  | Compact | 10 | ≈163–296 | ≈670 | ≈370px |
  | Standard | 11 | ≈176–322 | ≈783 | ≈460px |
  | Large | 12 | ≈194–354 | ≈896 | ≈540px |

  The subtitle is set once at load (metadata does not change in a session);
  a preset change only re-renders it at the new meta size.
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
    bounds / Help range / Default / Differs from default / Favorite).
    Favorite comes last because it is the user's own set, not a property
    of the data; it reads `has:favorite` in the chip tooltip, the same
    filter as typing `has:fav`. Scope, category,
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
    filter menu at its natural ~710px — scrolls inside the panel over an
    8px muted thumb in the list-scrollbar language. The wheel glides the
    panel 40px per notch (see Scrolling). The control row's menu
    rows are a fixed 24px with nowrap labels, so reachability is identical
    at 13/14/15/16 text sizes: the Has group always ends up behind the same
    ~174px of scroll and every row is reachable in all cases. Opening upward
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
  scrollbar. `CVar` is `LEFT` at (+22, +1), over the row names (was +6);
  the favorite cell has no header label. `Gauge` and `Value` are unchanged.
- **Rows**: 22px; selected rows get the accent fill + 2px left accent bar
  (x 0–1, drawn over the favorite cell). Columns from the row's left edge:
  the 22×22 favorite cell at x 0–21 (see Favorite toggle), the name `LEFT`
  at (+22, 0) with width 284 (was +6 / 300, so it still ends at x=306),
  the 88px gauge centered, and the value `RIGHT` at (−6, 0) with width 300.
  The `surface_hover` fill shows only while the pointer is over a row that
  is not selected, including over its favorite cell: selecting the hovered
  row clears it, and after a scroll it follows whatever row is now under
  the pointer, never the row that used to be there. The partly scrolled-off
  top row is always drawn: the first drawn row is `floor(offset / 22)`, so
  a mid-row offset clips that row at the list edge instead of leaving an
  empty strip.
- **Favorite toggle**: a `Button` child of each pooled row, 22×22,
  `TOPLEFT` on the row's `TOPLEFT` (0, 0), one frame level above the row,
  left click only. It holds a 7×7 mark frame at `TOPLEFT` (7, −8) of the
  toggle, so the diamond covers row pixels x 7–13, y 8–14. An odd-height
  mark cannot center on a 22px row; its widest pixel row (y 11) sits just
  below the row's center line, level with the cap-height middle of the
  name. The mark is 17 `snap_texture` textures, each 1px tall, at
  whole-pixel `TOPLEFT` offsets from the mark frame (x, −y), `ARTWORK`
  layer:
  - Outline, 12 textures of 1×1: (3,0) (2,1) (4,1) (1,2) (5,2) (0,3) (6,3)
    (1,4) (5,4) (2,5) (4,5) (3,6).
  - Interior, 5 textures as (x, y, width): (3,1,1) (2,2,3) (1,3,5) (2,4,3)
    (3,5,1). Outline plus interior is the solid diamond, rows 1/3/5/7/5/3/1
    wide.

  All 17 always share one color. States, first match wins:

  | State | Outline | Interior |
  | --- | --- | --- |
  | Pointer over the toggle, favorite | `accent` | shown |
  | Pointer over the toggle, not favorite | `accent` | hidden |
  | Favorite | `text` | shown |
  | Not favorite, row hovered or selected | `muted` | hidden |
  | Not favorite, otherwise | hidden | hidden |

  Favorites show on every row. A non-favorite shows nothing at rest, so the
  list stays quiet. Read-only and locked rows behave the same (the mark is
  the user's, not data state). Clicking the toggle flips the favorite
  (`g_frame.toggle_favorite`), never selects the row, keeps the scroll
  offset, and hides the row tooltip (cold). The row then moves into or out
  of the favorites group, and the hover fill and toggle state follow
  whatever row is now under the pointer. The status line confirms in the
  default (success) tone: `Added <name> to favorites` or `Removed <name>
  from favorites`. Because the toggle is a child frame, entering it fires
  the row's `OnLeave`; the toggle's `OnEnter` must show the row's hover
  fill (unless the row is selected) and its `OnLeave` must leave the fill
  on while `row:IsMouseOver()`, so the row reads as hovered across its
  whole width. The pooled marks cost 17 × 20 = 340 textures.
- **Favorites order**: favorites sort above every other row in both
  directions; the sort key and direction only order rows inside the
  favorites group and the rest, with the usual name-ascending tie rule. No
  divider or group header: the column of filled marks is the group marker.
  Favorites are not a sort key, so they never turn the Sort chip accent.
- **Vocabulary**: the feature is called favorite everywhere the user reads
  it: the `Favorite` facet and key entry, the tooltip lines, the status
  line, and chat (`<name> added to favorites` / `<name> removed from
  favorites`, never pinned/unpinned).
- **Row tooltip**: a custom panel, not `GameTooltip`, whose gold-edged
  backdrop and font objects would break the flat plum language. A `Frame`
  parented to `g_frame` (so it hides with the window), strata `TOOLTIP`,
  `SetClampedToScreen(true)`, mouse disabled, hidden by default. `surface`
  fill and a 1px `border` drawn with the custom snapped hairlines (joins
  `g_frame.snap_boxes`), no shadow.
  - **Lines**: FontStrings stacked top to bottom, each `TOPLEFT` on the
    previous one's `BOTTOMLEFT`, justify-H left, word wrap on, wrapped
    lines at `SetSpacing(2)`, overflow cut by `SetMaxLines` (WoW ends the
    last line with an ellipsis):

    | # | Text | Font | Color | Shown | Max lines | Gap above |
    | --- | --- | --- | --- | --- | --- | --- |
    | 1 | CVar name | `FONT_BODY` | `muted` if read-only, else `changed` if changed, else `text` (never `accent`) | always | 2 | — |
    | 2 | `Value: <value>` | `FONT_BODY` | `text` | always | 4 | 2 |
    | 3 | `Default: <default>` | `FONT_BODY` | `muted` | changed only | 2 | 2 |
    | 4 | help text, trimmed | `FONT_META` | `text` | help not blank | 8 | 6 |

    `<value>` is the full current value with CR/LF runs turned into one
    space (rows cut it at 28 characters), `empty` when blank, and
    `Bitfield (N bytes)` / `Serialized (N bytes)` for binary values, as
    the row shows. `<default>` uses the detail meta wording: the default,
    `empty`, or `Bitfield (N bytes)` / `Serialized (N bytes)`.
  - **Toggle line**: while the pointer is over the favorite toggle the
    panel holds one line instead, `Add to favorites` or `Remove from
    favorites`, `FONT_META`, `text`, same panel, sizing, and anchor.
  - **Size**: text inset 8px on every side (first line `TOPLEFT` at
    (8, −8)). Text width W = min(320, ceil(widest line's unwrapped width));
    every line gets `SetWidth(W)` and wraps there. Panel width W + 16,
    height 16 + the line heights + the gaps, each rounded up to whole
    pixels. The 320 cap holds at every preset.
  - **Anchor**: placed once per show, never following the cursor. Below
    the row: panel `TOPLEFT` on the row's `BOTTOMLEFT` at (14, −4), so the
    text column lines up with the row name at x=22 and the tooltip reads
    as the row unfolded. If the panel's bottom would then come within 8px
    of the window's bottom edge, anchor it above instead: `BOTTOMLEFT` on
    the row's `TOPLEFT` at (14, 4). If that would come within 8px of the
    window's top edge too, keep it below.
  - **Timing**: shows after the pointer rests 0.5s on a target (a row, or
    a row's favorite toggle as a separate target). Moving inside the
    target never restarts the delay. Warm handoff: while the panel is up,
    or within 0.1s after it hid because the pointer left a row, the next
    target shows at once. Hides warm on `OnLeave` with no new target.
    Hides cold (the next show waits the full 0.5s) on a click on a row or
    toggle, a list rebuild (search, filter, sort, favorite toggle, rescan),
    a popup menu or the copy box opening (it never shows while one is
    open), and the window hiding. Any change of the list's scroll offset
    (wheel, glide, keyboard navigation, thumb drag) hides it cold and
    restarts the 0.5s for the row now under the pointer, so it returns
    once the list comes to rest; nothing arms during a thumb drag.
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
- **Semantic key**: glossary marks with plain-language labels, in the
  row's left-to-right order: filled favorite diamond (the toggle's 7×7
  pixels, all 17 textures in `text`) = favorite; changed lilac text =
  differs from default; tally ticks (12×8: two 1×6 ticks 10px apart,
  rows 1–6) = observed
  bounds; hollow square (9×9, 1px lines) = read-only; cursor (2×8) = current
  value. Entries sit 16px apart, marks 8px from their labels. The favorite
  entry is first: `key_items` gains `{ favorite mark, 7, 8 }` and
  `{ "Favorite" FONT_META muted, nil, 16 }` ahead of "Differs from
  default"; the mark frame is 7×7, `LEFT` anchored like the other marks.
  The row stays clear of the right-aligned hint at every preset
  (approximate widths, key entries plus hint: ≈690 of 752px at Compact,
  ≈760 of 872 at Standard, ≈830 of 992 at Large). The hint shows
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
| Favorite | filled 7×7 diamond in `text` in the favorite cell; row sorts into the top group |
| Not favorite, hovered or selected | hollow 7×7 diamond in `muted` |
| Pointer over favorite toggle | diamond (filled or hollow) in `accent`; row keeps its hover fill |
| Row tooltip | `surface` panel, 1px `border`, under the row with its text at the name's x=22 (above near the window bottom) |
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
| Favorites filter | Has `Favorite` ticked; Filters chip counts it; tooltip lists `has:favorite` |

## Interaction

- `/cvars` / `/cb` toggle the window; `/cvars <name>` opens, searches,
  selects, and focuses the value field; `/cvars refresh` rescans; `/cvars
  undo` / `/cvars redo`; `/cvars ranges`; `/cvars regex`; `/cvars filters`;
  `/cvars sort name|type|scope|category|changed|range`; `/cvars minimap
  [reset]`; `/cvars copy [value|raw|default|name|help|range] [cvar]` opens
  the copy box with that field (see Copy box); `/cvars smooth [on|off]`
  sets smooth scrolling (no argument flips it); `/cvars clearranges` clears
  observed bounds; `/cvars clearrange <name>` clears one; `/cvars fav
  [name]` toggles the favorite of the named CVar, or the selected one, and
  confirms in chat (see Vocabulary). The change log is chat only, with no
  window UI: `/cvars log [count|name]` prints it and `/cvars clearlog`
  empties it.
- Search syntax: the text splits on whitespace into lowercased tokens.
  Plain words must each appear in the name or the help text (regex mode
  joins them into one pattern). Filter terms:
  - `scope:<s>`, `category:<c>` (or `cat:<c>`): the scope or category
    contains the text.
  - `type:<t>`: the value type is exactly t (see Value type).
  - `has:<facet>`: `range`, `observed`, `help`, `default`, `changed`, or
    `fav` (also `favorite`). An unknown facet filters nothing out.
  - `value:<x>`: the current value contains x. `value:=<x>`: the current
    value is exactly x. Both ignore case and compare the text the value
    field shows (hex for bitfield and serialized values). Tokens never
    hold spaces, so a value with spaces only matches by one of its words.
  - `changed`: same as Changed only.

  A later term with the same key replaces an earlier one. The filter and
  sort chips are the visual face of these command filters: selecting
  facets in the filter menu is equivalent to typing the same
  `scope:`/`type:`/`has:` terms, and both routes combine into one filter
  set. The regex chip switches the search box between literal and
  regular-expression matching (an invalid pattern simply matches nothing).
- Keyboard: Up/Down move the selection one row, PageUp/PageDown one page
  (the whole rows the list shows, `floor(list height / 22)`, 15 at
  Standard), Home/End to the first or last result. The selected row glides
  to the top of the list (see Scrolling). In the search box Up/Down and
  PageUp/PageDown navigate while Home/End stay with the caret. With no
  edit box focused, all six navigate while the cursor is over the window,
  out of combat (in combat every key passes through to the game); any
  other key passes through. Enter in the search box selects the row
  picked with the navigation keys — or, with none since the search text
  last changed, the first result — then focuses the value field (unless
  the CVar is read-only, locked, or secure in combat). With no results
  Enter leaves the search box.
- Escape, first match wins: closes an open menu; in the search box, clears
  its text, and a second Escape leaves the box; with no edit box focused,
  clears the search text, and a second Escape closes the window. The value
  field and copy box keep their own Escape (leave the field, close the
  box).
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
  Favorites stay above everything in both directions (see Favorites
  order). The chip always shows the live `key dir`.
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
- Click a row to select it; click its favorite cell to toggle the favorite
  without selecting it. Edit the value; Enter or Set applies.
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
- **Navigation keys** (Up/Down/PageUp/PageDown/Home/End, see Keyboard):
  glide so the newly selected row sits at the top of the list, clamped at
  the bottom of the range.
- **Search, filter, Changed only, regex, or sort change**: the list jumps
  instantly to the top and any pending glide is dropped. Setting or
  resetting a value, or toggling a favorite, keeps the offset.
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
- Build: Release 1.0.0 (default) / Dev. It feeds the subtitle rule the TOC
  metadata a build carries — release is `Version: 1.0.0`, `X-Build: afaa9bd
  2026-11-18`, rendering `WoW Forever · v1.0.0 · afaa9bd`; dev is
  `Version: dev` with no X-Build, rendering `WoW Forever · dev`. Reset
  returns to Release.
- 8px grid overlay and Reset.
- **States** scenario bar — one click per acceptance state, each resetting
  the window to a known base first (favorites back to `farclip` and
  `nameplateMaxDistance`) and noting the change in the status line (which
  auto-clears after 30s like every status message):
  - *Active filters*: `scope:account, type:number, has:changed` set in the
    filter menu; the Filters chip reads `Filters 3` in accent.
  - *Active sort*: the sort chip reads `Sort changed desc` in accent.
  - *Undo & redo disabled*: edit history cleared; both icon buttons dimmed.
  - *Copy disabled*: an unmatched search empties the list — empty state
    line, count `0 / N CVars`, Copy disabled, detail cleared.
  - *Favorites only*: Has `Favorite` ticked; two rows, `Filters 1`.
  - *Value filter*: search `value:=1` keeps the CVars whose value is
    exactly `1`.
  - *Row tooltip*: search `realm`, with the tooltip held open on
    `realmList` (long wrapped value and help) until the pointer reaches the
    list.
  - *Default*: everything at rest.
- Favorites, the tooltip, and the keyboard keys are live: hover a row for
  0.5s, click a favorite cell, or press the navigation keys with the
  pointer over the window.

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
