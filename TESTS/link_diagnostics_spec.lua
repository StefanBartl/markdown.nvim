-- TESTS/link_diagnostics_spec.lua — dead relative-file links / duplicate
-- heading anchors, reusing core/link_scan + core/slug.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local diag = require("markdown.core.link_diagnostics")
  local sev = vim.diagnostic.severity

  local buf = H.scratch("markdown")
  -- Unnamed buffer: relative targets resolve against getcwd(), which the
  -- runner sets to the repo root, so "README.md" is a real, existing file.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# Title",
    "",
    "[dead](./this-file-does-not-exist-xyz.md)",
    "[ok](README.md)",
    "[anchor-ok](#title)",
    "[anchor-bad](#nope)",
    "",
    "## Title",
  })

  local findings = diag.collect(buf)

  local by_sev = { [sev.ERROR] = 0, [sev.WARN] = 0, [sev.HINT] = 0 }
  for _, f in ipairs(findings) do
    by_sev[f.severity] = (by_sev[f.severity] or 0) + 1
  end

  eq(by_sev[sev.ERROR], 1, "one dead-link ERROR")
  eq(by_sev[sev.WARN], 1, "one missing-anchor WARN")
  eq(by_sev[sev.HINT], 1, "one duplicate-heading HINT")

  local has_dead, has_anchor_bad = false, false
  for _, f in ipairs(findings) do
    if f.message:match("this%-file%-does%-not%-exist%-xyz%.md") then has_dead = true end
    if f.message:match("#nope") then has_anchor_bad = true end
  end
  ok(has_dead, "dead-link finding mentions the missing file")
  ok(has_anchor_bad, "missing-anchor finding mentions #nope")

  -- check()/clear() drive vim.diagnostic directly.
  local n = diag.check(buf)
  eq(n, 3, "check() returns the same finding count")
  local set = vim.diagnostic.get(buf, { namespace = diag.namespace })
  eq(#set, 3, "vim.diagnostic.get sees all 3 findings")

  -- check() also mirrors into the quickfix list. Before this existed, the
  -- command told the user to run `:lopen`, which raised E776: vim.diagnostic
  -- never populates the location list.
  local qf = vim.fn.getqflist()
  eq(#qf, 3, "check() fills the quickfix list")
  eq(vim.fn.getqflist({ title = 0 }).title, "markdown.nvim: link check", "quickfix title")

  -- The two APIs disagree on index base -- vim.diagnostic is 0-based in lnum
  -- and col, quickfix is 1-based in both. An off-by-one here is silent.
  local entries = diag.to_qf_entries(diag.collect(buf), buf)
  local raw = diag.collect(buf)
  for i, e in ipairs(entries) do
    eq(e.lnum, raw[i].lnum + 1, "qf lnum is 1-based")
    eq(e.col, raw[i].col + 1, "qf col is 1-based")
  end

  local by_type = {}
  for _, e in ipairs(qf) do
    by_type[e.type] = (by_type[e.type] or 0) + 1
  end
  eq(by_type.E, 1, "dead link maps to type E")
  eq(by_type.W, 1, "missing anchor maps to type W")
  eq(by_type.N, 1, "duplicate heading maps to type N, not I")

  diag.clear(buf)
  local cleared = vim.diagnostic.get(buf, { namespace = diag.namespace })
  eq(#cleared, 0, "clear() resets the namespace")

  -- A clean buffer reports nothing.
  local buf2 = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "# Only Heading", "", "[ok](README.md)" })
  eq(#diag.collect(buf2), 0, "clean buffer has no findings")

  -- ...and running check() on it must *clear* the previous run's entries.
  -- Leaving them standing would show yesterday's dead links under a "no
  -- issues" notification.
  eq(diag.check(buf2), 0, "clean buffer check() returns 0")
  eq(#vim.fn.getqflist(), 0, "clean run clears stale quickfix entries")
end
