---@module 'markdown.commands.render'
--- `:Markdown render [on|off|toggle]` — control render-markdown.nvim.
--- render-markdown.nvim is the host of the in-buffer rendering until markdown.nvim renders
--- natively (task markdown.nvim/replace-render-markdown-nvim). It is listed as a dependency in
--- the install docs; when it is not present the command warns instead of erroring.
--- (Tables are drawn by `core.table_render`, not by render-markdown.nvim: disable its
--- `pipe_table` component, see docs/FEATURES/INTEGRATIONS.md.)
local notify = require("markdown.util.notify").create("[markdown.commands.render]")

local M = {}

---@internal
---@return boolean
local function available() return vim.fn.exists(":RenderMarkdown") == 2 end

---@internal
---@param action "enable"|"disable"|"toggle"
local function run(action)
  if not available() then
    notify.warn("render: render-markdown.nvim not available (add it as a dependency, see docs)")
    return
  end
  -- The plugin starts enabled, so there is no state of our own to track: ask it to toggle.
  vim.cmd("RenderMarkdown " .. action)
  notify.info("Markdown rendering: " .. action)
end

--- Runs `:Markdown render [on|off|toggle]`.
---@param argv string[]
---@return nil
function M.run(argv)
  local arg = (argv[1] or "toggle"):lower()
  if arg == "on" then
    run("enable")
  elseif arg == "off" then
    run("disable")
  elseif arg == "" or arg == "toggle" then
    run("toggle")
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
