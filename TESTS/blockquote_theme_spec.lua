-- TESTS/blockquote_theme_spec.lua — blockquote_hl colors derive from the
-- active colorscheme when marker_fg/text_fg aren't set explicitly; an
-- explicit config value still wins.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local bq = require("markdown.hl_options.hl_groups.blockquote")

  local MARKER = "MarkdownBlockquoteMarker"
  local TEXT   = "MarkdownBlockquoteText"

  -- No explicit colors: both groups still get SOME resolved foreground
  -- (theme-derived, falling back to the historical hex if nothing resolves —
  -- never left unset).
  bq.apply({ blockquote_hl = {} })
  local marker_hl = vim.api.nvim_get_hl(0, { name = MARKER })
  local text_hl   = vim.api.nvim_get_hl(0, { name = TEXT })
  ok(type(marker_hl.fg) == "number", "marker fg resolved without explicit config")
  ok(type(text_hl.fg) == "number", "text fg resolved without explicit config")

  -- Explicit config still overrides theme derivation.
  bq.apply({ blockquote_hl = { marker_fg = "#123456", text_fg = "#654321" } })
  local marker_hl2 = vim.api.nvim_get_hl(0, { name = MARKER })
  local text_hl2   = vim.api.nvim_get_hl(0, { name = TEXT })
  eq(marker_hl2.fg, tonumber("123456", 16), "explicit marker_fg overrides theme derivation")
  eq(text_hl2.fg, tonumber("654321", 16), "explicit text_fg overrides theme derivation")

  -- Reset to no explicit config for any following spec/state.
  bq.apply({ blockquote_hl = {} })
end
