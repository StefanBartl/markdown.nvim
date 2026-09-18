-- TESTS/heading_gaps_spec.lua — core.heading_gaps: detect (and optionally
-- fix) skipped heading levels, e.g. an H1 followed directly by an H3.

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api
  local hg = require("markdown.core.heading_gaps")

  -- No gap: consecutive levels (including staying flat or going shallower).
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { "# One", "## Two", "### Three", "## Back to two", "# Back to one" }
    )
    eq(#hg.find_gaps(buf), 0, "find_gaps: no gap in a properly nested outline")
  end

  -- The very first heading can never be a gap, regardless of its level.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "### Starts at H3", "content" })
    eq(#hg.find_gaps(buf), 0, "find_gaps: the first heading in the buffer is never a gap")
  end

  -- Single gap: H1 -> H3 (skips H2).
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "### Three", "content" })
    local gaps = hg.find_gaps(buf)
    eq(#gaps, 1, "find_gaps: one gap found")
    eq(gaps[1].lnum, 2, "find_gaps: gap reported at the offending line")
    eq(gaps[1].level, 3, "find_gaps: actual level recorded")
    eq(gaps[1].prev_level, 1, "find_gaps: previous level recorded")
    eq(gaps[1].expected, 2, "find_gaps: expected level is prev+1")
    eq(gaps[1].title, "Three", "find_gaps: heading title captured without '#'s")
  end

  -- Multiple gaps, and the outline continues as if the first one were fixed
  -- (so a second big jump right after is still reported relative to the
  -- corrected level, not the original one).
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "#### Four", "###### Six" })
    local gaps = hg.find_gaps(buf)
    eq(#gaps, 2, "find_gaps: two gaps found")
    eq(gaps[1].level, 4, "find_gaps: first gap is the H4")
    eq(gaps[1].expected, 2, "find_gaps: first gap expected H2 (prev H1 + 1)")
    eq(gaps[2].level, 6, "find_gaps: second gap is the H6")
    eq(
      gaps[2].prev_level,
      2, -- as if gap 1 had been fixed to H2
      "find_gaps: second gap's prev_level assumes the outline continues as if fixed"
    )
    eq(gaps[2].expected, 3, "find_gaps: second gap expected H3")
  end

  -- Fenced code interiors are skipped: a `#`-led line inside a fence is not
  -- a heading and must not affect gap detection either way.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "```", "### fake", "```", "### Three" })
    local gaps = hg.find_gaps(buf)
    eq(#gaps, 1, "find_gaps: fenced '#' lines are not seen as headings")
    eq(gaps[1].lnum, 5, "find_gaps: the real gap after the fence is still found")
  end

  -- fix_gaps: rewrites each offending heading's level, preserving indent and title.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "#### Four Deep", "content" })
    local gaps = hg.find_gaps(buf)
    hg.fix_gaps(buf, gaps)
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(lines[2], "## Four Deep", "fix_gaps: heading rewritten to the expected level")
    eq(lines[3], "content", "fix_gaps: unrelated lines untouched")
    eq(#hg.find_gaps(buf), 0, "fix_gaps: no gaps remain after fixing")
  end

  -- fix_gaps preserves leading indent (e.g. a heading inside a blockquote-ish
  -- indent is unusual for ATX but the rewrite must not eat arbitrary prefix).
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "  ##### Five" })
    local gaps = hg.find_gaps(buf)
    hg.fix_gaps(buf, gaps)
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(lines[2], "  ## Five", "fix_gaps: leading whitespace before the '#'s is preserved")
  end

  -- M.check: silent_ok suppresses the "no gaps" notice but still returns [].
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "## Two" })
    local gaps = hg.check(buf, { silent_ok = true })
    eq(#gaps, 0, "check: silent_ok still returns the (empty) gap list")
  end

  -- M.check: when gaps exist, vim.fn.confirm is consulted; "Yes" fixes them.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "### Three" })

    local real_confirm = vim.fn.confirm
    vim.fn.confirm = function(...) return 1 end -- "&Yes"
    local gaps = hg.check(buf)
    vim.fn.confirm = real_confirm

    eq(#gaps, 1, "check: returns the gaps found regardless of the fix choice")
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(lines[2], "## Three", "check: 'Yes' at the confirm prompt actually fixes the gap")
  end

  -- M.check: "No" at the confirm prompt leaves the buffer untouched.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "### Three" })

    local real_confirm = vim.fn.confirm
    vim.fn.confirm = function(...) return 2 end -- "&No"
    hg.check(buf)
    vim.fn.confirm = real_confirm

    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(lines[2], "### Three", "check: 'No' at the confirm prompt leaves the heading as-is")
  end
end
