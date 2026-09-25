---@module 'markdown.core.inline_segment'
---@brief Split a markdown text line into alternating plain/protected segments.
---@description
--- Extracted from heading_format.lua so core.body_format can apply the same
--- protection to full-buffer prose, not just heading text. Anything that
--- rewrites markdown prose needs this: a code span, a link/image target, and
--- a raw HTML tag or autolink are markup or content, not prose, and must be
--- copied through untouched rather than mangled by a text rule.

local M = {}

---@class Mkdn.InlineSegment
---@field text string
---@field verbatim boolean # true: copied through untouched.

--- Split `s` into alternating plain and protected segments.
---
--- Protected: code spans (a backtick run and its matching close), the
--- `](…)` target of an inline link or image, and `<…>` autolinks / raw HTML
--- tags. A segment is never split or merged afterwards, so every later rule
--- can be written as a plain string transform over one segment.
---@param s string
---@return Mkdn.InlineSegment[]
function M.segment(s)
  ---@type Mkdn.InlineSegment[]
  local segs = {}
  local plain = {}
  local i, n = 1, #s

  local function flush()
    if #plain > 0 then
      segs[#segs + 1] = { text = table.concat(plain), verbatim = false }
      plain = {}
    end
  end

  local function take(text)
    flush()
    segs[#segs + 1] = { text = text, verbatim = true }
    i = i + #text
  end

  while i <= n do
    local c = s:sub(i, i)
    local before = i

    if c == "`" then
      local _, run_end = s:find("^`+", i)
      local fence = s:sub(i, run_end)
      -- `true` for a plain find: a backtick run is not a pattern, and the
      -- closing run must match the opening one exactly.
      local close_start = s:find(fence, run_end + 1, true)
      if close_start then take(s:sub(i, close_start + #fence - 1)) end
    elseif c == "]" and s:sub(i + 1, i + 1) == "(" then
      -- `%b()` so a target with nested parens (a Wikipedia URL, say) is taken
      -- whole rather than cut at the first `)`.
      local target = s:match("^%b()", i + 1)
      if target then take("]" .. target) end
    elseif c == "<" then
      local tag = s:match("^<[^<>%s][^<>]*>", i)
      if tag then take(tag) end
    end

    if i == before then
      plain[#plain + 1] = c
      i = i + 1
    end
  end

  flush()
  return segs
end

return M
