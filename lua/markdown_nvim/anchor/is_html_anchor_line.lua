---@module 'markdown_nvim.anchor.is_html_anchor_line'
local api = vim.api

---@param line string
---@return boolean
return function(line)
  if not line then return false end

  if
    line:match("<%w+[^>]-id%s*=%s*[\"']#.-[\"']")
    or line:match("<a[^>]-href%s*=%s*[\"']#.-[\"']")
    or line:match("<img[^>]-src%s*=%s*[\"']#.-[\"']")
  then
    return true
  end

  local bufnr = api.nvim_get_current_buf()
  local curline = api.nvim_win_get_cursor(0)[1]
  local start_line = math.max(1, curline - 5)
  local end_line = math.min(api.nvim_buf_line_count(bufnr), curline + 5)
  local ok, lines = pcall(api.nvim_buf_get_lines, bufnr, start_line - 1, end_line, false)
  if ok and lines then
    local joined = table.concat(lines, "\n")
    if joined:match("<figure.-<img[^>]-src%s*=%s*['\"]#.-['\"]") then
      return true
    end
  end

  return false
end
