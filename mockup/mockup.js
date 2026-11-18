"use strict";

const PALETTES = {
  void: {
    name: "Void amethyst",
    bg: "#0D0B14",
    surface: "#161223",
    hover: "#1F1930",
    border: "#2E2547",
    text: "#ECE9F6",
    muted: "#9A90B8",
    accent: "#A8A3D4",
    accentRgb: "168,163,212",
    observed: "#5EEAD4",
    warning: "#E8B45C",
    success: "#6FD68A",
    error: "#E86A6A",
    changed: "#C6C2E8",
  },
  grim: {
    name: "Grim plum",
    bg: "#121114",
    surface: "#1A181C",
    hover: "#232126",
    border: "#343138",
    text: "#EDEAF2",
    muted: "#9A929F",
    accent: "#B7A3CC",
    accentRgb: "183,163,204",
    observed: "#68C3B9",
    warning: "#E0A857",
    success: "#63C98A",
    error: "#E06A72",
    changed: "#D2BFE6",
  },
  nebula: {
    name: "Nebula",
    bg: "#0A0812",
    surface: "#130F22",
    hover: "#1D1733",
    border: "#322A55",
    text: "#F2F0FA",
    muted: "#A79EC9",
    accent: "#ADA0D8",
    accentRgb: "173,160,216",
    observed: "#67E8F9",
    warning: "#F0C05A",
    success: "#7EE2A8",
    error: "#F07676",
    changed: "#D9C4EC",
  },
  orchid: {
    name: "Dark orchid",
    bg: "#100916",
    surface: "#191022",
    hover: "#241732",
    border: "#3A2551",
    text: "#EFE6F7",
    muted: "#A18CB8",
    accent: "#B98ACC",
    accentRgb: "185,138,204",
    observed: "#35D6C7",
    warning: "#E8B45C",
    success: "#6FD68A",
    error: "#E86A6A",
    changed: "#D9B8E4",
  },
};

const FONTS = {
  inter: { label: "Inter", css: "var(--font-inter)" },
  plex: { label: "IBM Plex Sans", css: "var(--font-plex)" },
  manrope: { label: "Manrope", css: "var(--font-manrope)" },
  space: { label: "Space Grotesk", css: "var(--font-space)" },
  noto: { label: "Noto Sans", css: "var(--font-noto)" },
};

const SCALES = {
  13: { row: 22, small: 11, detail: 15 },
  14: { row: 24, small: 12, detail: 16 },
  15: { row: 26, small: 13, detail: 17 },
  16: { row: 28, small: 14, detail: 18 },
};

const PRESETS = [
  { value: "auto", label: "Auto" },
  { value: "compact", label: "Compact" },
  { value: "standard", label: "Standard" },
  { value: "large", label: "Large" },
];

/* TOC metadata the runtime reads through C_AddOns.GetAddOnMetadata. CI
   stamps release builds with Version and X-Build ("<hash> <YYYY-MM-DD>");
   a repository copy carries Version "dev" and no X-Build. */
const BUILDS = {
  release: { version: "1.0.0", xBuild: "afaa9bd 2026-11-18" },
  dev: { version: "dev", xBuild: null },
};

const DEFAULTS = {
  palette: "grim",
  font: "noto",
  data: "sans",
  scale: 13,
  preset: "auto",
  smooth: true,
  build: "release",
};

const CVARS = [
  {
    name: "assaoFadeOutTo",
    help: "ASSAO Fade Out To [0.0, ~ ] Distance at which the effect is faded out.",
    range: "0.0 - open",
    source: "help",
    value: "50.0",
    def: "50.0",
    helpMin: 0,
    helpMax: null,
    openMax: true,
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "giQuality",
    help: "Graphics quality [1, 10]",
    range: "1 - 10",
    source: "help",
    value: "4",
    def: "3",
    helpMin: 1,
    helpMax: 10,
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "nameplateMaxDistance",
    help: "Maximum distance at which nameplates are shown.",
    range: "max 50",
    source: "observed",
    observed: "max: 200 -> 50 (was 40)",
    value: "45",
    def: "40",
    observedMax: 50,
    scope: "Character",
    category: "Game",
  },
  {
    name: "nameplateOverlapV",
    help: "Vertical overlap of stacked nameplates [0.5, 2.5].",
    range: "max 1.6",
    source: "observed",
    observed: "max: 3 -> 1.6",
    helpRange: "0.5 - 2.5",
    value: "1.1",
    def: "1.1",
    helpMin: 0.5,
    helpMax: 2.5,
    observedMax: 1.6,
    scope: "Character",
    category: "Game",
    locked: true,
    secure: true,
  },
  {
    name: "farclip",
    help: "Far clipping distance.",
    range: "",
    source: "",
    value: "10000",
    def: "1000",
    scope: "Local",
    category: "Graphics",
  },
  {
    name: "graphicsQuality",
    help: "Overall graphics quality preset.",
    range: "",
    source: "",
    value: "9",
    def: "7",
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "shadowTextureSize",
    help: "Shadow texture size.",
    range: "",
    source: "observed",
    observed: "min: 256 -> 512; max: 8192 -> 4096 (2x)",
    value: "4096",
    def: "2048",
    observedMin: 512,
    observedMax: 4096,
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "Sound_MasterVolume",
    help: "Master sound volume [0, 1].",
    range: "0 - 1",
    source: "help",
    value: "0.7",
    def: "0.7",
    helpMin: 0,
    helpMax: 1,
    scope: "Account",
    category: "Sound",
  },
  {
    name: "cameraDistanceMaxZoomFactor",
    help: "Maximum camera zoom factor.",
    range: "",
    source: "",
    value: "1.9",
    def: "1.9",
    scope: "Character",
    category: "Game",
  },
  {
    name: "nameplateShowEnemies",
    help: "Show enemy nameplates.",
    range: "",
    source: "",
    value: "1",
    def: "1",
    scope: "Character",
    category: "Game",
    secure: true,
  },
  {
    name: "advancedCombatLogging",
    help: "Whether advanced combat log data is sent from the server.",
    range: "",
    source: "",
    value: "1",
    def: "0",
    scope: "Account",
    category: "Game",
  },
  {
    name: "assaoRadius",
    help: "ASSAO Radius [0.01, 100] World-space size of the occlusion sphere.",
    range: "0.01 - 100",
    source: "help",
    value: "1.85",
    def: "1.85",
    helpMin: 0.01,
    helpMax: 100,
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "bloomUserMult",
    help: "Bloom multiplier.",
    range: "",
    source: "",
    value: "0.8",
    def: "0.8",
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "groundEffectDensity",
    help: "Ground effect density.",
    range: "",
    source: "",
    value: "48",
    def: "48",
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "terrainLodDist",
    help: "Terrain level of detail distance.",
    range: "",
    source: "",
    value: "650",
    def: "650",
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "waterDetail",
    help: "Water detail level. 0 = low, 1 = fair, 2 = good, 3 = ultra.",
    range: "",
    source: "",
    value: "3",
    def: "3",
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "particleDensity",
    help: "Particle density.",
    range: "",
    source: "",
    value: "80",
    def: "80",
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "ResampleSharpness",
    help: "Resample sharpness [0, 1].",
    range: "0 - 1",
    source: "help",
    value: "0.6",
    def: "0.6",
    helpMin: 0,
    helpMax: 1,
    scope: "Account",
    category: "Graphics",
  },
  {
    name: "agentUID",
    help: "The UID provided by Battle.net to be passed to Agent.",
    range: "",
    source: "",
    value: "wowf",
    def: "wowf",
    scope: "Local",
    category: "Game",
  },
  {
    name: "textLocale",
    help: "Client text locale.",
    range: "",
    source: "",
    value: "enUS",
    def: "enUS",
    scope: "Local",
    category: "Game",
  },
  {
    name: "portal",
    help: "Realm portal.",
    range: "",
    source: "",
    value: "US",
    def: "US",
    scope: "Local",
    category: "Net",
    readonly: true,
  },
  {
    name: "realmList",
    help: "Address of the login server the client connects to. A change applies at the next login, and an address the client cannot reach leaves the realm list empty.",
    range: "",
    source: "",
    value: "logon.forever.example.net;logon2.forever.example.net;logon-backup.forever.example.net",
    def: "logon.forever.example.net",
    scope: "Local",
    category: "Net",
  },
  {
    name: "weirdCvar",
    help: "A CVar that accepts a set but silently ignores it.",
    range: "",
    source: "",
    value: "1",
    def: "1",
    scope: "Account",
    category: "Debug",
    ignoreSet: true,
  },
  {
    name: "trackedProfessionRecipes",
    help: "Tracked profession recipes.",
    range: "",
    source: "",
    value: "v2\u0001\u0004\u0012##>@",
    def: "",
    scope: "Character",
    category: "Game",
  },
  {
    name: "closedInfoFrames",
    help: "Bitfield for which help frames have been acknowledged by the user.",
    range: "",
    source: "",
    value: "\u0003\u0080\u0010\u0001",
    def: "\u0001\u0080\u0010\u0001",
    scope: "Character",
    category: "Game",
  },
];

const SORT_KEYS = ["name", "type", "scope", "category", "changed", "range"];

