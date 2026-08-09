---@module 'markdown.core.toc'
--- Generate or update a Markdown Table of Contents (TOC).

local notify = require("markdown.util.notify").create("[markdown.core.toc]")

local M = {}

local DEFAULT_MIN_LEVEL = 2
local DEFAULT_MAX_LEVEL = 4

---@internal
---@param line string?
---@return boolean?
local function is_frontmatter_fence(line) return line and line:match("^%s*%-%-%-%s*$") ~= nil end

---@internal
---@param bufnr integer
---@return integer
local function frontmatter_end(bufnr)
  local first = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  if not is_frontmatter_fence(first) then return 0 end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 1, -1, false)
  for i = 1, #lines do
    if is_frontmatter_fence(lines[i]) then return i + 1 end
  end
  return 0
end

-- A fenced-code delimiter line: 3+ backticks or 3+ tildes, then an optional info
-- string. `{3,}` is NOT a Lua-pattern quantifier (it matches the literal chars
-- `{3,}`), so three-or-more is spelled out explicitly.
local FENCE_LINE = "^%s*[`~][`~][`~]+%S*%s*$"

-- Shared with core.refs so generated anchors and repaired links never drift.
local slug_mod = require("markdown.core.slug")

---@internal
---@param line string?
---@return boolean
local function is_empty_line(line) return not line or line:match("^%s*$") ~= nil end

---@internal
---@param bufnr integer
---@param toc_header_line integer
---@param separator_line integer
local function ensure_proper_spacing(bufnr, toc_header_line, separator_line)
  local total = vim.api.nvim_buf_line_count(bufnr)

  if toc_header_line > 1 then
    local empty_before = 0
    for i = toc_header_line - 1, 1, -1 do
      local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
      if is_empty_line(line) then
        empty_before = empty_before + 1
      else
        break
      end
    end

    if empty_before > 1 then
      local remove_count = empty_before - 1
      local delete_start = toc_header_line - empty_before
      local delete_end = toc_header_line - 2
      vim.api.nvim_buf_set_lines(bufnr, delete_start, delete_end + 1, false, {})
      separator_line = separator_line - remove_count
      total = vim.api.nvim_buf_line_count(bufnr)
    elseif empty_before == 0 and toc_header_line > 1 then
      vim.api.nvim_buf_set_lines(bufnr, toc_header_line - 1, toc_header_line - 1, false, { "" })
      separator_line = separator_line + 1
      total = vim.api.nvim_buf_line_count(bufnr)
    end
  end

  if separator_line > 1 then
    local before_sep = separator_line - 1
    local empty_before_sep = is_empty_line(
      vim.api.nvim_buf_get_lines(bufnr, before_sep - 1, before_sep, false)[1]
    ) and 1 or 0

    local extra = 0
    for i = before_sep - 1, 1, -1 do
      local l = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
      if is_empty_line(l) then
        extra = extra + 1
      else
        break
      end
    end

    if empty_before_sep == 0 then
      vim.api.nvim_buf_set_lines(bufnr, before_sep, before_sep, false, { "" })
      separator_line = separator_line + 1
      total = vim.api.nvim_buf_line_count(bufnr)
    elseif extra > 0 then
      local delete_start = before_sep - extra
      local delete_end = before_sep - 1
      vim.api.nvim_buf_set_lines(bufnr, delete_start, delete_end + 1, false, {})
      separator_line = separator_line - extra
      total = vim.api.nvim_buf_line_count(bufnr)
    end
  end

  if separator_line < total then
    local empty_after = 0
    for i = separator_line + 1, total do
      local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
      if is_empty_line(line) then
        empty_after = empty_after + 1
      else
        break
      end
    end

    if empty_after > 1 then
      vim.api.nvim_buf_set_lines(bufnr, separator_line + 1, separator_line + empty_after, false, {})
    elseif empty_after == 0 and separator_line < total then
      vim.api.nvim_buf_set_lines(bufnr, separator_line, separator_line, false, { "" })
    end
  end
end

