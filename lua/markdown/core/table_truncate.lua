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
  if budget <= 0 then return 0 end
  -- Plain ASCII (the usual cell): one byte is one column, no per-character calls.
  if not content:find("[\128-\255]") then return math.min(#content, budget) end
  local used, bytes = 0, 0
  -- skipcc: a base character and its composing marks are one unit, so a cut can
  -- not fall between them and the marks do not use up budget of their own.
  local n = vim.fn.strchars(content, true)
  for i = 0, n - 1 do
    local ch = vim.fn.strcharpart(content, i, 1, true)
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
  local fenced = require("markdown.util.fence").mask(lines)

  for _, tbl in ipairs(lib_table.parse(lines)) do
    -- a table inside a fenced code block is an example, not a table of the document
    if tbl.end_line - tbl.start_line < MAX_ROWS and not fenced[tbl.start_line] then
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
        -- only the delimiter row loses dashes; a data row of dashes (`| - | - |`) is cut like data
        local sep_idx = lib_table.separator_index(lines, tbl.start_line, tbl.end_line)
        for ln = tbl.start_line, tbl.end_line do
          local line = lines[ln]
          local is_sep = ln == sep_idx
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
                  local budget = v - vim.fn.strdisplaywidth(marker)
                  local keep = prefix_bytes(content, budget)
                  -- a double-width character that does not fit leaves a column short: fill it
                  local short = math.max(0, budget - vim.fn.strdisplaywidth(content:sub(1, keep)))
                  local from = s + lead + keep
                  local to = trail >= 1 and (e - 1) or e
                  if to >= from then
                    marks[#marks + 1] = { s = from, e = to, text = marker .. (" "):rep(short) }
                  end
                  -- Centered / right-aligned column: a cut cell that is not the widest
                  -- also has padding in front; keep one margin space, hide the rest.
                  if lead > 1 then
                    marks[#marks + 1] = { s = s + 1, e = s + lead - 1, text = "" }
                  end
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

--- Lines kept concealed beyond the window edges, so a scroll by a few screens
--- does not show raw table text before the next re-render.
local VIEW_MARGIN = 200

---@class Mkdn.TruncateRendered
---@field key string   # "changedtick:max:marker" the marks were computed for
---@field lo integer   # first line (1-based) that carries extmarks
---@field hi number    # last line that carries extmarks (math.huge: all)

---@type table<integer, Mkdn.TruncateRendered>  # what is currently painted per buffer
local rendered_at = {}

---@type table<integer, { key: string, marks: table<integer, Mkdn.TruncateConceal[]> }>
local computed = {}

---@internal
---The line span the windows showing `bufnr` currently display, over all of
---them. `nil` when no window shows the buffer (then everything is painted).
---@param bufnr integer
---@return integer|nil lo, integer|nil hi  # 1-based, inclusive
local function visible_span(bufnr)
  local lo, hi
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    local info = vim.fn.getwininfo(win)[1]
    if info then
      lo = math.min(lo or info.topline, info.topline)
      hi = math.max(hi or info.botline, info.botline)
    end
  end
  return lo, hi
end

---@internal
---What the computed ranges depend on: the text and the settings.
---@param bufnr integer
---@return string
local function render_key(bufnr)
  local d = cfg()
  return ("%d:%d:%s"):format(api.nvim_buf_get_changedtick(bufnr), d.max, d.marker)
end

---@param bufnr integer
function M.clear(bufnr)
  rendered_at[bufnr] = nil
  computed[bufnr] = nil
  if api.nvim_buf_is_valid(bufnr) then api.nvim_buf_clear_namespace(bufnr, NS, 0, -1) end
end

---Apply the truncation extmarks to the lines the windows show (plus a margin).
---The ranges are computed once per text and settings (whole buffer: the width
---of a column needs every row of its table); a scroll only repaints.
---@param bufnr integer
---@return integer count  # ranges concealed
function M.render(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then return 0 end
  -- InsertLeave / BufWinEnter / a scroll inside the painted span fire without
  -- an edit: nothing to redo then.
  local key = render_key(bufnr)
  local vlo, vhi = visible_span(bufnr)
  local done = rendered_at[bufnr]
  if done and done.key == key and (not vlo or (vlo >= done.lo and vhi <= done.hi)) then return 0 end
  local c = computed[bufnr]
  if not c or c.key ~= key then
    c = { key = key, marks = M.compute(api.nvim_buf_get_lines(bufnr, 0, -1, false)) }
    computed[bufnr] = c
  end
  api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  local lo = vlo and math.max(1, vlo - VIEW_MARGIN) or 1
  local hi = vhi and (vhi + VIEW_MARGIN) or math.huge
  rendered_at[bufnr] = { key = key, lo = lo, hi = hi }
  local count = 0
  for ln, marks in pairs(c.marks) do
    if ln >= lo and ln <= hi then
      for _, m in ipairs(marks) do
        local ok = pcall(api.nvim_buf_set_extmark, bufnr, NS, ln - 1, m.s - 1, {
          end_row = ln - 1,
          end_col = m.e,
          conceal = m.text,
        })
        if ok then count = count + 1 end
      end
    end
  end
  return count
end

---@internal
---@param bufnr integer
---@param on boolean
local function set_conceallevel(bufnr, on)
  local guard = require("markdown.core.conceal_guard")
  if on then
    guard.apply("truncate", bufnr)
  else
    guard.restore("truncate", bufnr)
  end
end

---@param bufnr? integer
---@return boolean
function M.is_enabled(bufnr) return S[bufnr or api.nvim_get_current_buf()] ~= nil end

---@param bufnr? integer
function M.enable(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if S[bufnr] then return end
  -- Both hide table text with conceal: the last one switched on wins.
  local tr = package.loaded["markdown.core.table_render"]
  if tr and tr.is_enabled(bufnr) then tr.disable(bufnr) end
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
  -- Not buffer-local (the event is keyed by window): a scroll or resize of any
  -- window showing this buffer repaints when the view left the painted span.
  api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
    group = group,
    callback = function()
      if #vim.fn.win_findbuf(bufnr) == 0 then return end
      local c = computed[bufnr]
      if c and c.key == render_key(bufnr) then
        -- the text did not change: only a repaint from the cached ranges, at once, so a jump never shows
        -- raw table text for the length of the debounce
        M.render(bufnr)
      else
        schedule()
      end
    end,
    desc = "[markdown.nvim] table truncate: repaint the visible lines",
  })
  api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      set_conceallevel(bufnr, true)
      schedule()
    end,
    desc = "[markdown.nvim] table truncate: conceallevel for a new window",
  })
  api.nvim_create_autocmd("BufReadPost", {
    group = group,
    buffer = bufnr,
    callback = function()
      rendered_at[bufnr] = nil
      schedule()
    end,
    desc = "[markdown.nvim] table truncate: re-render after :edit!",
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      S[bufnr] = nil
      rendered_at[bufnr] = nil
      computed[bufnr] = nil
      pcall(api.nvim_del_augroup_by_id, group)
    end,
  })
  set_conceallevel(bufnr, true)
  M.render(bufnr)
  local rr = package.loaded["markdown.core.render"]
  if rr then rr.grid_changed(bufnr) end
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
  local rr = package.loaded["markdown.core.render"]
  if rr then rr.grid_changed(bufnr) end
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
