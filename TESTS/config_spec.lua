-- docs/TESTS/config_spec.lua — config merge (DEFAULTS + user options).
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("markdown.config")

  -- defaults
  config.setup({})
  local d = config.get()
  eq(d.map_double_asterisk, true, "default map_double_asterisk")
  eq(d.enable_keymaps, true, "default enable_keymaps")
  eq(d.links.picker, "hover_select", "default picker")
  ok(type(d.open.external_extensions) == "table", "external_extensions is a table")

  -- shallow override
  config.setup({ enable_keymaps = false, protect_h1 = true })
  local o = config.get()
  eq(o.enable_keymaps, false, "override enable_keymaps")
  eq(o.protect_h1, true, "override protect_h1")
  -- untouched keys keep their default
  eq(o.map_wrap_link, true, "untouched key keeps default")

  -- nested deep-merge keeps sibling keys
  config.setup({ blockquote_hl = { text_bold = false } })
  local n = config.get()
  eq(n.blockquote_hl.text_bold, false, "nested override applied")
  eq(n.blockquote_hl.text_italic, false, "nested sibling kept from defaults")
  -- marker_fg/text_fg default to a fixed VS Code-style green, independent of
  -- the active colorscheme (see hl_groups/blockquote.lua); `false` opts back
  -- into colorscheme-derived colors at render time.
  eq(n.blockquote_hl.marker_fg, "#6A9955", "marker_fg defaults to the VS Code-style green")
  eq(n.blockquote_hl.text_fg, "#7EE787", "text_fg defaults to the VS Code-style green")

  -- reset
  config.setup({})
end
