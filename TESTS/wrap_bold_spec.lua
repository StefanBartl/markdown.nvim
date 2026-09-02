-- TESTS/wrap_bold_spec.lua — `**` in visual mode, linewise and charwise.
--
-- The linewise (`V`) case is the regression this spec exists for: `V` selects
-- whole lines, but the old code read the cursor and anchor *columns* anyway,
-- so `**` wrapped from wherever the cursor sat to wherever the anchor sat --
-- opening asterisks mid-word and closing ones a few characters later.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local api = vim.api
  local config = require("markdown.config")
  local wrap = require("markdown.core.wrap")

  ---@param lines string[]
  ---@return integer bufnr
  local function fresh(lines)
    config.setup({})
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
  end

  ---@param buf integer
  ---@return string[]
  local function get(buf) return api.nvim_buf_get_lines(buf, 0, -1, false) end

  --- Select `first`..`last` (1-indexed) linewise and leave visual mode, so the
  --- selection is reachable exactly the way `:'<,'>` leaves it: `visualmode()`
  --- is "V" and the `'<`/`'>` marks span whole lines.
  ---
  --- The leading `<Esc>` matters: a toggle re-selects its lines (`gv`), so the
  --- next call starts in visual mode, where `V` would *leave* it instead of
  --- starting a fresh selection.
  ---@param first integer
  ---@param last integer
  ---@param col integer Cursor column, to prove it is not read
  local function select_lines(first, last, col)
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    api.nvim_win_set_cursor(0, { first, col or 0 })
    local keys =
      api.nvim_replace_termcodes("V" .. string.rep("j", last - first) .. "<Esc>", true, false, true)
    api.nvim_feedkeys(keys, "x", false)
  end

  -- ---- one line, cursor parked mid-word (the reported case) ---------------
  do
    local buf = fresh({ "hello world" })
    select_lines(1, 1, 4)
    wrap.toggle_visual_bold()
    eq(get(buf)[1], "**hello world**", "V on one line bolds the whole line")
  end

  -- ---- and back again ------------------------------------------------------
  do
    local buf = fresh({ "**hello world**" })
    select_lines(1, 1, 6)
    wrap.toggle_visual_bold()
    eq(get(buf)[1], "hello world", "V on a bold line unwraps it")
  end

  -- ---- several lines at once ----------------------------------------------
  do
    local buf = fresh({ "first line", "second line", "third line" })
    select_lines(1, 3, 3)
    wrap.toggle_visual_bold()
    local L = get(buf)
    eq(L[1], "**first line**", "line 1 wrapped")
    eq(L[2], "**second line**", "line 2 wrapped")
    eq(L[3], "**third line**", "line 3 wrapped")

    select_lines(1, 3, 0)
    wrap.toggle_visual_bold()
    L = get(buf)
    eq(L[1], "first line", "line 1 unwrapped")
    eq(L[2], "second line", "line 2 unwrapped")
    eq(L[3], "third line", "line 3 unwrapped")
  end

  -- ---- a mixed range wraps what is not bold and leaves what is ------------
  do
    local buf = fresh({ "plain", "**already bold**" })
    select_lines(1, 2, 0)
    wrap.toggle_visual_bold()
    local L = get(buf)
    eq(L[1], "**plain**", "the plain line gets wrapped")
    eq(L[2], "**already bold**", "the bold line is left alone")
  end

  -- ---- blank lines are skipped, not filled with `****` --------------------
  do
    local buf = fresh({ "text", "", "   ", "more" })
    select_lines(1, 4, 0)
    wrap.toggle_visual_bold()
    local L = get(buf)
    eq(L[1], "**text**", "content wrapped")
    eq(L[2], "", "empty line untouched")
    eq(L[3], "   ", "whitespace-only line untouched")
    eq(L[4], "**more**", "content wrapped")
  end

  -- ---- markup stays outside the wrap --------------------------------------
  do
    local buf = fresh({
      "  - item",
      "3. numbered",
      "> quoted",
      "- [ ] task",
      "## Heading",
      "hard break  ",
    })
    select_lines(1, 6, 0)
    wrap.toggle_visual_bold()
    local L = get(buf)
    eq(L[1], "  - **item**", "list bullet and indent stay outside")
    eq(L[2], "3. **numbered**", "ordered-list marker stays outside")
    eq(L[3], "> **quoted**", "blockquote marker stays outside")
    eq(L[4], "- [ ] **task**", "task-list checkbox stays outside")
    eq(L[5], "## **Heading**", "heading hashes stay outside")
    eq(L[6], "**hard break**  ", "trailing hard-break spaces stay outside")

    select_lines(1, 6, 0)
    wrap.toggle_visual_bold()
    L = get(buf)
    eq(L[1], "  - item", "list line round-trips")
    eq(L[5], "## Heading", "heading round-trips")
    eq(L[6], "hard break  ", "hard break round-trips")
  end

  -- ---- charwise `v` is unchanged ------------------------------------------
  do
    local buf = fresh({ "hello world" })
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    api.nvim_win_set_cursor(0, { 1, 0 })
    local keys = api.nvim_replace_termcodes("v4l<Esc>", true, false, true)
    api.nvim_feedkeys(keys, "x", false)
    wrap.toggle_visual_bold()
    eq(get(buf)[1], "**hello** world", "charwise still wraps just the selection")

    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    api.nvim_win_set_cursor(0, { 1, 2 })
    keys = api.nvim_replace_termcodes("v4l<Esc>", true, false, true)
    api.nvim_feedkeys(keys, "x", false)
    wrap.toggle_visual_bold()
    eq(get(buf)[1], "hello world", "charwise still unwraps")
  end
end
