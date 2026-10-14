-- TESTS/render_spec.lua -- native in-buffer rendering (core.render): what is hidden / drawn for a
-- line (pure), and the buffer side (extmarks only, text untouched, cursor row raw).
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local r = require("markdown.core.render")

  local function ctx(extra)
    return vim.tbl_extend("force", { width = 20, cfg = r.DEFAULTS }, extra or {})
  end
  local function marks(line, extra) return r.line_marks(line, ctx(extra)) end
  local function find(ms, pred)
    for _, m in ipairs(ms) do
      if pred(m) then return m end
    end
  end

  -- ───────────── headings ─────────────
  local h2 = marks("## Title")
  local icon = find(h2, function(m) return m.opts.virt_text ~= nil end)
  eq(icon.opts.virt_text[1][1], "○ ", "H2 icon")
  eq(icon.opts.end_col, 3, "the hashes and the space are hidden")
  eq(icon.opts.conceal, "", "concealed, replaced by the icon")
  ok(
    find(h2, function(m) return m.opts.line_hl_group == "MarkdownRenderH2Bg" end),
    "background line"
  )
  eq(#marks("#nospace"), 0, "no space, no heading")
  eq(#marks("####### seven"), 0, "seven hashes are no heading")

  -- ───────────── bullets / checkboxes ─────────────
  eq(marks("- item")[1].opts.conceal, "•", "bullet level 1")
  eq(marks("  - item")[1].opts.conceal, "◦", "bullet level 2")
  eq(marks("    * item")[1].opts.conceal, "▪", "bullet level 3")
  local todo = marks("- [ ] todo")
  ok(
    find(
      todo,
      function(m) return m.opts.conceal == "☐" and m.col == 2 and m.opts.end_col == 5 end
    ),
    "unchecked"
  )
  ok(find(marks("- [x] done"), function(m) return m.opts.conceal == "☑" end), "checked")
  ok(find(marks("- [-] part"), function(m) return m.opts.conceal == "◐" end), "partial")
  eq(#marks("-nospace"), 0, "no space, no bullet")
  eq(#marks("1. ordered"), 0, "ordered lists are left alone")

  -- ───────────── rules ─────────────
  local rule = marks("---")[1]
  eq(rule.opts.virt_text[1][1], ("─"):rep(20), "a rule fills the width")
  eq(#marks("***"), 1, "stars")
  eq(#marks("- - -"), 1, "spaced dashes are a rule, not a bullet")
  eq(#marks("---", { prev = "some text" }), 0, "under text it is a setext underline, not a rule")
  eq(#marks("--"), 0, "two are not enough")

  -- ───────────── quotes / callouts ─────────────
  local q = marks("> quote")
  eq(q[1].opts.conceal, "▎", "quote marker")
  eq(#marks(">> deep"), 2, "one marker per level")
  local co = marks("> [!WARNING] careful")
  local label = find(co, function(m) return m.opts.virt_text ~= nil end)
  eq(label.opts.virt_text[1][1], "▲ Warning", "callout label")
  eq(#marks("> [!UNKNOWN] x"), 1, "an unknown callout is a plain quote")

  -- ───────────── inline ─────────────
  local inl = marks("a `code` b")
  eq(#inl, 3, "code span: two backticks and the text")
  ok(find(inl, function(m) return m.opts.hl_group == "MarkdownRenderCode" end), "code highlight")
  local link = marks("see [text](http://x) now")
  ok(
    find(link, function(m) return m.col == 4 and m.opts.end_col == 5 and m.opts.conceal == "" end),
    "[ hidden"
  )
  ok(
    find(link, function(m) return m.opts.hl_group == "MarkdownRenderLink" end),
    "link text highlighted"
  )
  ok(
    find(link, function(m) return m.opts.conceal == "" and m.opts.end_col == 20 end),
    "](url) hidden"
  )
  ok(find(marks("![alt](a.png)"), function(m) return m.opts.conceal == "▣" end), "image marker")
  eq(#marks("`[not](a)`"), 3, "no link inside a code span")
  eq(#marks("| `c` | [d](u) |"), 0, "table rows are left to the table grid")
  ok(
    #marks("| `c` | [d](u) |", { grid = false }) > 0,
    "without a grid the table rows get the inline marks"
  )

  -- links: a badge, parentheses in the url, an escaped bracket; code spans: runs of equal length
  local badge = "[![build](a.svg)](http://x)"
  local bs, be = r._link_at(badge, 1)
  eq(bs .. "-" .. be, "1-" .. #badge, "a badge is one link")
  local paren = "[a](http://x/(y)) z"
  local ps, pe = r._link_at(paren, 1)
  eq(pe, #"[a](http://x/(y))", "balanced parentheses stay in the url")
  eq(r._link_at("\\[not](x)", 1), nil, "an escaped bracket is no link")
  eq(#marks("x `` y `z`"), 3, "an unpaired backtick run does not hide a later span")
  local run = find(
    marks("a ``b`c`` d"),
    function(m) return m.opts.hl_group == "MarkdownRenderCode" end
  )
  eq(run.opts.end_col - run.col, 3, "the closing run has the length of the opening one: b`c")
  eq(ps, 1, "link starts at the bracket")

  -- `---` is a rule under a heading, list item, quote or fence, only text makes it a setext line
  eq(#marks("---", { prev = "# Title" }), 1, "rule under a heading")
  eq(#marks("---", { prev = "- item" }), 1, "rule under a list item")
  eq(#marks("---", { prev = "> quote" }), 1, "rule under a quote")
  eq(#marks("---", { prev = "```" }), 1, "rule under a fence")

  -- ───────────── code blocks, front matter ─────────────
  local roles, langs = r.roles({ "---", "a: 1", "---", "```lua", "x", "```", "y" })
  eq(roles[1] .. roles[3], "frontfront", "front matter")
  eq(roles[4] .. roles[5] .. roles[6], "openinclose", "fence roles")
  eq(langs[4], "lua", "language")
  eq(roles[7], nil, "text after the block")
  local open = marks("```lua", { role = "open", lang = "lua" })
  ok(
    find(open, function(m) return m.opts.line_hl_group == "MarkdownRenderCodeBg" end),
    "code background"
  )
  ok(
    find(open, function(m) return m.opts.virt_text and m.opts.virt_text[1][1] == "lua" end),
    "language label"
  )
  eq(#marks("# not a heading in code", { role = "in" }), 1, "inside code only the background")
  eq(#marks("- x", { role = "front" }), 0, "front matter is left alone")
  local r2 = r.roles({ "````", "```lua", "x", "````", "# H" })
  eq(r2[2], "in", "a shorter inner fence is code")
  eq(r2[5], nil, "and the longer one closes")

  -- ───────────── config switches ─────────────
  local off = vim.deepcopy(r.DEFAULTS)
  off.headings.enabled = false
  off.bullets.enabled = false
  eq(#r.line_marks("# H", { width = 20, cfg = off }), 0, "headings off")
  eq(#r.line_marks("- b", { width = 20, cfg = off }), 0, "bullets off")

  -- ───────────── buffer ─────────────
  local function rows_of(b, n)
    local set = {}
    for _, m2 in ipairs(vim.api.nvim_buf_get_extmarks(b, n, 0, -1, {})) do
      set[m2[2] + 1] = true
    end
    return set
  end
  local ns = vim.api.nvim_create_namespace("markdown_render")
  local buf = H.scratch("markdown")
  local doc = { "# T", "", "- [ ] a", "", "> q", "", "text `c`", "", "last" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, doc)
  vim.api.nvim_win_set_cursor(0, { 9, 0 })
  vim.wo.conceallevel = 0
  r.enable(buf)
  ok(r.is_enabled(buf), "enabled")
  eq(vim.wo.conceallevel, 2, "conceallevel raised")
  local function rows()
    local set = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})) do
      set[m[2] + 1] = true
    end
    return set
  end
  local drawn = rows()
  ok(
    drawn[1] and drawn[3] and drawn[5] and drawn[7],
    "heading, checkbox, quote and code span are drawn"
  )
  ok(not drawn[9], "the cursor row shows its text")
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], "# T", "the text is untouched")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  drawn = rows()
  ok(not drawn[1], "the cursor row is raw after the move")
  ok(drawn[3], "other rows stay drawn")
  r.disable(buf)
  eq(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}), 0, "disable removes every extmark")
  eq(vim.wo.conceallevel, 0, "conceallevel is back")
  ok(not r.is_enabled(buf), "disabled")
  eq(r.toggle(buf), true, "toggle on")
  eq(r.toggle(buf), false, "toggle off")
  r.enable(0)
  ok(r.is_enabled(buf), "enable(0) is the current buffer")
  r.disable(0)

  -- only the rows around the window are drawn
  local big = H.scratch("markdown")
  local lines = {}
  for i = 1, 3000 do
    lines[i] = "# H" .. i
  end
  vim.api.nvim_buf_set_lines(big, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  r.enable(big)
  local count = #vim.api.nvim_buf_get_extmarks(big, ns, 0, -1, {})
  ok(count < 600, "a long file draws only the rows around the window (" .. count .. " marks)")
  r.disable(big)

  -- a table row: drawn inline without a grid, left alone while the grid owns the buffer
  local tb = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(tb, 0, -1, false, { "| `a` | b |", "|---|---|", "| 1 | 2 |", "", "x" })
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  r.enable(tb)
  ok(rows_of(tb, ns)[1], "no grid: the inline code in a table row is drawn")
  r.disable(tb)
  local grid = require("markdown.core.table_render")
  grid.enable(tb)
  r.enable(tb)
  local own = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(tb, ns, 0, -1, {})) do
    own[m[2] + 1] = true
  end
  ok(not own[1], "the grid owns the table rows")
  r.disable(tb)
  grid.disable(tb)

  -- two windows on one buffer, one at the top and one at the bottom: the rows between them are not drawn
  vim.cmd("split")
  local second = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(second, big)
  vim.api.nvim_win_set_cursor(second, { 3000, 0 })
  vim.cmd("normal! zb")
  vim.api.nvim_set_current_win(vim.fn.win_getid(vim.fn.winnr("#")))
  vim.api.nvim_win_set_buf(0, big)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("normal! zt")
  r.enable(big)
  count = #vim.api.nvim_buf_get_extmarks(big, ns, 0, -1, {})
  ok(
    count > 0 and count < 600,
    "two distant windows draw their own rows only (" .. count .. " marks)"
  )
  r.disable(big)
  vim.cmd("only")

  -- a window that leaves the buffer and comes back must not take the raised level for its own
  do
    local guard = require("markdown.core.conceal_guard")
    local a = H.scratch("markdown")
    local b = H.scratch("markdown")
    vim.api.nvim_set_current_buf(a)
    vim.wo.conceallevel = 0
    guard.apply("t", a)
    eq(vim.wo.conceallevel, 2, "guard raises the level")
    vim.api.nvim_set_current_buf(b)
    guard.apply("t", a) -- what the scheduled BufWinLeave handler does: the window has left
    eq(vim.wo.conceallevel, 0, "the window got its level back when it left")
    vim.api.nvim_set_current_buf(a) -- Neovim restores the raised value it remembered for `a`
    guard.apply("t", a)
    guard.restore("t", a)
    eq(vim.wo.conceallevel, 0, "and still has its own level after coming back")
  end

  -- ───────────── review round 3 ─────────────
  -- a badge: the inner image is marked too, not only the outer link
  do
    local bm = marks("[![build](a.svg)](http://x)")
    ok(
      find(bm, function(m) return m.opts.conceal == "▣" end),
      "the image inside a badge gets its marker"
    )
    eq(#bm, 6, "outer link: 3 marks, inner image: 3 marks")
  end

  -- an escaped "!" is a literal "!" in front of a plain link
  do
    local s, e, bang = r._link_at("\\![a](b)", 1)
    eq(s .. "-" .. e .. "-" .. bang, "3-8-", "the link after \\! is found, as a link")
    ok(#marks("\\![a](b)") > 0, "and drawn")
    eq(r._link_at("\\\\![a](b)", 1), 3, "an even run of backslashes does not escape the !")
  end

  -- `- - -` under a paragraph is a thematic break (a setext underline has no inner spaces)
  do
    local sp = marks("- - -", { prev = "text" })
    ok(
      find(sp, function(m) return m.opts.virt_text ~= nil end),
      "a spaced rule under text is drawn as a rule"
    )
    eq(#marks("---", { prev = "text" }), 0, "a plain run of dashes under text stays a setext line")
  end

  -- the cursor row of a window that closes is drawn again
  do
    local cb = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(cb, 0, -1, false, { "# H", "", "- a", "", "`x`", "", "> q" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    r.enable(cb)
    vim.cmd("split")
    local w2 = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(w2, { 5, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = cb })
    ok(not rows_of(cb, ns)[5], "the second window's cursor row is raw")
    vim.api.nvim_win_close(w2, true)
    vim.wait(1000, function() return rows_of(cb, ns)[5] end, 20)
    ok(rows_of(cb, ns)[5], "closing that window draws its row again")
    -- the same when the window goes to another buffer (no WinEnter then)
    vim.cmd("split")
    local w3 = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(w3, { 5, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = cb })
    ok(not rows_of(cb, ns)[5], "a window on the same buffer holds the cursor row again")
    vim.api.nvim_win_set_buf(w3, H.scratch("markdown"))
    vim.wait(1000, function() return rows_of(cb, ns)[5] end, 20)
    ok(rows_of(cb, ns)[5], "a window that switched buffer releases its cursor row")
    r.disable(cb)
    vim.cmd("only")
  end

  -- a floating window closed from outside changes no layout: WinClosed redraws its cursor row
  do
    local fb = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(fb, 0, -1, false, { "# H", "", "- a", "", "`x`", "", "> q" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    r.enable(fb)
    local fl = vim.api.nvim_open_win(
      fb,
      false,
      { relative = "editor", row = 2, col = 2, width = 20, height = 5 }
    )
    vim.api.nvim_win_set_cursor(fl, { 5, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = fb })
    ok(not rows_of(fb, ns)[5], "the floating window's cursor row is raw")
    vim.api.nvim_win_close(fl, true)
    vim.wait(1000, function() return rows_of(fb, ns)[5] end, 20)
    ok(rows_of(fb, ns)[5], "closing the floating window draws its row again")
    r.disable(fb)
  end

  -- a link after a badge is marked once: the inner scan of the badge stops at its end
  eq(#marks("[![a](b)](c) [d](e)"), 9, "badge 3 + inner image 3 + sibling link 3")

  -- conceal_guard: the remembered original of a left window is used up once it is back
  do
    local guard = require("markdown.core.conceal_guard")
    local a, b = H.scratch("markdown"), H.scratch("markdown")
    vim.api.nvim_set_current_buf(a)
    vim.wo.conceallevel = 0
    guard.apply("t5", a)
    vim.api.nvim_set_current_buf(b)
    guard.apply("t5", a) -- the window left: its original 0 is remembered
    vim.api.nvim_set_current_buf(a)
    guard.apply("t5", a)
    guard.restore("t5", a)
    eq(vim.wo.conceallevel, 0, "back to the original after the round trip")
    vim.wo.conceallevel = 2
    guard.apply("t5", a)
    guard.restore("t5", a)
    eq(vim.wo.conceallevel, 2, "a 2 the user set afterwards is kept (the old 0 is not replayed)")
  end

  -- the text area width changes with `number`: the rules are fitted again
  do
    local nb = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(nb, 0, -1, false, { "# H", "", "---", "", "x" })
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    vim.wo.number = false
    r.enable(nb)
    local function rule_width()
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(nb, ns, 0, -1, { details = true })) do
        local vt = m[4].virt_text
        if vt and vt[1][1]:find("─", 1, true) then return vim.fn.strchars(vt[1][1]) end
      end
    end
    local before = rule_width()
    vim.wo.number = true
    -- the harness runs the spec inside an autocommand: Neovim does not nest OptionSet there
    vim.api.nvim_exec_autocmds("OptionSet", { pattern = "number" })
    vim.wait(1000, function() return rule_width() ~= before end, 20)
    ok(
      rule_width() < before,
      ("the rule got narrower after :set number (%s -> %s)"):format(before, tostring(rule_width()))
    )
    r.disable(nb)
    vim.wo.number = false
  end

  -- conceal_guard: a window that went to another buffer keeps that buffer's own level
  do
    local guard = require("markdown.core.conceal_guard")
    local a, b = H.scratch("markdown"), H.scratch("markdown")
    vim.api.nvim_set_current_buf(b)
    vim.wo.conceallevel = 3
    vim.api.nvim_set_current_buf(a)
    vim.wo.conceallevel = 0
    guard.apply("t2", a)
    vim.api.nvim_set_current_buf(b)
    guard.apply("t2", a) -- the scheduled BufWinLeave handler
    eq(vim.wo.conceallevel, 3, "the other buffer's own level is not overwritten")
    guard.restore("t2", a)
    vim.api.nvim_set_current_buf(a)
  end

  -- conceal_guard: a level the user sets after render was switched off is theirs
  do
    local guard = require("markdown.core.conceal_guard")
    local a = H.scratch("markdown")
    vim.api.nvim_set_current_buf(a)
    vim.wo.conceallevel = 0
    guard.apply("t3", a)
    guard.restore("t3", a)
    eq(vim.wo.conceallevel, 0, "first round: back to 0")
    vim.wo.conceallevel = 2
    guard.apply("t3", a)
    guard.restore("t3", a)
    eq(vim.wo.conceallevel, 2, "second round: the 2 the user set is kept")
  end

  -- config
  local cfgm = require("markdown.config")
  local sn = vim.notify
  vim.notify = function() end
  cfgm.setup({ render = { margin = 2.5, headings = { icons = "x" }, bogus = 1 } })
  eq(cfgm.get().render.margin, r.DEFAULTS.margin, "a fractional margin is refused")
  eq(#cfgm.get().render.headings.icons, 6, "icons must be a list of strings")
  cfgm.setup({ render = true })
  eq(cfgm.get().render.enabled, true, "render = true is the short form of enabled = true")
  eq(cfgm.get().render.margin, r.DEFAULTS.margin, "and keeps the other defaults")
  cfgm.setup({ render = false })
  eq(cfgm.get().render.enabled, false, "render = false is the short form of enabled = false")
  eq(cfgm.get().render.margin, r.DEFAULTS.margin, "and keeps the other defaults too")
  cfgm.setup({ render = "yes" })
  eq(cfgm.get().render.enabled, r.DEFAULTS.enabled, "a string is refused and the default is used")
  cfgm.setup({ render = { bullets = { icons = { "-", "+" } } } })
  eq(cfgm.get().render.bullets.icons[2], "+", "a valid override is kept")
  vim.notify = sn
  cfgm.setup({})
end
