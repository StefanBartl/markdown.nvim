---@module 'markdown_nvim.core.table_mode'
---@brief A focused Lua reimplementation of vim-table-mode's core, fused with the
---       markdown.nvim table stack (reuses core.table_fmt for alignment).
---@description
--- Provides the most-used table-mode features without a Vimscript dependency:
---   * mode      — per-buffer auto-format: after each edit inside a GFM table the
---                 table is re-aligned (InsertLeave + TextChanged, debounced).
---   * tableize  — convert delimited text (CSV/TSV/2+ spaces) into a GFM table.
---   * motions   — jump to the previous / next cell on the current row.
--- Alignment is delegated to `core.table_fmt.format_table_at_cursor`, so the
--- header/cell alignment config and separator style stay consistent with
--- `:Markdown table format`.

local fmt = require("markdown_nvim.core.table_fmt")

local api = vim.api
local uv  = vim.uv or vim.loop

local M = {}

-- Per-buffer state: augroup id, debounce timer, and a re-entrancy guard so the
-- reformat's own buffer write does not retrigger the TextChanged handler.
---@type table<integer, { aug: integer, timer: any, busy: boolean }>
local S = {}

-- ---------------------------------------------------------------------------
-- Detection / reformat
-- ---------------------------------------------------------------------------

local function is_table_line(line)
  return type(line) == "string" and line:match("^%s*|.*|%s*$") ~= nil
end

--- True when the cursor row is a GFM table line.
---@param bufnr integer
---@return boolean
local function cursor_in_table(bufnr)
  local ok, cur = pcall(api.nvim_win_get_cursor, 0)
  if not ok then return false end
  local line = api.nvim_buf_get_lines(bufnr, cur[1] - 1, cur[1], false)[1]
  return is_table_line(line)
end

--- Re-align the table under the cursor, preserving the cursor position as well
--- as possible across width changes. No-op when the cursor is not in a table.
---@param bufnr integer
function M.reformat(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if not api.nvim_buf_is_valid(bufnr) then return end
  if not cursor_in_table(bufnr) then return end

  local st = S[bufnr]
  local win = api.nvim_get_current_win()
  local cur = api.nvim_win_get_cursor(win)

  if st then st.busy = true end
  pcall(fmt.format_table_at_cursor, bufnr, {})
  if st then st.busy = false end

  -- Clamp the saved cursor back into the (possibly reshaped) buffer.
  local lc = api.nvim_buf_line_count(bufnr)
  local row = math.min(cur[1], lc)
  local llen = #(api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or "")
  pcall(api.nvim_win_set_cursor, win, { row, math.min(cur[2], llen) })
end

-- ---------------------------------------------------------------------------
-- Mode (per-buffer auto-format)
-- ---------------------------------------------------------------------------

---@param bufnr integer
---@return boolean
function M.is_enabled(bufnr)
  return S[bufnr] ~= nil
end

--- Enable auto-format for `bufnr`: a debounced reformat runs after leaving
--- insert mode or changing text while the cursor is inside a table.
---@param bufnr? integer
function M.enable(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if S[bufnr] then return end

  local aug = api.nvim_create_augroup("MarkdownNvimTableMode_" .. bufnr, { clear = true })
  S[bufnr] = { aug = aug, timer = nil, busy = false }

  local function schedule()
    local st = S[bufnr]
    if not st or st.busy then return end
    if st.timer then st.timer:stop(); pcall(function() st.timer:close() end); st.timer = nil end
    local t = uv.new_timer()
    st.timer = t
    t:start(120, 0, function()
      t:stop(); pcall(function() t:close() end)
      if S[bufnr] and S[bufnr].timer == t then S[bufnr].timer = nil end
      vim.schedule(function()
        if S[bufnr] and api.nvim_buf_is_valid(bufnr) then M.reformat(bufnr) end
      end)
    end)
  end

  api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
    group = aug,
    buffer = bufnr,
    callback = schedule,
    desc = "[markdown.nvim] table mode: auto-format",
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = aug,
    buffer = bufnr,
    callback = function() M.disable(bufnr) end,
  })
end

