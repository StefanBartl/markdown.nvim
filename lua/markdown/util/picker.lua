---@module 'markdown.util.picker'
--- Thin selection abstraction. Default backend is lib.nvim's float chooser
--- (lib.nvim.ui.kit.select); falls back to vim.ui.select when lib.nvim is
--- unavailable or another backend is requested. The backend name "hover_select"
--- is kept for config compatibility. "telescope" and "fzf" are soft
--- dependencies: each falls back to vim.ui.select with a warning when the
--- corresponding plugin isn't installed.
local notify = require("markdown.util.notify").create("[markdown.util.picker]")

local M = {}

-- `Mkdn.PickerOpts` is declared in `markdown.@types`.

--- Fallback used when a requested backend's plugin is unavailable.
---@generic T
---@param items T[]
---@param opts Mkdn.PickerOpts
---@param on_choose fun(item: T)
local function select_builtin(items, opts, format, on_choose)
  vim.ui.select(items, {
    prompt = opts.prompt or "Select",
    format_item = format,
  }, function(choice)
    if choice then on_choose(choice) end
  end)
end

local function select_hover(items, opts, format, on_choose)
  local ok, kit = pcall(require, "lib.nvim.ui.kit")
  if ok and kit and type(kit.select) == "function" then
    local labels = {}
    for i, it in ipairs(items) do
      labels[i] = format(it)
    end
    kit.select({
      items = labels,
      title = opts.prompt or "Select",
      relative = "editor",
      on_select = function(_label, idx)
        local chosen = items[idx]
        if chosen then on_choose(chosen) end
      end,
    })
    return true
  end
  return false
end

--- Telescope backend: a one-off picker built from `finders.new_table`, using
--- the default `theme`/sorter from telescope's own config.
local function select_telescope(items, opts, format, on_choose)
  local ok_p, pickers = pcall(require, "telescope.pickers")
  local ok_f, finders = pcall(require, "telescope.finders")
  local ok_c, tconf = pcall(require, "telescope.config")
  local ok_a, actions = pcall(require, "telescope.actions")
  local ok_s, astate = pcall(require, "telescope.actions.state")
  if not (ok_p and ok_f and ok_c and ok_a and ok_s) then return false end

  pickers
    .new({}, {
      prompt_title = opts.prompt or "Select",
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          local label = format(item)
          return { value = item, display = label, ordinal = label }
        end,
      }),
      sorter = tconf.values.generic_sorter({}),
      attach_mappings = function(bufnr, _map)
        actions.select_default:replace(function()
          local entry = astate.get_selected_entry()
          actions.close(bufnr)
          if entry and entry.value then on_choose(entry.value) end
        end)
        return true
      end,
    })
    :find()
  return true
end

--- fzf-lua backend: items are matched back to their label (last write wins on
--- duplicate labels — an acceptable edge case for a display string).
local function select_fzf(items, opts, format, on_choose)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then return false end

  local labels, by_label = {}, {}
  for i, it in ipairs(items) do
    local label = format(it)
    labels[i] = label
    by_label[label] = it
  end

  fzf.fzf_exec(labels, {
    prompt = (opts.prompt or "Select") .. "> ",
    actions = {
      ["default"] = function(selected)
        local label = selected and selected[1]
        local chosen = label and by_label[label]
        if chosen then on_choose(chosen) end
      end,
    },
  })
  return true
end

local BACKENDS = {
  telescope = select_telescope,
  fzf = select_fzf,
}

--- Present `items` and invoke `on_choose` with the picked item.
---@generic T
---@param items T[]
---@param opts Mkdn.PickerOpts
---@param on_choose fun(item: T)
function M.select(items, opts, on_choose)
  opts = opts or {}
  if not items or #items == 0 then return end

  local format = opts.format or tostring
  local backend = opts.backend or "hover_select"

  if backend == "hover_select" then
    if select_hover(items, opts, format, on_choose) then return end
    -- lib.nvim missing → fall through to vim.ui.select
  elseif BACKENDS[backend] then
    if BACKENDS[backend](items, opts, format, on_choose) then return end
    notify.warn(
      string.format("picker backend %q not available, falling back to vim.ui.select", backend)
    )
  elseif backend ~= "select" then
    notify.warn(string.format("unknown picker backend %q, falling back to vim.ui.select", backend))
  end

  select_builtin(items, opts, format, on_choose)
end

return M
