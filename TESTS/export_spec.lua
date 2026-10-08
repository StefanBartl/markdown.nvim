-- Test code: when something here comes back nil -- a fixture read, a uv
-- handle -- this file must crash and name it.
---@diagnostic disable: need-check-nil, missing-fields
-- TESTS/export_spec.lua -- `:Markdown export pdf [path]` (markdown.commands.export).
--
-- pdfport.nvim is replaced by a stub that records what `create()` is asked to export, so the spec
-- pins which SOURCE is chosen: the file named by `path`, the buffer's own file, or the live buffer.
--
-- Regression: with the current buffer modified, `:Markdown export pdf other.md` skipped the
-- "export the file from disk" branch (it needs an unmodified buffer) and fell through to the live
-- buffer: the unsaved text of the OTHER buffer was written to `other.pdf`.

return function(H)
  local eq, ok = H.eq, H.ok

  local root = H.tmproot("mdnvim_export_spec")
  vim.fn.writefile({ "# current" }, root .. "/cur.md")
  vim.fn.writefile({ "# other" }, root .. "/other.md")

  local create_calls, warnings = {}, {}
  package.loaded["pdfport"] = {
    can_create = function() return true end,
    create = function(opts) create_calls[#create_calls + 1] = opts end,
  }
  package.loaded["markdown.util.notify"] = {
    create = function()
      return {
        info = function() end,
        warn = function(msg) warnings[#warnings + 1] = msg end,
        error = function() end,
        debug = function() end,
      }
    end,
  }
  package.loaded["markdown.commands.export"] = nil
  local export = require("markdown.commands.export")

  --- Open `cur.md` and optionally make it modified, then run the export.
  ---@param modified boolean
  ---@param path string|nil
  ---@return table|nil call  what pdfport.create() received, nil when it was not called
  local function run(modified, path)
    create_calls, warnings = {}, {}
    vim.cmd("silent! %bwipeout!")
    vim.cmd.edit(vim.fn.fnameescape(root .. "/cur.md"))
    if modified then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# unsaved text of the current buffer" })
    end
    eq(
      vim.bo.modified,
      modified,
      "fixture: the buffer is " .. (modified and "" or "not ") .. "modified"
    )
    export.run(path and { "pdf", path } or { "pdf" })
    eq(#create_calls <= 1, true, "pdfport.create() runs at most once")
    return create_calls[1]
  end

  local function inputs_of(call) return call and call.inputs and call.inputs[1] end

  local function same(a, b) return vim.fs.normalize(a):lower() == vim.fs.normalize(b):lower() end

  -- The defect: another file was named while the current buffer has unsaved changes.
  do
    local call = run(true, root .. "/other.md")
    ok(call ~= nil, "a modified current buffer + another file: pdfport.create() was called")
    eq(call.bufnr, nil, "the unsaved current buffer is NOT the source of the other file's pdf")
    ok(inputs_of(call) and same(inputs_of(call), root .. "/other.md"), "the named file is exported")
    eq(call.output, nil, "pdfport picks the output next to the input")
  end

  -- Same, with a relative path (the usual `:Markdown export pdf other.md`).
  do
    local old_cwd = vim.fn.getcwd()
    vim.fn.chdir(root)
    local call = run(true, "other.md")
    vim.fn.chdir(old_cwd)
    ok(call ~= nil and call.bufnr == nil, "relative path: not the live buffer")
    ok(
      inputs_of(call) ~= nil and same(inputs_of(call), "other.md"),
      "relative path: the named file"
    )
  end

  -- Another file with an unmodified buffer: the same answer as before.
  do
    local call = run(false, root .. "/other.md")
    ok(call ~= nil and call.bufnr == nil, "unmodified buffer + another file: not the live buffer")
    ok(inputs_of(call) ~= nil and same(inputs_of(call), root .. "/other.md"), "the named file")
  end

  -- No path: unmodified buffer exports its file, a modified one its live content.
  do
    local call = run(false, nil)
    ok(
      call ~= nil and inputs_of(call) ~= nil and same(inputs_of(call), root .. "/cur.md"),
      "no path, unmodified: the buffer's file"
    )
    eq(call.bufnr, nil, "no path, unmodified: not the live buffer")

    call = run(true, nil)
    ok(call ~= nil, "no path, modified: pdfport.create() was called")
    eq(call.bufnr, 0, "no path, modified: the live buffer is exported")
    eq(call.inputs, nil, "no path, modified: no file input")
    ok(same(call.output, root .. "/cur.pdf"), "no path, modified: pdf next to the buffer's file")
  end

  -- A path that names the current buffer's OWN file, spelled another way, is still "the buffer":
  -- its unsaved text is what the user means.
  do
    local call = run(true, root .. "/./cur.md")
    ok(call ~= nil and call.bufnr == 0, "own file spelled with ./ : the live buffer")
    eq(call.inputs, nil, "own file spelled with ./ : no file input")

    call = run(true, (root .. "/cur.md"):gsub("/", "\\"))
    ok(call ~= nil and call.bufnr == 0, "own file spelled with backslashes: the live buffer")

    call = run(false, root .. "/cur.md")
    ok(
      call ~= nil and inputs_of(call) ~= nil and same(inputs_of(call), root .. "/cur.md"),
      "own file, unmodified: exported from disk"
    )
  end

  -- A file that is not there: say so, export nothing (it used to export the current buffer as
  -- buffer.pdf without a word).
  do
    local call = run(true, root .. "/missing.md")
    eq(call, nil, "an unreadable path exports nothing")
    eq(#warnings, 1, "an unreadable path warns once")
    ok((warnings[1] or ""):find("missing.md", 1, true) ~= nil, "the warning names the file")

    call = run(false, root)
    eq(call, nil, "a directory is not a file to export")
  end

  -- A new buffer that has not been saved yet, named by `path`: it is the live buffer.
  do
    create_calls, warnings = {}, {}
    vim.cmd("silent! %bwipeout!")
    vim.cmd.edit(vim.fn.fnameescape(root .. "/unsaved_new.md"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# not on disk yet" })
    export.run({ "pdf", root .. "/unsaved_new.md" })
    ok(
      create_calls[1] ~= nil and create_calls[1].bufnr == 0,
      "an unsaved new file: the live buffer"
    )
    eq(#warnings, 0, "an unsaved new file does not warn")
  end

  package.loaded["pdfport"] = nil
  package.loaded["markdown.util.notify"] = nil
  package.loaded["markdown.commands.export"] = nil
end
