-- TESTS/table_truncate_spec.lua -- display-only truncation of over-wide table cells
-- (core.table_truncate): conceal ranges are computed so every cell of a truncated
-- column shows the same number of columns; the buffer text is never changed.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local tt = require("markdown.core.table_truncate")
  local lib = require("lib.nvim.markdown.table")

  local SRC = {
    "| Syntax | Meaning | Example |",
    "|---|---|---|",
    "| `a` | stdout of the left command becomes stdin of the right one | `ls` |",
    "| `b` | short | `npx vitest run --reporter verbose --bail` |",
  }

  --- Shown text of `line` after applying its conceal ranges.
  local function shown(line, marks)
    local out, pos = {}, 1
    local ms = vim.deepcopy(marks or {})
    table.sort(ms, function(a, b) return a.s < b.s end)
    for _, m in ipairs(ms) do
      out[#out + 1] = line:sub(pos, m.s - 1) .. m.text
      pos = m.e + 1
    end
    out[#out + 1] = line:sub(pos)
    return table.concat(out)
  end

  local lines = lib.format_lines(SRC)
  local marks = tt.compute(lines, { max = 20, marker = "…" })

  -- every row of the table is shown with the same width
  local width = vim.fn.strdisplaywidth(shown(lines[1], marks[1]))
  for i = 1, #lines do
    eq(
      vim.fn.strdisplaywidth(shown(lines[i], marks[i])),
      width,
      "row " .. i .. " has the common width"
    )
  end
  ok(
    shown(lines[3], marks[3]):find("left …", 1, true) ~= nil,
    "a long cell is cut with the marker"
  )
  ok(shown(lines[4], marks[4]):find("--r…", 1, true) ~= nil, "the code span is cut, too")
  for _, m in ipairs(marks[1]) do
    eq(m.text, "", "the header only loses padding, never text")
  end
  eq(lines[3], lib.format_lines(SRC)[3], "compute never changes the text")

  -- nothing wider than max -> no marks
  eq(next(tt.compute(lines, { max = 100 })), nil, "no marks when everything fits")

  -- the right-aligned / compact separator keeps its colon
  local long = string.rep("w", 50)
  local aligned = {
    "| A | " .. long .. " |",
    "| --- | " .. string.rep("-", 49) .. ": |",
    "| x | " .. long .. " |",
  }
  local m2 = tt.compute(aligned, { max = 10 })
  local sep = shown(aligned[2], m2[2])
  ok(sep:find("-: |$") ~= nil, "separator colon survives")
  eq(
    vim.fn.strdisplaywidth(sep) - 2, -- first column is "---" vs "A"
    vim.fn.strdisplaywidth(shown(aligned[1], m2[1])),
    "separator width follows the row"
  )

  -- render applies extmarks and does not touch the buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local before = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  require("markdown.config").setup({ table = { truncate = { max = 20 } } })
  ok(tt.render(buf) > 0, "render places conceal extmarks")
  local ns = vim.api.nvim_create_namespace("markdown_table_truncate")
  local ext = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  ok(#ext > 0 and ext[1][4].conceal ~= nil, "extmarks carry a conceal")
  eq(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
    before,
    "buffer text unchanged"
  )

  -- toggle sets conceallevel while on and restores it
  vim.wo.conceallevel = 0
  eq(tt.toggle(buf), true, "toggle turns on")
  eq(vim.wo.conceallevel, 2, "conceallevel raised to 2")
  eq(tt.toggle(buf), false, "toggle turns off")
  eq(vim.wo.conceallevel, 0, "conceallevel restored")
  eq(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}), 0, "extmarks cleared")
  require("markdown.config").setup({})
end
