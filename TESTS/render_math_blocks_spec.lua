-- TESTS/render_math_blocks_spec.lua -- a `$$` ... `$$` block over several lines in the native renderer: the roles say where
-- it is, the rows are coloured as math, the dollars go, and nothing inside is emphasis or a link.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local r = require("markdown.core.render")

  local function row(line, role, inline)
    local cfg = vim.tbl_deep_extend("force", r.DEFAULTS, inline and { inline = inline } or {})
    return r.line_marks(line, { width = 20, cfg = cfg, role = role })
  end
  local function count(ms, group)
    local n = 0
    for _, m in ipairs(ms) do
      if m.opts.hl_group == group then n = n + 1 end
    end
    return n
  end

  -- the roles
  local roles = r.roles({ "a", "$$", "x = **y**", "$$", "b" })
  eq(roles[2], "mstart", "the row that opens it")
  eq(roles[3], "min", "the rows inside")
  eq(roles[4], "mend", "the row that closes it")
  eq(roles[5], nil, "the row after is text")
  eq(
    r.roles({ "$$ x = 1", "y", "z $$" })[3],
    "mend",
    "the formula may start on the opening row and end on the closing one"
  )
  eq(r.roles({ "$$x$$", "text" })[1], nil, "a block on one row is inline math, not a block")
  eq(r.roles({ "    $$", "text" })[1], nil, "four columns of indent: code, no block")
  eq(r.roles({ "  $$", "x" })[1], "mstart", "up to three columns are fine")
  eq(
    r.roles({ "$$", "x", "y" })[3],
    "min",
    "an unclosed block runs to the end, like an unclosed fence"
  )
  local fenced = r.roles({ "```", "$$", "```", "text" })
  eq(fenced[2], "in", "a `$$` inside a fence is code")
  eq(fenced[4], nil, "and opens nothing")
  local inmath = r.roles({ "$$", "```", "$$", "text" })
  eq(inmath[2], "min", "a fence marker inside a math block is math")
  eq(inmath[4], nil, "and the text after the block is text")
  local commented = r.roles({ "<!--", "$$", "-->", "text" })
  eq(commented[2], "cin", "a `$$` inside a comment is comment")
  eq(commented[4], nil, "and the text after it is text")
  eq(r._math_open(roles, 3), true, "a block is open below its opening row")
  eq(r._math_open(roles, 5), false, "and not below the closing row")

  -- the rows
  local start = row("$$", "mstart")
  eq(start[1].opts.conceal, "", "the opening dollars go")
  eq(start[1].col, 0)
  eq(start[1].opts.end_col, 2)
  local first = row("$$ x = 1", "mstart")
  eq(count(first, "MarkdownRenderMath"), 1, "a formula on the opening row is coloured")
  eq(first[2].col, 2)
  eq(first[2].opts.end_col, 8)
  local inside = row("x = **y** + [a](b)", "min")
  eq(#inside, 1, "inside: one mark over the whole row, no emphasis, no link")
  eq(inside[1].opts.hl_group, "MarkdownRenderMath")
  eq(inside[1].opts.end_col, 18, "to the end of the row")
  local last = row("z $$ see **bold**", "mend")
  eq(count(last, "MarkdownRenderMath"), 1, "the closing row is coloured up to the closing dollars")
  eq(last[1].opts.end_col, 2)
  eq(count(last, "MarkdownRenderBold"), 1, "and what stands after them is inline text")
  eq(count(row("x **y** $$", "mend"), "MarkdownRenderBold"), 0, "what stands before them is not")

  -- the switches
  eq(
    #row("x **y**", "min", { math_blocks = false }) > 0,
    true,
    "math_blocks = false: the rows are plain text"
  )
  eq(
    count(row("x **y**", "min", { math_blocks = false }), "MarkdownRenderBold"),
    1,
    "with their emphasis"
  )
  eq(
    count(row("x", "min", { math = false }), "MarkdownRenderMath"),
    0,
    "math = false turns the blocks off too"
  )
  eq(
    count(row("x", "min", { enabled = false }), "MarkdownRenderMath"),
    0,
    "and so does inline.enabled = false"
  )

  -- the buffer: the block is drawn, and an edit below it updates the rows from there on
  local ns = vim.api.nvim_create_namespace("markdown_render")
  local buf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    { "intro", "$$", "a = b", "$$", "outro **bold**", "", "end" }
  )
  vim.api.nvim_win_set_cursor(0, { 7, 0 })
  r.enable(buf)
  r.refresh(buf, true)
  local function math_rows()
    local set = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      if m[4].hl_group == "MarkdownRenderMath" then set[m[2] + 1] = true end
    end
    return set
  end
  local drawn = math_rows()
  eq(drawn[3], true, "the row inside is coloured as math")
  eq(drawn[5], nil, "the row after the block is not")
  -- delete the closing `$$`: the block now runs to the end
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "no dollars" })
  r.refresh(buf, false)
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  r.refresh(buf, false)
  drawn = math_rows()
  eq(drawn[5], true, "without a closing `$$` the rows below are math (like an unclosed fence)")
  -- put it back: the rows below are text again
  vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "$$" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  r.refresh(buf, false)
  drawn = math_rows()
  eq(drawn[5], nil, "closing it again ends the block")
  r.disable(buf)
end
