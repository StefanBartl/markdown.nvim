---@module 'markdown.core.link_scan'
--- Extract link-like targets (markdown inline links and bare URLs) from lines,
--- a buffer, or a list of lines. Shared by the cursor handler (`ml`) and the
--- `:Markdown links show` command.
local M = {}

local api = vim.api

-- `Mkdn.Link` is declared in `markdown.@types`.

local FENCE = "^%s*[`~][`~][`~]"

-- Conservative bare-URL character class (mirrors handler/url.lua).
local URL_PATTERN = "https?://[%w%-%_%.%/%?%%=&~#@:+,;]+"

local ok_lib_trim, lib_strings_core = pcall(require, "lib.lua.strings.core")

---@internal
---@param s string
---@return string
local function trim(s)
  if ok_lib_trim then return lib_strings_core.trim(s) end
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

---@internal
---@param s string
---@return string
local function strip_angle_brackets(s)
  if s:match("^<.+>$") then return s:sub(2, -2) end
  return s
end

---@internal
---@param s string
---@return string
local function strip_trailing_punct(s)
  return (s:gsub("[%.,;:%)%]%}>]+$", ""))
end

--- Extract all links from a single line of text.
---@param line string
---@param lnum integer
---@return Mkdn.Link[]
function M.from_line(line, lnum)
  local out = {}
  if not line or line == "" then return out end

  -- Markdown inline links: [text](target). Record covered byte ranges so the
  -- bare-URL pass does not re-report a URL that is already a link target.
  local covered = {}
  local from = 1
  while true do
    local s, e, text, target = line:find("%[(.-)%]%((.-)%)", from)
    if not s then break end
    if target and target ~= "" then
      local t = strip_angle_brackets(trim(target))
      out[#out + 1] = {
        display = string.format("[%s](%s)", text, t),
        target  = t,
        text    = text,
        kind    = "mdlink",
        lnum    = lnum,
        col     = s - 1,
        col_end = e - 1,
      }
    end
    covered[#covered + 1] = { s, e }
    from = e + 1
  end

  -- Bare URLs outside any covered markdown-link span.
  local us = 1
  while true do
    local s, e = line:find(URL_PATTERN, us)
    if not s then break end
    local inside = false
    for _, r in ipairs(covered) do
      if s >= r[1] and s <= r[2] then
        inside = true
        break
      end
    end
    if not inside then
      local url = strip_trailing_punct(line:sub(s, e))
      out[#out + 1] = {
        display = url,
        target  = url,
        kind    = "url",
        lnum    = lnum,
        col     = s - 1,
        col_end = e - 1,
      }
    end
    us = e + 1
  end

  return out
end

--- Extract links from a list of lines, skipping fenced code blocks.
---@param lines string[]
---@return Mkdn.Link[]
function M.from_lines(lines)
  local out = {}
  local in_fence = false
  for i, line in ipairs(lines) do
    if line:match(FENCE) then in_fence = not in_fence end
    if not in_fence then
      local found = M.from_line(line, i)
      for _, lk in ipairs(found) do out[#out + 1] = lk end
    end
  end
  return out
end

--- Extract all links in a buffer (skips fenced code blocks).
---@param bufnr? integer
---@return Mkdn.Link[]
function M.from_buffer(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return M.from_lines(lines)
end

return M
