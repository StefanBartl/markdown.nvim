---@module 'markdown.commands.render'
--- `:Markdown render [on|off|toggle]` — control render-markdown.nvim.
--- render-markdown.nvim is an optional host dependency; when it is not present
--- the command warns instead of erroring.
local notify = require("markdown.util.notify").create("[markdown.commands.render]")

local M = {}

local is_enabled = false

local function available()
  return vim.fn.exists(":RenderMarkdown") == 2
end

local function set(state)
  if not available() then
    notify.warn("render: render-markdown.nvim not available")
    return
  end
  is_enabled = state
  vim.cmd(state and "RenderMarkdown enable" or "RenderMarkdown disable")
  notify.info("Markdown rendering " .. (state and "enabled" or "disabled"))
end

---@param argv string[]
function M.run(argv)
  local arg = (argv[1] or "toggle"):lower()
  if arg == "on" then
    set(true)
  elseif arg == "off" then
    set(false)
  elseif arg == "" or arg == "toggle" then
    set(not is_enabled)
  else
    notify.warn("render: invalid argument (on|off|toggle)")
  end
end

---@param arglead string
---@return string[]
function M.complete(arglead)
  local out = {}
  for _, c in ipairs({ "on", "off", "toggle" }) do
    if vim.startswith(c, arglead) then out[#out + 1] = c end
  end
  return out
end

return M
