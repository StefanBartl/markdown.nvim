---@module 'markdown.config'
---@brief Runtime config store: merge user options over DEFAULTS, expose get().
---@description
--- The public require path stays `markdown.config` (this init.lua). The
--- immutable defaults live in `markdown.config.DEFAULTS`; user options are
--- deep-merged on top on setup(). `get()` returns the resolved table.
---
--- Feature gating: `cfg.features` (`disable` | `enable` | `just_enable`) is
--- resolved once at setup() into a per-feature on/off map, queried everywhere via
--- `feature_enabled(name)`. This lets a user reduce the plugin to a subset, e.g.
--- `features = { just_enable = { "table", "toc" } }` runs ONLY those two.

local notify = require("markdown.util.notify").create("[markdown.config]")

local M = {}

local DEFAULTS = require("markdown.config.DEFAULTS")

--- Canonical, gateable feature names. Anything not listed is always on.
---@type string[]
local FEATURES = {
  "keymaps",
  "fold",
  "hl",
  "link_hl",
  "fenced_fix",
  "fenced_scope",
  "tableview",
  "refs",
  -- :Markdown subcommand features
  "links",
  "toc",
  "table",
  "render",
  "preview",
  "mdview",
  "create",
  "headline_spacing",
  "scope",
  "list",
  "image",
  "export",
  "underline_headings",
  "table_wrap",
  "hover",
  "headings",
}

local FEATURE_SET = {}
for _, f in ipairs(FEATURES) do
  FEATURE_SET[f] = true
end

local _cfg = vim.deepcopy(DEFAULTS)
---@type table<string, boolean>
local _resolved = {}

--- What the last `setup()` had to reject or degrade, one human-readable line
--- each (ERR-50/ERR-22), for `:checkhealth markdown`. Empty when every
--- option `setup()` was called with matched a known key and a valid value.
---@type string[]
local _issues = {}

---@type string[]  Top-level `Mkdn.Config` keys `setup()` accepts.
local TOP_LEVEL_OPTS = {
  "features",
  "progress_style",
  "map_double_asterisk",
  "map_wrap_link",
  "keep_inner_selection",
  "protect_h1",
  "use_zf_override",
  "enable_autocmds",
  "enable_keymaps",
  "ft_only",
  "ensure_headline_spacing",
  "check_heading_gaps",
  "underline_headings",
  "menu",
  "nav",
  "heading_format",
  "keymaps",
  "table",
  "tableview",
  "links",
  "list",
  "hover",
  "image",
  "open",
  "blockquote_hl",
  "link_hl",
  "toc",
  "refs",
  "fenced_fix",
  "fenced_scope",
}

