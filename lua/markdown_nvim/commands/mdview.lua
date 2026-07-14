---@module 'markdown_nvim.commands.mdview'
--- `:Markdown mdview [path]` — open a file directly via mdview.nvim.
--- mdview.nvim is an optional host dependency; when it is not present the
--- command warns instead of erroring. `:MDViewStart` is idempotent: it starts
--- a new session, or — if one is already running — pushes `path`'s content
--- and re-opens the preview surface for it, so this works whether or not a
--- session is already up.
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.commands.mdview]")

local M = {}

local function available()
  return vim.fn.exists(":MDViewStart") == 2
end

---@param argv string[]
function M.run(argv)
  if not available() then
    notify.warn("mdview: mdview.nvim not available")
    return
  end

  local path = argv[1]
  if not path or path == "" then
    path = vim.api.nvim_buf_get_name(0)
  end
  if not path or path == "" then
    notify.warn("mdview: current buffer has no file path to open")
    return
  end

  vim.cmd("MDViewStart " .. vim.fn.fnameescape(vim.fn.expand(path)))
end

---@param arglead string
---@return string[]
function M.complete(arglead)
  return vim.fn.getcompletion(arglead, "file")
end

return M
