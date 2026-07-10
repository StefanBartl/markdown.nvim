-- TESTS/path_spec.lua — util.path: separator/`.`/`..` normalization and
-- multi-base resolution (buffer dir first, then cwd) with existence probing.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local ok = H.ok

  package.loaded["markdown_nvim.util.path"] = nil
  local path = require("markdown_nvim.util.path")

  -- resolve() returns OS-native separators; normalize() stays slash-canonical.
  local win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
  local function os_native(p) return win and (p:gsub("/", "\\")) or p end

  -- normalize(): collapse `.`/`..` and unify separators, no filesystem access.
  eq(path.normalize("a/./b"), "a/b", "normalize: drops '.' segment")
  eq(path.normalize("a\\b\\c"), "a/b/c", "normalize: backslashes -> slashes")
  eq(path.normalize("a/b/../c"), "a/c", "normalize: collapses '..'")
  eq(path.normalize("a/b/./../c"), "a/c", "normalize: mixed './..' collapse")
  eq(path.normalize("../a"), "../a", "normalize: keeps leading '..' (relative)")

  -- URLs pass through untouched.
  eq(path.resolve("https://example.com/x"), "https://example.com/x", "resolve: URL unchanged")

  -- Multi-base resolution: a target authored relative to cwd (not the buffer
  -- dir) must still resolve — this is the reported double-`spickzettel` bug.
  local root = (vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/mdnvim_pathspec"):gsub("\\", "/")
  local prev_cwd = vim.fn.getcwd()

  -- Everything that changes cwd / touches the filesystem runs guarded so the
  -- teardown (cwd restore + rmdir) always happens, even on assertion failure.
  local run_ok, err = pcall(function()
    vim.fn.mkdir(root .. "/sub/deep", "p")
    local target_file = root .. "/sub/deep/file.md"
    local fh = io.open(target_file, "w"); if fh then fh:write("x"); fh:close() end

    -- Buffer lives in root/sub; cwd is root. A link written relative to cwd
    -- ("./sub/deep/file.md") would double "sub" under the buffer base and only
    -- resolve under the cwd base.
    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_name(buf, root .. "/sub/note.md")
    vim.cmd("cd " .. vim.fn.fnameescape(root))

    local resolved = path.resolve("./sub/deep/file.md")
    eq(resolved, os_native(root .. "/sub/deep/file.md"), "resolve: falls back to cwd base when buffer base misses")
    ok(vim.loop.fs_stat(resolved), "resolve: returned path exists on disk")

    -- Backslash-authored relative link resolves identically.
    local resolved_bs = path.resolve(".\\sub\\deep\\file.md")
    eq(resolved_bs, os_native(root .. "/sub/deep/file.md"), "resolve: backslash link resolves like slash link")

    -- A genuine miss returns the buffer-relative candidate (clean, normalized).
    local miss = path.resolve("./does/not/exist.md")
    eq(miss, os_native(root .. "/sub/does/not/exist.md"), "resolve: miss -> normalized buffer-relative candidate")
  end)

  -- Teardown (always).
  pcall(vim.cmd, "cd " .. vim.fn.fnameescape(prev_cwd))
  pcall(vim.fn.delete, root, "rf")
  package.loaded["markdown_nvim.util.path"] = nil

  if not run_ok then error(err, 0) end
end
