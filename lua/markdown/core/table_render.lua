---@module 'markdown.core.table_render'
---@brief Display-only grid rendering of GFM tables that fits the window.
---@description
--- The buffer text is never touched. Every table row is hidden with extmark
--- `conceal` (needs `conceallevel` >= 2 in the window, set while the render is
--- on and restored after) and shown again as inline virtual text:
---
---   * columns are as wide as their longest cell, no more -- the padding the
---     formatter wrote for one huge cell in another row is gone;
---   * when the table is wider than the window the columns share the space and
---     the cells wrap onto extra virtual lines;
---   * a window resize re-computes the layout (debounced).
---
--- The row under the cursor shows its real text (`cursor = "row"`, or the whole
--- table with `cursor = "table"`), so it can be edited as usual.
---
---   M.layout(src, opts)          – pure: widths, aligns and wrapped cells of one table
---   M.row_lines(model, i, style) – pure: virtual-text chunks of source row `i`
---   M.border(model, kind, style) – pure: top / mid / bottom border chunks
---   M.render(bufnr, force)       – apply the extmarks for the whole buffer
---   M.clear(bufnr)               – remove them
---   M.enable/disable/toggle(bufnr)

local lib_table = require("lib.nvim.markdown.table")
local table_wrap = require("markdown.core.table_wrap")

local M = {}

local api = vim.api
local NS = api.nvim_create_namespace("markdown_table_render")

local MAX_ROWS = 3000
local WORD_CAP = 14 -- a column is not kept wider than this just for one long word

M.DEFAULTS = {
  border = "single", -- "single" | "rounded" | "ascii"
  cursor = "row", -- "row" | "table": what shows its real text under the cursor
  pad = 1, -- spaces left and right of a cell's text
  min_width = 6, -- narrowest a column is squeezed to before the table overflows
  max_width = nil, -- cap on the table width, nil = the window width
  row_separator = "auto", -- true | false | "auto" (only when a row wraps)
  debounce_ms = 80,
}

local CHARS = {
  single = {
    v = "│",
    h = "─",
    tl = "┌",
    tm = "┬",
    tr = "┐",
    ml = "├",
    mm = "┼",
    mr = "┤",
    bl = "└",
    bm = "┴",
    br = "┘",
  },
  rounded = {
    v = "│",
    h = "─",
    tl = "╭",
    tm = "┬",
    tr = "╮",
    ml = "├",
    mm = "┼",
    mr = "┤",
    bl = "╰",
    bm = "┴",
    br = "╯",
  },
  ascii = {
    v = "|",
    h = "-",
    tl = "+",
    tm = "+",
    tr = "+",
    ml = "+",
    mm = "+",
    mr = "+",
    bl = "+",
    bm = "+",
    br = "+",
  },
}

local HL_BORDER, HL_HEAD, HL_CODE = "MarkdownTableBorder", "MarkdownTableHead", "MarkdownTableCode"

---@internal
local function setup_highlights()
  api.nvim_set_hl(0, HL_BORDER, { link = "Comment", default = true })
  api.nvim_set_hl(0, HL_HEAD, { link = "Title", default = true })
  api.nvim_set_hl(0, HL_CODE, { link = "@markup.raw.markdown_inline", default = true })
end

---@internal
---@return table
local function cfg()
  local ok, config = pcall(require, "markdown.config")
  local t = (ok and config.get().table and config.get().table.render) or {}
  return vim.tbl_extend("force", M.DEFAULTS, t)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Pure layout
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---@param s string
---@return integer
local function dw(s) return vim.fn.strdisplaywidth(s) end

