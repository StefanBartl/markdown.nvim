---@module 'markdown_nvim.config'
---@brief Runtime config store: merge user options over DEFAULTS, expose get().
---@description
--- The public require path stays `markdown_nvim.config` (this init.lua). The
--- immutable defaults live in `markdown_nvim.config.DEFAULTS`; user options are
--- deep-merged on top on setup(). `get()` returns the resolved table.
---
--- Feature gating: `cfg.features` (`disable` | `enable` | `just_enable`) is
--- resolved once at setup() into a per-feature on/off map, queried everywhere via
--- `feature_enabled(name)`. This lets a user reduce the plugin to a subset, e.g.
--- `features = { just_enable = { "table", "toc" } }` runs ONLY those two.

local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.config]")

local M = {}

local DEFAULTS = require("markdown_nvim.config.DEFAULTS")

--- Canonical, gateable feature names. Anything not listed is always on.
---@type string[]
local FEATURES = {
  "keymaps", "fold", "hl", "link_hl", "fenced_fix", "fenced_scope",
  "tableview", "refs",
  -- :Markdown subcommand features
  "links", "toc", "table", "render", "preview", "create", "headline_spacing", "scope",
}

local FEATURE_SET = {}
for _, f in ipairs(FEATURES) do FEATURE_SET[f] = true end

local _cfg = vim.deepcopy(DEFAULTS)
---@type table<string, boolean>
local _resolved = {}

--- Resolve `cfg.features` into `_resolved[name] = bool`. Precedence:
---   just_enable  → hard allowlist (only the listed features on; wins over all)
---   otherwise    → start all-on, apply `disable`, then re-apply `enable`
local function resolve_features(cfg)
  _resolved = {}
  for _, f in ipairs(FEATURES) do _resolved[f] = true end

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
    for _, f in ipairs(FEATURES) do _resolved[f] = false end
    for _, name in ipairs(F.just_enable) do
      if FEATURE_SET[name] then _resolved[name] = true end
    end
    return
  end

  if F.disable == "all" then
    for _, f in ipairs(FEATURES) do _resolved[f] = false end
  elseif type(F.disable) == "table" then
    warn_unknown(F.disable, "disable")
    for _, name in ipairs(F.disable) do
      if FEATURE_SET[name] then _resolved[name] = false end
    end
  elseif F.disable ~= nil then
    notify.warn("features.disable: expected \"all\" or a list of feature names")
  end

  if type(F.enable) == "table" then
    warn_unknown(F.enable, "enable")
    for _, name in ipairs(F.enable) do
      if FEATURE_SET[name] then _resolved[name] = true end
    end
  end
end

---@param opts Mkdn.Config|nil
function M.setup(opts)
  _cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
  resolve_features(_cfg)
end

---@return Mkdn.Config
function M.get()
  return _cfg
end

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
function M.features()
  return FEATURES
end

return M
