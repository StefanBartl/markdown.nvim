---@module 'markdown.core.slug'
---@brief Single source of truth for GFM heading slugs / anchor resolution.
---@description
--- Both the TOC generator (`core.toc`) and the reference-sync engine (`core.refs`)
--- must agree on exactly which anchor a heading produces — otherwise a "fixed"
--- link would point at an anchor the TOC never emits. This module owns the slug
--- algorithm and the document-order anchor map (GitHub-style de-duplication with
--- `-1`, `-2`, … suffixes), computed over every heading in the buffer.

local M = {}

-- A fenced-code delimiter: 3+ backticks or tildes plus an optional info string.
local FENCE_LINE = "^%s*[`~][`~][`~]+%S*%s*$"

--- Convert a heading title to its GFM base slug (no de-dup suffix).
--- Kept byte-for-byte identical to the historical `toc.slugify_gfm` so existing
--- anchors/links stay valid.
---@param title string
---@return string
function M.gfm(title)
  local s = title:lower()
  s = s:gsub("%s+", "-")
  s = s:gsub("[^%w%-%_]", "")
  s = s:gsub("%-+", "-")
  s = s:gsub("^[-_]+", ""):gsub("[-_]+$", "")
  return s
end

local function is_frontmatter_fence(line)
  return line and line:match("^%s*%-%-%-%s*$") ~= nil
end

--- Row (1-indexed) at which body content begins, skipping a leading `--- … ---`
--- YAML frontmatter block. Returns 1 when there is no frontmatter.
---@param lines string[]
---@return integer
local function body_start(lines)
  if not is_frontmatter_fence(lines[1]) then return 1 end
  for i = 2, #lines do
    if is_frontmatter_fence(lines[i]) then return i + 1 end
  end
  return 1
end

--- Resolve every heading in `bufnr` to its final anchor, in document order.
--- Skips fenced code blocks (a `#` line inside a code fence is a comment, not a
--- heading) and YAML frontmatter. De-duplication matches GitHub: repeated base
--- slugs get `-1`, `-2`, … in the order they appear.
---@param bufnr? integer
---@return { list: { row: integer, level: integer, title: string, anchor: string }[], set: table<string, true>, by_row: table<integer, string> }
function M.heading_anchors(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local list, set, by_row = {}, {}, {}
  local seen = {}
  local in_fence = false
  local start = body_start(lines)

  for i = start, #lines do
    local line = lines[i]
    if line:match(FENCE_LINE) then
      in_fence = not in_fence
    elseif not in_fence then
      local hashes, title = line:match("^(%s*#+)%s+(.*%S)")
      if hashes and title then
        local level = #(hashes:gsub("%s", ""))
        local base = M.gfm(title)
        if base == "" then base = "section-" .. tostring(i) end
        local count = seen[base] or 0
        local anchor = count == 0 and base or (base .. "-" .. tostring(count))
        seen[base] = count + 1

        list[#list + 1] = { row = i, level = level, title = title, anchor = anchor }
        set[anchor] = true
        by_row[i] = anchor
      end
    end
  end

  return { list = list, set = set, by_row = by_row }
end

return M
