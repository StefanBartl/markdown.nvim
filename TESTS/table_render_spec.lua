-- TESTS/table_render_spec.lua -- virtual grid rendering of tables (core.table_render):
-- compact columns, cells wrapped to the window width, the cursor row shown as text;
-- the buffer text is never changed.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local tr = require("markdown.core.table_render")

  local function text(chunks)
    local t = {}
    for _, c in ipairs(chunks) do
      t[#t + 1] = c[1]
    end
    return table.concat(t)
  end

  local function shown_lines(src, avail, opts)
    local model = tr.layout(src, vim.tbl_extend("force", { avail = avail }, opts or {}))
    local style = tr.style({}, model)
    local out = { text(tr.border(model, "top", style)) }
    for i = 1, #model.rows do
      for _, l in ipairs(tr.row_lines(model, i, style)) do
        out[#out + 1] = text(l)
      end
    end
    out[#out + 1] = text(tr.border(model, "bottom", style))
    return out, model
  end

  local LONG = string.rep("word ", 30)
  local SRC = {
    "| Name                  | Description |",
    "| --------------------- | ----------- |",
    "| a                     | " .. LONG .. " |",
    "| `code` and more       | short       |",
  }

  -- no avail: natural widths, no padding left over from the source
  local lines, model = shown_lines(SRC, nil)
  eq(model.wrapped, false, "nothing wraps without a width")
  eq(
    model.widths[1],
    vim.fn.strdisplaywidth("`code` and more"),
    "column 1 is as wide as its longest cell"
  )
  for _, l in ipairs(lines) do
    eq(vim.fn.strdisplaywidth(l), model.width, "every line has the table width")
  end

  -- fits: same as natural
  local _, roomy = shown_lines(SRC, 1000)
  eq(roomy.wrapped, false, "a wide window does not wrap")

  -- too narrow: wrapped to the width, every line exactly that wide
  for _, avail in ipairs({ 80, 60, 40 }) do
    local out, m = shown_lines(SRC, avail)
    eq(m.wrapped, true, "wraps at " .. avail)
    ok(m.width <= avail, "fits " .. avail)
    for _, l in ipairs(out) do
      eq(vim.fn.strdisplaywidth(l), m.width, "line width at " .. avail)
    end
    ok(#out > #SRC + 2, "continuation lines were added at " .. avail)
  end

  -- short columns keep their words whole
  local _, m80 = shown_lines(SRC, 60)
  ok(m80.widths[1] >= #"and more" - 2, "column 1 not squeezed mid-word")

  -- alignment from the separator row
  local aligned = {
    "| L | C | R |",
    "| :-- | :-: | --: |",
    "| a | b | c |",
    "| aaaaa | bbbbb | ccccc |",
  }
  local out = shown_lines(aligned, nil)
  ok(out[4]:find("│ a     │   b   │     c │", 1, true), "left / center / right")

  -- <br> forces a line break; \| is a literal pipe
  local br = { "| A | B |", "| - | - |", "| x<br>y | a \\| b |" }
  local out_br, m_br = shown_lines(br, nil)
  eq(m_br.rows[3].height, 2, "<br> makes two lines")
  ok(table.concat(out_br, "\n"):find("a | b", 1, true), "escaped pipe shown as pipe")

  -- ragged row: missing cells are empty, no error
  local ragged = { "| A | B | C |", "| - | - | - |", "| only |" }
  local _, m_r = shown_lines(ragged, nil)
  eq(m_r.n, 3, "column count from the widest row")

  -- impossible: more columns than the width allows -> nil, never an error
  eq(tr.layout(SRC, { avail = 6 }), nil, "no layout when it cannot fit")

  -- row separators: auto only when a row wraps
  local st_auto = tr.style({}, { wrapped = false })
  eq(st_auto.row_separator, false, "no separator when nothing wraps")
  eq(tr.style({}, { wrapped = true }).row_separator, true, "separator when a row wraps")
  eq(
    tr.style({ row_separator = false }, { wrapped = true }).row_separator,
    false,
    "explicit false wins"
  )

  -- plain text lines (picker preview): the same grid
  local plain = tr.to_lines({ "| A | B |", "| - | - |", "| 1 | 22 |" })
  eq(plain[1], "┌───┬────┐", "to_lines: top border")
  eq(plain[2], "│ A │ B  │", "to_lines: header")
  eq(plain[3], "├───┼────┤", "to_lines: separator")
  eq(plain[#plain], "└───┴────┘", "to_lines: bottom border")
  eq(#tr.to_lines({ "no table" }), 1, "to_lines: not a table -> the source back")

  -- a token no whitespace can break is split by its DISPLAY width: combining marks add none
  local tok = string.rep("e\u{301}", 20) -- 20 columns, 40 code points
  local m_tok = tr.layout({ "| a |", "| - |", "| " .. tok .. " |" }, { avail = 14 })
  eq(m_tok.widths[1], 10, "the column is squeezed to the budget")
  eq(m_tok.rows[3].height, 2, "20 columns of combining text split into two 10-column pieces")
  for _, piece in ipairs(m_tok.rows[3].cells[1]) do
    eq(vim.fn.strdisplaywidth(piece), 10, "each piece is 10 columns wide")
  end

  -- ───────────── buffer ─────────────
  local ns = vim.api.nvim_create_namespace("markdown_table_render")
  local buf = H.scratch("markdown")
  local doc = {
    "# T",
    "",
    "| A | B |",
    "| - | - |",
    "| 1 | " .. LONG .. " |",
    "",
    "```",
    "| x | y |",
    "| - | - |",
    "| 1 | 2 |",
    "```",
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, doc)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  tr.enable(buf)
  ok(tr.is_enabled(buf), "enabled")
  ok(vim.wo.conceallevel >= 2, "conceallevel raised")

  local function marks() return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end
  local function concealed_rows()
    local rows = {}
    for _, m in ipairs(marks()) do
      if m[4].conceal_lines then rows[m[2] + 1] = true end
    end
    return rows
  end

  local rows = concealed_rows()
  ok(rows[3] and rows[4] and rows[5], "all three table rows are concealed")
  ok(not rows[8] and not rows[9] and not rows[10], "a table inside a fenced block is left alone")
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[5], doc[5], "the text is not touched")

  -- cursor row shows its real text
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  rows = concealed_rows()
  ok(rows[3] and rows[4] and not rows[5], "the cursor row is not concealed")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  ok(concealed_rows()[5], "concealed again after the cursor left")

  -- truncate and render exclude each other
  local tt = require("markdown.core.table_truncate")
  tt.enable(buf)
  ok(not tr.is_enabled(buf), "enabling truncate switches render off")
  ok(tt.is_enabled(buf), "truncate is on")
  tr.enable(buf)
  ok(not tt.is_enabled(buf), "enabling render switches truncate off")

  -- narrower window -> more virtual lines
  local function vline_count()
    local n = 0
    for _, m in ipairs(marks()) do
      n = n + #(m[4].virt_lines or {})
    end
    return n
  end
  local wide = vline_count()
  vim.cmd("vsplit")
  vim.cmd("vertical resize 30")
  tr.render(buf)
  ok(vline_count() > wide, "a narrower window wraps into more virtual lines")
  vim.cmd("only")

  -- the events the render lives on are wired
  local function has(event, group, pattern)
    for _, a in ipairs(vim.api.nvim_get_autocmds({ event = event, group = group })) do
      if pattern == nil or vim.inspect(a.pattern or ""):find(pattern, 1, true) then return true end
    end
    return false
  end
  for _, ev in ipairs({ "WinResized", "VimResized", "OptionSet", "ColorScheme" }) do
    ok(has(ev, "MarkdownNvimTableRender"), ev .. " is wired (global group)")
  end
  local bufgroup = "MarkdownNvimTableRenderBuf" .. buf
  for _, ev in ipairs({
    "TextChanged",
    "TextChangedI",
    "InsertLeave",
    "CursorMoved",
    "CursorMovedI",
    "BufWinEnter",
    "WinEnter",
    "BufWinLeave",
    "BufReadPost",
    "BufWipeout",
  }) do
    ok(has(ev, bufgroup), ev .. " is wired (buffer group)")
  end
  ok(has("OptionSet", "MarkdownNvimTableRender", "signcolumn"), "signcolumn changes re-lay-out")

  tr.disable(buf)

  -- ───────────── a re-render only draws the tables that changed ─────────────
  local inc = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(inc, 0, -1, false, {
    "x",
    "",
    "| A | B |",
    "| - | - |",
    "| 1 | 2 |",
    "",
    "y",
    "",
    "| C | D |",
    "| - | - |",
    "| 3 | 4 |",
    "",
    "end",
  })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  tr.enable(inc)
  ---@return table<integer, boolean> ids, table<integer, integer[]> rows  # extmark ids / id lists per row
  local function snapshot()
    local ids, by_row = {}, {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(inc, ns, 0, -1, {})) do
      ids[m[1]] = true
      by_row[m[2]] = by_row[m[2]] or {}
      table.insert(by_row[m[2]], m[1])
    end
    return ids, by_row
  end
  local function same_ids(a, b_)
    for id in pairs(a) do
      if not b_[id] then return false end
    end
    return true
  end
  local function ids_in(by_row, from, to)
    local found = {}
    for r = from, to do
      for _, id in ipairs(by_row[r] or {}) do
        found[id] = true
      end
    end
    return found
  end
  local _, before_rows = snapshot()
  local first_before = ids_in(before_rows, 2, 5) -- table 1 (rows 2..4) and the line after it
  local second_before = ids_in(before_rows, 8, 11)

  -- an edit in table 2 leaves table 1 alone
  vim.api.nvim_buf_set_text(inc, 10, 4, 10, 5, { "44" })
  tr.render(inc)
  local _, rows_now = snapshot()
  ok(same_ids(first_before, ids_in(rows_now, 2, 5)), "the untouched table keeps its extmarks")
  ok(not same_ids(second_before, ids_in(rows_now, 8, 11)), "the edited table is drawn again")

  -- lines inserted above move the tables; their marks follow and are kept
  local _, rows_a = snapshot()
  local table1 = ids_in(rows_a, 2, 5)
  vim.api.nvim_buf_set_lines(inc, 0, 0, false, { "new top line" })
  tr.render(inc)
  local _, rows_b = snapshot()
  ok(same_ids(table1, ids_in(rows_b, 3, 6)), "a table that only moved is not drawn again")
  local concealed_after = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(inc, ns, 0, -1, { details = true })) do
    if m[4].conceal_lines then concealed_after[m[2] + 1] = true end
  end
  ok(
    concealed_after[4] and concealed_after[5] and concealed_after[6],
    "table 1 is on its new lines"
  )

  -- a line inserted between a table and the line its grid hangs on: the grid is drawn again
  local rows_c = select(2, snapshot())
  local grid_row
  for r, list in pairs(rows_c) do
    if r == 6 then grid_row = list end
  end
  vim.api.nvim_buf_set_lines(inc, 6, 6, false, { "inserted under the table" })
  tr.render(inc)
  local ids_d, rows_d = snapshot()
  local still = false
  for _, id in ipairs(grid_row or {}) do
    if ids_d[id] and rows_d[7] then
      for _, id2 in ipairs(rows_d[7]) do
        if id2 == id then still = true end
      end
    end
  end
  ok(not still, "a grid whose line is no longer next to the table is not kept")
  tr.disable(inc)

  -- one window, two buffers with the grid on: the level the window had is not lost
  do
    local function mk()
      local b = H.scratch("markdown")
      vim.api.nvim_buf_set_lines(b, 0, -1, false, { "| a |", "| - |", "| 1 |", "", "x" })
      return b
    end
    vim.cmd("only")
    local a = mk()
    vim.wo.conceallevel = 0
    tr.enable(a)
    local b2 = mk()
    tr.enable(b2)
    vim.api.nvim_set_current_buf(a)
    tr.disable(a)
    tr.disable(b2)
    eq(vim.wo.conceallevel, 0, "conceallevel is back after switching between two grid buffers")
  end

  vim.api.nvim_set_current_buf(buf)
  tr.enable(buf)
  tr.disable(buf)
  eq(#marks(), 0, "disable removes every extmark")
  ok(not tr.is_enabled(buf), "disabled")
  eq(tr.enable(0), nil, "enable(0) means the current buffer")
  ok(tr.is_enabled(buf), "enable(0) enabled the current buffer")
  tr.disable(0)
end
