-- TESTS/table_scope_guards_spec.lua -- what `scope=cwd` (and any scope that rewrites files) leaves alone: vendored
-- trees, directories named like a file, tables in fenced code blocks; and what the width-capped format does to the
-- separator of a compact table.
---@diagnostic disable: need-check-nil

return function(H)
  local eq, ok = H.eq, H.ok
  local md_files = require("markdown.util.md_files")
  local fmt = require("markdown.core.table_fmt")
  local mdtable = require("markdown.commands.mdtable")

  local function write(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
  end
  local function read(path) return vim.fn.readfile(path) end

  -- ── md_files.collect ──────────────────────────────────────────────────────
  local root = H.tmproot("mdnvim_scope_guards_spec")
  write(root .. "/one.md", { "x" })
  write(root .. "/sub/two.md", { "x" })
  write(root .. "/UPPER.MD", { "x" })
  write(root .. "/node_modules/pkg/README.md", { "x" })
  write(root .. "/sub/node_modules/deep/README.md", { "x" })
  write(root .. "/.git/info/notes.md", { "x" })
  write(root .. "/.deps/lib/README.md", { "x" })
  write(root .. "/vendor/lib/README.md", { "x" })
  write(root .. "/docs.md/inner.md", { "x" }) -- a directory named like a file; what is in it is a file
  write(root .. "/note.txt", { "x" })

  local function names(paths)
    local out = {}
    for _, p in ipairs(paths) do
      out[#out + 1] = p:gsub("\\", "/"):sub(#(root:gsub("\\", "/")) + 2)
    end
    table.sort(out)
    return out
  end

  local found = names(md_files.collect(root))
  ok(
    vim.deep_equal(found, { "UPPER.MD", "docs.md/inner.md", "one.md", "sub/two.md" }),
    "collect: .md in any case, nothing vendored, the directory docs.md is not a file: "
      .. vim.inspect(found)
  )
  eq(
    #md_files.collect(root .. "/node_modules/pkg"),
    1,
    "collect: the folder the walk starts in is never skipped"
  )
  eq(#md_files.collect(root .. "/nope"), 0, "collect: a missing folder is empty, not an error")

  -- ── fenced tables ─────────────────────────────────────────────────────────
  local doc = {
    "|a|b|",
    "|---|---|",
    "|1|22|",
    "",
    "```md",
    "|x|y|",
    "|---|---|",
    "|3|4|",
    "```",
  }
  eq(
    #fmt.parse_all_tables(doc),
    1,
    "parse_all_tables: the table in the fence is not one of the document"
  )

  local wrapped = mdtable.format_lines(doc, { max = 40 })
  eq(wrapped[6], "|x|y|", "width-capped format: the table in the fence stays")
  eq(wrapped[1], "| a   | b   |", "width-capped format: the table outside is formatted")

  local file = root .. "/fenced.md"
  write(file, doc)
  local fok = fmt.format_tables_in_scope({ scope = file })
  ok(fok, "natural format of a file works")
  local after = read(file)
  eq(after[6], "|x|y|", "natural format of a file: the table in the fence stays")
  eq(after[1], "| a | b  |", "natural format of a file: the table outside is formatted")

  -- ── the separator of a compact table under a width cap ────────────────────
  local compact = { "|a|b|", "|-|-|", "|1|2|" }
  local strict = mdtable.format_lines(compact, { max = 40 })
  eq(
    strict[2],
    "| --- | --- |",
    "format max=N: restyles to the configured flavor (github: min 3, spaced separator)"
  )
  local loose = mdtable.format_lines(compact, { max = 40, flavor = "loose" })
  ok(
    loose[2]:match("^|[-|]+|$") ~= nil,
    "flavor = loose: the compact separator stays: " .. loose[2]
  )
end
