-- docs/TESTS/table_fmt_spec.lua — GFM table formatter: arg parsing + rendering.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local tf = require("markdown.core.table_fmt")

  -- parse_args: key=value form
  local o1, e1 = tf.parse_args({ "header=left", "cell=right" })
  eq(e1, nil, "parse_args no error")
  eq(o1.header_align, "left", "header=left")
  eq(o1.entry_align, "right", "cell=right")

  -- parse_args: positional alignment (single positional applies to both)
  local o2 = tf.parse_args({ "center" })
  eq(o2.header_align, "center", "positional header")
  eq(o2.entry_align, "center", "positional entry")

  -- parse_args: invalid value returns an error
  local _, e3 = tf.parse_args({ "header=bogus" })
  ok(e3 ~= nil, "invalid alignment errors")

  -- parse_args: skip builds column overrides
  local o4 = tf.parse_args({ "skip=1,Name" })
  ok(type(o4.col_overrides) == "table" and #o4.col_overrides == 2, "skip -> 2 overrides")

  -- complete: prefix filtering
  local c = tf.complete("scope=")
  local has_cursor = false
  for _, v in ipairs(c) do
    if v == "scope=cursor" then has_cursor = true end
  end
  ok(has_cursor, "complete offers scope=cursor")

  -- format_tables_in_buffer: aligns to equal-width rows and is idempotent.
  local buf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "| Name | Age |",
    "|---|---|",
    "| Bob | 3 |",
    "| Alice | 40 |",
  })
  local okf, err, n = tf.format_tables_in_buffer(buf, {})
  eq(okf, true, "format ok (" .. tostring(err) .. ")")
  eq(n, 1, "one table formatted")
  local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- every table row renders to the same display width
  local w = #out[1]
  for i = 2, #out do
    eq(#out[i], w, "row " .. i .. " equal width")
  end
  ok(out[1]:match("^|.*|$") ~= nil, "header keeps pipes")
  ok(out[2]:match("^|[%-%s:|]+|$") ~= nil, "separator is dashes only")

  -- idempotent: formatting again yields the same lines
  tf.format_tables_in_buffer(buf, {})
  local out2 = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i = 1, #out do
    eq(out2[i], out[i], "idempotent row " .. i)
  end
  -- escaped pipe: the Shells.md table must stay three columns and keep its `\|`
  do
    local bs = string.char(92)
    local lines = {
      "| Syntax | Meaning | Example |",
      "|---|---|---|",
      "| `a " .. bs .. "| b` | Pipe | `npx vitest run " .. bs .. "| more` |",
      "| `>` | redirect | |",
    }
    local fmt_out = require("lib.nvim.markdown.table").format_lines(lines)
    for i, l in ipairs(fmt_out) do
      eq(#tf.parse_row(l), 3, "escaped-pipe table keeps 3 columns in row " .. i)
    end
    ok(fmt_out[3]:find(bs .. "|", 1, true) ~= nil, "the escaped pipe survives formatting")

    local tv = require("markdown.tableview.parser").get_tables_from_lines(lines)
    eq(#tv, 1, "tableview parses the table")
    eq(#tv[1].rows[1].cells, 3, "tableview keeps 3 cells (escaped pipe)")
    eq(#tv[1].rows[2].cells, 3, "tableview keeps the empty trailing cell")
  end
  -- import writers escape a literal pipe in cell text
  do
    local bs = string.char(92)
    local g = tf.rows_to_gfm({ { "H1", "H2" }, { "a|b", "c" .. bs .. "|d" } })
    eq(#tf.parse_row(g[3]), 2, "an unescaped pipe in cell text is escaped on import")
    ok(g[3]:find("a" .. bs .. "|b", 1, true) ~= nil, "a|b becomes a|b")
    ok(not g[3]:find(bs .. bs .. "|", 1, true), "an already escaped pipe is not escaped twice")
  end
end
