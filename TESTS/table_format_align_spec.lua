-- TESTS/table_format_align_spec.lua -- `:Markdown table format` defaults to left alignment and
-- leaves every row of the table exactly as wide as the others (same display column for each
-- unescaped pipe), also with escaped pipes, code spans, umlauts, CJK, emoji and empty cells.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("markdown.config")
  local tf = require("markdown.core.table_fmt")
  local bs = string.char(92)

  ---Display columns (0-based) at which an unescaped `|` sits.
  ---@param line string
  ---@return integer[]
  local function pipe_cols(line)
    local cols = {}
    local i = 1
    while i <= #line do
      local c = line:sub(i, i)
      if c == bs then
        i = i + 2
      else
        if c == "|" then cols[#cols + 1] = vim.fn.strdisplaywidth(line:sub(1, i - 1)) end
        i = i + 1
      end
    end
    return cols
  end

  ---Every line of `out` has the same pipe columns and the same display width.
  local function assert_rectangular(out, label)
    local first = pipe_cols(out[1])
    ok(#first >= 2, label .. ": header has pipes")
    local w = vim.fn.strdisplaywidth(out[1])
    for i, l in ipairs(out) do
      eq(
        table.concat(pipe_cols(l), ","),
        table.concat(first, ","),
        label .. ": pipes of line " .. i
      )
      eq(vim.fn.strdisplaywidth(l), w, label .. ": width of line " .. i)
    end
  end

  local function format(lines, opts, label)
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local okf, err = tf.format_table_at_cursor(buf, opts or {})
    eq(okf, true, (label or "") .. " format ok (" .. tostring(err) .. ")")
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  config.setup({})

  -- the reported table: escaped pipes inside code spans
  local pipe = bs .. "|"
  local reported = {
    "| Syntax | Bedeutung | Beispiel |",
    "|---|---|---|",
    "| `a "
      .. pipe
      .. " b` | Pipe: stdout von `a` wird stdin von `b` | `npx vitest run "
      .. pipe
      .. " more` |",
    "| `> datei` | stdout in Datei schreiben (überschreibt) | `ls > liste.txt` |",
    "| `2>&1` | stderr in den stdout-Kanal umleiten | `cmd 2>&1 " .. pipe .. " more` |",
    "| `"
      .. pipe
      .. pipe
      .. "` | nächster Befehl nur bei Fehler | `test "
      .. pipe
      .. pipe
      .. " echo kaputt` |",
    "| `cd ..` | Eine Ebene hoch | |",
    "| `*` und `?` | Wildcards für Dateinamen (cmd gibt sie an das Programm weiter) | `ls *.js` |",
  }
  local out = format(reported)
  assert_rectangular(out, "reported table")

  -- default alignment is left: a non-empty cell starts with exactly one space of padding
  local cells = require("lib.nvim.markdown.table")
  for i, l in ipairs(out) do
    if i ~= 2 then
      local _, ranges = cells.split_cells(l)
      for ci, r in ipairs(ranges) do
        local raw = l:sub(r[1], r[2])
        if vim.trim(raw) ~= "" then
          ok(
            raw:match("^ %S") ~= nil,
            "line " .. i .. " cell " .. ci .. " is left aligned: '" .. raw .. "'"
          )
        end
      end
    end
  end
  ok(out[2]:match("^|%-+|%-+|%-+|$") ~= nil, "separator is plain dashes, no alignment colons")

  -- the formatted result is stable (formatting twice changes nothing)
  eq(table.concat(format(out), "\n"), table.concat(out, "\n"), "format is idempotent")

  -- mixed-width content
  local cases = {
    {
      name = "umlauts",
      "| Größe | Äpfel | ß |",
      "|---|---|---|",
      "| äöüß | x | Straße |",
      "| a | übergroß | |",
    },
    {
      name = "cjk and emoji",
      "| 名前 | 説明 | e |",
      "|---|---|---|",
      "| 日本語のテキスト | ok | 🚀 rocket |",
      "| a | 全角ｱｲｳ | ✅ |",
    },
    {
      name = "empty cells and ragged rows",
      "| A | B | C |",
      "|---|---|---|",
      "| | | |",
      "| only one |",
      "| a | b | c | d |",
    },
    {
      name = "escaped pipes",
      "| p | q |",
      "|---|---|",
      "| a " .. pipe .. " b | " .. pipe .. pipe .. " |",
      "| `x " .. pipe .. " y` | z |",
    },
    {
      name = "indented",
      "  | a | b |",
      "  |---|---|",
      "  | longer cell | x |",
    },
    {
      name = "alignment colons in the source",
      "| L | C | R |",
      "|:--|:-:|--:|",
      "| aaaa | bbbbbbb | c |",
    },
  }
  for _, c in ipairs(cases) do
    local o = format(vim.list_slice(c), nil, c.name)
    -- ragged / no-outer-pipe sources may legitimately gain a pipe; only rectangularity matters
    assert_rectangular(o, c.name)
    eq(table.concat(format(o), "\n"), table.concat(o, "\n"), c.name .. ": idempotent")
  end

  -- explicit alignment still wins, and is rectangular too
  for _, a in ipairs({ "left", "center", "right" }) do
    assert_rectangular(format(reported, { header_align = a, entry_align = a }), "explicit " .. a)
  end

  -- config default flipped back to center is honoured
  config.setup({ table = { header_align = "center", entry_align = "center" } })
  local centered = format({ "| Name | Age |", "|---|---|", "| Bob | 3 |", "| Alexandra | 40 |" })
  assert_rectangular(centered, "configured center")
  ok(centered[3]:match("^|  +Bob +|") ~= nil, "configured center pads both sides")
  config.setup({})
end
