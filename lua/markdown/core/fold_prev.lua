---@module 'markdown.core.fold_prev'
local M = {}

local api, fn, cmd = vim.api, vim.fn, vim.cmd

local function goto_prev_heading_any()
  local found = fn.search("^#\\+\\s\\+\\S", "bWs")
  if found > 0 then return true end
  local cur = fn.line(".")
  for lnum = cur - 1, 2, -1 do
    local line = fn.getline(lnum)
    local nextl = fn.getline(lnum + 1)
    if line:match("%S") and nextl and nextl:match("^%s*%-%-+%s*$") then
      api.nvim_win_set_cursor(0, { lnum, 0 })
      return true
    end
  end
  return false
end

-- NOTE: unlike `headings.goto_prev_heading()`, this does NOT delegate to it —
-- it has its own single-hop `goto_prev_heading_any()` search (which also
-- covers Setext-style `===`/`---` headings that the ANY_HEADING regex there
-- doesn't match). So it isn't count-aware by delegation; loop it here the
-- same way `goto_prev_heading` loops `vim.v.count1`.
function M.fold_prev_heading_then_center()
  if vim.bo.filetype ~= "markdown" then return end
  local buf = api.nvim_get_current_buf()
  if not (buf and api.nvim_buf_is_valid(buf)) then return end

  local view = fn.winsaveview()
  local moved = false
  for _ = 1, vim.v.count1 do
    if not goto_prev_heading_any() then break end
    moved = true
  end
  if not moved then
    fn.winrestview(view)
    return
  end

  cmd("silent! normal! zx")
  cmd("silent! normal! zc")
  cmd("silent! normal! zz")
end

return M
