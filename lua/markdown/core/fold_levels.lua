---@module 'markdown.core.fold_levels'
local M = {}

local api, fn, cmd = vim.api, vim.fn, vim.cmd

local function compute_foldlevel(levels_to_fold)
  if type(levels_to_fold) ~= "table" or #levels_to_fold == 0 then return 0 end
  local min_fold = 7
  for i = 1, #levels_to_fold do
    local lv = tonumber(levels_to_fold[i]) or 7
    if lv >= 1 and lv <= 6 and lv < min_fold then
      min_fold = lv
    end
  end
  if min_fold == 7 then return 0 end
  return math.max(0, min_fold - 1)
end

--- Set the window 'foldlevel' to `n` and reapply folds, preserving the view.
---@param n integer
local function apply_foldlevel(n)
  vim.opt_local.foldmethod = "expr"
  vim.opt_local.foldenable = true
  vim.opt_local.foldlevel = n
  vim.opt_local.foldlevelstart = n
  local view = fn.winsaveview()
  cmd("silent! normal! zx")
  fn.winrestview(view)
end

function M.fold_levels(levels_to_fold)
  if vim.bo.filetype ~= "markdown" then return end
  local buf = api.nvim_get_current_buf()
  if not (buf and api.nvim_buf_is_valid(buf)) then return end
  apply_foldlevel(compute_foldlevel(levels_to_fold))
end

--- Toggle an "outline" view: keep H1 and H2 visible and fold everything below
--- (H3+). Running it again unfolds all. `foldlevel = 2` closes folds whose level
--- is > 2 (i.e. H3, H4, …) while H1/H2 folds stay open.
function M.fold_h2_plus()
  if vim.bo.filetype ~= "markdown" then return end
  local buf = api.nvim_get_current_buf()
  if not (buf and api.nvim_buf_is_valid(buf)) then return end

  local cur = vim.wo.foldlevel or 99
  if cur <= 2 then
    apply_foldlevel(99) -- currently folded to the outline (or deeper) → unfold all
  else
    apply_foldlevel(2)  -- fold below H2 (keep H1/H2 open)
  end
end

return M