---@internal
---Cell text -> its forced lines (`<br>` breaks), with `\|` shown as `|`.
---@param text string
---@return string[]
local function pieces(text)
  local s = text:gsub("\\|", "|"):gsub("<[bB][rR]%s*/?>", "\n")
  local out = {}
  for part in (s .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = vim.trim(part)
  end
  return out
end

---@internal
---Splits `s` into pieces of at most `w` display columns (a last resort for a
---token no whitespace break can shorten).
---@param s string
---@param w integer
---@return string[]
local function hard_split(s, w)
  if dw(s) <= w then return { s } end
  local out, cur, cw = {}, {}, 0
  for i = 0, vim.fn.strchars(s, true) - 1 do
    local ch = vim.fn.strcharpart(s, i, 1, true)
    local chw = dw(ch)
    if cw + chw > w and cw > 0 then
      out[#out + 1] = table.concat(cur)
      cur, cw = {}, 0
    end
    cur[#cur + 1] = ch
    cw = cw + chw
  end
  out[#out + 1] = table.concat(cur)
  return out
end

---@internal
---@param text string
---@param w integer
---@return string[]
local function wrap_text(text, w)
  local out = {}
  for _, piece in ipairs(pieces(text)) do
    for _, line in ipairs(table_wrap.wrap_cell(piece, w)) do
      vim.list_extend(out, hard_split(line, w))
    end
  end
  if #out == 0 then out[1] = "" end
  return out
end

---@internal
---Column widths summing to at most `budget`. Every column starts at its
---minimum; what is left is handed out in proportion to how far a column is
---still below its natural width, so all columns shrink by the same fraction of
---their excess. `nil` when the minimums alone do not fit.
---@param natural integer[]
---@param budget integer
---@param mins integer[]  # per column, already <= natural
---@return integer[]|nil
local function fit(natural, budget, mins)
  local n, total, used = #natural, 0, 0
  for c = 1, n do
    total = total + natural[c]
  end
  if total <= budget then return vim.deepcopy(natural) end
  local widths = {}
  for c = 1, n do
    widths[c] = mins[c]
    used = used + mins[c]
  end
  if used > budget then return nil end

  while used < budget do
    local deficit = 0
    for c = 1, n do
      deficit = deficit + natural[c] - widths[c]
    end
    if deficit == 0 then break end
    local extra, given = budget - used, 0
    for c = 1, n do
      local add =
        math.min(natural[c] - widths[c], math.floor(extra * (natural[c] - widths[c]) / deficit))
      widths[c] = widths[c] + add
      given = given + add
    end
    if given == 0 then -- rounding swallowed it: one column at a time, the most squeezed first
      local pick
      for c = 1, n do
        if
          natural[c] > widths[c]
          and (not pick or natural[c] - widths[c] > natural[pick] - widths[pick])
        then
          pick = c
        end
      end
      widths[pick] = widths[pick] + 1
      given = 1
    end
    used = used + given
  end
  return widths
end

---@class Mkdn.TableRenderRow
---@field kind "head"|"sep"|"body"
---@field cells? string[][]  # per column the wrapped lines of the cell
---@field height integer

---@class Mkdn.TableRenderModel
---@field n integer  # column count
---@field widths integer[]
---@field aligns ("left"|"center"|"right")[]
---@field pad integer
---@field rows Mkdn.TableRenderRow[]  # one per source line
---@field wrapped boolean  # some row spans more than one line
---@field width integer  # total display width of a rendered line

---Pure: the layout of one table (`src` = its source lines).
---@param src string[]
---@param opts? { avail?: integer, pad?: integer, min_width?: integer }
---@return Mkdn.TableRenderModel|nil model  # nil when the table does not fit even squeezed
function M.layout(src, opts)
  opts = opts or {}
  local pad = opts.pad or M.DEFAULTS.pad
  local rows, n, aligns, seen_sep = {}, 0, {}, false
  for i, line in ipairs(src) do
    if lib_table.is_separator_line(line) then
      rows[i] = { kind = "sep", height = 1 }
      if not seen_sep then
        seen_sep = true
        for c, spec in ipairs((lib_table.split_cells(line))) do
          local l, r = spec:sub(1, 1) == ":", spec:sub(-1) == ":"
          aligns[c] = (l and r) and "center" or (r and "right" or "left")
        end
      end
    else
      local cells = lib_table.split_cells(line)
      rows[i] = { kind = seen_sep and "body" or "head", raw = cells, height = 1 }
      n = math.max(n, #cells)
    end
  end
  if n == 0 then return nil end

  local natural, longest = {}, {}
  for c = 1, n do
    natural[c], longest[c] = 1, 1
  end
  for _, row in pairs(rows) do
    if row.raw then
      for c, text in ipairs(row.raw) do
        for _, piece in ipairs(pieces(text)) do
          natural[c] = math.max(natural[c], dw(piece))
          for word in piece:gmatch("%S+") do
            longest[c] = math.max(longest[c], dw(word))
          end
        end
      end
    end
  end

  local widths = natural
  if opts.avail then
    local budget = opts.avail - (n + 1) - 2 * pad * n
    local minw = opts.min_width or M.DEFAULTS.min_width
    -- A column is squeezed to its longest word (at most WORD_CAP columns), so
    -- short columns are not broken mid-word; when that does not fit, to `minw`,
    -- and as a last resort to 3.
    local function mins(floor, cap)
      local out = {}
      for c = 1, n do
        out[c] = math.min(natural[c], math.max(floor, cap and math.min(longest[c], cap) or 0))
      end
      return out
    end
    widths = fit(natural, budget, mins(minw, WORD_CAP))
      or fit(natural, budget, mins(minw))
      or fit(natural, budget, mins(3))
    if not widths then return nil end
  end

  local wrapped = false
  for _, row in pairs(rows) do
    if row.raw then
      row.cells = {}
      for c = 1, n do
        row.cells[c] = wrap_text(row.raw[c] or "", widths[c])
        row.height = math.max(row.height, #row.cells[c])
      end
      row.raw = nil
      wrapped = wrapped or row.height > 1
    end
  end

  local width = n + 1
  for c = 1, n do
    aligns[c] = aligns[c] or "left"
    width = width + widths[c] + 2 * pad
  end
  return {
    n = n,
    widths = widths,
    aligns = aligns,
    pad = pad,
    rows = rows,
    wrapped = wrapped,
    width = width,
  }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Pure chunk building
-- ─────────────────────────────────────────────────────────────────────────────

---@class Mkdn.TableRenderStyle
---@field chars table<string, string>
---@field row_separator boolean

---@param opts? { border?: string, row_separator?: boolean|"auto" }
---@param model? Mkdn.TableRenderModel
---@return Mkdn.TableRenderStyle
function M.style(opts, model)
  opts = opts or {}
  local rs = opts.row_separator
  if rs == nil then rs = M.DEFAULTS.row_separator end
  if rs == "auto" then rs = model ~= nil and model.wrapped end
  return { chars = CHARS[opts.border or M.DEFAULTS.border] or CHARS.single, row_separator = rs }
end

---@internal
---Appends the chunks of `text`, `code spans` in the code highlight.
---@param out table[]
---@param text string
---@param hl string|nil
local function text_chunks(out, text, hl)
  local pos = 1
  while pos <= #text do
    local s, e = text:find("`[^`]+`", pos)
    if not s then break end
    if s > pos then out[#out + 1] = { text:sub(pos, s - 1), hl } end
    out[#out + 1] = { text:sub(s, e), HL_CODE }
    pos = e + 1
  end
  if pos <= #text then out[#out + 1] = { text:sub(pos), hl } end
end

---Pure: the border line `kind` ("top" | "mid" | "bottom") as chunks.
---@param model Mkdn.TableRenderModel
---@param kind "top"|"mid"|"bottom"
---@param style Mkdn.TableRenderStyle
---@return table[]
function M.border(model, kind, style)
  local ch = style.chars
  local l, m, r
  if kind == "top" then
    l, m, r = ch.tl, ch.tm, ch.tr
  elseif kind == "bottom" then
    l, m, r = ch.bl, ch.bm, ch.br
  else
    l, m, r = ch.ml, ch.mm, ch.mr
  end
  local parts = { l }
  for c = 1, model.n do
    parts[#parts + 1] = ch.h:rep(model.widths[c] + 2 * model.pad)
    parts[#parts + 1] = c < model.n and m or r
  end
  return { { table.concat(parts), HL_BORDER } }
end

---Pure: source row `i` as virtual lines, each a list of `{ text, hl }` chunks.
---A separator row is the mid border; a wrapped row yields several lines.
---@param model Mkdn.TableRenderModel
---@param i integer
---@param style Mkdn.TableRenderStyle
---@return table[][]
function M.row_lines(model, i, style)
  local row = model.rows[i]
  if row.kind == "sep" then return { M.border(model, "mid", style) } end
  local ch, pad = style.chars, model.pad
  local text_hl = row.kind == "head" and HL_HEAD or nil
  local lines = {}
  for k = 1, row.height do
    local out = { { ch.v, HL_BORDER } }
    for c = 1, model.n do
      local text = row.cells[c][k] or ""
      local free = model.widths[c] - dw(text)
      local align = model.aligns[c]
      local lpad = align == "right" and free or (align == "center" and math.floor(free / 2) or 0)
      out[#out + 1] = { (" "):rep(pad + lpad) }
      text_chunks(out, text, text_hl)
      out[#out + 1] = { (" "):rep(pad + free - lpad) }
      out[#out + 1] = { ch.v, HL_BORDER }
    end
    lines[k] = out
  end
  return lines
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Buffer rendering
-- ─────────────────────────────────────────────────────────────────────────────

---@internal
---Table line ranges of `lines`, outside fenced code blocks.
---@param lines string[]
---@return { first: integer, last: integer }[]
local function find_tables(lines)
  local found = {}
  local seg_start, fence = 1, nil
  local function flush(seg_end)
    if seg_end < seg_start then return end
    local seg = vim.list_slice(lines, seg_start, seg_end)
    for _, t in ipairs(lib_table.parse(seg)) do
      if t.end_line - t.start_line < MAX_ROWS then
        found[#found + 1] = {
          first = seg_start + t.start_line - 1,
          last = seg_start + t.end_line - 1,
        }
      end
    end
  end
  for i, line in ipairs(lines) do
    local mark = line:match("^%s*(```+)") or line:match("^%s*(~~~+)")
    if mark then
      if not fence then
        flush(i - 1)
        fence = { c = mark:sub(1, 1), n = #mark }
      elseif mark:sub(1, 1) == fence.c and #mark >= fence.n and line:match("^%s*%S+%s*$") then
        fence = nil
        seg_start = i + 1
      end
    end
  end
  if not fence then flush(#lines) end
  return found
end

---@class Mkdn.TableRenderState
---@field group integer
---@field pending boolean
---@field tick integer  # changedtick of the last full render
---@field stamp string
---@field tables { first: integer, last: integer, model: Mkdn.TableRenderModel }[]
---@field cursor table<integer, boolean>

---@type table<integer, Mkdn.TableRenderState>
local S = {}

---@internal
---@param bufnr integer
---@return table<integer, boolean>
local function cursor_rows(bufnr)
  local set = {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    set[api.nvim_win_get_cursor(win)[1]] = true
  end
  return set
end

---@internal
---Display width the tables may use: the narrowest window showing `bufnr`.
---@param bufnr integer
---@param o table
---@return integer|nil
local function avail_width(bufnr, o)
  local w
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    local info = vim.fn.getwininfo(win)[1]
    local aw = info.width - info.textoff
    w = w and math.min(w, aw) or aw
  end
  if w and o.max_width then w = math.min(w, o.max_width) end
  return w
end

---@internal
---Draws one table. `tlines` are its source lines, `first` the 1-based number of the first.
---@param bufnr integer
---@param first integer
---@param tlines string[]
---@param model Mkdn.TableRenderModel
---@param cursor table<integer, boolean>
---@param o table
local function draw(bufnr, first, tlines, model, cursor, o)
  local style = M.style(o, model)
  local nrows = #model.rows
  local raw_all = false
  if o.cursor == "table" then
    for i = 1, nrows do
      if cursor[first + i - 1] then raw_all = true end
    end
  end

  pcall(api.nvim_buf_set_extmark, bufnr, NS, first - 1, 0, {
    virt_lines = { M.border(model, "top", style) },
    virt_lines_above = true,
  })

  for i = 1, nrows do
    local lnum = first + i - 1
    local line = tlines[i]
    local indent = #line:match("^%s*")
    local rendered = not raw_all and not cursor[lnum]
    local vlines, extra = {}, {}
    if rendered then
      local phys = M.row_lines(model, i, style)
      for k = 2, #phys do
        table.insert(phys[k], 1, { (" "):rep(indent) })
        vlines[#vlines + 1] = phys[k]
      end
      extra = phys[1]
      if style.row_separator and model.rows[i].kind == "body" and i < nrows then
        vlines[#vlines + 1] = M.border(model, "mid", style)
      end
    end
    if i == nrows then vlines[#vlines + 1] = M.border(model, "bottom", style) end
    if indent > 0 then
      for _, vl in ipairs(vlines) do
        if vl[1] and vl[1][1] ~= (" "):rep(indent) then
          table.insert(vl, 1, { (" "):rep(indent) })
        end
      end
    end

    local mark = {}
    if rendered then
      mark.end_row = lnum - 1
      mark.end_col = #line
      mark.conceal = ""
      mark.virt_text = extra
      mark.virt_text_pos = "inline"
    end
    if #vlines > 0 then mark.virt_lines = vlines end
    if rendered or #vlines > 0 then
      pcall(api.nvim_buf_set_extmark, bufnr, NS, lnum - 1, rendered and indent or 0, mark)
    end
  end
end

---@param bufnr integer
function M.clear(bufnr)
  if api.nvim_buf_is_valid(bufnr) then api.nvim_buf_clear_namespace(bufnr, NS, 0, -1) end
  if S[bufnr] then
    S[bufnr].stamp, S[bufnr].tables = "", {}
  end
end

---Apply the rendering for the whole buffer. A no-op while nothing changed
---(text, width, config), unless `force`.
---@param bufnr integer
---@param force? boolean
---@return integer count  # tables drawn
function M.render(bufnr, force)
  local st = S[bufnr]
  if not st or not api.nvim_buf_is_valid(bufnr) then return 0 end
  local o = cfg()
  local avail = avail_width(bufnr, o)
  if not avail then return 0 end -- not shown anywhere: BufWinEnter renders it
  local tick = api.nvim_buf_get_changedtick(bufnr)
  local stamp = ("%d:%d:%s"):format(tick, avail, vim.inspect(o))
  if st.stamp == stamp and not force then return 0 end

  api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  st.stamp, st.tick, st.tables, st.cursor = stamp, tick, {}, cursor_rows(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, t in ipairs(find_tables(lines)) do
    local tlines = vim.list_slice(lines, t.first, t.last)
    local model = M.layout(tlines, { avail = avail, pad = o.pad, min_width = o.min_width })
    if model then
      st.tables[#st.tables + 1] = { first = t.first, last = t.last, model = model }
      draw(bufnr, t.first, tlines, model, st.cursor, o)
    end
  end
  return #st.tables
end

---@internal
---The cursor moved to another row: only the tables it left and entered are redrawn.
---@param bufnr integer
local function on_cursor(bufnr)
  local st = S[bufnr]
  if not st then return end
  local now = cursor_rows(bufnr)
  local old = st.cursor or {}
  local same = true
  for l in pairs(now) do
    if not old[l] then same = false end
  end
  for l in pairs(old) do
    if not now[l] then same = false end
  end
  if same then return end
  st.cursor = now
  if st.tick ~= api.nvim_buf_get_changedtick(bufnr) then return end -- the text debounce redraws
  local o = cfg()
  for _, t in ipairs(st.tables) do
    local touched = false
    for l in pairs(now) do
      if l >= t.first and l <= t.last then touched = true end
    end
    for l in pairs(old) do
      if l >= t.first and l <= t.last then touched = true end
    end
    if touched then
      api.nvim_buf_clear_namespace(bufnr, NS, t.first - 1, t.last)
      draw(
        bufnr,
        t.first,
        api.nvim_buf_get_lines(bufnr, t.first - 1, t.last, false),
        t.model,
        now,
        o
      )
    end
  end
end

---@internal
---@param bufnr integer
---@param on boolean
local function set_conceallevel(bufnr, on)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if on then
      local cl = api.nvim_get_option_value("conceallevel", { win = win })
      if vim.w[win].mkdn_render_cl == nil then vim.w[win].mkdn_render_cl = cl end
      if cl < 2 then
        api.nvim_set_option_value("conceallevel", 2, { scope = "local", win = win })
      end
    elseif vim.w[win].mkdn_render_cl ~= nil then
      api.nvim_set_option_value(
        "conceallevel",
        vim.w[win].mkdn_render_cl,
        { scope = "local", win = win }
      )
      vim.w[win].mkdn_render_cl = nil
    end
  end
end

---@internal
---@param bufnr integer
---@param force? boolean
local function schedule(bufnr, force)
  local st = S[bufnr]
  if not st or st.pending then return end
  st.pending = true
  vim.defer_fn(function()
    if S[bufnr] then
      S[bufnr].pending = false
      M.render(bufnr, force)
    end
  end, cfg().debounce_ms)
end

local global_group

---@internal
---Events that are not buffer-local; created on the first `enable`, so requiring
---this module has no side effect.
local function ensure_global()
  if global_group then return end
  global_group = api.nvim_create_augroup("MarkdownNvimTableRender", { clear = true })
  api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = global_group,
    callback = function()
      for bufnr in pairs(S) do
        schedule(bufnr)
      end
    end,
    desc = "[markdown.nvim] table render: re-layout after a resize",
  })
  api.nvim_create_autocmd("OptionSet", {
    group = global_group,
    pattern = { "number", "relativenumber", "signcolumn", "foldcolumn", "numberwidth" },
    callback = function()
      for bufnr in pairs(S) do
        schedule(bufnr)
      end
    end,
    desc = "[markdown.nvim] table render: re-layout when the text area width changes",
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = global_group,
    callback = setup_highlights,
    desc = "[markdown.nvim] table render: re-link the highlight groups",
  })
end

---@param bufnr? integer
---@return boolean
function M.is_enabled(bufnr) return S[bufnr or api.nvim_get_current_buf()] ~= nil end

---@param bufnr? integer
function M.enable(bufnr)
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  if S[bufnr] then return end
  -- Both hide table text with conceal: the last one switched on wins.
  local tt = package.loaded["markdown.core.table_truncate"]
  if tt and tt.is_enabled(bufnr) then tt.disable(bufnr) end

  ensure_global()
  setup_highlights()
  local group = api.nvim_create_augroup("MarkdownNvimTableRenderBuf" .. bufnr, { clear = true })
  S[bufnr] = { group = group, pending = false, tick = -1, stamp = "", tables = {}, cursor = {} }

  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    buffer = bufnr,
    callback = function() schedule(bufnr) end,
    desc = "[markdown.nvim] table render: re-render",
  })
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = bufnr,
    callback = function() on_cursor(bufnr) end,
    desc = "[markdown.nvim] table render: show the cursor row as text",
  })
  api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = bufnr,
    callback = function()
      set_conceallevel(bufnr, true)
      schedule(bufnr)
    end,
    desc = "[markdown.nvim] table render: conceallevel for a new window",
  })
  api.nvim_create_autocmd("BufReadPost", {
    group = group,
    buffer = bufnr,
    callback = function()
      if S[bufnr] then S[bufnr].stamp = "" end
      schedule(bufnr)
    end,
    desc = "[markdown.nvim] table render: re-render after :edit!",
  })
  api.nvim_create_autocmd("BufWipeout", {
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
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  local st = S[bufnr]
  if not st then return end
  pcall(api.nvim_del_augroup_by_id, st.group)
  S[bufnr] = nil
  if api.nvim_buf_is_valid(bufnr) then api.nvim_buf_clear_namespace(bufnr, NS, 0, -1) end
  set_conceallevel(bufnr, false)
end

---@param bufnr? integer
---@return boolean now_enabled
function M.toggle(bufnr)
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  if M.is_enabled(bufnr) then
    M.disable(bufnr)
    return false
  end
  M.enable(bufnr)
  return true
end

return M