// Favorites the mockup starts with. The runtime keeps them in g_db.favorites.
const DEFAULT_FAVORITES = ["farclip", "nameplateMaxDistance"];

const state = {
  query: "",
  regex: false,
  changedOnly: false,
  filters: { scope: "all", category: "all", type: "all", has: [] },
  sort: { key: "name", dir: "asc" },
  favorites: new Set(DEFAULT_FAVORITES),
  selected: "assaoFadeOutTo",
  palette: DEFAULTS.palette,
  font: DEFAULTS.font,
  data: DEFAULTS.data,
  scale: DEFAULTS.scale,
  preset: DEFAULTS.preset,
  smooth: DEFAULTS.smooth,
  build: DEFAULTS.build,
};

const history = { undo: [], redo: [] };
let searchNavigated = false;

const app = document.getElementById("app");
const rowsEl = document.getElementById("rows");
const viewport = document.getElementById("rows-viewport");
const scrollbar = document.getElementById("scrollbar");
const scrollbarThumb = document.getElementById("scrollbar-thumb");
const countEl = document.getElementById("count");
const searchEl = document.getElementById("search");
const changedOnlyEl = document.getElementById("changed-only");
const gridToggleEl = document.getElementById("grid-toggle");
const smoothToggleEl = document.getElementById("smooth-toggle");
const fontSelectEl = document.getElementById("font-select");
const dataSelectEl = document.getElementById("data-select");
const scaleSwitchEl = document.getElementById("scale-switch");
const paletteSwitchEl = document.getElementById("palette-switch");
const selectionEl = document.getElementById("selection");
const detailNameEl = document.getElementById("detail-name");
const detailMetaEl = document.getElementById("detail-meta");
const detailHelpEl = document.getElementById("detail-help");
const valueEditEl = document.getElementById("value-edit");
const setButtonEl = document.getElementById("set-button");
const resetButtonEl = document.getElementById("reset-button");
const statusEl = document.getElementById("status");
const regexChipEl = document.getElementById("regex-chip");
const filterChipEl = document.getElementById("filter-chip");
const filterLabelEl = document.getElementById("filter-label");
const filterMenuEl = document.getElementById("filter-menu");
const sortChipEl = document.getElementById("sort-chip");
const sortLabelEl = document.getElementById("sort-label");
const sortMenuEl = document.getElementById("sort-menu");
const undoButtonEl = document.getElementById("undo-button");
const redoButtonEl = document.getElementById("redo-button");
const copyButtonEl = document.getElementById("copy-button");
const copyMenuEl = document.getElementById("copy-menu");
const copyBoxEl = document.getElementById("copy-box");
const copyBoxInputEl = document.getElementById("copy-box-input");
const sizeButtonEl = document.getElementById("size-button");
const sizeMenuEl = document.getElementById("size-menu");
const scenariosEl = document.getElementById("scenarios");
const buildSwitchEl = document.getElementById("build-switch");
const subtitleEl = document.getElementById("subtitle");

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function isChanged(cvar) {
  return cvar.value !== cvar.def;
}

// Binary CVars known by name (runtime BITFIELD_CVARS).
const BITFIELD_CVARS = new Set(["closedInfoFrames"]);

/* Binary kind as the runtime's read_cvar_value flags it. Bitfields match by
   name, and a value holding a control or high byte is serialized. Values are
   byte strings with one char per byte, like Lua strings. */
function binaryKind(cvar) {
  if (BITFIELD_CVARS.has(cvar.name)) {
    return "Bitfield";
  }
  return /[\x00-\x1f\x7f-\xff]/.test(cvar.value) ? "Serialized" : null;
}

/* Bitfield and serialized values edit as hex, two uppercase digits per byte
   (runtime display_edit_value). */
function editText(cvar, value) {
  if (!binaryKind(cvar)) {
    return value;
  }
  return Array.from(value, (ch) => ch.charCodeAt(0).toString(16).toUpperCase().padStart(2, "0")).join("");
}

/* Parses hex like the runtime's hex_to_bitfield. Whitespace is ignored, empty
   stays empty, and an odd length or a non-hex digit is invalid (null). */
function hexToBytes(text) {
  const hex = text.replace(/\s+/g, "");
  if (hex.length % 2 !== 0 || /[^0-9a-f]/i.test(hex)) {
    return null;
  }
  return hex.replace(/../g, (pair) => String.fromCharCode(parseInt(pair, 16)));
}

/* Detects enums like the runtime's parse_enum_help. The help text needs at
   least two `N = label` or `N: label` pairs, each label starting with a
   letter and at most 32 chars long. */
function helpEnum(help) {
  if (!help) {
    return null;
  }
  const options = [];
  for (const [, value, rawLabel] of help.matchAll(/([+-]?\d+)\s*[=:]\s*([A-Za-z][A-Za-z0-9\s./-]*)/g)) {
    const label = rawLabel.trim();
    if (label !== "" && label.length <= 32) {
      options.push(`${value} = ${label}`);
    }
  }
  return options.length >= 2 ? options : null;
}

/* Value type, tested in the runtime's infer_value_type order of Bitfield,
   Serialized, Enum (help parses as an enum), Unknown (no value), Boolean,
   Number, List, then Text. The meta line, the Type filter, and the type sort
   all use it. */
function valueType(cvar) {
  const kind = binaryKind(cvar);
  if (kind) {
    return kind;
  }
  if (helpEnum(cvar.help)) {
    return "Enum";
  }
  const value = cvar.value;
  if (value == null) {
    return "Unknown";
  }
  if (value === "0" || value === "1" || value === "true" || value === "false") {
    return "Boolean";
  }
  if (value.trim() !== "" && Number.isFinite(Number(value))) {
    return "Number";
  }
  return /[,;\s]/.test(value) ? "List" : "Text";
}

function isEditable(cvar) {
  return !cvar.readonly && !cvar.locked;
}

function selectedCvar() {
  return CVARS.find((cvar) => cvar.name === state.selected) ?? null;
}

function hasFacet(cvar, facet) {
  switch (facet) {
    case "range":
      return cvar.helpMin != null || cvar.helpMax != null || cvar.observedMin != null || cvar.observedMax != null;
    case "observed":
      return cvar.observedMin != null || cvar.observedMax != null;
    case "help":
      return cvar.helpMin != null || cvar.helpMax != null;
    case "default":
      return !(cvar.def === "" || /^\s*$/.test(cvar.def));
    case "changed":
      return isChanged(cvar);
    case "favorite":
      return state.favorites.has(cvar.name);
    default:
      return false;
  }
}

function isFavorite(cvar) {
  return state.favorites.has(cvar.name);
}

/* Splits the search text like the runtime's rebuild_view. Lowercased
   `key:value` tokens become filters (scope, category or cat, type, has,
   value), a bare `changed` turns on Changed only, and every other token is
   a text term. A later token of the same key replaces an earlier one. */
function parseQuery(text) {
  const parsed = { terms: [], scope: null, category: null, type: null, has: null, value: null, changed: false };
  for (const raw of text.trim().split(/\s+/).filter(Boolean)) {
    const token = raw.toLowerCase();
    const match = /^(\w+):(.+)$/.exec(token);
    const key = match ? match[1] : "";
    if (key === "scope") {
      parsed.scope = match[2];
    } else if (key === "category" || key === "cat") {
      parsed.category = match[2];
    } else if (key === "type") {
      parsed.type = match[2];
    } else if (key === "has") {
      parsed.has = match[2];
    } else if (key === "value") {
      parsed.value = match[2];
    } else if (token === "changed") {
      parsed.changed = true;
    } else {
      parsed.terms.push(state.regex ? raw : token);
    }
  }
  return parsed;
}

// Typed `has:` terms. `fav` is short for `favorite`, and an unknown facet
// filters nothing out (runtime has_state).
const HAS_FACETS = new Set(["range", "observed", "help", "default", "changed", "favorite"]);
function typedHas(cvar, facet) {
  const key = facet === "fav" ? "favorite" : facet;
  return HAS_FACETS.has(key) ? hasFacet(cvar, key) : true;
}

function activeFilterCount() {
  const f = state.filters;
  let count = f.has.length;
  if (f.scope !== "all") count += 1;
  if (f.category !== "all") count += 1;
  if (f.type !== "all") count += 1;
  return count;
}

function filterSummary() {
  const f = state.filters;
  const parts = [];
  if (f.scope !== "all") parts.push(`scope:${f.scope}`);
  if (f.category !== "all") parts.push(`category:${f.category}`);
  if (f.type !== "all") parts.push(`type:${f.type}`);
  for (const facet of f.has) parts.push(`has:${facet}`);
  if (state.changedOnly) parts.push("changed");
  return parts.join(", ");
}

