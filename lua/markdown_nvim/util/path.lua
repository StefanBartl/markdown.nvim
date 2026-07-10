---@module 'markdown_nvim.util.path'
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
local lib_cwd         = optional("lib.nvim.cross.fs._cwd")
local lib_sep_norm    = optional("lib.nvim.cross.fs.separators.normalize")

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
  return (p:gsub("\\", "/"))
end

--- True for absolute paths on any platform (POSIX `/…` or Windows `C:/…`).
--- Expects a slash-space path.
---@param p string
---@return boolean
local function is_absolute(p)
  return p:match("^/") ~= nil or has_drive(p)
end

--- Collapse `.`/`..` segments and repeated separators in a slash-form path.
--- Keeps a leading `/` (POSIX root) and a `C:` drive prefix intact, and never
--- pops past either of them.
---@param p string
---@return string
local function collapse(p)
  p = to_slashes(p)
  local leading = p:match("^/") and "/" or ""
  local segs = {}
  for seg in p:gmatch("[^/]+") do
    if seg == "." then
      -- drop
    elseif seg == ".." then
      local top = segs[#segs]
      if #segs > 0 and top ~= ".." and not top:match("^%a:$") then
        table.remove(segs)
      elseif leading == "" then
        -- relative path climbing above its base: keep the `..`
        table.insert(segs, seg)
      end
      -- absolute path: a `..` at root is a no-op (drop it)
    else
      table.insert(segs, seg)
    end
  end
  return leading .. table.concat(segs, "/")
end

--- Normalize a path *logically*: expand `~`/env vars, unify separators to
--- forward slashes, collapse `.`/`..`. Deterministic and platform-independent;
--- does not touch the filesystem and does not make relative paths absolute.
--- (For an OS-native, real-world path use `M.resolve`.)
---@param p string
---@return string
function M.normalize(p)
  return collapse(to_slashes(vim.fn.expand(p)))
end

--- Ordered list of base directories a relative target is resolved against.
---@return string[]
local function candidate_bases()
  local bases = {}
  local seen = {}
  local function add(dir)
    if dir and dir ~= "" then
      local norm = collapse(to_slashes(dir))
      if not seen[norm] then
        seen[norm] = true
        bases[#bases + 1] = norm
      end
    end
  end
  add(vim.fn.expand("%:p:h")) -- buffer's own directory (markdown convention)
  add(cwd())                  -- project root / nvim cwd
  return bases
end

--- Resolve a raw link target to an absolute filesystem path (OS-native seps).
--- URLs (scheme://…) are returned unchanged. Absolute paths are only
--- normalized. Relative paths are joined against each candidate base in order;
--- the first that exists on disk wins. If none exist, the buffer-relative
--- candidate is returned so the caller can notify with a clean path.
---@param target string
---@return string|nil path  Resolved path, original URL, or nil for empty input.
function M.resolve(target)
  if not target or target == "" then return nil end
  if target:match("^%w[%w+.%-]*://") then return target end

  local expanded = to_slashes(vim.fn.expand(target))

  if is_absolute(expanded) then
    return to_os(collapse(expanded))
  end

  local first
  for _, base in ipairs(candidate_bases()) do
    local cand = collapse(base .. "/" .. expanded)
    if not first then first = cand end
    if uv.fs_stat(cand) then
      return to_os(cand)
    end
  end

  return to_os(first or collapse(expanded))
end

return M
