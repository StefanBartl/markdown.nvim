---@module 'markdown.core.wrap_link'
--- Wrap the word under the cursor (normal mode) or the visual selection in a
--- Markdown link. The heuristic decides which side of `[](…)` the text lands in:
---
---   * empty / whitespace -> insert `[]()`, cursor inside `[]`
---   * URL or file path    -> `[](target)`, cursor inside `[]`
---   * plain text          -> `[text]()`, cursor inside `()`
local M = {}

local api = vim.api

--- Heuristic: does `text` look like a URL or filesystem path (i.e. belongs in
--- the `(target)` part) rather than display text?
---@param text string
---@return boolean
local function is_url_or_path(text)
  if text:match("^%a[%w+.-]*://") then return true end -- http://, file://, ftp://, ...
  if text:match("^mailto:") then return true end
  if text:match("[/\\]") then return true end -- contains a path separator
  if text:match("^%S+%.%S+$") then return true end -- looks like name.ext
  return false
end

--- Build the wrapped link for a piece of inner text plus the cursor byte-offset
--- (relative to the start of the replacement).
---@param text string
---@return string wrapped
---@return integer cursor_offset  0-based offset from the replacement start
local function build(text)
  if is_url_or_path(text) then
    return "[](" .. text .. ")", 1 -- cursor between the [ ]
  end
  return "[" .. text .. "]()", #text + 3 -- cursor between the ( )
end

--- Normal mode: wrap the word under the cursor.
---@return nil
function M.wrap_normal()
  local bufnr = api.nvim_get_current_buf()
  local pos = api.nvim_win_get_cursor(0)
  local row, col = pos[1], pos[2] -- row 1-based, col 0-based
  local line = api.nvim_get_current_line()

  local function is_word(c) return c:match("[%w_./:\\-]") ~= nil end

  local s, e = col, col
  while s > 0 and is_word(line:sub(s, s)) do
    s = s - 1
  end
  s = s + 1
  while e < #line and is_word(line:sub(e + 1, e + 1)) do
    e = e + 1
  end

  local word = line:sub(s, e)

  -- Empty / no word under cursor: drop an empty template.
  if word == "" or word:match("^%s*$") then
    api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { "[]()" })
    api.nvim_win_set_cursor(0, { row, col + 1 })
    return
  end

  local wrapped, off = build(word)
  api.nvim_buf_set_text(bufnr, row - 1, s - 1, row - 1, e, { wrapped })
  api.nvim_win_set_cursor(0, { row, (s - 1) + off })
end

--- Visual mode: wrap the current selection. Reads the live selection bounds via
--- `getpos('v')` + cursor, then leaves visual mode.
---@return nil
function M.wrap_visual()
  local bufnr = api.nvim_get_current_buf()
  local mode = vim.fn.mode()
  if not mode:match("[vV\22]") then return end

  local cur = api.nvim_win_get_cursor(0) -- { row(1-based), col(0-based) }
  local vp = vim.fn.getpos("v") -- { bufnum, lnum, col(1-based), off }

  local srow, scol, erow, ecol
  if vp[2] < cur[1] or (vp[2] == cur[1] and (vp[3] - 1) <= cur[2]) then
    srow, scol = vp[2] - 1, vp[3] - 1
    erow, ecol = cur[1] - 1, cur[2]
  else
    srow, scol = cur[1] - 1, cur[2]
    erow, ecol = vp[2] - 1, vp[3] - 1
  end
  local ecol_excl = ecol + 1

  -- Leave visual mode before mutating the buffer.
  api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

  local ok, lines = pcall(api.nvim_buf_get_text, bufnr, srow, scol, erow, ecol_excl, {})
  if not ok or type(lines) ~= "table" then return end

  local text = table.concat(lines, "\n")
  local trimmed = text:match("^%s*(.-)%s*$") or ""

  if trimmed == "" then
    api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol_excl, { "[]()" })
    api.nvim_win_set_cursor(0, { srow + 1, scol + 1 })
    return
  end

  local wrapped, off = build(trimmed)
  local repl = vim.split(wrapped, "\n", { plain = true })
  api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol_excl, repl)
  if #repl == 1 then api.nvim_win_set_cursor(0, { srow + 1, scol + off }) end
end

return M