---Inserts or refreshes the TOC block for `header_line`.
---@param header_line string?
---@param opts? { min_level?: integer, max_level?: integer, marker?: string, anchor_style?: string, anchor_separator?: string, scan_first?: integer, scan_last?: integer, no_frontmatter?: boolean, exclude?: { first: integer, last: integer }[] }
---@return nil
function M.update_markdown_toc(header_line, opts)
  header_line = header_line or "## Table of content"
  opts = opts or {}

  local min_level = opts.min_level or DEFAULT_MIN_LEVEL
  local max_level = opts.max_level or DEFAULT_MAX_LEVEL
  local marker = opts.marker or "-"
  local slug_opts = { style = opts.anchor_style, separator = opts.anchor_separator }
  if min_level < 1 then min_level = 1 end
  if max_level > 6 then max_level = 6 end
  if min_level > max_level then
    min_level, max_level = max_level, min_level
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local total = vim.api.nvim_buf_line_count(bufnr)

  -- Optional scan bounds (1-indexed inclusive). When the TOC is generated for a
  -- fenced markdown sub-document, callers pass the block interior as
  -- scan_first/scan_last (+ no_frontmatter) so scanning AND insertion stay
  -- inside the block. Unset → whole buffer (frontmatter-aware), i.e. unchanged.
  local no_fm = opts.no_frontmatter == true
  local start_after_fm = no_fm and 0 or frontmatter_end(bufnr)
  local scan_lower = opts.scan_first
    or math.max(1, start_after_fm > 0 and (start_after_fm + 1) or 1)
  local scan_upper = opts.scan_last or total

  -- Optional excluded ranges (1-indexed inclusive). Buffer-scope callers pass the
  -- interiors of every fenced block so their headings never leak into the outer
  -- TOC. This uses color_my_ascii's robust detection instead of the fragile
  -- in-fence line toggle below (retained only for the feature-disabled path).
  local exclude = opts.exclude
  local function excluded(i)
    if not exclude then return false end
    for _, r in ipairs(exclude) do
      if i >= r.first and i <= r.last then return true end
    end
    return false
  end

  local existing_start, existing_end
  do
    local re = "^%s*" .. vim.pesc(header_line) .. "%s*$"
    for i = scan_lower, scan_upper do
      local l = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
      if l and l:match(re) then
        existing_start = i
        for j = i + 1, scan_upper do
          local lj = vim.api.nvim_buf_get_lines(bufnr, j - 1, j, false)[1]
          if lj then
            if lj:match("^%s*%-%-%-%s*$") then
              existing_end = j
              for k = j + 1, scan_upper do
                local lk = vim.api.nvim_buf_get_lines(bufnr, k - 1, k, false)[1]
                if lk and is_empty_line(lk) then
                  existing_end = k
                else
                  break
                end
              end
              break
            elseif lj:match("^%s*#%s+") then
              existing_end = j - 1
              break
            end
          end
        end
        existing_end = existing_end or scan_upper
        break
      end
    end
  end

  local toc_lines = {}
  local in_fence = false
  local in_toc_block = false
  local seen_count = {}
  local toc_header_pattern = "^%s*" .. vim.pesc(header_line) .. "%s*$"
  local scan_start = scan_lower

  for i = scan_start, scan_upper do
    local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""

    if line:match(toc_header_pattern) then
      in_toc_block = true
    elseif in_toc_block and line:match("^%s*%-%-%-%s*$") then
      in_toc_block = false
    end

    if line:match(FENCE_LINE) then
      in_fence = not in_fence
    elseif not in_fence and not in_toc_block and not excluded(i) then
      local hashes, title = line:match("^(%s*#+)%s+(.*%S)")
      if hashes and title then
        local level = (#hashes:gsub("%s", "")) - 0
        if level >= min_level and level <= max_level then
          local base = slug_mod.slugify(title, slug_opts)
          if base == "" then base = "section-" .. tostring(i) end
          local count = seen_count[base] or 0
          local anchor = count == 0 and base or (base .. "-" .. tostring(count))
          seen_count[base] = count + 1
          local indent = string.rep("  ", math.max(0, level - 1))
          table.insert(toc_lines, indent .. string.format("%s [%s](#%s)", marker, title, anchor))
        end
      end
    end
  end

  if #toc_lines == 0 then
    notify.info("No headings found for TOC in the requested level range")
    return
  end

  local insert_at
  if existing_start then
    insert_at = existing_start
    vim.api.nvim_buf_set_lines(bufnr, existing_start - 1, existing_end, false, {})
  else
    local first_level1_idx = nil
    for i = scan_start, scan_upper do
      local l = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""
      if l:match("^%s*#%s+[^#]") and not excluded(i) then
        first_level1_idx = i
        break
      end
    end

    if first_level1_idx then
      local first_level2_idx = nil
      for j = first_level1_idx + 1, scan_upper do
        local lj = vim.api.nvim_buf_get_lines(bufnr, j - 1, j, false)[1] or ""
        if lj:match("^%s*##%s+") then
          first_level2_idx = j
          break
        end
      end
      insert_at = first_level2_idx or (scan_upper + 1)
    else
      insert_at = scan_upper + 1
    end
  end

  local block = { header_line, "" }
  for _, l in ipairs(toc_lines) do
    block[#block + 1] = l
  end
  block[#block + 1] = ""
  block[#block + 1] = "---"
  block[#block + 1] = ""

  vim.api.nvim_buf_set_lines(bufnr, insert_at - 1, insert_at - 1, false, block)

  local toc_header_line = insert_at
  local separator_line = insert_at + #block - 2
  ensure_proper_spacing(bufnr, toc_header_line, separator_line)
end

return M