---@param bufnr? integer
function M.disable(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local st = S[bufnr]
  if not st then return end
  if st.timer then st.timer:stop(); pcall(function() st.timer:close() end) end
  pcall(api.nvim_del_augroup_by_id, st.aug)
  S[bufnr] = nil
end

--- Toggle auto-format for `bufnr`. Returns the new state.
---@param bufnr? integer
---@return boolean enabled
function M.toggle(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if M.is_enabled(bufnr) then
    M.disable(bufnr)
    return false
  end
  M.enable(bufnr)
  return true
end

-- ---------------------------------------------------------------------------
-- Tableize
-- ---------------------------------------------------------------------------

--- Pick a field delimiter for `lines`. Explicit `delim` wins; otherwise auto:
--- tab, then comma, then runs of 2+ spaces. Returns a Lua pattern and a label.
---@param lines string[]
---@param delim? string  literal delimiter, or nil for auto
---@return string pattern, string label
local function pick_delim(lines, delim)
  if delim and delim ~= "" and delim ~= "auto" then
    if delim == "\\t" or delim == "tab" then return "\t", "tab" end
    return vim.pesc(delim), delim
  end
  local sample = ""
  for _, l in ipairs(lines) do if l:match("%S") then sample = l; break end end
  if sample:find("\t") then return "\t", "tab" end
  if sample:find(",") then return ",", "," end
  if sample:find("%s%s+") then return "%s%s+", "whitespace" end
  return "\t", "tab" -- single-column fallback (no delimiter present)
end

--- Split `line` into trimmed fields on the (Lua-pattern) delimiter.
---@param line string
---@param pat string
---@return string[]
local function split_fields(line, pat)
  local out = {}
  local pos = 1
  while true do
    local s, e = line:find(pat, pos)
    if not s then break end
    out[#out + 1] = vim.trim(line:sub(pos, s - 1))
    pos = e + 1
  end
  out[#out + 1] = vim.trim(line:sub(pos))
  return out
end

--- Convert lines `[line1, line2]` (1-indexed inclusive) of `bufnr` into a GFM
--- table: first row becomes the header, a separator is inserted, the result is
--- alignment-formatted. Blank lines are skipped. Returns ok, err.
---@param bufnr integer
---@param line1 integer
---@param line2 integer
---@param delim? string
---@return boolean ok, string|nil err
function M.tableize(bufnr, line1, line2, delim)
  bufnr = bufnr or api.nvim_get_current_buf()
  local raw = api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)

  local rows = {}
  for _, l in ipairs(raw) do
    if l:match("%S") then rows[#rows + 1] = l end
  end
  if #rows == 0 then return false, "tableize: no non-empty lines in range" end

  local pat = pick_delim(rows, delim)
  local matrix = {}
  local cols = 0
  for _, l in ipairs(rows) do
    local f = split_fields(l, pat)
    matrix[#matrix + 1] = f
    cols = math.max(cols, #f)
  end

  -- Build a raw GFM table (header, separator, body); table_fmt re-aligns it.
  local function render(cells)
    local parts = {}
    for i = 1, cols do parts[i] = cells[i] or "" end
    return "| " .. table.concat(parts, " | ") .. " |"
  end
  local out = { render(matrix[1]) }
  local sep = {}
  for i = 1, cols do sep[i] = "---" end
  out[#out + 1] = "| " .. table.concat(sep, " | ") .. " |"
  for i = 2, #matrix do out[#out + 1] = render(matrix[i]) end

  api.nvim_buf_set_lines(bufnr, line1 - 1, line2, false, out)

  -- Align it in place (cursor onto the header first so at_cursor finds it).
  pcall(api.nvim_win_set_cursor, 0, { line1, 0 })
  pcall(fmt.format_table_at_cursor, bufnr, {})
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Cell motions
-- ---------------------------------------------------------------------------

--- Byte columns (0-indexed) of the first content char of every cell on `line`
--- (position just after each `|`, skipping leading spaces; the trailing `|` at
--- end-of-line yields no cell and is dropped).
---@param line string
---@return integer[]
local function cell_starts(line)
  local starts = {}
  local pos = 1
  while true do
    local s = line:find("|", pos, true)
    if not s then break end
    pos = s + 1
    local t = s -- 0-indexed position of the `|` is s-1; content begins at s
    while t < #line and line:sub(t + 1, t + 1) == " " do t = t + 1 end
    if t < #line then starts[#starts + 1] = t end -- t is 0-indexed content col
  end
  return starts
end

--- Move to the first non-space of the next cell on the current row.
function M.next_cell()
  local win = api.nvim_get_current_win()
  local cur = api.nvim_win_get_cursor(win)
  local line = api.nvim_get_current_line()
  if not is_table_line(line) then return end
  for _, c in ipairs(cell_starts(line)) do
    if c > cur[2] then
      api.nvim_win_set_cursor(win, { cur[1], c })
      return
    end
  end
end

--- Move to the first non-space of the previous cell on the current row.
function M.prev_cell()
  local win = api.nvim_get_current_win()
  local cur = api.nvim_win_get_cursor(win)
  local line = api.nvim_get_current_line()
  if not is_table_line(line) then return end
  local starts = cell_starts(line)
  -- Index of the current cell = last start ≤ cursor; jump to the one before it.
  local idx = nil
  for i = #starts, 1, -1 do
    if starts[i] <= cur[2] then idx = i; break end
  end
  if idx and idx > 1 then
    api.nvim_win_set_cursor(win, { cur[1], starts[idx - 1] })
  end
end

return M
