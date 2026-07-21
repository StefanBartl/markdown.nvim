-- docs/TESTS/headings_spec.lua — heading level shift on a buffer.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local config = require("markdown.config")
  config.setup({})
  local head = require("markdown.core.headings")

  local buf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# A", "## B", "### C" })

  -- increase (deeper): every heading gains one '#'
  local changed = head.shift_range(1, 3, 1)
  eq(changed, 3, "three headings shifted")
  local up = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(up[1], "## A", "H1 -> H2")
  eq(up[2], "### B", "H2 -> H3")
  eq(up[3], "#### C", "H3 -> H4")

  -- decrease (shallower): round-trips back
  head.shift_range(1, 3, -1)
  local down = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(down[1], "# A", "H2 -> H1")
  eq(down[2], "## B", "H3 -> H2")
  eq(down[3], "### C", "H4 -> H3")

  -- clamp at H6: increasing an H6 does not add a seventh '#'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "###### D" })
  eq(head.shift_range(1, 1, 1), 0, "H6 increase clamped (no change)")
  eq(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "###### D", "H6 unchanged")

  -- non-markdown buffer is a no-op
  local plain = H.scratch("text")
  vim.api.nvim_buf_set_lines(plain, 0, -1, false, { "# A" })
  eq(head.shift_range(1, 1, 1), 0, "non-markdown buffer no-op")

  -- shift_range skips fenced code: `#`-prefixed lines inside a ``` / ~~~ block
  -- must NOT be treated as headings (regression: the old `[`~]{3,}` Lua pattern
  -- never matched a real fence, so fenced `#` lines got shifted and corrupted).
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# A",             -- 1 heading (outside)
    "```bash",         -- 2 fence open
    "# not a heading", -- 3 comment inside the fence
    "```",             -- 4 fence close
    "## B",            -- 5 heading (outside)
  })
  eq(head.shift_range(1, 5, 1), 2, "only the two real headings shift")
  local fenced = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(fenced[1], "## A", "outer H1 shifted")
  eq(fenced[3], "# not a heading", "fenced # comment left untouched")
  eq(fenced[5], "### B", "outer H2 shifted")

  -- same for a tilde fence
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "~~~",             -- 1 fence open (bare tilde)
    "### inside",      -- 2 not a heading (fenced)
    "~~~",             -- 3 fence close
    "# After",         -- 4 heading (outside)
  })
  eq(head.shift_range(1, 4, 1), 1, "only the heading outside the ~~~ fence shifts")
  local tfenced = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(tfenced[2], "### inside", "tilde-fenced line untouched")
  eq(tfenced[4], "## After", "heading after tilde fence shifted")

  -- goto_prev_heading reaches an H1 (regression: the old pattern required
  -- 2+ hashes and could never land on a level-1 heading) and preserves the
  -- cursor's column, clipped to the target line's length.
  vim.api.nvim_set_current_buf(buf) -- H.scratch("text") above switched the window's buffer
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# Top",
    "prose prose prose prose",
    "## Second",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 10 })
  head.goto_prev_heading()
  local pos = vim.api.nvim_win_get_cursor(0)
  eq(pos[1], 1, "goto_prev_heading reaches H1")
  eq(pos[2], 4, "column clipped to the short H1 line's length")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# A",
    "## Second Level Heading",
    "prose",
  })
  vim.api.nvim_win_set_cursor(0, { 3, 4 })
  head.goto_prev_heading()
  pos = vim.api.nvim_win_get_cursor(0)
  eq(pos[1], 2, "goto_prev_heading stops at nearest heading")
  eq(pos[2], 4, "column preserved when the target line is long enough")

  config.setup({})
end
