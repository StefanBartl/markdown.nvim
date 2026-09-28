-- TESTS/toc_config_spec.lua — config.toc (header/marker/levels/anchor style)
-- drives commands.toc / core.toc / core.slug.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("markdown.config")
  local toc_cmd = require("markdown.commands.toc")
  local slug = require("markdown.core.slug")

  config.setup({})

  -- Defaults: header text + "-" marker.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Title",
      "",
      "## Section A",
      "",
      "### Sub A1",
      "",
      "#### Deep A1a",
      "",
      "## Section B",
    })
    toc_cmd.update(nil, { separators = false })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local body = table.concat(lines, "\n")
    ok(body:match("\n## Table of content\n") ~= nil, "default header inserted")
    ok(body:match("\n%s*%- %[Section A%]") ~= nil, "default marker '-' used")
    ok(body:match("%[Deep A1a%]") ~= nil, "level 4 included by default (max_level 4)")
    ok(body:match("Title%]") == nil, "level 1 excluded by default (min_level 2)")
  end

  -- Custom marker + narrower level range via config.toc.
  config.setup({ toc = { marker = "*", min_level = 2, max_level = 3 } })
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Title",
      "",
      "## Section A",
      "",
      "### Sub A1",
      "",
      "#### Deep A1a",
    })
    toc_cmd.update(nil, { separators = false })
    local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    ok(body:match("\n%s*%* %[Section A%]") ~= nil, "configured '*' marker used")
    ok(body:match("%[Deep A1a%]") == nil, "configured max_level=3 excludes level 4")
  end

  -- Per-call min=/max=/marker= override config.toc.run parses key=value args.
  config.setup({ toc = { marker = "*" } })
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Title", "", "## Section A" })
    toc_cmd.run({ "marker=+", "--no-sep" })
    local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    ok(body:match("\n%s*%+ %[Section A%]") ~= nil, "argv marker= overrides config.toc.marker")
  end

  -- Anchor style: "keep-case" + custom separator, shared between core.toc and
  -- core.slug.heading_anchors (the latter used by refs/diagnostics).
  config.setup({ toc = { anchor_style = "keep-case", anchor_separator = "_" } })
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "## Hello World" })

    local anchors = slug.heading_anchors(buf)
    eq(
      anchors.list[1].anchor,
      "Hello_World",
      "heading_anchors respects config anchor_style/separator"
    )

    toc_cmd.update(nil, { separators = false })
    local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    ok(body:match("%(#Hello_World%)") ~= nil, "TOC link uses the same keep-case/underscore anchor")
  end

  -- slug.gfm() itself must stay byte-for-byte identical regardless of config
  -- (explicit style="gfm" call bypasses config.toc entirely).
  eq(slug.gfm("Hello World!"), "hello-world", "slug.gfm unaffected by config overrides")

  -- Refreshing a TOC must not move the window's view. A TOC sits near the top of
  -- the file, so a scrolled window's `topline` often lies INSIDE the block: the
  -- old delete-then-insert clamped it into the deleted range and the text jumped
  -- on every save (refs.reconcile updates the TOC on BufWritePre). Checked
  -- against the text under the cursor, not just line numbers.
  config.setup({})
  do
    --- Scratch markdown buffer: title + `n` sections, then a generated TOC
    --- (block at rows 3..3+n+4, sections after it).
    local function fresh(n)
      local buf = H.scratch("markdown")
      local lines = { "# Title", "" }
      for i = 1, n do
        vim.list_extend(lines, { "## Section " .. i, "text", "" })
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      toc_cmd.update(nil, { separators = false })
      return buf
    end
    local function find(buf, text)
      for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if l == text then return i end
      end
      error("fixture line not found: " .. text)
    end
    local function update() toc_cmd.update(nil, { separators = false }) end

    -- Unchanged TOC: not written at all (no changedtick bump, no undo step) and
    -- the view stays exactly where it was.
    do
      local buf = fresh(16)
      vim.fn.winrestview({ topline = 10, lnum = 25 })
      eq(vim.fn.winsaveview().topline, 10, "fixture: topline lies inside the TOC block")
      local tick = vim.api.nvim_buf_get_changedtick(buf)
      local seq = vim.fn.undotree().seq_last
      update()
      eq(vim.api.nvim_buf_get_changedtick(buf), tick, "unchanged TOC: buffer not written")
      eq(vim.fn.undotree().seq_last, seq, "unchanged TOC: no undo step")
      local v = vim.fn.winsaveview()
      eq(v.topline, 10, "unchanged TOC: topline kept")
      eq(v.lnum, 25, "unchanged TOC: cursor line kept")
    end

    -- Block grows by one line: topline inside the block keeps its number, a
    -- cursor below the block follows its text.
    do
      local buf = fresh(16)
      vim.fn.winrestview({ topline = 10, lnum = 25 })
      local text = vim.fn.getline(25)
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "## Section 17", "text" })
      update()
      local v = vim.fn.winsaveview()
      eq(v.topline, 10, "block grew: topline inside the block kept")
      eq(vim.fn.getline("."), text, "block grew: cursor keeps its text")
      eq(v.lnum, 26, "block grew: cursor moved down by the added line")
    end

    -- Block shrinks; the view sits entirely below it.
    do
      local buf = fresh(16)
      local at = find(buf, "## Section 3")
      vim.api.nvim_buf_set_lines(buf, at - 1, at + 2, false, {}) -- drop section 3
      local row = find(buf, "## Section 12")
      vim.fn.winrestview({ topline = row - 8, lnum = row })
      local top = vim.fn.winsaveview().topline
      local n0 = vim.api.nvim_buf_line_count(buf)
      update()
      local v = vim.fn.winsaveview()
      eq(vim.fn.getline("."), "## Section 12", "block shrank: cursor keeps its text")
      eq(v.topline, top + (vim.api.nvim_buf_line_count(buf) - n0), "block shrank: topline follows")
    end

    -- Cursor INSIDE the block: keeps its row when the block changes length.
    do
      local buf = fresh(16)
      vim.fn.winrestview({ topline = 5, lnum = 8 })
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "## Section 17", "text" })
      update()
      local v = vim.fn.winsaveview()
      eq(v.topline, 5, "cursor inside block: topline kept")
      eq(v.lnum, 8, "cursor inside block: lnum kept")
    end

    -- A missing blank line above the header is repaired ABOVE the block; a view
    -- inside the block moves with it.
    do
      local buf = fresh(16)
      vim.api.nvim_buf_set_lines(buf, 1, 2, false, {}) -- remove the blank above the header
      eq(vim.fn.getline(2), "## Table of content", "fixture: header directly under the title")
      vim.fn.winrestview({ topline = 3, lnum = 8 })
      local text = vim.fn.getline(8)
      update()
      eq(vim.fn.getline(2), "", "spacing: blank line restored above the header")
      eq(vim.fn.getline("."), text, "spacing: cursor inside the block keeps its text")
    end

    -- No TOC yet: inserting one moves everything below it.
    do
      local buf = H.scratch("markdown")
      local lines = { "# Title", "" }
      for i = 1, 16 do
        vim.list_extend(lines, { "## Section " .. i, "text", "" })
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      local row = find(buf, "## Section 8")
      vim.fn.winrestview({ topline = row - 5, lnum = row })
      update()
      eq(vim.fn.getline("."), "## Section 8", "fresh insert: cursor keeps its text")
    end

    -- Two windows on one buffer, both restored. (After a split each window is
    -- only ~10 rows tall, so cursor and topline stay close together.)
    do
      local buf = fresh(16)
      vim.cmd("split")
      local w2 = vim.api.nvim_get_current_win()
      vim.fn.winrestview({ topline = 30, lnum = 34 }) -- below the block
      local text2 = vim.fn.getline(34)
      vim.cmd("wincmd p")
      vim.fn.winrestview({ topline = 10, lnum = 14 }) -- inside the block
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "## Section 17", "text" })
      update()
      local v1 = vim.fn.winsaveview()
      eq(v1.topline, 10, "window 1: topline kept")
      eq(v1.lnum, 14, "window 1: lnum kept")
      local v2 = vim.api.nvim_win_call(w2, vim.fn.winsaveview)
      eq(v2.topline, 31, "window 2: topline follows the added line")
      local now2 = vim.api.nvim_win_call(w2, function() return vim.fn.getline(".") end)
      eq(now2, text2, "window 2: cursor keeps its text")
      vim.cmd("only")
    end
  end

  config.setup({})
end
