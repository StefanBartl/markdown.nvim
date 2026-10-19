-- TESTS/render_footnotes_spec.lua -- `[^id]` references and `[^id]:` definitions in the native renderer: the brackets and the
-- caret are hidden, the id gets a link colour; code spans, escapes and links are left alone.
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

  local ref = marks("a[^1] b")
  eq(count(ref, "MarkdownRenderFootnote"), 1, "the id is coloured")
  local hid = {}
  for _, m in ipairs(ref) do
    if m.opts.conceal then hid[#hid + 1] = m.col .. "-" .. m.opts.end_col end
  end
  eq(table.concat(hid, ","), "1-3,4-5", "`[^` and `]` are hidden")
  eq(
    count(marks("[^note]: the text"), "MarkdownRenderFootnote"),
    1,
    "a definition is drawn the same way"
  )
  eq(count(marks("two[^a][^b]"), "MarkdownRenderFootnote"), 2, "two in a row")

  eq(count(marks("`[^1]`"), "MarkdownRenderFootnote"), 0, "not inside a code span")
  eq(
    count(marks("a " .. string.char(92) .. "[^1]"), "MarkdownRenderFootnote"),
    0,
    "an escaped bracket is text"
  )
  eq(
    count(marks("[^1](http://x)"), "MarkdownRenderFootnote"),
    0,
    "a link target after it makes it a link"
  )
  eq(count(marks("[^a b]"), "MarkdownRenderFootnote"), 0, "an id has no space")
  eq(
    count(marks("a[^1]", { footnotes = false }), "MarkdownRenderFootnote"),
    0,
    "the switch turns it off"
  )
end
