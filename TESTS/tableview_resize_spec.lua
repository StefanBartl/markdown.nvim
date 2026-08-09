-- TESTS/tableview_resize_spec.lua — interactive TableView column resize
-- (<M-Left>/<M-Right>, <M-h>/<M-l>), row reordering (<M-Up>/<M-Down>,
-- <M-k>/<M-j>), and write-back (`:w`): all buffer-local to the floating
-- preview, Normal mode only.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api
  local renderer = require("markdown.tableview.renderer")
  local parser = require("markdown.tableview.parser")

  local function mt2col()
    return {
      header = { cells = { { content = "Name" }, { content = "Age" } } },
      rows = {
        { cells = { { content = "Alice" }, { content = "30" } } },
        { cells = { { content = "Bob" }, { content = "5" } } },
      },
      alignments = {},
    }
  end

  -- ── keymaps are buffer-local to the view buffer, Normal mode only ────────
  do
    renderer.render_markdowntable(mt2col(), { floating = true })

    local lhss =
      { "<M-Left>", "<M-Right>", "<M-h>", "<M-l>", "<M-Up>", "<M-Down>", "<M-k>", "<M-j>" }
    for _, lhs in ipairs(lhss) do
      local m = vim.fn.maparg(lhs, "n", false, true)
      ok(
        m and m.buffer == 1,
        ("%s is bound buffer-locally in Normal mode on the preview buffer"):format(lhs)
      )
    end

    local other = api.nvim_create_buf(false, true)
    for _, m in ipairs(api.nvim_buf_get_keymap(other, "n")) do
      ok(m.lhs ~= "<M-Left>", "resize keymaps do not leak into unrelated buffers")
    end

    renderer.close_view()
  end

  -- ── widen/narrow the column under the cursor ──────────────────────────────
  do
    renderer.render_markdowntable(mt2col(), { floating = true, style = "markdown" })
    local win = api.nvim_get_current_win()
    local function lines() return api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false) end

    local before = lines()
    eq(before[1], "| Name  | Age |", "initial header row at natural width")

    api.nvim_win_set_cursor(win, { 1, 3 }) -- inside "Name"
    renderer.resize_current_column(1)
    renderer.resize_current_column(1)
    local widened = lines()
    eq(widened[1], "| Name    | Age |", "resize_current_column(1) x2 widens column 1 by 2")
    eq(widened[3], "| Alice   | 30  |", "widened padding applies to every row in the column")

    -- Narrowing floors at the natural content width (never truncates/misaligns).
    renderer.resize_current_column(-1)
    renderer.resize_current_column(-1)
    renderer.resize_current_column(-1) -- one extra past the floor: no-op
    local narrowed = lines()
    eq(narrowed[1], before[1], "narrowing back down floors at the natural width")

    renderer.close_view()
  end

  -- ── move the row under the cursor up/down (swap with the neighbor) ───────
  do
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "| Name  | Age |",
      "| ----- | --- |",
      "| Alice | 30  |",
      "| Bob   | 5   |",
      "| Carol | 40  |",
    })
    local mt = parser.get_tables(buf)[1]
    renderer.render_markdowntable(mt, { floating = true, style = "markdown" })
    local win = api.nvim_get_current_win()
    local function lines() return api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false) end

    eq(#lines(), 5, "initial: header + separator + 3 data rows (row count unaffected by moving)")

    -- Move "Bob" (row 2) up: swaps with Alice.
    for i, l in ipairs(lines()) do
      if l:find("Bob") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.move_current_row(-1)
    local after_up = lines()
    eq(#after_up, 5, "move_current_row never changes the row count")
    ok(after_up[3]:find("Bob") ~= nil, "Bob moved into row 1's slot")
    ok(after_up[4]:find("Alice") ~= nil, "Alice swapped down into Bob's old slot")
    ok(after_up[5]:find("Carol") ~= nil, "Carol (untouched row) stays put")

    -- Move Bob (now row 1) back down: undoes the swap.
    for i, l in ipairs(lines()) do
      if l:find("Bob") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.move_current_row(1)
    local after_down = lines()
    ok(after_down[3]:find("Alice") ~= nil, "swap undone: Alice back in row 1")
    ok(after_down[4]:find("Bob") ~= nil, "swap undone: Bob back in row 2")

    -- Header row: nothing to swap it against.
    api.nvim_win_set_cursor(win, { 1, 2 })
    renderer.move_current_row(-1)
    renderer.move_current_row(1)
    ok(lines()[1]:find("Name") ~= nil, "move_current_row on the header row is a no-op")

    -- Edges: first data row can't move up past the header; last can't move
    -- down past the end.
    local before_edge = table.concat(lines(), "\n")
    for i, l in ipairs(lines()) do
      if l:find("Alice") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.move_current_row(-1)
    for i, l in ipairs(lines()) do
      if l:find("Carol") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.move_current_row(1)
    eq(table.concat(lines(), "\n"), before_edge, "moving past either edge is a no-op")

    -- Cursor on the separator line: no-op (no cell there).
    local before_sep = table.concat(lines(), "\n")
    api.nvim_win_set_cursor(win, { 2, 2 })
    renderer.resize_current_column(1)
    renderer.move_current_row(1)
    eq(table.concat(lines(), "\n"), before_sep, "resize/move ops on the separator line are no-ops")

    renderer.close_view()
  end

  -- ── box style: same operations, box-drawing grid ──────────────────────────
  do
    renderer.render_markdowntable(mt2col(), { floating = true, style = "box" })
    local win = api.nvim_get_current_win()
    local function lines() return api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false) end

    -- top border(1), header(2), header rule(3), Alice(4), rule(5), Bob(6), bottom(7)
    eq(#lines(), 7, "box style: full grid line count")
    api.nvim_win_set_cursor(win, { 2, 3 }) -- header row, inside "Name"
    renderer.resize_current_column(1)
    ok(
      lines()[2]:find("Name") ~= nil and #lines()[2] > #"│ Name  │ Age │",
      "box style: header widens too"
    )

    for i, l in ipairs(lines()) do
      if l:find("Bob") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.move_current_row(-1)
    eq(#lines(), 7, "box style: moving a row keeps the same grid line count")
    ok(lines()[4]:find("Bob") ~= nil, "box style: Bob swapped into Alice's row slot")
    ok(lines()[6]:find("Alice") ~= nil, "box style: Alice swapped into Bob's row slot")

    renderer.close_view()
  end

  -- ── stacked multi-table view: per-table column overrides are independent ─
  do
    local mt_a = {
      header = { cells = { { content = "A" }, { content = "B" } } },
      rows = { { cells = { { content = "1" }, { content = "2" } } } },
      alignments = {},
      start_line = 1,
    }
    local mt_b = {
      header = { cells = { { content = "X" }, { content = "Y" } } },
      rows = { { cells = { { content = "foo" }, { content = "bar" } } } },
      alignments = {},
      start_line = 5,
    }
    renderer.render_tables({ mt_a, mt_b }, { floating = true, style = "markdown" })
    local win = api.nvim_get_current_win()
    local function lines() return api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false) end

    -- Widen table A's first column only.
    for i, l in ipairs(lines()) do
      if l:find("| A |") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.resize_current_column(1)

    local after = lines()
    local a_header, b_header
    for _, l in ipairs(after) do
      if l:find("A ") and l:find("|") then a_header = l end
      if l:find("X ") and l:find("|") then b_header = l end
    end
    ok(a_header:find("| A  |") ~= nil, "table A's column widened")
    ok(b_header == "| X   | Y   |", "table B's columns untouched by table A's resize")

    -- Cursor on a multi-table label line: no-op, doesn't error.
    api.nvim_win_set_cursor(win, { 1, 2 })
    renderer.resize_current_column(1)
    renderer.move_current_row(1)
    ok(true, "resize/move ops on a stacked-view label line are a safe no-op")

    renderer.close_view()
  end

  -- ── write-back: `:w` in the popup persists row reorders to the source ────
  do
    -- Source buffer case: mt.bufnr is tagged by parser.get_tables.
    local src = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(src, "tableview_writeback_src.md")
    api.nvim_buf_set_lines(src, 0, -1, false, {
      "before",
      "| Name  | Age |",
      "| ----- | --- |",
      "| Alice | 30  |",
      "| Bob   | 5   |",
      "after",
    })
    local mt = parser.get_tables(src)[1]
    eq(mt.bufnr, src, "parser.get_tables tags each table with its source bufnr")

    renderer.render_markdowntable(mt, { floating = true, style = "markdown" })
    local win = api.nvim_get_current_win()
    local function lines() return api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false) end

    -- Swap Alice/Bob, then widen a column (widening must NOT be written back).
    for i, l in ipairs(lines()) do
      if l:find("Bob") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.move_current_row(-1)
    api.nvim_win_set_cursor(win, { 1, 2 })
    renderer.resize_current_column(1)

    vim.cmd("write")

    local src_lines = api.nvim_buf_get_lines(src, 0, -1, false)
    eq(src_lines[1], "before", "write_back: line before the table is untouched")
    eq(src_lines[#src_lines], "after", "write_back: line after the table is untouched")
    ok(
      table.concat(src_lines, "\n"):find("Bob") ~= nil
        and table.concat(src_lines, "\n"):find("Alice") ~= nil,
      "write_back: both rows present in the source"
    )
    local bob_line, alice_line
    for i, l in ipairs(src_lines) do
      if l:find("Bob") then bob_line = i end
      if l:find("Alice") then alice_line = i end
    end
    ok(
      bob_line < alice_line,
      "write_back: reordered rows (Bob before Alice) persisted to the source buffer"
    )
    eq(
      src_lines[2],
      "| Name  | Age |",
      "write_back: writes NATURAL widths, ignoring the popup's column-widen override"
    )
    ok(
      not vim.bo[api.nvim_win_get_buf(win)].modified,
      "write_back: popup buffer's 'modified' flag is cleared after :w"
    )

    renderer.close_view()

    -- File-on-disk case: mt.source, no live buffer for that path.
    local path = vim.fn.tempname() .. ".md"
    vim.fn.writefile({
      "intro",
      "| X   | Y   |",
      "| --- | --- |",
      "| foo | bar |",
      "| baz | qux |",
      "outro",
    }, path)

    local file_tables = parser.get_tables_from_file(path)
    local fmt = file_tables[1]
    eq(fmt.source, path, "parser.get_tables_from_file tags .source (no .bufnr)")
    ok(fmt.bufnr == nil, "a file-sourced table has no bufnr")

    renderer.render_markdowntable(fmt, { floating = true, style = "markdown" })
    local fwin = api.nvim_get_current_win()
    local function flines() return api.nvim_buf_get_lines(api.nvim_win_get_buf(fwin), 0, -1, false) end
    for i, l in ipairs(flines()) do
      if l:find("baz") then api.nvim_win_set_cursor(fwin, { i, 2 }) end
    end
    renderer.move_current_row(-1) -- swap baz/foo

    vim.cmd("write")

    local written = vim.fn.readfile(path)
    eq(written[1], "intro", "write_back (file): line before the table is untouched")
    eq(written[#written], "outro", "write_back (file): line after the table is untouched")
    local baz_line, foo_line
    for i, l in ipairs(written) do
      if l:find("baz") then baz_line = i end
      if l:find("foo") then foo_line = i end
    end
    ok(baz_line < foo_line, "write_back (file): reordered rows persisted directly to disk")

    renderer.close_view()
    os.remove(path)
  end
end