function matchesFilters(cvar, parsed) {
  const f = state.filters;
  if ((state.changedOnly || parsed.changed) && !isChanged(cvar)) {
    return false;
  }
  if (f.scope !== "all" && cvar.scope.toLowerCase() !== f.scope) {
    return false;
  }
  if (f.category !== "all" && cvar.category.toLowerCase() !== f.category) {
    return false;
  }
  if (f.type !== "all" && valueType(cvar).toLowerCase() !== f.type) {
    return false;
  }
  if (!f.has.every((facet) => hasFacet(cvar, facet))) {
    return false;
  }
  if (parsed.scope && !cvar.scope.toLowerCase().includes(parsed.scope)) {
    return false;
  }
  if (parsed.category && !cvar.category.toLowerCase().includes(parsed.category)) {
    return false;
  }
  if (parsed.type && valueType(cvar).toLowerCase() !== parsed.type) {
    return false;
  }
  if (parsed.has && !typedHas(cvar, parsed.has)) {
    return false;
  }
  if (parsed.value != null) {
    // `value:x` finds x in the current value and `value:=x` needs the whole
    // value, both ignoring case. Binary values compare as the hex the value
    // field shows.
    const shown = editText(cvar, cvar.value).toLowerCase();
    return parsed.value.startsWith("=") ? shown === parsed.value.slice(1) : shown.includes(parsed.value);
  }
  return true;
}

function matchesQuery(cvar, parsed) {
  if (parsed.terms.length === 0) {
    return true;
  }
  if (state.regex) {
    let re;
    try {
      re = new RegExp(parsed.terms.join(" "), "i");
    } catch {
      return false;
    }
    return re.test(cvar.name) || re.test(cvar.help ?? "");
  }
  const name = cvar.name.toLowerCase();
  const help = (cvar.help ?? "").toLowerCase();
  return parsed.terms.every((term) => name.includes(term) || help.includes(term));
}

/* Sorts like the runtime's rebuild_view. Favorites always sort above every
   other row, in both directions, and the sort key orders rows inside each
   group. Lowercase keys compare bytewise. The direction flips only the key,
   and ties always fall back to name ascending. Changed asc puts unchanged
   rows first. Rows with no range width sort last in both directions. */
function compareCvars(a, b) {
  if (isFavorite(a) !== isFavorite(b)) {
    return isFavorite(a) ? -1 : 1;
  }
  const dir = state.sort.dir === "desc" ? -1 : 1;
  const cmp = (x, y) => (x < y ? -1 : x > y ? 1 : 0);
  const byName = cmp(a.name.toLowerCase(), b.name.toLowerCase());
  let diff;
  switch (state.sort.key) {
    case "type":
      diff = cmp(valueType(a).toLowerCase(), valueType(b).toLowerCase());
      break;
    case "scope":
      diff = cmp(a.scope.toLowerCase(), b.scope.toLowerCase());
      break;
    case "category":
      diff = cmp(a.category.toLowerCase(), b.category.toLowerCase());
      break;
    case "changed":
      diff = Number(isChanged(a)) - Number(isChanged(b));
      break;
    case "range": {
      const width = (c) => {
        const mins = [c.helpMin, c.observedMin].filter((v) => v != null);
        const maxs = [c.helpMax, c.observedMax].filter((v) => v != null);
        return mins.length && maxs.length ? Math.max(...maxs) - Math.min(...mins) : null;
      };
      const wa = width(a);
      const wb = width(b);
      if (wa == null && wb == null) return byName;
      if (wa == null) return 1;
      if (wb == null) return -1;
      diff = wa - wb;
      break;
    }
    default:
      diff = byName;
      break;
  }
  return dir * diff || byName;
}

function filteredCvars() {
  const parsed = parseQuery(state.query);
  return CVARS.filter((cvar) => matchesFilters(cvar, parsed) && matchesQuery(cvar, parsed)).sort(compareCvars);
}

/* Every status message, errors included, clears 30s after it appears. A new
   message replaces the old one and restarts the 30s. An empty message clears
   immediately and disarms the timer. */
const STATUS_TTL_MS = 30000;
let statusTimer = 0;

function setStatus(message, tone) {
  statusEl.textContent = message;
  statusEl.className = "status" + (tone ? " " + tone : "");
  if (statusTimer) {
    clearTimeout(statusTimer);
    statusTimer = 0;
  }
  if (message) {
    statusTimer = setTimeout(() => {
      statusTimer = 0;
      statusEl.textContent = "";
      statusEl.className = "status";
    }, STATUS_TTL_MS);
  }
}

function gaugeFor(cvar) {
  const value = Number(cvar.value);
  const helpMin = cvar.helpMin ?? null;
  const helpMax = cvar.helpMax ?? null;
  const obsMin = cvar.observedMin ?? null;
  const obsMax = cvar.observedMax ?? null;
  const mins = [helpMin, obsMin].filter((bound) => bound != null);
  const maxs = [helpMax, obsMax].filter((bound) => bound != null);
  const knownMin = mins.length ? Math.min(...mins) : null;
  const knownMax = maxs.length ? Math.max(...maxs) : null;

  if (!Number.isFinite(value) || (knownMin == null && knownMax == null)) {
    return `<span class="gauge-empty" role="img" title="No numeric range advertised" aria-label="No numeric range advertised"><i></i></span>`;
  }

  let domainMin = knownMin;
  let domainMax = knownMax;
  if (domainMin == null) {
    domainMin = Math.min(0, domainMax);
  }
  if (domainMax == null) {
    const upper = Math.max(value, 0, domainMin + 1, 1);
    domainMax = upper * 1.25;
  }
  if (domainMax <= domainMin) {
    domainMax = domainMin + 1;
  }

  const width = 88;
  const height = 8;
  const x = (bound) => Math.max(0, Math.min(width, ((bound - domainMin) / (domainMax - domainMin)) * width));
  const changed = isChanged(cvar);
  const ticks = [`<rect class="gauge-track" x="0" y="3" width="${width}" height="1"/>`];
  // Runtime place_gauge_mark: a w x h mark centered on x on whole pixels —
  // left edge round(x - w/2), capped at the last track column; top
  // floor((8 - h)/2), so 1x6 ticks fill rows 1-6 and 1x3 ticks rows 2-4.
  const mark = (position, className, w, h) => {
    const left = Math.min(Math.round(position - w / 2), width - 1);
    const top = Math.floor((height - h) / 2);
    return `<rect class="${className}" x="${left}" y="${top}" width="${w}" height="${h}"/>`;
  };

  // An open end is one 1px full-height diagonal through the track end (left
  // `/`, right `\`) that rises 8px over an 8px run, with no 5x4 cap.
  if (knownMin == null) {
    ticks.push(`<line class="gauge-open" x1="0" y1="8" x2="8" y2="0"/>`);
  }
  if (knownMax == null) {
    ticks.push(`<line class="gauge-open" x1="${width - 8}" y1="0" x2="${width}" y2="8"/>`);
  }
  if (helpMin != null) {
    ticks.push(mark(x(helpMin), "gauge-help", 1, 3));
  }
  if (helpMax != null) {
    ticks.push(mark(x(helpMax), "gauge-help", 1, 3));
  }
  if (obsMin != null) {
    ticks.push(mark(x(obsMin), "gauge-observed", 1, 6));
  }
  if (obsMax != null) {
    ticks.push(mark(x(obsMax), "gauge-observed", 1, 6));
  }
  if (cvar.clampedAt != null) {
    const clampedX = x(Number(cvar.clampedAt));
    const capX = cvar.clampSide === "low" ? Math.max(0, clampedX - 2) : Math.min(width, clampedX + 2);
    ticks.push(mark(capX, "gauge-clamp", 2, 8));
  }
  ticks.push(mark(x(value), `gauge-cursor${changed ? " changed" : ""}`, 2, 8));

  const label = [
    helpMin != null || helpMax != null
      ? `help ${helpMin ?? "open"} to ${helpMax ?? "open"}`
      : "",
    obsMin != null || obsMax != null
      ? `observed ${obsMin ?? "open"} to ${obsMax ?? "open"}`
      : "",
    `current ${cvar.value}`,
  ]
    .filter(Boolean)
    .join(", ");

  return `<svg class="gauge" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" role="img" aria-label="${escapeHtml(label)}">${ticks.join("")}</svg>`;
}

/* The favorite mark is a 7x7 pixel diamond drawn from 1px rects, like the
   runtime's textures (no bundled font has a star). The 12 outline pixels
   always draw together. The 5 interior rows fill it in when the CVar is a
   favorite. Offsets are [x, y, width] from the mark's top-left corner. */
const FAV_OUTLINE = [[3, 0, 1], [2, 1, 1], [4, 1, 1], [1, 2, 1], [5, 2, 1], [0, 3, 1], [6, 3, 1], [1, 4, 1], [5, 4, 1], [2, 5, 1], [4, 5, 1], [3, 6, 1]];
const FAV_INTERIOR = [[3, 1, 1], [2, 2, 3], [1, 3, 5], [2, 4, 3], [3, 5, 1]];
const favRects = (parts) => parts.map(([x, y, w]) => `<rect x="${x}" y="${y}" width="${w}" height="1"></rect>`).join("");
const FAV_MARK = `<svg class="fav-mark" viewBox="0 0 7 7" width="7" height="7" aria-hidden="true">${favRects(FAV_OUTLINE)}<g class="fav-fill">${favRects(FAV_INTERIOR)}</g></svg>`;

// Row value text. Binary values show their size, never their bytes (runtime
// render_row).
function valueDisplay(cvar) {
  const kind = binaryKind(cvar);
  return kind ? `${kind} (${cvar.value.length} bytes)` : cvar.value;
}

