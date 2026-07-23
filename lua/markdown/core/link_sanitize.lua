---@module 'markdown.core.link_sanitize'
--- Normalize markdown inline-link targets: convert backslashes to forward
--- slashes and ensure a relative file path starts with `./` (matching the
--- style file_refs.lua/refs.lua already produce for retargeted links). URLs,
--- scheme targets (`mailto:`, a Windows drive letter `C:\...`), anchor-only
--- links (`#foo`), absolute paths, and `~`-relative paths are left alone.
--- Shared by `:Markdown links sanitize` and the save-time autocmd.
local M = {}

-- Mirrors link_scan.lua's fence detection so sanitize never touches a target
-- written as an example inside a fenced code block.
local FENCE = "^%s*[`~][`~][`~]"

--- Whether `target` should be left completely untouched.
---@param target string
---@return boolean
local function is_untouchable(target)
  if target == "" then return true end
  if target:match("^#") then return true end -- in-document anchor
  if target:match("^~") then return true end -- home-relative
  if target:match("^%a[%w+.-]*:") then return true end -- URL scheme or drive letter (C:\...)
  return false
end

--- Normalize a single link target.
---@param target string
---@return string new_target
---@return boolean changed
function M.sanitize_target(target)
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

--- Sanitize link targets in a file on disk. Returns 0 (no-op) when the file
--- cannot be read.
---@param path string
---@return integer changed
function M.file(path)
  if vim.fn.filereadable(path) ~= 1 then return 0 end
  local lines = vim.fn.readfile(path)
  local new_lines, total = M.sanitize_lines(lines)
  if total > 0 then vim.fn.writefile(new_lines, path) end
  return total
end

--- Sanitize `path`, preferring an already-loaded buffer over raw file I/O so
--- unsaved edits are never clobbered.
---@param path string
---@return integer changed
function M.path(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then return M.buffer(bufnr) end
  return M.file(path)
end

return M
