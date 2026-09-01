-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- The hover targets built below carry only what the assertion reads; a full
-- Lib.Hover.Target per case would be noise, not coverage.
-- TESTS/hover_spec.lua — markdown.hover
--
-- Real files in a real temp directory: classification and the text previewers
-- are pure enough to assert on directly, without opening a float. The float
-- itself is exercised separately (open/close/geometry), since a hover that
-- leaks a window is the failure mode that actually bites.

return function(H)
  local eq, ok = H.eq, H.ok

  local classify = require("lib.nvim.hover.classify")
  local text = require("lib.nvim.hover.preview.text")
  local section = require("markdown.hover.section")
  local float = require("lib.nvim.hover.float")

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
    local content = section.file_anchor(
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
    local content = section.file_anchor(
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
    eq(
      content.lines[1],
      "✗ no such file",
      "preview.missing: states the reason, behind a ✗ marker"
    )
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
    local content = section.anchor(
      { type = "anchor", raw = "#target-section", anchor = "target-section" },
      { max_lines = 20 },
      buf
    )
    eq(content.lines[1], "## Target Section", "preview.anchor: finds the heading by gfm slug")
    local joined = table.concat(content.lines, "\n")
    ok(joined:match("the body") ~= nil, "preview.anchor: includes the section body")
    ok(joined:match("## After") == nil, "preview.anchor: stops at the next same-level heading")

    local miss = section.anchor(
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
    local reopened = assert(float.win(), "float: reopening produced a window")
    ok(reopened ~= first, "float: reopening replaces the previous window")
    ok(vim.api.nvim_win_is_valid(reopened), "float: the new window is valid")

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

  -- --------------------------------------------------------- image hover

  -- Synthetic headers, not real pictures: `dimensions` only ever reads the
  -- first bytes, so a valid header is the whole fixture. It also keeps the
  -- ImageMagick fallback out of the test -- these parse locally or not at all.
  local function write_bytes(path, bytes)
    local f = assert(io.open(path, "wb"))
    f:write(bytes)
    f:close()
  end

  local function be16(n) return string.char(math.floor(n / 256), n % 256) end
  local function be32(n)
    return string.char(
      math.floor(n / 0x1000000) % 256,
      math.floor(n / 0x10000) % 256,
      math.floor(n / 0x100) % 256,
      n % 256
    )
  end

  local png = tmp .. "/wide.png"
  write_bytes(
    png,
    "\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(400) .. be32(100) .. "\8\6\0\0\0"
  )

  -- SOI, an APP0 the walker must skip over, then the SOF0 carrying the size.
  local jpg = tmp .. "/wide.jpg"
  write_bytes(
    jpg,
    "\255\216"
      .. "\255\224"
      .. be16(16)
      .. "JFIF\0\1\1\0\0\1\0\1\0\0"
      .. "\255\192"
      .. be16(17)
      .. "\8"
      .. be16(300)
      .. be16(900)
      .. "\3\1\17\0\2\17\1\3\17\1"
  )

  do
    local media = require("lib.nvim.hover.preview.media")
    local preview_opts = { max_lines = 10, max_width = 40 }

    local function target_for(path)
      local st = vim.uv.fs_stat(path)
      return { type = "image", path = path, ext = path:match("%.(%w+)$"), size = st and st.size }
    end

    -- With a drawing provider present the float is a frame for the picture:
    -- sized to the file's aspect ratio, and carrying no text or title at all.
    local saved = package.loaded["lib.nvim.image_preview"]
    package.loaded["lib.nvim.image_preview"] = { detect = function() return "images.nvim" end }

    local c = media.image(target_for(png), preview_opts)
    ok(c.canvas ~= nil, "image hover: drawable target yields a canvas")
    -- 400x100 is wider than the 40x10 box allows, so width is the binding
    -- limit and the height follows from it (cells being ~twice as tall as wide).
    eq(c.canvas.cols, 40, "image hover: canvas width clamped to max_width")
    eq(c.canvas.rows, 5, "image hover: canvas height follows the image ratio")
    eq(#c.lines, 0, "image hover: no metadata lines next to the picture")
    eq(c.title, nil, "image hover: no filename in the border")
    eq(c.image_path, png, "image hover: still asks for the draw")

    -- JPEG has no fixed size offset; its segment chain has to be walked.
    local j = media.image(target_for(jpg), preview_opts)
    eq(j.canvas.cols, 40, "image hover: JPEG width clamped")
    eq(j.canvas.rows, 6, "image hover: JPEG ratio read from the SOF segment past APP0")

    -- The float takes the canvas verbatim, and shows nothing in it.
    local win, fbuf =
      float.open(c.lines, { title = c.title, canvas = c.canvas, max_width = 40, max_height = 10 })
    ok(win ~= nil, "image hover: canvas opens a float even with no lines")
    ---@cast win -nil
    ---@cast fbuf -nil
    eq(vim.api.nvim_win_get_width(win), 40, "image hover: float is the canvas width")
    eq(vim.api.nvim_win_get_height(win), 5, "image hover: float is the canvas height")
    eq(vim.api.nvim_win_get_config(win).title, nil, "image hover: float has no border title")
    eq(
      table.concat(vim.api.nvim_buf_get_lines(fbuf, 0, -1, false), "|"),
      "||||",
      "image hover: float holds blank lines only"
    )
    float.close()

    -- No provider: metadata is then the only thing the hover can say, so it
    -- says it -- including the dimensions parsed out of the header.
    package.loaded["lib.nvim.image_preview"] = { detect = function() return nil end }
    local m = media.image(target_for(png), preview_opts)
    eq(m.canvas, nil, "image hover: no provider means no canvas")
    eq(m.title, "wide.png", "image hover: metadata float is titled with the filename")
    eq(m.lines[1], "400 × 100 px", "image hover: dimensions parsed from the PNG header")
    ok(m.lines[2]:match("^PNG"), "image hover: format and size line")

    package.loaded["lib.nvim.image_preview"] = saved
  end

  -- ----------------------------------------------------------- pdf hover

  do
    local media = require("lib.nvim.hover.preview.media")
    local preview_opts = { max_lines = 10, max_width = 40 }

    local pdf = tmp .. "/doc.pdf"
    vim.fn.writefile({ "%PDF-1.4 not really a pdf" }, pdf)

    local saved_preview = package.loaded["lib.nvim.image_preview"]
    local saved_pdfport = package.loaded["pdfport"]
    package.loaded["lib.nvim.image_preview"] = { detect = function() return "images.nvim" end }

    -- Stands in for pdftoppm: hands back the PNG fixture and counts how often
    -- it was asked to do so.
    local renders = 0
    package.loaded["pdfport"] = {
      render_page = function(_, _, _, cb)
        renders = renders + 1
        cb(png, nil)
      end,
    }

    local delivered
    local provisional = media.pdf(
      { type = "pdf", path = pdf, size = 42 },
      preview_opts,
      function(c) delivered = c end
    )

    ok(provisional.pending, "pdf hover: the float returned during a render is provisional")
    eq(
      provisional.lines[2],
      "rendering page 1…",
      "pdf hover: provisional float says what it is waiting for"
    )

    -- The render callback is scheduled onto the main loop, so it lands a tick later.
    vim.wait(500, function() return delivered ~= nil end)
    ok(delivered ~= nil, "pdf hover: the rendered page is delivered")
    eq(
      delivered.canvas.cols,
      40,
      "pdf hover: page float is sized to the rendered page, not to text"
    )
    eq(delivered.canvas.rows, 5, "pdf hover: page float keeps the page ratio")
    eq(delivered.title, nil, "pdf hover: no filename over the rendered page")
    eq(#delivered.lines, 0, "pdf hover: no metadata over the rendered page")
    eq(renders, 1, "pdf hover: one render so far")

    -- Second hover, same file, same mtime: answered from the kept page, with
    -- no provisional float at all -- there is nothing to wait for.
    local again = media.pdf({ type = "pdf", path = pdf, size = 42 }, preview_opts, function() end)
    eq(again.pending, nil, "pdf hover: a cached page needs no provisional float")
    eq(again.image_path, png, "pdf hover: cached page is reused")
    eq(renders, 1, "pdf hover: cached page does not shell out again")

    -- A changed PDF must not answer with the old page.
    vim.wait(1100) -- mtime has second resolution
    vim.fn.writefile({ "%PDF-1.4 changed" }, pdf)
    media.pdf({ type = "pdf", path = pdf, size = 43 }, preview_opts, function() end)
    eq(renders, 2, "pdf hover: a changed file is rendered again")

    -- Without a drawing provider the metadata float is all there is.
    package.loaded["lib.nvim.image_preview"] = { detect = function() return nil end }
    local meta = media.pdf({ type = "pdf", path = pdf, size = 43 }, preview_opts, function() end)
    eq(meta.pending, nil, "pdf hover: no provider means nothing to wait for")
    eq(meta.title, "doc.pdf", "pdf hover: metadata float is titled with the filename")
    ok(
      meta.lines[2]:match("no image provider"),
      "pdf hover: metadata float says why there is no page"
    )

    package.loaded["lib.nvim.image_preview"] = saved_preview
    package.loaded["pdfport"] = saved_pdfport
  end

  -- ------------------------------------------------------------ escalation

  -- `escalate()` reuses each target's existing opener rather than growing a
  -- second one: mocking those modules (instead of e.g. images.nvim's actual
  -- draw path) is the point -- it proves the dispatch, not the openers,
  -- which are already covered where they live.
  do
    local hover = require("markdown.hover")

    local function escalate_on(buf, target_text)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { ("[link](%s)"):format(target_text) })
      vim.api.nvim_win_set_cursor(0, { 1, 2 })
      return hover.escalate()
    end

    do -- markdown -> mdview.run({ path })
      local buf = H.scratch("markdown")
      local captured
      local saved = package.loaded["markdown.commands.mdview"]
      package.loaded["markdown.commands.mdview"] = { run = function(argv) captured = argv end }

      ok(escalate_on(buf, doc), "escalate: markdown target reports handled")
      ok(
        captured ~= nil and captured[1] ~= nil and captured[1]:match("doc%.md$") ~= nil,
        "escalate: markdown hands mdview the resolved path"
      )

      package.loaded["markdown.commands.mdview"] = saved
    end

    do -- anchor -> mdview.run({}): nothing to escalate an in-page anchor to
      -- but a full render of the current file itself.
      local buf = H.scratch("markdown")
      local captured
      local saved = package.loaded["markdown.commands.mdview"]
      package.loaded["markdown.commands.mdview"] = { run = function(argv) captured = argv end }

      escalate_on(buf, "#second")
      ok(captured ~= nil and captured[1] == nil, "escalate: anchor hands mdview no path")

      package.loaded["markdown.commands.mdview"] = saved
    end

    do -- image -> images.zen.open(path), an explicit path -- untouched by
      -- images.nvim's own (separately in-flux) under-cursor resolution.
      local buf = H.scratch("markdown")
      -- A dedicated fixture, not the outer `png`: that name gets
      -- re-declared (shadowed) further up for the wide.png/wide.jpg cases,
      -- and a test tied to "whatever `png` currently refers to" is fragile.
      local esc_png = tmp .. "/escalate.png"
      local f = assert(io.open(esc_png, "wb"))
      f:write("\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\0\1\0\0\0\1" .. string.rep("\0", 8))
      f:close()

      local captured
      local saved = package.loaded["images.zen"]
      package.loaded["images.zen"] = { open = function(p) captured = p end }

      escalate_on(buf, esc_png)
      ok(
        captured ~= nil and captured:match("escalate%.png$") ~= nil,
        "escalate: image hands images.zen.open the resolved path"
      )

      package.loaded["images.zen"] = saved
    end

    do -- pdf -> handler.file.open_pdf(path)
      local buf = H.scratch("markdown")
      local pdf = tmp .. "/escalate.pdf"
      vim.fn.writefile({ "%PDF-1.4 not really a pdf" }, pdf)
      local captured
      local saved = package.loaded["markdown.handler.file"]
      package.loaded["markdown.handler.file"] =
        { open_pdf = function(p) captured = p end, system_open = function() end }

      escalate_on(buf, pdf)
      ok(
        captured ~= nil and captured:match("escalate%.pdf$") ~= nil,
        "escalate: pdf hands handler.file.open_pdf the resolved path"
      )

      package.loaded["markdown.handler.file"] = saved
    end

    do -- other file -> handler.file.system_open(path)
      local buf = H.scratch("markdown")
      local captured
      local saved = package.loaded["markdown.handler.file"]
      package.loaded["markdown.handler.file"] =
        { open_pdf = function() end, system_open = function(p) captured = p end }

      escalate_on(buf, plain)
      ok(
        captured ~= nil and captured:match("notes%.txt$") ~= nil,
        "escalate: plain file hands handler.file.system_open the resolved path"
      )

      package.loaded["markdown.handler.file"] = saved
    end

    do -- directory -> platform.open(path)
      local buf = H.scratch("markdown")
      local captured
      local saved = package.loaded["markdown.util.platform"]
      package.loaded["markdown.util.platform"] = { open = function(p) captured = p end }

      escalate_on(buf, tmp .. "/sub")
      ok(
        captured ~= nil and captured:match("sub$") ~= nil,
        "escalate: directory hands platform.open the resolved path"
      )

      package.loaded["markdown.util.platform"] = saved
    end

    do -- url -> platform.open(url) directly, not through a line-extraction opener
      local buf = H.scratch("markdown")
      local captured
      local saved = package.loaded["markdown.util.platform"]
      package.loaded["markdown.util.platform"] = { open = function(p) captured = p end }

      escalate_on(buf, "https://example.com/a?b=c")
      eq(captured, "https://example.com/a?b=c", "escalate: url hands platform.open the raw url")

      package.loaded["markdown.util.platform"] = saved
    end

    do -- missing target -> nothing to open
      local buf = H.scratch("markdown")
      ok(not escalate_on(buf, "nope-escalate.md"), "escalate: missing target is not handled")
    end

    do -- no link under cursor -> not handled, nothing crashes
      local buf = H.scratch("markdown")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "no link on this line" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      ok(not hover.escalate(), "escalate: no link under cursor is not handled")
    end
  end

  -- ------------------------------------------------- bare paths (no link syntax)
  -- A path written as plain text -- in prose, a code comment, a `:messages`
  -- dump -- is a hover target too. Everything downstream is shared with a
  -- linked target, so what is asserted here is only the detection: that a real
  -- path is found, that ordinary words are not, and that a non-existent one
  -- stays silent rather than opening a "does not exist" float on every word.
  do
    local hover = require("markdown.hover")
    local lib_hover = require("lib.nvim.hover")

    -- The buffer is *named* into the fixture directory rather than the cwd
    -- being changed to it: `bare_path` resolves against the buffer's own
    -- directory first, so this exercises the same code path without leaving
    -- global state behind. An earlier version used `lcd`, and when an
    -- assertion below failed the restore never ran -- which broke every spec
    -- the runner loaded afterwards by a relative path.
    local counter = 0

    ---@param line string
    ---@param col integer
    ---@return table|nil target The link under the cursor, or nil.
    ---@return string path The probe buffer's own name, which `show()` classifies against.
    local function target_on(line, col)
      counter = counter + 1
      local buf = H.scratch("lua") -- deliberately NOT markdown
      vim.api.nvim_buf_set_name(buf, tmp .. "/probe" .. counter .. ".lua")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
      vim.api.nvim_win_set_cursor(0, { 1, col })
      return hover.link_under_cursor(buf), vim.api.nvim_buf_get_name(buf)
    end

    --- Detection plus classification, against the probe buffer's own path --
    --- the same pair `show()` performs at runtime.
    ---@param line string
    ---@param col integer
    ---@return string|nil target type
    local function type_on(line, col)
      local found, src = target_on(line, col)
      if not found then return nil end
      return classify.classify(found.target, src).type
    end

    local found = target_on("-- see pic.png for the layout", 10)
    ok(found ~= nil, "bare path: a plain path in a lua comment is a target")
    eq(found and found.kind, "bare_path", "bare path: reported as kind=bare_path")
    eq(
      type_on("-- see pic.png for the layout", 10),
      "image",
      "bare path: classified by the same rules as a linked target"
    )

    -- The case markdown links never covered: a non-image file.
    local md = target_on("-- doc.md has the details", 6)
    ok(md ~= nil, "bare path: a non-image file is a target too")
    eq(type_on("-- doc.md has the details", 6), "markdown", "bare path: .md classifies as markdown")

    -- False positives are the whole risk of running on every CursorHold.
    ok(not target_on("local function helper()", 8), "bare path: an ordinary word is not a target")
    -- A missing target is reported only when the text cannot have been
    -- anything but a path. `name.ext` without a separator is how every Lua
    -- identifier is spelled, so those must stay silent, or a code buffer
    -- would carry a red ✗ on half its tokens.
    ok(
      not target_on("-- nope-does-not-exist.png here", 6),
      "bare path: bare name.ext that is missing stays silent"
    )
    ok(
      not target_on("local x = vim.api.nvim_get_mode()", 12),
      "bare path: vim.api is an identifier, not a broken path"
    )

    local gone = target_on("-- see docs/nope-missing.md for that", 12)
    ok(gone ~= nil, "bare path: a missing path WITH a separator is still a target")
    eq(
      type_on("-- see docs/nope-missing.md for that", 12),
      "missing",
      "bare path: ... and classifies as missing rather than being dropped"
    )

    do -- the ✗ marker is what makes "missing" readable at a glance
      local content = text.missing({
        type = "missing",
        raw = "a/b.md",
        path = tmp .. "/a/b.md",
        reason = "no such file",
      })
      ok(content.lines[1]:match("^✗") ~= nil, "preview.missing: marked with a ✗")
      eq(content.highlight, "LibHoverMissing", "preview.missing: carries its highlight group")
    end
    ok(not target_on("   ", 1), "bare path: whitespace under the cursor is not a target")

    -- Opt-out, even where a real path sits under the cursor. Set on the
    -- framework directly: markdown.nvim hands its `hover` block to
    -- `lib.nvim.hover.setup` and the library owns the value from there on.
    lib_hover.setup({ bare_paths = false })
    ok(
      not target_on("-- see pic.png for the layout", 10),
      "bare path: hover.bare_paths = false disables it"
    )
    lib_hover.setup({ bare_paths = true })
    ok(target_on("-- see pic.png for the layout", 10) ~= nil, "bare path: re-enabling restores it")
  end

  vim.fn.delete(tmp, "rf")
end
