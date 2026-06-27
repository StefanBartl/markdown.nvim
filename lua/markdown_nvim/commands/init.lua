---@module 'markdown_nvim.commands'
local M = {}

local commands = {
  links             = require("markdown_nvim.commands.links").run,
  toc               = require("markdown_nvim.commands.toc").run,
  table             = require("markdown_nvim.commands.table").run,
  render            = require("markdown_nvim.commands.render").run,
  preview           = require("markdown_nvim.commands.preview").run,
  headline_spacing  = function()
    local bufnr = vim.api.nvim_get_current_buf()
    require("markdown_nvim.core.headline_spacing").apply_headl_separators(bufnr, { notify = true })
  end,
}

function M.execute(argv)
  local command = argv[1]
  if not command then
    vim.notify("Usage: :Markdown <subcommand>", vim.log.levels.INFO)
    return
  end

  local fn = commands[command]
  if not fn then
    vim.notify(string.format("Unknown Markdown command: %s", command), vim.log.levels.ERROR)
    return
  end

  table.remove(argv, 1)
  fn(argv)
end

-- Subcommands exposing their own `complete(arglead, cmdline)` for nested completion.
local sub_complete = {
  links   = function(arglead) return require("markdown_nvim.commands.links").complete(arglead) end,
  table   = function(arglead, cmdline) return require("markdown_nvim.commands.table").complete(arglead, cmdline) end,
  render  = function(arglead) return require("markdown_nvim.commands.render").complete(arglead) end,
  preview = function(arglead) return require("markdown_nvim.commands.preview").complete(arglead) end,
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
    if vim.startswith(name, arglead) then
      result[#result + 1] = name
    end
  end
  table.sort(result)
  return result
end

return M
