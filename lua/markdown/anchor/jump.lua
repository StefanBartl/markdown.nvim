---@module 'markdown.anchor.jump'
--- Jumps the cursor to the heading matched by the anchor under it.
local notify = require("markdown.util.notify").create("[markdown.anchor.jump]")

local M = {}
local api = vim.api

---@internal
---@param title string
---@return string
local function slugify_gfm(title)
  local s = title:lower()
  s = s:gsub("%s+", "-")
  s = s:gsub("[^%w%-%_]", "")
  s = s:gsub("%-+", "-")
  s = s:gsub("^[-_]+", ""):gsub("[-_]+$", "")
  return s
end

---@internal
---@param line string?
---@return string? anchor
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

--- Resolve the scan window for anchor resolution from the fenced-block scope.
--- Inside a markdown-family block the search is confined to that block's
--- interior; outside, it spans the whole buffer but excludes every fenced
--- block's interior (so an inner heading never captures an outer anchor). When
--- the feature is off, falls back to the whole buffer (the caller's in_fence
--- toggle then handles skipping, as before).
---@param bufnr integer
---@return integer lower, integer upper, { first: integer, last: integer }[]|nil exclude
local function resolve_range(bufnr)
  local total = api.nvim_buf_line_count(bufnr)
  local scope = require("markdown.scope")
  if scope.op_enabled("jump") then
    local sc = scope.detect(bufnr)
    if sc and sc.kind == "block" then
      return sc.first, sc.last, nil
    elseif sc and sc.kind == "buffer" then
      return 1, total, sc.exclude
    end
  end
  return 1, total, nil
end

---@internal
---@param anchor string?
---@return boolean
local function jump_to_anchor(anchor)
  if not anchor or anchor == "" then return false end

  local bufnr = api.nvim_get_current_buf()
  local lower, upper, exclude = resolve_range(bufnr)
  local function excluded(i)
    if not exclude then return false end
    for _, r in ipairs(exclude) do
      if i >= r.first and i <= r.last then return true end
    end
    return false
  end
  local seen_count = {}
  local in_fence = false
  -- 3+ backticks/tildes + optional info string. `{3,}` is not a Lua-pattern
  -- quantifier, so three-or-more is spelled out explicitly.
  local fence_pattern = "^%s*[`~][`~][`~]+%S*%s*$"

  for i = lower, upper do
    local line = api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""

    if line:match(fence_pattern) then
      in_fence = not in_fence
    elseif not in_fence and not excluded(i) then
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

---Jumps to the heading referenced by the anchor under the cursor's current line.
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

  -- `ok` is pcall's own success flag (no Lua error), not jump_to_anchor's
  -- "found it" result — the two were conflated before, so a plain "heading
  -- not found" case (no error, `jumped == false`) fell through both branches
  -- and gave the user no feedback at all.
  local ok_jump, jumped = pcall(jump_to_anchor, anchor)
  if not ok_jump then
    notify.warn("Could not jump to anchor: " .. anchor)
  elseif not jumped then
    notify.info("No heading found for anchor: " .. anchor)
  end
end

return M
