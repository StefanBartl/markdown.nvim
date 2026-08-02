-- TESTS/blockquote_theme_spec.lua — blockquote_hl:
--   * marker_fg/text_fg default to a fixed VS Code-style green via
--     config.DEFAULTS (independent of the active colorscheme).
--   * `blockquote.apply()` called directly (bypassing config.setup, as here)
--     with no marker_fg/text_fg falls back to colorscheme-derived colors —
--     also what `false` opts back into when going through config.setup().
--   * An explicit hex always wins over both.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local bq     = require("markdown.hl_options.hl_groups.blockquote")
  local config = require("markdown.config")

  local MARKER = "MarkdownBlockquoteMarker"
  local TEXT   = "MarkdownBlockquoteText"

  -- Through config.setup(): default is the fixed VS Code-style green,
  -- regardless of what the active colorscheme's Comment/String resolve to.
  config.setup({})
  bq.apply(config.get())
  local marker_default = vim.api.nvim_get_hl(0, { name = MARKER })
  local text_default   = vim.api.nvim_get_hl(0, { name = TEXT })
  eq(marker_default.fg, tonumber("6A9955", 16), "marker_fg defaults to the fixed VS Code-style green")
  eq(text_default.fg, tonumber("7EE787", 16), "text_fg defaults to the fixed VS Code-style green")

  -- `false` opts back into colorscheme-derived colors: both groups still get
  -- SOME resolved foreground (theme-derived, falling back to the historical
  -- hex if nothing resolves — never left unset).
  bq.apply({ blockquote_hl = { marker_fg = false, text_fg = false } })
  local marker_hl = vim.api.nvim_get_hl(0, { name = MARKER })
  local text_hl   = vim.api.nvim_get_hl(0, { name = TEXT })
  ok(type(marker_hl.fg) == "number", "marker_fg = false: fg still resolved (theme-derived)")
  ok(type(text_hl.fg) == "number", "text_fg = false: fg still resolved (theme-derived)")

  -- Calling apply() directly (bypassing config.setup/DEFAULTS) with no
  -- marker_fg/text_fg at all behaves the same way.
  bq.apply({ blockquote_hl = {} })
  ok(type(vim.api.nvim_get_hl(0, { name = MARKER }).fg) == "number", "marker fg resolved without explicit config")
  ok(type(vim.api.nvim_get_hl(0, { name = TEXT }).fg) == "number", "text fg resolved without explicit config")

  -- Explicit config still overrides both the fixed default and theme derivation.
  bq.apply({ blockquote_hl = { marker_fg = "#123456", text_fg = "#654321" } })
  local marker_hl2 = vim.api.nvim_get_hl(0, { name = MARKER })
  local text_hl2   = vim.api.nvim_get_hl(0, { name = TEXT })
  eq(marker_hl2.fg, tonumber("123456", 16), "explicit marker_fg overrides the default")
  eq(text_hl2.fg, tonumber("654321", 16), "explicit text_fg overrides the default")

  -- Reset to defaults for any following spec/state.
  config.setup({})
  bq.apply(config.get())

  -- highlight_line: per-line extmark placement (what the decoration provider
  -- calls on every redraw). The text extmark must use hl_eol so the
  -- background fills past the last character to the window edge, VS
  -- Code-style, instead of stopping behind the actual text glyphs.
  local api = vim.api
  local ns = api.nvim_create_namespace("MarkdownNvimBlockquote")
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, {
    "> quoted",       -- row 0: ordinary blockquote line
    "not a quote",    -- row 1: must get no marks at all
    ">",              -- row 2: bare marker, empty text
  })

  bq.highlight_line(buf, 0)
  bq.highlight_line(buf, 1)
  bq.highlight_line(buf, 2)

  local marks0 = api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { 0, -1 }, { details = true })
  eq(#marks0, 2, "highlight_line: quoted line gets a marker + text extmark")
  local marker0, text0
  for _, m in ipairs(marks0) do
    if m[4].hl_group == MARKER then marker0 = m end
    if m[4].hl_group == TEXT   then text0   = m end
  end
  ok(marker0 ~= nil and text0 ~= nil, "highlight_line: both marker and text extmarks present")
  eq(marker0[3], 0, "highlight_line: marker extmark starts at column 0")
  ok(not marker0[4].hl_eol, "highlight_line: marker extmark does not fill to end of line")
  ok(text0[4].hl_eol == true, "highlight_line: text extmark fills to end of line (hl_eol)")
  eq(text0[3], marker0[4].end_col, "highlight_line: text extmark starts where the marker extmark ends")

  local marks1 = api.nvim_buf_get_extmarks(buf, ns, { 1, 0 }, { 1, -1 }, { details = true })
  eq(#marks1, 0, "highlight_line: a non-blockquote line gets no extmarks")

  local marks2 = api.nvim_buf_get_extmarks(buf, ns, { 2, 0 }, { 2, -1 }, { details = true })
  eq(#marks2, 2, "highlight_line: a bare '>' still gets marker + (empty, eol-filled) text extmarks")
end