// Default text in the detail meta wording, shared by the row tooltip.
function defaultDisplay(cvar) {
  const kind = binaryKind(cvar);
  return kind ? `${kind} (${cvar.def.length} bytes)` : /^\s*$/.test(cvar.def) ? "empty" : cvar.def;
}

function renderRows() {
  const list = filteredCvars();
  if (list.length === 0) {
    state.selected = "";
    rowsEl.innerHTML = `<div class="empty-state">No CVars match. Clear filters or change the search.</div>`;
    countEl.textContent = `0 / ${CVARS.length} CVars`;
    updateScrollbar();
    return;
  }
  if (!list.some((cvar) => cvar.name === state.selected)) {
    state.selected = list[0].name;
  }

  const scrollTop = viewport.scrollTop;
  rowsEl.innerHTML = list
    .map((cvar) => {
      const selected = cvar.name === state.selected;
      const changed = isChanged(cvar);
      const readonly = cvar.readonly ? "readonly" : "";
      const kind = binaryKind(cvar);
      const defDisplay = kind ? `${cvar.def.length} bytes` : /^\s*$/.test(cvar.def) ? "empty" : cvar.def;
      const defaultValue = changed
        ? `<span class="default-value">(Default: ${escapeHtml(defDisplay)})</span>`
        : "";
      const fav = isFavorite(cvar);
      return `
        <div class="row ${selected ? "selected" : ""} ${readonly}" data-name="${escapeHtml(cvar.name)}" role="button" tabindex="0">
          <button type="button" class="fav-toggle" tabindex="-1" aria-pressed="${fav}" aria-label="${fav ? "Remove from favorites" : "Add to favorites"}">${FAV_MARK}</button>
          <span class="name ${changed ? "changed" : ""}">${escapeHtml(cvar.name)}</span>
          <span class="gauge-cell">${gaugeFor(cvar)}</span>
          <span class="value">${escapeHtml(valueDisplay(cvar))}${defaultValue}</span>
        </div>`;
    })
    .join("");

  viewport.scrollTop = scrollTop;
  const withRange = list.filter((cvar) => cvar.helpMin != null || cvar.helpMax != null || cvar.observedMin != null || cvar.observedMax != null).length;
  countEl.textContent = `${list.length} / ${CVARS.length} CVars, ${withRange} with range`;
  updateScrollbar();
}

function renderDetail() {
  const cvar = selectedCvar();
  if (!cvar) {
    detailNameEl.textContent = "";
    detailNameEl.className = "";
    detailMetaEl.innerHTML = "";
    detailHelpEl.textContent = "";
    valueEditEl.value = "";
    valueEditEl.disabled = true;
    setButtonEl.disabled = true;
    resetButtonEl.disabled = true;
    setStatus("", "");
    return;
  }

  const changed = isChanged(cvar);
  detailNameEl.textContent = cvar.name;
  detailNameEl.className = changed ? "changed" : "";
  if (cvar.readonly) {
    detailNameEl.classList.add("readonly");
  }

  // Up to 8 parts in the runtime's order (META_MAX_PARTS = 8). Range help
  // and Help range never appear together, so the fullest line is 8 parts
  // and the Secure part is never dropped.
  const meta = [
    { text: cvar.scope },
    { text: cvar.category },
    { text: `Type: ${valueType(cvar)}` },
    { text: `Default: ${defaultDisplay(cvar)}` },
  ];
  if (cvar.range && cvar.source === "help") {
    meta.push({ text: `Range help: ${cvar.range}` });
  }
  if (cvar.observed) {
    meta.push({ text: `Observed: ${cvar.observed}`, className: "meta-observed" });
  }
  if (cvar.helpRange && cvar.source === "observed" && cvar.helpRange !== cvar.range) {
    meta.push({ text: `Help range: ${cvar.helpRange}` });
  }
  if (cvar.readonly) {
    meta.push({ text: "Read-only" });
  } else if (cvar.locked) {
    meta.push({ text: "Locked" });
  }
  if (cvar.secure) {
    meta.push({ text: "Secure: locked in combat", className: "meta-warning" });
  }
  detailMetaEl.innerHTML = meta
    .filter(({ text }) => Boolean(text))
    .map(({ text, className }) => `<span${className ? ` class="${className}"` : ""}>${escapeHtml(text)}</span>`)
    .join("");

  detailHelpEl.textContent = cvar.help ?? "";
  valueEditEl.value = editText(cvar, cvar.value);
  const editable = isEditable(cvar);
  valueEditEl.disabled = !editable;
  setButtonEl.disabled = !editable;
  resetButtonEl.disabled = !editable;
  setStatus("", "");
}

function render() {
  renderRows();
  renderDetail();
  renderControls();
}

function updateScrollbar() {
  const scrollHeight = viewport.scrollHeight;
  const clientHeight = viewport.clientHeight;
  if (scrollHeight <= clientHeight + 1) {
    scrollbar.classList.add("hidden");
    return;
  }
  scrollbar.classList.remove("hidden");
  // Thumb geometry maps to the track column (the 8px strip spanning the two
  // list separators) instead of the row viewport, so the thumb always
  // travels the full height of the column.
  const trackHeight = scrollbar.clientHeight;
  const thumbHeight = Math.max(32, Math.round((trackHeight * clientHeight) / scrollHeight));
  const maxTop = trackHeight - thumbHeight;
  const maxScroll = scrollHeight - clientHeight;
  const top = maxScroll > 0 ? Math.round((viewport.scrollTop / maxScroll) * maxTop) : 0;
  scrollbarThumb.style.height = `${thumbHeight}px`;
  scrollbarThumb.style.top = `${top}px`;
}

/* ---- Scrolling ----
   Mirrors the runtime's g_frame.scroll_frame_to / smooth_step. Every offset
   is a whole pixel. A smooth scroll records a target and eases toward it.
   Each frame moves round(diff * min(1, elapsed * 16)) px, at least 1px, and
   the last step lands exactly on the target. With smooth off (lab toggle,
   `/cvars smooth off`) the same requests jump straight to the target. */
const SCROLL_EASE_RATE = 16;
const WHEEL_ROWS = 3;
const FILTER_WHEEL_STEP = 40;
const scrollGlides = new WeakMap();

function rowHeight() {
  return (SCALES[state.scale] ?? SCALES[DEFAULTS.scale]).row;
}

function scrollRange(el) {
  return Math.max(0, el.scrollHeight - el.clientHeight);
}

function glideStep(el, now) {
  const glide = scrollGlides.get(el);
  if (!glide) {
    return;
  }
  const elapsed = glide.last ? (now - glide.last) / 1000 : 1 / 60;
  glide.last = now;
  const target = Math.min(glide.target, scrollRange(el));
  const current = Math.round(el.scrollTop);
  const diff = target - current;
  if (Math.abs(diff) < 1) {
    scrollGlides.delete(el);
    el.scrollTop = target;
    return;
  }
  let step = Math.round(diff * Math.min(1, elapsed * SCROLL_EASE_RATE));
  if (step === 0) {
    step = Math.sign(diff);
  }
  el.scrollTop = current + step;
  if (Math.round(el.scrollTop) === current) {
    // Browser zoom can quantize scrollTop, so never let a glide stall.
    scrollGlides.delete(el);
    el.scrollTop = target;
    return;
  }
  glide.frame = requestAnimationFrame((time) => glideStep(el, time));
}

function scrollFrameTo(el, value, smooth) {
  const target = Math.min(Math.max(Math.round(value), 0), scrollRange(el));
  const glide = scrollGlides.get(el);
  if (smooth && state.smooth) {
    if (glide) {
      glide.target = target;
    } else {
      const next = { target, last: 0, frame: 0 };
      scrollGlides.set(el, next);
      next.frame = requestAnimationFrame((time) => glideStep(el, time));
    }
    return;
  }
  if (glide) {
    cancelAnimationFrame(glide.frame);
    scrollGlides.delete(el);
  }
  el.scrollTop = target;
}

/* Wheel notches add onto the pending target, not the current offset, so a
   fast spin accumulates. */
function scrollBase(el) {
  return scrollGlides.get(el)?.target ?? el.scrollTop;
}

function wheelNotches(event) {
  if (event.deltaMode === 1) {
    return event.deltaY / 3; // lines, 3 per notch
  }
  if (event.deltaMode === 2) {
    return event.deltaY; // pages
  }
  return event.deltaY / 100; // pixels, ~100 per notch
}

/* Search, filter, regex, and sort changes rebuild the view at the top,
   instantly, dropping any pending glide. A rebuild also hides the row
   tooltip, cold. */
function jumpListToTop() {
  scrollFrameTo(viewport, 0, false);
  hideTooltip(false);
}

