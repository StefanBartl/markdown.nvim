-- TESTS/table_format_wrap_spec.lua -- `:Markdown table format` / <leader>mtf honour a maximum
-- column width (core.table_wrap): long cells wrap onto shared continuation rows.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local tf = require("markdown.core.table_fmt")
  local tcmd = require("markdown.commands.table")
  local mdtable = require("markdown.commands.mdtable")

  local function open(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    return buf
  end

  local function get(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end

  local SRC = {
    "| Syntax | Meaning | Example |",
    "|---|---|---|",
    "| `a` | stdout of the left command becomes stdin of the right one | `ls` |",
    "| `b` | short | `npx vitest run --reporter verbose --bail` |",
  }

  -- parse_args: max= / wrap / nowrap / auto
  local o = tf.parse_args({ "max=25", "wrap" })
  eq(o.max, 25, "max=25 parsed")
  eq(o.wrap, true, "wrap flag parsed")
  eq(tf.parse_args({ "nowrap" }).wrap, false, "nowrap flag parsed")
  eq(tf.parse_args({ "auto" }).auto, true, "auto flag parsed")
  local _, err = tf.parse_args({ "max=abc" })
  ok(err ~= nil, "max=abc is rejected")
  _, err = tf.parse_args({ "max=0" })
  ok(err ~= nil, "max=0 is rejected")

  -- wants_wrap: explicit flag > max/auto > config
  eq(mdtable.wants_wrap({ wrap = false, max = 20 }), false, "nowrap beats max")
  eq(mdtable.wants_wrap({ max = 20 }), true, "max implies wrapping")
  eq(mdtable.wants_wrap({}), false, "off by default")

  -- natural format (no flag) keeps one physical row per record
  local buf = open(SRC)
  tcmd.run({ "format" })
  eq(#get(buf), 4, "plain format does not wrap")

  -- max=20: continuation rows appear, every row keeps three columns
  buf = open(SRC)
  tcmd.run({ "format", "max=20" })
  local out = get(buf)
  ok(#out > 4, "max=20 wraps long cells onto extra rows")
  for i, l in ipairs(out) do
    eq(#tf.parse_row(l), 3, "row " .. i .. " keeps 3 columns")
  end

  -- row `a` overflows in two columns (Meaning, Example is short): physical rows of
  -- `a` = lines before the `b` row, minus header and separator. The longest cell
  -- decides the count; the other column reuses those rows instead of adding its own.
  local b_at
  for i, l in ipairs(out) do
    if tf.parse_row(l)[1] == "`b`" then b_at = i end
  end
  local wrapped = require("markdown.core.table_wrap").wrap_cell(
    "stdout of the left command becomes stdin of the right one",
    20,
    {}
  )
  eq(b_at - 3, #wrapped, "row a occupies exactly as many rows as its longest cell needs")

  -- idempotent at the same width
  local first = get(buf)
  tcmd.run({ "format", "max=20" })
  eq(
    table.concat(get(buf), "\n"),
    table.concat(first, "\n"),
    "formatting twice at the same max is stable"
  )

  -- nowrap overrides table.wrap.enabled
  require("markdown.config").setup({ table = { wrap = { enabled = true, max = 20 } } })
  buf = open(SRC)
  tcmd.run({ "format" })
  ok(#get(buf) > 4, "table.wrap.enabled = true makes plain format wrap at wrap.max")
  buf = open(SRC)
  tcmd.run({ "format", "nowrap" })
  eq(#get(buf), 4, "nowrap wins over table.wrap.enabled")
  require("markdown.config").setup({})

  -- wrap with neither max nor auto uses the default cap
  buf = open({
    "| A | B |",
    "|---|---|",
    "| " .. string.rep("word ", 30) .. "| x |",
  })
  tcmd.run({ "format", "wrap" })
  for _, l in ipairs(get(buf)) do
    ok(
      vim.fn.strdisplaywidth(l) <= mdtable.DEFAULT_FORMAT_MAX + 12,
      "line within the default cap: " .. l
    )
  end
  -- pure lines (file scopes): wrapped like the buffer path
  local plines, pcount = mdtable.format_lines(SRC, { max = 20 })
  eq(pcount, 1, "format_lines wraps one table")
  eq(table.concat(plines, "\n"), table.concat(out, "\n"), "pure path equals the buffer path")

  -- file scope keeps BOM, CRLF and a missing final newline
  local path = vim.fn.tempname() .. ".md"
  local disk = require("markdown.util.disk_lines")
  disk.write(path, vim.deepcopy(SRC), { bom = true, crlf = true, final_newline = false })
  tcmd.run({ "format", "max=20", "scope=" .. path })
  local rl, meta = disk.read(path)
  eq(meta.bom, true, "the BOM is kept")
  eq(meta.crlf, true, "the CRLF endings are kept")
  eq(meta.final_newline, false, "a missing final newline stays missing")
  eq(table.concat(rl, "\n"), table.concat(out, "\n"), "the file holds the wrapped table")
  local before = vim.uv.fs_stat(path).mtime.nsec
  tcmd.run({ "format", "max=20", "scope=" .. path })
  eq(vim.uv.fs_stat(path).mtime.nsec, before, "an unchanged file is not rewritten")
  vim.fn.delete(path)

  -- reflow: merge continuation rows first, so a changed max re-flows
  buf = open(SRC)
  tcmd.run({ "format", "max=30" })
  tcmd.run({ "format", "reflow", "max=20" })
  eq(
    table.concat(get(buf), "\n"),
    table.concat(out, "\n"),
    "reflow at max=20 equals wrapping the original at 20"
  )
  eq(tf.parse_args({ "reflow" }).reflow, true, "reflow flag parsed")

  -- review fixes ----------------------------------------------------------------------

  -- the header row is never wrapped: line 2 must stay the separator, and a second
  -- format must not move the header's tail into the body
  local HDR = {
    "| A very long header that is wider than the cap | B |",
    "|---|---|",
    "| x | y |",
  }
  buf = open(HDR)
  tcmd.run({ "format", "max=12" })
  local h1 = get(buf)
  ok(h1[2]:match("^|[%s%-]+|[%s%-]+|$") ~= nil, "line 2 is still the separator row")
  eq(#h1, 3, "the header did not add rows")
  tcmd.run({ "format", "max=12" })
  eq(table.concat(get(buf), "\n"), table.concat(h1, "\n"), "formatting again is stable")

  -- an unchanged table is not rewritten (a TextChanged-driven caller would loop)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  tcmd.run({ "format", "max=12" })
  eq(vim.api.nvim_buf_get_changedtick(buf), tick, "no write when nothing changes")
  tcmd.run({ "format" })
  tcmd.run({ "format" })
  local tick2 = vim.api.nvim_buf_get_changedtick(buf)
  tcmd.run({ "format" })
  eq(vim.api.nvim_buf_get_changedtick(buf), tick2, "natural format does not rewrite either")

  -- reflow: a single-column table, the header and the first data row are never merged
  buf = open({ "| Item |", "|---|", "| apple |", "| pear |" })
  tcmd.run({ "format", "reflow", "max=30" })
  eq(#get(buf), 4, "reflow leaves a single-column table alone")
  buf = open({ "| A | B |", "|---|---|", "| only first |  |", "| x | y |" })
  tcmd.run({ "format", "reflow", "max=30" })
  eq(#get(buf), 4, "the first data row is not merged into the header")

  -- explicit max= beats a directive comment; skip= keeps a configured max
  local dlines = { "<!-- mdwrap: max=60 -->", "| a | b |", "|---|---|", "| c | d |" }
  eq(mdtable.resolve_wrap_opts(nil, 2, { max = 20 }, dlines).max, 20, "override beats directive")
  eq(mdtable.resolve_wrap_opts(nil, 2, nil, dlines).max, 60, "the directive still beats config")
  require("markdown.config").setup({ table = { col_overrides = { { col = 1, max = 15 } } } })
  local merged =
    mdtable.resolve_wrap_opts(nil, nil, { col_overrides = { { col = 2, align = "left" } } })
  eq(#merged.col_overrides, 2, "skip= adds to the configured col_overrides")
  eq(merged.col_overrides[1].max, 15, "and the configured max survives")
  require("markdown.config").setup({})

  -- :MDTableUnwrap works with a configured max
  require("markdown.config").setup({ table = { wrap = { max = 20 } } })
  buf = open(SRC)
  mdtable.wrap_at_cursor(buf)
  ok(#get(buf) > 4, "wrapped with wrap.max = 20")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  mdtable.unwrap_at_cursor(buf)
  eq(#get(buf), 4, "unwrap merges the continuation rows although wrap.max is set")
  require("markdown.config").setup({})

  -- mixed endings in a file: a CRLF block keeps its CRs and an already formatted one is unchanged
  local cr = string.char(13)
  local plain = mdtable.format_lines({ "| A | B |", "|---|---|", "| xxxx | y |" }, { max = 40 })
  local mixed = { "intro" }
  for _, l in ipairs(plain) do
    mixed[#mixed + 1] = l .. cr
  end
  mixed[#mixed + 1] = "outro"
  local messy = vim.deepcopy(mixed)
  messy[2], messy[3], messy[4] = "|A|B|" .. cr, "|-|-|" .. cr, "|xxxx|y|" .. cr
  local mout = mdtable.format_lines(mixed, { max = 40 })
  eq(
    table.concat(mout, "\n"),
    table.concat(mixed, "\n"),
    "a formatted CRLF block in an LF file is unchanged"
  )
  eq(
    table.concat(mdtable.format_lines(messy, { max = 40 }), "\n"),
    table.concat(mixed, "\n"),
    "a misaligned CRLF block is rewritten with its CRs, the LF lines stay"
  )

  -- format_lines with two tables, the first one growing
  local two = {
    "| A | B |",
    "|---|---|",
    "| " .. string.rep("w ", 30) .. "| x |",
    "",
    "| C | D |",
    "|---|---|",
    "| e | f |",
  }
  local tout, tcount = mdtable.format_lines(two, { max = 12 })
  eq(tcount, 2, "both tables are formatted")
  ok(
    tout[#tout - 2]:find("C", 1, true) ~= nil,
    "the second table follows the grown first one intact"
  )

  -- completion: show belongs to truncate only
  local function has(list, item)
    for _, v in ipairs(list) do
      if v == item then return true end
    end
    return false
  end
  eq(has(tcmd.complete("", "Markdown table mode "), "show"), false, "mode does not offer show")
  eq(has(tcmd.complete("", "Markdown table truncate "), "show"), true, "truncate offers show")
end
