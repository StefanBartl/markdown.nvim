---@module 'markdown_nvim.core.fold_levels'
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

function M.fold_levels(levels_to_fold)
  if vim.bo.filetype ~= "markdown" then return end
  local buf = api.nvim_get_current_buf()
  if not (buf and api.nvim_buf_is_valid(buf)) then return end

  vim.opt_local.foldmethod = "expr"
  vim.opt_local.foldenable = true

  local lvl = compute_foldlevel(levels_to_fold)
  vim.opt_local.foldlevel = lvl
  vim.opt_local.foldlevelstart = lvl

  local view = fn.winsaveview()
  cmd("silent! normal! zx")
  fn.winrestview(view)
end

function M.fold_h2_plus()
  M.fold_levels({ 2, 3, 4, 5, 6 })
end

return M
