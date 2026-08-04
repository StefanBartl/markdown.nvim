---@module 'markdown.core.slug'
---@brief Single source of truth for heading slugs / anchor resolution.
---@description
--- Both the TOC generator (`core.toc`) and the reference-sync engine (`core.refs`)
--- must agree on exactly which anchor a heading produces — otherwise a "fixed"
--- link would point at an anchor the TOC never emits. This module owns the slug
--- algorithm and the document-order anchor map (GitHub-style de-duplication with
--- `-1`, `-2`, … suffixes), computed over every heading in the buffer.
---
--- `M.gfm` is the default (and historical) algorithm; `M.slugify` generalizes it
--- with opt-in `style`/`separator` for renderers that don't follow GFM (see
--- `config.toc.anchor_style` / `config.toc.anchor_separator`).

local M = {}

-- A fenced-code delimiter: 3+ backticks or tildes plus an optional info string.
local FENCE_LINE = "^%s*[`~][`~][`~]+%S*%s*$"

--- Convert a heading title to a slug, per `opts.style`/`opts.separator`.
---   style = "gfm" (default)  — lowercase, GitHub's dedup-suffix source slug.
---   style = "keep-case"      — same shape, but the original case is preserved.
---   separator (default "-") — replaces the dash joiner in the final slug.
---@param title string
---@param opts? { style?: "gfm"|"keep-case", separator?: string }
---@return string
function M.slugify(title, opts)
  opts = opts or {}
  local sep = opts.separator or "-"

  local s = opts.style == "keep-case" and title or title:lower()
  s = s:gsub("%s+", "-")
  s = s:gsub("[^%w%-%_]", "")
  s = s:gsub("%-+", "-")
  s = s:gsub("^[-_]+", ""):gsub("[-_]+$", "")
  if sep ~= "-" then
    s = s:gsub("%-", sep)
  end
  return s
end

--- Convert a heading title to its GFM base slug (no de-dup suffix).
--- Kept byte-for-byte identical to the historical algorithm so existing
--- anchors/links stay valid; equivalent to `M.slugify(title, { style = "gfm" })`.
---@param title string
---@return string
function M.gfm(title)
  return M.slugify(title, { style = "gfm", separator = "-" })
end

--- `config.toc.anchor_style` / `anchor_separator`, read lazily so a module
--- required before `markdown.config` exists still gets sane (gfm) defaults.
---@return { style?: string, separator?: string }
---@internal
local function configured_style()
  local ok, config = pcall(require, "markdown.config")
  if not ok then return {} end
  local toc = config.get().toc or {}
  return { style = toc.anchor_style, separator = toc.anchor_separator }
end

---@internal
---@param line string?
---@return boolean?
local function is_frontmatter_fence(line)
  return line and line:match("^%s*%-%-%-%s*$") ~= nil
end

--- Row (1-indexed) at which body content begins, skipping a leading `--- … ---`
--- YAML frontmatter block. Returns 1 when there is no frontmatter.
---@param lines string[]
---@return integer
---@internal
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
---@param opts? { style?: "gfm"|"keep-case", separator?: string } # Defaults to `config.toc.anchor_style`/`anchor_separator` when omitted.
---@return { list: { row: integer, level: integer, title: string, anchor: string }[], set: table<string, true>, by_row: table<integer, string> }
function M.heading_anchors(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = opts or configured_style()
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
        local base = M.slugify(title, opts)
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
