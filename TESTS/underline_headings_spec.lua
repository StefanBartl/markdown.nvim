-- TESTS/underline_headings_spec.lua — core.underline_headings: Setext-style
-- decoration under every ATX heading (M.apply / M.apply_range).

return function(H)
  local eq, ok = H.eq, H.ok
  local uh = require("markdown.core.underline_headings")

  -- Basic insertion: one heading gets an underline of the matching length.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Title", "body" })
    local changed = uh.apply(buf, { notify = false })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(changed, 1, "apply: one heading changed")
    eq(lines[2], "=====", "apply: underline matches heading text length ('Title' = 5)")
    eq(lines[3], "body", "apply: body line pushed down, untouched")
  end

  -- Idempotent: a correctly-sized underline is left alone (no edit, no count).
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Title", "=====", "body" })
    local changed = uh.apply(buf, { notify = false })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(changed, 0, "apply: already-correct underline is not counted as changed")
    eq(#lines, 3, "apply: no line inserted when already correct")
    eq(lines[2], "=====", "apply: existing correct underline left untouched")
  end

  -- Wrongly-sized: an existing underline (any run of `char`) is corrected in
  -- place rather than a second one being inserted.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "## Section", "==", "body" })
    local changed = uh.apply(buf, { notify = false })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(changed, 1, "apply: wrongly-sized underline counted as changed")
    eq(#lines, 3, "apply: corrected in place, no line added")
    eq(lines[2], "=======", "apply: underline corrected to 'Section' length (7)")
  end

  -- Multiple headings: offset tracking keeps later insertions aligned.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "", "## Two", "", "### Three" })
    local changed = uh.apply(buf, { notify = false })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(changed, 3, "apply: all three headings changed")
    eq(lines[1], "# One", "apply: heading 1 line unchanged")
    eq(lines[2], "===", "apply: heading 1 underline (One=3)")
    eq(lines[4], "## Two", "apply: heading 2 still at the right line after the first insert")
    eq(lines[5], "===", "apply: heading 2 underline (Two=3)")
    eq(lines[7], "### Three", "apply: heading 3 still at the right line after two inserts")
    eq(lines[8], "=====", "apply: heading 3 underline (Three=5)")
  end

  -- Fenced code interiors are skipped: a `#`-led line inside a fence is not a
  -- heading and must not get an underline inserted under it.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { "# Real", "```", "# not a heading", "```", "after" }
    )
    local changed = uh.apply(buf, { notify = false })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(changed, 1, "apply: only the real heading outside the fence is touched")
    eq(lines[2], "====", "apply: real heading gets its underline")
    eq(lines[4], "# not a heading", "apply: fenced '#' line untouched")
    eq(lines[5], "```", "apply: fence close untouched")
  end

  -- Configurable char: '-' instead of the default '='.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Hi" })
    uh.apply(buf, { notify = false, char = "-" })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(lines[2], "--", "apply: char option honored")
  end

  -- BUG (fixed): the underline must match display width, not byte length.
  -- "Über uns" is 8 display columns but 9 bytes (ü is 2 bytes in UTF-8) — the
  -- underline used to be built from #text (9 '=' chars), one character wider
  -- than the heading it decorates. Regression coverage for the fix.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Über uns", "" })
    uh.apply(buf, { notify = false })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(
      vim.fn.strdisplaywidth(lines[2]),
      vim.fn.strdisplaywidth("Über uns"),
      "apply: underline display width matches a multi-byte heading's display width"
    )
    eq(#lines[2], 8, "apply: underline is 8 bytes ('=' is 1 byte each), not 9")
    ok(
      lines[2] ~= string.rep("=", #"Über uns"),
      "apply: underline is not built from the heading's BYTE length"
    )
  end

  -- Idempotent on the multi-byte case too: applying twice makes no further change.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Öff nung" })
    uh.apply(buf, { notify = false })
    local changed_again = uh.apply(buf, { notify = false })
    eq(changed_again, 0, "apply: re-running after a multi-byte fix is a true no-op")
  end
end
