---@module 'markdown.core.table_truncate'
---@brief Display-only truncation of over-wide table cells.
---@description
--- A column wider than `max` display columns is shown cut with a marker
--- (`…`) so every table row stays one line. The file text is never touched:
--- the cut tail is hidden with extmark `conceal`, which needs
--- `conceallevel` >= 2 in the window (set while truncation is on, restored
--- after). The line under the cursor shows its full text unless
--- `concealcursor` includes the current mode.
---
--- The formatter pads every cell to the column's natural width, so cutting
--- only the long cells would misalign the column: the surplus padding of
--- every other cell (and surplus dashes of the separator row) is concealed
--- too, so each cell of a truncated column is `visible = min(content, max)`
--- columns wide.
---
---   M.compute(lines, opts)   – pure: per-line conceal ranges
---   M.render(bufnr)          – apply extmarks for the whole buffer
---   M.clear(bufnr)           – remove them
---   M.enable/disable/toggle(bufnr)

local lib_table = require("lib.nvim.markdown.table")

local M = {}

local api = vim.api
local NS = api.nvim_create_namespace("markdown_table_truncate")

M.DEFAULT_MAX = 40
M.DEFAULT_MARKER = "…"
local MAX_ROWS = 3000

---@class Mkdn.TruncateConceal
---@field s integer  # 1-based first byte
---@field e integer  # 1-based last byte (inclusive)
---@field text string # replacement shown for the range ("" hides it)

---@internal
---@return { max: integer, marker: string }
local function cfg()
  local ok, config = pcall(require, "markdown.config")
  local t = (ok and config.get().table and config.get().table.truncate) or {}
  return { max = t.max or M.DEFAULT_MAX, marker = t.marker or M.DEFAULT_MARKER }
end

---@internal
---Longest prefix of `content` that fits `budget` display columns.
---@param content string
---@param budget integer
---@return integer bytes
local function prefix_bytes(content, budget)
  local used, bytes = 0, 0
  local n = vim.fn.strchars(content)
  for i = 0, n - 1 do
    local ch = vim.fn.strcharpart(content, i, 1)
    local w = vim.fn.strdisplaywidth(ch)
    if used + w > budget then break end
    used = used + w
    bytes = bytes + #ch
  end
  return bytes
end

