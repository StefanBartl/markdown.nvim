---@module 'markdown.commands'
local M = {}

local notify = require("markdown.util.notify").create("[markdown.commands]")

-- A subcommand name usually equals its gating feature; a few map to several
-- (enabled if ANY is on). Keeps "just enable tableview" == full table surface.
local SUBCOMMAND_FEATURES = {
  table = { "table", "tableview" },
}

--- Whether the `:Markdown <command>` subcommand is enabled by feature gating.
---@param command string
---@return boolean
local function command_feature_enabled(command)
  local feat = require("markdown.config").feature_enabled
  local names = SUBCOMMAND_FEATURES[command] or { command }
  for _, n in ipairs(names) do
    if feat(n) then return true end
  end
  return false
end

local commands = {
  links             = require("markdown.commands.links").run,
  toc               = require("markdown.commands.toc").run,
  refs              = require("markdown.commands.refs").run,
  table             = require("markdown.commands.table").run,
  render            = require("markdown.commands.render").run,
  preview           = require("markdown.commands.preview").run,
  mdview            = require("markdown.commands.mdview").run,
  create            = require("markdown.commands.create").run,
  scope             = require("markdown.commands.scope").run,
  headline_spacing  = function()
    local bufnr = vim.api.nvim_get_current_buf()
    require("markdown.core.headline_spacing").apply_headl_separators(bufnr, { notify = true })
  end,
}

---@param argv string[]
---@param ctx? table  Optional context (e.g. range info) forwarded to the subcommand
function M.execute(argv, ctx)
  local command = argv[1]
  if not command then
    notify.info("Usage: :Markdown <subcommand>")
    return
  end

  local fn = commands[command]
  if not fn then
    notify.error(string.format("Unknown Markdown command: %s", command))
    return
  end

  -- Feature gate: subcommand names double as feature names (links, toc, table,
  -- render, preview, create, headline_spacing, scope, refs). A disabled feature
  -- reports instead of running. `table` is available under either the "table"
  -- or "tableview" feature so enabling just tableview keeps the whole table
  -- surface (view/format/new/mode/tableize) working standalone.
  if not command_feature_enabled(command) then
    notify.warn(string.format("Markdown %s: feature disabled via features config", command))
    return
  end

  table.remove(argv, 1)
  fn(argv, ctx)
end

-- Subcommands exposing their own `complete(arglead, cmdline)` for nested completion.
local sub_complete = {
  links   = function(arglead) return require("markdown.commands.links").complete(arglead) end,
  refs    = function(arglead, cmdline) return require("markdown.commands.refs").complete(arglead, cmdline) end,
  table   = function(arglead, cmdline) return require("markdown.commands.table").complete(arglead, cmdline) end,
  render  = function(arglead) return require("markdown.commands.render").complete(arglead) end,
  preview = function(arglead) return require("markdown.commands.preview").complete(arglead) end,
  mdview  = function(arglead) return require("markdown.commands.mdview").complete(arglead) end,
  create  = function(arglead) return require("markdown.commands.create").complete(arglead) end,
  scope   = function(arglead) return require("markdown.commands.scope").complete(arglead) end,
}

function M.complete(arglead, cmdline, _cursorpos)
  -- Tokens already typed after ":Markdown".
  local tokens = vim.split(vim.trim(cmdline), "%s+")
  -- tokens[1] == "Markdown"; tokens[2] == first subcommand (if present).
  local first = tokens[2]

  -- If a first subcommand is complete and we are now on a later argument,
  -- delegate to that subcommand's own completion.
  local on_second = #tokens > 2 or (#tokens == 2 and arglead == "" and first ~= nil)
  if first and on_second and sub_complete[first] then
    return sub_complete[first](arglead, cmdline)
  end

  local result = {}
  for name in pairs(commands) do
    if vim.startswith(name, arglead) and command_feature_enabled(name) then
      result[#result + 1] = name
    end
  end
  table.sort(result)
  return result
end

return M
