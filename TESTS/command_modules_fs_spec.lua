-- TESTS/command_modules_fs_spec.lua -- direct specs for commands/{create,image}, util/md_files
-- and the anchor predicates (anchor/is_*_line, is_inside_toc_block).
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok

  local logs = { info = {}, warn = {} }
  package.loaded["markdown.util.notify"] = {
    create = function()
      return {
        info = function(m) logs.info[#logs.info + 1] = m end,
        warn = function(m) logs.warn[#logs.warn + 1] = m end,
        error = function() end,
        debug = function() end,
      }
    end,
  }
  local function reset_logs()
    logs.info, logs.warn = {}, {}
  end

  local function buffer(lines, name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    if name then vim.api.nvim_buf_set_name(buf, name) end
    return buf
  end

  local function exists(path) return (vim.uv or vim.loop).fs_stat(path) ~= nil end

  -- ── commands/create ──────────────────────────────────────────────────────
  package.loaded["markdown.commands.create"] = nil
  local create = require("markdown.commands.create")
  local root = H.tmproot("mdnvim_create_spec")

  buffer({
    "[a](notes/a.md) and [dir](assets/) and [web](https://example.com/x.md)",
    "[anchor](#top) [mail](mailto:me@example.com) [again](notes/a.md)",
  }, root .. "/doc.md")

  create.run({})
  ok(exists(root .. "/notes/a.md"), "a link target is created with its parent directory")
  eq(vim.fn.isdirectory(root .. "/assets"), 1, "a trailing slash makes a directory")
  eq(vim.fn.isdirectory(root .. "/https:"), 0, "a URL is not created")
  ok(
    logs.info[#logs.info]:find("2 created, 0 already existed", 1, true),
    "reports 2 created once (duplicate skipped)"
  )

  reset_logs()
  create.run({ "fs" })
  ok(
    logs.info[#logs.info]:find("0 created, 2 already existed", 1, true),
    "existing paths are left alone"
  )

  reset_logs()
  buffer({ "[x](only/second.md)", "[y](only/skipped.md)" }, root .. "/ranged.md")
  create.run({}, { range = 2, line1 = 1, line2 = 1 })
  ok(exists(root .. "/only/second.md"), "a range creates the targets inside it")
  ok(not exists(root .. "/only/skipped.md"), "a range leaves the targets outside it")

  reset_logs()
  buffer({ "no links here" }, root .. "/none.md")
  create.run({})
  ok(logs.info[1]:find("no local markdown-link paths", 1, true), "no links: says so")

  reset_logs()
  create.run({ "bogus" })
  ok(logs.warn[1]:find("unknown type", 1, true), "unknown type warns")
  eq(table.concat(create.complete("f"), ","), "fs", "completes fs")
  eq(#create.complete("z"), 0, "no completion for z")

  -- ── commands/image ───────────────────────────────────────────────────────
  package.loaded["markdown.commands.image"] = nil
  package.loaded["images"] = nil
  package.preload["images"] = function() error("not installed") end
  local image = require("markdown.commands.image")

  reset_logs()
  image.run({})
  ok(logs.warn[1]:find("images.nvim not installed", 1, true), "paste without images.nvim warns")
  reset_logs()
  image.run({ "screenshot" })
  ok(
    logs.warn[1]:find("images.nvim not installed", 1, true),
    "screenshot without images.nvim warns"
  )
  reset_logs()
  image.run({ "dance" })
  ok(logs.warn[1]:find("unknown subcommand", 1, true), "unknown subcommand warns")

  local called = {}
  package.preload["images"] = nil
  package.loaded["images"] = {
    paste = function() called[#called + 1] = "paste" end,
    screenshot = function() called[#called + 1] = "screenshot" end,
  }
  image.run({})
  image.run({ "screenshot" })
  eq(
    table.concat(called, ","),
    "paste,screenshot",
    "delegates to images.nvim, paste is the default"
  )
  eq(table.concat(image.complete(""), ","), "paste,screenshot", "completes both subcommands")
  eq(table.concat(image.complete("s"), ","), "screenshot", "completes by prefix")
  package.loaded["images"] = nil

  -- ── util/md_files ────────────────────────────────────────────────────────
  local md_files = require("markdown.util.md_files")
  local tree = H.tmproot("mdnvim_mdfiles_spec")
  for _, d in ipairs({ "docs", "node_modules/pkg", ".git", "folder.md" }) do
    vim.fn.mkdir(tree .. "/" .. d, "p")
  end
  for _, f in ipairs({
    "B.md",
    "a.md",
    "README.MD",
    "docs/c.md",
    "node_modules/pkg/x.md",
    ".git/y.md",
    "note.txt",
  }) do
    vim.fn.writefile({ "" }, tree .. "/" .. f)
  end
  vim.fn.writefile({ "" }, tree .. "/folder.md/inner.md")
  local rel = {}
  for _, p in ipairs(md_files.collect(tree .. "/")) do
    rel[#rel + 1] = p:sub(#tree + 2)
  end
  eq(
    table.concat(rel, ","),
    "a.md,B.md,docs/c.md,folder.md/inner.md,README.MD",
    "case-insensitive .md, sorted, skips vendored dirs and non-md, a folder.md is walked not listed"
  )
  eq(#md_files.collect(tree .. "/node_modules/pkg"), 1, "the start folder is never skipped")
  eq(#md_files.collect(tree .. "/missing"), 0, "a missing directory gives an empty list")

  -- ── anchor predicates ────────────────────────────────────────────────────
  local is_anchor = require("markdown.anchor.is_anchor_line")
  eq(is_anchor("see [x](#sec-one) here"), true, "markdown anchor link")
  eq(is_anchor("see [x](file.md#sec) here"), false, "a file link is no anchor")
  eq(is_anchor(""), false, "empty line")
  eq(is_anchor(nil), false, "nil line")

  buffer({ "plain" })
  local is_html = require("markdown.anchor.is_html_anchor_line")
  eq(is_html([[<a href="#top">up</a>]]), true, "html anchor href")
  eq(is_html([[<h2 id="#top">T</h2>]]), true, "html id anchor")
  eq(is_html([[<a href="x.md">f</a>]]), false, "html file href is no anchor")
  buffer({ "<figure>", [[<img src="#fig" alt="">]], "</figure>" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  eq(is_html("<figure>"), true, "figure/img anchor within five lines of the cursor")

  buffer({ "plain" })
  local extern = require("markdown.anchor.is_html_extern_anchor_line")
  local r = extern("[doc](docs/guide.md#install)")
  eq(r and r.target, "docs/guide.md", "markdown file target")
  eq(r and r.fragment, "install", "markdown file fragment")
  eq(extern("[doc](#local)"), nil, "an in-document anchor is not external")
  eq(extern("[web](https://example.com/a.md)"), nil, "a URL is not a file")
  r = extern([[<a href="C:\notes\a.md">a</a>]])
  eq(r and r.target, [[C:\notes\a.md]], "windows drive path in an html href")
  r = extern([[<img src='pic.png'>]])
  eq(r and r.target, "pic.png", "html img src")
  eq(extern("just words"), nil, "no link at all")

  local in_toc = require("markdown.anchor.is_inside_toc_block")
  buffer({ "# Title", "", "## Table of Contents", "- [a](#a)", "- [b](#b)", "---", "text after" })
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  eq(in_toc(), true, "inside the TOC block")
  vim.api.nvim_win_set_cursor(0, { 7, 0 })
  eq(in_toc(), false, "after the closing rule")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  eq(in_toc(), false, "before the TOC")

  for _, m in ipairs({
    "markdown.util.notify",
    "markdown.commands.create",
    "markdown.commands.image",
  }) do
    package.loaded[m] = nil
  end
end
