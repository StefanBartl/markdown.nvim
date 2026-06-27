---@module 'markdown_nvim.commands.preview'
--- `:Markdown preview [start|stop|toggle]` — control markdown-preview.nvim.
--- Tracks an "active" flag and refreshes the preview on BufEnter for *.md while
--- active. markdown-preview.nvim is an optional host dependency.
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.commands.preview]")

local M = {}

local active = false
local aug = nil

local function available()
  return vim.fn.exists(":MarkdownPreview") == 2
end

--- Install the BufEnter auto-refresh autocmd once.
local function ensure_autorefresh()
  if aug then return end
  aug = vim.api.nvim_create_augroup("MarkdownNvimPreviewRefresh", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group   = aug,
    pattern = "*.md",
    callback = function()
      if active and available() then
        vim.cmd("silent! MarkdownPreview")
      end
    end,
    desc = "[markdown.nvim] Refresh preview on buffer switch while active",
  })
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
    active = true
    vim.cmd("silent! MarkdownPreview")
    notify.info("Markdown preview started")
  elseif arg == "stop" or arg == "off" then
    active = false
    vim.cmd("silent! MarkdownPreviewStop")
    notify.info("Markdown preview stopped")
  elseif arg == "" or arg == "toggle" then
    active = not active
    vim.cmd("silent! MarkdownPreviewToggle")
    notify.info("Markdown preview " .. (active and "started" or "stopped"))
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
