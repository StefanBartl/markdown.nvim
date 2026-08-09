---@module 'markdown.util.path'
---@brief Robust, cross-platform resolution of link targets to filesystem paths.
---@description
--- The single source of truth for turning a raw link target (as written in a
--- markdown file / HTML attribute) into an absolute path. Fixes two classes of
--- bug that the old per-handler resolvers shared on Windows:
---   * `vim.fn.fnamemodify(:p)` does not reliably collapse `.`/`..` segments or
---     mixed `/`+`\` separators, so `bufdir\.\foo` survived verbatim.
---   * relative links were only ever resolved against the *buffer* directory,
---     which breaks links authored relative to the project root (cwd).
--- Resolution tries each candidate base in order (buffer dir, then cwd) and
--- returns the first that exists; if none exist it returns the buffer-relative
--- candidate so the caller can report a clean, normalized path.
---
--- Cross-platform primitives (Windows-drive detection, cwd, OS-native separator
--- output) are delegated to lib.nvim when present, with inline fallbacks so the
--- plugin still works standalone. `.`/`..` collapse is done here — lib.nvim's
--- separator helpers intentionally do not touch path segments.

local M = {}

local uv = vim.uv or vim.loop

-- Soft dependency on lib.nvim's cross-platform helpers (see [[lib-nvim-dependency]]).
local function optional(mod)
  local ok, m = pcall(require, mod)
  if ok then return m end
  return nil
end

local lib_has_win_sep = optional("lib.nvim.cross.fs.separators.has_win_sep")
local lib_cwd = optional("lib.nvim.cross.fs._cwd")
local lib_sep_norm = optional("lib.nvim.cross.fs.separators.normalize")
local lib_unify = optional("lib.nvim.cross.fs.separators.unify_slashes")
local lib_collapse = optional("lib.nvim.cross.fs.separators.collapse_dots")
local lib_relpath = optional("lib.nvim.fs.relpath")

--- True when `p` starts with a Windows drive prefix (`C:/` or `C:\`).
---@param p string
---@return boolean
local function has_drive(p)
  if lib_has_win_sep then return lib_has_win_sep(p) and true or false end
  return p:match("^%a:[/\\]") ~= nil
end

--- Current working directory (libuv-based, version-compatible).
---@return string
local function cwd()
  if lib_cwd then return lib_cwd() end
  return (uv and uv.cwd()) or vim.fn.getcwd()
end

--- Convert a finished slash-space path to the OS-native separator style for
--- the return value (backslashes on Windows). Internal computation stays in
--- slash-space; this only runs at the boundary.
---@param p string
---@return string
local function to_os(p)
  if lib_sep_norm then
    local ok, r = pcall(lib_sep_norm, p)
    if ok and type(r) == "string" then return r end
  end
  -- Fallback: package.config's first char is the OS path separator.
  if package.config:sub(1, 1) == "\\" then return (p:gsub("/", "\\")) end
  return p
end

--- Canonicalize separators to forward slashes for internal splitting/joining.
---@param p string
---@return string
local function to_slashes(p)
  if lib_unify then return lib_unify(p) end
  return (p:gsub("\\", "/"))
end

--- True for absolute paths on any platform (POSIX `/…` or Windows `C:/…`).
--- Expects a slash-space path.
---@param p string
---@return boolean
local function is_absolute(p) return p:match("^/") ~= nil or has_drive(p) end

--- Collapse `.`/`..` segments and repeated separators; returns slash form.
--- Keeps a leading `/` (POSIX root) and a `C:` drive prefix intact, and never
--- pops past either of them. Delegates to lib.nvim; the inline fallback mirrors
--- `lib.nvim.cross.fs.separators.collapse_dots` exactly.
---@param p string
---@return string
-- luacheck: push ignore 542 -- deliberately empty branches below (self-documenting no-ops)
local function collapse(p)
  if lib_collapse then return lib_collapse(p) end
  p = to_slashes(p)
  local leading = p:match("^/") and "/" or ""
  local segs = {}
  for seg in p:gmatch("[^/]+") do
    if seg == "." then
      -- drop
    elseif seg == ".." then
      local top = segs[#segs]
      if top and top:match("^%a:$") then
        -- at a Windows drive root ('C:'): '..' is a no-op, drop it
      elseif #segs > 0 and top ~= ".." then
        table.remove(segs)
      elseif leading == "" then
        -- relative path climbing above its base: keep the `..`
        table.insert(segs, seg)
      end
      -- POSIX absolute at root: a `..` is a no-op (drop it)
    else
      table.insert(segs, seg)
    end
  end
  return leading .. table.concat(segs, "/")
end
-- luacheck: pop

--- Normalize a path *logically*: expand `~`/env vars, unify separators to
--- forward slashes, collapse `.`/`..`. Deterministic and platform-independent;
--- does not touch the filesystem and does not make relative paths absolute.
--- (For an OS-native, real-world path use `M.resolve`.)
---@param p string
---@return string
function M.normalize(p)
  -- Unify separators *before* vim.fn.expand(): expand() treats a bare
  -- backslash as an escape character (drops it and keeps the following
  -- character verbatim), so a Windows-style "a\b\c" fed to expand() first
  -- comes back as "abc" -- the backslashes vanish instead of becoming "/".
  return collapse(vim.fn.expand(to_slashes(p)))
end

--- Ordered list of base directories a relative target is resolved against.
---@param first_base? string  Override for the primary base (defaults to the
---                            current buffer's directory — the markdown
---                            convention). Pass the containing file's own
---                            directory when resolving links found while
---                            scanning a file on disk that isn't the current
---                            buffer.
---@return string[]
local function candidate_bases(first_base)
  local raw = { first_base or vim.fn.expand("%:p:h"), cwd() } -- file dir, project root/cwd
  local bases = {}
  for _, dir in ipairs(raw) do
    if dir and dir ~= "" then bases[#bases + 1] = collapse(to_slashes(dir)) end
  end
  return require("lib.lua.tables").dedup_list(bases)
end

--- On a non-Windows host, a literal `C:/...` prefix (e.g. a link authored on
--- Windows, opened on POSIX) has no filesystem meaning. When the path as
--- written doesn't exist, retry with the drive prefix stripped and treated
--- as a POSIX absolute path; use that instead when it exists on disk.
---@param collapsed string  Already-collapsed, slash-form absolute path.
---@return string
local function drive_fallback_if_exists(collapsed)
  if package.config:sub(1, 1) == "\\" then return collapsed end
  if not has_drive(collapsed) then return collapsed end
  local stripped = "/" .. (collapsed:gsub("^%a:/?", ""))
  if uv.fs_stat(stripped) then return stripped end
  return collapsed
end

--- Resolve a raw link target to an absolute filesystem path (OS-native seps),
--- against an explicit base directory list (see `candidate_bases`).
---@param target string
---@param first_base? string
---@return string|nil path
local function resolve_impl(target, first_base)
  if not target or target == "" then return nil end
  if target:match("^%w[%w+.%-]*://") then return target end

  local expanded = to_slashes(vim.fn.expand(to_slashes(target)))

  if is_absolute(expanded) then return to_os(drive_fallback_if_exists(collapse(expanded))) end

  local first
  for _, base in ipairs(candidate_bases(first_base)) do
    local cand = collapse(base .. "/" .. expanded)
    if not first then first = cand end
    if uv.fs_stat(cand) then return to_os(cand) end
  end

  return to_os(first or collapse(expanded))
end

--- Resolve a raw link target to an absolute filesystem path (OS-native seps).
--- URLs (scheme://…) are returned unchanged. Absolute paths are only
--- normalized. Relative paths are joined against each candidate base in order;
--- the first that exists on disk wins. If none exist, the buffer-relative
--- candidate is returned so the caller can notify with a clean path.
---@param target string
---@return string|nil path  Resolved path, original URL, or nil for empty input.
function M.resolve(target) return resolve_impl(target, nil) end

--- Like `M.resolve`, but resolves relative targets against `base_dir` first
--- (instead of the current buffer's directory) before falling back to cwd.
--- For resolving links found while scanning a file on disk that is not the
--- current buffer (e.g. a project-wide reference search).
---@param target string
---@param base_dir string
---@return string|nil path
function M.resolve_from(target, base_dir) return resolve_impl(target, base_dir) end

--- Like `M.resolve_from`, but also reports *how* the target resolved, so a
--- caller can later re-express a moved/renamed target in the same style the
--- original link used (relative-to-a-base vs absolute vs URL). This is what
--- lets a rename rewrite `./old.md` -> `./new.md` and `docs/old.md` ->
--- `docs/new.md` instead of collapsing every link to one canonical form.
---@param target string
---@param base_dir string
---@return string|nil path        Resolved path (OS-native), URL, or nil.
---@return string|nil base_used   The base dir a *relative* target resolved
---                               against (slash-normalized); nil for
---                               absolute paths and URLs.
---@return boolean is_absolute    True when the raw target was already absolute.
function M.resolve_traced(target, base_dir)
  if not target or target == "" then return nil, nil, false end
  if target:match("^%w[%w+.%-]*://") then return target, nil, false end

  local expanded = to_slashes(vim.fn.expand(to_slashes(target)))
  if is_absolute(expanded) then
    return to_os(drive_fallback_if_exists(collapse(expanded))), nil, true
  end

  local first, first_base
  for _, base in ipairs(candidate_bases(base_dir)) do
    local cand = collapse(base .. "/" .. expanded)
    if not first then
      first, first_base = cand, base
    end
    if uv.fs_stat(cand) then return to_os(cand), base, false end
  end

  return to_os(first or collapse(expanded)), first_base, false
end

--- POSIX-style relative path from `base_dir` to `target_path`, using `..`
--- segments where the target isn't a descendant of the base. Both sides are
--- logically normalized first (no filesystem access). Returns "." when the
--- two paths are the same directory.
---
--- Delegates the actual computation to lib.nvim.fs.relpath when present
--- (identical common-ancestor-climb algorithm, upstreamed from this
--- function — see lib.nvim commit 43b49db); as a bonus that version also
--- correctly declines to climb across differing Windows drive letters,
--- which this file's inline fallback below does not guard against.
---@param base_dir string
---@param target_path string
---@return string
function M.relative_to(base_dir, target_path)
  local b = collapse(to_slashes(vim.fn.expand(base_dir)))
  local t = collapse(to_slashes(vim.fn.expand(target_path)))

  if lib_relpath then
    local ok, rel = pcall(lib_relpath, t, b)
    if ok and type(rel) == "string" then return rel end
  end

  local bp, tp = {}, {}
  for seg in b:gmatch("[^/]+") do
    bp[#bp + 1] = seg
  end
  for seg in t:gmatch("[^/]+") do
    tp[#tp + 1] = seg
  end

  local i = 1
  while bp[i] and tp[i] and bp[i] == tp[i] do
    i = i + 1
  end

  local parts = {}
  for _ = i, #bp do
    parts[#parts + 1] = ".."
  end
  for j = i, #tp do
    parts[#parts + 1] = tp[j]
  end

  return #parts > 0 and table.concat(parts, "/") or "."
end

return M
