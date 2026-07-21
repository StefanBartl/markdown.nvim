---@module 'markdown.commands.preview'
--- `:Markdown preview [start|stop|toggle]` — control markdown-preview.nvim.
--- Tracks an "active" flag and refreshes the preview on BufEnter for *.md while
--- active. markdown-preview.nvim is an optional host dependency.
local notify = require("markdown.util.notify").create("[markdown.commands.preview]")
local autocmd = require("lib.nvim.autocmd")

local M = {}

local active = false
local aug = nil

local function available()
  return vim.fn.exists(":MarkdownPreview") == 2
end

-- Re-entrancy guard: while we drive markdown-preview ourselves, suppress the
-- BufEnter auto-refresh so focus changes triggered by opening/closing the
-- browser tab cannot spawn a second preview.
local busy = false

--- Install the BufEnter auto-refresh autocmd once. Only refreshes an already
--- running preview; never starts one on its own beyond the active session.
local function ensure_autorefresh()
  if aug then return end
  -- Raw nvim_create_augroup on purpose, not autocmd.group(): that caches by
  -- name and would stop re-clearing on a second ensure_autorefresh() after a
  -- hot-reload (which resets the local `aug` and re-enters this branch),
  -- leaving the previous instance's autocmd registered alongside the new one.
  aug = vim.api.nvim_create_augroup("MarkdownNvimPreviewRefresh", { clear = true })
  autocmd.create("BufEnter", function()
    if active and not busy and available() then
      vim.cmd("silent! MarkdownPreview")
    end
  end, {
    group   = aug,
    pattern = "*.md",
    desc = "[markdown.nvim] Refresh preview on buffer switch while active",
  })
end

--- Start the preview (idempotent). Drives markdown-preview explicitly instead
--- of using its toggle, so our `active` flag stays the single source of truth.
local function start_preview()
  busy = true
  active = true
  vim.cmd("silent! MarkdownPreview")
  busy = false
end

--- Stop the preview (idempotent). `active` is cleared first so the BufEnter
--- auto-refresh cannot re-open the browser tab during teardown.
local function stop_preview()
  active = false
  busy = true
  vim.cmd("silent! MarkdownPreviewStop")
  busy = false
end

---@param argv string[]
function M.run(argv)
  local arg = (argv[1] or "toggle"):lower()
  if not available() then
    notify.warn("preview: markdown-preview.nvim not available")
    return
  end
  ensure_autorefresh()

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
