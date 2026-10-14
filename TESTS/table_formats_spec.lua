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
