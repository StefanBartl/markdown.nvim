-- TESTS/tableview_resize_spec.lua — interactive TableView column resize
-- (<M-Left>/<M-Right>) and row insert/remove (<M-Up>/<M-Down>): buffer-local
-- to the floating preview, Normal mode only.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api
  local renderer = require("markdown.tableview.renderer")

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

    for _, lhs in ipairs({ "<M-Left>", "<M-Right>", "<M-Up>", "<M-Down>" }) do
      local m = vim.fn.maparg(lhs, "n", false, true)
      ok(m and m.buffer == 1, ("%s is bound buffer-locally in Normal mode on the preview buffer"):format(lhs))
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

  -- ── add / remove a row under the cursor ───────────────────────────────────
  do
    renderer.render_markdowntable(mt2col(), { floating = true, style = "markdown" })
    local win = api.nvim_get_current_win()
    local function lines() return api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false) end

    eq(#lines(), 4, "initial: header + separator + 2 data rows")

    -- Cursor on "Alice" (row_idx=1): insert a row directly after it.
    for i, l in ipairs(lines()) do
      if l:find("Alice") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.resize_current_row(1)
    local after_add = lines()
    eq(#after_add, 5, "resize_current_row(1) inserts one blank row")
    ok(after_add[4]:match("^|%s*|%s*|$"), "the inserted row is blank")
    ok(after_add[3]:find("Alice") ~= nil, "inserted row goes AFTER the cursor row, not before")
    ok(after_add[5]:find("Bob") ~= nil, "rows after the insertion point are preserved")

    -- Remove that same blank row.
    for i, l in ipairs(lines()) do
      if l:match("^|%s*|%s*|$") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.resize_current_row(-1)
    eq(#lines(), 4, "resize_current_row(-1) removes the row under the cursor")

    -- Header row cannot be removed via <M-Down>.
    api.nvim_win_set_cursor(win, { 1, 2 })
    renderer.resize_current_row(-1)
    eq(#lines(), 4, "resize_current_row(-1) on the header row is a no-op")

    -- Cursor on the separator line: both ops are no-ops (no cell there).
    local before_sep = table.concat(lines(), "\n")
    api.nvim_win_set_cursor(win, { 2, 2 })
    renderer.resize_current_column(1)
    renderer.resize_current_row(1)
    eq(table.concat(lines(), "\n"), before_sep, "resize ops on the separator line are no-ops")

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
    ok(lines()[2]:find("Name") ~= nil and #lines()[2] > #("│ Name  │ Age │"), "box style: header widens too")

    for i, l in ipairs(lines()) do
      if l:find("Bob") then api.nvim_win_set_cursor(win, { i, 2 }) end
    end
    renderer.resize_current_row(-1)
    eq(#lines(), 5, "box style: removing the last data row also drops its trailing rule")
    ok(not lines()[#lines()]:find("Bob"), "Bob's row is gone")

    renderer.close_view()
  end

  -- ── stacked multi-table view: per-table column overrides are independent ─
  do
    local mt_a = {
      header = { cells = { { content = "A" }, { content = "B" } } },
      rows = { { cells = { { content = "1" }, { content = "2" } } } },
      alignments = {}, start_line = 1,
    }
    local mt_b = {
      header = { cells = { { content = "X" }, { content = "Y" } } },
      rows = { { cells = { { content = "foo" }, { content = "bar" } } } },
      alignments = {}, start_line = 5,
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
    renderer.resize_current_row(1)
    ok(true, "resize ops on a stacked-view label line are a safe no-op")

    renderer.close_view()
  end
end
