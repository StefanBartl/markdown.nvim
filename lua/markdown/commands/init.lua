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
  links = require("markdown.commands.links").run,
  toc = require("markdown.commands.toc").run,
  refs = require("markdown.commands.refs").run,
  table = require("markdown.commands.table").run,
  render = require("markdown.commands.render").run,
  preview = require("markdown.commands.preview").run,
  mdview = require("markdown.commands.mdview").run,
  create = require("markdown.commands.create").run,
  scope = require("markdown.commands.scope").run,
  image = require("markdown.commands.image").run,
  export = require("markdown.commands.export").run,
  headline_spacing = function()
    local bufnr = vim.api.nvim_get_current_buf()
    require("markdown.core.headline_spacing").apply_headl_separators(bufnr, { notify = true })
  end,
}

--- Dispatches a `:Markdown <subcommand> ...` invocation.
---@param argv string[]
---@param ctx? table  Optional context (e.g. range info) forwarded to the subcommand
---@return nil
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

-- Subcommands exposing their own `complete(arglead, cmdline)` for nested
-- completion. `nested = true` marks the ones that read the cmdline and so have
-- something to say beyond their own sub-subcommand slot; the rest only know
-- that first slot, and delegating deeper would just echo their sub-subcommand
-- names into an argument position.
local sub_complete = {
  links = { mod = "markdown.commands.links", nested = true },
  refs = { mod = "markdown.commands.refs", nested = true },
  table = { mod = "markdown.commands.table", nested = true },
  render = { mod = "markdown.commands.render" },
  preview = { mod = "markdown.commands.preview" },
  mdview = { mod = "markdown.commands.mdview" },
  create = { mod = "markdown.commands.create" },
  scope = { mod = "markdown.commands.scope" },
  image = { mod = "markdown.commands.image" },
  export = { mod = "markdown.commands.export" },
}

--- Completion for `:Markdown`: subcommand names, then delegates to the
--- matched subcommand's own completion.
---@param arglead string
---@param cmdline string
---@param _cursorpos integer?
---@return string[]
function M.complete(arglead, cmdline, _cursorpos)
  -- Tokens already typed after ":Markdown".
  local tokens = vim.split(vim.trim(cmdline), "%s+")
  -- tokens[1] == "Markdown"; tokens[2] == first subcommand (if present).
  local first = tokens[2]
  -- The slot being completed: the token under the cursor, or one past the last
  -- committed token when nothing has been typed for it yet. Slot 2 is the
  -- subcommand itself, 3 its first argument.
  local slot = (arglead == "") and (#tokens + 1) or #tokens

  -- A first subcommand is complete and we are on one of its arguments.
  local entry = first and slot >= 3 and sub_complete[first]
  if entry then
    if slot > 3 and not entry.nested then return {} end
    return require(entry.mod).complete(arglead, cmdline)
  end

  -- A subcommand with no nested completion of its own (toc, headline_spacing)
  -- takes no further candidates — its own name is not one of them.
  if slot >= 3 then return {} end

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
