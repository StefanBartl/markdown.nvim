-- TESTS/table_formats_wave3_spec.lua -- the third wave of table formats: MediaWiki, AsciiDoc, LaTeX
-- tabular, HTML with colspan/rowspan (embedded) and JSON (standalone). Found or read, written back,
-- and read -> written -> read stays the same for every pair.
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

  local WIKI = {
    '{| class="wikitable"',
    "|-",
    "! Name !! Qty",
    "|-",
    "| apple || 3",
    "|-",
    "| pear || 12",
    "|}",
  }
  local ASCIIDOC = {
    "[%header]",
    "|===",
    "|Name |Qty",
    "",
    "|apple |3",
    "|pear |12",
    "|===",
  }
  local LATEX = {
    "\\begin{tabular}{ll}",
    "\\hline",
    "Name & Qty \\\\",
    "\\hline",
    "apple & 3 \\\\",
    "pear & 12 \\\\",
    "\\hline",
    "\\end{tabular}",
  }
  local HTML = {
    "<table>",
    "  <tr><th>Name</th><th>Qty</th></tr>",
    "  <tr><td>apple</td><td>3</td></tr>",
    "  <tr><td>pear</td><td>12</td></tr>",
    "</table>",
  }
  local JSON = { '[{"name": "apple", "qty": 3}, {"name": "pear", "qty": 12}]' }

  -- ───────────── wiki ─────────────
  local w = reg.find(WIKI, { formats = { "wiki" } })
  eq(#w, 1, "wiki table found")
  eq(strings(w[1]), "Name,Qty/apple,3;pear,12", "wiki parsed")
  eq({ w[1].start_line, w[1].end_line }, { 1, 8 }, "wiki range")

  w = reg.find({
    '{| class="wikitable" style="width:50%"',
    "|+ A caption",
    "|-",
    "! scope=col | Name !! Qty",
    "|-",
    '| style="color:red" | a{{!}}b || 1',
    "continued",
    "|}",
  }, { formats = { "wiki" } })
  eq(
    strings(w[1]),
    "Name,Qty/a|b,1<br>continued",
    "attributes dropped, {{!}} is a pipe, a plain line continues the cell"
  )
  eq(w[1].caption, "A caption", "caption kept")
  ok(#reg.lossy("gfm", w[1]) > 0, "dropped cell attributes are reported")
  eq(
    #reg.find({ "{| ", "|- ", "no end" }, { formats = { "wiki" } }),
    0,
    "an unclosed wiki table is none"
  )

  -- ───────────── asciidoc ─────────────
  local a = reg.find(ASCIIDOC, { formats = { "asciidoc" } })
  eq(#a, 1, "asciidoc table found")
  eq(strings(a[1]), "Name,Qty/apple,3;pear,12", "asciidoc parsed")
  eq({ a[1].start_line, a[1].end_line }, { 1, 7 }, "the attribute line belongs to the table")

  a = reg.find({ "|===", "|a |b", "|c \\| d |e", "|===" }, { formats = { "asciidoc" } })
  eq(strings(a[1]), "a,b/c | d,e", "no attribute line; an escaped pipe stays")
  eq(
    #reg.find({ "|===", "2+|span |x", "|===" }, { formats = { "asciidoc" } }),
    0,
    "a cell specifier: not read"
  )
  a = reg.find({ "|===", "|a |b", "continues here", "|c |d", "|===" }, { formats = { "asciidoc" } })
  eq(strings(a[1]), "a,b<br>continues here/c,d", "a line without | continues the cell")

  -- ───────────── latex ─────────────
  local l = reg.find(LATEX, { formats = { "latex" } })
  eq(#l, 1, "tabular found")
  eq(strings(l[1]), "Name,Qty/apple,3;pear,12", "tabular parsed, rules dropped")
  eq(l[1].alignments, { "left", "left" }, "column spec gives the alignment")
  local lr = reg.find(
    { "\\begin{tabular}{lr}", "a & b \\\\", "\\end{tabular}" },
    { formats = { "latex" } }
  )
  eq(lr[1].alignments, { "left", "right" }, "l and r")

  l = reg.find({
    "\\begin{tabular}{|c|p{3cm}|}",
    "x & 100\\% \\\\ % a comment",
    "a\\&b & \\$5 \\_ \\textbackslash{} \\\\",
    "\\end{tabular}",
  }, { formats = { "latex" } })
  eq(l[1].alignments, { "center", "left" }, "|c|p{3cm}|")
  eq(strings(l[1]), "x,100%/a&b,$5 _ \\", "escapes are undone, a comment is dropped")
  eq(
    #reg.find(
      { "\\begin{tabular}{ll}", "\\multicolumn{2}{c}{x} \\\\", "\\end{tabular}" },
      { formats = { "latex" } }
    ),
    0,
    "multicolumn: not read"
  )
  local escaped =
    assert(reg.render("latex", reg.from_strings({ "a&b", "c" }, { { "50%", "x_y \\ ~" } })))
  eq(escaped[3], "a\\&b & c \\\\", "special characters are escaped on writing")
  eq(
    escaped[5],
    "50\\% & x\\_y \\textbackslash{} \\textasciitilde{} \\\\",
    "backslash and tilde too"
  )

  -- ───────────── html with spans ─────────────
  local h = reg.find(HTML, { formats = { "html" } })
  eq(#h, 1, "html table found")
  eq(strings(h[1]), "Name,Qty/apple,3;pear,12", "html parsed")

  h = reg.find({
    "<table>",
    "<tr><th colspan=2>Fruit</th><th align=right>Qty</th></tr>",
    '<tr><td rowspan="2">apple</td><td>red</td><td>3</td></tr>',
    "<tr><td>green &amp; <b>sour</b><br>x</td><td>4</td></tr>",
    "</table>",
  }, { formats = { "html" } })
  eq(
    strings(h[1]),
    "Fruit,,Qty/apple,red,3;,green & sour<br>x,4",
    "spans laid out on the grid, tags stripped, entities decoded"
  )
  eq(h[1].alignments, { "left", "left", "right" }, "align= gives the alignment")
  eq(#h[1].spans, 2, "two merged cells remembered")
  ok(#reg.lossy("gfm", h[1]) > 0, "other formats report the merge")
  local back = assert(reg.render("html", h[1]))
  local text = table.concat(back, "\n")
  ok(
    text:find('colspan="2"', 1, true) and text:find('rowspan="2"', 1, true),
    "html writes the spans back"
  )
  eq(#reg.find(back, { formats = { "html" } })[1].spans, 2, "and reads them again")
  eq(#reg.lossy("html", h[1]), 0, "html keeps its own spans")
  eq(
    #reg.find({ "<table><tr><td>a</td></tr>" }, { formats = { "html" } }),
    0,
    "an unclosed table is none"
  )
  local one = reg.find(
    { "<table><tr><th>A</th></tr><tr><td>1 &lt; 2</td></tr></table>" },
    { formats = { "html" } }
  )
  eq(strings(one[1]), "A/1 < 2", "a table on one line")
  ok(
    table
      .concat(assert(reg.render("html", reg.from_strings({ "a" }, { { "x < y & z" } }))), "\n")
      :find("x &lt; y &amp; z", 1, true),
    "html escapes on writing"
  )

  -- ───────────── json (standalone) ─────────────
  local j = assert(reg.parse("json", JSON))
  eq(strings(j), "name,qty/apple,3;pear,12", "array of objects")
  eq(
    #reg.find(JSON, { formats = { "wiki", "asciidoc", "latex", "html" } }),
    0,
    "json is not an embedded format"
  )

  j = assert(reg.parse("json", { '[{"b":1,"a":2},{"a":3,"c":null}]' }))
  eq(strings(j), "b,a,c/1,2,;,3,", "columns in order of first appearance, null is an empty cell")

  j = assert(reg.parse("json", { '[["x","y"],[1,"two"],[true,[1,2]]]' }))
  eq(strings(j), "x,y/1,two;true,[1,2]", "array of arrays; nested values as compact JSON")

  j = assert(reg.parse("json", { '[1,"a"]' }))
  eq(strings(j), "value/1;a", "plain values are one column")

  local bad, err = reg.parse("json", { "{}" })
  ok(
    bad == nil and err:find("array", 1, true),
    "an object at the top is no table: " .. tostring(err)
  )
  bad, err = reg.parse("json", { "[1," })
  ok(bad == nil and err:find("not JSON", 1, true), "broken JSON is reported: " .. tostring(err))
  bad = reg.parse("json", { "[]" })
  ok(bad == nil, "an empty array is no table")
  bad = reg.parse("json", { '[{"a":1}, 5]' })
  ok(bad == nil, "mixed objects and values are refused")

  -- types survive a JSON round trip; other sources write plain numbers as numbers
  j = assert(reg.parse("json", { '[{"id":"007","n":12,"ok":true,"gone":null,"obj":{"k":[1]}}]' }))
  local out = table.concat(assert(reg.render("json", j)), "")
  ok(out:find('"id": "007"', 1, true), "a string that looks like a number stays a string")
  ok(
    out:find('"n": 12', 1, true) and out:find('"ok": true', 1, true),
    "numbers and booleans keep their type"
  )
  ok(
    out:find('"gone": null', 1, true) and out:find('"obj": {"k":[1]}', 1, true),
    "null and nested values too"
  )
  local from_gfm = table.concat(
    assert(reg.render("json", reg.from_strings({ "n", "s", "z" }, { { "12", "x", "007" } }))),
    ""
  )
  ok(
    from_gfm:find('"n": 12', 1, true)
      and from_gfm:find('"s": "x"', 1, true)
      and from_gfm:find('"z": "007"', 1, true),
    "from another format: plain numbers become numbers"
  )

  -- unicode and escapes
  j = assert(reg.parse("json", { '[{"t":"a\\"b\\n\\u00e4"}]' }))
  eq(strings(j), 't/a"b\n\xc3\xa4', "string escapes are decoded")

  -- convert reads json as a standalone document
  local t = conv.read(JSON, { from = "json" }, 1)
  eq(strings(t), "name,qty/apple,3;pear,12", "convert from=json")
  ok(
    select(2, conv.parse_args({ "from=json", "to=wiki" })) == nil,
    "json and wiki are convert targets"
  )

  -- ───────────── round trips ─────────────
  local SOURCES = {
    { "wiki", WIKI },
    { "asciidoc", ASCIIDOC },
    { "latex", LATEX },
    { "html", HTML },
  }
  local TARGETS = {
    "gfm",
    "org",
    "box",
    "grid",
    "psql",
    "rst",
    "wiki",
    "asciidoc",
    "latex",
    "html",
    "csv",
    "json",
  }
  local function read_in(name, lines)
    if name == "csv" or name == "json" then return reg.parse(name, lines) end
    return reg.find(lines, { formats = { name } })[1]
  end
  local all_sources = {}
  for _, s in ipairs(SOURCES) do
    all_sources[#all_sources + 1] = { s[1], read_in(s[1], s[2]) }
  end
  all_sources[#all_sources + 1] = { "json", assert(reg.parse("json", JSON)) }
  for _, src in ipairs(all_sources) do
    local expected = strings(src[2])
    for _, target in ipairs(TARGETS) do
      local lines = assert(reg.render(target, src[2]))
      local back2 = read_in(target, lines)
      local label = src[1] .. " -> " .. target
      ok(back2 ~= nil, label .. ": the written table is read again")
      if #reg.lossy(target, src[2]) == 0 then
        eq(strings(back2), expected, label .. ": same cells after the round trip")
      end
      eq(
        assert(reg.render(target, back2)),
        lines,
        label .. ": writing it again gives the same lines"
      )
    end
  end

  -- ───────────── nothing changes unless listed; config accepts the names ─────────────
  for _, found in ipairs(reg.find(WIKI)) do
    eq(
      found.format,
      "gfm",
      "wiki is not looked for by default (GFM may read its pipe lines, as before)"
    )
  end
  eq(#reg.find(HTML), 0, "html is not looked for by default")
  for _, name in ipairs({ "wiki", "asciidoc", "latex", "html" }) do
    ok(vim.tbl_contains(reg.embedded(), name), name .. " is an embedded format")
  end
  ok(not vim.tbl_contains(reg.embedded(), "json"), "json is standalone")
  local config = require("markdown.config")
  config.setup({ table = { formats = { "gfm", "wiki", "asciidoc", "latex", "html" } } })
  eq(
    config.get().table.formats,
    { "gfm", "wiki", "asciidoc", "latex", "html" },
    "table.formats takes the new names"
  )
  config.setup({})
end
