---@module 'markdown.util.progress'
---@brief Progress indicator for scope-wide operations over many *.md files.
---@description
--- Thin wrapper around `lib.nvim.progress`. `lib.nvim` is a hard dependency of
--- markdown.nvim, but this *submodule* of it is treated as optional (an older
--- lib.nvim predates it): `create` returns nil then, and every call site
--- guards with `if handle then … end` — the operation still runs, just without
--- the indicator.
---
--- Style comes from the top-level `progress_style` option
--- (`require("markdown").setup({ progress_style = "statusline" })`), so a
--- `:Markdown links sanitize cwd` over a big docs tree can feed
--- `lib.nvim.progress.styles.statusline` like the other plugins do.

local ok_progress, progress_mod = pcall(require, "lib.nvim.progress")

local M = {}

---Create a progress handle, or nil when `lib.nvim.progress` isn't available.
---@param text string        Initial message, shown after the "[markdown]" title.
---@param total integer|nil   Total unit count when the operation is countable.
---@return table|nil
function M.create(text, total)
  if not ok_progress then return nil end
  local cfg = require("markdown.config").get()
  local handle = progress_mod.create({
    title = "[markdown]",
    style = cfg.progress_style or "auto",
  })
  handle:update({ text = text, current = total and 0 or nil, total = total })
  return handle
end

return M
