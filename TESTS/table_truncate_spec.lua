-- TESTS/table_truncate_spec.lua -- display-only truncation of over-wide table cells
-- (core.table_truncate): conceal ranges are computed so every cell of a truncated
-- column shows the same number of columns; the buffer text is never changed.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local tt = require("markdown.core.table_truncate")
  local lib = require("lib.nvim.markdown.table")

  local SRC = {
    "| Syntax | Meaning | Example |",
    "|---|---|---|",
    "| `a` | stdout of the left command becomes stdin of the right one | `ls` |",
    "| `b` | short | `npx vitest run --reporter verbose --bail` |",
  }

  --- Shown text of `line` after applying its conceal ranges.
  local function shown(line, marks)
    local out, pos = {}, 1
    local ms = vim.deepcopy(marks or {})
    table.sort(ms, function(a, b) return a.s < b.s end)
    for _, m in ipairs(ms) do
      out[#out + 1] = line:sub(pos, m.s - 1) .. m.text
      pos = m.e + 1
    end
    out[#out + 1] = line:sub(pos)
    return table.concat(out)
  end

  local lines = lib.format_lines(SRC)
  local marks = tt.compute(lines, { max = 20, marker = "…" })

  -- every row of the table is shown with the same width
  local width = vim.fn.strdisplaywidth(shown(lines[1], marks[1]))
  for i = 1, #lines do
    eq(
      vim.fn.strdisplaywidth(shown(lines[i], marks[i])),
      width,
      "row " .. i .. " has the common width"
    )
  end
  ok(
    shown(lines[3], marks[3]):find("left …", 1, true) ~= nil,
    "a long cell is cut with the marker"
  )
  ok(shown(lines[4], marks[4]):find("--r…", 1, true) ~= nil, "the code span is cut, too")
  -- a double-width character at the cut: the missing column is filled, rows keep one width
  local wide = lib.format_lines({
    "| A | B |",
    "|---|---|",
    "| 日本語日本語日本語日本語日本語 | x |",
    "| short | y |",
  })
  local wmarks = tt.compute(wide, { max = 8, marker = "…" })
  local wwidth = vim.fn.strdisplaywidth(shown(wide[1], wmarks[1]))
  for r = 1, #wide do
    eq(vim.fn.strdisplaywidth(shown(wide[r], wmarks[r])), wwidth, "wide chars: row " .. r)
  end

  -- a table inside a fenced code block is left alone
  local fenced = {
    "```",
    "| A | B |",
    "|---|---|",
    "| " .. string.rep("x", 60) .. " | y |",
    "```",
  }
  eq(next(tt.compute(fenced, { max = 10 })), nil, "no truncation inside a fence")

  -- config: the marker is one display column
  local cfgm = require("markdown.config")
  local saved_notify = vim.notify
  vim.notify = function() end
  cfgm.setup({ table = { truncate = { marker = "..." } } })
  eq(
    cfgm.get().table.truncate.marker,
    cfgm.DEFAULTS and "…" or "…",
    "a 3-column marker is refused"
  )
  vim.notify = saved_notify
  cfgm.setup({})

  for _, m in ipairs(marks[1]) do
    eq(m.text, "", "the header only loses padding, never text")
  end
  eq(lines[3], lib.format_lines(SRC)[3], "compute never changes the text")

  -- nothing wider than max -> no marks
  eq(next(tt.compute(lines, { max = 100 })), nil, "no marks when everything fits")

  -- the right-aligned / compact separator keeps its colon
  local long = string.rep("w", 50)
  local aligned = {
    "| A | " .. long .. " |",
    "| --- | " .. string.rep("-", 49) .. ": |",
    "| x | " .. long .. " |",
  }
  local m2 = tt.compute(aligned, { max = 10 })
  local sep = shown(aligned[2], m2[2])
  ok(sep:find("-: |$") ~= nil, "separator colon survives")
  eq(
    vim.fn.strdisplaywidth(sep) - 2, -- first column is "---" vs "A"
    vim.fn.strdisplaywidth(shown(aligned[1], m2[1])),
    "separator width follows the row"
  )

  -- render applies extmarks and does not touch the buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local before = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  require("markdown.config").setup({ table = { truncate = { max = 20 } } })
  ok(tt.render(buf) > 0, "render places conceal extmarks")
  local ns = vim.api.nvim_create_namespace("markdown_table_truncate")
  local ext = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  ok(#ext > 0 and ext[1][4].conceal ~= nil, "extmarks carry a conceal")
  eq(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
    before,
    "buffer text unchanged"
  )

  -- toggle sets conceallevel while on and restores it
  vim.wo.conceallevel = 0
  eq(tt.toggle(buf), true, "toggle turns on")
  eq(vim.wo.conceallevel, 2, "conceallevel raised to 2")
  eq(tt.toggle(buf), false, "toggle turns off")
  eq(vim.wo.conceallevel, 0, "conceallevel restored")
  eq(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}), 0, "extmarks cleared")

  -- 0 is the current buffer, as in the API (win_findbuf(0) finds no window)
  tt.enable(0)
  eq(vim.wo.conceallevel, 2, "enable(0) raises conceallevel in the current window")
  ok(tt.is_enabled(buf), "enable(0) is the state of the real buffer")
  -- clear(0) forgets the cache of the real buffer, so the next render draws again
  ok(tt.render(0) >= 0, "(render(0) runs)")
  local drawn = #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  ok(drawn > 0, "enable(0) drew the cut")
  tt.clear(0)
  eq(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}), 0, "clear(0) removed the marks")
  ok(tt.render(0) > 0, "render(0) after clear(0) draws again")
  eq(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}), drawn, "with the same marks")
  tt.disable(0)
  eq(vim.wo.conceallevel, 0, "disable(0) restores it")

  -- centered columns: a cut cell that is not the widest also loses its leading padding
  local centered = lib.format_lines(SRC, { header_align = "center", entry_align = "center" })
  local cm = tt.compute(centered, { max = 20, marker = "…" })
  local cwidth = vim.fn.strdisplaywidth(shown(centered[1], cm[1]))
  for i = 1, #centered do
    eq(
      vim.fn.strdisplaywidth(shown(centered[i], cm[i])),
      cwidth,
      "centered: row " .. i .. " has the common width"
    )
  end

  -- conceallevel is window-local: neither the global value nor a new window changes
  vim.go.conceallevel = 0
  vim.wo.conceallevel = 0
  tt.enable(buf)
  eq(vim.go.conceallevel, 0, "the global conceallevel is untouched")
  vim.cmd("new")
  eq(vim.wo.conceallevel, 0, "a window opened later starts at the global value")
  vim.cmd("close")
  tt.disable(buf)

  -- a re-render without an edit is skipped (stamp = changedtick + settings)
  tt.enable(buf)
  eq(tt.render(buf), 0, "nothing to redo while the text and the settings are unchanged")
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
  ok(tt.render(buf) > 0, "an edit renders again")
  tt.disable(buf)

  -- composing marks are not split from their base character
  local nfd = "e" .. string.char(204, 129) -- e + U+0301
  local text = string.rep(nfd, 12)
  local keep = select(
    2,
    next(
      tt.compute(
        { "| A |", "|---|", "| " .. text .. " |", "| " .. string.rep("w", 30) .. " |" },
        { max = 6 }
      )
    )
  )
  ok(keep ~= nil, "a line with composing marks is truncated")

  -- only the lines around the window carry extmarks; a jump repaints, a move inside
  -- the painted span does not
  local many = {}
  for _ = 1, 1500 do
    vim.list_extend(many, { "| H | " .. string.rep("w", 30) .. " |", "|---|---|", "| a | b |", "" })
  end
  local big = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(big)
  vim.api.nvim_buf_set_lines(big, 0, -1, false, many)
  require("markdown.config").setup({ table = { truncate = { max = 10 } } })
  vim.cmd("normal! gg")
  local near = tt.render(big)
  ok(near > 0, "the first screen is painted")
  local rows = {}
  for _, e in ipairs(vim.api.nvim_buf_get_extmarks(big, ns, 0, -1, {})) do
    rows[#rows + 1] = e[2]
  end
  ok(#rows < #many, "the far end of a many buffer is not painted")
  local worked, total = tt._worked_out(big)
  eq(total, 1500, "the whole buffer is parsed")
  ok(
    worked > 0 and worked < 200,
    "but only the tables in the painted span are worked out, not all 1500: " .. worked
  )
  ok(math.max(unpack(rows)) < 1000, "nothing beyond the margin below the window")
  eq(tt.render(big), 0, "a render without a move or an edit repaints nothing")
  vim.cmd("normal! G")
  ok(tt.render(big) > 0, "a jump to the end paints the new view")
  local last = vim.api.nvim_buf_get_extmarks(big, ns, { #many - 5, 0 }, { #many - 1, -1 }, {})
  ok(#last > 0, "the end of the buffer is concealed after the jump")
  -- a scroll event repaints at once from the cached ranges (no debounce, no raw text after a jump)
  tt.clear(big)
  tt.enable(big)
  vim.cmd("normal! gg")
  vim.api.nvim_exec_autocmds("WinScrolled", {})
  eq(
    #vim.api.nvim_buf_get_extmarks(big, ns, { #many - 5, 0 }, { #many - 1, -1 }, {}),
    0,
    "top: the end is not painted"
  )
  vim.cmd("normal! G")
  vim.api.nvim_exec_autocmds("WinScrolled", {})
  ok(
    #vim.api.nvim_buf_get_extmarks(big, ns, { #many - 5, 0 }, { #many - 1, -1 }, {}) > 0,
    "WinScrolled paints the new view before any debounce"
  )
  -- the ranges worked out table by table for the painted span are the ones the whole-buffer computation gives
  do
    local want = tt.compute(many, { max = 10 })
    local by_start = function(a, b) return a.s < b.s end
    local checked = 0
    local seen = {}
    for _, e in ipairs(vim.api.nvim_buf_get_extmarks(big, ns, 0, -1, { details = true })) do
      local ln = e[2] + 1
      seen[ln] = seen[ln] or {}
      seen[ln][#seen[ln] + 1] =
        { s = e[3] + 1, e = e[4].end_row == e[2] and e[4].end_col or -1, text = e[4].conceal }
    end
    for ln, got in pairs(seen) do
      table.sort(got, by_start)
      local w = vim.deepcopy(want[ln] or {})
      table.sort(w, by_start)
      ok(vim.deep_equal(got, w), "line " .. ln .. ": painted ranges equal the computed ones")
      checked = checked + 1
    end
    ok(checked > 20, "a whole screen of lines was compared")
  end
  -- an edit makes the ranges new (the memo belongs to one text)
  vim.api.nvim_buf_set_lines(
    big,
    #many - 4,
    #many - 3,
    false,
    { "| a | " .. string.rep("z", 40) .. " |" }
  )
  local after_edit = tt.render(big)
  ok(after_edit > 0, "after an edit the visible tables are worked out again")
  tt.disable(big)
  vim.api.nvim_buf_delete(big, { force = true })

  -- `truncate = true` is accepted as "on"
  require("markdown.config").setup({ table = { truncate = true } })
  eq(require("markdown.config").get().table.truncate.enabled, true, "truncate = true turns it on")
  eq(require("markdown.config").get().table.truncate.max, 40, "and keeps the default max")
  require("markdown.config").setup({})
end
