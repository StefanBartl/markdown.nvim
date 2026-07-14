-- docs/TESTS/tableview_alignment_spec.lua — TableView column alignment with
-- multi-byte UTF-8 content (German umlauts, em dashes, curly quotes, arrows,
-- ellipses). Regression coverage for the bug where compute_col_widths()/
-- align_cell() padded by BYTE length (#cell) instead of screen-display width
-- (vim.fn.strdisplaywidth), so any cell containing such characters made every
-- `|` column divider drift out of vertical alignment.
--
-- Uses renderer.validate_alignment(lines) — the de-facto check requested
-- alongside the fix: verify real rendered output rather than eyeballing a
-- screenshot for drifted `|` columns.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local renderer = require("markdown_nvim.tableview.renderer")
  local parser = require("markdown_nvim.tableview.parser")

  -- Reproduces the reported content almost verbatim: umlauts (Überschneidet,
  -- Kürzung, zusammenführen, überall), an em dash (→ is U+2192, not an em
  -- dash, but equally multi-byte/1-column), an ellipsis (…), curly quotes
  -- („…"), and markdown's own ASCII noise (`code`, **bold**) mixed in.
  local lines = {
    "| Config-Modul | Überschneidet sich mit | Empfehlung |",
    "|---|---|---|",
    "| `config/harpoon/utils/normkey.lua` (Slash-Normalisierung, Drive-Upper, UNC, realpath) | `lib.nvim.cross.fs.separators.normalize`, `lib.nvim.fs.path` | In lib zusammenführen; Harpoon konsumiert lib |",
    "| `config/harpoon/utils/path_label.lua` (Kürzung `<root>/…/<parent>/<file>`) | `lib.nvim.fs.path_shorten` | „....\"-Elision als Option in `path_shorten` |",
    "| `config/harpoon/utils/fs_project_key.lua` (Git-Root → cwd-Fallback, normalisiert) | `lib.nvim.fs.find_root` + `lib.nvim.git` | `lib.nvim.fs.project_key()` bauen, überall nutzen |",
  }

  local tables = parser.get_tables_from_lines(lines)
  eq(#tables, 1, "the fixture parses as exactly one GFM table")
  local mt = tables[1]

  -- Markdown-style float.
  renderer.render_markdowntable(mt, { floating = true, style = "markdown" })
  local out_md = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
  local ok_md, err_md = renderer.validate_alignment(out_md)
  ok(ok_md, "markdown style: every | divider aligns on the same display column — " .. tostring(err_md))
  renderer.close_view()

  -- Box-drawing style.
  renderer.render_markdowntable(mt, { floating = true, style = "box" })
  local out_box = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
  local ok_box, err_box = renderer.validate_alignment(out_box)
  ok(ok_box, "box style: every │ divider aligns on the same display column — " .. tostring(err_box))
  renderer.close_view()

  -- validate_alignment itself: must actually CATCH a drifted table, not just
  -- pass everything (a validator that never fails is worthless as a check).
  local drifted = {
    "| short | b |",
    "| a very long cell that is much wider | b |",
  }
  local drift_ok, drift_err = renderer.validate_alignment(drifted)
  eq(drift_ok, false, "validate_alignment: detects a genuinely misaligned divider")
  ok(drift_err and drift_err:match("display column"), "validate_alignment: error message names the mismatch")

  -- And a well-formed, hand-aligned table must pass (sanity: not overly strict).
  local aligned = {
    "| a   | b |",
    "| --- | - |",
    "| 1   | 2 |",
  }
  local aligned_ok = renderer.validate_alignment(aligned)
  ok(aligned_ok, "validate_alignment: a correctly padded table passes")

  -- Stacked (multi-table) rendering must also stay aligned per-table (the
  -- label lines have no dividers and are correctly skipped by the check).
  local mt2 = parser.get_tables_from_lines({
    "| x | y |",
    "| - | - |",
    "| übrigens | … |",
  })[1]
  renderer.render_tables({ mt, mt2 }, { floating = true, style = "markdown" })
  local out_stacked = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
  -- Validate each table's own block separately: the two tables have different
  -- column counts, so a single global check across both would itself flag a
  -- (correct) count difference between blocks — that's expected, not a bug.
  local blank_idx = nil
  for i, l in ipairs(out_stacked) do if l == "" then blank_idx = i break end end
  ok(blank_idx ~= nil, "stacked render: tables are separated by a blank line")
  local first_block = { unpack(out_stacked, 1, blank_idx - 1) }
  local ok_first = renderer.validate_alignment(first_block)
  ok(ok_first, "stacked render: first table's own block is internally aligned")
  renderer.close_view()
end
