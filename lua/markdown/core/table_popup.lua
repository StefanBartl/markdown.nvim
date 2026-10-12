---@module 'markdown.core.table_popup'
---@brief Popup with the full text of the table cell under the cursor.
---@description
--- Companion of `core.table_truncate`: a cell shown cut with `…` gets its whole
--- text in a small float next to the cursor. Native float (no dependency on
--- hover.nvim, which is optional for this plugin); the float never takes
--- focus and closes on the next cursor move, mode change or buffer switch.
---
---   M.cell_at(line, col)   – pure: the cell under byte column `col` (0-based)
---   M.show(bufnr, opts)    – open the popup (`opts.force`: even if the cell fits)
---   M.close()

local lib_table = require("lib.nvim.markdown.table")

local M = {}

local api = vim.api

---@class Mkdn.TableCellAt
---@field index integer   # 1-based column
---@field text string     # trimmed cell text, `\|` shown as `|`
---@field s integer       # 1-based first byte of the raw cell
---@field e integer       # 1-based last byte of the raw cell

---Pure: the cell of table row `line` that byte column `col` (0-based, as
---`nvim_win_get_cursor` reports it) is in. The pipe in front of a cell belongs
---to that cell. Nil for a non-row, a separator row, or a column past the last cell.
---@param line string
---@param col integer
---@return Mkdn.TableCellAt|nil
function M.cell_at(line, col)
  if not lib_table.is_table_line(line) or lib_table.is_separator_line(line) then return nil end
  local cells, ranges = lib_table.split_cells(line)
  local c1 = col + 1
  for i, rng in ipairs(ranges) do
    if c1 >= rng[1] - 1 and c1 <= rng[2] then
      local text = cells[i]:gsub("\\|", "|")
      return { index = i, text = text, s = rng[1], e = rng[2] }
    end
  end
  return nil
end

---Pure: the lines of the popup body, hard-wrapped at `width` display columns
---(word boundaries first).
---@param text string
---@param width integer
---@return string[]
function M.body(text, width)
  local out, cur = {}, ""
  for word in text:gmatch("%S+") do
    if cur == "" then
      cur = word
    elseif vim.fn.strdisplaywidth(cur .. " " .. word) <= width then
      cur = cur .. " " .. word
    else
      out[#out + 1] = cur
      cur = word
    end
    while vim.fn.strdisplaywidth(cur) > width do
      -- an unbreakable word longer than the float: cut by characters
      local keep, used = 0, 0
      for i = 0, vim.fn.strchars(cur) - 1 do
        local w = vim.fn.strdisplaywidth(vim.fn.strcharpart(cur, i, 1))
        if used + w > width then break end
        used = used + w
        keep = i + 1
      end
      keep = math.max(keep, 1)
      out[#out + 1] = vim.fn.strcharpart(cur, 0, keep)
      cur = vim.fn.strcharpart(cur, keep)
    end
  end
  if cur ~= "" then out[#out + 1] = cur end
  if #out == 0 then out[1] = "" end
  return out
end

---@type { win: integer, buf: integer, group: integer }|nil
local current

function M.close()
  if not current then return end
  local c = current
  current = nil
  pcall(api.nvim_del_augroup_by_id, c.group)
  if api.nvim_win_is_valid(c.win) then pcall(api.nvim_win_close, c.win, true) end
  if api.nvim_buf_is_valid(c.buf) then pcall(api.nvim_buf_delete, c.buf, { force = true }) end
end

---@return boolean
function M.is_open() return current ~= nil and api.nvim_win_is_valid(current.win) end

---Open the popup for the cell under the cursor.
---@param bufnr? integer
---@param opts? { force?: boolean, max?: integer }
---@return boolean shown
function M.show(bufnr, opts)
  opts = opts or {}
  bufnr = bufnr or api.nvim_get_current_buf()
  if bufnr ~= api.nvim_get_current_buf() then return false end
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
  local cell = line and M.cell_at(line, col)
  if not cell or cell.text == "" then return false end

  local cfg = ((require("markdown.config").get().table or {}).truncate or {})
  local limit = opts.max or cfg.max or require("markdown.core.table_truncate").DEFAULT_MAX
  -- Only a cut cell has more to show, unless asked explicitly.
  if not opts.force and vim.fn.strdisplaywidth(cell.text) <= limit then return false end

  M.close()
  local width = math.max(20, math.min(80, vim.o.columns - 8))
  local text = cell.text
  local cap = width * 15
  if vim.fn.strchars(text) > cap then text = vim.fn.strcharpart(text, 0, cap) .. "…" end
  local lines = M.body(text, width)
  local used = 0
  for _, l in ipairs(lines) do
    used = math.max(used, vim.fn.strdisplaywidth(l))
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local opened, win = pcall(api.nvim_open_win, buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = math.max(used, 1),
    height = math.min(#lines, 15),
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
  })
  if not opened then
    pcall(api.nvim_buf_delete, buf, { force = true })
    return false
  end
  api.nvim_set_option_value("wrap", true, { scope = "local", win = win })
  local group = api.nvim_create_augroup("MarkdownNvimTablePopup", { clear = true })
  current = { win = win, buf = buf, group = group }
  api.nvim_create_autocmd(
    { "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave", "WinScrolled" },
    {
      group = group,
      callback = function() M.close() end,
      desc = "[markdown.nvim] table popup: close",
    }
  )
  return true
end

return M