---Pure: the conceal ranges that truncate the over-wide cells of every table in
---`lines`. Returns a map `line index (1-based) -> TruncateConceal[]`.
---@param lines string[]
---@param opts? { max?: integer, marker?: string }
---@return table<integer, Mkdn.TruncateConceal[]>
function M.compute(lines, opts)
  local d = cfg()
  local max = (opts and opts.max) or d.max
  local marker = vim.fn.strcharpart((opts and opts.marker) or d.marker, 0, 1)
  local result = {}

  for _, tbl in ipairs(lib_table.parse(lines)) do
    if tbl.end_line - tbl.start_line < MAX_ROWS then
      -- Natural width per column over the data rows.
      local widths = {}
      for _, row in ipairs(tbl.rows) do
        for ci, cell in ipairs(row) do
          widths[ci] = math.max(widths[ci] or 0, vim.fn.strdisplaywidth(cell))
        end
      end
      local visible = {}
      local any = false
      for ci, w in pairs(widths) do
        visible[ci] = math.min(w, max)
        if w > max then any = true end
      end

      if any then
        for ln = tbl.start_line, tbl.end_line do
          local line = lines[ln]
          local is_sep = lib_table.is_separator_line(line)
          local cells, ranges = lib_table.split_cells(line)
          local marks = {}
          for ci, rng in ipairs(ranges) do
            local v, w = visible[ci], widths[ci]
            if v and w and v < w then
              local s, e = rng[1], rng[2]
              local raw = line:sub(s, e)
              local lead = #raw:match("^ *")
              local trail = #raw:match(" *$")
              if raw:match("^ *$") then trail = 0 end
              local rw = vim.fn.strdisplaywidth(raw)
              local excess = rw - (v + 2)
              if is_sep then
                -- Hide surplus dashes (keep any trailing alignment colon).
                local body = raw:gsub(" +$", "")
                local stop = #body
                if body:sub(stop, stop) == ":" then stop = stop - 1 end
                local run_start = stop
                while run_start > 1 and body:sub(run_start - 1, run_start - 1) == "-" do
                  run_start = run_start - 1
                end
                local run = stop - run_start + 1
                local cut = math.min(excess, run - 1)
                if cut > 0 then
                  marks[#marks + 1] = { s = s + stop - cut, e = s + stop - 1, text = "" }
                end
              else
                local content = cells[ci]
                local cw = vim.fn.strdisplaywidth(content)
                if cw > v then
                  local keep = prefix_bytes(content, v - vim.fn.strdisplaywidth(marker))
                  local from = s + lead + keep
                  local to = trail >= 1 and (e - 1) or e
                  if to >= from then marks[#marks + 1] = { s = from, e = to, text = marker } end
                elseif excess > 0 then
                  local rt = math.min(excess, math.max(trail - 1, 0))
                  if rt > 0 then marks[#marks + 1] = { s = e - rt, e = e - 1, text = "" } end
                  local rl = math.min(excess - rt, math.max(lead - 1, 0))
                  if rl > 0 then marks[#marks + 1] = { s = s + 1, e = s + rl, text = "" } end
                end
              end
            end
          end
          if #marks > 0 then result[ln] = marks end
        end
      end
    end
  end
  return result
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Buffer state
-- ─────────────────────────────────────────────────────────────────────────────

---@type table<integer, { pending: boolean, group: integer }>
local S = {}

---@param bufnr integer
function M.clear(bufnr)
  if api.nvim_buf_is_valid(bufnr) then api.nvim_buf_clear_namespace(bufnr, NS, 0, -1) end
end

---Apply the truncation extmarks for the whole buffer.
---@param bufnr integer
---@return integer count  # ranges concealed
function M.render(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then return 0 end
  M.clear(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local count = 0
  for ln, marks in pairs(M.compute(lines)) do
    for _, m in ipairs(marks) do
      local ok = pcall(api.nvim_buf_set_extmark, bufnr, NS, ln - 1, m.s - 1, {
        end_row = ln - 1,
        end_col = m.e,
        conceal = m.text,
      })
      if ok then count = count + 1 end
    end
  end
  return count
end

---@internal
---@param bufnr integer
local function set_conceallevel(bufnr, on)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if on then
      if vim.w[win].mkdn_truncate_cl == nil then
        vim.w[win].mkdn_truncate_cl = vim.wo[win].conceallevel
      end
      if vim.wo[win].conceallevel < 2 then vim.wo[win].conceallevel = 2 end
    elseif vim.w[win].mkdn_truncate_cl ~= nil then
      vim.wo[win].conceallevel = vim.w[win].mkdn_truncate_cl
      vim.w[win].mkdn_truncate_cl = nil
    end
  end
end

---@param bufnr? integer
---@return boolean
function M.is_enabled(bufnr) return S[bufnr or api.nvim_get_current_buf()] ~= nil end

---@param bufnr? integer
function M.enable(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if S[bufnr] then return end
  local group = api.nvim_create_augroup("MarkdownNvimTableTruncate" .. bufnr, { clear = true })
  S[bufnr] = { pending = false, group = group }
  local function schedule()
    local st = S[bufnr]
    if not st or st.pending then return end
    st.pending = true
    vim.defer_fn(function()
      if S[bufnr] then
        S[bufnr].pending = false
        M.render(bufnr)
      end
    end, 80)
  end
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    buffer = bufnr,
    callback = schedule,
    desc = "[markdown.nvim] table truncate: re-render",
  })
  api.nvim_create_autocmd("CursorHold", {
    group = group,
    buffer = bufnr,
    callback = function()
      local t = ((require("markdown.config").get().table or {}).truncate or {})
      if t.popup ~= false then require("markdown.core.table_popup").show(bufnr) end
    end,
    desc = "[markdown.nvim] table truncate: popup with the full text of a cut cell",
  })
  api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = bufnr,
    callback = function()
      set_conceallevel(bufnr, true)
      schedule()
    end,
    desc = "[markdown.nvim] table truncate: conceallevel for a new window",
  })
  api.nvim_create_autocmd("BufUnload", {
    group = group,
    buffer = bufnr,
    callback = function()
      S[bufnr] = nil
      pcall(api.nvim_del_augroup_by_id, group)
    end,
  })
  set_conceallevel(bufnr, true)
  M.render(bufnr)
end

---@param bufnr? integer
function M.disable(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local st = S[bufnr]
  if not st then return end
  pcall(api.nvim_del_augroup_by_id, st.group)
  S[bufnr] = nil
  M.clear(bufnr)
  set_conceallevel(bufnr, false)
end

---@param bufnr? integer
---@return boolean now_enabled
function M.toggle(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if M.is_enabled(bufnr) then
    M.disable(bufnr)
    return false
  end
  M.enable(bufnr)
  return true
end

return M
