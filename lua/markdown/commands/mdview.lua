---@module 'markdown.commands.mdview'
--- `:Markdown mdview [path]` — open a file directly via mdview.nvim.
--- mdview.nvim is an optional host dependency; when it is not present the
--- command warns instead of erroring. `:MDView start` is idempotent: it
--- starts a new session, or — if one is already running — pushes `path`'s
--- content and re-opens the preview surface for it, so this works whether or
--- not a session is already up.
local notify = require("markdown.util.notify").create("[markdown.commands.mdview]")
local expand_path = require("lib.nvim.cross.fs.expand_path")
local preview = require("markdown.commands.preview")

local M = {}

---@internal
---@return boolean
local function available() return vim.fn.exists(":MDView") == 2 end

--- Runs `:Markdown mdview [path]`.
---@param argv string[]
---@return nil
function M.run(argv)
  if not available() then
    notify.warn("mdview: mdview.nvim not available")
    return
  end

  local path = argv[1]
  if not path or path == "" then path = vim.api.nvim_buf_get_name(0) end
  if not path or path == "" then
    notify.warn("mdview: current buffer has no file path to open")
    return
  end

  -- expand_path, not vim.fn.expand (SEC-34): `path` is a user-typed
  -- command argument, not a Vim cmdline special.
  vim.cmd("MDView start " .. vim.fn.fnameescape(expand_path(path)))

  -- This starts (or reuses) the same mdview.nvim session `:Markdown preview`
  -- drives, so keep its "active" flag in sync — otherwise a later
  -- `:Markdown preview toggle` doesn't know a session is already running and
  -- re-issues `MDView start` instead of stopping it.
  preview.set_active(true)
end

---@param arglead string
---@return string[]
function M.complete(arglead) return vim.fn.getcompletion(arglead, "file") end

return M
