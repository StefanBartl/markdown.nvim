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

  -- ERR-50: an unknown key anywhere in the shape is dropped, not merged in
  -- as a dead field next to the default it was meant to override.
  config.setup({ tabel = { header_align = "left" } })
  local typo_top = config.get()
  eq(typo_top.table.header_align, "center", "unknown top-level key dropped, default kept")
  ok(#config.issues() > 0, "unknown top-level key recorded in issues()")

  config.setup({ table = { wrap = { maximum = 40 } } })
  local typo_nested = config.get()
  eq(typo_nested.table.wrap.max, nil, "typo'd nested key does not leak in under a new name")
  ok(#config.issues() > 0, "unknown nested key recorded in issues()")

  -- The correctly-spelled sibling of that same typo still applies (proves
  -- the fix does not just refuse the whole `table.wrap` sub-table).
  config.setup({ table = { wrap = { max = 40 } } })
  eq(config.get().table.wrap.max, 40, "correctly-spelled nested key still applies")
  eq(#config.issues(), 0, "no issues for an all-valid setup()")

  -- ERR-22: an out-of-range scalar degrades to its default instead of
  -- reaching whatever reads it with something that raises there instead.
  config.setup({ progress_style = "not-a-style" })
  eq(config.get().progress_style, "auto", "invalid progress_style degrades to default")
  ok(#config.issues() > 0, "invalid scalar recorded in issues()")

  -- reset
  config.setup({})
  eq(#config.issues(), 0, "issues() clears on a clean setup()")
end
