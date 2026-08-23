---@module 'markdown.core.heading_scan'
--- Extract ATX headings from lines, a buffer, or a file. The counterpart to
--- `core.link_scan`, shared by `:Markdown list headings`.
---
--- Setext headings (`Title` over `===`) are deliberately not recognized, so
--- what this reports matches what `core.toc` puts into a generated TOC.
local M = {}

local api = vim.api

-- `Mkdn.Heading` is declared in `markdown.@types`.

-- A fenced-code delimiter: 3+ backticks or tildes plus an optional info string.
-- `{3,}` is not a Lua-pattern quantifier, so three-or-more is spelled out.
local FENCE = "^%s*[`~][`~][`~]"

---@internal
---@param line string?
---@return boolean
local function is_frontmatter_fence(line) return line ~= nil and line:match("^%s*%-%-%-%s*$") ~= nil end

--- Index of the closing frontmatter fence (1-based), or 0 when `lines` does not
--- open with one. Headings before that index are frontmatter content, not
--- document structure.
---@internal
---@param lines string[]
---@return integer
local function frontmatter_end(lines)
  if not is_frontmatter_fence(lines[1]) then return 0 end
  for i = 2, #lines do
    if is_frontmatter_fence(lines[i]) then return i end
  end
  return 0
end

--- Extract headings from a list of lines, skipping frontmatter and fenced
--- code blocks.
---@param lines string[]
---@return Mkdn.Heading[]
function M.from_lines(lines)
  local out = {}
  local in_fence = false
  local start = frontmatter_end(lines) + 1

  for i = start, #lines do
    local line = lines[i] or ""
    if line:match(FENCE) then
      in_fence = not in_fence
    elseif not in_fence then
      local hashes, title = line:match("^(%s*#+)%s+(.*%S)")
      if hashes and title then
        local level = #(hashes:gsub("%s", ""))
        if level <= 6 then out[#out + 1] = { level = level, title = title, lnum = i } end
      end
    end
  end

  return out
end

--- Extract every heading in a buffer.
---@param bufnr? integer
---@return Mkdn.Heading[]
function M.from_buffer(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  return M.from_lines(api.nvim_buf_get_lines(bufnr, 0, -1, false))
end

--- Extract every heading in a file on disk, tagging each with its `file`.
--- Returns an empty list for an unreadable path rather than raising.
---@param path string
---@return Mkdn.Heading[]
function M.from_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then return {} end
  local found = M.from_lines(lines)
  for _, h in ipairs(found) do
    h.file = path
  end
  return found
end

return M
