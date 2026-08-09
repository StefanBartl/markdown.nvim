-- docs/TESTS/fenced_scope_spec.lua — fenced-block scope: detection + wiring
-- into TOC, heading nav, anchor jump, heading shift, and foldexpr.
--
-- Uses provider="builtin" so the spec is self-contained (no color_my_ascii
-- needed on the runtime path); the color_my_ascii provider is exercised
-- separately by that plugin's own tests.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api
  local config = require("markdown.config")
  local scope = require("markdown.scope")

  local DOC = {
    "# Doc Title", -- 1
    "", -- 2
    "## Section A", -- 3
    "", -- 4
    "```markdown", -- 5
    "# Inner Title", -- 6
    "", -- 7
    "## Inner A", -- 8
    "", -- 9
    "## Inner B", -- 10
    "", -- 11
    "```", -- 12
    "", -- 13
    "## Section B", -- 14
  }

  local function fresh()
    config.setup({ fenced_scope = { provider = "builtin" } })
    scope._reset_backend()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.deepcopy(DOC))
    return buf
  end

  local function has_sub(buf, needle)
    for _, l in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l:find(needle, 1, true) then return true end
    end
    return false
  end

  -- ---- scope.detect --------------------------------------------------------
  do
    local buf = fresh()
    local s = scope.detect(buf, 7) -- inside the block (## Inner A is row 7 0-idx)
    ok(s and s.kind == "block", "cursor inside block -> block scope")
    eq(s.first, 6, "block scope first line")
    eq(s.last, 11, "block scope last line")

    local b = scope.detect(buf, 0) -- title, outside
    ok(b and b.kind == "buffer", "cursor outside -> buffer scope")
    ok(scope.is_excluded(b, 8), "buffer scope excludes inner heading line")
    ok(not scope.is_excluded(b, 3), "buffer scope keeps outer heading line")
  end

  -- ---- TOC inside the block ------------------------------------------------
  do
    local buf = fresh()
    api.nvim_win_set_cursor(0, { 8, 0 }) -- on ## Inner A
    require("markdown.commands.toc").update("## Table of content", { separators = false })
    local L = api.nvim_buf_get_lines(buf, 0, -1, false)
    local toc_i, open_i, close_i
    for i, l in ipairs(L) do
      if l == "## Table of content" then toc_i = i end
      if l == "```markdown" then open_i = i end
      if l == "```" and open_i and not close_i then close_i = i end
    end
    ok(
      toc_i and open_i and close_i and toc_i > open_i and toc_i < close_i,
      "TOC inserted inside the block"
    )
    ok(has_sub(buf, "- [Inner A](#inner-a)"), "block TOC lists Inner A")
    ok(not has_sub(buf, "- [Section A](#section-a)"), "block TOC excludes outer Section A")
  end

  -- ---- TOC outside the block (fence interiors excluded) --------------------
  do
    local buf = fresh()
    api.nvim_win_set_cursor(0, { 1, 0 }) -- on the title, outside
    require("markdown.commands.toc").update("## Table of content", { separators = false })
    ok(has_sub(buf, "- [Section A](#section-a)"), "buffer TOC lists Section A")
    ok(not has_sub(buf, "- [Inner A](#inner-a)"), "buffer TOC excludes fenced Inner A")
  end

  -- ---- heading nav is scope-bounded ---------------------------------------
  do
    local buf = fresh()
    local head = require("markdown.core.headings")
    api.nvim_win_set_cursor(0, { 8, 0 }) -- ## Inner A
    head.goto_next_heading()
    eq(api.nvim_win_get_cursor(0)[1], 10, "next heading -> Inner B")
    head.goto_next_heading()
    eq(api.nvim_win_get_cursor(0)[1], 10, "no heading past block end -> stays")

    api.nvim_win_set_cursor(0, { 3, 0 }) -- ## Section A (outside)
    head.goto_next_heading()
    eq(api.nvim_win_get_cursor(0)[1], 14, "outside nav skips fenced block -> Section B")
  end

  -- ---- disabled = legacy (enters the fence) --------------------------------
  do
    config.setup({ fenced_scope = { enable = false } })
    scope._reset_backend()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, vim.deepcopy(DOC))
    api.nvim_win_set_cursor(0, { 3, 0 })
    require("markdown.core.headings").goto_next_heading()
    eq(api.nvim_win_get_cursor(0)[1], 6, "disabled: legacy nav enters fence")
  end

  -- ---- anchor jump scoped to the block ------------------------------------
  do
    config.setup({ fenced_scope = { provider = "builtin" } })
    scope._reset_backend()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "## Outer Target",
      "",
      "```markdown",
      "## Inner Target",
      "",
      "See [go](#inner-target)",
      "```",
    })
    api.nvim_win_set_cursor(0, { 6, 4 })
    require("markdown.anchor.jump").jump()
    eq(api.nvim_win_get_cursor(0)[1], 4, "anchor jump resolves inside the block")
  end

  -- ---- heading shift-all scoped to the block ------------------------------
  do
    local buf = fresh()
    api.nvim_win_set_cursor(0, { 8, 0 })
    local s = scope.detect()
    require("markdown.core.headings").shift_range(s.first, s.last, 1)
    ok(has_sub(buf, "### Inner A"), "block shift deepened Inner A")
    ok(has_sub(buf, "## Section A"), "outer Section A unchanged")
  end

  -- ---- foldexpr scope gating ----------------------------------------------
  do
    config.setup({ fenced_scope = { provider = "builtin", operations = { fold = true } } })
    scope._reset_backend()
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Doc", -- 1
      "```python", -- 2
      "# comment", -- 3
      "```", -- 4
      "```markdown", -- 5
      "## Inner", -- 6
      "```", -- 7
    })
    local fold = require("markdown.core.fold")
    eq(fold.foldexpr(3), "=", "python-fence # comment does not fold")
    eq(fold.foldexpr(6), ">2", "markdown-fence ## Inner folds as heading")
    eq(fold.foldexpr(1), ">1", "outer # Doc folds")
  end

  config.setup({})
  scope._reset_backend()
end
