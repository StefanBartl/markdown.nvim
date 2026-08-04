---@module 'markdown.commands.scope'
--- `:Markdown scope [on|off|toggle|status]` — control the fenced-block scope
--- feature at runtime (overrides the `fenced_scope.enable` config).
local M = {}

local notify = require("markdown.util.notify").create("[markdown.scope]")

---@internal
---@param enabled boolean
local function report(enabled)
  notify.info("fenced-block scope " .. (enabled and "enabled" or "disabled"))
end

--- `:Markdown scope [on|off|toggle|status]` entry point.
---@param argv string[]
---@param _ctx? table Unused; matches the dispatcher's (argv, ctx) calling convention.
---@return nil
function M.run(argv, _ctx)
  local scope = require("markdown.scope")
  local action = (argv and argv[1] or "toggle"):lower()

  if action == "on" or action == "enable" then
    scope.set_enabled(true)
    report(true)
  elseif action == "off" or action == "disable" then
    scope.set_enabled(false)
    report(false)
  elseif action == "status" then
    report(scope.enabled())
  elseif action == "toggle" then
    report(scope.toggle())
  else
    notify.warn("Usage: :Markdown scope [on|off|toggle|status]")
  end
end

--- Completion for the subcommand argument.
---@param arglead string
---@return string[]
function M.complete(arglead)
  local out = {}
  for _, a in ipairs({ "on", "off", "toggle", "status" }) do
    if vim.startswith(a, arglead) then out[#out + 1] = a end
  end
  return out
end

return M
