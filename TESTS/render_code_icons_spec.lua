-- TESTS/render_code_icons_spec.lua -- the language label of a fenced code block gets an icon: the user's `code.icon_map`
-- first, then an icon plugin when one is installed; `code.icons = false` keeps the plain label.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local r = require("markdown.core.render")

  local function label(lang, code)
    local cfg = vim.tbl_deep_extend("force", r.DEFAULTS, code and { code = code } or {})
    for _, m in
      ipairs(r.line_marks("```" .. lang, { width = 20, cfg = cfg, role = "open", lang = lang }))
    do
      if m.opts.virt_text then return m.opts.virt_text[1][1] end
    end
  end

  eq(label("lua", { icon_map = { lua = "L" } }), "L lua", "the mapped icon comes first")
  eq(
    label("Lua", { icon_map = { lua = "L" } }),
    "L Lua",
    "the language is looked up in lower case, shown as written"
  )
  eq(
    label("lua", { icon_map = { lua = "L" }, icons = false }),
    "lua",
    "the switch keeps the plain label"
  )
  eq(label("lua", { icon_map = { lua = "" } }), "lua", "an empty entry is no icon")
  eq(
    r._lang_icon("zzz-no-such-language", { icons = true, icon_map = {} }),
    nil,
    "no icon without a source"
  )
  -- the config accepts the map (empty by default) and drops a bad one with a report
  local config = require("markdown.config")
  config.setup({ render = { code = { icon_map = { lua = "L" } } } })
  eq(#config.issues(), 0, "a map of text to text is valid")
  eq(config.get().render.code.icon_map.lua, "L", "and arrives as given")
  config.setup({ render = { code = { icon_map = { lua = 5 } } } })
  eq(#config.issues(), 1, "an entry that is not text is reported")
  eq(next(config.get().render.code.icon_map), nil, "and the map falls back to the empty default")
  config.setup({})
  eq(label("lua", { label = false, icon_map = { lua = "L" } }), nil, "no label, no icon")
end
