-- TESTS/html_links_spec.lua — markdown.core.html_links
--
-- The captioned-image case, end to end: a `<figure>` block is one link spread
-- over several lines, and the interesting assertion is that every line of it
-- (including the `<figcaption>`, which contains no target at all) resolves to
-- the same image.

return function(H)
  local eq, ok = H.eq, H.ok

  local html = require("markdown.core.html_links")
  local scan = require("markdown.core.link_scan")

  -- ------------------------------------------------------------- from_line

  do
    local links = html.from_line('  <img src="assets/start.png" alt="Start Screen">', 3)
    eq(#links, 1, "from_line: one img")
    eq(links[1].target, "assets/start.png", "from_line: src")
    eq(links[1].text, "Start Screen", "from_line: alt becomes the link text")
    eq(links[1].kind, "html_media", "from_line: img is media")
    eq(links[1].lnum, 3, "from_line: line number passed through")
    eq(links[1].col, 2, "from_line: span starts at the tag, not the attribute")
  end

  do
    local line = "<img src=\"a.png\"><img src='b.png'><img src=c.png>"
    local links = html.from_line(line, 1)
    eq(#links, 3, "from_line: three tags on one line")
    eq(links[2].target, "b.png", "from_line: single-quoted value")
    eq(links[3].target, "c.png", "from_line: unquoted value")
  end

  do
    local line = '<a href="doc.md#intro">Zur Einleitung</a>'
    local links = html.from_line(line, 1)
    eq(#links, 1, "from_line: one anchor")
    eq(links[1].target, "doc.md#intro", "from_line: href")
    eq(links[1].text, "Zur Einleitung", "from_line: label between the tags")
    eq(links[1].kind, "html_link", "from_line: a is a plain link")
    eq(links[1].col_end, #line - 1, "from_line: span reaches the closing </a>")
  end

  do
    local links = html.from_line('<img src="q.png?a=1&amp;b=2">', 1)
    eq(links[1].target, "q.png?a=1&b=2", "from_line: &amp; decoded")
  end

  do
    eq(#html.from_line("plain prose, no tags", 1), 0, "from_line: prose yields nothing")
    eq(#html.from_line("<figcaption>Abbildung 1</figcaption>", 1), 0, "from_line: no target attr")
    eq(#html.from_line("<div class='x'>", 1), 0, "from_line: unlisted tag ignored")
  end

  -- ------------------------------------------------------------- link_scan

  do
    -- A URL inside an `<img>` is one link, not an image plus a bare URL.
    local links = scan.from_line('<img src="https://example.com/a.png">', 1)
    eq(#links, 1, "link_scan: html span covers its own URL")
    eq(links[1].kind, "html_media", "link_scan: reported as media")
  end

  do
    local links = scan.from_line('See [docs](x.md) and <img src="y.png">', 1)
    eq(#links, 2, "link_scan: markdown and html side by side")
    eq(links[1].kind, "mdlink", "link_scan: markdown link first")
    eq(links[2].target, "y.png", "link_scan: html link second")
  end

  -- ------------------------------------------------------------ figure_at

  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Doc",
      "",
      "<figure>",
      '  <img src="assets/start.png" alt="Start Screen">',
      "  <figcaption>Abbildung 1: Start Screen</figcaption>",
      "</figure>",
      "",
      "Prosa danach.",
    })

    for _, row in ipairs({ 3, 4, 5, 6 }) do
      local link = html.figure_at(buf, row)
      ok(link, ("figure_at: row %d is inside the figure"):format(row))
      eq(link.target, "assets/start.png", ("figure_at: row %d resolves the img"):format(row))
      eq(link.lnum, row, ("figure_at: row %d re-anchored onto the cursor line"):format(row))
    end

    eq(
      html.figure_at(buf, 5).text,
      "Abbildung 1: Start Screen",
      "figure_at: figcaption wins over alt as the label"
    )

    eq(html.figure_at(buf, 1), nil, "figure_at: above the block")
    eq(html.figure_at(buf, 8), nil, "figure_at: below the block")

    -- The hover entry point must agree: cursor parked on the caption line.
    vim.api.nvim_win_set_cursor(0, { 5, 4 })
    local hovered = require("markdown.hover").link_under_cursor(buf)
    ok(hovered, "hover: caption line has a link under the cursor")
    eq(hovered.target, "assets/start.png", "hover: caption resolves the figure's image")

    -- And on the img line it comes from the line scan, not the fallback.
    vim.api.nvim_win_set_cursor(0, { 4, 4 })
    eq(
      require("markdown.hover").link_under_cursor(buf).target,
      "assets/start.png",
      "hover: img line resolves directly"
    )

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  do
    -- Two adjacent figures: a line between them belongs to neither.
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "<figure>",
      '  <img src="a.png">',
      "</figure>",
      "",
      "Text zwischen den Abbildungen.",
      "",
      "<figure>",
      '  <img src="b.png">',
      "</figure>",
    })

    eq(html.figure_at(buf, 2).target, "a.png", "figure_at: first block")
    eq(html.figure_at(buf, 8).target, "b.png", "figure_at: second block")
    eq(html.figure_at(buf, 5), nil, "figure_at: the gap belongs to neither block")

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- ------------------------------------------------------------- media_at

  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "<picture>", -- 1
      '  <source src="wide.webp">', -- 2
      '  <img src="fallback.png">', -- 3
      "</picture>", -- 4
      "", -- 5
      "Freistehende Prosa.", -- 6
      "", -- 7
      "<figure>", -- 8
      "  <img", -- 9
      '    src="split.png"', -- 10
      '    alt="Attribut auf eigener Zeile">', -- 11
      "  <figcaption>Zerlegtes Tag</figcaption>", -- 12
      "</figure>", -- 13
    })

    eq(html.media_at(buf, 2).target, "wide.webp", "media_at: <picture> block resolves")
    eq(html.figure_at(buf, 2), nil, "figure_at: a <picture> is not a <figure>")

    -- A tag broken across lines is invisible to the per-line scan; inside a
    -- block whose bounds are known, joining is safe.
    eq(html.media_at(buf, 12).target, "split.png", "media_at: multi-line <img> from the caption")
    eq(html.media_at(buf, 9).target, "split.png", "media_at: multi-line <img> from its own line")

    eq(html.media_at(buf, 6), nil, "media_at: prose between two blocks resolves to nothing")

    vim.api.nvim_buf_delete(buf, { force = true })
  end
end
