---@diagnostic disable: missing-fields
-- TESTS/usrcmds_help_spec.lua -- every positional argument of `:Markdown`, `:MDTable*` and
-- `:TableView*` has a line in lib.nvim's option float.
--
-- The texts come from `SUBARG_DESC` (the six generic slots of each `:Markdown <sub>` route, whose
-- meaning depends on the subcommand), the `desc` / `enum_desc` of the `:MDTable*` ArgSpecs and the
-- text of the `MARKDOWN_TABLEVIEW_SCOPE` type. An argument without one shows up as a bare row in
-- the cheatsheet, so this fails until it is described -- which is also how a new `:Markdown`
-- subcommand that forgot its entry in `SUBARG_DESC` is caught.

return function(H)
  local eq, ok = H.eq, H.ok

  local okc, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  ok(okc, "the composer loads")

  -- A lib.nvim older than `help.undocumented` cannot answer the question; that is a missing
  -- feature of the dependency, not a defect of this plugin.
  if type(composer.help.undocumented) ~= "function" then return end

  require("markdown.config").setup({})
  local buf = H.scratch("markdown")
  local usrcmds = require("markdown.bindings.usrcmds")
  usrcmds.apply({ buf = buf })
  usrcmds.apply_tableview({ buf = buf })

  local VERBS = {
    "Markdown",
    "MDTableProfile",
    "MDTableAlign",
    "MDTableFlavor",
    "TableViewToggle",
    "TableViewMarkdown",
    "TableViewBox",
    "TableViewOpenBrowser",
    "TableViewOpenBrowserNice",
  }

  local texts, malformed, stray, args = 0, {}, {}, 0
  for _, verb in ipairs(VERBS) do
    local handle = composer.registry()[verb]
    ok(handle ~= nil, ":" .. verb .. " is registered through the composer")

    local missing = {}
    for _, m in ipairs(composer.help.undocumented(verb, { args = true })) do
      missing[#missing + 1] = ("%s %s %s"):format(m.kind, m.route, m.name)
    end
    eq(#missing, 0, ":" .. verb .. " entries without a help text: " .. table.concat(missing, ", "))

    -- House style: one line, no trailing period, at most 80 characters; an `enum_desc` key is a
    -- value the argument really offers.
    for _, route in ipairs(handle:spec().routes) do
      for _, arg in ipairs(route.args or {}) do
        args = args + 1
        local offered = {}
        for _, value in ipairs(arg.enum or arg.values or {}) do
          offered[value] = true
        end
        local all = { arg.desc }
        for value, text in pairs(arg.enum_desc or {}) do
          all[#all + 1] = text
          if not offered[value] then stray[#stray + 1] = verb .. " " .. arg.name .. "=" .. value end
        end
        for _, text in ipairs(all) do
          texts = texts + 1
          if text:find("\n", 1, true) or text:sub(-1) == "." or #text > 80 then
            malformed[#malformed + 1] = text
          end
        end
      end
    end
  end

  -- The six slots of a `:Markdown <sub>` route are generic, so a text has to hold for every action
  -- typed before it. `:Markdown table view <action> <a3>`: toggle/markdown/box take a scope,
  -- browser/browsernice take `reopen` (a scope there is ignored), select/close take nothing --
  -- commands.table's completion is the source of that, and the text has to name both.
  local function slot_text(sub, slot)
    for _, route in ipairs(composer.registry().Markdown:spec().routes) do
      if route.path[1] == sub then return route.args[slot].desc end
    end
  end
  local table_slot3 = slot_text("table", 3)
  ok(type(table_slot3) == "string", ":Markdown table has a text for its third slot")
  if type(table_slot3) == "string" then
    ok(table_slot3:find("scope", 1, true), "table slot 3 names the view scope: " .. table_slot3)
    ok(
      table_slot3:find("reopen", 1, true),
      "table slot 3 names the browser's reopen: " .. table_slot3
    )
  end
  local table_cmd = require("markdown.commands.table")
  local function offered(action)
    return table.concat(table_cmd.complete("", "Markdown table view " .. action .. " "), ",")
  end
  ok(offered("toggle"):find("%", 1, true), "the scope is offered for toggle")
  ok(offered("box"):find("cwd", 1, true), "the scope is offered for box")
  eq(offered("browser"), "reopen", "browser offers only reopen")
  eq(offered("browsernice"), "reopen", "browsernice offers only reopen")
  eq(offered("select"), "", "select takes no third argument")
  eq(offered("close"), "", "close takes no third argument")

  local argtypes = require("lib.nvim.bindings.usercmd.composer.argtypes")
  local scope_text = argtypes.get("MARKDOWN_TABLEVIEW_SCOPE").desc
  ok(type(scope_text) == "string" and scope_text ~= "", "MARKDOWN_TABLEVIEW_SCOPE has a text")
  if type(scope_text) == "string" then
    ok(
      not scope_text:find("\n", 1, true) and scope_text:sub(-1) ~= "." and #scope_text <= 80,
      "MARKDOWN_TABLEVIEW_SCOPE: one line, no trailing period, <= 80 characters"
    )
  end

  -- Not vacuous: 15 routes x 6 slots on `:Markdown`, plus the eight other arguments.
  ok(args >= 98, "the arguments of all verbs were walked, saw " .. args)
  ok(texts >= 98, "their texts were found, saw " .. texts)
  eq(#malformed, 0, "malformed texts: " .. table.concat(malformed, " | "))
  eq(#stray, 0, "enum_desc keys that are no value: " .. table.concat(stray, ", "))
end
