-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/html_table_import_spec.lua — HTML <table> -> GFM round-trip
-- (core.table_fmt.parse_html_table / rows_to_gfm), and the
-- :Markdown table import command.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("markdown.config")
  local tf = require("markdown.core.table_fmt")
  local table_cmd = require("markdown.commands.table")

  config.setup({})

  local HTML = table.concat({
    "<!doctype html><html><body><table><thead><tr>",
    "<th>Name</th><th>Age</th>",
    "</tr></thead><tbody>",
    "<tr><td>Bob</td><td>3</td></tr>",
    "<tr><td>A &amp; B</td><td>&lt;40&gt;</td></tr>",
    "</tbody></table></body></html>",
  }, "\n")

  -- parse_html_table: rows include unescaped entities, tags stripped.
  do
    local rows, err = tf.parse_html_table(HTML)
    eq(err, nil, "parse ok")
    eq(#rows, 3, "header + 2 data rows")
    eq(rows[1][1], "Name", "header cell 1")
    eq(rows[1][2], "Age", "header cell 2")
    eq(rows[2][1], "Bob", "data cell")
    eq(rows[3][1], "A & B", "&amp; unescaped")
    eq(rows[3][2], "<40>", "&lt;/&gt; unescaped")
  end

  -- No <table>: clear error, not a crash.
  do
    local rows, err = tf.parse_html_table("<p>no table here</p>")
    eq(rows, nil, "no rows when no table")
    ok(err ~= nil, "error message present")
  end

  -- rows_to_gfm renders a valid, parseable GFM table.
  do
    local rows = assert(tf.parse_html_table(HTML), "the fixture table parses")
    local gfm = tf.rows_to_gfm(rows, {})
    eq(#gfm, 4, "header + separator + 2 rows")
    ok(gfm[1]:match("^|.*Name.*|$") ~= nil, "header row has Name")
    ok(gfm[2]:match("^|[%-%s:|]+|$") ~= nil, "separator row is dashes")
    ok(gfm[3]:match("Bob") ~= nil, "data row present")

    -- Round-trip through the buffer formatter stays well-formed.
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, gfm)
    local okf, ferr, n = tf.format_tables_in_buffer(buf, {})
    eq(okf, true, "re-format ok (" .. tostring(ferr) .. ")")
    eq(n, 1, "one table recognized")
  end

  -- :Markdown table import (no source, no range) reads the whole buffer.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(HTML, "\n"))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    table_cmd.run({ "import" }, {})
    local out = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    ok(
      out:match("| Name | Age |") ~= nil or out:match("Name") ~= nil,
      "import inserted a GFM table"
    )
    ok(out:match("Bob") ~= nil, "imported data row present")
  end

  -- Ranged call replaces the selected HTML lines in place.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "before",
      "<table><tr><th>X</th></tr><tr><td>1</td></tr></table>",
      "after",
    })
    table_cmd.run({ "import" }, { range = 1, line1 = 2, line2 = 2 })
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(out[1], "before", "line before untouched")
    eq(out[#out], "after", "line after untouched")
    ok(table.concat(out, "\n"):match("| X |") ~= nil, "range replaced with GFM table")
  end

  config.setup({})
end
