-- TESTS/table_formats_spec.lua -- the table format registry: gfm / org / box found in documents,
-- csv / tsv read as a whole, every format written back, `:Markdown table convert`, and the rule
-- that nothing changes for anybody who does not list the formats.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local reg = require("markdown.tables.registry")
  local conv = require("markdown.commands.table_convert")

  local GFM = { "| Name | Qty |", "| :-- | --: |", "| apple | 3 |", "| pear | 12 |" }
  local ORG = {
    "| Name  | Qty |",
    "|-------+-----|",
    "| apple |   3 |",
    "| pear  |  12 |",
  }
  local BOX = {
    "┌───────┬─────┐",
    "│ Name  │ Qty │",
    "├───────┼─────┤",
    "│ apple │ 3   │",
    "│ pear  │ 12  │",
    "└───────┴─────┘",
  }

  local function strings(tbl)
    local h, r = reg.strings(tbl)
    return table.concat(h, ",")
      .. "/"
      .. table.concat(vim.tbl_map(function(x) return table.concat(x, ",") end, r), ";")
  end

  -- ───────────── detection ─────────────
  eq(#reg.find(GFM), 1, "gfm is found by default")
  eq(reg.find(GFM)[1].format, "gfm", "and says so")
  eq(#reg.find(ORG), 0, "org is not looked for unless listed")
  eq(#reg.find(BOX), 0, "box is not looked for unless listed")
  local o = reg.find(ORG, { formats = { "org" } })
  eq(#o, 1, "org table found")
  eq(strings(o[1]), "Name,Qty/apple,3;pear,12", "org parsed")
  local b = reg.find(BOX, { formats = { "box" } })
  eq(#b, 1, "box table found")
  eq(strings(b[1]), "Name,Qty/apple,3;pear,12", "box parsed")
  eq(b[1].start_line, 1, "box range start")
  eq(b[1].end_line, 6, "box range end")

  -- a document with all three, and prose that must not match
  local doc = {
    "# T",
    "",
    "a | b in prose, and a - b + c | d",
    "",
    unpack(GFM),
  }
  vim.list_extend(doc, { "" })
  vim.list_extend(doc, ORG)
  vim.list_extend(doc, { "" })
  vim.list_extend(doc, BOX)
  local all = reg.find(doc, { formats = { "gfm", "org", "box" } })
  eq(#all, 3, "three tables of three formats")
  eq(all[1].format .. all[2].format .. all[3].format, "gfmorgbox", "in line order")
  eq(
    #reg.find({ "x | y", "plain | text", "- a", "+ b" }, { formats = { "gfm", "org", "box" } }),
    0,
    "prose is left alone"
  )

  -- a gfm table is not an org table (no `+` in its separator)
  eq(#reg.find(GFM, { formats = { "org" } }), 0, "org does not claim a gfm table")
  eq(
    #reg.find({ "| a |", "|---|", "| 1 |" }, { formats = { "org" } }),
    0,
    "nor a one-column gfm table"
  )
  -- both formats match the same lines: the one listed first wins, the table is found once
  local clash = { "| a | b |", "| - | - |", "|---+---|", "| 1 | 2 |" }
  local won = reg.find(clash, { formats = { "gfm", "org" } })
  eq(#won, 1, "overlapping matches give one table")
  eq(won[1].format, "gfm", "the format listed first wins")
  eq(reg.find(clash, { formats = { "org", "gfm" } })[1].format, "org", "and the order decides")

  -- fences
  local fenced = { "```", unpack(ORG) }
  fenced[#fenced + 1] = "```"
  eq(
    #reg.find(fenced, { formats = { "org" }, skip_fences = true }),
    0,
    "org inside a fence is skipped on request"
  )

  -- org: cookies give the alignment and are not data; TBLFM stays out
  local cook = reg.find({
    "| a | b |",
    "|---+---|",
    "| <r> | <l> |",
    "| 1 | 2 |",
    "#+TBLFM: $2=$1*2",
  }, { formats = { "org" } })[1]
  eq(cook.alignments[1], "right", "org cookie row: right")
  eq(#cook.rows, 1, "the cookie row is not a data row")
  eq(cook.end_line, 4, "the #+TBLFM line is not part of the table")

  -- box with a multi-line cell
  local multi = reg.find({
    "┌───┬───┐",
    "│ a │ b │",
    "├───┼───┤",
    "│ x │ 1 │",
    "│ y │   │",
    "├───┼───┤",
    "│ z │ 2 │",
    "└───┴───┘",
  }, { formats = { "box" } })[1]
  eq(multi.rows[1].cells[1].content, "x<br>y", "lines of one box row become <br>")
  local rewritten = reg.render("box", multi)
  local rules = 0
  for _, l in ipairs(rewritten) do
    if vim.startswith(l, "├") then rules = rules + 1 end
  end
  eq(rules, 2, "the rule between the body rows survives the write-back")
  local again = reg.find(rewritten, { formats = { "box" } })[1]
  eq(again.rows[2].cells[1].content, "z", "and the rewritten table reads the same")

  -- ───────────── csv / tsv ─────────────
  local csv = reg.parse("csv", { "name,note", '"Smith, J","said ""hi"""', 'x,"two', 'lines"' })
  eq(
    strings(csv),
    'name,note/Smith, J,said "hi";x,two\nlines',
    "RFC 4180: quoted separators, quotes and newlines"
  )
  local tsv = reg.parse("tsv", { "a\tb", "1\t2" })
  eq(require("markdown.tables.formats.csv").sep, ",", "tsv leaves no state behind in csv")
  eq(reg.render("csv", tsv)[1], "a,b", "csv after tsv still writes commas")
  eq(strings(tsv), "a,b/1,2", "tsv")
  eq(reg.parse("gfm", { "x" }), nil, "gfm is not a standalone format")

  -- ───────────── round trips ─────────────
  local g = reg.find(GFM)[1]
  for _, name in ipairs({ "org", "box", "gfm" }) do
    local lines = reg.render(name, g)
    local back = reg.find(lines, { formats = { name } })[1]
    ok(back, name .. ": rendered text is found again")
    eq(strings(back), strings(g), name .. ": parse -> render -> parse")
  end
  eq(
    reg.find(reg.render("org", g), { formats = { "org" } })[1].alignments[2],
    "right",
    "org keeps the alignment as cookies"
  )
  eq(reg.find(reg.render("gfm", o[1]))[1].format, "gfm", "org -> gfm is a gfm table")
  for _, name in ipairs({ "csv", "tsv" }) do
    local lines = reg.render(name, csv)
    eq(
      strings(reg.parse(name, lines)),
      strings(csv),
      name .. ": quoted fields survive a round trip"
    )
  end
  eq(reg.render("csv", g)[1], "Name,Qty", "csv header")
  eq(
    table.concat(reg.lossy("csv", g), ","),
    "column alignment",
    "csv warns about the alignment it drops"
  )
  eq(#reg.lossy("org", g), 0, "org keeps alignment")

  -- ───────────── the convert command ─────────────
  local function buf_with(lines)
    local bufnr = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
  end
  local ob = buf_with({ "intro", "", unpack(ORG) })
  local done, msg = conv.convert(ob, { from = "auto", to = "gfm" }, 4)
  ok(done, "org -> gfm converts: " .. tostring(msg))
  eq(
    reg.find(vim.api.nvim_buf_get_lines(ob, 0, -1, false))[1].format,
    "gfm",
    "the buffer holds a gfm table now"
  )
  eq(vim.api.nvim_buf_get_lines(ob, 0, 1, false)[1], "intro", "text around it is untouched")
  eq(
    select(1, conv.convert(ob, { from = "auto", to = "gfm" }, 3)),
    false,
    "gfm -> gfm says it is already"
  )
  eq(
    select(1, conv.convert(ob, { from = "auto", to = "gfm" }, 1)),
    false,
    "no table under the cursor"
  )

  local bb = buf_with(BOX)
  ok(conv.convert(bb, { from = "box", to = "org" }, 2), "box -> org")
  eq(vim.api.nvim_buf_get_lines(bb, 0, 1, false)[1], "| Name  | Qty |", "org header line")

  -- a range of csv text becomes a table
  local cb = buf_with({ "keep", "a,b", '"x,1",2', "keep too" })
  local csv_ok = conv.convert(cb, { from = "csv", to = "gfm" }, 1, { 2, 3 })
  ok(csv_ok, "csv range -> gfm")
  eq(vim.api.nvim_buf_get_lines(cb, 0, 1, false)[1], "keep", "line before the range")
  eq(vim.api.nvim_buf_get_lines(cb, -2, -1, false)[1], "keep too", "line after the range")
  ok(
    vim.api.nvim_buf_get_lines(cb, 1, 2, false)[1]:find("| a ", 1, true),
    "header from the first record"
  )

  -- lossy conversions are reported
  local fb = buf_with({ "| a | b |", "|---+---|", "| 1 | 2 |", "#+TBLFM: $2=$1" })
  local _, lmsg, lossy = conv.convert(fb, { from = "org", to = "gfm" }, 1)
  ok(lossy and lmsg:find("TBLFM", 1, true), "an org formula line is reported as not kept")

  -- the list shows an org table through its gfm form
  do
    local cfgm = require("markdown.config")
    local sn = vim.notify
    vim.notify = function() end
    cfgm.setup({ table = { formats = { "gfm", "org" } } })
    vim.notify = sn
    local lb = buf_with({ "x", "", unpack(ORG) })
    local items = require("markdown.commands.table_list").collect("%", "markdown")
    eq(#items, 1, "the list finds the org table")
    eq(items[1].previews.table.lines[1], "| Name  | Qty |", "and previews it as a formatted table")
    cfgm.setup({})
    vim.api.nvim_buf_delete(lb, { force = true })
  end

  -- arguments
  eq(conv.parse_args({ "to=org" }).to, "org", "to=")
  eq(conv.parse_args({ "from=csv", "to=tsv" }).from, "csv", "from=")
  eq(conv.parse_args({ "org" }).to, "org", "a bare word is the target")
  ok(select(2, conv.parse_args({ "to=latex" })) ~= nil, "unknown target refused")
  ok(select(2, conv.parse_args({ "bogus=1" })) ~= nil, "unknown option refused")
  ok(vim.tbl_contains(conv.complete("to="), "to=org"), "completion")
  ok(
    vim.tbl_contains(require("markdown.commands.table").subcommand_names(), "convert"),
    ":Markdown table convert exists"
  )

  -- ───────────── review fixes ─────────────
  -- an escaped pipe is not escaped twice
  local pipe = reg.find({ "| x \\| y | z |", "| --- | --- |", "| 1 | 2 |" })[1]
  eq(reg.render("gfm", pipe)[1], "| x \\| y | z |", "an escaped pipe survives the gfm writer")
  eq(#reg.find(reg.render("gfm", pipe))[1].header.cells, 2, "and the table keeps two columns")

  -- alignment survives gfm -> box / org -> gfm
  local aligned = reg.find(GFM)[1]
  eq(reg.render("gfm", aligned)[2], "| ----- | --: |", "gfm keeps the right-alignment colon")
  local from_org =
    reg.find({ "| a | b |", "|---+---|", "| <r> | <c> |", "| 1 | 2 |" }, { formats = { "org" } })[1]
  eq(reg.render("gfm", from_org)[2], "| -: | :-: |", "org cookies become gfm alignment")

  -- an empty row in an org table is data, not the alignment row
  local gaps =
    reg.find({ "| a | b |", "|---+---|", "| | |", "| 1 | 2 |" }, { formats = { "org" } })[1]
  eq(#gaps.rows, 2, "an all-empty org row stays a row")

  -- a multi-line cell written as box reads back as one row
  local br = reg.from_strings({ "a", "b" }, { { "x<br>y", "1" }, { "z", "2" } })
  local boxed = reg.find(reg.render("box", br), { formats = { "box" } })[1]
  eq(#boxed.rows, 2, "<br> cells come back as the same two rows")
  eq(boxed.rows[1].cells[1].content, "x<br>y", "with the lines joined again")
  eq(
    #reg.lossy("box", reg.from_strings({ "a" }, { { "x<br>y" } })),
    1,
    "one body row cannot say where it ends"
  )

  -- a header-only GFM table covers its separator line, so a rewrite does not leave it behind
  local only = reg.find({ "| a | b |", "| --- | --- |", "after" })[1]
  eq(only.end_line, 2, "header-only table ends on the separator")

  -- ───────────── review round 3 ─────────────
  local function no_newline(lines)
    for _, l in ipairs(lines) do
      if l:find("\n", 1, true) then return false end
    end
    return true
  end

  -- a multi-line csv field converts to org (it used to raise inside nvim_buf_set_lines)
  do
    local mb = buf_with({ "a,b", '"x', 'y",2' })
    local good, why = conv.convert(mb, { from = "csv", to = "org" }, 1)
    ok(good, "csv with a multi-line field -> org: " .. tostring(why))
    ok(no_newline(vim.api.nvim_buf_get_lines(mb, 0, -1, false)), "no cell line holds a newline")
    ok(vim.api.nvim_buf_get_lines(mb, 0, -1, false)[3]:find("x<br>y", 1, true), "as <br>")
  end

  -- a pipe in a csv cell is escaped in org, so it stays one cell
  do
    local piped = reg.render("org", reg.parse("csv", { "a,b", '"x|y",2' }))
    local back = reg.find(piped, { formats = { "org" } })[1]
    eq(#back.header.cells, 2, "the pipe did not become a column")
    eq(#back.rows[1].cells, 2, "nor in the body")
  end

  -- an escaped pipe from gfm / org is a plain pipe in csv / tsv
  do
    local gp = reg.find({ "| a | b |", "| --- | --- |", "| x \\| y | 2 |" })[1]
    eq(reg.render("csv", gp)[2], "x | y,2", "csv holds the plain pipe")
    eq(reg.render("tsv", gp)[2], "x | y\t2", "tsv too")
    local twice = reg.find({ "| a |", "| --- |", "| x \\\\| y |" })
    eq(#twice, 1, "an even run of backslashes does not escape (still one table)")
  end

  -- empty cells of a one-column table survive csv
  do
    local one = reg.find({ "| a |", "| --- |", "| |", "| x |" })[1]
    local lines = reg.render("csv", one)
    eq(table.concat(lines, "\n"), 'a\n""\nx', "an empty cell is written as an empty quoted field")
    eq(#reg.parse("csv", lines).rows, 2, "and reads back as a row")
    eq(#reg.parse("csv", { "a", "", "x" }).rows, 1, "a blank line is still no record")
  end

  -- CRLF inside a quoted field is one newline
  eq(
    reg.parse("csv", { "a,b\r", '"x\r', 'y",2\r' }).rows[1].cells[1].content,
    "x\ny",
    "no stray CR in a multi-line field"
  )

  -- a body row that looks like a delimiter row is data
  do
    local dash = reg.find({ "| a | b |", "|---|---|", "| - | - |", "| x | y |" })[1]
    eq(#dash.rows, 2, "the parser keeps the dash row")
    local lines = reg.render("box", dash)
    local rows_seen = 0
    for _, l in ipairs(lines) do
      if vim.startswith(l, "│") then rows_seen = rows_seen + 1 end
    end
    eq(rows_seen, 3, "box shows header + dash row + data row")
    local m =
      require("markdown.core.table_render").layout({ "| a | b |", "|---|---|", "| - | - |" })
    eq(m.rows[3].kind, "body", "the layout draws it as a body row")
    eq(m.rows[2].kind, "sep", "and only the second line as the rule")
  end

  -- TableView's own box style (╞═╪═╡ header rule) is found and read
  do
    local tv = reg.find({
      "┌─────┬─────┐",
      "│ a   │ b   │",
      "╞═════╪═════╡",
      "│ 1   │ 2   │",
      "├─────┼─────┤",
      "│ 3   │ 4   │",
      "└─────┴─────┘",
    }, { formats = { "box" } })
    eq(#tv, 1, "the table with a double header rule is found")
    eq(#tv[1].rows, 2, "two body rows")
    eq(tv[1].rows[2].cells[1].content, "3", "read correctly")
  end

  -- a multi-line csv field written as box keeps its rows apart
  do
    local mt = reg.parse("csv", { "a,b", '"x', 'y",2', "3,4" })
    local lines = reg.render("box", mt)
    local mids = 0
    for _, l in ipairs(lines) do
      if vim.startswith(l, "├") then mids = mids + 1 end
    end
    eq(mids, 2, "a rule between the rows, as for <br> cells")
    eq(#reg.find(lines, { formats = { "box" } })[1].rows, 2, "read back as two rows")
    eq(
      #reg.lossy("box", reg.parse("csv", { "a", '"x', 'y"' })),
      1,
      "a single multi-line row is reported as lossy"
    )
  end

  -- org: the rules between body rows are written back (TableView `:w` on an unedited table)
  do
    local ORG_GROUPS = { "| a | b |", "|---+---|", "| 1 | 2 |", "|---+---|", "| 3 | 4 |" }
    local og = reg.find(ORG_GROUPS, { formats = { "org" } })[1]
    eq(
      table.concat(reg.render("org", og), "\n"),
      table.concat(ORG_GROUPS, "\n"),
      "an unedited org table is written back as it was"
    )
    eq(#reg.lossy("org", og), 0, "nothing is lost writing org as org")
    ok(#reg.lossy("gfm", og) > 0, "but converting it to gfm drops the rules")
  end

  -- box: a rounded border stays rounded
  do
    local rounded = {
      "╭───┬───╮",
      "│ a │ b │",
      "├───┼───┤",
      "│ 1 │ 2 │",
      "╰───┴───╯",
    }
    local rb = reg.find(rounded, { formats = { "box" } })[1]
    eq(
      table.concat(reg.render("box", rb), "\n"),
      table.concat(rounded, "\n"),
      "the rounded table is written back unchanged"
    )
  end

  -- ───────────── independent review of 2696980 ─────────────
  -- csv / tsv data is not GFM text: a literal backslash + pipe survives csv -> csv / tsv
  do
    local cm = reg.parse("csv", { "h,k", "foo\\|bar,2", "C:\\dir\\|x,3" })
    eq(cm.format, "csv", "registry.parse says which format it read")
    eq(reg.render("csv", cm)[2], "foo\\|bar,2", "a backslash-pipe in csv data survives csv -> csv")
    eq(reg.render("tsv", cm)[3], "C:\\dir\\|x\t3", "and csv -> tsv")
    local fm = reg.from_strings({ "a" }, { { "p\\\\|q" } })
    eq(
      reg.render("csv", fm)[2],
      "p\\\\|q",
      "an even run of backslashes before a pipe stays as it is"
    )
  end

  -- csv: a last record that is a quoted empty field, without a trailing newline, is a record
  eq(#reg.parse("csv", { "a", '""' }).rows, 1, "a final quoted empty record is a row")

  -- org: an already escaped pipe is not escaped twice
  do
    local line = reg.render("org", reg.from_strings({ "a" }, { { "x \\| y" } }))[3]
    ok(line:find("x \\| y |", 1, true), "an escaped pipe is kept as it is")
    ok(not line:find("\\\\|", 1, true), "and not doubled")
  end

  -- org: a row ending in backslash + pipe is read with that pipe as a literal (org has no escape,
  -- the GFM reader's rule is shared): pinned so a change is a decision
  do
    local o2 =
      reg.find({ "| a | b \\|", "|---+---|", "| 1 | C:\\dir\\|" }, { formats = { "org" } })[1]
    eq(o2.header.cells[2].content, "b \\|", "a trailing backslash-pipe stays in the last cell")
  end

  -- box: TableView's own style (`╞` header rule) with a multi-line body row
  do
    local tv = reg.find({
      "┌───┬───┐",
      "│ a │ b │",
      "╞═══╪═══╡",
      "│ 1 │ 2 │",
      "│   │ 2b│",
      "├───┼───┤",
      "│ 3 │ 4 │",
      "└───┴───┘",
    }, { formats = { "box" } })[1]
    eq(#tv.rows, 2, "the lines between two rules are one row, also after a `╞` header rule")
    eq(tv.rows[1].cells[2].content, "2<br>2b", "joined with <br>")
  end

  -- the layout treats a header of dashes above the delimiter row as the header
  do
    local lay =
      require("markdown.core.table_render").layout({ "| - | - |", "|---|---|", "| 1 | 2 |" })
    eq(
      lay.rows[1].kind .. "," .. lay.rows[2].kind .. "," .. lay.rows[3].kind,
      "head,sep,body",
      "dash header, delimiter, body"
    )
  end

  -- org: rules that are stored nowhere are reported as lost, org -> org included
  do
    local lead =
      reg.find({ "|---+---|", "| a | b |", "|---+---|", "| 1 | 2 |" }, { formats = { "org" } })[1]
    eq(#reg.lossy("gfm", lead), 1, "a rule above the header is reported when converting")
    eq(#reg.lossy("org", lead), 1, "and when writing org again")
    local twice =
      reg.find({ "| a | b |", "|---+---|", "|---+---|", "| 1 | 2 |" }, { formats = { "org" } })[1]
    eq(#reg.lossy("org", twice), 1, "a second rule under the header rule is reported")
    local plain = reg.find({ "| a | b |", "|---+---|", "| 1 | 2 |" }, { formats = { "org" } })[1]
    eq(#reg.lossy("org", plain), 0, "an ordinary org table loses nothing")
  end

  -- org: a row without its closing pipe still has its cells
  do
    local open = reg.find({ "| a | b", "|---+---|", "| 1 | 2" }, { formats = { "org" } })[1]
    eq(strings(open), "a,b/1,2", "missing closing pipes are tolerated")
  end

  -- org: a rule without its closing pipe is a rule too (hand-typed tables)
  do
    local typed = reg.find({ "| a | b", "|---+---", "| 1 | 2" }, { formats = { "org" } })
    eq(#typed, 1, "an org block whose rule has no closing pipe is found")
    eq(strings(typed[1]), "a,b/1,2", "and read like the closed one")
    eq(#typed[1].raw_lines, 3, "the rule stays part of the block")
    local spaced = reg.find({ "| a | b |", "|-----+-----  ", "| 1 | 2 |" }, { formats = { "org" } })
    eq(#spaced, 1, "trailing blanks after an open rule are fine")
    local three = reg.find({ "| a | b | c", "|-+-+-", "| 1 | 2 | 3" }, { formats = { "org" } })
    eq(strings(three[1]), "a,b,c/1,2,3", "a rule made only of -+ with no pipe at the end")
    -- the written form keeps the rule and closes everything
    eq(reg.render("org", typed[1])[2], "|---+---|", "writing it back gives the closed rule")
    -- gfm separators and plain one-column rules stay gfm / not org, with or without closing pipe
    local gfm_closed = { "| a | b |", "| --- | --- |", "| 1 | 2 |" }
    eq(#reg.find(gfm_closed, { formats = { "org" } }), 0, "gfm")
    eq(#reg.find({ "| a | b", "|---|---", "| 1 | 2" }, { formats = { "org" } }), 0, "gfm, open")
    eq(#reg.find({ "| a", "|---", "| 1" }, { formats = { "org" } }), 0, "one column stays gfm")
    eq(#reg.find({ "| a |", "|-", "| 1 |" }, { formats = { "org" } }), 0, "org hline stays gfm")
    -- a data row that merely contains a plus is no rule
    eq(#reg.find({ "| a | b", "| 1 | 2+3" }, { formats = { "org" } }), 0, "a plus in a cell")
  end

  -- org: a rule starts with `|-` (org's own hline test), so `|+...` lines are data, never rules
  do
    local function org_of(lines) return reg.find(lines, { formats = { "org" } })[1] end
    -- a data row `|+|` between rows is a cell holding `+`, not a repeated rule that eats the row
    local plus = org_of({ "| a | b |", "|---+---|", "|+|", "| 1 | 2 |" })
    ok(plus ~= nil, "a block with a `|+|` data row is still an org table")
    if plus then
      -- the cells are compared, not the whole string: how short rows are padded is not under test
      local _, rows = reg.strings(plus)
      eq(#rows, 2, "the `|+|` row stays data and the row after it is not swallowed")
      eq(rows[1] and rows[1][1], "+", "the `|+|` row holds a `+` cell")
      eq(rows[2] and table.concat(rows[2], ","), "1,2", "and the row after it is intact")
      eq(#reg.lossy("org", plus), 0, "nothing is reported as lost")
    end
    -- `|+|`, `|+---|`, `|+-|` and `|+--+--+|` are no rules: with no real rule there is no org table
    for _, bad in ipairs({ "|+|", "|+---|", "|+-|", "|+--+--+|", "|+--+--+", "  |+---+---|" }) do
      eq(
        #reg.find({ "| a | b |", bad, "| 1 | 2 |" }, { formats = { "org" } }),
        0,
        bad .. " is no rule"
      )
    end
    -- the real rules stay rules: a leading dash, plus signs inside, open or closed
    for _, good in ipairs({ "|-+-|", "|---+---|", "|-+-+-", "  |-----+-----  ", "|-+|" }) do
      local t = org_of({ "| a | b |", good, "| 1 | 2 |" })
      ok(t ~= nil, good .. " is a rule")
      eq(t and strings(t), "a,b/1,2", good .. " is read as a rule")
    end
  end

  -- org: the strict half of the rule. After `|-` only `-` and `+` may follow, at least one `+`,
  -- and only blanks after the optional closing pipe. Everything else is a data row of an org
  -- table that has a real rule elsewhere, so it must neither end the table nor eat the row.
  do
    for _, data in ipairs({
      "|-5+3|", -- another character after the dash
      "|---+--- |", -- a blank inside, before the closing pipe
      "|--- +---|", -- a blank in the middle of the body
      "|-+|-+|", -- an inner pipe
      "|---+---| x |", -- text after the closing pipe
      "|---|", -- dashes only: no plus, so no rule (and not an org one-column rule)
      "|-|",
    }) do
      local t =
        reg.find({ "| a | b |", "|---+---|", data, "| 1 | 2 |" }, { formats = { "org" } })[1]
      ok(t ~= nil, data .. " does not break the org table")
      if t then
        local _, rows = reg.strings(t)
        eq(#rows, 2, data .. " is a data row, not a rule")
        eq(rows[2] and table.concat(rows[2], ","), "1,2", data .. " does not swallow the next row")
        eq(#reg.lossy("org", t), 0, data .. " loses nothing (it is no second rule)")
      end
    end
    -- the offending line keeps its text as a cell, so it really was read as data
    local dash =
      reg.find({ "| a | b |", "|---+---|", "|-5+3|", "| 1 | 2 |" }, { formats = { "org" } })[1]
    if dash then
      local _, rows = reg.strings(dash)
      eq(rows[1] and rows[1][1], "-5+3", "`|-5+3|` is a cell with that text")
    end
  end

  -- the csv separator is an option, and registry.parse hands it on
  do
    local semi = reg.parse("csv", { "a;b", "1;2" }, { sep = ";" })
    eq(strings(semi), "a,b/1,2", "csv reads a semicolon separator")
    eq(
      require("markdown.tables.formats.csv").render(semi, { sep = ";" })[2],
      "1;2",
      "and writes it"
    )
    eq(reg.parse("csv", { "a;b", "1;2" }).header.cells[1].content, "a;b", "default stays a comma")
  end

  -- write-back goes bottom-up: a table that changes its line count must not stale the ones below
  do
    local api = vim.api
    local cfg = require("markdown.config")
    local notify_before = vim.notify
    vim.notify = function() end
    cfg.setup({ table = { formats = { "gfm", "org", "box" } } })
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "|---+---|",
      "| a | b |",
      "|---+---|",
      "| 1 | 2 |",
      "|---+---|",
      "",
      "|G1|G2|",
      "|--|--|",
      "|1|2|",
    })
    local tables = require("markdown.tableview.parser").get_tables(buf)
    eq(#tables, 2, "an org table with three rules and a gfm table")
    local renderer = require("markdown.tableview.renderer")
    renderer.render_tables(tables, { floating = true })
    renderer.write_back()
    local out = api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(out[#out - 2], "| G1 | G2 |", "the table below the shrunk org table was still written")
    renderer.close_view()
    cfg.setup({})
    vim.notify = notify_before
  end

  -- TableView `move_current_row` on an org table with row groups: a move swaps two rows, the
  -- rules stay at their POSITIONS. So the group sizes survive and moving a row across a rule is
  -- how a row changes its group (decided 2026-10-15: not a bug; attaching the rule to a row would
  -- change the group sizes with every move)
  do
    local api = vim.api
    local cfg = require("markdown.config")
    local notify_before = vim.notify
    vim.notify = function() end
    cfg.setup({ table = { formats = { "gfm", "org", "box" } } })
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "| h | k |",
      "|---+---|",
      "| a | 1 |",
      "| b | 2 |",
      "|---+---|",
      "| c | 3 |",
      "| d | 4 |",
    })
    local renderer = require("markdown.tableview.renderer")
    local mt = require("markdown.tableview.parser").get_tables(buf)[1]
    eq(mt.format, "org", "the org table with row groups")
    renderer.render_markdowntable(mt, { floating = true, style = "markdown" })
    local win = api.nvim_get_current_win()
    for i, l in ipairs(api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false)) do
      if l:find("| c ", 1, true) then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.move_current_row(-1) -- c swaps places with b, across the rule
    renderer.write_back()
    eq(
      table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
      table.concat({
        "| h | k |",
        "|---+---|",
        "| a | 1 |",
        "| c | 3 |",
        "|---+---|",
        "| b | 2 |",
        "| d | 4 |",
      }, "\n"),
      "the rule stays between the second and third body row; c and b changed groups"
    )
    renderer.close_view()
    cfg.setup({})
    vim.notify = notify_before
  end

  -- ───────────── config ─────────────
  local cfgm = require("markdown.config")
  local saved_notify = vim.notify
  vim.notify = function() end
  cfgm.setup({ table = { formats = { "gfm", "org" } } })
  eq(#cfgm.get().table.formats, 2, "formats accepted")
  eq(
    #require("markdown.tableview.parser").get_tables_from_lines(ORG),
    1,
    "the parser answers for the enabled formats"
  )
  cfgm.setup({ table = { formats = { "gfm", "latex" } } })
  eq(#cfgm.get().table.formats, 1, "an unknown format falls back to the default")
  cfgm.setup({ table = { formats = {} } })
  eq(cfgm.get().table.formats[1], "gfm", "an empty list falls back to the default")
  vim.notify = saved_notify
  cfgm.setup({})
  eq(
    #require("markdown.tableview.parser").get_tables_from_lines(ORG),
    0,
    "back to gfm only: nothing else is found"
  )
end
