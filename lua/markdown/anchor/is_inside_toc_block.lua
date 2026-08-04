---@module 'markdown.anchor.is_inside_toc_block'
--- Checks whether the cursor is currently inside a generated TOC block.
local api = vim.api

---@return boolean
return function()
  local bufnr = api.nvim_get_current_buf()
  local cursor_line = api.nvim_win_get_cursor(0)[1]
  local total = api.nvim_buf_line_count(bufnr)

  local toc_start = nil
  for i = cursor_line, 1, -1 do
    local line = api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
    if line and line:match("^%s*##%s+[Tt]able%s+[Oo]f%s+[Cc]ontent") then
      toc_start = i
      break
    end
    if line and line:match("^%s*#%s+") then break end
  end

  if not toc_start then return false end

  for i = toc_start + 1, total do
    local line = api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
    if line and (line:match("^%s*%-%-%-%s*$") or line:match("^%s*#%s+")) then
      return cursor_line >= toc_start and cursor_line < i
    end
  end

  return cursor_line >= toc_start
end
