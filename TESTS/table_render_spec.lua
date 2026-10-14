-- TESTS/table_render_spec.lua -- virtual grid rendering of tables (core.table_render):
-- compact columns, cells wrapped to the window width, the cursor row shown as text;
-- the buffer text is never changed.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local tr = require("markdown.core.table_render")

  local function text(chunks)
    local t = {}
    for _, c in ipairs(chunks) do
      t[#t + 1] = c[1]
    end
    return table.concat(t)
  end

  local function shown_lines(src, avail, opts)
    local model = tr.layout(src, vim.tbl_extend("force", { avail = avail }, opts or {}))
    local style = tr.style({}, model)
    local out = { text(tr.border(model, "top", style)) }
    for i = 1, #model.rows do
      for _, l in ipairs(tr.row_lines(model, i, style)) do
        out[#out + 1] = text(l)
      end
    end
    out[#out + 1] = text(tr.border(model, "bottom", style))
    return out, model
  end

  local LONG = string.rep("word ", 30)
  local SRC = {
    "| Name                  | Description |",
    "| --------------------- | ----------- |",
    "| a                     | " .. LONG .. " |",
    "| `code` and more       | short       |",
  }

  -- no avail: natural widths, no padding left over from the source
  local lines, model = shown_lines(SRC, nil)
  eq(model.wrapped, false, "nothing wraps without a width")
  eq(
    model.widths[1],
    vim.fn.strdisplaywidth("`code` and more"),
    "column 1 is as wide as its longest cell"
  )
  for _, l in ipairs(lines) do
    eq(vim.fn.strdisplaywidth(l), model.width, "every line has the table width")
  end

  -- fits: same as natural
  local _, roomy = shown_lines(SRC, 1000)
  eq(roomy.wrapped, false, "a wide window does not wrap")

  -- too narrow: wrapped to the width, every line exactly that wide
  for _, avail in ipairs({ 80, 60, 40 }) do
    local out, m = shown_lines(SRC, avail)
    eq(m.wrapped, true, "wraps at " .. avail)
    ok(m.width <= avail, "fits " .. avail)
    for _, l in ipairs(out) do
      eq(vim.fn.strdisplaywidth(l), m.width, "line width at " .. avail)
    end
    ok(#out > #SRC + 2, "continuation lines were added at " .. avail)
  end

  -- short columns keep their words whole
  local _, m80 = shown_lines(SRC, 60)
  ok(m80.widths[1] >= #"and more" - 2, "column 1 not squeezed mid-word")

  -- alignment from the separator row
  local aligned = {
    "| L | C | R |",
    "| :-- | :-: | --: |",
    "| a | b | c |",
    "| aaaaa | bbbbb | ccccc |",
  }
  local out = shown_lines(aligned, nil)
  ok(out[4]:find("│ a     │   b   │     c │", 1, true), "left / center / right")

  -- <br> forces a line break; \| is a literal pipe
  local br = { "| A | B |", "| - | - |", "| x<br>y | a \\| b |" }
  local out_br, m_br = shown_lines(br, nil)
  eq(m_br.rows[3].height, 2, "<br> makes two lines")
  ok(table.concat(out_br, "\n"):find("a | b", 1, true), "escaped pipe shown as pipe")

  -- ragged row: missing cells are empty, no error
  local ragged = { "| A | B | C |", "| - | - | - |", "| only |" }
  local _, m_r = shown_lines(ragged, nil)
  eq(m_r.n, 3, "column count from the widest row")

  -- impossible: more columns than the width allows -> nil, never an error
  eq(tr.layout(SRC, { avail = 6 }), nil, "no layout when it cannot fit")

  -- row separators: auto only when a row wraps
  local st_auto = tr.style({}, { wrapped = false })
  eq(st_auto.row_separator, false, "no separator when nothing wraps")
  eq(tr.style({}, { wrapped = true }).row_separator, true, "separator when a row wraps")
  eq(
    tr.style({ row_separator = false }, { wrapped = true }).row_separator,
    false,
    "explicit false wins"
  )

  -- ───────────── buffer ─────────────
  local ns = vim.api.nvim_create_namespace("markdown_table_render")
  local buf = H.scratch("markdown")
  local doc = {
    "# T",
    "",
    "| A | B |",
    "| - | - |",
    "| 1 | " .. LONG .. " |",
    "",
    "```",
    "| x | y |",
    "| - | - |",
    "| 1 | 2 |",
    "```",
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, doc)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  tr.enable(buf)
  ok(tr.is_enabled(buf), "enabled")
  ok(vim.wo.conceallevel >= 2, "conceallevel raised")

  local function marks() return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end
  local function concealed_rows()
    local rows = {}
    for _, m in ipairs(marks()) do
      if m[4].conceal then rows[m[2] + 1] = true end
    end
    return rows
  end

  local rows = concealed_rows()
  ok(rows[3] and rows[4] and rows[5], "all three table rows are concealed")
  ok(not rows[8] and not rows[9] and not rows[10], "a table inside a fenced block is left alone")
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[5], doc[5], "the text is not touched")

  -- cursor row shows its real text
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  rows = concealed_rows()
  ok(rows[3] and rows[4] and not rows[5], "the cursor row is not concealed")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  ok(concealed_rows()[5], "concealed again after the cursor left")

  -- truncate and render exclude each other
  local tt = require("markdown.core.table_truncate")
  tt.enable(buf)
  ok(not tr.is_enabled(buf), "enabling truncate switches render off")
  ok(tt.is_enabled(buf), "truncate is on")
  tr.enable(buf)
  ok(not tt.is_enabled(buf), "enabling render switches truncate off")

  -- narrower window -> more virtual lines
  local function vline_count()
    local n = 0
    for _, m in ipairs(marks()) do
      n = n + #(m[4].virt_lines or {})
    end
    return n
  end
  local wide = vline_count()
  vim.cmd("vsplit")
  vim.cmd("vertical resize 30")
  tr.render(buf)
  ok(vline_count() > wide, "a narrower window wraps into more virtual lines")
  vim.cmd("only")

  tr.disable(buf)
  eq(#marks(), 0, "disable removes every extmark")
  ok(not tr.is_enabled(buf), "disabled")
  eq(tr.enable(0), nil, "enable(0) means the current buffer")
  ok(tr.is_enabled(buf), "enable(0) enabled the current buffer")
  tr.disable(0)
end
