---@module 'markdown.commands.preview'
--- `:Markdown preview [start|stop|toggle]` — control mdview.nvim.
--- Tracks an "active" flag so `toggle` and the status messages have a single
--- source of truth. Unlike the previous markdown-preview.nvim backend,
--- mdview.nvim follows buffer switches and drives scroll sync itself
--- (`browser.behavior`, default "reuse") once a session is running, so no
--- BufEnter re-render workaround is needed here. mdview.nvim is an optional
--- host dependency.
local notify = require("markdown.util.notify").create("[markdown.commands.preview]")

local M = {}

local active = false

---@internal
---@return boolean
local function available() return vim.fn.exists(":MDView") == 2 end

--- Start the preview (idempotent).
---@internal
local function start_preview()
  active = true
  vim.cmd("silent! MDView start")
end

--- Stop the preview (idempotent).
---@internal
local function stop_preview()
  active = false
  vim.cmd("silent! MDView stop")
end

--- Runs `:Markdown preview [start|stop|toggle]`.
---@param argv string[]
---@return nil
function M.run(argv)
  local arg = (argv[1] or "toggle"):lower()
  if not available() then
    notify.warn("preview: mdview.nvim not available")
    return
  end

  if arg == "start" or arg == "on" then
    start_preview()
    notify.info("Markdown preview started")
  elseif arg == "stop" or arg == "off" then
    stop_preview()
    notify.info("Markdown preview stopped")
  elseif arg == "" or arg == "toggle" then
    if active then
      stop_preview()
      notify.info("Markdown preview stopped")
    else
      start_preview()
      notify.info("Markdown preview started")
    end
  else
    notify.warn("preview: invalid argument (start|stop|toggle)")
  end
end

---@param arglead string
---@return string[]
function M.complete(arglead)
  local out = {}
  for _, c in ipairs({ "start", "stop", "toggle" }) do
    if vim.startswith(c, arglead) then out[#out + 1] = c end
  end
  return out
end

return M
