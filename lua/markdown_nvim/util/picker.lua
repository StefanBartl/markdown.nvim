---@module 'markdown_nvim.util.picker'
--- Thin selection abstraction. Default backend is lib.nvim's hover_select;
--- falls back to vim.ui.select when lib.nvim is unavailable or another backend
--- is requested. Telescope / fzf-lua backends can be added here later.
local M = {}

---@class Mkdn.PickerOpts
---@field prompt?  string
---@field format?  fun(item: any): string
---@field backend? string

--- Present `items` and invoke `on_choose` with the picked item.
---@generic T
---@param items T[]
---@param opts Mkdn.PickerOpts
---@param on_choose fun(item: T)
function M.select(items, opts, on_choose)
  opts = opts or {}
  if not items or #items == 0 then return end

  local format  = opts.format or tostring
  local backend = opts.backend or "hover_select"

  if backend == "hover_select" then
    local ok, hs = pcall(require, "lib.nvim.ui.hover_select")
    if ok and hs and type(hs.open) == "function" then
      local labels = {}
      for i, it in ipairs(items) do labels[i] = format(it) end
      hs.open({
        items     = labels,
        title     = opts.prompt or "Select",
        relative  = "editor",
        on_select = function(_label, idx)
          local chosen = items[idx]
          if chosen then on_choose(chosen) end
        end,
      })
      return
    end
    -- lib.nvim missing → fall through to vim.ui.select
  end

  vim.ui.select(items, {
    prompt      = opts.prompt or "Select",
    format_item = format,
  }, function(choice)
    if choice then on_choose(choice) end
  end)
end

return M
