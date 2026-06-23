---@module 'markdown_nvim.core.toc'
--- Generate or update a Markdown Table of Contents (TOC).

local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.core.toc]")

local M = {}

local DEFAULT_MIN_LEVEL = 2
local DEFAULT_MAX_LEVEL = 4

local function is_frontmatter_fence(line)
  return line and line:match("^%s*%-%-%-%s*$") ~= nil
end

local function frontmatter_end(bufnr)
  local first = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  if not is_frontmatter_fence(first) then return 0 end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 1, -1, false)
  for i = 1, #lines do
    if is_frontmatter_fence(lines[i]) then
      return i + 1
    end
  end
  return 0
end

local FENCE_LINE = "^%s*([`~]{3,})%S*%s*$"

local function slugify_gfm(title)
  local s = title:lower()
  s = s:gsub("%s+", "-")
  s = s:gsub("[^%w%-%_]", "")
  s = s:gsub("%-+", "-")
  s = s:gsub("^[-_]+", ""):gsub("[-_]+$", "")
  return s
end

local function is_empty_line(line)
  return not line or line:match("^%s*$") ~= nil
end

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
      toc_header_line = toc_header_line - remove_count
      separator_line = separator_line - remove_count
      total = vim.api.nvim_buf_line_count(bufnr)
    elseif empty_before == 0 and toc_header_line > 1 then
      vim.api.nvim_buf_set_lines(bufnr, toc_header_line - 1, toc_header_line - 1, false, { "" })
      toc_header_line = toc_header_line + 1
      separator_line = separator_line + 1
      total = vim.api.nvim_buf_line_count(bufnr)
    end
  end

  if separator_line > 1 then
    local before_sep = separator_line - 1
    local empty_before_sep = is_empty_line(vim.api.nvim_buf_get_lines(bufnr, before_sep - 1, before_sep, false)[1])
        and 1
      or 0

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

function M.update_markdown_toc(header_line, opts)
  header_line = header_line or "## Table of content"
  opts = opts or {}

  local min_level = opts.min_level or DEFAULT_MIN_LEVEL
  local max_level = opts.max_level or DEFAULT_MAX_LEVEL
  if min_level < 1 then min_level = 1 end
  if max_level > 6 then max_level = 6 end
  if min_level > max_level then min_level, max_level = max_level, min_level end

  local bufnr = vim.api.nvim_get_current_buf()
  local start_after_fm = frontmatter_end(bufnr)
  local total = vim.api.nvim_buf_line_count(bufnr)

  local existing_start, existing_end
  do
    local re = "^%s*" .. vim.pesc(header_line) .. "%s*$"
    for i = math.max(1, start_after_fm > 0 and (start_after_fm + 1) or 1), total do
      local l = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1]
      if l and l:match(re) then
        existing_start = i
        for j = i + 1, total do
          local lj = vim.api.nvim_buf_get_lines(bufnr, j - 1, j, false)[1]
          if lj then
            if lj:match("^%s*%-%-%-%s*$") then
              existing_end = j
              for k = j + 1, total do
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
        existing_end = existing_end or total
        break
      end
    end
  end

  local toc_lines = {}
  local in_fence = false
  local in_toc_block = false
  local seen_count = {}
  local toc_header_pattern = "^%s*" .. vim.pesc(header_line) .. "%s*$"
  local scan_start = math.max(1, start_after_fm > 0 and (start_after_fm + 1) or 1)

  for i = scan_start, total do
    local line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""

    if line:match(toc_header_pattern) then
      in_toc_block = true
    elseif in_toc_block and line:match("^%s*%-%-%-%s*$") then
      in_toc_block = false
    end

    if line:match(FENCE_LINE) then
      in_fence = not in_fence
    elseif not in_fence and not in_toc_block then
      local hashes, title = line:match("^(%s*#+)%s+(.*%S)")
      if hashes and title then
        local level = (#hashes:gsub("%s", "")) - 0
        if level >= min_level and level <= max_level then
          local base = slugify_gfm(title)
          if base == "" then base = "section-" .. tostring(i) end
          local count = seen_count[base] or 0
          local anchor = count == 0 and base or (base .. "-" .. tostring(count))
          seen_count[base] = count + 1
          local indent = string.rep("  ", math.max(0, level - 1))
          table.insert(toc_lines, indent .. string.format("- [%s](#%s)", title, anchor))
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
    total = vim.api.nvim_buf_line_count(bufnr)
  else
    local first_level1_idx = nil
    for i = scan_start, total do
      local l = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""
      if l:match("^%s*#%s+[^#]") then
        first_level1_idx = i
        break
      end
    end

    if first_level1_idx then
      local first_level2_idx = nil
      for j = first_level1_idx + 1, total do
        local lj = vim.api.nvim_buf_get_lines(bufnr, j - 1, j, false)[1] or ""
        if lj:match("^%s*##%s+") then
          first_level2_idx = j
          break
        end
      end
      insert_at = first_level2_idx or (total + 1)
    else
      insert_at = total + 1
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
