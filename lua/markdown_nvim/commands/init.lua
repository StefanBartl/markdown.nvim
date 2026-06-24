---@module 'markdown_nvim.commands'
local M = {}

local commands = {
  links             = require("markdown_nvim.commands.markdown_links").run,
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

function M.complete(arglead, _cmdline, _cursorpos)
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
