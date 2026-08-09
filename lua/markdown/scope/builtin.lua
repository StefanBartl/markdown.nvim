---@module 'markdown.scope.builtin'
---@brief Minimal fallback fenced-block scanner.
---@description
--- Used only when color_my_ascii isn't installed. Deliberately small: a single
--- line-by-line state machine that mirrors color_my_ascii's CommonMark-style
--- fence matching (closing fence length >= opening). It exposes the same
--- `list_blocks`/`block_at` shape as the color_my_ascii provider so
--- `markdown.scope` can treat the two backends interchangeably.
---
--- Blocks use 0-indexed rows with a half-open content range
--- `[content_start, content_end)`, matching ColorMyAscii.FenceBlock.

local M = {}

local api = vim.api

--- Scan a buffer for all closed fenced code blocks.
---@param bufnr integer
---@return { open_row: integer, close_row: integer, content_start: integer, content_end: integer, lang: string }[]
function M.list_blocks(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = {}
  local open = nil

  for i = 1, #lines do
    local line = lines[i]
    local fence, lang = line:match("^%s*(```+)%s*(.*)$")
    if not fence then
      fence, lang = line:match("^%s*(~~~+)%s*(.*)$")
    end

    if fence then
      if not open then
        open = { row = i - 1, len = #fence, lang = vim.trim(lang or "") }
      elseif #fence >= open.len then
        blocks[#blocks + 1] = {
          open_row = open.row,
          close_row = i - 1,
          content_start = open.row + 1,
          content_end = i - 1,
          lang = open.lang,
        }
        open = nil
      end
    end
  end

  return blocks
end

--- Return the innermost block whose *interior* contains `row`, optionally
--- filtered to a set of language tags. Mirrors color_my_ascii.api.fences.block_at
--- with `include_fence = false`.
---@param bufnr integer
---@param row integer 0-indexed
---@param opts? { lang?: table<string, boolean> } lowercase language set
---@return { open_row: integer, close_row: integer, content_start: integer, content_end: integer, lang: string }|nil
function M.block_at(bufnr, row, opts)
  local lang_set = opts and opts.lang
  local best = nil
  for _, b in ipairs(M.list_blocks(bufnr)) do
    local ok = true
    if lang_set and not lang_set[(b.lang or ""):lower()] then ok = false end
    if ok and row >= b.content_start and row <= (b.content_end - 1) then
      if not best or (b.close_row - b.open_row) < (best.close_row - best.open_row) then best = b end
    end
  end
  return best
end

return M
