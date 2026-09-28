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

  -- Refreshing an existing TOC must not scroll the window. A TOC sits near the
  -- top of the file, so a scrolled window's `topline` often lies INSIDE the
  -- block: the old delete-then-insert clamped it into the deleted range and the
  -- text jumped on every save (refs.reconcile updates the TOC on BufWritePre).
  config.setup({})
  do
    local buf = H.scratch("markdown")
    local lines = { "# Title", "" }
    for i = 1, 16 do
      vim.list_extend(lines, { "## Section " .. i, "text", "" })
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    toc_cmd.update(nil, { separators = false }) -- first call creates the TOC (lines 3..~22)

    vim.fn.winrestview({ topline = 10, lnum = 25 })
    local before = vim.fn.winsaveview()
    eq(before.topline, 10, "fixture: topline lies inside the TOC block")

    -- Same headings: the rewritten block has the same length.
    toc_cmd.update(nil, { separators = false })
    local after = vim.fn.winsaveview()
    eq(after.topline, 10, "TOC refresh keeps topline (same length)")
    eq(after.lnum, 25, "TOC refresh keeps the cursor line (same length)")

    -- One more heading below the view: the block grows by one line.
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "## Section 17", "text" })
    toc_cmd.update(nil, { separators = false })
    after = vim.fn.winsaveview()
    eq(after.topline, 10, "TOC refresh keeps topline (block grew)")
    eq(after.lnum, 26, "cursor line below the TOC moves with the inserted line")
  end

  config.setup({})
end
