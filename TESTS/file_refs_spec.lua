-- TESTS/file_refs_spec.lua — core.file_refs: project-wide "who links to this
-- path" search, and util.path.resolve_from (link resolution against an
-- arbitrary base dir, not just the current buffer).
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local ok = H.ok

  package.loaded["markdown_nvim.util.path"] = nil
  package.loaded["markdown_nvim.core.file_refs"] = nil
  local path      = require("markdown_nvim.util.path")
  local file_refs = require("markdown_nvim.core.file_refs")

  local win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
  local function os_native(p) return win and (p:gsub("/", "\\")) or p end

  local root = (vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/mdnvim_filerefsspec"):gsub("\\", "/")

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
    -- Links to target.md relative to their own directory.
    write("docs/linker_same_dir.md", { "See [target](target.md) for details." })
    write("docs/sub/linker_nested.md", { "Back to [target](../target.md)." })
    -- A link to something else entirely — must NOT show up as a match.
    write("docs/unrelated.md", { "[other](other.md)" })
    -- An in-document anchor link — must be skipped (not a cross-file target).
    write("docs/anchor_only.md", { "[jump](#target)" })
    -- A link inside a fenced code block — link_scan already skips fences.
    write("docs/fenced.md", { "```", "[target](target.md)", "```" })
    -- Ignored directory: even though it contains a matching link, it must not
    -- be reported.
    write(".git/ignored.md", { "[target](../docs/target.md)" })

    -- util.path.resolve_from: resolves relative to an explicit base dir, not
    -- the current buffer (which the plain resolve() would use).
    local resolved = path.resolve_from("target.md", root .. "/docs")
    eq(resolved, os_native(target), "resolve_from: resolves against the given base dir")
    local resolved_nested = path.resolve_from("../target.md", root .. "/docs/sub")
    eq(resolved_nested, os_native(target), "resolve_from: '..' climbs from the given base dir")

    -- find_references: the actual project-wide search.
    local refs = file_refs.find_references(target, { root = root })
    eq(#refs, 2, "find_references: exactly the 2 real links to target.md, not the unrelated/anchor/ignored ones")

    local files = {}
    for _, r in ipairs(refs) do files[vim.fn.fnamemodify(r.file, ":t")] = true end
    ok(files["linker_same_dir.md"], "find_references: found the same-dir linker")
    ok(files["linker_nested.md"], "find_references: found the nested ('..') linker")

    -- No target -> no crash, empty result.
    eq(#file_refs.find_references("", { root = root }), 0, "find_references: empty target_path -> []")
  end)

  pcall(vim.fn.delete, root, "rf")
  package.loaded["markdown_nvim.util.path"] = nil
  package.loaded["markdown_nvim.core.file_refs"] = nil

  if not run_ok then error(err, 0) end
end