function applyValue() {
  const cvar = selectedCvar();
  if (!cvar) {
    return;
  }
  if (cvar.readonly) {
    setStatus("This CVar is read-only.", "error");
    return;
  }
  if (cvar.locked) {
    setStatus("This CVar is locked.", "error");
    return;
  }

  let requested = valueEditEl.value.trim();
  const previous = cvar.value;
  if (binaryKind(cvar)) {
    const decoded = hexToBytes(requested);
    if (decoded == null) {
      setStatus("Bitfield/serialized value must be an even-length hex string.", "error");
      return;
    }
    requested = decoded;
  }
  if (cvar.ignoreSet) {
    setStatus(`Ignored: ${cvar.name} stays ${editText(cvar, previous)}`, "error");
    return;
  }

  const requestedNumber = Number(requested);
  const previousNumber = Number(previous);
  const numeric =
    requested !== "" &&
    Number.isFinite(requestedNumber) &&
    Number.isFinite(previousNumber);

  let actual = requested;
  let outcome = "accepted";

  if (numeric) {
    if (cvar.helpMax != null && requestedNumber > cvar.helpMax) {
      actual = String(cvar.helpMax);
      outcome = "clamped";
    } else if (cvar.observedMax != null && requestedNumber > cvar.observedMax) {
      actual = String(cvar.observedMax);
      outcome = "clamped";
    } else if (cvar.helpMin != null && requestedNumber < cvar.helpMin) {
      actual = String(cvar.helpMin);
      outcome = "clamped";
    } else if (cvar.observedMin != null && requestedNumber < cvar.observedMin) {
      actual = String(cvar.observedMin);
      outcome = "clamped";
    }
  }

  if (actual !== previous) {
    pushHistory(cvar.name, previous, actual);
  }
  cvar.value = actual;
  if (outcome === "clamped") {
    cvar.clampedAt = Number(actual);
    cvar.clampSide = requestedNumber > Number(actual) ? "high" : "low";
  } else {
    cvar.clampedAt = null;
    cvar.clampSide = null;
  }

  render();
  setStatus(
    outcome === "clamped"
      ? `${cvar.name} clamped to ${editText(cvar, actual)} (asked ${editText(cvar, requested)})`
      : `Set ${cvar.name} = ${editText(cvar, actual)}`,
    outcome === "clamped" ? "warning" : "success",
  );
  valueEditEl.focus();
  valueEditEl.select();
}

function resetValue() {
  const cvar = selectedCvar();
  if (!cvar || !isEditable(cvar)) {
    return;
  }
  if (cvar.value !== cvar.def) {
    pushHistory(cvar.name, cvar.value, cvar.def);
  }
  cvar.value = cvar.def;
  cvar.clampedAt = null;
  cvar.clampSide = null;
  render();
  setStatus(`Reset ${cvar.name} to ${editText(cvar, cvar.def)}`, "success");
  valueEditEl.focus();
  valueEditEl.select();
}

/* ---- History (undo / redo) ---- */

function pushHistory(name, from, to) {
  history.undo.push({ name, from, to });
  if (history.undo.length > 50) {
    history.undo.shift();
  }
  history.redo.length = 0;
}

function undo() {
  const entry = history.undo.pop();
  if (!entry) {
    return;
  }
  const cvar = CVARS.find((c) => c.name === entry.name);
  if (!cvar) {
    return;
  }
  cvar.value = entry.from;
  cvar.clampedAt = null;
  cvar.clampSide = null;
  history.redo.push(entry);
  state.selected = entry.name;
  render();
  setStatus(`Undid ${entry.name} to ${editText(cvar, entry.from)}`, "success");
}

function redo() {
  const entry = history.redo.pop();
  if (!entry) {
    return;
  }
  const cvar = CVARS.find((c) => c.name === entry.name);
  if (!cvar) {
    return;
  }
  cvar.value = entry.to;
  cvar.clampedAt = null;
  cvar.clampSide = null;
  history.undo.push(entry);
  state.selected = entry.name;
  render();
  setStatus(`Redid ${entry.name} to ${editText(cvar, entry.to)}`, "success");
}

/* ---- Control row (chips, menus, history, copy) ---- */

function renderControls() {
  const filterCount = activeFilterCount();
  // One text run with ordinary spaces, as the runtime's update_filter_chip.
  filterLabelEl.textContent = filterCount ? `Filters ${filterCount}` : "Filters off";
  filterChipEl.classList.toggle("active", filterCount > 0);
  filterChipEl.title = filterCount ? `Active filters: ${filterSummary()}` : "No active filters";

  const sortActive = state.sort.key !== "name" || state.sort.dir !== "asc";
  sortLabelEl.textContent = `Sort ${state.sort.key} ${state.sort.dir}`;
  sortChipEl.classList.toggle("active", sortActive);

  regexChipEl.setAttribute("aria-pressed", String(state.regex));

  undoButtonEl.disabled = history.undo.length === 0;
  redoButtonEl.disabled = history.redo.length === 0;

  copyButtonEl.disabled = !selectedCvar();

  // Re-toggling a facet re-renders the open menu. Keep its scroll position so
  // the list doesn't snap back to the top.
  const refresh = (menu, html) => {
    const scrollTop = menu.scrollTop;
    menu.innerHTML = html;
    menu.scrollTop = scrollTop;
  };
  if (openMenu === filterMenuEl) {
    refresh(filterMenuEl, filterMenuHtml());
  } else if (openMenu === sortMenuEl) {
    refresh(sortMenuEl, sortMenuHtml());
  } else if (openMenu === copyMenuEl) {
    refresh(copyMenuEl, copyMenuHtml());
  } else if (openMenu === sizeMenuEl) {
    refresh(sizeMenuEl, sizeMenuHtml());
  }
}

function filterMenuHtml() {
  const f = state.filters;
  const rows = (facet, values, current) =>
    values
      .map(([value, label]) => {
        const checked = Array.isArray(current) ? current.includes(value) : current === value;
        return `<button type="button" class="menu-row ${checked ? "checked" : ""}" role="menuitem" data-facet="${facet}" data-value="${escapeHtml(value)}"><span class="menu-check" aria-hidden="true"></span>${escapeHtml(label)}</button>`;
      })
      .join("");

  const categories = [...new Set(CVARS.map((c) => c.category))].sort();
  return `
    <div class="menu-header">Filters <button type="button" class="menu-clear" id="filter-clear"${activeFilterCount() || state.changedOnly ? "" : " disabled"}>Clear all</button></div>
    <div class="menu-group">
      <span class="menu-group-label">Scope</span>
      ${rows("scope", [["all", "All"], ["account", "Account"], ["character", "Character"], ["local", "Local"]], f.scope)}
    </div>
    <div class="menu-group">
      <span class="menu-group-label">Category</span>
      ${rows("category", [["all", "All"], ...categories.map((c) => [c.toLowerCase(), c])], f.category)}
    </div>
    <div class="menu-group">
      <span class="menu-group-label">Type</span>
      ${rows("type", [["all", "All"], ["number", "Number"], ["text", "Text"], ["boolean", "Boolean"], ["enum", "Enum"], ["list", "List"], ["bitfield", "Bitfield"], ["serialized", "Serialized"]], f.type)}
    </div>
    <div class="menu-group">
      <span class="menu-group-label">Has</span>
      ${rows("has", [["range", "Range"], ["observed", "Observed bounds"], ["help", "Help range"], ["default", "Default"], ["changed", "Differs from default"], ["favorite", "Favorite"]], f.has)}
    </div>`;
}

function sortMenuHtml() {
  const labels = {
    name: "Name",
    type: "Type",
    scope: "Scope",
    category: "Category",
    changed: "Changed",
    range: "Range width",
  };
  return SORT_KEYS.map((key) => {
    const active = state.sort.key === key;
    return `<button type="button" class="menu-row ${active ? "checked" : ""}" role="menuitem" data-sort="${key}"><span class="menu-check" aria-hidden="true"></span>${labels[key]}<span class="menu-note">${active ? state.sort.dir : ""}</span></button>`;
  }).join("");
}

function sizeMenuHtml() {
  return PRESETS.map((option) => {
    const active = state.preset === option.value;
    return `<button type="button" class="menu-row size-row${active ? " selected" : ""}" role="menuitemradio" aria-checked="${active}" data-preset="${option.value}">${escapeHtml(option.label)}</button>`;
  }).join("");
}

function copyMenuHtml() {
  const cvar = selectedCvar();
  if (!cvar) {
    return "";
  }
  const rows = [
    ["value", "Copy value", ""],
    ["raw", "Copy raw value", ""],
    ["default", "Copy default", ""],
    ["name", "Copy name", ""],
    ["help", "Copy help", cvar.help ? "" : "none"],
    ["range", "Copy range", cvar.range ? "" : "none"],
  ];
  return rows
    .map(([key, label, note]) => {
      const disabled = note === "none";
      return `<button type="button" class="menu-row" role="menuitem" data-copy="${key}"${disabled ? " disabled" : ""}>${escapeHtml(label)}<span class="menu-note">${escapeHtml(note)}</span></button>`;
    })
    .join("");
}

/* CopyToClipboard is protected for addons, so nothing writes the clipboard.
   Copying opens a small box under the Copy button holding the text, focused
   and fully highlighted, and the status line asks for Ctrl+C. */
let copyBoxText = "";

function highlightCopyBox() {
  // Select everything with the caret at the start, so long text shows its
  // beginning.
  copyBoxInputEl.setSelectionRange(0, copyBoxInputEl.value.length, "backward");
  copyBoxInputEl.scrollLeft = 0;
}

