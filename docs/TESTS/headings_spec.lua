-- docs/TESTS/headings_spec.lua — heading level shift on a buffer.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local config = require("markdown_nvim.config")
  config.setup({})
  local head = require("markdown_nvim.core.headings")

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

  config.setup({})
end
