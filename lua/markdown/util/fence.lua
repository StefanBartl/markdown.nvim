---@module 'markdown.util.fence'
---@brief Fenced code block detection for plain line lists.
---@description
--- A backtick fence has no backtick in its info string (so "```code``` text" is
--- inline code, not a fence); a closing fence is the same character, at least as
--- long as the opener, with nothing else on the line (so "```lua" does not close).
---
---   M.open(line)              – "`"|"~", length  when `line` opens a fence
---   M.close(line, char, len)  – whether `line` closes a fence opened with char x len
---   M.mask(lines)             – boolean per line: inside a fence (fence lines included)

local M = {}

---@param line string
---@return string|nil char, integer|nil len
function M.open(line)
  local m = line:match("^%s*(```+)[^`]*$")
  if m then return "`", #m end
  m = line:match("^%s*(~~~+)")
  if m then return "~", #m end
end

---@param line string
---@param char string
---@param len integer
---@return boolean
function M.close(line, char, len)
  local m = line:match("^%s*(" .. char .. "+)%s*$")
  return m ~= nil and #m >= len
end

---@param lines string[]
---@return boolean[] inside
function M.mask(lines)
  local inside, c, n = {}, nil, nil
  for i, line in ipairs(lines) do
    if not c then
      c, n = M.open(line)
      inside[i] = c ~= nil
    else
      inside[i] = true
      if M.close(line, c, n) then
        c, n = nil, nil
      end
    end
  end
  return inside
end

return M
