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

  -- re-review fixes ------------------------------------------------------------------

  -- :MDTableUnwrap on a single-column table leaves it alone
  buf = open({ "| Item |", "| --- |", "| apple |", "| banana |", "| cherry |" })
  mdtable.unwrap_at_cursor(buf)
  eq(#get(buf), 5, "unwrap does not merge the rows of a single-column table")
  eq(
    #require("markdown.core.table_wrap").unwrap_rows(
      { { "Item" }, { "apple" }, { "banana" }, { "cherry" } },
      " "
    ),
    4,
    "unwrap_rows guards single-column tables itself"
  )

  -- :MDTableUnwrap with a per-column max in col_overrides really unwraps
  require("markdown.config").setup({
    table = { wrap = { enabled = true }, col_overrides = { { col = 1, max = 10 } } },
  })
  buf = open({
    "| Name | Note |",
    "|---|---|",
    "| the quick brown fox jumps over the lazy dog | x |",
    "| b | y |",
  })
  mdtable.wrap_at_cursor(buf)
  local wrapped_n = #get(buf)
  ok(wrapped_n > 4, "col_overrides max wraps the first column")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  mdtable.unwrap_at_cursor(buf)
  eq(#get(buf), 4, "unwrap merges although a per-column max is configured")
  require("markdown.config").setup({})

  -- table mode with wrapping keeps the cursor inside its cell and does not move it when
  -- nothing changed
  require("markdown.config").setup({ table = { wrap = { enabled = true, max = 20 } } })
  buf = open(SRC)
  tcmd.run({ "format" })
  vim.api.nvim_win_set_cursor(0, { 3, 12 })
  local before_cursor = vim.api.nvim_win_get_cursor(0)
  require("markdown.core.table_mode").reformat(buf)
  eq(
    vim.inspect(vim.api.nvim_win_get_cursor(0)),
    vim.inspect(before_cursor),
    "an unchanged table does not move the cursor"
  )
  require("markdown.config").setup({})

  -- cursor restore is by characters inside the cell: never inside a multibyte character,
  -- and the same character stays under the cursor when the padding changes (centered)
  require("markdown.config").setup({ table = { wrap = { enabled = true, max = 30 } } })
  local function char_at(line, col0)
    return line:sub(col0 + 1):match("^[%z\1-\127\194-\244][\128-\191]*")
  end
  buf = open({
    "| Name | Note |",
    "| --- | --- |",
    "| äö | größe äöü ßx |",
    "| cd | x |",
  })
  tcmd.run({ "format" })
  local ln3 = get(buf)[3]
  local ocol = ln3:find("öü", 1, true) - 1
  vim.api.nvim_win_set_cursor(0, { 3, ocol })
  local ochar = char_at(ln3, ocol)
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "| cd | a considerably longer note here |" })
  require("markdown.core.table_mode").reformat(buf)
  local cur = vim.api.nvim_win_get_cursor(0)
  local line = get(buf)[cur[1]]
  local b = line:byte(cur[2] + 1)
  ok(b < 128 or b >= 192, "the cursor is on a character boundary, not inside a multibyte character")
  eq(char_at(line, cur[2]), ochar, "and on the same character after the padding changed")
  require("markdown.config").setup({})

  -- default path (no wrapping, centered): same character after the re-padding, also with
  -- composing marks (NFD) and a variation-selector emoji
  for _, cell in ipairs({
    "größe äöü ßx",
    "e" .. string.char(204, 129) .. "e" .. string.char(204, 129) .. "x yz",
  }) do
    buf = open({ "| Name | Note |", "| --- | --- |", "| a | " .. cell .. " |", "| b | x |" })
    local l3 = get(buf)[3]
    local target = l3:find("x", 1, true) - 1
    vim.api.nvim_win_set_cursor(0, { 3, target })
    local before_char = char_at(l3, target)
    vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "| b | a considerably longer note here |" })
    require("markdown.core.table_mode").reformat(buf)
    local c2 = vim.api.nvim_win_get_cursor(0)
    local l = get(buf)[c2[1]]
    eq(
      char_at(l, c2[2]),
      before_char,
      "default path keeps the character under the cursor: " .. cell
    )
  end

  -- table mode on the default path: nothing written -> the cursor stays where it is (even on a
  -- pipe or in the padding); insert mode and another buffer are left alone
  buf = open({ "| Name | Note |", "| ---- | ---- |", "| abcd | xxxx |" })
  tcmd.run({ "format" })
  local aligned = get(buf)
  for _, col in ipairs({ 0, 6, 7, #aligned[3] - 1 }) do
    vim.api.nvim_win_set_cursor(0, { 3, col })
    require("markdown.core.table_mode").reformat(buf)
    eq(
      vim.api.nvim_win_get_cursor(0)[2],
      col,
      "an aligned table does not move the cursor (col " .. col .. ")"
    )
  end

  local real_get_mode = vim.api.nvim_get_mode
  vim.api.nvim_get_mode = function() return { mode = "i", blocking = false } end -- luacheck: ignore 122
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "| abcd | a much longer cell here |" })
  vim.api.nvim_win_set_cursor(0, { 3, 4 })
  local before_insert = table.concat(get(buf), "\n")
  require("markdown.core.table_mode").reformat(buf)
  vim.api.nvim_get_mode = real_get_mode -- luacheck: ignore 122
  eq(table.concat(get(buf), "\n"), before_insert, "no reformat while in insert mode")
  eq(vim.api.nvim_win_get_cursor(0)[2], 4, "and the insert cursor is not moved")

  local other = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(other, 0, -1, false, { "| a | b |", "|---|---|", "| c | dddddd |" })
  vim.api.nvim_win_set_cursor(0, { 3, 5 })
  local pos = vim.api.nvim_win_get_cursor(0)
  require("markdown.core.table_mode").reformat(other)
  eq(
    vim.inspect(vim.api.nvim_win_get_cursor(0)),
    vim.inspect(pos),
    "a hidden buffer does not move the current cursor"
  )
  eq(get(other)[1], "| a | b |", "and is not re-formatted from the wrong window")

  -- an empty cell keeps the cursor inside it; a cursor in the indent maps to column 1
  require("markdown.config").setup({ table = { wrap = { enabled = true, max = 30 } } })
  buf = open({ "| A | B |", "| --- | --- |", "|  | y |", "| c | d |" })
  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "| cccccccc | d |" })
  require("markdown.core.table_mode").reformat(buf)
  local ec = vim.api.nvim_win_get_cursor(0)
  local eline = get(buf)[ec[1]]
  local first_pipe = eline:find("|", 1, true)
  local second_pipe = eline:find("|", first_pipe + 1, true)
  ok(ec[2] + 1 > first_pipe and ec[2] + 1 < second_pipe, "the cursor stays in the empty first cell")
  require("markdown.config").setup({})

  buf = open({ "  | A | B | C |", "  | --- | --- | --- |", "  | x | y | z |" })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  eq(
    require("markdown.commands.mdtable").snapshot_cursor(buf).col_index,
    1,
    "indent maps to column 1"
  )

  -- a cursor on the separator row stays on the separator row
  require("markdown.config").setup({ table = { wrap = { enabled = true, max = 12 } } })
  buf = open({ "| Name | Note |", "|---|---|", "| a | b |" })
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  require("markdown.core.table_mode").reformat(buf)
  eq(vim.api.nvim_win_get_cursor(0)[1], 2, "the separator row keeps the cursor")
  require("markdown.config").setup({})

  -- single-column fold predicate and ragged first row
  eq(
    #require("markdown.core.table_wrap").unwrap_rows({ { "H" }, { "a" }, { "b" }, { "c" } }, " ", 1),
    4,
    "col_count 1 never merges"
  )
  eq(
    #require("markdown.core.table_wrap").unwrap_rows(
      { { "H" }, { "a", "b" }, { "", "cont" }, { "c", "d" } },
      " ",
      2
    ),
    3,
    "a ragged first row does not disable merging when col_count says 2"
  )

  -- the plan never makes a column narrower than its header
  local tw = require("markdown.core.table_wrap")
  local plan = tw.plan({
    col_count = 2,
    rows = { { "A header wider than the cap", "B" }, { "x", "y" } },
  }, { max = 8, min = 3 })
  ok(
    plan.widths[1] >= vim.fn.strdisplaywidth("A header wider than the cap"),
    "plan floors at the header"
  )

  -- :MDTableReflowHeader keeps the header on one line
  require("markdown.config").setup({ table = { wrap = { max = 12 } } })
  buf = open({ "| Description of the thing | Count of items |", "|---|---|", "| a | b |" })
  mdtable.reflow_header(buf)
  eq(#get(buf), 3, "reflow_header does not add a header line")
  require("markdown.config").setup({})

  -- skip= adds to the configured col_overrides in the natural path too
  require("markdown.config").setup({
    table = { col_overrides = { { col = 1, align = "right" } } },
  })
  buf = open({ "| a | b |", "|---|---|", "| xxxx | y |" })
  tcmd.run({ "format", "skip=2" })
  ok(
    get(buf)[3]:match("^|%s+xxxx |") ~= nil and get(buf)[1]:match("^|%s+a |") ~= nil,
    "col 1 stays right-aligned"
  )
  require("markdown.config").setup({})

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
