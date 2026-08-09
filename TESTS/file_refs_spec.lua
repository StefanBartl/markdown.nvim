-- TESTS/file_refs_spec.lua — core.file_refs: project-wide "who links to this
-- path" search (rg-prefiltered), style-tracing resolution, retarget(), and the
-- async variant.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local ok = H.ok

  package.loaded["markdown.util.path"] = nil
  package.loaded["markdown.core.file_refs"] = nil
  local path = require("markdown.util.path")
  local file_refs = require("markdown.core.file_refs")

  local win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
  local function os_native(p) return win and (p:gsub("/", "\\")) or p end

  -- ── Basic search (no cd): same-dir + nested, skipping unrelated/anchor/fenced/ignored ──
  local root = (vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/mdnvim_filerefsspec"):gsub(
    "\\",
    "/"
  )

  local run_ok, err = pcall(function()
    vim.fn.mkdir(root .. "/docs/sub", "p")
    vim.fn.mkdir(root .. "/.git", "p") -- must be skipped by the ignore list

    local target = root .. "/docs/target.md"
    local function write(rel, lines)
      local fh = io.open(root .. "/" .. rel, "w")
      ok(fh ~= nil, "fixture write: " .. rel)
      fh:write(table.concat(lines, "\n"))
      fh:close()
    end

    write("docs/target.md", { "# Target" })
    write("docs/linker_same_dir.md", { "See [target](target.md) for details." })
    write("docs/sub/linker_nested.md", { "Back to [target](../target.md)." })
    write("docs/unrelated.md", { "[other](other.md)" })
    write("docs/anchor_only.md", { "[jump](#target)" })
    write("docs/fenced.md", { "```", "[target](target.md)", "```" })
    write(".git/ignored.md", { "[target](../docs/target.md)" })

    local resolved = path.resolve_from("target.md", root .. "/docs")
    eq(resolved, os_native(target), "resolve_from: resolves against the given base dir")
    local resolved_nested = path.resolve_from("../target.md", root .. "/docs/sub")
    eq(resolved_nested, os_native(target), "resolve_from: '..' climbs from the given base dir")

    local refs = file_refs.find_references(target, { root = root })
    eq(
      #refs,
      2,
      "find_references: exactly the 2 real links to target.md, not the unrelated/anchor/ignored ones"
    )

    local files = {}
    for _, r in ipairs(refs) do
      files[vim.fn.fnamemodify(r.file, ":t")] = true
    end
    ok(files["linker_same_dir.md"], "find_references: found the same-dir linker")
    ok(files["linker_nested.md"], "find_references: found the nested ('..') linker")

    eq(
      #file_refs.find_references("", { root = root }),
      0,
      "find_references: empty target_path -> []"
    )
  end)

  pcall(vim.fn.delete, root, "rf")

  if not run_ok then
    package.loaded["markdown.util.path"] = nil
    package.loaded["markdown.core.file_refs"] = nil
    error(err, 0)
  end

  -- ── cwd-relative links + retarget style preservation + async (cd into root) ──
  -- Reproduces the reported bug: a link written relative to cwd (not the file's
  -- own dir) must be found, and each style must be preserved on retarget.
  local root2 = (vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/mdnvim_filerefsspec2"):gsub(
    "\\",
    "/"
  )
  local prev_cwd = vim.fn.getcwd()

  local run_ok2, err2 = pcall(function()
    vim.fn.mkdir(root2 .. "/docs/sub", "p")
    local target = root2 .. "/docs/target.md"
    local function write(rel, lines)
      local fh = io.open(root2 .. "/" .. rel, "w")
      ok(fh ~= nil, "fixture2 write: " .. rel)
      fh:write(table.concat(lines, "\n"))
      fh:close()
    end
    write("docs/target.md", { "# Target" })
    write("docs/a_same.md", { "[t](target.md)" }) -- base = docs, no dot
    write("docs/a_dot.md", { "[t](./target.md)" }) -- base = docs, dot prefix
    write("docs/a_cwd.md", { "[t](docs/target.md)" }) -- base = cwd (root2)
    write("docs/sub/a_up.md", { "[t](../target.md)" }) -- base = docs/sub

    vim.cmd("cd " .. vim.fn.fnameescape(root2))

    local refs = file_refs.find_references(target, { root = root2 })
    eq(
      #refs,
      4,
      "find_references: finds all 4 link styles incl. the cwd-relative one (the reported bug)"
    )

    -- Index refs by containing file for targeted retarget assertions.
    local by = {}
    for _, r in ipairs(refs) do
      by[vim.fn.fnamemodify(r.file, ":t")] = r
    end

    -- retarget each to a rename: docs/target.md -> docs/renamed.md
    local new_abs = root2 .. "/docs/renamed.md"
    eq(
      file_refs.retarget(by["a_same.md"], new_abs),
      "renamed.md",
      "retarget: plain same-dir keeps plain form"
    )
    eq(
      file_refs.retarget(by["a_dot.md"], new_abs),
      "./renamed.md",
      "retarget: './'-prefixed keeps the './' prefix"
    )
    eq(
      file_refs.retarget(by["a_cwd.md"], new_abs),
      "docs/renamed.md",
      "retarget: cwd-relative stays cwd-relative"
    )
    eq(
      file_refs.retarget(by["a_up.md"], new_abs),
      "../renamed.md",
      "retarget: '..'-climbing base recomputes correctly"
    )

    -- Async returns the same set as sync.
    local async_refs, done = nil, false
    file_refs.find_references_async(target, { root = root2 }, function(r)
      async_refs = r
      done = true
    end)
    vim.wait(3000, function() return done end)
    ok(done, "find_references_async: callback fired")
    eq(#(async_refs or {}), 4, "find_references_async: same 4 refs as the sync path")
  end)

  pcall(vim.cmd, "cd " .. vim.fn.fnameescape(prev_cwd))
  pcall(vim.fn.delete, root2, "rf")
  package.loaded["markdown.util.path"] = nil
  package.loaded["markdown.core.file_refs"] = nil

  if not run_ok2 then error(err2, 0) end
end
