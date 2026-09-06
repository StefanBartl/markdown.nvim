---@module 'markdown.core.file_refs'
---@brief Find markdown files that link to a given filesystem path.
---@description
--- Project-wide reference search: finds `*.md` files whose inline links
--- (`link_scan`) resolve (`util.path.resolve_traced`) to a given path. Used by
--- third-party integrations (e.g. a file manager's delete/rename flow) to warn
--- before a linked-to file disappears, or to rewrite links after it moves.
---
--- One caller is now markdown.nvim's own: `core.link_delete` (the `DD` key)
--- asks for the count before offering to delete a file, which is what turns
--- that dialog into a decision. It still only *reports* -- nothing here acts
--- on the result, and `retarget` below produces a string rather than writing
--- one.
---
--- Performance: instead of reading every `*.md` file under the root, a ripgrep
--- prefilter (`rg --files-with-matches --fixed-strings <basename>`) narrows the
--- set to files that even mention the target's basename — a link to the file
--- must contain its basename verbatim — so only those handful of files are
--- read and parsed. A pure-Lua `globpath` path is kept as a fallback when
--- ripgrep isn't installed. Both sync and async entry points share the same
--- candidate → scan pipeline.

local link_scan = require("markdown.core.link_scan")
local path = require("markdown.util.path")
local globbable = require("lib.nvim.fs.globbable")
local ignore = require("markdown.util.ignore")

local M = {}

---@class MarkdownFileRef
---@field file           string   Absolute path of the markdown file containing the link.
---@field line           integer  1-indexed line number.
---@field target         string   Raw link target as written (e.g. `./old.md`).
---@field display        string   Full `[text](target)` as it appears in the file.
---@field base_dir       string|nil  Dir a relative target resolved against (for `retarget`); nil if absolute.
---@field is_absolute    boolean  Whether the raw target was already absolute.
---@field had_dot_prefix boolean  Whether the raw target started with `./` or `.\`.

--- True when any path segment of `p` is in the default ignore set
--- (`.git`, `node_modules`, `dist`, …).
---@param p string
---@return boolean
local function is_ignored(p)
  local ignored = ignore.as_set()
  for seg in p:gmatch("[^/\\]+") do
    if ignored[seg] then return true end
  end
  return false
end

--- Basename used as the ripgrep prefilter needle. A link to `target_path` must
--- contain its final path component verbatim (works for files and directories).
---@param target_path string
---@return string|nil
local function needle_for(target_path)
  local base = vim.fn.fnamemodify(target_path, ":t")
  return (base ~= "") and base or nil
end

--- Build the `rg --files-with-matches` argv for the prefilter.
---@param root string
---@param needle string
---@return string[]
local function rg_cmd(root, needle)
  return {
    "rg",
    "--files-with-matches",
    "--fixed-strings",
    "--color=never",
    "-g",
    "*.md",
    "-g",
    "!.git/*",
    "-g",
    "!node_modules/*",
    "--",
    needle,
    root,
  }
end

--- Parse `rg --files-with-matches` stdout into a file list, and report
--- whether rg actually completed a determination. rg exits 0 with matches, 1
--- with none -- both are a real, trustworthy answer. Any other exit code (or
--- none at all, e.g. the process was killed) means rg did NOT determine
--- anything, and callers must not treat that the same as "confirmed zero
--- references": `find_references`/`find_references_async` fall back to the
--- exhaustive glob scan in that case rather than silently reporting an empty
--- list. Collapsing "no matches" and "search failed" into the same `{}` is
--- exactly the kind of ambiguity that turned a delete confirmation ("N other
--- links point at it") into a false "0 others" when rg errored out.
---@param result vim.SystemCompleted
---@return string[] files
---@return boolean determined  false when rg errored and `files` cannot be trusted
local function rg_files(result)
  local files = {}
  local determined = result.code ~= nil and result.code <= 1
  if determined then
    for line in (result.stdout or ""):gmatch("[^\r\n]+") do
      files[#files + 1] = line
    end
  end
  return files, determined
end

--- Pure-Lua fallback candidate list (every `*.md` under root).
---@param root string
---@return string[]
local function glob_files(root) return vim.fn.globpath(globbable(root), "**/*.md", false, true) end

--- Scan a candidate file list for links resolving to `wanted` (a normalized,
--- lower-cased absolute path). Reads each file fully so fenced code blocks are
--- skipped (link_scan.from_lines is fence-aware) — the same correctness the
--- non-prefiltered version had.
---@param files string[]
---@param wanted string
---@return MarkdownFileRef[]
local function scan(files, wanted)
  local out = {}
  for _, file in ipairs(files) do
    if not is_ignored(file) then
      local ok, lines = pcall(vim.fn.readfile, file)
      if ok and lines then
        local file_dir = vim.fn.fnamemodify(file, ":h")
        for _, lk in ipairs(link_scan.from_lines(lines)) do
          if lk.kind == "mdlink" and lk.target and not lk.target:match("^#") then
            local resolved, base_used, is_abs = path.resolve_traced(lk.target, file_dir)
            if resolved and path.normalize(resolved):lower() == wanted then
              out[#out + 1] = {
                file = file,
                line = lk.lnum,
                target = lk.target,
                display = lk.display,
                base_dir = base_used,
                is_absolute = is_abs,
                had_dot_prefix = lk.target:match("^%.[/\\]") ~= nil,
              }
            end
          end
        end
      end
    end
  end
  return out
end

--- Find every `*.md` file under `root` whose link(s) resolve to `target_path`.
--- Synchronous. Uses the ripgrep prefilter when available, else globs.
---@param target_path string  Absolute filesystem path being searched for.
---@param opts? { root?: string }  `root` defaults to the current working directory.
---@return MarkdownFileRef[]
function M.find_references(target_path, opts)
  opts = opts or {}
  if not target_path or target_path == "" then return {} end

  local root = opts.root or vim.fn.getcwd()
  local wanted = path.normalize(target_path):lower()
  local needle = needle_for(target_path)

  local files
  if needle and vim.fn.executable("rg") == 1 then
    local rg_result, determined = rg_files(vim.system(rg_cmd(root, needle), { text = true }):wait())
    -- An errored rg run (root vanished, permission denied, killed, ...) is
    -- "we don't know", not "zero candidates" -- fall back to the exhaustive
    -- glob so a real answer, not a false negative, reaches the caller.
    files = determined and rg_result or glob_files(root)
  else
    files = glob_files(root)
  end

  return scan(files, wanted)
end

--- Async variant: identical result to `find_references`, but the (potentially
--- slow) candidate discovery runs off the main loop via `vim.system`. The
--- `callback` receives the ref list, scheduled on the main loop so it may touch
--- buffers/vim state freely. Falls back to a scheduled sync glob+scan when
--- ripgrep isn't installed.
---@param target_path string
---@param opts? { root?: string }
---@param callback fun(refs: MarkdownFileRef[])
function M.find_references_async(target_path, opts, callback)
  opts = opts or {}
  if not target_path or target_path == "" then
    vim.schedule(function() callback({}) end)
    return
  end

  local root = opts.root or vim.fn.getcwd()
  local wanted = path.normalize(target_path):lower()
  local needle = needle_for(target_path)

  if needle and vim.fn.executable("rg") == 1 then
    vim.system(rg_cmd(root, needle), { text = true }, function(result)
      local files, determined = rg_files(result)
      -- glob_files uses vim.fn.*, which needs the main loop -- do the
      -- fallback decision (and the call itself) inside vim.schedule, same as
      -- the "rg not installed" branch below.
      vim.schedule(function()
        if not determined then files = glob_files(root) end
        callback(scan(files, wanted))
      end)
    end)
  else
    vim.schedule(function() callback(scan(glob_files(root), wanted)) end)
  end
end

--- Re-express a moved/renamed target in the same style the original ref used,
--- so an auto-updated link reads the way the author wrote it:
---   - absolute original          → absolute new path (slash-normalized)
---   - relative-to-a-base original → new path relative to that same base,
---                                   preserving a leading `./` when it doesn't
---                                   climb up
--- Falls back to a cwd-relative path if the ref carries no base info.
---@param ref MarkdownFileRef
---@param new_abs_path string  New absolute path of the moved/renamed file.
---@return string  The link target to write in place of `ref.target`.
function M.retarget(ref, new_abs_path)
  if ref.is_absolute then return (path.normalize(new_abs_path)) end

  local base = ref.base_dir or vim.fn.getcwd()
  local rel = path.relative_to(base, new_abs_path)
  if ref.had_dot_prefix and not rel:match("^%.%.?/") and rel ~= "." then rel = "./" .. rel end
  return rel
end

return M
