-- TESTS/render_math_spec.lua -- `$x$` and `$$x$$` on one line in the native renderer: the dollars are hidden, the formula
-- is coloured and is not emphasis; prices, escapes and code spans are not math.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local r = require("markdown.core.render")

  local function marks(line, inline)
    local cfg = vim.tbl_deep_extend("force", r.DEFAULTS, inline and { inline = inline } or {})
    return r.line_marks(line, { width = 20, cfg = cfg })
  end
  local function count(ms, group)
    local n = 0
    for _, m in ipairs(ms) do
      if m.opts.hl_group == group then n = n + 1 end
    end
    return n
  end

  local one = marks("a $x+1$ b")
  eq(count(one, "MarkdownRenderMath"), 1, "the formula is coloured")
  local span
  for _, m in ipairs(one) do
    if m.opts.hl_group == "MarkdownRenderMath" then span = m.col .. "-" .. m.opts.end_col end
  end
  eq(span, "3-6", "between the dollars")
  local hid = {}
  for _, m in ipairs(one) do
    if m.opts.conceal then hid[#hid + 1] = m.col .. "-" .. m.opts.end_col end
  end
  eq(table.concat(hid, ","), "2-3,6-7", "both dollars are hidden")
  eq(count(marks("$$a*b*c$$"), "MarkdownRenderMath"), 1, "a display pair on one line")
  eq(count(marks("$$a*b*c$$"), "MarkdownRenderItalic"), 0, "no emphasis inside")
  eq(count(marks("$a$ and $b$"), "MarkdownRenderMath"), 2, "two formulas")

  eq(count(marks("costs $5 and $6"), "MarkdownRenderMath"), 0, "two prices are not a formula")
  eq(count(marks("$5 or$6"), "MarkdownRenderMath"), 0, "a closer followed by a digit is a price")
  eq(count(marks("$ x $"), "MarkdownRenderMath"), 0, "a space after the opener")
  eq(count(marks("`$x$`"), "MarkdownRenderMath"), 0, "not inside a code span")
  eq(count(marks(string.char(92) .. "$x$"), "MarkdownRenderMath"), 0, "an escaped dollar is text")
  eq(count(marks("$x"), "MarkdownRenderMath"), 0, "an unpaired dollar")
  eq(count(marks("a $x$", { math = false }), "MarkdownRenderMath"), 0, "the switch turns it off")
end
