-- TESTS/command_modules_spec.lua -- direct specs for commands/{headings,scope,markdown_links}
-- and util/progress: argument vocabulary, completion, the sorted ignore-filtered link list.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok

  local logs = { info = {}, warn = {}, error = {} }
  local function reset_logs()
    for k in pairs(logs) do
      logs[k] = {}
    end
  end
  package.loaded["markdown.util.notify"] = {
    create = function()
      return {
        info = function(m) logs.info[#logs.info + 1] = m end,
        warn = function(m) logs.warn[#logs.warn + 1] = m end,
        error = function(m) logs.error[#logs.error + 1] = m end,
        debug = function() end,
      }
    end,
  }

  local function fresh(mod)
    package.loaded[mod] = nil
    return require(mod)
  end

  local function buffer(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
  end

  local function lines_of(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end

  -- ── commands/headings ────────────────────────────────────────────────────
  local headings = fresh("markdown.commands.headings")

  headings.run({})
  ok(logs.info[1] and logs.info[1]:find("Usage", 1, true), "no action prints the usage")
  reset_logs()

  headings.run({ "bogus" })
  ok(logs.warn[1] and logs.warn[1]:find("unknown action", 1, true), "unknown action warns")
  reset_logs()

  local SRC = { "# **Bold**   title ##", "", "## **Other**   one ##" }
  local buf = buffer(vim.deepcopy(SRC))
  for _, bad in ipairs({ "plain", "nope=on", "emphasis=maybe", "capitalize=loud" }) do
    reset_logs()
    headings.run({ "format", bad })
    eq(#logs.warn, 1, "bad token warns once: " .. bad)
    eq(
      table.concat(lines_of(buf), "|"),
      table.concat(SRC, "|"),
      "bad token leaves the buffer: " .. bad
    )
  end

  reset_logs()
  headings.run({ "format", "emphasis=on", "hashes=on", "whitespace=on", "capitalize=off" })
  eq(lines_of(buf)[1], "# Bold title", "format normalizes the first heading")
  eq(lines_of(buf)[3], "## Other one", "format normalizes the second heading")
  ok(logs.info[1] and logs.info[1]:find("Formatted 2 headings", 1, true), "reports the count")

  reset_logs()
  headings.run({ "format", "emphasis=on", "hashes=on", "whitespace=on", "capitalize=off" })
  ok(logs.info[1] and logs.info[1]:find("needed formatting", 1, true), "second run changes nothing")

  buf = buffer(vim.deepcopy(SRC))
  headings.run(
    { "format", "emphasis=on", "hashes=on", "whitespace=on", "capitalize=off" },
    { range = 2, line1 = 3, line2 = 3 }
  )
  eq(lines_of(buf)[1], SRC[1], "a range leaves the lines outside it")
  eq(lines_of(buf)[3], "## Other one", "a range formats the lines inside it")

  buf = buffer(vim.deepcopy(SRC))
  headings.run({ "format", "emphasis=off", "hashes=off", "whitespace=off", "capitalize=off" })
  eq(lines_of(buf)[1], SRC[1], "all rules off keeps the heading")

  eq(
    table.concat(headings.complete("", "Markdown headings "), ","),
    "format",
    "completes the action"
  )
  eq(
    table.concat(headings.complete("cap", "Markdown headings format cap"), ","),
    "capitalize=",
    "completes an option key"
  )
  eq(
    table.concat(headings.complete("capitalize=t", "Markdown headings format capitalize=t"), ","),
    "capitalize=title",
    "completes a capitalize value"
  )
  eq(
    table.concat(headings.complete("emphasis=o", "Markdown headings format emphasis=o"), ","),
    "emphasis=off,emphasis=on",
    "completes a boolean value"
  )

  -- ── commands/scope ───────────────────────────────────────────────────────
  local scope = fresh("markdown.commands.scope")
  local scope_state = require("markdown.scope")

  reset_logs()
  scope.run({ "on" })
  eq(scope_state.enabled(), true, "scope on")
  scope.run({ "off" })
  eq(scope_state.enabled(), false, "scope off")
  scope.run({ "toggle" })
  eq(scope_state.enabled(), true, "scope toggle flips")
  scope.run({})
  eq(scope_state.enabled(), false, "no argument toggles")
  scope.run({ "status" })
  eq(scope_state.enabled(), false, "status changes nothing")
  eq(logs.info[#logs.info], "fenced-block scope disabled", "status reports the state")
  scope.run({ "sideways" })
  ok(logs.warn[1] and logs.warn[1]:find("Usage", 1, true), "unknown argument warns")
  eq(table.concat(scope.complete("t"), ","), "toggle", "completes the subcommand")
  eq(#scope.complete(""), 4, "empty lead offers all four")

  -- ── commands/markdown_links ──────────────────────────────────────────────
  local copied
  package.loaded["markdown.util.clipboard"] = {
    copy = function(text)
      copied = text
      return true
    end,
  }
  local links = fresh("markdown.commands.markdown_links")

  local root = H.tmproot("mdnvim_links_spec")
  vim.fn.mkdir(root .. "/sub", "p")
  vim.fn.mkdir(root .. "/node_modules", "p")
  vim.fn.writefile({ "" }, root .. "/b.md")
  vim.fn.writefile({ "" }, root .. "/a.md")
  vim.fn.writefile({ "" }, root .. "/sub/c.md")
  vim.fn.writefile({ "" }, root .. "/node_modules/x.md")

  local function titles(text)
    local out = {}
    for t in text:gmatch("%[([^%]]+)%]") do
      out[#out + 1] = t
    end
    return table.concat(out, ",")
  end

  eq(titles(links.for_paths({ root })), "a.md,b.md", "sorted, not recursive")
  eq(
    titles(links.for_paths({ root }, { recursive = true })),
    "a.md,b.md,c.md",
    "recursive skips ignored dirs"
  )
  eq(
    titles(links.for_paths({ root }, { recursive = true, noignore = true })),
    "a.md,b.md,x.md,c.md",
    "noignore lists ignored dirs (sorted by path)"
  )
  ok(
    links.for_paths({ root .. "/a.md" }):find("](" .. root .. "/a.md)", 1, true),
    "a file gives its own link"
  )

  reset_logs()
  links.run({})
  eq(#logs.error, 1, "no path prints the usage as an error")

  copied = nil
  links.run({ "-r", "--noignore", root })
  eq(titles(copied), "a.md,b.md,x.md,c.md", "run parses -r and --noignore")
  copied = nil
  links.run({ root })
  eq(titles(copied), "a.md,b.md", "run defaults to a flat, filtered scan")
  ok(logs.info[#logs.info]:find("copied", 1, true), "run reports the copy")

  -- ── util/progress ────────────────────────────────────────────────────────
  package.loaded["markdown.util.progress"] = nil
  local has_lib = pcall(require, "lib.nvim.progress")
  local progress = require("markdown.util.progress")
  if has_lib then
    ok(progress.create("scan", 3) ~= nil, "a handle comes back when lib.nvim.progress exists")
  end

  local saved_loaded, saved_preload =
    package.loaded["lib.nvim.progress"], package.preload["lib.nvim.progress"]
  package.loaded["lib.nvim.progress"] = nil
  package.preload["lib.nvim.progress"] = function() error("absent") end
  package.loaded["markdown.util.progress"] = nil
  eq(
    require("markdown.util.progress").create("scan", 3),
    nil,
    "no lib.nvim.progress: nil, no error"
  )
  package.loaded["lib.nvim.progress"], package.preload["lib.nvim.progress"] =
    saved_loaded, saved_preload

  for _, m in ipairs({
    "markdown.util.notify",
    "markdown.util.clipboard",
    "markdown.util.progress",
    "markdown.commands.headings",
    "markdown.commands.scope",
    "markdown.commands.markdown_links",
  }) do
    package.loaded[m] = nil
  end
end
