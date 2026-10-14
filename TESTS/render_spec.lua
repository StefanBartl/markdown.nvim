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

  -- config
  local cfgm = require("markdown.config")
  local sn = vim.notify
  vim.notify = function() end
  cfgm.setup({ render = { margin = 2.5, headings = { icons = "x" }, bogus = 1 } })
  eq(cfgm.get().render.margin, r.DEFAULTS.margin, "a fractional margin is refused")
  eq(#cfgm.get().render.headings.icons, 6, "icons must be a list of strings")
  cfgm.setup({ render = { bullets = { icons = { "-", "+" } } } })
  eq(cfgm.get().render.bullets.icons[2], "+", "a valid override is kept")
  vim.notify = sn
  cfgm.setup({})
end
