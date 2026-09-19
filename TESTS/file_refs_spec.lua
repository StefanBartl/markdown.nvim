-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
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
  local root = H.tmproot("mdnvim_filerefsspec")

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
  local root2 = H.tmproot("mdnvim_filerefsspec2")
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

  pcall(function() vim.cmd("cd " .. vim.fn.fnameescape(prev_cwd)) end)
  pcall(vim.fn.delete, root2, "rf")
  package.loaded["markdown.util.path"] = nil
  package.loaded["markdown.core.file_refs"] = nil

  if not run_ok2 then error(err2, 0) end

  -- ── rg failure falls back to the exhaustive glob scan, not to "0 refs" ──
  -- Regression for the bug where an errored `rg` run (root vanished,
  -- permission denied, killed mid-scan, ...) and a genuinely empty result
  -- both collapsed to `{}`. A caller (e.g. core.link_delete's "N other links
  -- point at it" dialog) cannot tell "confirmed nothing else links here" from
  -- "the scan broke and we don't know" -- and would let a file be deleted out
  -- from under links it could not see. Forcing `vim.system` to report an rg
  -- error (exit code 2) here must still surface the real reference via the
  -- glob fallback, both sync and async.
  package.loaded["markdown.util.path"] = nil
  package.loaded["markdown.core.file_refs"] = nil
  local file_refs3 = require("markdown.core.file_refs")

  local root3 = (vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/mdnvim_filerefsspec3"):gsub(
    "\\",
    "/"
  )

  local run_ok3, err3 = pcall(function()
    vim.fn.mkdir(root3 .. "/docs", "p")
    local target = root3 .. "/docs/target.md"
    local function write(rel, lines)
      local fh = io.open(root3 .. "/" .. rel, "w")
      ok(fh ~= nil, "fixture3 write: " .. rel)
      fh:write(table.concat(lines, "\n"))
      fh:close()
    end
    write("docs/target.md", { "# Target" })
    write("docs/linker.md", { "[t](target.md)" })

    ok(vim.fn.executable("rg") == 1, "this regression needs rg on PATH to exercise the rg path")

    local real_system = vim.system
    vim.system = function(_cmd, _opts, cb)
      local fake = { code = 2, signal = 0, stdout = "", stderr = "rg: forced failure for test" }
      if cb then
        vim.schedule(function() cb(fake) end)
        return { wait = function() return fake end }
      end
      return { wait = function() return fake end }
    end

    local refs_ok, refs = pcall(file_refs3.find_references, target, { root = root3 })
    vim.system = real_system
    ok(refs_ok, "find_references: survives a forced rg error")
    eq(
      #refs,
      1,
      "find_references: rg error falls back to the glob scan instead of reporting 0 refs"
    )

    vim.system = function(_cmd, _opts, cb)
      local fake = { code = 2, signal = 0, stdout = "", stderr = "rg: forced failure for test" }
      vim.schedule(function() cb(fake) end)
      return { wait = function() return fake end }
    end

    local async_refs, done = nil, false
    file_refs3.find_references_async(target, { root = root3 }, function(r)
      async_refs = r
      done = true
    end)
    vim.wait(3000, function() return done end)
    vim.system = real_system
    ok(done, "find_references_async: callback fired despite the forced rg error")
    eq(
      #(async_refs or {}),
      1,
      "find_references_async: rg error falls back to the glob scan instead of reporting 0 refs"
    )
  end)

  pcall(vim.fn.delete, root3, "rf")
  package.loaded["markdown.util.path"] = nil
  package.loaded["markdown.core.file_refs"] = nil

  if not run_ok3 then error(err3, 0) end

  -- ── an unreadable candidate file is "we don't know", not "no reference" ───
  -- Regression for ERR-11: `scan()`'s per-file `pcall(vim.fn.readfile, ...)`
  -- used to drop a file that fails to read (permission error, or it vanished
  -- in the TOCTOU window between the rg/glob listing and this read) with no
  -- trace at all -- indistinguishable from a file that read fine and simply
  -- carried no matching link. Left unfixed, `link_delete`'s "N other links
  -- point at it" dialog could tell a user "0 others" while a real reference
  -- sat in a file it never actually managed to read. `determined = false`
  -- now says the count may be a lower bound instead.
  do
    package.loaded["markdown.core.file_refs"] = nil
    local file_refs5 = require("markdown.core.file_refs")
    local root5 = H.tmproot("mdnvim_filerefs_unreadable_fixture")
    local real_readfile = vim.fn.readfile

    local run_ok5, err5 = pcall(function()
      vim.fn.mkdir(root5 .. "/docs", "p")
      local target = root5 .. "/docs/target.md"
      local function write(rel, lines)
        local fh = io.open(root5 .. "/" .. rel, "w")
        ok(fh ~= nil, "fixture5 write: " .. rel)
        fh:write(table.concat(lines, "\n"))
        fh:close()
      end
      write("docs/target.md", { "# Target" })
      write("docs/linker.md", { "[t](target.md)" }) -- carries the real reference

      local blocked = vim.fs.normalize(root5 .. "/docs/linker.md")
      local function readfile_blocking_linker(fname, ...)
        if vim.fs.normalize(fname) == blocked then error("E484: simulated unreadable file", 0) end
        return real_readfile(fname, ...)
      end

      vim.fn.readfile = readfile_blocking_linker
      local refs, determined = file_refs5.find_references(target, { root = root5 })
      vim.fn.readfile = real_readfile

      eq(
        determined,
        false,
        "find_references: an unreadable candidate marks the result undetermined"
      )
      eq(
        #refs,
        0,
        "find_references: the unreadable file's real reference is not silently reported as absent"
      )

      -- Async variant carries the same flag through to its callback.
      vim.fn.readfile = readfile_blocking_linker
      local async_refs, async_determined, done = nil, nil, false
      file_refs5.find_references_async(target, { root = root5 }, function(r, d)
        async_refs, async_determined, done = r, d, true
      end)
      vim.wait(3000, function() return done end)
      vim.fn.readfile = real_readfile
      ok(done, "find_references_async: callback fired")
      eq(#(async_refs or {}), 0, "find_references_async: same lower-bound count as the sync path")
      eq(
        async_determined,
        false,
        "find_references_async: same undetermined flag reaches the callback"
      )
    end)

    vim.fn.readfile = real_readfile
    pcall(vim.fn.delete, root5, "rf")
    package.loaded["markdown.core.file_refs"] = nil
    if not run_ok5 then error(err5, 0) end
  end

  -- ── 8.3 short-form paths (Windows) ────────────────────────────────────────
  --
  -- Windows gives a directory whose name is longer than eight characters a
  -- second, "short" spelling (MDNVIM~1), and that is what %TEMP% and
  -- tempname() expand to for a profile name over eight characters -- true of
  -- the CI runner ("runneradmin") and of plenty of real machines.
  --
  -- Both spellings name one directory, so find_references has to answer the
  -- same either way. It did not: the root reached rg in whatever spelling it
  -- was handed and rg echoed that spelling back in every path it reported,
  -- while the target was compared in the other one -- so a file WITH
  -- references reported zero. To the delete-confirm caller that is
  -- indistinguishable from "nothing links here", which is how a file gets
  -- deleted out from under its own links.
  --
  -- Skipped where no short form exists (non-Windows, or a volume with 8.3
  -- generation turned off) rather than faked: the hazard is specific to it.
  do
    package.loaded["markdown.core.file_refs"] = nil
    local file_refs4 = require("markdown.core.file_refs")
    local root4 = H.tmproot("mdnvim_filerefs_shortname_fixture")

    local run_ok4, err4 = pcall(function()
      vim.fn.mkdir(root4 .. "/docs", "p")
      local fh = io.open(root4 .. "/docs/target.md", "w")
      ok(fh ~= nil, "fixture4: target.md opened for writing")
      fh:write("# Target")
      fh:close()
      fh = io.open(root4 .. "/docs/linker.md", "w")
      ok(fh ~= nil, "fixture4: linker.md opened for writing")
      fh:write("[t](target.md)")
      fh:close()

      local short
      if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
        local out = vim.fn.system({
          "cmd",
          "/c",
          'for %I in ("' .. root4:gsub("/", "\\") .. '") do @echo %~sI',
        })
        short = vim.trim(out or ""):gsub("\\", "/")
      end

      if not short or short == "" or not short:find("~", 1, true) then
        return -- no short form on this host: nothing to assert
      end

      local refs = file_refs4.find_references(short .. "/docs/target.md", { root = short })
      eq(#refs, 1, "find_references: a target spelled in 8.3 short form finds the same reference")
    end)

    pcall(vim.fn.delete, root4, "rf")
    package.loaded["markdown.core.file_refs"] = nil
    if not run_ok4 then error(err4, 0) end
  end
end
