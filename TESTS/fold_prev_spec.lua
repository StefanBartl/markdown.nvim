-- TESTS/fold_prev_spec.lua — core.fold_prev: "fold previous heading, then
-- center" (bound to `zi`). Its own single-hop search independent of
-- headings.goto_prev_heading, covering ATX and Setext headings and the
-- restore-view no-op when nothing is found.

return function(H)
  local eq = H.eq
  local api = vim.api
  local fold_prev = require("markdown.core.fold_prev")

  -- Non-markdown buffer: a true no-op (early return on filetype check).
  do
    local buf = H.scratch("text")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "# looks like a heading", "body" })
    api.nvim_win_set_cursor(0, { 2, 0 })
    fold_prev.fold_prev_heading_then_center()
    local cur = api.nvim_win_get_cursor(0)
    eq(cur[1], 2, "non-markdown buffer: cursor row untouched")
    eq(cur[2], 0, "non-markdown buffer: cursor col untouched")
  end

  -- No heading above the cursor: winrestview puts the view back (cursor
  -- position unchanged) rather than moving somewhere arbitrary.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "no heading here", "still none", "cursor here" })
    api.nvim_win_set_cursor(0, { 3, 0 })
    fold_prev.fold_prev_heading_then_center()
    local cur = api.nvim_win_get_cursor(0)
    eq(cur[1], 3, "no heading above: cursor row stays put")
    eq(cur[2], 0, "no heading above: cursor col stays put")
  end

  -- ATX heading above the cursor: cursor moves to it.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { "# Heading", "para one", "para two", "cursor here" }
    )
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
    vim.wo.foldenable = true
    api.nvim_win_set_cursor(0, { 4, 0 })
    fold_prev.fold_prev_heading_then_center()
    eq(api.nvim_win_get_cursor(0)[1], 1, "ATX heading above: cursor lands on it")
  end

  -- BUG regressions (both fixed): a Setext heading right at the buffer's
  -- first two lines, underlined with '=' (H1-style).
  --   (A) goto_prev_heading_any's manual Setext loop only ever matched a
  --       '-'-underline, never '=', despite this function's own doc comment
  --       claiming to cover "Setext-style ===/--- headings" -- confirmed:
  --       an '='-underlined title anywhere in the buffer was never found.
  --   (B) the loop's lower bound stopped at lnum=2, so a Setext heading
  --       occupying the buffer's very first two lines (title=1,
  --       underline=2) was never reachable regardless of underline char --
  --       lnum=1 was never evaluated as a title candidate.
  -- This case exercises both at once (top-of-buffer + '=' underline); the
  -- next case isolates (B) alone with a '-' underline elsewhere confirmed
  -- already working before the fix.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { "Setext Title", "============", "body one", "cursor here" }
    )
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
    vim.wo.foldenable = true
    api.nvim_win_set_cursor(0, { 4, 0 })
    fold_prev.fold_prev_heading_then_center()
    eq(
      api.nvim_win_get_cursor(0)[1],
      1,
      "BUG regression: '='-underlined Setext title at the buffer's top is found"
    )
  end

  -- Isolates (B): a '-'-underlined Setext heading at the buffer's very top.
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "Setext Title", "------------", "cursor here" })
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
    vim.wo.foldenable = true
    api.nvim_win_set_cursor(0, { 3, 0 })
    fold_prev.fold_prev_heading_then_center()
    eq(
      api.nvim_win_get_cursor(0)[1],
      1,
      "BUG regression: '-'-underlined Setext title at the buffer's top is found"
    )
  end

  -- Repeated calls walk one heading at a time (the default v:count1 == 1
  -- path; v:count1 is read-only from Lua so a multi-hop count can't be
  -- simulated directly here, but two single hops exercise the same loop body).
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# First",
      "para",
      "## Second",
      "para",
      "cursor here",
    })
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require'markdown.core.fold'.foldexpr(v:lnum)"
    vim.wo.foldenable = true
    api.nvim_win_set_cursor(0, { 5, 0 })
    fold_prev.fold_prev_heading_then_center()
    eq(api.nvim_win_get_cursor(0)[1], 3, "1st call: cursor lands on the nearer '## Second'")
    fold_prev.fold_prev_heading_then_center()
    eq(api.nvim_win_get_cursor(0)[1], 1, "2nd call: cursor walks up to '# First'")
  end
end
