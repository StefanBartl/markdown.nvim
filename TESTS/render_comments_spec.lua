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

  -- a comment over several lines: the roles say where it is, and the rows are dimmed
  local roles = r.roles({ "a", "<!-- start", "inside", "end -->", "b", "`<!--` in code", "c" })
  eq(roles[2], "cstart", "the row that opens it")
  eq(roles[3], "cin", "the rows inside")
  eq(roles[4], "cend", "the row that closes it")
  eq(roles[5], nil, "the row after is text")
  eq(roles[6], nil, "a marker in a code span opens nothing")
  eq(roles[7], nil, "so the rest of the document stays text")
  local function row(line, role)
    return r.line_marks(line, { width = 20, cfg = r.DEFAULTS, role = role })
  end
  local cin = row("a **b** c", "cin")
  eq(#cin, 1, "inside: one mark over the whole row, no emphasis")
  eq(cin[1].opts.end_col, 9, "to the end of the row")
  local cstart = row("x <!-- start", "cstart")
  eq(cstart[1].col, 2, "the opening row is dimmed from the marker")
  local cend = row("end --> after", "cend")
  eq(cend[1].col, 0, "the closing row from its start")
  eq(cend[1].opts.end_col, 7, "to the end of the closing marker")
  local fenced = r.roles({ "```", "<!-- not a comment", "```", "text" })
  eq(fenced[2], "in", "a marker inside a fence is code")
  eq(fenced[4], nil, "and opens nothing")
  local commented = r.roles({ "<!--", "```", "-->", "text" })
  eq(commented[2], "cin", "a fence marker inside a comment is comment")
  eq(commented[4], nil, "and the text after it is text")

  -- not a comment
  eq(#marks("<!-- never closed"), 0, "an unclosed comment is left alone here")
  eq(count(marks("`<!-- code -->`"), "MarkdownRenderComment"), 0, "not inside a code span")
  eq(
    count(marks("a <!-- c -->", { comments = false }), "MarkdownRenderComment"),
    0,
    "comments = false"
  )
end
