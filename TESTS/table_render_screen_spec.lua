-- TESTS/table_render_screen_spec.lua -- the table grid on a REAL screen: an embedded Neovim
-- (testing.rpc) draws it and the spec reads the cells. Covers what the pure specs cannot: no blank
-- rows between table rows with `wrap` on, the cursor row, indent, restore of `conceallevel` in
-- splits, fences, the event wiring (edit / resize / wipeout), the top border of a line-1 table in
-- a split that was not at the top, after a buffer switch and after zz/zt (and <C-e> hiding it
-- until the next cursor move), and the config checks.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok

  local function root_of(file, up)
    local f = vim.api.nvim_get_runtime_file(file, false)[1]
    assert(f, "not on the runtimepath: " .. file)
    f = vim.fs.normalize(f)
    for _ = 1, up do
      f = vim.fs.dirname(f)
    end
    return f
  end
  local rpc = require("testing.rpc")
  local RTP = {
    root_of("lua/markdown/core/table_render.lua", 4),
    root_of("lua/lib/nvim", 3),
    root_of("lua/testing/rpc/init.lua", 4),
  }

  local function spawn()
    local child, err = rpc.spawn({ guard = false, rtp_prepend = RTP })
    assert(child, err)
    return child
  end

  local LONG = string.rep("word ", 30)
  local DOC = {
    "# T",
    "",
    "| Name | Description | Z |",
    "| --- | --- | --- |",
    "| a | " .. LONG .. " | q |",
    "| `code` and more | short | r |",
    "| b | c | d |",
    "",
    "after text",
  }

  ---@param child table
  ---@param lines string[]
  ---@param setup? string  # lua run before the render is enabled
  local function load(child, lines, setup)
    child.lua(
      [[
      local lines, setup = ...
      -- a clean editor for every case: one window, a new buffer, default config and size
      vim.cmd("only")
      local old = vim.api.nvim_get_current_buf()
      pcall(require("markdown.core.table_render").disable, old)
      vim.cmd("silent! enew!")
      vim.cmd("silent! bwipeout! " .. old)
      vim.o.columns, vim.o.lines = 80, 24
      require("markdown.config").setup({})
      vim.o.swapfile = false
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.bo.filetype = "markdown"
      vim.wo.wrap = true
      if setup ~= vim.NIL then loadstring(setup)() end
      require("markdown.core.table_render").enable(0)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    ]],
      lines,
      setup
    )
    child.settle(500)
  end

  ---@param child table
  ---@return string[]
  local function screen(child)
    local s = child.screen().lines
    local out = {}
    for i, l in ipairs(s) do
      out[i] = (l:gsub("%s+$", ""))
    end
    return out
  end

  local function is_grid(l)
    local t = vim.trim(l)
    for _, p in ipairs({ "│", "┌", "├", "└", "╭", "|", "+" }) do
      if vim.startswith(t, p) then return true end
    end
    return false
  end
  ---@param l string
  ---@param n integer  # characters
  local function head(l, n) return vim.fn.strcharpart(l, 0, n) end

  -- ───────────── A: no blank rows between the table rows with wrap on ─────────────
  local c = spawn()
  load(c, DOC)
  local sc = screen(c)
  eq(sc[1], "# T", "text above the table")
  eq(head(sc[3], 1), "┌", "top border right below the blank line")
  local bottom
  for i = 3, #sc do
    if sc[i]:find("^└") then
      bottom = i
      break
    end
  end
  ok(bottom, "bottom border is on the screen")
  for i = 3, bottom do
    ok(is_grid(sc[i]), "row " .. i .. " of the grid is not blank: '" .. sc[i] .. "'")
  end
  eq(sc[bottom + 1], "", "one blank line after the table")
  eq(sc[bottom + 2], "after text", "the text after the table follows directly")
  eq(c.lua_get("vim.api.nvim_buf_get_lines(0, 4, 5, false)[1]"), DOC[5], "the file text is intact")

  -- ───────────── D: separator / border below the cursor row stay ─────────────
  c.feed("6G") -- the "`code` and more" row: raw text, the rest stays a grid
  c.settle(500)
  sc = screen(c)
  local raw_at
  for i, l in ipairs(sc) do
    if l == "| `code` and more | short | r |" then raw_at = i end
  end
  ok(raw_at, "the cursor row shows its text")
  ok(sc[raw_at - 1]:find("^├"), "separator above the cursor row")
  ok(sc[raw_at + 1]:find("^├"), "separator below the cursor row")
  ok(sc[raw_at + 3]:find("^└"), "bottom border below the last row")
  eq(select(2, table.concat(sc, "\n"):gsub("┌", "")), 1, "the top border is drawn once")
  -- moving away and back leaves no stale copy of the grid behind
  c.feed("1G")
  c.settle(500)
  c.feed("7G")
  c.settle(500)
  sc = screen(c)
  eq(select(2, table.concat(sc, "\n"):gsub("┌", "")), 1, "still one top border after moves")
  eq(select(2, table.concat(sc, "\n"):gsub("└", "")), 1, "still one bottom border after moves")

  -- cursor = "table": the whole table is text
  c.lua("require('markdown.core.table_render').disable(0)")
  load(c, DOC, "vim.g.x = 1")
  c.lua([[
    package.loaded["markdown.config"] = nil
    require("markdown.config").setup({ table = { render = { cursor = "table" } } })
    require("markdown.core.table_render").render(0, true)
  ]])
  c.feed("5G")
  c.settle(500)
  sc = screen(c)
  ok(
    table.concat(sc, "\n"):find("| --- | --- | --- |", 1, true),
    "cursor=table: separator row is text"
  )
  ok(
    not table.concat(sc, "\n"):find("│", 1, true),
    "cursor=table: no rendered rows while the cursor is in it"
  )

  -- ───────────── B: indent ─────────────
  local indented = {
    "text",
    "",
    "   | A | B |",
    "   | - | - |",
    "   | " .. LONG .. " | y |",
    "",
    "end",
  }
  load(c, indented)
  sc = screen(c)
  eq(head(sc[3], 4), "   ┌", "the top border is indented like the table")
  for i = 3, #sc do
    if is_grid(sc[i]) then ok(vim.fn.strdisplaywidth(sc[i]) <= 80, "fits the window: " .. sc[i]) end
  end
  local widest = 0
  for i = 3, 12 do
    widest = math.max(widest, vim.fn.strdisplaywidth(sc[i]))
  end
  ok(widest <= 80, "the indent is part of the width budget")
  -- a tab indent counts as what it displays as
  load(c, { "x", "", "\t| A | B |", "\t| - | - |", "\t| " .. LONG .. " | y |", "", "end" })
  sc = screen(c)
  local tab_w = c.lua_get("vim.o.tabstop")
  local top
  for _, l in ipairs(sc) do
    if l:find("┌", 1, true) then top = l end
  end
  ok(top, "tab: a top border exists")
  eq(#top:match("^ *"), tab_w, "tab: indent is tabstop wide")
  for _, l in ipairs(sc) do
    ok(vim.fn.strdisplaywidth(l) <= 80, "tab: fits the window")
  end

  -- ───────────── C: table on buffer line 1 ─────────────
  load(c, { "| A | B |", "| - | - |", "| 1 | 2 |", "", "end" })
  sc = screen(c)
  ok(c.lua_get("require('markdown.core.table_render').is_enabled(0)"), "enabled")
  ok(table.concat(sc, "\n"):find("│ 1 │ 2 │", 1, true), "line 1 table: rows are drawn")
  -- the cursor sits in the first row (raw text): the top border is above it, on screen line 1
  eq(head(sc[1], 1), "┌", "line 1 table: the top border is shown above the text row")
  eq(sc[2], "| A | B |", "line 1 table: the cursor row shows its text")
  c.feed("j")
  c.settle(300)
  sc = screen(c)
  eq(head(sc[1], 1), "┌", "line 1 table: the border stays when the cursor moves on")
  c.feed("gg")
  c.settle(300)
  eq(head(screen(c)[1], 1), "┌", "line 1 table: and when it comes back")
  ok(table.concat(sc, "\n"):find("└", 1, true), "line 1 table: bottom border is drawn")
  -- a buffer that is only a table still shows it (nothing else to hang the grid on)
  load(c, { "| A | B |", "| - | - |", "| 1 | 2 |" })
  sc = screen(c)
  ok(table.concat(sc, "\n"):find("│ 1 │ 2 │", 1, true), "only-table buffer: rows drawn")
  ok(table.concat(sc, "\n"):find("└", 1, true), "only-table buffer: bottom border drawn")

  -- ───────────── E: conceallevel in splits ─────────────
  load(c, DOC)
  eq(c.lua_get("vim.wo.conceallevel"), 2, "render raised conceallevel")
  c.cmd("split")
  eq(c.lua_get("vim.wo.conceallevel"), 2, "the split shows the same buffer")
  c.cmd("vsplit")
  c.lua("require('markdown.core.table_render').disable(0)")
  local levels = c.lua_get(
    "(function() local t = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do t[#t+1] = vim.wo[w].conceallevel end return t end)()"
  )
  eq(#levels, 3, "three windows")
  for i, cl in ipairs(levels) do
    eq(cl, 0, "window " .. i .. " has its conceallevel back after render off")
  end
  -- a window that moves to another buffer gets its level back too
  load(c, DOC)
  c.cmd("only")
  c.cmd("enew")
  eq(c.lua_get("vim.wo.conceallevel"), 0, "a window on another buffer is not left concealed")

  -- table_truncate has the same pattern
  c.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "| A | B |", "| - | - |", "| 1 | 2 |" })
    vim.bo.filetype = "markdown"
    local b = vim.api.nvim_get_current_buf()
    require("markdown.core.table_truncate").enable(b)
    vim.g.cl_after_enable = vim.wo.conceallevel
    vim.cmd("split")
    require("markdown.core.table_truncate").disable(b)
  ]])
  local tl = c.lua_get(
    "(function() local t = {} for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do t[#t+1] = vim.wo[w].conceallevel end return t end)()"
  )
  eq(c.lua_get("vim.g.cl_after_enable"), 2, "truncate raised conceallevel")
  eq(tl[1], 0, "truncate: first window restored")
  eq(tl[2], 0, "truncate: split window restored")

  -- ───────────── F: fences ─────────────
  load(c, {
    "```lua",
    "| x | y |",
    "| - | - |",
    "| 1 | 2 |",
    "```",
    "",
    "| A | B |",
    "| - | - |",
    "| 7 | 8 |",
    "",
    "end",
  })
  sc = screen(c)
  local joined = table.concat(sc, "\n")
  ok(joined:find("│ 7 │ 8 │", 1, true), "the table after a ```lua block is rendered")
  ok(not joined:find("│ 1 │ 2 │", 1, true), "the table inside the block is not")
  -- an inline ```code``` line does not open a fence
  load(c, {
    "see ```code``` here",
    "",
    "| A | B |",
    "| - | - |",
    "| 7 | 8 |",
    "",
    "end",
  })
  sc = screen(c)
  ok(table.concat(sc, "\n"):find("│ 7 │ 8 │", 1, true), "an inline ``` pair is not a fence")
  -- a ```lua line inside the block does not close it; a longer closer does
  load(c, {
    "````",
    "```lua",
    "| x | y |",
    "| - | - |",
    "| 1 | 2 |",
    "````",
    "",
    "| A | B |",
    "| - | - |",
    "| 7 | 8 |",
  })
  joined = table.concat(screen(c), "\n")
  ok(not joined:find("│ 1 │ 2 │", 1, true), "a shorter inner fence does not close the block")
  ok(joined:find("│ 7 │ 8 │", 1, true), "the table after a four-backtick block is rendered")

  -- ───────────── event wiring: edit, resize, wipeout ─────────────
  load(c, { "x", "", "| A | B |", "| - | - |", "| 1 | 2 |", "", "end" })
  c.feed("5Gwwwiiiiiiiiiiiiiiiiiiii<Esc>") -- edit a cell (the cursor is still in the row)
  c.feed("1G")
  c.cmd("sleep 250m")
  c.settle(500)
  joined = table.concat(screen(c), "\n")
  ok(
    joined:find("│ 1 │ i+2 │") and joined:find("│ A │ B +│"),
    "an edit is laid out again after the debounce"
  )
  -- resize: a narrower window wraps the table
  load(c, DOC)
  local before = table.concat(screen(c), "\n")
  c.cmd("set columns=50")
  c.cmd("sleep 300m")
  c.settle(1000)
  local narrow = table.concat(c.screen().lines, "\n")
  ok(narrow ~= before, "a resize re-lays-out the table")
  for _, l in ipairs(c.screen().lines) do
    if is_grid(l) then
      ok(vim.fn.strdisplaywidth((l:gsub("%s+$", ""))) <= 50, "fits the narrower window")
    end
  end
  -- a plain window resize (the screen size stays) is noticed through WinResized
  load(c, DOC)
  local function word_rows()
    local n = 0
    for _, l in ipairs(c.screen().lines) do
      if l:find("word", 1, true) then n = n + 1 end
    end
    return n
  end
  local rows_before = word_rows()
  c.cmd("vsplit")
  c.cmd("vertical resize 30")
  c.cmd("sleep 300m")
  c.settle(1000)
  ok(word_rows() > rows_before, "a narrower split wraps the cells onto more rows")
  c.cmd("only")
  -- wipeout cleans the state up
  c.lua([[
    local tr = require("markdown.core.table_render")
    local b = vim.api.nvim_get_current_buf()
    vim.cmd("enew")
    vim.cmd("bwipeout! " .. b)
    vim.g.wiped_enabled = tr.is_enabled(b)
  ]])
  eq(c.lua_get("vim.g.wiped_enabled"), false, "a wiped buffer is forgotten")

  -- ───────────── undo / redo leave no stale grid behind ─────────────
  load(c, {
    "x",
    "| a | b |",
    "|---|---|",
    "| 1 | 2 |",
    "",
    "| c | d |",
    "|---|---|",
    "| 3 | 4 |",
    "",
    "end",
  })
  local function tops() return select(2, table.concat(screen(c), "\n"):gsub("┌", "")) end
  eq(tops(), 2, "two tables, two grids")
  c.feed("ggjdG") -- delete both tables and more
  c.feed("u")
  c.feed("<C-r>")
  c.feed("u")
  c.feed("G")
  c.cmd("sleep 250m")
  c.settle(500)
  eq(tops(), 2, "after undo / redo / undo there is one grid per table")
  c.feed("ggjdd") -- one row removed
  c.feed("u")
  c.cmd("sleep 250m")
  c.settle(500)
  eq(tops(), 2, "after deleting a row and undoing it, still one grid per table")

  -- ───────────── layout options on the screen ─────────────
  load(c, DOC, [[require("markdown.config").setup({ table = { render = { border = "ascii" } } })]])
  sc = screen(c)
  eq(head(sc[3], 3), "+--", "border = ascii")
  load(
    c,
    DOC,
    [[require("markdown.config").setup({ table = { render = { border = "rounded", pad = 2 } } })]]
  )
  sc = screen(c)
  eq(head(sc[3], 1), "╭", "border = rounded")
  ok(sc[4]:find("│  Name", 1, true), "pad = 2")
  local SMALL =
    { "x", "", "| A | B |", "| - | - |", "| 1 | 2 |", "| 3 | 4 |", "| 5 | 6 |", "", "end" }
  local function count_seps()
    local n = 0
    for _, l in ipairs(screen(c)) do
      if vim.startswith(l, "├") then n = n + 1 end
    end
    return n
  end
  local function sep_cfg(v)
    return ("require('markdown.config').setup({ table = { render = { row_separator = %s } } })"):format(
      v
    )
  end
  load(c, SMALL)
  eq(count_seps(), 1, "row_separator = auto: only the header separator when nothing wraps")
  load(c, SMALL, sep_cfg("true"))
  eq(count_seps(), 3, "row_separator = true: a separator between the body rows")
  load(c, SMALL, sep_cfg("false"))
  eq(count_seps(), 1, "row_separator = false")
  load(c, DOC, [[require("markdown.config").setup({ table = { render = { max_width = 40 } } })]])
  for _, l in ipairs(screen(c)) do
    if is_grid(l) then ok(vim.fn.strdisplaywidth(l) <= 40, "max_width caps the table: " .. l) end
  end

  -- ───────────── wide characters: no line wider than the table ─────────────
  load(c, {
    "x",
    "",
    "| A | B |",
    "| - | - |",
    "| " .. string.rep("❤️日本語🎉 ", 14) .. " | y |",
    "",
    "end",
  })
  local widths = {}
  for _, l in ipairs(screen(c)) do
    if is_grid(l) then widths[vim.fn.strdisplaywidth(l)] = true end
  end
  eq(vim.tbl_count(widths), 1, "every grid line has the same display width")

  -- ───────────── table on line 1 in a second window that was not at the top ─────────────
  -- Neovim draws the virtual line above buffer line 1 only when the window is scrolled to
  -- `topfill`; sync_topfill has to do that for every window showing the buffer, not only the
  -- current one or the one that was at the top when the row turned into text.
  local LINE1 = { "| A | B |", "| - | - |", "| 1 | 2 |" }
  for i = 1, 80 do
    LINE1[#LINE1 + 1] = "text " .. i
  end
  load(c, LINE1)
  c.cmd("split")
  c.cmd("wincmd =")
  local wins = c.lua_get("vim.api.nvim_tabpage_list_wins(0)") -- top to bottom
  local upper, lower = wins[1], wins[2]
  ---@param win integer
  ---@return integer topline, integer topfill
  local function view(win)
    local v = c.lua_get(
      ("vim.api.nvim_win_call(%d, function() local v = vim.fn.winsaveview() return { v.topline, v.topfill } end)"):format(
        win
      )
    )
    return v[1], v[2]
  end
  ---@param win integer
  ---@return string  # "topline,topfill"
  local function at_top(win) return table.concat({ view(win) }, ",") end
  ---@return integer
  local function tops_on_screen() return select(2, table.concat(screen(c), "\n"):gsub("┌", "")) end
  ---Screen line of the lower window's top border: the last "┌" on the screen.
  ---@return integer|nil
  local function lower_top_border()
    local found
    for i, l in ipairs(screen(c)) do
      if l:find("^┌") then found = i end
    end
    return found
  end
  ---Put the lower window at `lower_keys` and the upper one at `upper_keys`, then run `keys`
  ---in the lower window.
  local function scene(lower_keys, upper_keys, keys)
    c.cmd("wincmd =")
    c.lua(("vim.api.nvim_set_current_win(%d)"):format(lower))
    c.feed(lower_keys)
    c.settle(200)
    c.lua(("vim.api.nvim_set_current_win(%d)"):format(upper))
    c.feed(upper_keys)
    c.settle(200)
    c.lua(("vim.api.nvim_set_current_win(%d)"):format(lower))
    c.feed(keys)
    c.settle(400)
  end
  ok(
    c.lua_get(("vim.api.nvim_win_get_height(%d)"):format(lower)) >= 8,
    "the lower window has room for the table"
  )

  -- 1. the lower window is scrolled down, its own cursor goes to line 1 (the upper one is far away)
  scene("30Gzt", "50G", "gg")
  local wtop, fill = view(lower)
  eq(wtop, 1, "own gg: the lower window is at the top")
  eq(fill, 1, "own gg: the lower window is scrolled to the filler line")
  local at = lower_top_border()
  ok(at and at > 3, "own gg: the lower window shows the top border")
  eq(screen(c)[(at or 0) + 1], "| A | B |", "own gg: the cursor row follows the border")
  -- the same with :1 and with k from further down
  scene("30Gzt", "50G", ":1<CR>")
  eq(select(2, view(lower)), 1, "own :1: scrolled to the filler line")
  scene("30Gzt", "50G", "29k")
  eq(select(2, view(lower)), 1, "own k: scrolled to the filler line")

  -- 2. both cursors on line 1, the lower window comes up from further down
  scene("30Gzt", "gg", "gg")
  eq(select(2, view(upper)), 1, "both on line 1: upper scrolled to the filler line")
  eq(select(2, view(lower)), 1, "both on line 1: lower scrolled to the filler line")
  eq(tops_on_screen(), 2, "both on line 1: two top borders, one per window")

  -- 3. the lower window scrolls back to the top with <C-y> while the upper cursor holds line 1
  scene("40Gzt", "gg", "100<C-y>")
  wtop, fill = view(lower)
  eq(wtop, 1, "<C-y>: the lower window is back at the top")
  eq(fill, 1, "<C-y>: and shows the filler line")
  eq(tops_on_screen(), 2, "<C-y>: two top borders")

  -- 4. the lower window sits at the top (cursor further down); the upper cursor enters line 1
  scene("ggjjjj", "50G", "")
  eq(select(2, view(lower)), 0, "no row is text: no filler line needed")
  c.lua(("vim.api.nvim_set_current_win(%d)"):format(upper))
  c.feed("gg")
  c.settle(400)
  eq(select(2, view(lower)), 1, "the other window's cursor row: the lower window follows")
  eq(tops_on_screen(), 2, "the other window's cursor row: two top borders")

  -- 5. <C-e> scrolls the border away, and it stays away (also once every timer has run) until
  -- the cursor moves again
  scene("30Gzt", "50G", "gg")
  eq(select(2, view(lower)), 1, "<C-e>: the border is there before")
  c.feed("<C-e>")
  c.settle(400)
  eq(at_top(lower), "1,0", "<C-e> scrolls the border away")
  c.settle(400)
  eq(at_top(lower), "1,0", "<C-e>: still away once the editor is idle")
  c.feed("l")
  c.settle(400)
  eq(at_top(lower), "1,1", "<C-e>: the next cursor move brings the border back")

  -- one window from here on
  c.cmd("only")
  local win = c.lua_get("vim.api.nvim_get_current_win()")
  ---@param what string
  local function border_on_top(what)
    eq(at_top(win), "1,1", what .. ": scrolled to the filler line")
    eq(head(screen(c)[1], 1), "┌", what .. ": the top border is the first screen line")
    eq(screen(c)[2], "| A | B |", what .. ": the cursor row follows the border")
  end
  c.feed("gg0") -- column 0 too ('nostartofline' keeps the column of the `l` above)
  c.settle(400)
  border_on_top("gg")

  -- 6. the buffer comes back into the window with its cursor still on (1, 0), where the cursor
  -- of the other buffer was as well: no CursorMoved, and the stamp of the last render is unchanged
  eq(c.lua_get("vim.api.nvim_win_get_cursor(0)")[2], 0, "the cursor is on column 0")
  c.cmd("enew")
  c.settle(300)
  c.feed("<C-^>")
  c.settle(400)
  border_on_top("back with <C-^>")
  c.cmd("enew")
  c.settle(300)
  c.cmd("b#")
  c.settle(400)
  border_on_top("back with :b#")

  -- 7. zz / zt / z<CR> / z. on line 1 scroll without moving the cursor (no CursorMoved)
  for _, keys in ipairs({ "zz", "zt", "z<CR>", "z." }) do
    c.feed(keys)
    c.settle(400)
    border_on_top(keys .. " on line 1")
  end
  c.kill()

  -- ───────────── pure helpers ─────────────
  local tr = require("markdown.core.table_render")
  local cfgm = require("markdown.config")

  -- G: config values must be whole, finite numbers
  local function render_cfg(t)
    cfgm.setup({ table = { render = t } })
    return cfgm.get().table.render
  end
  local saved_notify = vim.notify
  vim.notify = function() end
  eq(render_cfg({ pad = 1.5 }).pad, tr.DEFAULTS.pad, "pad = 1.5 is refused")
  eq(render_cfg({ pad = math.huge }).pad, tr.DEFAULTS.pad, "pad = inf is refused")
  eq(render_cfg({ min_width = 2.5 }).min_width, tr.DEFAULTS.min_width, "min_width = 2.5 is refused")
  eq(render_cfg({ max_width = 80.5 }).max_width, nil, "max_width = 80.5 is refused")
  eq(render_cfg({ max_width = math.huge }).max_width, nil, "max_width = inf is refused")
  eq(render_cfg({ debounce_ms = 0.5 }).debounce_ms, tr.DEFAULTS.debounce_ms, "debounce 0.5 refused")
  eq(
    render_cfg({ debounce_ms = 0 / 0 }).debounce_ms,
    tr.DEFAULTS.debounce_ms,
    "debounce nan refused"
  )
  eq(render_cfg({ pad = 3 }).pad, 3, "a whole number is kept")
  eq(render_cfg({ border = "bogus" }).border, tr.DEFAULTS.border, "border is checked")
  vim.notify = saved_notify

  -- H: to_lines uses the table.render config for what the caller leaves unset
  cfgm.setup({ table = { render = { border = "ascii", pad = 2 } } })
  local plain = tr.to_lines({ "| A | B |", "| - | - |", "| 1 | 22 |" })
  eq(plain[1], "+-----+------+", "to_lines: border and pad from the config")
  eq(
    tr.to_lines({ "| A | B |", "| - | - |", "| 1 | 22 |" }, { border = "single", pad = 1 })[1],
    "┌───┬────┐",
    "to_lines: an explicit option wins"
  )
  cfgm.setup({})
end
