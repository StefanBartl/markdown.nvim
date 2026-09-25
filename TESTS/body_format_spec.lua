-- TESTS/body_format_spec.lua — core.emphasis, core.inline_segment (shared with
-- heading_format.lua) and core.body_format (`:Markdown format`'s engine).

return function(H)
  local eq = H.eq
  local ok = H.ok

  local emphasis = require("markdown.core.emphasis")
  local body_format = require("markdown.core.body_format")

  -- ── core.emphasis: the marker-stripping primitives ────────────────────────

  eq(emphasis.strip_bold("**bold**"), "bold", "strip_bold: double-star pair")
  eq(emphasis.strip_bold("__bold__"), "bold", "strip_bold: double-underscore pair")
  eq(emphasis.strip_bold("*italic*"), "*italic*", "strip_bold: single-star italic untouched")
  eq(
    emphasis.strip_bold("*italic* and **bold**"),
    "*italic* and bold",
    "strip_bold: only the bold span goes"
  )
  eq(
    emphasis.strip_bold("***bold and italic***"),
    "*bold and italic*",
    "strip_bold: a triple run is peeled symmetrically, italic remains"
  )
  eq(
    emphasis.strip_bold("foo__bar__baz"),
    "foo__bar__baz",
    "strip_bold: intraword __ is not emphasis in GFM"
  )
  eq(
    emphasis.strip_bold("**a** and **b**"),
    "a and b",
    "strip_bold: two separate bold spans on one line"
  )

  eq(emphasis.strip_strikethrough("~~struck~~"), "struck", "strip_strikethrough: basic pair")
  eq(
    emphasis.strip_strikethrough("**bold** ~~struck~~"),
    "**bold** struck",
    "strip_strikethrough: leaves bold alone"
  )

  -- strip_all is heading_format's pre-existing rule (moved here unchanged);
  -- a couple of pin tests are enough, heading_format_spec.lua covers the rest.
  eq(emphasis.strip_all("**bold** and *italic*"), "bold and italic", "strip_all: everything goes")

  -- ── core.body_format: fenced blocks, front matter and inline protection ───

  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "---",
      "title: __not prose__",
      "---",
      "**bold** prose",
      "```sh",
      "# **not touched, a shell comment**",
      "```",
      "Pass `**kwargs` through, and a [link](**not_a_target**.md).",
    })
    local changed = body_format.format_buffer(buf, { "strip-bold" })
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(out[2], "title: __not prose__", "front matter left alone")
    eq(out[4], "bold prose", "body prose stripped")
    eq(out[6], "# **not touched, a shell comment**", "fenced content left alone")
    eq(
      out[8],
      "Pass `**kwargs` through, and a [link](**not_a_target**.md).",
      "code span and link target left alone"
    )
    eq(changed, 1, "exactly the one real prose line reported changed")
  end

  -- ── collapse-blank-lines: whole-buffer op, skips fenced content ───────────

  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "one",
      "",
      "",
      "",
      "two",
      "```sh",
      "a",
      "",
      "",
      "b",
      "```",
      "three",
    })
    local changed = body_format.format_buffer(buf, { "collapse-blank-lines" })
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(#out, 10, "the 3-blank run outside the fence collapsed to 1")
    eq(out[2], "", "one blank line kept")
    eq(out[3], "two", "next real line follows immediately")
    ok(changed >= 2, "reports the removed lines")

    -- the fenced blank-line pair survives untouched
    local joined = table.concat(out, "\n")
    ok(joined:match("a\n\n\nb") ~= nil, "the 2-blank run inside the fence is untouched")
  end

  -- ── trim-trailing-space: hard breaks survive, everything else goes ────────

  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "hard break  ", -- exactly two trailing spaces: keep
      "too many spaces     ", -- 5 trailing spaces: normalize to 2
      "one trailing space ", -- 1 trailing space: strip
      "   ", -- whitespace-only line: strip to empty
      "clean",
    })
    body_format.format_buffer(buf, { "trim-trailing-space" })
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(out[1], "hard break  ", "genuine hard break untouched")
    eq(out[2], "too many spaces  ", "excess trailing spaces normalized to the hard-break pair")
    eq(out[3], "one trailing space", "a single trailing space is noise, not a hard break")
    eq(out[4], "", "a whitespace-only line has nothing to break, goes to empty")
    eq(out[5], "clean", "already-clean line untouched")
  end

  -- ── normalize-list-markers ─────────────────────────────────────────────

  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "* one",
      "+ two",
      "- three",
      "  * nested",
      "1. ordered stays",
    })
    body_format.format_buffer(buf, { "normalize-list-markers" })
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(out[1], "- one", "* -> -")
    eq(out[2], "- two", "+ -> -")
    eq(out[3], "- three", "already - stays")
    eq(out[4], "  - nested", "indent preserved")
    eq(out[5], "1. ordered stays", "ordered marker untouched")
  end

  -- A thematic break (`* * *`, `***`) must never be reparsed as a bullet
  -- item -- turning it into `- * *` would swap a horizontal rule for a
  -- completely different line.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "* * *",
      "***",
      "* * * *",
      "* real item",
    })
    body_format.format_buffer(buf, { "normalize-list-markers" })
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    eq(out[1], "* * *", "spaced thematic break untouched")
    eq(out[2], "***", "bare thematic break untouched")
    eq(out[3], "* * * *", "longer spaced thematic break untouched")
    eq(out[4], "- real item", "a genuine bullet item is still normalized")
  end

  -- ── FENCE_PAT: a fence needs 3+ of the *same* character ───────────────────

  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "`~~", -- not a real fence: mixed characters
      "**bold**",
    })
    local changed = body_format.format_buffer(buf, { "strip-bold" })
    eq(changed, 1, "a mixed backtick/tilde run does not open a fence")
    eq(
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)[2],
      "bold",
      "the following prose line was still processed"
    )
  end

  -- ── dry-run: reports the count, writes nothing ────────────────────────────

  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "**bold**" })
    local changed = body_format.format_buffer(buf, { "strip-bold" }, { dry_run = true })
    eq(changed, 1, "dry-run still reports the change")
    eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], "**bold**", "but the buffer is untouched")
  end

  -- ── format_file: independent of any open buffer ───────────────────────────

  do
    local root = H.tmproot("mdnvim_body_format_spec")
    local path = root .. "/doc.md"
    vim.fn.writefile({ "**bold** text", "plain" }, path)

    local changed, err = body_format.format_file(path, { "strip-bold" })
    eq(err, nil, "format_file: no error")
    eq(changed, 1, "format_file: one line changed")
    eq(vim.fn.readfile(path)[1], "bold text", "format_file: written back to disk")

    local no_changed = body_format.format_file(path, { "strip-bold" })
    eq(no_changed, 0, "format_file: idempotent, nothing left to strip")

    local missing_changed, missing_err =
      body_format.format_file(root .. "/missing.md", { "strip-bold" })
    eq(missing_changed, nil, "format_file: unreadable path reports nil")
    ok(missing_err ~= nil, "format_file: and an error message")
  end
end
