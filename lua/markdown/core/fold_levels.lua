---@module 'markdown.core.fold_levels'
--- "Outline" fold-level toggling: fold everything below a given heading level.
local M = {}

local api, fn, cmd = vim.api, vim.fn, vim.cmd

---@internal
---@param levels_to_fold integer[]
---@return integer
local function compute_foldlevel(levels_to_fold)
  if type(levels_to_fold) ~= "table" or #levels_to_fold == 0 then return 0 end
  local min_fold = 7
  for i = 1, #levels_to_fold do
    local lv = tonumber(levels_to_fold[i]) or 7
    if lv >= 1 and lv <= 6 and lv < min_fold then min_fold = lv end
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

---Sets the fold level so only the given heading levels stay folded.
---@param levels_to_fold integer[]
---@return nil
function M.fold_levels(levels_to_fold)
  if vim.bo.filetype ~= "markdown" then return end
  local buf = api.nvim_get_current_buf()
  if not (buf and api.nvim_buf_is_valid(buf)) then return end
  apply_foldlevel(compute_foldlevel(levels_to_fold))
end

--- Toggle an "outline" view: keep H1..`level` visible and fold everything below.
--- Running it again unfolds all. `foldlevel = level` closes folds whose level
--- is > `level` while H1..`level` folds stay open. `level` defaults to 2 (H2+);
--- a count (e.g. `3zk`) sets it instead, mirroring `M.toc()`'s "count = max
--- heading level" convention (see `bindings/actions.lua`).
---@return nil
function M.fold_h2_plus()
  if vim.bo.filetype ~= "markdown" then return end
  local buf = api.nvim_get_current_buf()
  if not (buf and api.nvim_buf_is_valid(buf)) then return end

  local count = vim.v.count
  local level = count > 0 and math.max(1, math.min(6, count)) or 2

  local cur = vim.wo.foldlevel or 99
  if cur <= level then
    apply_foldlevel(99) -- currently folded to the outline (or deeper) → unfold all
  else
    apply_foldlevel(level) -- fold below `level` (keep H1..level open)
  end
end

return M
