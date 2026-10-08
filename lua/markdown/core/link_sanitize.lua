---@module 'markdown.core.link_sanitize'
--- Normalize markdown inline-link targets: convert backslashes to forward
--- slashes and ensure a relative file path starts with `./` (matching the
--- style file_refs.lua/refs.lua already produce for retargeted links). URLs,
--- scheme targets (`mailto:`, a Windows drive letter `C:\...`), anchor-only
--- links (`#foo`), absolute paths, `~`-relative paths and env-rooted paths
--- (`$VAR/...`, `${VAR}/...`, `%VAR%/...`) are left alone.
--- Shared by `:Markdown links sanitize` and the save-time autocmd.
local disk_lines = require("markdown.util.disk_lines")

local M = {}

-- Mirrors link_scan.lua's fence detection so sanitize never touches a target
-- written as an example inside a fenced code block.
local FENCE = "^%s*[`~][`~][`~]"

--- Name of the environment variable a target is rooted in: `$VAR/...`,
--- `${VAR}/...` or `%VAR%/...` (nil otherwise). The reference must be the whole
--- first path segment -- followed by a separator or the end of the target -- so
--- `$foo.md` (a file) and percent-encoded targets such as `%E2%80%93x.md` are NOT
--- taken for one. Such a target is rooted by the variable, so a `./` in front of it
--- would turn it into "a folder literally named `$VAR`" and break the expansion
--- (`./$REPOS_DIR/x.md` never resolves).
---@param target string
---@return string|nil
local function env_var_name(target)
  local name, rest = target:match("^%$([%a_][%w_]*)(.*)$")
  if not name then
    name, rest = target:match("^%${([%a_][%w_]*)}(.*)$")
  end
  if not name then
    name, rest = target:match("^%%([%a_][%w_]*)%%(.*)$")
  end
  if name and (rest == "" or rest:match("^[/\\]")) then return name end
  return nil
end

---@param target string
---@return boolean
local function starts_with_env_var(target) return env_var_name(target) ~= nil end
M.starts_with_env_var = starts_with_env_var

--- Whether `target` should be left completely untouched.
---@param target string
---@return boolean
local function is_untouchable(target)
  if target == "" then return true end
  if target:match("^#") then return true end -- in-document anchor
  if target:match("^~") then return true end -- home-relative
  if target:match("^%a[%w+.-]*:") then return true end -- URL scheme or drive letter (C:\...)
  if starts_with_env_var(target) then return true end -- `$VAR/...` is already rooted
  return false
end

--- A link broken by an earlier version of this module: `./$VAR/x` or
--- `../$VAR/x`. The prefix is stripped -- but only when `VAR` is actually
--- set in the environment, so a real folder that happens to be named `$x`
--- is never "repaired" away. Opt-out via `links.repair_env_prefix`.
---@param target string
---@return string|nil repaired  nil when `target` is not such a link
local function repair_env_prefix(target)
  -- Cheap shape test first: this runs for every link target on every save, the
  -- config lookup below only for the rare `./`/`../`-prefixed candidate.
  local rest = target:match("^%.%.?[/\\](.+)$")
  local name = rest and env_var_name(rest)
  if not name or (vim.env[name] or "") == "" then return nil end

  local ok, cfg = pcall(function() return require("markdown.config").get() end)
  if ok and cfg and cfg.links and cfg.links.repair_env_prefix == false then return nil end
  return rest
end

--- Normalize a single link target.
---@param target string
---@return string new_target
---@return boolean changed
function M.sanitize_target(target)
  local repaired = repair_env_prefix(target)
  if repaired then
    local fixed = (repaired:gsub("\\", "/"))
    return fixed, fixed ~= target
  end
  if is_untouchable(target) then return target, false end

  local normalized = (target:gsub("\\", "/"))
  if not (normalized:match("^%.%.?/") or normalized:match("^/")) then
    normalized = "./" .. normalized
  end

  return normalized, normalized ~= target
end

--- Sanitize every inline-link target (`[text](target)`) on one line.
---@param line string
---@return string new_line
---@return integer changed  number of targets changed on this line
function M.sanitize_line(line)
  local changed = 0
  local new_line = line:gsub("(%[.-%]%()(.-)(%))", function(prefix, target, suffix)
    local sane, did_change = M.sanitize_target(target)
    if did_change then changed = changed + 1 end
    return prefix .. sane .. suffix
  end)
  return new_line, changed
end

--- Sanitize a list of lines, skipping fenced code blocks.
---@param lines string[]
---@return string[] new_lines
---@return integer changed  total number of targets changed
function M.sanitize_lines(lines)
  local out = {}
  local total = 0
  local in_fence = false
  for i, line in ipairs(lines) do
    if line:match(FENCE) then in_fence = not in_fence end
    if in_fence then
      out[i] = line
    else
      local new_line, changed = M.sanitize_line(line)
      out[i] = new_line
      total = total + changed
    end
  end
  return out, total
end

--- Sanitize link targets in a buffer in place. Only the lines that actually
--- change are written back (keeps undo history / extmarks minimal).
---@param bufnr? integer
---@return integer changed  number of targets changed
function M.buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local new_lines, total = M.sanitize_lines(lines)
  if total > 0 then
    for i, line in ipairs(new_lines) do
      if line ~= lines[i] then vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { line }) end
    end
  end
  return total
end

--- Sanitize link targets in a file on disk.
---@param path string
---@return integer changed  0 when nothing needed normalizing OR the file
---  could not be read/written -- check `err` to tell those apart (ERR-11).
---@return string? err  set when the file was not readable/writable; nil on success.
function M.file(path)
  if vim.fn.filereadable(path) ~= 1 then return 0, "not readable" end

  -- ERR-01: readfile/writefile raise (E484/E482) on a permission error or a
  -- file that vanished between the filereadable check above and this call.
  -- util.disk_lines keeps the BOM, the CRLF endings and the missing final
  -- newline: a text-mode readfile/writefile round trip dropped all three.
  local ok_read, lines, meta = pcall(disk_lines.read, path)
  if not ok_read then return 0, "read failed" end

  local new_lines, total = M.sanitize_lines(lines)
  if total > 0 then
    if not disk_lines.write(path, new_lines, meta) then return 0, "write failed" end
  end
  return total
end

--- Sanitize `path`, preferring an already-loaded buffer over raw file I/O so
--- unsaved edits are never clobbered.
---@param path string
---@return integer changed
---@return string? err  see `M.file`; a buffer-backed sanitize never errors.
function M.path(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then return M.buffer(bufnr) end
  return M.file(path)
end

return M
