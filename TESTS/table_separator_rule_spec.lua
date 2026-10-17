-- TESTS/table_separator_rule_spec.lua -- one delimiter row per table block
--
-- `table_render.layout`, `table_truncate.compute` and `table_mode.insert_row`
-- all tell the delimiter row from the other rows by lib.nvim's
-- `markdown.table.separator_index` (the GFM rule `markdown.table.parse` uses):
-- only the first separator-looking line is the delimiter row, a later
-- `| - | - |` is a data row, and a header of dashes above the delimiter row is
-- the header. truncate and insert_row used to treat every separator-looking
-- line as the delimiter row.

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api

  -- ------------------------------------------------------------ layout
  do
    local tr = require("markdown.core.table_render")
    local m = tr.layout({ "| a | b |", "|---|---|", "| - | - |", "| x | y |" })
    eq(m.rows[2].kind, "sep", "layout: the second line is the delimiter row")
    eq(m.rows[3].kind, "body", "layout: a later `| - | - |` is a body row")
    local dh = tr.layout({ "| - | - |", "|---|---|", "| x | y |" })
    eq(dh.rows[1].kind, "head", "layout: a dash header is the header")
    eq(dh.rows[2].kind, "sep", "layout: and the line below it the delimiter row")
  end

  -- ------------------------------------------------------------ truncate
  do
    local tt = require("markdown.core.table_truncate")
    local dashes = string.rep("-", 30)

    --- Shown text of `line` after applying its conceal ranges.
    local function shown(line, marks)
      local out, pos = {}, 1
      local ms = vim.deepcopy(marks or {})
      table.sort(ms, function(a, b) return a.s < b.s end)
      for _, mk in ipairs(ms) do
        out[#out + 1] = line:sub(pos, mk.s - 1) .. mk.text
        pos = mk.e + 1
      end
      out[#out + 1] = line:sub(pos)
      return table.concat(out)
    end

    -- a data row of dashes is cut like data (with the marker), not like the delimiter row
    local src = { "| A | B |", "|---|---|", "| " .. dashes .. " | - |", "| short | y |" }
    local marks = tt.compute(src, { max = 10, marker = "…" })
    ok(marks[3] ~= nil, "truncate: the dash data row is truncated")
    ok(
      shown(src[3], marks[3]):find("…", 1, true) ~= nil,
      "truncate: a data row of dashes gets the marker like any data row"
    )

    -- a header of dashes is the header: cut with the marker, the delimiter row below loses dashes
    local head = { "| " .. dashes .. " | - |", "|---|---|", "| x | y |" }
    local hm = tt.compute(head, { max = 10, marker = "…" })
    ok(
      hm[1] ~= nil and shown(head[1], hm[1]):find("…", 1, true) ~= nil,
      "truncate: a dash header is cut like a header"
    )
  end

  -- ------------------------------------------------------------ insert_row
  do
    local table_mode = require("markdown.core.table_mode")

    -- a data row right above a `| - | - |` data row is not a header
    local b = H.scratch("markdown")
    api.nvim_buf_set_lines(
      b,
      0,
      -1,
      false,
      { "| a | b |", "| --- | --- |", "| 1 | 2 |", "| - | - |" }
    )
    ok(
      table_mode.insert_row(b, 2, "above"),
      "insert_row: 'above' a row followed by a dash row works"
    )
    local l = api.nvim_buf_get_lines(b, 0, -1, false)
    eq(#l, 5, "insert_row above: one row added")
    ok(
      l[3]:match("^|%s*|%s*|%s*$") ~= nil,
      "insert_row above: the blank row lands above the data row"
    )
    ok(l[4]:find("1", 1, true) ~= nil, "insert_row above: the data row follows it")
    vim.cmd("stopinsert")

    -- `O` on a dash data row inserts above it (it is not the delimiter row)
    local d = H.scratch("markdown")
    api.nvim_buf_set_lines(d, 0, -1, false, { "| a | b |", "| --- | --- |", "| - | - |" })
    ok(table_mode.insert_row(d, 2, "above"), "insert_row: 'above' a dash data row is handled")
    local dl = api.nvim_buf_get_lines(d, 0, -1, false)
    eq(#dl, 4, "insert_row above dash row: one row added")
    ok(dl[3]:match("^|%s*|%s*|%s*$") ~= nil, "insert_row above dash row: blank row above it")
    ok(dl[4]:match("^|%s*%-%s*|") ~= nil, "insert_row above dash row: the dash row follows")
    vim.cmd("stopinsert")

    -- `o` on a dash header skips the delimiter row below it
    local h = H.scratch("markdown")
    api.nvim_buf_set_lines(h, 0, -1, false, { "| - | - |", "|---|---|", "| x | y |" })
    ok(table_mode.insert_row(h, 0, "below"), "insert_row: 'below' a dash header is handled")
    local hl = api.nvim_buf_get_lines(h, 0, -1, false)
    eq(#hl, 4, "insert_row below dash header: one row added")
    ok(
      hl[3]:match("^|%s*|%s*|%s*$") ~= nil,
      "insert_row below dash header: after the delimiter row"
    )
    vim.cmd("stopinsert")
  end
end
