-- TESTS/blockquote_width_spec.lua -- blockquote_hl.width: how far the text
-- background reaches (block = widest line of the `>` block, line, window, n).
---@diagnostic disable: missing-fields, need-check-nil

return function(H)
  local eq, ok = H.eq, H.ok
  local bq = require("markdown.hl_options.hl_groups.blockquote")
  local NS = vim.api.nvim_create_namespace("MarkdownNvimBlockquote")

  ---@param buf integer
  ---@return table<integer, { pad: integer, eol: boolean }> row -> padding info
  local function marks_by_row(buf)
    local out = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, NS, 0, -1, { details = true })) do
      local row, d = m[2], m[4]
      out[row] = out[row] or { pad = 0, eol = false }
      if d.virt_text then out[row].pad = #d.virt_text[1][1] end
      if d.hl_eol then out[row].eol = true end
    end
    return out
  end

  ---@param width any
  ---@param lines string[]
  ---@return table
  local function run(width, lines)
    bq.apply({ blockquote_hl = { width = width, text_bg = "dimm" } })
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for row = 0, #lines - 1 do
      bq.highlight_line(buf, row)
    end
    return marks_by_row(buf), buf
  end

  local lines = {
    "text",
    "> short",
    "  > a much longer quote line",
    "> mid line",
    "",
    "> lone",
    "plain",
  }

  -- block (default): every line of a block is padded to the block's widest line.
  local m = run("block", lines)
  local widest = vim.fn.strdisplaywidth(lines[3])
  eq(m[0], nil, "plain line: no marks")
  eq(m[1].pad, widest - vim.fn.strdisplaywidth(lines[2]), "block: short line padded to the widest")
  eq(m[2].pad, 0, "block: the widest line needs no padding")
  eq(m[3].pad, widest - vim.fn.strdisplaywidth(lines[4]), "block: third line padded to the widest")
  eq(m[5].pad, 0, "block: a blank line ends the block, `> lone` is its own block")
  eq(m[6], nil, "plain line after a block: no marks")
  ok(not m[1].eol, "block: no hl_eol")

  -- unset/invalid falls back to the default (block)
  m = run(nil, lines)
  eq(m[1].pad, widest - vim.fn.strdisplaywidth(lines[2]), "unset width behaves like block")
  m = run("nonsense", lines)
  eq(m[1].pad, widest - vim.fn.strdisplaywidth(lines[2]), "invalid width behaves like block")

  -- line: no padding at all.
  m = run("line", lines)
  eq(m[1].pad, 0, "line: no padding")
  ok(not m[1].eol, "line: no hl_eol")

  -- window: the original hl_eol behaviour.
  m = run("window", lines)
  ok(m[1].eol, "window: hl_eol to the window edge")
  eq(m[1].pad, 0, "window: no padding")

  -- number: at least n columns, a longer line is never cut.
  m = run(40, lines)
  eq(m[1].pad, 40 - vim.fn.strdisplaywidth(lines[2]), "number: padded to n columns")
  m = run(5, lines)
  eq(m[2].pad, 0, "number: a line longer than n gets no padding")

  -- wide characters count by display width, not bytes.
  local wide = { "> äöü", "> ab" }
  m = run("block", wide)
  eq(m[0].pad, 0, "multibyte: widest line by display width")
  eq(m[1].pad, vim.fn.strdisplaywidth(wide[1]) - vim.fn.strdisplaywidth(wide[2]), "multibyte: pad")

  -- an edit invalidates the cached block width; a removed `>` loses its marks.
  local _, buf = run("block", { "> aa", "> bbbbbbbb" })
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "> b" })
  for row = 0, 1 do
    bq.highlight_line(buf, row)
  end
  m = marks_by_row(buf)
  eq(m[0].pad, 0, "edit: widest line shrank, the padding follows (cache invalidated)")
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "no quote" })
  bq.highlight_line(buf, 0)
  eq(marks_by_row(buf)[0], nil, "a line that stops being a quote loses its marks")

  -- reset for any following spec
  require("markdown.config").setup({})
  bq.apply(require("markdown.config").get())
end
