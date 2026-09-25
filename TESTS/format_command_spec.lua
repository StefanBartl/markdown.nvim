-- Test code: when something here comes back nil -- a fixture read, a uv
-- handle -- this file must crash and name it.
---@diagnostic disable: need-check-nil
-- TESTS/format_command_spec.lua — `:Markdown format` end to end
-- (commands.format's arg parsing + util.scope's %/cfile/cwd/path vocabulary),
-- and its feature gating / completion through the `:Markdown` dispatcher.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local ok = H.ok

  local config = require("markdown.config")
  local commands = require("markdown.commands")
  local scope_util = require("markdown.util.scope")

  config.setup({})

  -- ── util.scope: the vocabulary itself ─────────────────────────────────────

  do
    local buf = H.scratch("markdown")
    local res, err = scope_util.resolve(nil)
    eq(err, nil, "resolve(nil): no error")
    eq(res.kind, "buffer", "resolve(nil): defaults to the current buffer")
    eq(res.bufnr, buf, "resolve(nil): the current buffer number")

    local res2 = scope_util.resolve("%")
    eq(res2.kind, "buffer", 'resolve("%"): same as nil')

    local res3, err3 = scope_util.resolve("cfile")
    eq(res3, nil, "resolve('cfile'): nothing under an empty cursor position")
    ok(err3 ~= nil, "resolve('cfile'): reports why")
  end

  do
    local root = H.tmproot("mdnvim_format_scope_spec")
    vim.fn.mkdir(root .. "/sub", "p")
    vim.fn.writefile({ "**a**" }, root .. "/one.md")
    vim.fn.writefile({ "**b**" }, root .. "/sub/two.md")
    vim.fn.writefile({ "not markdown" }, root .. "/note.txt")

    local res, err = scope_util.resolve(root)
    eq(err, nil, "resolve(dir): no error")
    eq(res.kind, "files", "resolve(dir): a directory resolves to files")
    eq(#res.paths, 2, "resolve(dir): recurses, only *.md files")

    local single, serr = scope_util.resolve(root .. "/one.md")
    eq(serr, nil, "resolve(file): no error")
    eq(#single.paths, 1, "resolve(file): exactly the one file")

    local missing, merr = scope_util.resolve(root .. "/nope.md")
    eq(missing, nil, "resolve(missing): nil result")
    ok(merr ~= nil, "resolve(missing): reports why")
  end

  -- cfile: resolves the filename under the cursor, relative to the naming
  -- buffer's own directory (not the process cwd).
  do
    local root = H.tmproot("mdnvim_format_cfile_spec")
    vim.fn.writefile({ "**target**" }, root .. "/target.md")

    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_name(buf, root .. "/main.md")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "See target.md for details." })
    vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- inside "target.md"

    local res, err = scope_util.resolve("cfile")
    eq(err, nil, "resolve('cfile'): no error")
    eq(res.kind, "files", "resolve('cfile'): a single file")
    eq(#res.paths, 1, "resolve('cfile'): exactly one path")
    ok(res.paths[1]:match("target%.md$") ~= nil, "resolve('cfile'): the file under the cursor")
  end

  -- ── :Markdown format, end to end through the command dispatcher ──────────

  -- Default scope (buffer), via commands.execute (feature-gated dispatch).
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "**bold** and __also bold__" })
    commands.execute({ "format", "strip-bold" })
    eq(
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "bold and also bold",
      "execute: default scope is the current buffer"
    )
  end

  -- Multiple ops compose, applied in the given order.
  do
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "**bold** ~~struck~~ trailing  " })
    commands.execute({ "format", "strip-bold", "strip-strikethrough" })
    eq(
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "bold struck trailing  ",
      "execute: both ops applied, hard-break spaces untouched (no trim op given)"
    )
  end

  -- scope=cwd: rewrites every *.md file under the working directory on disk.
  do
    local root = H.tmproot("mdnvim_format_cwd_spec")
    vim.fn.writefile({ "**one**" }, root .. "/one.md")
    vim.fn.writefile({ "**two**" }, root .. "/two.md")

    local prev_cwd = vim.fn.getcwd()
    local chdir_ok, chdir_err = pcall(vim.fn.chdir, root)
    ok(chdir_ok, "chdir into the fixture root: " .. tostring(chdir_err))

    local run_ok, run_err = pcall(function()
      commands.execute({ "format", "strip-bold", "scope=cwd" })
      eq(vim.fn.readfile(root .. "/one.md")[1], "one", "cwd scope: first file rewritten")
      eq(vim.fn.readfile(root .. "/two.md")[1], "two", "cwd scope: second file rewritten")
    end)

    vim.fn.chdir(prev_cwd)
    if not run_ok then error(run_err, 0) end
  end

  -- dry-run: reports without writing, whatever the scope.
  do
    local root = H.tmproot("mdnvim_format_dryrun_spec")
    local path = root .. "/doc.md"
    vim.fn.writefile({ "**bold**" }, path)

    commands.execute({ "format", "strip-bold", "scope=" .. path, "dry-run" })
    eq(vim.fn.readfile(path)[1], "**bold**", "dry-run: file left untouched")
  end

  -- Feature gating: `features.disable = { "format" }` skips the command
  -- entirely, the same way it does for every other :Markdown subcommand.
  do
    config.setup({ features = { disable = { "format" } } })
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "**bold**" })
    commands.execute({ "format", "strip-bold" })
    eq(
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1],
      "**bold**",
      "disabled feature: format does not run"
    )
    config.setup({})
  end

  -- Bad/empty input doesn't crash the command (usage message / warning only).
  do
    local run_ok = pcall(commands.execute, { "format" })
    ok(run_ok, "no ops given: reports usage, does not error")
    local run_ok2 = pcall(commands.execute, { "format", "not-a-real-op" })
    ok(run_ok2, "unknown op: reports an error, does not crash")
  end

  -- ── completion: an open-ended run of ops/flags, at every slot ─────────────

  do
    ---@param list string[]
    ---@param want string
    ---@return boolean
    local function has(list, want)
      for _, v in ipairs(list) do
        if v == want then return true end
      end
      return false
    end

    local first = commands.complete("", "Markdown format ")
    ok(has(first, "strip-bold"), "format: offers strip-bold at the first slot")
    ok(has(first, "scope=cwd"), "format: offers scope=cwd at the first slot")

    local second = commands.complete("", "Markdown format strip-bold ")
    ok(has(second, "strip-strikethrough"), "format: still completing ops at the second slot")
    ok(has(second, "dry-run"), "format: dry-run offered alongside the ops")
  end

  config.setup({})
end
