-- TESTS/handler_url_spec.lua — handler.url: URL extraction under the cursor
-- (markdown link syntax, raw https, HTML href, and the near-cursor buffer
-- scan fallback), plus M.open's platform.open wiring.
--
-- Mirrors handler_spec.lua / handler_image_spec.lua / handler_pdf_spec.lua,
-- which cover the file/image/pdf handlers but never this one.

return function(H)
  local eq, ok = H.eq, H.ok
  local api = vim.api
  local url = require("markdown.handler.url")

  -- Markdown link syntax: [text](url).
  eq(
    url.extract("see [docs](https://example.com/x) for more"),
    "https://example.com/x",
    "extract: markdown link target"
  )

  -- Markdown link with a non-URL target does not count as a URL line (falls
  -- through to the file/link handlers instead).
  eq(url.extract("[local](./notes.md)"), nil, "extract: non-URL markdown target -> nil")
  eq(url.is_url_line("[local](./notes.md)"), false, "is_url_line: false for a non-URL target")

  -- Angle-bracket-wrapped target inside the markdown link form is unwrapped.
  eq(
    url.extract("[x](<https://example.com/a b>)"),
    "https://example.com/a b",
    "extract: angle brackets stripped from a markdown link target"
  )

  -- Raw bare URL in prose.
  eq(
    url.extract("visit https://example.com/page for info"),
    "https://example.com/page",
    "extract: bare URL in prose"
  )

  -- Trailing punctuation is stripped from a bare URL (end of sentence).
  eq(
    url.extract("see https://example.com/page."),
    "https://example.com/page",
    "extract: trailing '.' stripped from a bare URL"
  )
  eq(
    url.extract("(https://example.com/page)"),
    "https://example.com/page",
    "extract: trailing ')' stripped from a parenthesized bare URL"
  )

  -- HTML href, both quote styles.
  eq(
    url.extract('<a href="https://example.com/href">link</a>'),
    "https://example.com/href",
    "extract: HTML href with double quotes"
  )
  eq(
    url.extract("<a href='https://example.com/href2'>link</a>"),
    "https://example.com/href2",
    "extract: HTML href with single quotes"
  )

  -- No URL anywhere in an isolated line (no buffer/cursor context) -> nil.
  eq(url.extract("just some prose, nothing to see"), nil, "extract: no URL -> nil")
  eq(url.is_url_line("just some prose"), false, "is_url_line: false for a plain line")

  -- is_url_line true whenever extract succeeds.
  ok(url.is_url_line("https://example.com"), "is_url_line: true for a bare URL line")

  -- ── M.open: notifies and returns false when no URL is found. ──
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, { "no url on this line" })
    api.nvim_win_set_cursor(0, { 1, 0 })
    local opened = url.open("no url on this line")
    eq(opened, false, "open: returns false when no URL is found on the given line")
  end

  -- ── M.open: a found URL is handed to platform.open. ──
  do
    local platform = require("markdown.util.platform")
    local real_open = platform.open
    local captured
    platform.open = function(target)
      captured = target
      return true
    end

    local opened = url.open("go to https://example.com/target now")
    platform.open = real_open

    ok(opened, "open: reports success when platform.open succeeds")
    eq(captured, "https://example.com/target", "open: hands the extracted URL to platform.open")
  end

  -- ── M.open: platform.open failing is reported back as false. ──
  do
    local platform = require("markdown.util.platform")
    local real_open = platform.open
    platform.open = function(_target) return false, "boom" end

    local opened = url.open("https://example.com/fails")
    platform.open = real_open

    eq(opened, false, "open: reports failure when platform.open fails")
  end

  -- ── Near-cursor HTML href fallback: no URL on the current line, but an
  -- <a href> sits within the scan radius. ──
  do
    local buf = H.scratch("markdown")
    api.nvim_buf_set_lines(buf, 0, -1, false, {
      '<a href="https://example.com/nearby">link text</a>',
      "some prose",
      "cursor sits here, no url",
    })
    api.nvim_win_set_cursor(0, { 3, 0 })
    -- Passing an explicit `line` argument with no URL forces extract() down
    -- to its buffer-scan fallback, which reads the real cursor position.
    eq(
      url.extract("cursor sits here, no url"),
      "https://example.com/nearby",
      "extract: falls back to a nearby <a href> within the scan radius"
    )
  end
end
