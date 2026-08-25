---@module 'markdown.core.underline_headings'
--- Inserts a Setext-style underline (default `=`) below every ATX heading's
--- text, matching the heading text's length. Purely visual decoration, not a
--- conversion to real Setext syntax (the `#` marker is left untouched, and
--- this applies at every level, not just H1/H2).
local api = vim.api
local notify = require("markdown.util.notify").create("[markdown.core.underline_headings]")

local M = {}

---@internal
---@param line string
---@return string? text
local function heading_text(line)
  local text = line:match("^#+%s+(.-)%s*$")
  return text ~= "" and text or nil
end

---@internal
---@param line string
---@param char string
---@return boolean
local function is_underline_of(line, char) return line:match("^%" .. char .. "+$") ~= nil end

---Inserts/updates the underline below every ATX heading in `[srow, erow]`
---(1-indexed, inclusive). Idempotent: an existing correctly-sized underline
---is left alone; a wrongly-sized one is corrected; fenced code interiors are
---skipped.
---@param bufnr integer
---@param srow integer
---@param erow integer
---@param char string Single underline character, e.g. "=".
---@return integer changed
function M.apply_range(bufnr, srow, erow, char)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local n = #lines
  erow = math.min(erow, n)

  local changed = 0
  local offset = 0
  local in_fence = false

  for i = 1, n do
    local line = lines[i]
    if line:match("^%s*```") or line:match("^%s*~~~") then in_fence = not in_fence end

    if not in_fence and i >= srow and i <= erow then
      local text = heading_text(line)
      if text then
        local want = char:rep(#text)
        local next_line = lines[i + 1]
        local adjusted = i + offset

        -- `next_line == want` is the already-correct case: no edit, no count.
        if next_line ~= want then
          if next_line and is_underline_of(next_line, char) then
            api.nvim_buf_set_lines(bufnr, adjusted, adjusted + 1, false, { want })
          else
            api.nvim_buf_set_lines(bufnr, adjusted, adjusted, false, { want })
            offset = offset + 1
          end
          changed = changed + 1
        end
      end
    end
  end

  return changed
end

---Inserts/updates the underline below every ATX heading in the buffer.
---@param bufnr integer
---@param opts? { notify?: boolean, char?: string }
---@return integer changed
function M.apply(bufnr, opts)
  opts = opts or {}
  local notify_enabled = opts.notify ~= false
  local char = opts.char or "="

  local n = api.nvim_buf_line_count(bufnr)
  local changed = M.apply_range(bufnr, 1, n, char)

  if notify_enabled then
    if changed == 0 then
      notify.info("all headings already underlined")
    else
      notify.info(string.format("underlined %d heading(s)", changed))
    end
  end

  return changed
end

return M
