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
  for _, v in ipairs(c) do if v == "scope=cursor" then has_cursor = true end end
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
end