-- A sub-table merged wholesale by `vim.tbl_deep_extend` below would otherwise
-- absorb a typo'd nested key silently -- ERR-50 requires the check to run
-- before that merge, not after. Keyed by dotted path so nesting deeper than
-- one level (`table.wrap.max`, `hover.url.fetch`) is still checked. Left
-- deliberately absent: `keymaps` (top-level; per-binding-id overrides, not
-- named options), `table.wrap_profiles` (profile-name-keyed presets),
-- `table.col_overrides`/`open.external_extensions`/`fenced_scope.langs`
-- (plain lists), and `features.disable`/`enable`/`just_enable` (lists of
-- feature names, already value-checked by `resolve_features`'s own
-- `warn_unknown`) -- all of those are user DATA, not a named-option shape.
---@type table<string, string[]>
local NESTED_OPTS = {
  features = { "disable", "enable", "just_enable" },
  underline_headings = { "char" },
  menu = { "enable", "fold", "toc", "refs" },
  nav = { "fences" },
  heading_format = {
    "strip_emphasis",
    "strip_closing_hashes",
    "collapse_whitespace",
    "strip_trailing_punctuation",
    "capitalize",
    "stopwords",
  },
  table = { "header_align", "entry_align", "col_overrides", "wrap", "wrap_profiles" },
  ["table.wrap"] = {
    "enabled",
    "auto",
    "min",
    "max",
    "pad",
    "join",
    "soft_break_chars",
    "continuation_marker",
    "flavor",
    "auto_resize",
    "resize_debounce_ms",
    "selective_reflow",
  },
  tableview = { "style" },
  links = { "picker", "sanitize_on_save", "diagnostics" },
  ["links.diagnostics"] = { "mode" },
  list = { "picker" },
  hover = {
    "enabled",
    "trigger",
    "delay_ms",
    "placeholder_grace_ms",
    "max_lines",
    "max_width",
    "border",
    "bare_paths",
    "filetypes",
    "inline_images",
    "url",
    "office",
  },
  ["hover.url"] = { "hover", "fetch", "timeout_ms" },
  ["hover.office"] = { "convert", "timeout_ms" },
  image = { "preview" },
  open = { "external_extensions" },
  blockquote_hl = { "marker_fg", "text_fg", "text_bg", "text_bold", "text_italic" },
  fenced_fix = { "inline_base_hl", "inline_style", "delimiter_hl" },
  ["fenced_fix.inline_style"] = { "italic", "bold" },
  fenced_scope = { "enable", "langs", "provider", "operations" },
  ["fenced_scope.operations"] = { "toc", "nav", "jump", "shift", "fold" },
  link_hl = { "underline" },
  toc = { "header", "marker", "min_level", "max_level", "anchor_style", "anchor_separator" },
  refs = { "mode", "debounce_ms", "update_toc", "orphans", "toc_header" },
}

---@internal
--- Nearest allowed key within edit distance 3, as a " (did you mean %q?)"
--- hint, or "" when nothing is close enough to guess.
---@param name string
---@param allowed string[]
---@return string
local function did_you_mean(name, allowed)
  local levenshtein = require("lib.lua.strings.distance").levenshtein
  local best, best_distance = nil, nil
  for _, known in ipairs(allowed) do
    local d = levenshtein(name, known)
    if d <= 3 and (best_distance == nil or d < best_distance) then
      best, best_distance = known, d
    end
  end
  return best and (" (did you mean %q?)"):format(best) or ""
end

---@internal
--- Drop (and record) every key not in `allowed`, recursing into sub-tables
--- named in `NESTED_OPTS` so a typo cannot hide behind the deep merge either.
--- Returns a shallow copy; kept leaf values are the original references, not
--- deep-copied (the merge below deep-copies DEFAULTS, not `opts`).
---@param raw table
---@param allowed string[]
---@param path string  dotted prefix for a nested issue, e.g. "table.wrap."
---@param issues string[]  appended to in place
---@return table
local function sanitize_level(raw, allowed, path, issues)
  local known = {}
  for _, k in ipairs(allowed) do
    known[k] = true
  end

  local out = {}
  for key, value in pairs(raw) do
    if type(key) ~= "string" then
      out[key] = value -- not a named option (e.g. a list entry); nothing to validate
    elseif not known[key] then
      issues[#issues + 1] = ("unknown config key %q%s -- ignored"):format(
        path .. key,
        did_you_mean(key, allowed)
      )
    elseif type(value) == "table" and NESTED_OPTS[path .. key] then
      out[key] = sanitize_level(value, NESTED_OPTS[path .. key], path .. key .. ".", issues)
    else
      out[key] = value
    end
  end
  return out
end

