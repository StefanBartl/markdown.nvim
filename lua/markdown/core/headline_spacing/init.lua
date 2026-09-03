---@module 'markdown.core.headline_spacing'
--- Ensures every H2+ section is closed with a blank/`---`/blank separator —
--- but only when the section actually has content. A section with nothing
--- between its heading and the next one gets a single blank line instead;
--- no `---` is inserted for an empty section.
local notify = require("markdown.util.notify").create("[markdown.core.headline_spacing]")

local api = vim.api
local M = {}

---@internal
---@param line string
---@return boolean
local function is_h2_or_more(line) return line:match("^##+%s") ~= nil end

---@internal
---@param lines string[]
---@param start_idx integer
---@return integer?
local function find_next_h2_heading(lines, start_idx)
  local n = #lines
  local in_fence = false
  for i = start_idx + 1, n do
    local line = lines[i] or ""
    if line:match("^%s*```") or line:match("^%s*~~~") then in_fence = not in_fence end
    if not in_fence and is_h2_or_more(line) then return i end
  end
  return nil
end

---Finds the last line of actual content in a section (skipping blank lines
---and any pre-existing `---` separator). Returns `heading_idx` unchanged
---when the section has no content at all.
---@internal
---@param lines string[]
---@param heading_idx integer
---@param next_heading_idx integer?
---@return integer
local function find_section_end(lines, heading_idx, next_heading_idx)
  local search_end = next_heading_idx and (next_heading_idx - 1) or #lines
  for i = search_end, heading_idx + 1, -1 do
    local line = lines[i] or ""
    if line ~= "---" and line:match("%S") then return i end
  end
  return heading_idx
end

---@internal
---@param lines string[]
---@param section_end_idx integer
---@param next_heading_idx integer
---@return boolean
local function has_separator_after(lines, section_end_idx, next_heading_idx)
  local gap = next_heading_idx - section_end_idx
  if gap ~= 4 then return false end
  local line1 = lines[section_end_idx + 1] or ""
  local line2 = lines[section_end_idx + 2] or ""
  local line3 = lines[section_end_idx + 3] or ""
  return line1 == "" and line2 == "---" and line3 == ""
end

---@internal
--- A section with no content only needs exactly one blank line between the
--- heading and the next one — no `---`.
---@param lines string[]
---@param heading_idx integer
---@param next_heading_idx integer
---@return boolean
local function has_single_blank_gap(lines, heading_idx, next_heading_idx)
  return next_heading_idx - heading_idx == 2 and (lines[heading_idx + 1] or "") == ""
end

---Finds every H2+ section whose closing whitespace doesn't match what it
---should be: `[blank]---[blank]` when the section has content, or a single
---blank line when it doesn't.
---@param lines string[]
---@return { heading_idx: integer, section_end_idx: integer, next_heading_idx: integer, has_content: boolean }[]
function M.find_sections_needing_separator(lines)
  local n = #lines
  local result = {}
  local in_fence = false

  for i = 1, n do
    local line = lines[i] or ""
    if line:match("^%s*```") or line:match("^%s*~~~") then in_fence = not in_fence end

    if not in_fence and is_h2_or_more(line) then
      local next_heading = find_next_h2_heading(lines, i)
      if next_heading then
        local section_end = find_section_end(lines, i, next_heading)
        local has_content = section_end ~= i
        local ok = has_content and has_separator_after(lines, section_end, next_heading)
          or (not has_content and has_single_blank_gap(lines, i, next_heading))
        if not ok then
          table.insert(result, {
            heading_idx = i,
            section_end_idx = section_end,
            next_heading_idx = next_heading,
            has_content = has_content,
          })
        end
      end
    end
  end

  return result
end

--- Ensure the final H2+ section is also closed with a `---` separator at EOF
--- — but only when that section actually has content. An empty final section
--- (nothing but blank lines/stray `---` after the last heading) is collapsed
--- to a single trailing blank line instead. Operates on fresh buffer lines,
--- so it is safe to run after the between-section pass. Idempotent: a no-op
--- when the document is already correctly formatted.
---@param bufnr integer
---@return boolean changed
local function ensure_final_closer(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local n = #lines

  -- Find the last H2+ heading (outside fenced code).
  local in_fence = false
  local last_heading = nil
  for i = 1, n do
    local line = lines[i] or ""
    if line:match("^%s*```") or line:match("^%s*~~~") then in_fence = not in_fence end
    if not in_fence and is_h2_or_more(line) then last_heading = i end
  end
  if not last_heading then return false end

  -- Last line of actual content in the final section.
  local section_end = last_heading
  for i = n, last_heading + 1, -1 do
    local l = lines[i] or ""
    if l ~= "---" and l:match("%S") then
      section_end = i
      break
    end
  end

  if section_end == last_heading then
    -- No content in the final section: no separator belongs here. Just
    -- collapse whatever trails the heading (extra blanks, a stray `---`)
    -- down to a single blank line.
    if n == last_heading then return false end
    if n - last_heading == 1 and lines[last_heading + 1] == "" then return false end
    api.nvim_buf_set_lines(bufnr, last_heading, n, false, { "" })
    return true
  end

  -- Already closed? A `---` anywhere after the content means it's done.
  for i = section_end + 1, n do
    if (lines[i] or "") == "---" then return false end
  end

  -- Replace any trailing blank lines after the content with the separator block.
  api.nvim_buf_set_lines(bufnr, section_end, n, false, { "", "---", "" })
  return true
end

---Inserts missing section separators (between-section and final-section).
---@param bufnr integer
---@param opts? { notify?: boolean, dry_run?: boolean }
---@return integer fixed
function M.apply_headl_separators(bufnr, opts)
  opts = opts or {}
  local notify_enabled = opts.notify ~= false
  local dry_run = opts.dry_run == true

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sections = M.find_sections_needing_separator(lines)

  if dry_run then
    if notify_enabled then notify.info(string.format("would fix %d sections", #sections)) end
    return #sections
  end

  local offset = 0

  for _, section in ipairs(sections) do
    local adjusted_end = section.section_end_idx + offset
    local adjusted_next = section.next_heading_idx + offset

    local lines_between = adjusted_next - adjusted_end - 1
    if lines_between > 0 then
      api.nvim_buf_set_lines(bufnr, adjusted_end, adjusted_end + lines_between, false, {})
      offset = offset - lines_between
    end

    -- A section with content gets the full `[blank]---[blank]` separator;
    -- an empty section just gets a single blank line, no `---`.
    local replacement = section.has_content and { "", "---", "" } or { "" }
    api.nvim_buf_set_lines(bufnr, adjusted_end, adjusted_end, false, replacement)
    offset = offset + #replacement
  end

  -- Close the final section at EOF as well.
  local final_changed = ensure_final_closer(bufnr)

  local fixed = #sections + (final_changed and 1 or 0)
  if notify_enabled then
    if fixed == 0 then
      notify.info("all sections properly formatted")
    else
      notify.info(string.format("fixed %d sections", fixed))
    end
  end

  return fixed
end

return M