function showCopyBox(text) {
  copyBoxText = text;
  copyBoxEl.hidden = false;
  copyBoxInputEl.value = text;
  copyBoxInputEl.focus();
  highlightCopyBox();
  hideTooltip(false);
}

function copyField(key) {
  const cvar = selectedCvar();
  if (!cvar) {
    return;
  }
  const fields = {
    value: editText(cvar, cvar.value),
    raw: cvar.value,
    default: cvar.def,
    name: cvar.name,
    help: cvar.help ?? "",
    range: cvar.range ?? "",
  };
  const text = fields[key] ?? "";
  if (text === "") {
    // The runtime says this in chat. The mockup borrows the status line.
    setStatus(`Nothing to copy for ${cvar.name}`, "");
    return;
  }
  closeMenus();
  showCopyBox(text);
  setStatus(`Press Ctrl+C to copy ${key}: ${cvar.name}`, "success");
}

let openMenu = null;
let openMenuButton = null;

function closeMenus() {
  for (const menu of [filterMenuEl, sortMenuEl, copyMenuEl, sizeMenuEl]) {
    menu.hidden = true;
  }
  copyBoxEl.hidden = true;
  for (const chip of [filterChipEl, sortChipEl, copyButtonEl, sizeButtonEl]) {
    chip.setAttribute("aria-expanded", "false");
  }
  openMenu = null;
  openMenuButton = null;
}

function toggleMenu(button, menu, html) {
  const wasOpen = openMenu === menu;
  closeMenus();
  if (wasOpen) {
    return;
  }
  menu.innerHTML = html();
  hideTooltip(false);
  menu.hidden = false;
  button.setAttribute("aria-expanded", "true");
  openMenu = menu;
  openMenuButton = button;
}

function clearFilters() {
  state.filters = { scope: "all", category: "all", type: "all", has: [] };
  state.changedOnly = false;
  changedOnlyEl.checked = false;
  jumpListToTop();
  render();
  setStatus("Filters cleared", "");
}

function applyScenario(name) {
  closeMenus();
  hideTooltip(false);
  state.query = "";
  searchEl.value = "";
  searchNavigated = false;
  state.regex = false;
  state.changedOnly = false;
  changedOnlyEl.checked = false;
  state.filters = { scope: "all", category: "all", type: "all", has: [] };
  state.sort = { key: "name", dir: "asc" };
  state.favorites = new Set(DEFAULT_FAVORITES);
  history.undo.length = 0;
  history.redo.length = 0;

  let note = "";
  switch (name) {
    case "filters":
      state.filters = { scope: "account", category: "all", type: "number", has: ["changed"] };
      note = "Active filters: scope:account, type:number, has:changed";
      break;
    case "sort":
      state.sort = { key: "changed", dir: "desc" };
      note = "Active sort: changed desc";
      break;
    case "undo":
      note = "History cleared: undo and redo disabled";
      break;
    case "copy":
      state.query = "no such cvar";
      searchEl.value = state.query;
      note = "No selection: copy disabled";
      break;
    case "favorites":
      state.filters = { scope: "all", category: "all", type: "all", has: ["favorite"] };
      note = "Active filters: has:favorite";
      break;
    case "value":
      state.query = "value:=1";
      searchEl.value = state.query;
      note = "Search value:=1 keeps values that are exactly 1";
      break;
    case "tooltip":
      state.query = "realm";
      searchEl.value = state.query;
      note = "Row tooltip for realmList, held open until the pointer reaches the list";
      break;
    default:
      break;
  }
  jumpListToTop();
  render();
  // Posted after the render because renderDetail clears the status line, and
  // the scenario note must live its full 30s like every other status.
  setStatus(note, "");
  if (name === "tooltip") {
    // After this frame's scroll events, so the jump to the top cannot hide it.
    requestAnimationFrame(() => showTooltip({ name: "realmList", toggle: false }));
  }
}

function applyPalette(key) {
  const palette = PALETTES[key] ?? PALETTES[DEFAULTS.palette];
  state.palette = key in PALETTES ? key : DEFAULTS.palette;
  const variables = {
    "--bg": palette.bg,
    "--surface": palette.surface,
    "--surface-hover": palette.hover,
    "--border": palette.border,
    "--text": palette.text,
    "--muted": palette.muted,
    "--accent": palette.accent,
    "--accent-rgb": palette.accentRgb,
    "--observed": palette.observed,
    "--warning": palette.warning,
    "--success": palette.success,
    "--error": palette.error,
    "--changed": palette.changed,
  };
  for (const [name, value] of Object.entries(variables)) {
    app.style.setProperty(name, value);
  }
  document.documentElement.style.setProperty("--lab-accent", palette.accent);

  for (const button of paletteSwitchEl.querySelectorAll("button")) {
    const candidate = PALETTES[button.dataset.palette];
    if (!candidate) {
      continue;
    }
    button.classList.toggle("active", button.dataset.palette === state.palette);
    const swatches = button.querySelectorAll(".palette-swatches i");
    if (swatches.length === 4) {
      swatches[0].style.setProperty("--swatch", candidate.bg);
      swatches[1].style.setProperty("--swatch", candidate.surface);
      swatches[2].style.setProperty("--swatch", candidate.accent);
      swatches[3].style.setProperty("--swatch", candidate.observed);
    }
    const label = button.querySelector(".palette-name");
    if (label) {
      label.textContent = candidate.name;
    }
  }
  updateSelection();
}

function applyFonts() {
  const font = FONTS[state.font] ?? FONTS[DEFAULTS.font];
  app.style.setProperty("--font-ui", font.css);
  app.style.setProperty(
    "--font-data",
    state.data === "mono" ? "var(--font-mono)" : font.css,
  );
  fontSelectEl.value = state.font;
  dataSelectEl.value = state.data;
  updateSelection();
}

function applyScale(scale) {
  const resolved = SCALES[scale] ?? SCALES[DEFAULTS.scale];
  // The text-size switch changes row height, so it changes the scroll range
  // the way a runtime size preset does (OnScrollRangeChanged). A list at the
  // bottom stays pinned there. Otherwise the browser clamps the offset and
  // glideStep clamps any pending target into the new range.
  const before = scrollRange(viewport);
  const wasAtBottom = before > 0 && viewport.scrollTop >= before - 0.5;
  state.scale = SCALES[scale] ? Number(scale) : DEFAULTS.scale;
  app.style.setProperty("--body-size", `${state.scale}px`);
  app.style.setProperty("--small-size", `${resolved.small}px`);
  app.style.setProperty("--row-height", `${resolved.row}px`);
  app.style.setProperty("--detail-name-size", `${resolved.detail}px`);
  for (const button of scaleSwitchEl.querySelectorAll("button")) {
    button.classList.toggle("active", Number(button.dataset.scale) === state.scale);
  }
  if (wasAtBottom) {
    scrollFrameTo(viewport, scrollRange(viewport), false);
  }
  updateSelection();
  updateScrollbar();
}

function presetLabel(value) {
  const option = PRESETS.find((candidate) => candidate.value === value);
  return option ? option.label : "Auto";
}

function applyPreset(value) {
  state.preset = PRESETS.some((option) => option.value === value)
    ? value
    : DEFAULTS.preset;
  sizeButtonEl.textContent = `Size: ${presetLabel(state.preset)}`;
  updateSelection();
}

// Mirrors the runtime subtitle rule in DESIGN.md (Title bar).
function subtitleText({ version, xBuild }) {
  const raw = (version ?? "").trim();
  if (raw === "" || raw.toLowerCase() === "dev") {
    return "WoW Forever · dev";
  }
  const parts = ["WoW Forever", `v${raw.replace(/^v/i, "")}`];
  const token = (xBuild ?? "").trim().split(/\s+/)[0];
  if (/^[0-9a-f]+$/i.test(token)) {
    parts.push(token);
  }
  return parts.join(" · ");
}

function applyBuild(value) {
  state.build = value in BUILDS ? value : DEFAULTS.build;
  subtitleEl.textContent = subtitleText(BUILDS[state.build]);
  for (const button of buildSwitchEl.querySelectorAll("button")) {
    button.classList.toggle("active", button.dataset.build === state.build);
  }
}

function updateSelection() {
  const palette = PALETTES[state.palette];
  const font = FONTS[state.font];
  selectionEl.innerHTML = [
    `Palette <strong>${escapeHtml(palette.name)}</strong>`,
    `Font <strong>${escapeHtml(font.label)}</strong>`,
    `Text <strong>${state.scale}px</strong>`,
    `Size <strong>${escapeHtml(presetLabel(state.preset))}</strong>`,
    `Data <strong>${state.data === "mono" ? "JetBrains Mono" : "Same as UI"}</strong>`,
    `Accent <strong>${palette.accent}</strong>`,
  ].join(" | ");
}

function saveState() {
  try {
    localStorage.setItem(
      "cvarbrowser-mockup-v2",
      JSON.stringify({
        palette: state.palette,
        font: state.font,
        data: state.data,
        scale: state.scale,
        preset: state.preset,
        smooth: state.smooth,
        build: state.build,
      }),
    );
  } catch {
    // Storage can be unavailable. The mockup works without it.
  }
}

