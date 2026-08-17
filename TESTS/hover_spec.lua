-- TESTS/hover_spec.lua — markdown.hover
--
-- Real files in a real temp directory: classification and the text previewers
-- are pure enough to assert on directly, without opening a float. The float
-- itself is exercised separately (open/close/geometry), since a hover that
-- leaks a window is the failure mode that actually bites.

return function(H)
  local eq, ok = H.eq, H.ok

  local classify = require("markdown.hover.classify")
  local text = require("markdown.hover.preview.text")
  local float = require("markdown.hover.float")

  -- ------------------------------------------------------------- fixtures

  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  vim.fn.mkdir(tmp .. "/sub", "p")

  local doc = tmp .. "/doc.md"
  vim.fn.writefile({
    "# Title",
    "",
    "Intro paragraph.",
    "",
    "## Second",
    "",
    "Body of second.",
    "",
    "### Nested",
    "",
    "Nested body.",
    "",
    "## Third",
    "",
    "Body of third.",
  }, doc)

  local plain = tmp .. "/notes.txt"
  vim.fn.writefile({ "line one", "line two", "line three" }, plain)

  local png = tmp .. "/pic.png"
  -- A real 1x1 PNG header is enough: the dimension parser reads bytes 17..24.
  local f = io.open(png, "wb")
  f:write("\137PNG\r\n\26\n")
  f:write("\0\0\0\13IHDR")
  f:write("\0\0\0\1") -- width 1
  f:write("\0\0\0\1") -- height 1
  f:write(string.rep("\0", 8))
  f:close()

  -- ------------------------------------------------------------- classify

  do
    local t = classify.classify("#second", doc)
    eq(t.type, "anchor", "classify: leading # is an in-page anchor")
    eq(t.anchor, "second", "classify: anchor text without the hash")
  end

  do
    local t = classify.classify("https://example.com/a?b=c", doc)
    eq(t.type, "url", "classify: https is a url")
    eq(t.url, "https://example.com/a?b=c", "classify: url passed through")
  end

  do
    local t = classify.classify("mailto:a@b.com", doc)
    eq(t.type, "url", "classify: mailto is a url, not a path")
  end

  do
    -- Relative targets resolve against the DOCUMENT's directory, not the cwd
    -- -- the whole point, and the easiest thing to get wrong.
    local t = classify.classify("notes.txt", doc)
    eq(t.type, "file", "classify: existing sibling file")
    ok(t.path:match("notes%.txt$") ~= nil, "classify: resolved next to the document")
  end

  do
    local t = classify.classify("doc.md", doc)
    eq(t.type, "markdown", "classify: .md is markdown")
  end

  do
    local t = classify.classify("pic.png", doc)
    eq(t.type, "image", "classify: .png is an image")
    eq(t.ext, "png", "classify: extension recorded")
  end

  do
    local t = classify.classify("sub", doc)
    eq(t.type, "directory", "classify: a directory is its own type")
  end

  do
    local t = classify.classify("nope.md", doc)
    eq(t.type, "missing", "classify: nonexistent target -> missing")
    ok(t.reason ~= nil, "classify: missing carries a reason")
  end

  do
    local t = classify.classify("doc.md#second", doc)
    eq(t.type, "markdown", "classify: path#anchor keeps the file type")
    eq(t.anchor, "second", "classify: ... and splits the anchor off")
  end

  do
    local t = classify.classify("", doc)
    eq(t.type, "missing", "classify: empty target -> missing, not a crash")
  end

  -- Windows drive letters must not be mistaken for a URL scheme.
  do
    local t = classify.classify("C:/definitely/not/here.md", doc)
    eq(t.type, "missing", "classify: a drive letter is a path, not a scheme")
    ok(t.type ~= "url", "classify: ... specifically not a url")
  end

  -- ------------------------------------------------------ text previewers

  do
    local content = text.file(
      { type = "file", raw = "notes.txt", path = plain },
      { max_lines = 20 }
    )
    eq(content.lines[1], "line one", "preview.file: first line")
    eq(#content.lines, 3, "preview.file: all lines within the cap")
    eq(content.filetype, nil, "preview.file: no filetype guessed for plain text")
  end

  do
    local content = text.file({ type = "file", raw = "notes.txt", path = plain }, { max_lines = 2 })
    eq(#content.lines, 3, "preview.file: cap of 2 yields 2 lines plus an ellipsis")
    eq(content.lines[3], "…", "preview.file: truncation is marked")
  end

  do
    local content = text.file({ type = "markdown", raw = "doc.md", path = doc }, { max_lines = 20 })
    eq(content.filetype, "markdown", "preview.file: markdown gets its filetype")
  end

  do
    local content = text.file_anchor(
      { type = "markdown", raw = "doc.md#second", path = doc, anchor = "second" },
      { max_lines = 20 }
    )
    eq(content.lines[1], "## Second", "preview.file_anchor: starts at the heading")
    -- The section must stop at the next same-level heading, but include the
    -- deeper "### Nested" that belongs to it.
    local joined = table.concat(content.lines, "\n")
    ok(joined:match("Body of second") ~= nil, "preview.file_anchor: includes its body")
    ok(joined:match("### Nested") ~= nil, "preview.file_anchor: includes deeper subsections")
    ok(joined:match("## Third") == nil, "preview.file_anchor: stops before the next H2")
  end

  do
    local content = text.file_anchor(
      { type = "markdown", raw = "doc.md#nope", path = doc, anchor = "nope" },
      { max_lines = 20 }
    )
    ok(
      content.title:match("not found") ~= nil,
      "preview.file_anchor: unknown anchor falls back to the file, and says so"
    )
  end

  do
    local content = text.directory(
      { type = "directory", raw = "sub", path = tmp },
      { max_lines = 20 }
    )
    local joined = table.concat(content.lines, "\n")
    ok(joined:match("sub/") ~= nil, "preview.directory: lists subdirectories with a slash")
    ok(joined:match("doc%.md") ~= nil, "preview.directory: lists files")
  end

  do
    local content = text.missing({
      type = "missing",
      raw = "nope.md",
      path = tmp .. "/nope.md",
      reason = "no such file",
    })
    eq(content.title, "broken link", "preview.missing: titled as a broken link")
    eq(content.lines[1], "no such file", "preview.missing: states the reason")
  end

  -- ------------------------------------------------- anchor in the buffer

  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Doc",
      "",
      "## Target Section",
      "",
      "the body",
      "",
      "## After",
    })
    local content = text.anchor(
      { type = "anchor", raw = "#target-section", anchor = "target-section" },
      { max_lines = 20 },
      buf
    )
    eq(content.lines[1], "## Target Section", "preview.anchor: finds the heading by gfm slug")
    local joined = table.concat(content.lines, "\n")
    ok(joined:match("the body") ~= nil, "preview.anchor: includes the section body")
    ok(joined:match("## After") == nil, "preview.anchor: stops at the next same-level heading")

    local miss = text.anchor(
      { type = "anchor", raw = "#nope", anchor = "nope" },
      { max_lines = 20 },
      buf
    )
    eq(miss.title, "broken anchor", "preview.anchor: unknown anchor is reported as broken")
  end

  -- --------------------------------------------------- link under cursor

  do
    local hover = require("markdown.hover")
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "see [the doc](doc.md) for more",
    })

    -- Cursor inside the link.
    vim.api.nvim_win_set_cursor(0, { 1, 6 })
    local link = hover.link_under_cursor(buf)
    ok(link ~= nil, "link_under_cursor: finds the link the cursor is on")
    eq(link.target, "doc.md", "link_under_cursor: reports its target")

    -- Cursor outside every link: a hover must NOT fall back to "the only
    -- link on the line" the way the opener does.
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    eq(hover.link_under_cursor(buf), nil, "link_under_cursor: no fallback to the line's only link")
  end

  -- --------------------------------------------------------------- float

  do
    ok(not float.is_open(), "float: nothing open initially")

    float.open({ "hello", "world" }, { title = "t", max_width = 40, max_height = 10 })
    ok(float.is_open(), "float: opens")
    ok(float.win() ~= nil, "float: exposes its window handle")

    -- Opening again replaces rather than stacking.
    local first = float.win()
    float.open({ "second" }, { max_width = 40, max_height = 10 })
    ok(float.win() ~= first, "float: reopening replaces the previous window")
    ok(vim.api.nvim_win_is_valid(float.win()), "float: the new window is valid")

    -- The hover must never take focus.
    ok(vim.api.nvim_get_current_win() ~= float.win(), "float: does not steal focus")

    local closed = false
    float.set_on_close(function() closed = true end)
    float.close()
    ok(not float.is_open(), "float: closes")
    ok(closed, "float: registered teardown ran")

    float.close()
    ok(true, "float: closing twice does not error")

    eq(float.open({}, {}), nil, "float: empty content opens nothing")
  end

  vim.fn.delete(tmp, "rf")
end
