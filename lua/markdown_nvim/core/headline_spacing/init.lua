---@module 'markdown_nvim.core.headline_spacing'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.core.headline_spacing]")

local api = vim.api
local M = {}

local function is_h2_or_more(line)
  return line:match("^##+%s") ~= nil
end

local function find_next_h2_heading(lines, start_idx)
  local n = #lines
  local in_fence = false
  for i = start_idx + 1, n do
    local line = lines[i] or ""
    if line:match("^%s*```") or line:match("^%s*~~~") then
      in_fence = not in_fence
    end
    if not in_fence and is_h2_or_more(line) then
      return i
    end
  end
  return nil
end

local function find_section_end(lines, heading_idx, next_heading_idx)
  local search_end = next_heading_idx and (next_heading_idx - 1) or #lines
  for i = search_end, heading_idx + 1, -1 do
    local line = lines[i] or ""
    if line ~= "---" and line:match("%S") then
      return i
    end
  end
  return heading_idx
end

local function has_separator_after(lines, section_end_idx, next_heading_idx)
  local gap = next_heading_idx - section_end_idx
  if gap ~= 4 then return false end
  local line1 = lines[section_end_idx + 1] or ""
  local line2 = lines[section_end_idx + 2] or ""
  local line3 = lines[section_end_idx + 3] or ""
  return line1 == "" and line2 == "---" and line3 == ""
end

function M.find_sections_needing_separator(lines)
  local n = #lines
  local result = {}
  local in_fence = false

  for i = 1, n do
    local line = lines[i] or ""
    if line:match("^%s*```") or line:match("^%s*~~~") then
      in_fence = not in_fence
    end

    if not in_fence and is_h2_or_more(line) then
      local next_heading = find_next_h2_heading(lines, i)
      if next_heading then
        local section_end = find_section_end(lines, i, next_heading)
        if not has_separator_after(lines, section_end, next_heading) then
          table.insert(result, {
            heading_idx = i,
            section_end_idx = section_end,
            next_heading_idx = next_heading,
          })
        end
      end
    end
  end

  return result
end

function M.apply_headl_separators(bufnr, opts)
  opts = opts or {}
  local notify_enabled = opts.notify ~= false
  local dry_run = opts.dry_run == true

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sections = M.find_sections_needing_separator(lines)

  if #sections == 0 then
    if notify_enabled then
      notify.info("all sections properly formatted")
    end
    return 0
  end

  if dry_run then
    if notify_enabled then
      notify.info(string.format("would fix %d sections", #sections))
    end
    return #sections
  end

  local separator = { "", "---", "" }
  local offset = 0

  for _, section in ipairs(sections) do
    local adjusted_end = section.section_end_idx + offset
    local adjusted_next = section.next_heading_idx + offset

    local lines_between = adjusted_next - adjusted_end - 1
    if lines_between > 0 then
      api.nvim_buf_set_lines(bufnr, adjusted_end, adjusted_end + lines_between, false, {})
      offset = offset - lines_between
      adjusted_next = section.next_heading_idx + offset
    end

    api.nvim_buf_set_lines(bufnr, adjusted_end, adjusted_end, false, separator)
    offset = offset + 3
  end

  if notify_enabled then
    notify.info(string.format("fixed %d sections", #sections))
  end

  return #sections
end

return M
