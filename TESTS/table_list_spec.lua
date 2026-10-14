-- TESTS/table_list_spec.lua -- `:Markdown table list` (picker over the tables of a scope) and
-- the parity of `:Markdown table` and the buffer-local `:TableView*` commands.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local tl = require("markdown.commands.table_list")

  local DOC = {
    "# Doc",
    "",
    "| Name | Description |",
    "| --- | --- |",
    "| a | first |",
    "| bb | second |",
    "",
    "text",
    "",
    "| X | Y | Z |",
    "| - | - | - |",
    "| 1 | 2 | 3 |",
  }

  -- ───────────── arguments ─────────────
  local o = tl.parse_args({ "scope=cwd", "style=markdown" })
  ok(o and o.scope == "cwd" and o.style == "markdown", "scope= and style= parsed")
  eq(tl.parse_args({ "cwd" }).scope, "cwd", "a bare value is the scope")
  eq(tl.parse_args({}).scope, nil, "no arguments: default scope")
  local bad, err = tl.parse_args({ "style=fancy" })
  ok(bad == nil and err:find("style"), "unknown style rejected")
  ok(select(2, tl.parse_args({ "bogus=1" })) ~= nil, "unknown option rejected")

  -- ───────────── collect: buffer ─────────────
  local buf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, DOC)
  local items = tl.collect("%")
  eq(#items, 2, "two tables in the buffer")
  ok(
    items[1].text:find(":3", 1, true) and items[1].text:find("Name | Description", 1, true),
    "text: line + header"
  )
  ok(items[1].text:find("(2 rows)", 1, true), "text: row count")
  eq(items[1].start_line, 3, "start line")
  eq(items[2].start_line, 10, "second table")
  ok(items[1].previews.normal.lines ~= nil, "a scratch buffer previews its own text")
  eq(items[1].previews.normal.line, 3, "normal preview points at the table")
  ok(items[1].previews.table.lines[1]:find("┌", 1, true), "table preview is the grid by default")
  local md = tl.collect("buffer", "markdown")
  eq(md[1].previews.table.lines[1], "| Name | Description |", "markdown style: aligned GFM")
  eq(md[1].previews.table.ft, "markdown", "markdown style is highlighted as markdown")

  -- ───────────── collect: files ─────────────
  local root = H.tmproot("mkdn_table_list")
  vim.fn.writefile(DOC, root .. "/a.md")
  vim.fn.writefile({ "no table here" }, root .. "/b.md")
  local files = tl.collect(root)
  eq(#files, 2, "tables of a directory scope")
  local uv = vim.uv or vim.loop
  eq(
    uv.fs_realpath(files[1].previews.normal.file),
    uv.fs_realpath(root .. "/a.md"),
    "file entries preview the file"
  )
  eq(files[1].previews.normal.line, 3, "... at the table")
  local none, nerr = tl.collect(root .. "/b.md")
  ok(none == nil and nerr ~= nil, "no tables -> nil + message")

  -- ───────────── open ─────────────
  tl.open(files[2])
  eq(vim.api.nvim_win_get_cursor(0)[1], 10, "open jumps to the table")
  ok(vim.api.nvim_buf_get_name(0):find("a.md", 1, true), "... in its file")

  -- ───────────── picker dispatch ─────────────
  local config = require("markdown.config")
  local saved_cfg = config.get().table.list.picker
  local seen
  local saved = {
    pm = package.loaded["pickers.preview_modes"],
    en = package.loaded["pickers.engines"],
    pk = package.loaded["markdown.util.picker"],
  }
  package.loaded["pickers.preview_modes"] = {}
  package.loaded["pickers.engines"] = {
    load = function()
      return { pick_item = function(opts) seen = opts end }
    end,
  }
  package.loaded["markdown.util.picker"] = {
    select = function(its, opts, cb) seen = { builtin = true, items = its, opts = opts, cb = cb } end,
  }
  config.get().table.list.picker = "auto"
  tl.pick(items, function() end)
  ok(
    seen and seen.preview_modes and seen.preview_modes[2] == "table",
    "auto: pickers.nvim with the two modes"
  )
  eq(seen.items, items, "the entries are handed over as they are")
  config.get().table.list.picker = "builtin"
  tl.pick(items, function() end)
  ok(seen.builtin, "builtin: the chooser of markdown.nvim")
  eq(seen.opts.format(items[1]), items[1].text, "builtin: entries show their text")
  config.get().table.list.picker = "auto"
  package.loaded["pickers.preview_modes"] = nil
  package.preload["pickers.preview_modes"] = nil
  local real_require = require
  ---@diagnostic disable-next-line: duplicate-set-field
  _G.require = function(name)
    if name == "pickers.preview_modes" then error("module not found") end
    return real_require(name)
  end
  tl.pick(items, function() end)
  _G.require = real_require
  ok(seen.builtin, "an older pickers.nvim without preview_modes: falls back")
  config.get().table.list.picker = saved_cfg
  package.loaded["pickers.preview_modes"] = saved.pm
  package.loaded["pickers.engines"] = saved.en
  package.loaded["markdown.util.picker"] = saved.pk

  -- ───────────── parity :Markdown table <-> :TableView* ─────────────
  local tcmd = require("markdown.commands.table")
  local pbuf = H.scratch("markdown")
  require("markdown.bindings.usrcmds").apply_tableview({ buf = pbuf })
  local cmds = vim.api.nvim_buf_get_commands(pbuf, { builtin = false })

  for _, sub in ipairs(tcmd.subcommand_names()) do
    if sub ~= "view" then
      local name = "TableView" .. sub:sub(1, 1):upper() .. sub:sub(2)
      ok(cmds[name] ~= nil, ":Markdown table " .. sub .. " has :" .. name)
    end
  end
  for _, name in ipairs({
    "TableViewToggle",
    "TableViewMarkdown",
    "TableViewBox",
    "TableViewSelect",
    "TableViewClose",
    "TableViewOpenBrowser",
    "TableViewOpenBrowserNice",
  }) do
    ok(cmds[name] ~= nil, name .. " exists")
  end
  -- every :TableView action is reachable as `:Markdown table view <action>` and completes
  local out = tcmd.complete("", "Markdown table view ")
  for _, action in ipairs({
    "toggle",
    "markdown",
    "box",
    "select",
    "list",
    "close",
    "browser",
    "browsernice",
  }) do
    ok(vim.tbl_contains(out, action), ":Markdown table view " .. action)
  end
  ok(vim.tbl_contains(tcmd.subcommand_names(), "list"), ":Markdown table list exists")
  ok(
    vim.tbl_contains(tcmd.complete("sc", "Markdown table list sc"), "scope=cwd"),
    "list completes scope="
  )
  eq(cmds["TableViewList"].nargs, "*", ":TableViewList takes the same arguments")

  -- the forwarder hands the sub-command the same raw text `:Markdown table ...` does: a quoted
  -- literal separator survives (`" "` is a space, not "auto-detect")
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, { "x y" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd('TableViewTableize " "')
  eq(
    vim.api.nvim_buf_get_lines(pbuf, 0, 1, false)[1],
    "| x | y |",
    ':TableViewTableize " " splits at the space'
  )
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, { "p,q" })
  vim.cmd("TableViewTableize csv")
  eq(vim.api.nvim_buf_get_lines(pbuf, 0, 1, false)[1], "| p | q |", ":TableViewTableize csv")
end
