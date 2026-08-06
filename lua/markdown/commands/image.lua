---@module 'markdown.commands.image'
--- `:Markdown image <sub>` router — thin delegators to images.nvim (soft
--- dependency, pcall-guarded), not a reimplementation. images.nvim is
--- FileType-scoped to the same buffers as markdown.nvim (see
--- docs/ROADMAP/CROSS-PLUGIN.md), so the natural coupling is discoverability
--- from markdown.nvim's own `:Markdown` namespace, not duplicated logic —
--- `:Image paste`/`:Image screenshot` already do the actual work.
local notify = require("markdown.util.notify").create("[markdown.commands.image]")

local M = {}

---@return table|nil images module, if installed
local function images()
  local ok, mod = pcall(require, "images")
  return ok and mod or nil
end

---@internal
local function do_paste()
  local mod = images()
  if not mod then
    notify.warn("images.nvim not installed — see https://github.com/StefanBartl/images.nvim")
    return
  end
  mod.paste()
end

---@internal
local function do_screenshot()
  local mod = images()
  if not mod then
    notify.warn("images.nvim not installed — see https://github.com/StefanBartl/images.nvim")
    return
  end
  mod.screenshot()
end

local subcommands = {
  paste = do_paste,
  screenshot = do_screenshot,
}

--- Runs `:Markdown image <sub>` (default sub: `paste`).
---@param argv string[]
---@return nil
function M.run(argv)
  argv = argv or {}
  local sub = argv[1] or "paste"
  local fn = subcommands[sub]
  if not fn then
    notify.warn("image: unknown subcommand '" .. sub .. "' (supported: paste, screenshot)")
    return
  end
  fn()
end

---@param arglead string
---@return string[]
function M.complete(arglead)
  local out = {}
  for name in pairs(subcommands) do
    if vim.startswith(name, arglead) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

return M
