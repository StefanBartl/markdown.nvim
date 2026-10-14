-- TESTS/table_render_screen_spec.lua -- the table grid on a REAL screen: an embedded Neovim
-- (testing.rpc) draws it and the spec reads the cells. Covers what the pure specs cannot: no blank
-- rows between table rows with `wrap` on, the cursor row, indent, restore of `conceallevel` in
-- splits, fences, the event wiring (edit / resize / wipeout) and the config checks.
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
  c.kill()

  -- ───────────── B: indent ─────────────
  c = spawn()
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
  c.kill()

  -- ───────────── C: table on buffer line 1 ─────────────
  c = spawn()
  load(c, { "| A | B |", "| - | - |", "| 1 | 2 |", "", "end" })
  sc = screen(c)
  ok(c.lua_get("require('markdown.core.table_render').is_enabled(0)"), "enabled")
  ok(table.concat(sc, "\n"):find("│ 1 │ 2 │", 1, true), "line 1 table: rows are drawn")
  ok(table.concat(sc, "\n"):find("└", 1, true), "line 1 table: bottom border is drawn")
  -- a buffer that is only a table still shows it (nothing else to hang the grid on)
  load(c, { "| A | B |", "| - | - |", "| 1 | 2 |" })
  sc = screen(c)
  ok(table.concat(sc, "\n"):find("│ 1 │ 2 │", 1, true), "only-table buffer: rows drawn")
  ok(table.concat(sc, "\n"):find("└", 1, true), "only-table buffer: bottom border drawn")
  c.kill()

  -- ───────────── E: conceallevel in splits ─────────────
  c = spawn()
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
  c.kill()

  -- table_truncate has the same pattern
  c = spawn()
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
  c.kill()

  -- ───────────── F: fences ─────────────
  c = spawn()
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
  c.kill()

  -- ───────────── event wiring: edit, resize, wipeout ─────────────
  c = spawn()
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
  c.kill()

  -- ───────────── layout options on the screen ─────────────
  c = spawn()
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
  c.kill()

  -- ───────────── wide characters: no line wider than the table ─────────────
  c = spawn()
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
