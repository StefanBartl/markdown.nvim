---@module 'markdown_nvim.core.headings'
local M = {}

local api, fn = vim.api, vim.fn
local cfg = require("markdown_nvim.config").get

local ANY_HEADING = "^##\\+\\s\\+.*$"

local function level_pattern(level)
  return "^" .. string.rep("#", level) .. "\\s\\+.*$"
end

function M.goto_prev_heading()
  for _ = 1, vim.v.count1 do
    fn.search(ANY_HEADING, "bWs")
  end
  vim.cmd("nohlsearch")
end

function M.goto_next_heading()
  for _ = 1, vim.v.count1 do
    fn.search(ANY_HEADING, "Ws")
  end
  vim.cmd("nohlsearch")
end

function M.goto_prev_heading_level()
  local count = vim.v.count
  local pattern = count > 0 and level_pattern(count) or ANY_HEADING
  fn.search(pattern, "bWs")
  vim.cmd("nohlsearch")
end

function M.goto_next_heading_level()
  local count = vim.v.count
  local pattern = count > 0 and level_pattern(count) or ANY_HEADING
  fn.search(pattern, "Ws")
  vim.cmd("nohlsearch")
end

local function shift_heading_line(line, delta, min_level, allow_creation)
  if line == "" or line:match("^%s*$") then
    return line, false
  end

  local hashes, rest = line:match("^(%s*#+)%s+(.*)$")

  if not hashes then
    if delta > 0 and allow_creation then
      return "# " .. line, true
    end
    return line, false
  end

  local indent = hashes:match("^%s*") or ""
  local level = #hashes - #indent

  if level == 1 and delta < 0 then
    return rest, true
  end

  local new_level = math.max(min_level, math.min(6, level + delta))
  if new_level == level then
    return line, false
  end

  return string.format("%s%s %s", indent, string.rep("#", new_level), rest), true
end

local function shift_range_internal(bufnr, srow, erow, delta, min_level, allow_creation)
  local lines = api.nvim_buf_get_lines(bufnr, srow - 1, erow, false)
  local changed = 0
  local in_fence = false
  local fence_pat = "^%s*([`~]{3,})"

  for i = 1, #lines do
    local line = lines[i]
    local fence = line:match(fence_pat)
    if fence then
      in_fence = not in_fence
    end
    if not in_fence then
      local out, did = shift_heading_line(line, delta, min_level, allow_creation)
      if did then
        lines[i] = out
        changed = changed + 1
      end
    end
  end

  if changed > 0 then
    api.nvim_buf_set_lines(bufnr, srow - 1, erow, false, lines)
  end

  return changed
end

function M.shift_range(srow, erow, delta)
  if type(srow) ~= "number" or type(erow) ~= "number" then return 0 end
  if srow < 1 or erow < srow then return 0 end
  if type(delta) ~= "number" or delta == 0 then return 0 end
  if vim.bo.filetype ~= "markdown" then return 0 end

  local bufnr = api.nvim_get_current_buf()
  if not (api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr)) then return 0 end

  local min_level = cfg().protect_h1 and 2 or 1
  local allow_creation = (srow == erow)

  local view = fn.winsaveview()
  local changed = shift_range_internal(bufnr, srow, erow, delta, min_level, allow_creation)
  if changed > 0 then fn.winrestview(view) end

  return changed
end

function M.shift_visual_selection(delta)
  if type(delta) ~= "number" or delta == 0 then return end
  if vim.bo.filetype ~= "markdown" then return end

  local bufnr = api.nvim_get_current_buf()
  if not (api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr)) then return end

  local start_line = fn.line("v")
  local end_line = fn.line(".")
  local srow = math.min(start_line, end_line)
  local erow = math.max(start_line, end_line)

  vim.cmd('normal! \\<Esc>')

  if srow > 0 and erow > 0 then
    M.shift_range(srow, erow, delta)
  end
end

local function op_get_repeat()
  local n = vim.b._markdown_heading_op_count
  if type(n) ~= "number" or n < 1 then return 1 end
  vim.b._markdown_heading_op_count = nil
  return n
end

function M._op_increase(_)
  local n = op_get_repeat()
  local srow = api.nvim_buf_get_mark(0, "[")[1]
  local erow = api.nvim_buf_get_mark(0, "]")[1]
  if srow and erow and srow > 0 and erow > 0 then
    M.shift_range(math.min(srow, erow), math.max(srow, erow), n)
  end
end

function M._op_decrease(_)
  local n = op_get_repeat()
  local srow = api.nvim_buf_get_mark(0, "[")[1]
  local erow = api.nvim_buf_get_mark(0, "]")[1]
  if srow and erow and srow > 0 and erow > 0 then
    M.shift_range(math.min(srow, erow), math.max(srow, erow), -n)
  end
end

return M
