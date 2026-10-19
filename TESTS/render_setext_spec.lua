-- TESTS/render_setext_spec.lua -- a setext heading (a paragraph line over `===` or `---`) in the native renderer: the title
-- row and the underline row are drawn with the heading colours, and what only looks like one is left alone.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local r = require("markdown.core.render")

  local function marks(line, extra)
    local ctx = vim.tbl_extend("force", { width = 20, cfg = r.DEFAULTS }, extra or {})
    return r.line_marks(line, ctx)
  end
  local function find(ms, pred)
    for _, m in ipairs(ms) do
      if pred(m) then return m end
    end
  end

  eq(r._setext_level("==="), 1, "=== is level 1")
  eq(r._setext_level("---"), 2, "--- is level 2")
  eq(r._setext_level("  ==="), 1, "up to three spaces of indent")
  eq(r._setext_level("    ==="), nil, "four are code")
  eq(r._setext_level("= ="), nil, "spaces inside are no underline")
  eq(r._setext_level(nil), nil, "no line below")

  -- the title row
  local title = marks("Title here", { next = "=====" })
  ok(
    find(title, function(m) return m.opts.line_hl_group == "MarkdownRenderH1Bg" end),
    "level 1 background"
  )
  local text = find(title, function(m) return m.opts.hl_group == "MarkdownRenderH1" end)
  ok(text ~= nil, "level 1 text colour")
  eq(text.opts.end_col, 10, "over the whole title")
  ok(
    find(
      marks("Title", { next = "---" }),
      function(m) return m.opts.hl_group == "MarkdownRenderH2" end
    ),
    "level 2 for dashes"
  )

  -- the underline row
  local under = marks("=====", { prev = "Title here" })
  ok(
    find(under, function(m) return m.opts.line_hl_group == "MarkdownRenderH1Bg" end),
    "the underline has the background"
  )
  ok(find(under, function(m) return m.opts.hl_group == "MarkdownRenderRule" end), "and is dimmed")
  ok(
    find(
      marks("---", { prev = "Title" }),
      function(m) return m.opts.line_hl_group == "MarkdownRenderH2Bg" end
    ),
    "level 2"
  )

  -- what is not one
  eq(#marks("===", { prev = "" }), 0, "an underline with no paragraph above is text")
  eq(#marks("===", { prev = "- item" }), 0, "a list item above is no title")
  eq(#marks("| a |", { next = "===" }), 0, "a table row is no title")
  eq(#marks("# Heading", { next = "===" }) > 0, true, "an ATX heading stays one")
  ok(
    not find(
      marks("# Heading", { next = "===" }),
      function(m) return m.opts.hl_group == "MarkdownRenderH1" end
    ),
    "and is not drawn twice"
  )
  eq(#marks("---", { prev = "" }), 1, "a rule after a blank line is still a rule")

  -- the switch
  local off = { cfg = vim.tbl_deep_extend("force", r.DEFAULTS, { headings = { setext = false } }) }
  eq(
    #marks("Title", vim.tbl_extend("force", off, { next = "===" })),
    0,
    "headings.setext = false: no title"
  )
  eq(#marks("===", vim.tbl_extend("force", off, { prev = "Title" })), 0, "and no underline")

  -- a title of several lines: every line of the paragraph is the title
  local function ahead(lines, from)
    return r._setext_ahead(
      lines[from],
      function(n) return { unpack(lines, from + 1, from + n) } end
    )
  end
  eq(ahead({ "a", "b", "===" }, 2), 1, "the line right above the underline")
  eq(ahead({ "a", "b", "c", "---" }, 2), 2, "a line further up sees it")
  eq(ahead({ "a", "b", "", "===" }, 2), nil, "a blank line ends the paragraph")
  eq(ahead({ "a", "b", "- item", "===" }, 2), nil, "so does a list item")
  eq(ahead({ "a" }, 2), nil, "nothing below")
  local long = { "t" }
  for _ = 1, r.MAX_SETEXT_LINES + 2 do
    long[#long + 1] = "p"
  end
  long[#long + 1] = "==="
  eq(ahead(long, 1), nil, "a paragraph longer than the limit keeps only the last line")
  local first = marks("first line", { next = "second line", setext = 1 })
  ok(
    find(first, function(m) return m.opts.line_hl_group == "MarkdownRenderH1Bg" end),
    "the first line of a two-line title is drawn as the heading"
  )
  eq(#marks("first line", { next = "second line" }), 0, "without the underline ahead it is text")

  -- in a buffer: both lines of the title carry the heading background
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { "first", "second", "=====", "", "plain", "text" }
    )
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    r.enable(buf)
    r.refresh(buf, true)
    local ns = vim.api.nvim_create_namespace("markdown_render")
    local function bg(row)
      for _, m in
        ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true }))
      do
        if m[4].line_hl_group == "MarkdownRenderH1Bg" then return true end
      end
      return false
    end
    ok(bg(0), "the first line of the title")
    ok(bg(1), "the second")
    ok(bg(2), "the underline")
    ok(not bg(4), "a paragraph without an underline is text")
    r.disable(buf)
  end
end
