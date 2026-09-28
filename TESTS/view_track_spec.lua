-- TESTS/view_track_spec.lua — markdown.util.view_track: windows keep their
-- view (lnum/topline) across line edits recorded through the tracker.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local view_track = require("markdown.util.view_track")

  --- Scratch buffer with `n` numbered lines, view set to topline/lnum.
  ---@param n integer
  ---@param topline integer
  ---@param lnum integer
  ---@return integer buf
  local function fixture(n, topline, lnum)
    local buf = H.scratch()
    local lines = {}
    for i = 1, n do
      lines[i] = "line " .. i
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.fn.winrestview({ topline = topline, lnum = lnum })
    local v = vim.fn.winsaveview()
    eq(v.topline, topline, "fixture: topline")
    eq(v.lnum, lnum, "fixture: lnum")
    return buf
  end

  -- Insert above the view: everything below moves down.
  do
    local buf = fixture(100, 30, 35)
    local track = view_track.begin(buf)
    track.set_lines(5, 5, { "x", "y" })
    track.restore()
    local v = vim.fn.winsaveview()
    eq(v.topline, 32, "insert above: topline shifts by +2")
    eq(v.lnum, 37, "insert above: lnum shifts by +2")
    eq(vim.fn.getline("."), "line 35", "insert above: cursor stays on its text")
  end

  -- Delete above the view: everything below moves up.
  do
    local buf = fixture(100, 30, 35)
    local track = view_track.begin(buf)
    track.set_lines(5, 8, {})
    track.restore()
    local v = vim.fn.winsaveview()
    eq(v.topline, 27, "delete above: topline shifts by -3")
    eq(vim.fn.getline("."), "line 35", "delete above: cursor stays on its text")
  end

  -- topline INSIDE a replaced range keeps its number (the original bug: it was
  -- clamped to the start of the range); a cursor below the range follows its text.
  do
    local buf = fixture(100, 30, 35)
    local track = view_track.begin(buf)
    track.set_lines(27, 33, { "a" }) -- replaces lines 28..33 by one line
    track.restore()
    local v = vim.fn.winsaveview()
    eq(v.topline, 30, "topline inside the replaced range keeps its number")
    eq(vim.fn.getline("."), "line 35", "cursor below the replaced range keeps its text")
  end

  -- Several edits: each is recorded in the coordinates current at its time.
  do
    local buf = fixture(100, 30, 35)
    local track = view_track.begin(buf)
    track.set_lines(10, 10, { "p", "q", "r" }) -- +3 above
    track.set_lines(2, 4, {}) -- -2 above
    track.set_lines(90, 90, { "tail" }) -- below the view: no effect on it
    track.restore()
    eq(vim.fn.winsaveview().topline, 31, "sequential edits: net +1 on topline")
    eq(vim.fn.getline("."), "line 35", "sequential edits: cursor stays on its text")
  end

  -- No edit through the tracker: restore must not touch anything the user did
  -- in between.
  do
    fixture(100, 30, 35)
    local buf = vim.api.nvim_get_current_buf()
    local track = view_track.begin(buf)
    vim.fn.winrestview({ topline = 50, lnum = 55 })
    track.restore()
    eq(vim.fn.winsaveview().lnum, 55, "no edits: restore is a no-op")
  end

  -- Every window on the buffer is restored, not only the current one.
  do
    local buf = fixture(100, 30, 35)
    vim.cmd("split")
    local w2 = vim.api.nvim_get_current_win()
    vim.fn.winrestview({ topline = 60, lnum = 64 })
    vim.cmd("wincmd p")
    local w1 = vim.api.nvim_get_current_win()
    -- `split` resized window 1, so compare against the views right before
    -- the tracked edit, not against the fixture numbers.
    local b1 = vim.api.nvim_win_call(w1, vim.fn.winsaveview)
    local b2 = vim.api.nvim_win_call(w2, vim.fn.winsaveview)
    local track = view_track.begin(buf)
    track.set_lines(5, 5, { "x", "y", "z" })
    track.restore()
    local v1 = vim.api.nvim_win_call(w1, vim.fn.winsaveview)
    local v2 = vim.api.nvim_win_call(w2, vim.fn.winsaveview)
    eq(v1.topline, b1.topline + 3, "window 1: topline +3")
    eq(v1.lnum, b1.lnum + 3, "window 1: lnum +3")
    eq(v2.topline, b2.topline + 3, "window 2: topline +3")
    eq(v2.lnum, b2.lnum + 3, "window 2: lnum +3")
    vim.cmd("only")
  end

  -- A big shrink whose range ends between topline and lnum: topline is inside
  -- the range (kept as-is) while lnum is below it (shifted down by `delta`).
  -- Remapped independently, that pushed topline below lnum -- an impossible
  -- view (cursor above the window top). topline must not end up past lnum.
  do
    local buf = fixture(60, 15, 52)
    local track = view_track.begin(buf)
    track.set_lines(9, 50, { "new" }) -- replaces lines 10..50 (41 lines) by 1
    track.restore()
    local v = vim.fn.winsaveview()
    eq(v.topline <= v.lnum, true, "big shrink across the gap: topline never passes lnum")
  end

  -- A buffer that shrinks below the saved view clamps instead of erroring.
  do
    local buf = fixture(100, 90, 95)
    local track = view_track.begin(buf)
    track.set_lines(20, 100, { "only" })
    track.restore()
    local v = vim.fn.winsaveview()
    eq(v.lnum, vim.api.nvim_buf_line_count(buf), "shrunk buffer: lnum clamped to the last line")
    eq(v.topline >= 1, true, "shrunk buffer: topline stays valid")
  end
end
