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
end
