-- TESTS/render_emphasis_spec.lua -- bold, italic, both and strikethrough in the native renderer (pure marks): the markers are
-- hidden, the text between them is highlighted, and what is not emphasis stays alone.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local r = require("markdown.core.render")

  local function marks(line, inline)
    local cfg = vim.tbl_deep_extend("force", r.DEFAULTS, inline and { inline = inline } or {})
    return r.line_marks(line, { width = 20, cfg = cfg })
  end
  local function hl(ms, group)
    local found = {}
    for _, m in ipairs(ms) do
      if m.opts.hl_group == group then found[#found + 1] = m end
    end
    return found
  end
  local function hidden(ms)
    local found = {}
    for _, m in ipairs(ms) do
      if m.opts.conceal == "" then found[#found + 1] = m.col .. "-" .. m.opts.end_col end
    end
    return table.concat(found, ",")
  end

  -- bold: both spellings, markers hidden, the text between highlighted
  local bold = marks("a **bold** b")
  eq(#hl(bold, "MarkdownRenderBold"), 1, "**bold** is highlighted")
  eq(hl(bold, "MarkdownRenderBold")[1].col, 4, "from after the opening markers")
  eq(hl(bold, "MarkdownRenderBold")[1].opts.end_col, 8, "to before the closing ones")
  eq(hidden(bold), "2-4,8-10", "and both marker pairs are hidden")
  eq(#hl(marks("a __bold__ b"), "MarkdownRenderBold"), 1, "__bold__ too")

  -- italic and both
  eq(#hl(marks("a *it* b"), "MarkdownRenderItalic"), 1, "*italic*")
  eq(#hl(marks("a _it_ b"), "MarkdownRenderItalic"), 1, "_italic_")
  eq(#hl(marks("a ***both*** b"), "MarkdownRenderBoldItalic"), 1, "***both***")
  eq(hidden(marks("a *it* b")), "2-3,5-6", "one marker each side")

  -- strike
  eq(#hl(marks("a ~~gone~~ b"), "MarkdownRenderStrike"), 1, "~~strike~~")
  eq(#marks("a ~one~ b"), 0, "a single tilde is no strike")

  -- nesting and several in a line
  local nested = marks("**bold *it* x**")
  eq(#hl(nested, "MarkdownRenderBold"), 1, "the bold of a nested pair")
  eq(#hl(nested, "MarkdownRenderItalic"), 1, "and the italic inside it")
  eq(#hl(marks("*a* and *b*"), "MarkdownRenderItalic"), 2, "two italics in one line")

  -- what is not emphasis
  eq(#marks("a * b * c"), 0, "stars with spaces around them are text")
  eq(#marks("snake_case_name"), 0, "an underscore inside a word is text")
  eq(#marks("2 * 3 * 4"), 0, "a product is text")
  eq(#marks("**unclosed"), 0, "an unclosed run stays as typed")
  eq(#marks("**a*"), 0, "runs of different lengths do not pair")
  local bs = string.char(92)
  eq(#marks(bs .. "*not it" .. bs .. "*"), 0, "a backslash escapes the run")
  eq(#hl(marks("`**code**`"), "MarkdownRenderBold"), 0, "nothing inside a code span")
  eq(
    #hl(marks("[x](http://a/__init__/b)"), "MarkdownRenderItalic"),
    0,
    "nothing in the address of a link"
  )
  ok(
    #hl(marks("[**bold** text](http://a)"), "MarkdownRenderBold") == 1,
    "but the text of a link may be emphasised"
  )
  eq(marks("* item")[1].opts.conceal, "•", "a star bullet is still a bullet")

  -- the switches
  eq(#hl(marks("**b** *i* ~~s~~", { bold = false }), "MarkdownRenderBold"), 0, "bold = false")
  eq(#hl(marks("**b** *i* ~~s~~", { italic = false }), "MarkdownRenderItalic"), 0, "italic = false")
  eq(#hl(marks("**b** *i* ~~s~~", { strike = false }), "MarkdownRenderStrike"), 0, "strike = false")
  eq(
    #hl(marks("***x***", { italic = false }), "MarkdownRenderBoldItalic"),
    0,
    "both needs both switches"
  )
end
