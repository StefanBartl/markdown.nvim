-- docs/TESTS/config_spec.lua — config merge (DEFAULTS + user options).
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local config = require("markdown_nvim.config")

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
  eq(n.blockquote_hl.marker_fg, "#6A9955", "nested sibling kept from defaults")

  -- reset
  config.setup({})
end