function loadState() {
  try {
    const raw = localStorage.getItem("cvarbrowser-mockup-v2");
    if (!raw) {
      return;
    }
    const saved = JSON.parse(raw);
    if (saved.palette in PALETTES) state.palette = saved.palette;
    if (saved.font in FONTS) state.font = saved.font;
    if (saved.data === "sans" || saved.data === "mono") state.data = saved.data;
    if (saved.scale in SCALES) state.scale = Number(saved.scale);
    if (PRESETS.some((option) => option.value === saved.preset)) {
      state.preset = saved.preset;
    }
    if (typeof saved.smooth === "boolean") state.smooth = saved.smooth;
    if (saved.build in BUILDS) state.build = saved.build;
  } catch {
    // Ignore corrupt storage.
  }
}

function resetOptions() {
  state.palette = DEFAULTS.palette;
  state.font = DEFAULTS.font;
  state.data = DEFAULTS.data;
  state.scale = DEFAULTS.scale;
  state.preset = DEFAULTS.preset;
  state.smooth = DEFAULTS.smooth;
  smoothToggleEl.checked = state.smooth;
  applyPalette(state.palette);
  applyFonts();
  applyScale(state.scale);
  applyPreset(state.preset);
  applyBuild(DEFAULTS.build);
  saveState();
}

/* ---- Row tooltip ----
   Mirrors the runtime row tooltip (DESIGN.md, Row tooltip). It shows after
   the pointer rests 500ms on a row. While it is up, or within 100ms of it
   hiding, the next row swaps in at once. Its text column lines up with the
   row's name column (panel x = row x + 14, text 8px in), 4px below the row,
   or 4px above it when below would come within 8px of the window's bottom.
   Over the favorite toggle it holds one action line instead. */
const TOOLTIP_DELAY_MS = 500;
const TOOLTIP_WARM_MS = 100;
const tooltipEl = document.getElementById("row-tooltip");
let tipTimer = 0;
let tipKey = "";
let tipHiddenAt = -Infinity;
let tipPointer = null;
let pointerOverApp = false;

function tooltipTarget(el) {
  const row = el instanceof Element ? el.closest(".row") : null;
  if (!row || !rowsEl.contains(row)) {
    return null;
  }
  return { name: row.dataset.name, toggle: Boolean(el.closest(".fav-toggle")) };
}

function tooltipKeyOf(target) {
  return target ? `${target.name}${target.toggle ? "|toggle" : ""}` : "";
}

function tooltipHtml(cvar, toggle) {
  if (toggle) {
    return `<div class="tip-line tip-action">${isFavorite(cvar) ? "Remove from favorites" : "Add to favorites"}</div>`;
  }
  // The name takes the row's name color: muted when read-only, changed lilac
  // when it differs from default, text otherwise.
  const tone = cvar.readonly ? " readonly" : isChanged(cvar) ? " changed" : "";
  const value = valueDisplay(cvar);
  const lines = [
    `<div class="tip-line tip-name${tone}">${escapeHtml(cvar.name)}</div>`,
    `<div class="tip-line tip-value">Value: ${escapeHtml(/^\s*$/.test(value) ? "empty" : value)}</div>`,
  ];
  if (isChanged(cvar)) {
    lines.push(`<div class="tip-line tip-default">Default: ${escapeHtml(defaultDisplay(cvar))}</div>`);
  }
  if (cvar.help && cvar.help.trim()) {
    lines.push(`<div class="tip-line tip-help">${escapeHtml(cvar.help.trim())}</div>`);
  }
  return lines.join("");
}

function showTooltip(target) {
  const cvar = CVARS.find((c) => c.name === target.name);
  const row = [...rowsEl.querySelectorAll(".row")].find((el) => el.dataset.name === target.name);
  if (!cvar || !row) {
    return;
  }
  tooltipEl.innerHTML = tooltipHtml(cvar, target.toggle);
  tooltipEl.hidden = false;
  const appRect = app.getBoundingClientRect();
  const rowRect = row.getBoundingClientRect();
  const rowTop = Math.round(rowRect.top - appRect.top - app.clientTop);
  const height = tooltipEl.offsetHeight;
  let top = rowTop + rowRect.height + 4;
  if (top + height > app.clientHeight - 8 && rowTop - 4 - height >= 8) {
    top = rowTop - 4 - height;
  }
  tooltipEl.style.left = `${Math.round(rowRect.left - appRect.left - app.clientLeft) + 14}px`;
  tooltipEl.style.top = `${top}px`;
}

// A warm hide (the pointer left the row) lets the next row show at once. A
// cold hide (click, scroll, menu) makes the next show wait the full delay.
function hideTooltip(warm) {
  clearTimeout(tipTimer);
  tipTimer = 0;
  if (warm && !tooltipEl.hidden) {
    tipHiddenAt = performance.now();
  } else if (!warm) {
    tipHiddenAt = -Infinity;
  }
  tooltipEl.hidden = true;
}

function armTooltip(target) {
  clearTimeout(tipTimer);
  tipTimer = 0;
  if (openMenu || !copyBoxEl.hidden || scrollDrag) {
    return;
  }
  if (!tooltipEl.hidden || performance.now() - tipHiddenAt <= TOOLTIP_WARM_MS) {
    showTooltip(target);
    return;
  }
  tipTimer = setTimeout(() => {
    tipTimer = 0;
    showTooltip(target);
  }, TOOLTIP_DELAY_MS);
}

rowsEl.addEventListener("pointermove", (event) => {
  tipPointer = { x: event.clientX, y: event.clientY };
  const target = tooltipTarget(event.target);
  const key = tooltipKeyOf(target);
  if (key === tipKey) {
    return;
  }
  tipKey = key;
  if (target) {
    armTooltip(target);
  } else {
    hideTooltip(true);
  }
});

rowsEl.addEventListener("pointerleave", () => {
  tipPointer = null;
  tipKey = "";
  hideTooltip(true);
});

app.addEventListener("pointerenter", () => {
  pointerOverApp = true;
});
app.addEventListener("pointerleave", () => {
  pointerOverApp = false;
});

/* Clicking the toggle flips the favorite without selecting the row. The
   runtime rebuilds with keep_scroll, so the list keeps its offset while the
   row moves into or out of the favorites group. */
function toggleFavorite(name) {
  const added = !state.favorites.has(name);
  if (added) {
    state.favorites.add(name);
  } else {
    state.favorites.delete(name);
  }
  render();
  setStatus(added ? `Added ${name} to favorites` : `Removed ${name} from favorites`, "success");
}

rowsEl.addEventListener("click", (event) => {
  const row = event.target.closest(".row");
  if (!row) {
    return;
  }
  // A click hides the tooltip until the pointer reaches another row.
  hideTooltip(false);
  if (event.target.closest(".fav-toggle")) {
    toggleFavorite(row.dataset.name);
    return;
  }
  state.selected = row.dataset.name;
  render();
});

/* Navigation keys, as the runtime's move_selection. Up/Down step one row,
   PageUp/PageDown step one page (the rows the list shows whole, 15 at
   Standard), Home/End jump to the ends. The selected row glides to the top
   of the list, clamped at the bottom of the range. */
function moveSelection(key) {
  const list = filteredCvars();
  const page = Math.max(1, Math.floor(viewport.clientHeight / rowHeight()));
  const steps = {
    ArrowUp: -1,
    ArrowDown: 1,
    PageUp: -page,
    PageDown: page,
    Home: -list.length,
    End: list.length,
  };
  if (!(key in steps)) {
    return false;
  }
  if (list.length === 0) {
    return true;
  }
  const current = Math.max(0, list.findIndex((cvar) => cvar.name === state.selected));
  const index = Math.min(Math.max(current + steps[key], 0), list.length - 1);
  state.selected = list[index].name;
  render();
  scrollFrameTo(viewport, index * rowHeight(), true);
  return true;
}

function clearSearch() {
  searchEl.value = "";
  state.query = "";
  searchNavigated = false;
  jumpListToTop();
  render();
}

rowsEl.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" && event.key !== " ") {
    return;
  }
  const row = event.target.closest(".row");
  if (!row) {
    return;
  }
  event.preventDefault();
  state.selected = row.dataset.name;
  render();
});

searchEl.addEventListener("input", () => {
  state.query = searchEl.value;
  searchNavigated = false;
  jumpListToTop();
  render();
});

/* The runtime hides the placeholder while the search box has focus (the
   caret blinks where the placeholder starts) and shows it again on blur
   when the box is empty. The native placeholder covers the empty case, and
   the attribute swap handles focus. */
const SEARCH_PLACEHOLDER = searchEl.placeholder;
searchEl.addEventListener("focus", () => {
  searchEl.placeholder = "";
});
searchEl.addEventListener("blur", () => {
  searchEl.placeholder = SEARCH_PLACEHOLDER;
});

