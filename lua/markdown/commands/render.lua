---@module 'markdown.commands.render'
--- `:Markdown render [on|off|toggle]` -- the native in-buffer rendering (`core.render`: headings,
--- bullets, checkboxes, code blocks, rules, quotes / callouts, inline markup) together with the
--- table grid (`core.table_render`) for the current buffer. Display only, the text is untouched.
local notify = require("markdown.util.notify").create("[markdown.commands.render]")

local M = {}

---@internal
---@param bufnr integer
---@param on boolean
local function apply(bufnr, on)
  local render = require("markdown.core.render")
  local tables = require("markdown.core.table_render")
  if on then
    -- the grid first: the renderer leaves the table rows to it
    if require("markdown.config").feature_enabled("table") then tables.enable(bufnr) end
    render.enable(bufnr)
  else
    render.disable(bufnr)
    tables.disable(bufnr)
  end
end

--- Runs `:Markdown render [on|off|toggle]`.
---@param argv string[]
---@return nil
function M.run(argv)
  local arg = (argv[1] or "toggle"):lower()
  local bufnr = vim.api.nvim_get_current_buf()
  local on
  if arg == "on" then
    on = true
  elseif arg == "off" then
    on = false
  elseif arg == "" or arg == "toggle" then
    on = not require("markdown.core.render").is_enabled(bufnr)
  else
    notify.warn("render: invalid argument (on|off|toggle)")
    return
  end
  apply(bufnr, on)
  notify.info("Markdown rendering: " .. (on and "on" or "off"))
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
