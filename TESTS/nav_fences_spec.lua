-- TESTS/nav_fences_spec.lua — <C-p>/<C-f> stop on fenced-code delimiters.
--
-- The prev/next-heading hops treat a fenced block's opening and closing line
-- as landmarks alongside headings (config `nav.fences`, default true). The
-- by-level hops (<leader><C-p>/<leader><C-f>) stay headings-only, which is
-- what keeps heading-only navigation available.
--
-- provider="builtin" keeps the spec self-contained (no color_my_ascii on the
-- runtime path), same as fenced_scope_spec.lua.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local api = vim.api
  local config = require("markdown.config")
  local scope = require("markdown.scope")
  local head = require("markdown.core.headings")

  local DOC = {
    "# Title", --  1
    "", --  2
    "## Section A", --  3
    "", --  4
    "```lua", --  5  fence open
    "local x = 1", --  6
    "```", --  7  fence close
    "", --  8
    "## Section B", --  9
    "", -- 10
    "~~~python", -- 11  tilde fence open
    "x = 1", -- 12
    "~~~", -- 13  tilde fence close
    "", -- 14
    "- item", -- 15
    "  ```sh", -- 16  indented fence open
    "  echo hi", -- 17
    "  ```", -- 18  indented fence close
    "", -- 19
    "## Section C", -- 20
  }

  ---@param nav table|nil `nav` config for this buffer
  ---@return integer bufnr
  local function fresh(nav)
    config.setup({ fenced_scope = { provider = "builtin" }, nav = nav })
    scope._reset_backend()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.deepcopy(DOC))
    return buf
  end

  ---@return integer lnum
  local function row() return api.nvim_win_get_cursor(0)[1] end

  -- ---- forward: every heading AND every delimiter, in document order -------
  do
    fresh()
    api.nvim_win_set_cursor(0, { 1, 0 })
    local expected = { 3, 5, 7, 9, 11, 13, 16, 18, 20 }
    for _, want in ipairs(expected) do
      head.goto_next_heading()
      eq(row(), want, "forward hop lands on line " .. want)
    end
    head.goto_next_heading()
    eq(row(), 20, "no stop past the last one -> cursor stays")
  end

  -- ---- backward: the same landmarks in reverse ----------------------------
  do
    fresh()
    api.nvim_win_set_cursor(0, { 20, 0 })
    local expected = { 18, 16, 13, 11, 9, 7, 5, 3, 1 }
    for _, want in ipairs(expected) do
      head.goto_prev_heading()
      eq(row(), want, "backward hop lands on line " .. want)
    end
    head.goto_prev_heading()
    eq(row(), 1, "no stop before the first one -> cursor stays")
  end

  -- ---- the cursor's column survives the hop, as it did before -------------
  do
    fresh()
    api.nvim_win_set_cursor(0, { 3, 5 })
    head.goto_next_heading()
    eq(row(), 5, "hop to the fence open")
    eq(api.nvim_win_get_cursor(0)[2], 5, "column kept")
  end

  -- ---- nav.fences = false: headings only (the pre-change behaviour) -------
  do
    fresh({ fences = false })
    api.nvim_win_set_cursor(0, { 3, 0 })
    head.goto_next_heading()
    eq(row(), 9, "fences off: Section A -> Section B, fences skipped")
    head.goto_next_heading()
    eq(row(), 20, "fences off: Section B -> Section C")
  end

  -- ---- the by-level hops stay headings-only even with fences on -----------
  do
    fresh()
    api.nvim_win_set_cursor(0, { 3, 0 })
    head.goto_next_heading_level()
    eq(row(), 9, "by-level hop ignores fences (forward)")
    head.goto_prev_heading_level()
    eq(row(), 3, "by-level hop ignores fences (backward)")
  end

  -- ---- a delimiter inside a markdown block's interior is a landmark too,
  --      and block scope still bounds the hop -------------------------------
  do
    config.setup({ fenced_scope = { provider = "builtin" } })
    scope._reset_backend()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Outer", --  1
      "", --  2
      "```markdown", --  3  the md block's own opening line
      "## Inner", --  4
      "", --  5
      "## Inner B", --  6
      "```", --  7
      "", --  8
      "## After", --  9
    })
    api.nvim_win_set_cursor(0, { 4, 0 }) -- inside the markdown block
    head.goto_next_heading()
    eq(row(), 6, "inside a markdown block: next stop is the next inner heading")
    head.goto_next_heading()
    eq(row(), 6, "block scope still stops at the interior's end")
  end

  config.setup({})
  scope._reset_backend()
end