---@internal
--- Degrade the handful of scalars whose valid range isn't "any value of the
--- right Lua type" back to their default when out of range (ERR-22): a
--- silently-accepted bad value here would otherwise only surface later, deep
--- inside whatever reads it (e.g. `core.slug`'s gsub on `anchor_separator`).
---@param cfg Mkdn.Config
---@param issues string[]
local function degrade_invalid_scalars(cfg, issues)
  local function bad(label, got, default)
    issues[#issues + 1] = ("invalid %s %s -- using %s"):format(
      label,
      vim.inspect(got),
      vim.inspect(default)
    )
  end

  local PROGRESS_STYLES =
    { auto = true, notify = true, statusline = true, fidget = true, float = true, kit = true }
  if type(cfg.progress_style) ~= "string" or not PROGRESS_STYLES[cfg.progress_style] then
    bad("progress_style", cfg.progress_style, DEFAULTS.progress_style)
    cfg.progress_style = DEFAULTS.progress_style
  end

  local ALIGNS = { left = true, center = true, right = true }
  if cfg.table then
    if type(cfg.table.header_align) ~= "string" or not ALIGNS[cfg.table.header_align] then
      bad("table.header_align", cfg.table.header_align, DEFAULTS.table.header_align)
      cfg.table.header_align = DEFAULTS.table.header_align
    end
    if type(cfg.table.entry_align) ~= "string" or not ALIGNS[cfg.table.entry_align] then
      bad("table.entry_align", cfg.table.entry_align, DEFAULTS.table.entry_align)
      cfg.table.entry_align = DEFAULTS.table.entry_align
    end

    -- ERR-22: `table.wrap.{min,pad}` reach `table_wrap.plan`'s `w < mins[i]`/
    -- `pad * 2` arithmetic unvalidated (`mins[i] = ov.min or opts.min or 1`
    -- only guards against `nil`, not a wrong type or a nonsensical negative
    -- width/padding); `resolve_wrap_opts`'s `math.max(opts.min or 1, 3)` for
    -- the default "github" flavor hits the same value even earlier. `max`
    -- reaches `w > maxs[i]` the same way, but `nil` (unlimited) is valid.
    -- `resize_debounce_ms` reaches `vim.defer_fn(fn, ms)` -- a libuv call
    -- that errors outright on a non-number. Every one of these is reachable
    -- from a plain `:MDTable*` command, not just when `wrap.enabled`.
    local wrap = cfg.table.wrap
    if wrap then
      if type(wrap.min) ~= "number" or wrap.min < 0 then
        bad("table.wrap.min", wrap.min, DEFAULTS.table.wrap.min)
        wrap.min = DEFAULTS.table.wrap.min
      end
      if wrap.max ~= nil and (type(wrap.max) ~= "number" or wrap.max < 0) then
        bad("table.wrap.max", wrap.max, DEFAULTS.table.wrap.max)
        wrap.max = DEFAULTS.table.wrap.max
      end
      if type(wrap.pad) ~= "number" or wrap.pad < 0 then
        bad("table.wrap.pad", wrap.pad, DEFAULTS.table.wrap.pad)
        wrap.pad = DEFAULTS.table.wrap.pad
      end
      if type(wrap.resize_debounce_ms) ~= "number" or wrap.resize_debounce_ms < 0 then
        bad(
          "table.wrap.resize_debounce_ms",
          wrap.resize_debounce_ms,
          DEFAULTS.table.wrap.resize_debounce_ms
        )
        wrap.resize_debounce_ms = DEFAULTS.table.wrap.resize_debounce_ms
      end
    end
  end

  -- ERR-22: `hover.max_lines` reaches `hover/section.lua`'s `#out >= limit`
  -- unvalidated -- a wrong type crashes that comparison the first time an
  -- anchor/file hover runs (the default-on path via `hover.enabled`).
  if cfg.hover then
    if type(cfg.hover.max_lines) ~= "number" or cfg.hover.max_lines < 1 then
      bad("hover.max_lines", cfg.hover.max_lines, DEFAULTS.hover.max_lines)
      cfg.hover.max_lines = DEFAULTS.hover.max_lines
    end
  end

  if cfg.toc then
    if type(cfg.toc.min_level) ~= "number" then
      bad("toc.min_level", cfg.toc.min_level, DEFAULTS.toc.min_level)
      cfg.toc.min_level = DEFAULTS.toc.min_level
    end
    if type(cfg.toc.max_level) ~= "number" then
      bad("toc.max_level", cfg.toc.max_level, DEFAULTS.toc.max_level)
      cfg.toc.max_level = DEFAULTS.toc.max_level
    end
    if type(cfg.toc.anchor_separator) ~= "string" then
      bad("toc.anchor_separator", cfg.toc.anchor_separator, DEFAULTS.toc.anchor_separator)
      cfg.toc.anchor_separator = DEFAULTS.toc.anchor_separator
    end
  end

  local CAPITALIZE = { ["false"] = true, first = true, title = true }
  if cfg.heading_format then
    local cap = cfg.heading_format.capitalize
    if not (cap == false or CAPITALIZE[tostring(cap)]) then
      bad("heading_format.capitalize", cap, DEFAULTS.heading_format.capitalize)
      cfg.heading_format.capitalize = DEFAULTS.heading_format.capitalize
    end
  end
end

--- Resolve `cfg.features` into `_resolved[name] = bool`. Precedence:
---   just_enable  → hard allowlist (only the listed features on; wins over all)
---   otherwise    → start all-on, apply `disable`, then re-apply `enable`
---@internal
---@param cfg Mkdn.Config
local function resolve_features(cfg)
  _resolved = {}
  for _, f in ipairs(FEATURES) do
    _resolved[f] = true
  end

  local F = cfg.features or {}

  local function warn_unknown(list, key)
    if type(list) ~= "table" then return end
    for _, name in ipairs(list) do
      if not FEATURE_SET[name] then
        notify.warn(string.format("features.%s: unknown feature '%s'", key, tostring(name)))
      end
    end
  end

  if type(F.just_enable) == "table" then
    warn_unknown(F.just_enable, "just_enable")
    for _, f in ipairs(FEATURES) do
      _resolved[f] = false
    end
    for _, name in ipairs(F.just_enable) do
      if FEATURE_SET[name] then _resolved[name] = true end
    end
    return
  end

  if F.disable == "all" then
    for _, f in ipairs(FEATURES) do
      _resolved[f] = false
    end
  elseif type(F.disable) == "table" then
    local disable_list = F.disable --[[@as string[] ]]
    warn_unknown(disable_list, "disable")
    for _, name in ipairs(disable_list) do
      if FEATURE_SET[name] then _resolved[name] = false end
    end
  elseif F.disable ~= nil then
    notify.warn('features.disable: expected "all" or a list of feature names')
  end

  if type(F.enable) == "table" then
    warn_unknown(F.enable, "enable")
    for _, name in ipairs(F.enable) do
      if FEATURE_SET[name] then _resolved[name] = true end
    end
  end
end

--- Validates `opts` (ERR-50: unknown keys dropped with a "did you mean" hint,
--- before the merge, so a typo cannot vanish into `tbl_deep_extend`'s result
--- next to the default it was meant to override), deep-merges the rest over
--- DEFAULTS, degrades a few known-invalid scalars back to their default
--- (ERR-22), and re-resolves feature gating. Anything rejected or degraded is
--- collected in `M.issues()` and reported once here and again by
--- `:checkhealth markdown`.
---@param opts Mkdn.Config|nil
---@return nil
function M.setup(opts)
  local issues = {}
  local sanitized = sanitize_level(opts or {}, TOP_LEVEL_OPTS, "", issues)

  _cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), sanitized)
  degrade_invalid_scalars(_cfg, issues)
  resolve_features(_cfg)

  _issues = issues
  if #issues > 0 then
    notify.warn("ignored/degraded config option(s):\n  " .. table.concat(issues, "\n  "))
  end
end

---@return Mkdn.Config
function M.get() return _cfg end

--- What the last `setup()` ignored or degraded: unknown keys and out-of-range
--- scalar values, one human-readable line each. Empty when every option
--- given to `setup()` matched a known key and a valid value. For
--- `:checkhealth markdown`.
---@return string[]
function M.issues() return vim.list_extend({}, _issues) end

--- Whether feature `name` is enabled by the resolved `features` gating.
--- Unknown (non-gateable) names are always enabled.
---@param name string
---@return boolean
function M.feature_enabled(name)
  if _resolved[name] == nil then return true end
  return _resolved[name]
end

--- The canonical list of gateable feature names (for docs/tooling).
---@return string[]
function M.features() return FEATURES end

return M
