-- TESTS/render_comments_spec.lua -- an HTML comment on one line is dimmed in the native renderer, and nothing inside it is
-- drawn as emphasis or a link.
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

  local one = marks("a <!-- note --> b")
  eq(count(one, "MarkdownRenderComment"), 1, "the comment is dimmed")
  eq(one[1].col, 2, "from its opening")
  eq(one[1].opts.end_col, 15, "to the end of its closing")
  eq(count(marks("<!-- a --> x <!-- b -->"), "MarkdownRenderComment"), 2, "two in one line")

  -- nothing inside is markup
  eq(count(marks("<!-- **not bold** -->"), "MarkdownRenderBold"), 0, "no emphasis inside")
  eq(count(marks("<!-- [x](http://a) -->"), "MarkdownRenderLink"), 0, "no link inside")
  eq(count(marks("**b** <!-- c -->"), "MarkdownRenderBold"), 1, "but the rest of the line is drawn")

  -- not a comment
  eq(#marks("<!-- never closed"), 0, "an unclosed comment is left alone here")
  eq(count(marks("`<!-- code -->`"), "MarkdownRenderComment"), 0, "not inside a code span")
  eq(
    count(marks("a <!-- c -->", { comments = false }), "MarkdownRenderComment"),
    0,
    "comments = false"
  )
end
