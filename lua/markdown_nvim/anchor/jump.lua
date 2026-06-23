---@module 'markdown_nvim.anchor.jump'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.anchor.jump]")

local M = {}
local api = vim.api

local function slugify_gfm(title)
  local s = title:lower()
  s = s:gsub("%s+", "-")
  s = s:gsub("[^%w%-%_]", "")
  s = s:gsub("%-+", "-")
  s = s:gsub("^[-_]+", ""):gsub("[-_]+$", "")
  return s
end

local function extract_anchor(line)
  if not line or line == "" then return nil end

  local md = line:match("%(#([^)]+)%)")
  if md then return md end

  local img = line:match("<img[^>]-src%s*=%s*[\"']#(.-)[\"']")
  if img then return img end

  local ahref = line:match("<a[^>]-href%s*=%s*[\"']#(.-)[\"']")
  if ahref then return ahref end

  local idtag = line:match("<%w+[^>]-id%s*=%s*[\"']#(.-)[\"']")
  if idtag then return idtag end

  return nil
end

local function jump_to_anchor(anchor)
  if not anchor or anchor == "" then return false end

  local bufnr = api.nvim_get_current_buf()
  local total = api.nvim_buf_line_count(bufnr)
  local seen_count = {}
  local in_fence = false
  local fence_pattern = "^%s*([`~]{3,})%S*%s*$"

  for i = 1, total do
    local line = api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""

    if line:match(fence_pattern) then
      in_fence = not in_fence
    elseif not in_fence then
      local hashes, title = line:match("^(%s*#+)%s+(.*%S)")
      if hashes and title then
        local base = slugify_gfm(title)
        if base == "" then base = "section-" .. i end
        local count = seen_count[base] or 0
        local current_anchor = count == 0 and base or (base .. "-" .. tostring(count))
        seen_count[base] = count + 1

        if current_anchor == anchor then
          api.nvim_win_set_cursor(0, { i, 0 })
          vim.cmd("normal! zz")
          return true
        end
      end
    end
  end

  return false
end

function M.jump()
  local ok, line = pcall(api.nvim_get_current_line)
  if not ok or not line then
    notify.error("Could not read current line")
    return
  end

  local anchor = extract_anchor(line)
  if not anchor then
    notify.info("No anchor found under cursor")
    return
  end

  local success = pcall(jump_to_anchor, anchor)
  if not success then
    notify.warn("Could not jump to anchor: " .. anchor)
  end
end

return M
