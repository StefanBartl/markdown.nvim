-- TESTS/headline_spacing_spec.lua — core.headline_spacing:
--   * A section with content between two H2+ headings gets the full
--     `[blank]---[blank]` separator.
--   * A section with NO content between two H2+ headings gets a single
--     blank line and no `---` — and an existing stray `---`/extra blanks
--     in such a gap are collapsed down to that one blank line.
--   * The same rule applies to the final H2+ section against EOF.

return function(H)
  local eq, ok = H.eq, H.ok
  local hs = require("markdown.core.headline_spacing")

  local function set(buf, lines) vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines) end
  local function get(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end

  -- Content between two headings: gets `[blank]---[blank]`. A final section
  -- also gets it, but only because it has content of its own here.
  do
    local buf = H.scratch("markdown")
    set(buf, {
      "# Title",
      "",
      "## One",
      "",
      "Body text.",
      "",
      "## Two",
      "",
      "More text.",
    })
    local fixed = hs.apply_headl_separators(buf, { notify = false })
    ok(fixed >= 1, "content section: reports a fix")
    local lines = get(buf)
    eq(
      table.concat(lines, "\n"),
      table.concat({
        "# Title",
        "",
        "## One",
        "",
        "Body text.",
        "",
        "---",
        "",
        "## Two",
        "",
        "More text.",
        "",
        "---",
        "",
      }, "\n"),
      "content section: separator inserted between and at EOF"
    )
  end

  -- No content between two headings: only a single blank line, no `---`.
  do
    local buf = H.scratch("markdown")
    set(buf, {
      "# Title",
      "",
      "## One",
      "",
      "## Two",
      "",
      "Body text.",
    })
    local fixed = hs.apply_headl_separators(buf, { notify = false })
    local lines = get(buf)
    eq(
      table.concat(lines, "\n"),
      table.concat({
        "# Title",
        "",
        "## One",
        "",
        "## Two",
        "",
        "Body text.",
        "",
        "---",
        "",
      }, "\n"),
      "empty section: no --- inserted between headings with no text, final section still closed"
    )
    ok(fixed >= 1, "empty section: still reports the final-section fix")
  end

  -- Already-correct empty gap (single blank line) is left untouched.
  do
    local buf = H.scratch("markdown")
    set(buf, { "## One", "", "## Two", "", "Body." })
    local sections = hs.find_sections_needing_separator(get(buf))
    eq(#sections, 0, "empty section: correctly-spaced gap is not flagged")
    hs.apply_headl_separators(buf, { notify = false })
    -- Only the final section (which has content) should change; the
    -- between-heading gap itself must stay a single blank line.
    ok(get(buf)[3] == "## Two", "empty section: gap untouched, heading still on line 3")
  end

  -- A stray `---` left in a no-content gap (e.g. from an older buggy run)
  -- gets collapsed down to a single blank line.
  do
    local buf = H.scratch("markdown")
    set(buf, {
      "## One",
      "",
      "---",
      "",
      "## Two",
      "",
      "Body.",
    })
    hs.apply_headl_separators(buf, { notify = false })
    local lines = get(buf)
    eq(lines[1], "## One", "stray dash: heading kept")
    eq(lines[2], "", "stray dash: collapsed to a single blank line")
    eq(lines[3], "## Two", "stray dash: no --- left behind before the next heading")
  end

  -- Final section with no content: no `---` inserted at EOF.
  do
    local buf = H.scratch("markdown")
    set(buf, { "# Title", "", "## Last", "" })
    local fixed = hs.apply_headl_separators(buf, { notify = false })
    eq(fixed, 0, "empty final section: nothing to fix")
    local lines = get(buf)
    ok(not vim.tbl_contains(lines, "---"), "empty final section: no --- inserted at EOF")
  end

  -- A window scrolled INTO the gap that gets replaced keeps its view: the
  -- separator replaces the gap in one edit (delete-then-insert clamped the
  -- topline to the start of the gap, so the text jumped on save).
  do
    local buf = H.scratch("markdown")
    local lines = { "# Title", "", "## One", "" }
    for i = 1, 30 do
      lines[#lines + 1] = "content " .. i
    end
    vim.list_extend(lines, { "", "", "", "", "", "## Two", "", "Body." }) -- 5 blank lines: too many
    set(buf, lines)
    local gap_first = #lines - 7 -- first of the five blank lines
    local topline = gap_first + 2 -- inside the gap
    vim.fn.winrestview({ topline = topline, lnum = topline + 3 })
    eq(vim.fn.getline("."), "## Two", "fixture: cursor on the next heading")
    eq(vim.fn.winsaveview().topline, topline, "fixture: topline inside the gap")

    hs.apply_headl_separators(buf, { notify = false })

    local v = vim.fn.winsaveview()
    eq(v.topline, topline, "gap replaced: topline keeps its number")
    eq(vim.fn.getline("."), "## Two", "gap replaced: cursor stays on its heading")
  end
end
