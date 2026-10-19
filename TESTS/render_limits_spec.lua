-- TESTS/render_limits_spec.lua -- the inline scan has bounds, so that a pathological line cannot cost the editor: links nested
-- deeper than a badge stop at a depth, and a line with very many emphasis markers is left alone.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local r = require("markdown.core.render")
  local function marks(line) return r.line_marks(line, { width = 20, cfg = r.DEFAULTS }) end

  -- 2000 nested links: drawn only to the depth limit (it was 6000 marks and ~100 ms per line)
  local deep = ("[x"):rep(2000) .. ("](u)"):rep(2000)
  local started = vim.uv.hrtime()
  local ms = marks(deep)
  local took = (vim.uv.hrtime() - started) / 1e6
  ok(#ms <= 3 * r.MAX_LINK_DEPTH, "nesting is drawn to the depth limit, not 6000 marks: " .. #ms)
  ok(took < 50, "and a line like that costs well under 50 ms: " .. took)
  eq(#marks("[![build](a.svg)](http://x)"), 6, "a badge (two deep) is drawn as before")

  -- very many emphasis runs: left alone instead of the quadratic search
  local many = ("*a "):rep(r.MAX_EMPHASIS_RUNS + 50)
  eq(#marks(many), 0, "more runs than the limit are plain text")
  eq(
    #marks("*a* *b* *c*"),
    9,
    "a few are drawn: three pairs, two hidden markers and a highlight each"
  )
end
