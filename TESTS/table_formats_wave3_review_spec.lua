-- TESTS/table_formats_wave3_review_spec.lua -- what the review of the wiki / asciidoc / latex / html /
-- json formats found: nothing outside a table may be replaced, nested or unclear tables are left
-- alone, newlines and escaped pipes survive every writer, and the hostile or odd inputs.
---@diagnostic disable: missing-fields

return function(H)
  local ok = H.ok
  local reg = require("markdown.tables.registry")
  local conv = require("markdown.commands.table_convert")

  ---Deep comparison (the shared `H.eq` compares references).
  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end

  local function strings(tbl)
    local h, r = reg.strings(tbl)
    return table.concat(h, ",")
      .. "/"
      .. table.concat(vim.tbl_map(function(x) return table.concat(x, ",") end, r), ";")
  end

  local function find(fmt, lines) return reg.find(lines, { formats = { fmt } }) end

  -- ───────────── a table is only a table when it fills its lines ─────────────
  eq(
    #find("html", { "before <table><tr><td>a</td></tr></table> after" }),
    0,
    "html: text around a one-line table"
  )
  eq(#find("html", { "Use `<table>` for tabular data." }), 0, "html: a mention in a code span")
  eq(
    #find("html", { "<table><tr><td>a</td></tr></table> <table><tr><td>b</td></tr></table>" }),
    0,
    "html: two tables on one line are not folded into one"
  )
  eq(
    #find("html", { "<table>", "<tr><td>a</td></tr>", "```html", "</table>", "```" }),
    1,
    "html: an unclosed table is not closed by something later that is fenced"
  )
  eq(
    #reg.find(
      { "<table>", "<tr><td>a</td></tr>", "```html", "x", "```", "</table>" },
      { formats = { "html" }, skip_fences = true }
    ),
    0,
    "html: the fence in the middle breaks the table"
  )
  eq(#find("latex", {
    "\\resizebox{\\textwidth}{!}{\\begin{tabular}{ll}",
    "a & b \\\\",
    "\\end{tabular}}",
  }), 0, "latex: a wrapped tabular is left alone")
  eq(
    #find("latex", { "x \\begin{tabular}{ll} a & b \\\\ \\end{tabular} y" }),
    0,
    "latex: text around a one-line tabular"
  )
  eq(
    #find("latex", { "Write `\\begin{tabular}{ll}` first." }),
    0,
    "latex: a mention in a code span"
  )
  eq(
    #find(
      "latex",
      { "\\begin{tabular}{ll}", "a & b \\\\", "% \\end{tabular}", "c & d \\\\", "\\end{tabular}" }
    ),
    1,
    "latex: an \\end{tabular} in a comment does not end the table"
  )
  eq(
    strings(
      find(
        "latex",
        { "\\begin{tabular}{ll}", "a & b \\\\", "% \\end{tabular}", "c & d \\\\", "\\end{tabular}" }
      )[1]
    ),
    "a,b/c,d",
    "latex: and the rows after the comment are read"
  )

  -- the surrounding text survives a conversion
  local buf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "before",
    "<table><tr><th>A</th></tr><tr><td>1</td></tr></table>",
    "after",
  })
  local done, msg = conv.convert(buf, { from = "html", to = "gfm" }, 2)
  ok(done, "convert html: " .. tostring(msg))
  local after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(after[1], "before", "the line above the table is kept")
  eq(after[#after], "after", "the line below the table is kept")
  vim.api.nvim_buf_delete(buf, { force = true })

  -- ───────────── from=auto: the specific format wins over GFM's pipe-line reading ─────────────
  local wiki = {
    '{| class="wikitable"',
    "|-",
    "! Name !! Qty",
    "|-",
    "| apple || 3",
    "|}",
  }
  local auto = reg.find(wiki, { formats = reg.embedded() })
  eq(#auto, 1, "auto: one table")
  eq(auto[1].format, "wiki", "auto: read as a wiki table, not as GFM pieces")
  eq({ auto[1].start_line, auto[1].end_line }, { 1, 6 }, "auto: the whole table")
  eq(reg.embedded()[#reg.embedded()], "gfm", "gfm is looked for last")

  -- ───────────── newlines in a cell reach every writer as a line break ─────────────
  local multiline = reg.from_strings({ "a", "b" }, { { "x\ny", "z" } })
  for _, target in ipairs({
    "wiki",
    "latex",
    "html",
    "asciidoc",
    "json",
    "grid",
    "psql",
    "rst",
    "org",
    "box",
    "gfm",
  }) do
    local lines = assert(reg.render(target, multiline))
    for _, line in ipairs(lines) do
      ok(not line:find("\n", 1, true), target .. ": no line of the output holds a newline")
    end
  end
  for _, target in ipairs({ "wiki", "latex", "html" }) do
    local t = assert(conv.read({ "a,b", '"x', 'y",z' }, { from = "csv" }, 1))
    ok(select(2, reg.render(target, t)) == nil, target .. ": a multi-line csv field converts")
  end

  -- ───────────── asciidoc ─────────────
  eq(
    #find("asciidoc", { "|===", "|a |b", "2+|wide", "|c |d", "|===" }),
    0,
    "asciidoc: a cell specifier on a later line leaves the table alone"
  )
  eq(
    #find("asciidoc", { "|===", "|a |b", "a|asciidoc cell", "|===" }),
    0,
    "asciidoc: a| style cell"
  )
  eq(#find("asciidoc", { "|===", "|a |b", "3*|x", "|===" }), 0, "asciidoc: a duplication specifier")
  eq(
    strings(find("asciidoc", { "|===", "|Version 2.0|x", "|win 95|y", "|===" })[1]),
    "Version 2.0,x/win 95,y",
    "asciidoc: numbers before a pipe are no specifier"
  )

  local multi = find("asciidoc", { "|===", "|h1 |h2", "", "|multi", "line |x", "|===" })[1]
  eq(
    strings(multi),
    "h1,h2/multi<br>line,x",
    "asciidoc: a continuation line with a pipe starts the next cell"
  )
  local para = find("asciidoc", { "|===", "|h1 |h2", "", "|one", "", "two |x", "|===" })[1]
  eq(
    strings(para),
    "h1,h2/one<br><br>two,x",
    "asciidoc: a blank line in a cell is a paragraph break"
  )
  local written = assert(
    reg.render(
      "asciidoc",
      reg.from_strings({ "h1", "h2" }, { { "l1<br>l2", "x" }, { "p<br><br>q", "y" } })
    )
  )
  eq(
    strings(find("asciidoc", written)[1]),
    "h1,h2/l1<br>l2,x;p<br><br>q,y",
    "asciidoc: multi-line cells survive our own output"
  )

  local anchored = reg.find(
    { "[[anchor]]", '[cols="1,2"]', "|===", "|a |b", "|===" },
    { formats = { "asciidoc" } }
  )
  eq(anchored[1].start_line, 3, "asciidoc: other attribute lines stay outside the replaced range")
  local optioned = find("asciidoc", { '[options="header"]', "|===", "|a |b", "|c |d", "|===" })
  eq(optioned[1].start_line, 1, 'asciidoc: [options="header"] belongs to the table')

  -- ───────────── html ─────────────
  local t0 = os.clock()
  local huge = find("html", { "<table>", '<tr><td colspan="20000000">x</td></tr>', "</table>" })[1]
  ok(os.clock() - t0 < 2, "html: a huge colspan is clamped, not built")
  ok(#huge.header.cells <= 1000, "html: at most 1000 columns")
  local deep = find(
    "html",
    { "<table>", '<tr><td rowspan="5">a</td><td>b</td></tr>', "<tr><td>c</td></tr>", "</table>" }
  )[1]
  eq(#deep.rows, 1, "html: a rowspan past the last row invents no rows")
  eq(
    strings(
      find("html", { "<table>", '<tr><td data-colspan="5">x</td><td>y</td></tr>', "</table>" })[1]
    ),
    "x,y/",
    "html: data-colspan is not colspan"
  )
  eq(
    strings(
      find(
        "html",
        { "<table>", "<tr><td>a<!-- <td>hidden</td> --></td><td>b</td></tr>", "</table>" }
      )[1]
    ),
    "a,b/",
    "html: comments hold no cells"
  )
  eq(
    strings(
      find("html", { "<table>", "<tr><td>p<script>var x='</td>'</script>q</td></tr>", "</table>" })[1]
    ),
    "pq/",
    "html: scripts are skipped"
  )
  eq(
    strings(find("html", {
      "<table>",
      "<tr><th>A</th></tr>",
      "<tr><td>&#x41;&#38;lt;&#0;&amp;</td></tr>",
      "</table>",
    })[1]),
    "A/A&lt;&#0;&",
    "html: hex entities, one decoding pass, NUL stays as written"
  )
  eq(
    strings(
      find(
        "html",
        { "<table>", "<tr><th>A</th></tr>", "<tr><td><p>a</p><p>b</p></td></tr>", "</table>" }
      )[1]
    ),
    "A/a b",
    "html: paragraphs are not glued together"
  )
  eq(#find("html", {
    "<table>",
    "<tr><td><table>",
    "<tr><td>in</td></tr>",
    "</table></td></tr>",
    "<tr><td>after</td></tr>",
    "</table>",
  }), 0, "html: a table inside a cell leaves the outer one alone")

  -- ───────────── latex ─────────────
  eq(
    strings(
      find("latex", { "\\begin{tabular}{ll}", "a & b \\\\[2pt]", "c & d \\\\", "\\end{tabular}" })[1]
    ),
    "a,b/c,d",
    "latex: \\\\[2pt]"
  )
  eq(
    strings(
      find(
        "latex",
        { "\\begin{tabular}{ll}", "\\toprule[1pt]", "a & b \\\\", "\\bottomrule", "\\end{tabular}" }
      )[1]
    ),
    "a,b/",
    "latex: \\toprule[1pt]"
  )
  eq(
    find("latex", { "\\begin{tabular}{*{3}{c}}", "a & b & c \\\\", "\\end{tabular}" })[1].alignments,
    { "center", "center", "center" },
    "latex: *{3}{c}"
  )
  eq(
    strings(find("latex", { "\\begin{tabular}[t]{ll}", "a & b \\\\", "\\end{tabular}" })[1]),
    "a,b/",
    "latex: [t]"
  )
  eq(
    #find(
      "latex",
      { "\\begin{tabular}{ll}", "% \\multicolumn{2}{c}{x}", "a & b \\\\", "\\end{tabular}" }
    ),
    1,
    "latex: a \\multicolumn in a comment does not matter"
  )
  eq(#find("latex", {
    "\\begin{tabular}{ll}",
    "\\begin{tabular}{ll}",
    "c & d \\\\",
    "\\end{tabular} \\\\",
    "\\end{tabular}",
  }), 0, "latex: a nested tabular leaves the outer one alone")
  local br = reg.from_strings({ "a", "b" }, { { "x", "1<br>2" } })
  eq(
    strings(find("latex", assert(reg.render("latex", br)))[1]),
    "a,b/x,1<br>2",
    "latex: a line break round trip"
  )

  -- ───────────── wiki ─────────────
  eq(
    strings(
      find("wiki", { "{|", "|-", "! A !! B", "|-", "| see [[a=b|text]] || {{t|x=1}}", "|}" })[1]
    ),
    "A,B/see [[a=b|text]],{{t|x=1}}",
    "wiki: links and templates are no attributes"
  )
  eq(
    #find("wiki", { "{|", "|-", "! A", "|-", "|", "{|", "| in", "|}", "|}" }),
    0,
    "wiki: a table in a cell leaves the outer one alone"
  )
  local bang = reg.from_strings({ "a!!b", "c" }, { { "x", "y!!z" } })
  eq(
    strings(find("wiki", assert(reg.render("wiki", bang)))[1]),
    "a!!b,c/x,y!!z",
    "wiki: !! in a cell survives"
  )
  local captioned = find("wiki", { "{|", "|+ Title", "|-", "! A", "|-", "| 1", "|}" })[1]
  ok(#reg.lossy("gfm", captioned) > 0, "wiki: the caption is reported when it cannot be kept")
  eq(#reg.lossy("wiki", captioned), 0, "wiki: and kept by wiki itself")

  -- ───────────── escaped pipes (GFM cell text) in formats without that escape ─────────────
  local piped = reg.from_strings({ "a", "b" }, { { "x\\|y", "z" } })
  for _, target in ipairs({ "wiki", "asciidoc", "latex", "html", "json" }) do
    local lines = assert(reg.render(target, piped))
    local back = target == "json" and reg.parse("json", lines) or find(target, lines)[1]
    eq(strings(back), "a,b/x|y,z", target .. ": an escaped pipe is a plain pipe in the data")
  end

  -- ───────────── json ─────────────
  for _, bad in ipairs({ "01", "1.", "1e", "1e+", "1.5.5", "-" }) do
    local t, err = reg.parse("json", { "[" .. bad .. "]" })
    ok(t == nil and err ~= nil, "json: " .. bad .. " is no number")
  end
  for _, good in ipairs({ "0", "-0", "12", "-3.5", "1e5", "1.5E-3", "0.1" }) do
    ok(reg.parse("json", { "[" .. good .. "]" }) ~= nil, "json: " .. good .. " is a number")
  end

  local dups = assert(reg.parse("json", { '[["a","a",""],[1,2,3]]' }))
  local rendered = table.concat(assert(reg.render("json", dups)), "")
  ok(
    rendered:find('"a": ', 1, true)
      and rendered:find('"a_2": ', 1, true)
      and rendered:find('"column3": ', 1, true),
    "json: duplicate and empty headers become distinct keys"
  )
  eq(
    strings(assert(reg.parse("json", assert(reg.render("json", dups))))),
    "a,a_2,column3/1,2,3",
    "json: and no value is lost"
  )
  local clash = reg.from_strings({ "", "column1" }, { { "x", "y" } })
  eq(
    strings(assert(reg.parse("json", assert(reg.render("json", clash))))),
    "column1,column1_2/x,y",
    "json: an empty header does not collide with column1"
  )

  local edited = assert(reg.parse("json", { '[{"n":12}]' }))
  edited.rows[1].cells[1].content = "1-2"
  ok(
    table.concat(assert(reg.render("json", edited)), ""):find('"n": "1-2"', 1, true),
    "json: an edited number that is none becomes a string"
  )
  edited.rows[1].cells[1].content = "01"
  ok(
    table.concat(assert(reg.render("json", edited)), ""):find('"n": "01"', 1, true),
    "json: 01 too"
  )
  local big = reg.from_strings({ "id" }, { { "12345678901234567" } })
  ok(
    table.concat(assert(reg.render("json", big)), ""):find('"id": "12345678901234567"', 1, true),
    "json: an integer past 15 digits stays a string"
  )

  ok(reg.parse("json", { "\239\187\191[1]" }) ~= nil, "json: a BOM is skipped")
  local nothing, nerr = reg.parse("json", { "[{}]" })
  ok(
    nothing == nil and nerr:find("no columns", 1, true),
    "json: objects without keys: " .. tostring(nerr)
  )
  local deep_json, derr = reg.parse("json", { ("["):rep(5000) .. ("]"):rep(5000) })
  ok(
    deep_json == nil and derr:find("deeply", 1, true),
    "json: deep nesting is refused, not a stack overflow: " .. tostring(derr)
  )

  -- ───────────── the config list follows the registry ─────────────
  local config = require("markdown.config")
  config.setup({ table = { formats = reg.embedded() } })
  eq(config.get().table.formats, reg.embedded(), "config: every embedded format is accepted")
  config.setup({})
end
