---@module 'markdown_nvim.commands'
local M = {}

local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.commands]")

local commands = {
  links             = require("markdown_nvim.commands.links").run,
  toc               = require("markdown_nvim.commands.toc").run,
  refs              = require("markdown_nvim.commands.refs").run,
  table             = require("markdown_nvim.commands.table").run,
  render            = require("markdown_nvim.commands.render").run,
  preview           = require("markdown_nvim.commands.preview").run,
  create            = require("markdown_nvim.commands.create").run,
  scope             = require("markdown_nvim.commands.scope").run,
  headline_spacing  = function()
    local bufnr = vim.api.nvim_get_current_buf()
    require("markdown_nvim.core.headline_spacing").apply_headl_separators(bufnr, { notify = true })
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
  -- reports instead of running.
  if not require("markdown_nvim.config").feature_enabled(command) then
    notify.warn(string.format("Markdown %s: feature disabled via features config", command))
    return
  end

  table.remove(argv, 1)
  fn(argv, ctx)
end

-- Subcommands exposing their own `complete(arglead, cmdline)` for nested completion.
local sub_complete = {
  links   = function(arglead) return require("markdown_nvim.commands.links").complete(arglead) end,
  refs    = function(arglead, cmdline) return require("markdown_nvim.commands.refs").complete(arglead, cmdline) end,
  table   = function(arglead, cmdline) return require("markdown_nvim.commands.table").complete(arglead, cmdline) end,
  render  = function(arglead) return require("markdown_nvim.commands.render").complete(arglead) end,
  preview = function(arglead) return require("markdown_nvim.commands.preview").complete(arglead) end,
  create  = function(arglead) return require("markdown_nvim.commands.create").complete(arglead) end,
  scope   = function(arglead) return require("markdown_nvim.commands.scope").complete(arglead) end,
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

  local feat = require("markdown_nvim.config").feature_enabled
  local result = {}
  for name in pairs(commands) do
    if vim.startswith(name, arglead) and feat(name) then
      result[#result + 1] = name
    end
  end
  table.sort(result)
  return result
end

return M
