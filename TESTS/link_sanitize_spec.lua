-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
-- TESTS/link_sanitize_spec.lua — core.link_sanitize: normalize link-target
-- paths (./, forward slashes) without touching URLs/anchors/absolute paths.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local ok = H.ok
  local sanitize = require("markdown.core.link_sanitize")

  -- ── sanitize_target: the two cases from the feature request ──
  local got, changed = sanitize.sanitize_target("testpfad.md")
  eq(got, "./testpfad.md", "bare relative path gets ./ prefix")
  ok(changed, "bare relative path reports changed")

  got, changed = sanitize.sanitize_target([[.\doc\testpfad.md]])
  eq(got, "./doc/testpfad.md", "backslashes normalized, existing ./ kept as-is")
  ok(changed, "backslash normalization reports changed")

  -- ── already sane: idempotent, no change ──
  got, changed = sanitize.sanitize_target("./doc/testpfad.md")
  eq(got, "./doc/testpfad.md", "already-sane path is unchanged")
  eq(changed, false, "already-sane path reports no change")

  -- ── left alone: URLs, anchors, drive letters, absolute, home-relative ──
  local untouched = {
    "https://example.com/a.md",
    "http://example.com",
    "mailto:foo@bar.com",
    "#section",
    [[C:\Users\bartl\doc.md]],
    "/etc/hosts",
    "~/notes/foo.md",
    "../up/one.md",
  }
  for _, t in ipairs(untouched) do
    local g, c = sanitize.sanitize_target(t)
    eq(g, t, "left untouched: " .. t)
    eq(c, false, "reports no change: " .. t)
  end

  -- ── sanitize_line: multiple targets on one line, only the relative ones touched ──
  local line = "see [a](rel.md) and [b](https://example.com) and [c](#anchor)"
  local new_line, n = sanitize.sanitize_line(line)
  eq(
    new_line,
    "see [a](./rel.md) and [b](https://example.com) and [c](#anchor)",
    "only the relative target rewritten"
  )
  eq(n, 1, "one target changed on the line")

  -- ── sanitize_lines: fenced code blocks are skipped ──
  local lines = {
    "```",
    "[hidden](inside.md)",
    "```",
    "[visible](outside.md)",
  }
  local new_lines, total = sanitize.sanitize_lines(lines)
  eq(new_lines[2], "[hidden](inside.md)", "fenced link left untouched")
  eq(new_lines[4], "[visible](./outside.md)", "unfenced link normalized")
  eq(total, 1, "only the unfenced link counted")

  -- ── buffer(): edits only the lines that actually changed ──
  local buf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# Title",
    "[a](rel.md)",
    "[b](./already.md)",
    "[c](https://example.com)",
  })
  local buf_changed = sanitize.buffer(buf)
  eq(buf_changed, 1, "buffer(): one target normalized")
  local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(out[2], "[a](./rel.md)", "buffer(): relative target rewritten in place")
  eq(out[3], "[b](./already.md)", "buffer(): already-sane line untouched")

  -- ── file(): reads/writes a file on disk ──
  local path = (vim.fn.tempname()) .. "_mdnvim_sanitize.md"
  local fh = io.open(path, "w")
  ok(fh ~= nil, "fixture write")
  fh:write("[x](sub/dir/target.md)\n")
  fh:close()

  local file_changed = sanitize.file(path)
  eq(file_changed, 1, "file(): one target normalized")
  local written = vim.fn.readfile(path)
  eq(written[1], "[x](./sub/dir/target.md)", "file(): target rewritten on disk")

  pcall(vim.fn.delete, path)
  ok(true, "done")
end
