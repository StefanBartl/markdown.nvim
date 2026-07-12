---@module 'markdown_nvim.util.picker'
--- Thin selection abstraction. Default backend is lib.nvim's float chooser
--- (lib.nvim.ui.kit.select); falls back to vim.ui.select when lib.nvim is
--- unavailable or another backend is requested. The backend name "hover_select"
--- is kept for config compatibility. Telescope / fzf-lua can be added later.
local M = {}

-- `Mkdn.PickerOpts` is declared in `markdown_nvim.@types`.

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
    local ok, kit = pcall(require, "lib.nvim.ui.kit")
    if ok and kit and type(kit.select) == "function" then
      local labels = {}
      for i, it in ipairs(items) do labels[i] = format(it) end
      kit.select({
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
