-- TESTS/render_ordered_spec.lua -- ordered list items in the native renderer: the number is coloured, a checkbox after it is
-- drawn like one after a bullet, and what is no list item is left alone.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local r = require("markdown.core.render")

  local function marks(line, extra)
    local cfg = vim.tbl_deep_extend("force", r.DEFAULTS, extra or {})
    return r.line_marks(line, { width = 20, cfg = cfg })
  end
  local function find(ms, pred)
    for _, m in ipairs(ms) do
      if pred(m) then return m end
    end
  end

  local one = marks("1. item")
  local num = find(one, function(m) return m.opts.hl_group == "MarkdownRenderOrdered" end)
  ok(num ~= nil, "the number gets its group")
  eq(num.col, 0, "from the first column")
  eq(num.opts.end_col, 2, "over the number and the dot")
  eq(
    find(marks("12) item"), function(m) return m.opts.hl_group == "MarkdownRenderOrdered" end).opts.end_col,
    3,
    "two digits and a parenthesis"
  )
  eq(
    find(marks("   3. item"), function(m) return m.opts.hl_group == "MarkdownRenderOrdered" end).col,
    3,
    "an indented item"
  )

  -- a checkbox after the number
  local todo = marks("1. [x] done")
  ok(find(todo, function(m) return m.opts.conceal == "☑" end), "the checkbox is drawn")
  ok(
    find(todo, function(m) return m.opts.hl_group == "MarkdownRenderOrdered" end),
    "and the number coloured"
  )

  -- not list items
  eq(#marks("1.item"), 0, "no space, no item")
  eq(#marks("2024 was a year"), 0, "a number without a dot is text")
  eq(#marks("> 1. quoted"), 1, "inside a quote only the quote marker is drawn")
  eq(#marks("# 1. heading", {}) > 0, true, "a heading stays a heading")
  ok(
    not find(
      marks("# 1. heading"),
      function(m) return m.opts.hl_group == "MarkdownRenderOrdered" end
    ),
    "and its number is not a list number"
  )

  -- the switch
  ok(
    not find(
      marks("1. item", { ordered = { enabled = false } }),
      function(m) return m.opts.hl_group == "MarkdownRenderOrdered" end
    ),
    "ordered.enabled = false"
  )
end
