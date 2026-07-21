-- docs/TESTS/link_scan_spec.lua — link extraction from lines (pure).
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local ls = require("markdown.core.link_scan")

  -- a markdown link and a bare URL on one line
  local got = ls.from_line("see [docs](./a.md) and https://example.com here", 5)
  eq(#got, 2, "two links found")
  eq(got[1].kind, "mdlink", "first is mdlink")
  eq(got[1].target, "./a.md", "mdlink target")
  eq(got[1].lnum, 5, "lnum threaded through")
  eq(got[2].kind, "url", "second is bare url")
  eq(got[2].target, "https://example.com", "url target (trailing word not swallowed)")

  -- a URL that is already a link target is not double-reported
  local one = ls.from_line("[site](https://example.com)", 1)
  eq(#one, 1, "link target url not double counted")
  eq(one[1].kind, "mdlink", "kept as mdlink")

  -- no links
  eq(#ls.from_line("just prose, no links", 1), 0, "no links -> empty")

  -- from_lines skips fenced code blocks
  local links = ls.from_lines({
    "```",
    "[hidden](inside.md)",
    "```",
    "[visible](outside.md)",
  })
  eq(#links, 1, "fenced link skipped")
  eq(links[1].target, "outside.md", "only the unfenced link is returned")
  ok(true, "done")
end
