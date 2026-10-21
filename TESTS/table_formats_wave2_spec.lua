-- TESTS/table_formats_wave2_spec.lua -- the second wave of table formats: grid (MySQL, reST,
-- Pandoc), psql's aligned output and reST simple tables. Found in documents, written back, and
-- read -> written -> read stays the same for every format pair.
---@diagnostic disable: missing-fields

return function(H)
  local ok = H.ok

  ---Deep comparison (the shared `H.eq` compares references).
  local function eq(a, b, msg)
    if not vim.deep_equal(a, b) then
      error(("FAIL %s: expected %s, got %s"):format(msg or "", vim.inspect(b), vim.inspect(a)), 2)
    end
  end
  local reg = require("markdown.tables.registry")

  local function strings(tbl)
    local h, r = reg.strings(tbl)
    return table.concat(h, ",")
      .. "/"
      .. table.concat(vim.tbl_map(function(x) return table.concat(x, ",") end, r), ";")
  end

  local MYSQL = {
    "+-------+-----+",
    "| Name  | Qty |",
    "+-------+-----+",
    "| apple | 3   |",
    "| pear  | 12  |",
    "+-------+-----+",
  }
  local RST_GRID = {
    "+-------+-----+",
    "| Name  | Qty |",
    "+=======+=====+",
    "| apple | 3   |",
    "|       | ea  |",
    "+-------+-----+",
    "| pear  | 12  |",
    "+-------+-----+",
  }
  local PANDOC = {
    "+-------+-----+",
    "| Name  | Qty |",
    "+:=====:+====:+",
    "| apple | 3   |",
    "+-------+-----+",
  }
  local PSQL = {
    " Name  | Qty",
    "-------+-----",
    " apple |   3",
    " pear  |  12",
    "(2 rows)",
  }
  local RST_SIMPLE = {
    "=====  ===",
    "Name   Qty",
    "=====  ===",
    "apple  3",
    "pear   12",
    "=====  ===",
  }

  -- ───────────── grid ─────────────
  local g = reg.find(MYSQL, { formats = { "grid" } })
  eq(#g, 1, "mysql grid found")
  eq(strings(g[1]), "Name,Qty/apple,3;pear,12", "mysql grid parsed: one line, one row")
  eq(g[1].style, "mysql", "no = border: mysql style")
  eq(g[1].start_line, 1, "grid range start")
  eq(g[1].end_line, 6, "grid range end")

  g = reg.find(RST_GRID, { formats = { "grid" } })
  eq(
    strings(g[1]),
    "Name,Qty/apple,3<br>ea;pear,12",
    "reST grid: lines between borders are one row"
  )
  eq(g[1].style, "rst", "the = border is reST")

  g = reg.find(PANDOC, { formats = { "grid" } })
  eq(g[1].alignments, { "center", "right" }, "pandoc colons give the alignment")

  -- a header of several lines and a `|` inside a cell
  g = reg.find({
    "+------+------+",
    "| a    | b    |",
    "| more |      |",
    "+======+======+",
    "| x|y  | 1    |",
    "+------+------+",
  }, { formats = { "grid" } })
  eq(strings(g[1]), "a<br>more,b/x|y,1", "header lines join; a pipe in a cell stays")

  -- spanning cells are not read at all
  eq(#reg.find({
    "+-----+-----+",
    "| a   | b   |",
    "+-----+-----+",
    "| span      |",
    "+-----+-----+",
  }, { formats = { "grid" } }), 0, "a spanning cell: not a plain grid")
  eq(
    #reg.find({ "+---+", "text", "+---+" }, { formats = { "grid" } }),
    0,
    "borders around prose are no table"
  )

  -- ───────────── psql ─────────────
  local p = reg.find(PSQL, { formats = { "psql" } })
  eq(#p, 1, "psql output found")
  eq(strings(p[1]), "Name,Qty/apple,3;pear,12", "psql parsed")
  eq(p[1].start_line, 1, "psql range start (the header line)")
  eq(p[1].end_line, 5, "psql range end includes the (N rows) footer")
  eq(p[1].footer, true, "and remembers it")

  local doc = { "intro", "", unpack(PSQL) }
  vim.list_extend(doc, { "", "after" })
  p = reg.find(doc, { formats = { "psql" } })
  eq(p[1].start_line, 3, "psql inside a document")
  eq(p[1].end_line, 7, "ends at the footer")

  eq(
    #reg.find({ "a   | b", "----+----", "no pipes here" }, { formats = { "psql" } }),
    1,
    "a header and rule alone is a table"
  )
  eq(
    #reg.find({ "plain prose", "-------+-------", "x" }, { formats = { "psql" } }),
    0,
    "a rule under prose is none"
  )
  eq(
    #reg.find({ "| a | b |", "|---+---|", "| 1 | 2 |" }, { formats = { "psql" } }),
    0,
    "an org table is not psql"
  )
  eq(
    #reg.find({ "| a | b |", "| --- | --- |", "| 1 | 2 |" }, { formats = { "psql" } }),
    0,
    "nor is GFM"
  )

  -- wide characters are cut by display width
  p = reg.find({ " 名前 | n", "------+---", " 日本 | 1" }, { formats = { "psql" } })
  eq(strings(p[1]), "名前,n/日本,1", "double-width cells are cut at the right column")

  -- ───────────── rst simple ─────────────
  local r = reg.find(RST_SIMPLE, { formats = { "rst" } })
  eq(#r, 1, "reST simple table found")
  eq(strings(r[1]), "Name,Qty/apple,3;pear,12", "reST simple parsed")
  eq(r[1].end_line, 6, "range")

  r = reg.find({
    "=====  ===",
    "a      b",
    "c      d",
    "=====  ===",
  }, { formats = { "rst" } })
  eq(strings(r[1]), "a,b/c,d", "without a header border the first row is the header")

  r = reg.find({
    "====  ====",
    "A     B",
    "====  ====",
    "one   two",
    "      three",
    "..    x",
    "====  ====",
  }, { formats = { "rst" } })
  eq(
    strings(r[1]),
    "A,B/one,two<br>three;,x",
    "a blank first column continues the row; .. is a blank cell"
  )

  eq(
    #reg.find({ "=====  ===", "a      b" }, { formats = { "rst" } }),
    0,
    "an unclosed table is none"
  )
  eq(
    #reg.find({ "=== ===", "-- --", "=== ===" }, { formats = { "rst" } }),
    0,
    "column span underlines are not read"
  )
  eq(
    #reg.find({ "Title", "=====", "text" }, { formats = { "rst" } }),
    0,
    "a section underline is no table"
  )

  -- ───────────── fences are skipped on request ─────────────
  local fenced = { "```", unpack(MYSQL) }
  vim.list_extend(fenced, { "```" })
  eq(
    #reg.find(fenced, { formats = { "grid" }, skip_fences = true }),
    0,
    "a grid in a code fence is left alone"
  )
  eq(#reg.find(fenced, { formats = { "grid" } }), 1, "unless fences are not skipped")

  -- ───────────── round trips: read -> write -> read, for every format pair ─────────────
  local SOURCES = {
    { "grid", MYSQL },
    { "grid", RST_GRID },
    { "psql", PSQL },
    { "rst", RST_SIMPLE },
  }
  local TARGETS = { "gfm", "org", "box", "grid", "psql", "rst" }
  for _, src in ipairs(SOURCES) do
    local t = reg.find(src[2], { formats = { src[1] } })[1]
    local expected = strings(t)
    for _, target in ipairs(TARGETS) do
      local lines = assert(reg.render(target, t))
      local back = reg.find(lines, { formats = { target } })
      local label = src[1] .. " -> " .. target
      eq(#back, 1, label .. ": the written table is found again")
      local got = strings(back[1])
      -- what the target cannot hold is reported by `lossy`, so only compare when it is silent
      if #reg.lossy(target, t) == 0 then
        eq(got, expected, label .. ": same cells after the round trip")
      end
      -- writing what was read changes nothing further
      local again = assert(reg.render(target, back[1]))
      eq(again, lines, label .. ": writing it again gives the same lines")
    end
  end

  -- every format's own text survives read -> write -> read byte for byte
  for _, src in ipairs(SOURCES) do
    local t = reg.find(src[2], { formats = { src[1] } })[1]
    local lines = assert(reg.render(src[1], t))
    local t2 = reg.find(lines, { formats = { src[1] } })[1]
    eq(strings(t2), strings(t), src[1] .. ": own format round trip")
    eq(assert(reg.render(src[1], t2)), lines, src[1] .. ": own format is stable")
  end

  -- ───────────── lossy ─────────────
  local aligned = reg.from_strings({ "a", "b" }, { { "1", "2" } }, { "right", "center" })
  ok(#reg.lossy("rst", aligned) > 0, "rst reports lost alignment")
  ok(#reg.lossy("psql", aligned) > 0, "psql reports lost alignment")
  eq(#reg.lossy("grid", aligned), 0, "grid keeps alignment")
  local multi = reg.from_strings({ "a", "b" }, { { "x", "y<br>z" } })
  ok(#reg.lossy("psql", multi) > 0, "psql reports multi-line cells")
  eq(#reg.lossy("grid", multi), 0, "grid keeps multi-line cells")
  eq(#reg.lossy("rst", multi), 0, "rst keeps multi-line cells outside the first column")
  local first = reg.from_strings({ "a", "b" }, { { "x<br>y", "2" } })
  first.header.cells[1].content = "h<br>i"
  ok(#reg.lossy("rst", first) > 0, "rst reports multi-line text in the first column")

  -- pandoc alignment is written back when there is any
  local back = assert(reg.render("grid", reg.find(PANDOC, { formats = { "grid" } })[1]))
  eq(
    reg.find(back, { formats = { "grid" } })[1].alignments,
    { "center", "right" },
    "pandoc alignment round trip"
  )

  -- an empty first cell in a reST simple table is written `..`
  local blank = reg.from_strings({ "a", "b" }, { { "", "2" } })
  ok(
    table.concat(assert(reg.render("rst", blank)), "\n"):find("%.%.%s+2"),
    "an empty first cell becomes .."
  )

  -- ───────────── nothing changes unless the formats are listed ─────────────
  eq(#reg.find(MYSQL), 0, "grid is not looked for by default")
  eq(#reg.find(PSQL), 0, "psql is not looked for by default")
  eq(#reg.find(RST_SIMPLE), 0, "rst is not looked for by default")
  ok(
    vim.tbl_contains(reg.embedded(), "grid")
      and vim.tbl_contains(reg.embedded(), "psql")
      and vim.tbl_contains(reg.embedded(), "rst"),
    "the new formats are embedded ones"
  )

  -- ───────────── the config accepts them ─────────────
  local config = require("markdown.config")
  config.setup({ table = { formats = { "gfm", "grid", "psql", "rst" } } })
  eq(
    config.get().table.formats,
    { "gfm", "grid", "psql", "rst" },
    "table.formats takes the new names"
  )
  config.setup({})
end
