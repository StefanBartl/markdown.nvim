-- TESTS/render_code_icons_spec.lua -- the language label of a fenced code block gets an icon: the user's `code.icon_map`
-- first, then an icon plugin when one is installed; `code.icons = false` keeps the plain label.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local r = require("markdown.core.render")
  local asked = {}
  -- a stand-in for the icon plugins: file types in, icons out, and a record of what was asked
  r._set_icon_provider(function(ft)
    asked[#asked + 1] = ft
    return ({ javascript = "JS", python = "PY", lua = "LU" })[ft]
  end)

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
  eq(
    label("lua", { icon_map = { lua = "" } }),
    "LU lua",
    "an empty entry is no icon of its own: the plugins answer"
  )
  eq(label("js"), "JS js", "an extension is taken to its file type")
  eq(label("py"), "PY py", "also python")
  eq(
    label("lua title=" .. string.char(34) .. "x" .. string.char(34)),
    "LU lua title=" .. string.char(34) .. "x" .. string.char(34),
    "only the first word is the language"
  )
  eq(label("{lua}"), "{lua}", "an attribute block is no language")
  eq(label("js", { icon_map = { javascript = "J" } }), "J js", "the map may name the file type")
  -- the plugins are asked once per language, not at every draw
  asked = {}
  for _ = 1, 5 do
    label("python")
  end
  eq(#asked <= 1, true, "the answer is cached")
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