// The first Escape clears the search text and a second one leaves the box.
// Home and End stay with the box, where they move the caret.
searchEl.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    event.stopPropagation();
    if (searchEl.value !== "") {
      clearSearch();
    } else {
      searchEl.blur();
    }
    return;
  }
  if (event.key !== "Home" && event.key !== "End" && moveSelection(event.key)) {
    event.preventDefault();
    searchNavigated = true;
    return;
  }
  if (event.key !== "Enter") {
    return;
  }
  event.preventDefault();
  // Enter keeps a row picked with the arrow keys. With no arrow navigation
  // since the text last changed, it takes the first result.
  const entry = (searchNavigated && selectedCvar()) || filteredCvars()[0];
  if (!entry) {
    searchEl.blur();
    return;
  }
  state.selected = entry.name;
  render();
  if (isEditable(entry)) {
    valueEditEl.focus();
    valueEditEl.select();
  }
});

changedOnlyEl.addEventListener("change", () => {
  state.changedOnly = changedOnlyEl.checked;
  jumpListToTop();
  render();
});

setButtonEl.addEventListener("click", applyValue);
resetButtonEl.addEventListener("click", resetValue);

valueEditEl.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    applyValue();
  } else if (event.key === "Escape") {
    valueEditEl.blur();
  }
});

// Scrolling hides the tooltip. Each scroll step restarts the full delay for
// the row now under the pointer, so it returns once the list comes to rest.
viewport.addEventListener("scroll", () => {
  updateScrollbar();
  hideTooltip(false);
  const target = tipPointer && !scrollDrag
    ? tooltipTarget(document.elementFromPoint(tipPointer.x, tipPointer.y))
    : null;
  tipKey = tooltipKeyOf(target);
  if (target) {
    armTooltip(target);
  }
}, { passive: true });

let scrollDrag = null;
scrollbarThumb.addEventListener("pointerdown", (event) => {
  scrollDrag = { y: event.clientY, scrollTop: viewport.scrollTop };
  scrollbarThumb.setPointerCapture(event.pointerId);
  event.preventDefault();
});
scrollbarThumb.addEventListener("pointermove", (event) => {
  if (!scrollDrag) {
    return;
  }
  const maxTop = scrollbar.clientHeight - scrollbarThumb.offsetHeight;
  if (maxTop <= 0) {
    return;
  }
  // While held, the list tracks the cursor 1 to 1 in whole-pixel offsets,
  // with no glide.
  const delta = event.clientY - scrollDrag.y;
  scrollFrameTo(viewport, scrollDrag.scrollTop + (delta / maxTop) * scrollRange(viewport), false);
});
// Release settles on the nearest whole row so the top row is never left
// half-clipped.
function endScrollDrag() {
  if (!scrollDrag) {
    return;
  }
  scrollDrag = null;
  const row = rowHeight();
  scrollFrameTo(viewport, Math.round(viewport.scrollTop / row) * row, true);
}
scrollbarThumb.addEventListener("pointerup", endScrollDrag);
scrollbarThumb.addEventListener("pointercancel", endScrollDrag);

viewport.addEventListener("wheel", (event) => {
  if (event.ctrlKey) {
    return;
  }
  event.preventDefault();
  scrollFrameTo(viewport, scrollBase(viewport) + wheelNotches(event) * WHEEL_ROWS * rowHeight(), true);
}, { passive: false });

paletteSwitchEl.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-palette]");
  if (!button) {
    return;
  }
  applyPalette(button.dataset.palette);
  saveState();
});

fontSelectEl.addEventListener("change", () => {
  state.font = fontSelectEl.value;
  applyFonts();
  saveState();
});

dataSelectEl.addEventListener("change", () => {
  state.data = dataSelectEl.value;
  applyFonts();
  saveState();
});

scaleSwitchEl.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-scale]");
  if (!button) {
    return;
  }
  applyScale(Number(button.dataset.scale));
  saveState();
});

buildSwitchEl.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-build]");
  if (!button) {
    return;
  }
  applyBuild(button.dataset.build);
  saveState();
});

gridToggleEl.addEventListener("change", () => {
  app.classList.toggle("show-grid", gridToggleEl.checked);
});

smoothToggleEl.addEventListener("change", () => {
  state.smooth = smoothToggleEl.checked;
  saveState();
});

document.getElementById("reset").addEventListener("click", resetOptions);

document.getElementById("close").addEventListener("click", () => {
  setStatus("Close button, mockup only", "warning");
});

regexChipEl.addEventListener("click", () => {
  state.regex = !state.regex;
  jumpListToTop();
  render();
  setStatus(state.regex ? "Search treats the query as a regular expression" : "Literal search", "");
});

filterChipEl.addEventListener("click", () => {
  toggleMenu(filterChipEl, filterMenuEl, filterMenuHtml);
});

filterMenuEl.addEventListener("click", (event) => {
  const clear = event.target.closest("#filter-clear");
  if (clear) {
    clearFilters();
    filterMenuEl.innerHTML = filterMenuHtml();
    return;
  }
  const row = event.target.closest(".menu-row[data-facet]");
  if (!row) {
    return;
  }
  const { facet, value } = row.dataset;
  if (facet === "has") {
    const has = state.filters.has;
    const index = has.indexOf(value);
    if (index >= 0) {
      has.splice(index, 1);
    } else {
      has.push(value);
    }
  } else {
    state.filters[facet] = value;
  }
  jumpListToTop();
  render();
  setStatus(activeFilterCount() ? `Filters: ${filterSummary()}` : "Filters cleared", "");
});

filterMenuEl.addEventListener("wheel", (event) => {
  if (event.ctrlKey) {
    return;
  }
  event.preventDefault();
  scrollFrameTo(filterMenuEl, scrollBase(filterMenuEl) + wheelNotches(event) * FILTER_WHEEL_STEP, true);
}, { passive: false });

sortChipEl.addEventListener("click", () => {
  toggleMenu(sortChipEl, sortMenuEl, sortMenuHtml);
});

sortMenuEl.addEventListener("click", (event) => {
  const row = event.target.closest(".menu-row[data-sort]");
  if (!row) {
    return;
  }
  const key = row.dataset.sort;
  if (state.sort.key === key) {
    state.sort.dir = state.sort.dir === "asc" ? "desc" : "asc";
  } else {
    // "changed" reads best with changed rows first. The rest default to a-z.
    state.sort = { key, dir: key === "changed" ? "desc" : "asc" };
  }
  jumpListToTop();
  render();
  setStatus(`Sorted by ${key} ${state.sort.dir}`, "");
});

undoButtonEl.addEventListener("click", undo);
redoButtonEl.addEventListener("click", redo);

copyButtonEl.addEventListener("click", () => {
  if (copyButtonEl.disabled) {
    return;
  }
  toggleMenu(copyButtonEl, copyMenuEl, copyMenuHtml);
});

copyMenuEl.addEventListener("click", (event) => {
  const row = event.target.closest(".menu-row[data-copy]");
  if (!row || row.disabled) {
    return;
  }
  closeMenus();
  copyField(row.dataset.copy);
});

/* Escape, Enter, or losing focus closes the copy box. Typing changes
   nothing, since the text snaps back and stays highlighted. */
copyBoxInputEl.addEventListener("keydown", (event) => {
  if (event.key === "Escape" || event.key === "Enter") {
    event.preventDefault();
    event.stopPropagation();
    copyBoxInputEl.blur();
  }
});
copyBoxInputEl.addEventListener("input", () => {
  copyBoxInputEl.value = copyBoxText;
  highlightCopyBox();
});
copyBoxInputEl.addEventListener("blur", () => {
  copyBoxEl.hidden = true;
});

sizeButtonEl.addEventListener("click", () => {
  toggleMenu(sizeButtonEl, sizeMenuEl, sizeMenuHtml);
});

sizeMenuEl.addEventListener("click", (event) => {
  const row = event.target.closest(".size-row[data-preset]");
  if (!row) {
    return;
  }
  closeMenus();
  applyPreset(row.dataset.preset);
  saveState();
});

scenariosEl.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-scenario]");
  if (!button) {
    return;
  }
  applyScenario(button.dataset.scenario);
});

document.addEventListener("pointerdown", (event) => {
  if (!openMenu) {
    return;
  }
  if (event.target.closest(".popup") || event.target === openMenuButton || event.target.closest(`#${openMenuButton.id}`)) {
    return;
  }
  closeMenus();
});

/* With no edit box focused, Escape closes an open menu, then clears the
   search text, then closes the window. Navigation keys move the selection
   while the pointer is over the window. */
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && openMenu) {
    const button = openMenuButton;
    closeMenus();
    button?.focus();
    return;
  }
  const typing = event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement;
  if (typing) {
    return;
  }
  if (event.key === "Escape") {
    if (searchEl.value !== "") {
      clearSearch();
    } else {
      setStatus("Escape closes the window, mockup only", "warning");
    }
    return;
  }
  if (!event.ctrlKey && !event.altKey && !event.metaKey) {
    if (pointerOverApp && moveSelection(event.key)) {
      event.preventDefault();
    }
    return;
  }
  if (!event.ctrlKey || event.altKey) {
    return;
  }
  const key = event.key.toLowerCase();
  if (key === "z" && !event.shiftKey) {
    event.preventDefault();
    undo();
  } else if (key === "y" || (key === "z" && event.shiftKey)) {
    event.preventDefault();
    redo();
  }
});

loadState();
smoothToggleEl.checked = state.smooth;
applyPalette(state.palette);
applyFonts();
applyScale(state.scale);
applyPreset(state.preset);
applyBuild(state.build);
render();
