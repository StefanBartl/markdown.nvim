---@module 'markdown.core.table_render'
---@brief Display-only grid rendering of GFM tables that fits the window.
---@description
--- The buffer text is never touched. Every table row is hidden with the extmark
--- option `conceal_lines` (Neovim >= 0.11; needs `conceallevel` >= 2 in the
--- window, set while the render is on and restored after) and the grid is shown
--- as virtual lines. A concealed line shows no virtual lines of its own, so the
--- grid hangs on a line that stays visible: the row under the cursor, or the
--- line right after (before) the table. (Inline virtual text would leave blank
--- screen rows between the table rows when `wrap` is on.)
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
---   M.to_lines(src, opts)        – pure: the table as plain text lines
---   M.render(bufnr, force)       – apply the extmarks for the whole buffer
---   M.clear(bufnr)               – remove them
---   M.enable/disable/toggle(bufnr)

local lib_table = require("lib.nvim.markdown.table")
local table_wrap = require("markdown.core.table_wrap")
local fences = require("markdown.util.fence")

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
  -- the width of the whole piece is measured, not summed per character: a
  -- variation selector or a joiner changes the width of what came before
  local out, cur = {}, ""
  for i = 0, vim.fn.strchars(s, true) - 1 do
    local ch = vim.fn.strcharpart(s, i, 1, true)
    if cur ~= "" and dw(cur .. ch) > w and dw(ch) > 0 then
      out[#out + 1] = cur
      cur = ""
    end
    cur = cur .. ch
  end
  out[#out + 1] = cur
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
    -- only the first separator-looking line is the delimiter row; a later `| - | - |` is data.
    -- A header of dashes right above the delimiter row is the header (same rule as lib.nvim's
    -- markdown.table.parse): when lines 1 and 2 both look like a separator, line 2 is it.
    local dash_header = i == 1 and lib_table.is_separator_line(src[2])
    if not seen_sep and not dash_header and lib_table.is_separator_line(line) then
      rows[i] = { kind = "sep", height = 1 }
      seen_sep = true
      for c, spec in ipairs((lib_table.split_cells(line))) do
        local l, r = spec:sub(1, 1) == ":", spec:sub(-1) == ":"
        aligns[c] = (l and r) and "center" or (r and "right" or "left")
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
      local free = math.max(0, model.widths[c] - dw(text))
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

---Pure: the table as plain text lines -- the same grid the buffer render
---draws, for places that show text (a picker preview, a float). Natural width,
---or fitted to `opts.avail` columns. A table that cannot be laid out comes back
---as its source lines. Unset options come from the `table.render` config.
---@param src string[]
---@param opts? { avail?: integer, pad?: integer, min_width?: integer, border?: string, row_separator?: boolean|"auto" }
---@return string[]
function M.to_lines(src, opts)
  local o = vim.tbl_extend("force", cfg(), opts or {})
  local model = M.layout(src, { avail = opts and opts.avail, pad = o.pad, min_width = o.min_width })
  if not model then return vim.deepcopy(src) end
  local style = M.style(o, model)
  local function join(chunks)
    local t = {}
    for _, c in ipairs(chunks) do
      t[#t + 1] = c[1]
    end
    return table.concat(t)
  end
  local out = { join(M.border(model, "top", style)) }
  local last = #model.rows
  for i = 1, last do
    for _, line in ipairs(M.row_lines(model, i, style)) do
      out[#out + 1] = join(line)
    end
    if style.row_separator and model.rows[i].kind == "body" and i < last then
      out[#out + 1] = join(M.border(model, "mid", style))
    end
  end
  out[#out + 1] = join(M.border(model, "bottom", style))
  return out
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
    if not fence then
      local c, n = fences.open(line)
      if c then
        flush(i - 1)
        fence = { c = c, n = n }
      end
    elseif fences.close(line, fence.c, fence.n) then
      fence = nil
      seg_start = i + 1
    end
  end
  if not fence then flush(#lines) end
  return found
end

---@class Mkdn.TableRenderTable
---@field first integer
---@field last integer
---@field model Mkdn.TableRenderModel
---@field key string  # text and width options the model was made from
---@field rawkey string  # which rows show their text
---@field drawn Mkdn.TableRenderDrawn

---@class Mkdn.TableRenderState
---@field group integer
---@field pending boolean
---@field tick integer  # changedtick of the last full render
---@field stamp string  # changedtick, width and config of the last render
---@field look string  # width and config of the last render (without the tick)
---@field tables Mkdn.TableRenderTable[]
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
---Display width of the whitespace in front of a table line (a tab counts as
---what it displays as).
---@param line string
---@return integer
local function indent_width(line) return dw(line:match("^%s*")) end

---@type table<string, integer>
local hl_ids = {}

---@internal
---@param name string
---@return integer
local function hl_id(name)
  local id = hl_ids[name]
  if not id then
    id = api.nvim_get_hl_id_by_name(name)
    hl_ids[name] = id
  end
  return id
end

---@internal
---Which rows of a table show their real text: the cursor row (every row with
---`cursor = "table"` and the cursor somewhere in the table). A buffer that is
---only this table has nothing to hang the grid on, so its last row stays text.
---@param first integer
---@param nrows integer
---@param nlines integer  # lines of the buffer
---@param cursor table<integer, boolean>
---@param o table
---@return boolean[] raw, string key  # key: the raw row numbers, "" when none
local function raw_rows(first, nrows, nlines, cursor, o)
  local whole = false
  if o.cursor == "table" then
    for i = 1, nrows do
      if cursor[first + i - 1] then whole = true end
    end
  end
  local raw, key, any = {}, {}, false
  for i = 1, nrows do
    raw[i] = whole or cursor[first + i - 1] or false
    any = any or raw[i]
  end
  if not any and first == 1 and first + nrows - 1 >= nlines then raw[nrows] = true end
  for i = 1, nrows do
    if raw[i] then key[#key + 1] = i end
  end
  return raw, table.concat(key, ",")
end

---@class Mkdn.TableRenderDrawn
---@field ids integer[]  # every extmark of the table
---@field probe integer  # a mark on the first line: where the table is now
---@field anchor? { id: integer, rel: integer }  # the grid hangs on a line outside the table
---@field top_fill? integer  # virtual lines above buffer line 1 (the first row shows its text there)

---@internal
---Draws one table. `tlines` are its source lines, `first` the 1-based number of
---the first, `raw[i]` says that row `i` shows its text. Rows that are not raw
---get `conceal_lines`; the virtual lines of the stretches between the raw rows
---hang on a raw row, or on the line after / before the table (see the module
---header).
---@param bufnr integer
---@param first integer
---@param tlines string[]
---@param model Mkdn.TableRenderModel
---@param raw boolean[]
---@param o table
---@return Mkdn.TableRenderDrawn
local function draw(bufnr, first, tlines, model, raw, o)
  local ids = {}
  ---@param row integer  # 0-based
  ---@param opts table
  ---@return integer|nil
  local function mark(row, opts)
    local ok, id = pcall(api.nvim_buf_set_extmark, bufnr, NS, row, 0, opts)
    if ok then ids[#ids + 1] = id end
    return ok and id or nil
  end
  local probe = mark(first - 1, {})
  local style = M.style(o, model)
  local nrows = #model.rows
  local last = first + nrows - 1
  local nlines = api.nvim_buf_line_count(bufnr)
  local indent = { { (" "):rep(indent_width(tlines[1])) } }
  if indent[1][1] == "" then indent = {} end

  -- Group ids instead of names: Neovim looks a name up per chunk, which dominates
  -- the time of a buffer with thousands of rows.
  ---@param chunks table[]
  local function vline(chunks)
    local out = vim.list_slice(indent, 1, #indent)
    for _, ch in ipairs(chunks) do
      out[#out + 1] = ch[2] and { ch[1], hl_id(ch[2]) } or ch
    end
    return out
  end

  -- segs[0]: before the first raw row (starts with the top border); segs[k]: after the k-th
  local segs, slots = { [0] = { vline(M.border(model, "top", style)) } }, {}
  local cur = segs[0]
  for i = 1, nrows do
    if raw[i] then
      slots[#slots + 1] = first + i - 1
      cur = {}
      segs[#slots] = cur
    else
      for _, l in ipairs(M.row_lines(model, i, style)) do
        cur[#cur + 1] = vline(l)
      end
      mark(first + i - 2, { conceal_lines = "" })
    end
    if style.row_separator and model.rows[i].kind == "body" and i < nrows then
      cur[#cur + 1] = vline(M.border(model, "mid", style))
    end
  end
  cur[#cur + 1] = vline(M.border(model, "bottom", style))

  ---@return integer|nil
  local function hang(lnum, lines, above)
    return mark(lnum - 1, { virt_lines = lines, virt_lines_above = above })
  end
  local anchor
  if #slots > 0 then
    hang(slots[1], segs[0], true)
    for k = 1, #slots do
      if #segs[k] > 0 then hang(slots[k], segs[k], false) end
    end
  else
    local lnum = last < nlines and last + 1 or first - 1
    local id = hang(lnum, segs[0], last < nlines)
    if id then anchor = { id = id, rel = lnum - first } end
  end
  local top_fill = (#slots > 0 and slots[1] == 1) and #segs[0] or nil
  return { ids = ids, probe = probe, anchor = anchor, top_fill = top_fill }
end

---@type table<string, Mkdn.TableRenderModel|false>
local models, n_models = {}, 0

---@internal
---`M.layout` of a table, remembered by `key` (its text and the width options):
---an edit elsewhere in the buffer, a cursor move or a resize back to a known
---width does not lay out every table again.
---@param key string
---@param tlines string[]
---@param avail integer
---@param o table
---@return Mkdn.TableRenderModel|nil
local function layout_cached(key, tlines, avail, o)
  local hit = models[key]
  if hit == nil then
    if n_models >= 400 then
      models, n_models = {}, 0
    end
    hit = M.layout(tlines, { avail = avail, pad = o.pad, min_width = o.min_width }) or false
    models[key], n_models = hit, n_models + 1
  end
  return hit or nil
end

---@param bufnr integer
function M.clear(bufnr)
  if api.nvim_buf_is_valid(bufnr) then api.nvim_buf_clear_namespace(bufnr, NS, 0, -1) end
  if S[bufnr] then
    S[bufnr].stamp, S[bufnr].look, S[bufnr].tables = "", "", {}
  end
end

---@internal
---@param bufnr integer
---@param t Mkdn.TableRenderTable
local function erase(bufnr, t)
  for _, id in ipairs(t.drawn.ids) do
    pcall(api.nvim_buf_del_extmark, bufnr, NS, id)
  end
end

---@internal
---1-based line where the extmark `id` sits now, nil when it is gone.
---@param bufnr integer
---@param id integer|nil
---@return integer|nil
local function line_of(bufnr, id)
  if not id then return nil end
  local pos = api.nvim_buf_get_extmark_by_id(bufnr, NS, id, {})
  return pos[1] and pos[1] + 1 or nil
end

---@internal
---Whether every mark of `ids` still sits on a line between `from` and `to` (1-based).
---@param bufnr integer
---@param ids integer[]
---@param from integer
---@param to integer
---@return boolean
local function marks_within(bufnr, ids, from, to)
  for _, id in ipairs(ids) do
    local at = line_of(bufnr, id)
    if not at or at < from or at > to then return false end
  end
  return true
end

---Neovim draws no virtual line above buffer line 1 unless the window is scrolled to
---`topfill`. When the table starts on line 1 and its first row shows its text, the top
---border sits there: show it in every window that is at the top of the buffer.
---@param bufnr integer
function M.sync_topfill(bufnr)
  local st = S[bufnr]
  if not st then return end
  local want = 0
  for _, t in ipairs(st.tables) do
    if t.first == 1 and t.drawn.top_fill then want = t.drawn.top_fill end
  end
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    api.nvim_win_call(win, function()
      local v = vim.fn.winsaveview()
      if v.topline == 1 and v.topfill ~= want then
        v.topfill = want
        vim.fn.winrestview(v)
      end
    end)
  end
end

---Apply the rendering for the whole buffer. A no-op while nothing changed
---(text, width, config), unless `force`. A table whose text, width and
---cursor state are the same as at the last render is left as it is (its
---extmarks followed the edit), only the others are drawn again.
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
  local look = ("%d:%s"):format(avail, vim.inspect(o)) -- what a drawing depends on besides the text
  local stamp = tick .. ":" .. look
  if st.stamp == stamp and not force then return 0 end

  -- tables of the last render, by the line they are on now
  local old = {}
  if force or st.look ~= look then
    api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  else
    for _, t in ipairs(st.tables) do
      local at = line_of(bufnr, t.drawn.probe)
      if at and not old[at] then old[at] = t end
    end
  end
  st.stamp, st.look, st.tick, st.cursor = stamp, look, tick, cursor_rows(bufnr)

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local nlines = #lines
  local tables = {}
  for _, f in ipairs(find_tables(lines)) do
    local tlines = vim.list_slice(lines, f.first, f.last)
    local width = avail - indent_width(tlines[1])
    local key = ("%d:%d:%d\n%s"):format(width, o.pad, o.min_width, table.concat(tlines, "\n"))
    local raw, rawkey = raw_rows(f.first, #tlines, nlines, st.cursor, o)

    local prev = old[f.first]
    local same = prev
      and prev.key == key
      and marks_within(bufnr, prev.drawn.ids, f.first - 1, f.last + 1)
      and prev.rawkey == rawkey
      and (
        not prev.drawn.anchor
        or line_of(bufnr, prev.drawn.anchor.id) == f.first + prev.drawn.anchor.rel
      )
    if same then
      old[f.first] = nil
      prev.first, prev.last = f.first, f.last
      tables[#tables + 1] = prev
    else
      local model = layout_cached(key, tlines, width, o)
      if model then
        tables[#tables + 1] = {
          first = f.first,
          last = f.last,
          model = model,
          key = key,
          rawkey = rawkey,
          drawn = draw(bufnr, f.first, tlines, model, raw, o),
        }
      end
    end
  end
  -- Whatever is not part of a kept or new table goes: tables that were not found again, and
  -- marks undo brought back or whose probes collapsed onto one line.
  local keep = {}
  for _, t in ipairs(tables) do
    for _, id in ipairs(t.drawn.ids) do
      keep[id] = true
    end
  end
  for _, m in ipairs(api.nvim_buf_get_extmarks(bufnr, NS, 0, -1, {})) do
    if not keep[m[1]] then pcall(api.nvim_buf_del_extmark, bufnr, NS, m[1]) end
  end
  st.tables = tables
  M.sync_topfill(bufnr)
  return #tables
end

---@internal
---The cursor moved to another row: only the tables it left and entered are redrawn.
---@param bufnr integer
local function on_cursor(bufnr)
  local st = S[bufnr]
  if not st then return end
  M.sync_topfill(bufnr)
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
  local nlines = api.nvim_buf_line_count(bufnr)
  for _, t in ipairs(st.tables) do
    local touched = false
    for l in pairs(now) do
      if l >= t.first and l <= t.last then touched = true end
    end
    for l in pairs(old) do
      if l >= t.first and l <= t.last then touched = true end
    end
    if touched then
      local raw, rawkey = raw_rows(t.first, #t.model.rows, nlines, now, o)
      if rawkey ~= t.rawkey then
        erase(bufnr, t)
        local tlines = api.nvim_buf_get_lines(bufnr, t.first - 1, t.last, false)
        t.drawn = draw(bufnr, t.first, tlines, t.model, raw, o)
        M.sync_topfill(bufnr)
        t.rawkey = rawkey
      end
    end
  end
end

---@internal
---@param bufnr integer
---@param on boolean
local function set_conceallevel(bufnr, on)
  local guard = require("markdown.core.conceal_guard")
  if on then
    guard.apply("render", bufnr)
  else
    guard.restore("render", bufnr)
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
function M.is_enabled(bufnr)
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  return S[bufnr] ~= nil
end

---@param bufnr? integer
function M.enable(bufnr)
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  if S[bufnr] then return end
  if vim.fn.has("nvim-0.11") ~= 1 then
    vim.notify(
      "markdown.nvim: table render needs Neovim >= 0.11 (conceal_lines)",
      vim.log.levels.WARN
    )
    return
  end
  -- Both hide table text with conceal: the last one switched on wins.
  local tt = package.loaded["markdown.core.table_truncate"]
  if tt and tt.is_enabled(bufnr) then tt.disable(bufnr) end

  ensure_global()
  setup_highlights()
  local group = api.nvim_create_augroup("MarkdownNvimTableRenderBuf" .. bufnr, { clear = true })
  S[bufnr] =
    { group = group, pending = false, tick = -1, stamp = "", look = "", tables = {}, cursor = {} }

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
  api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      set_conceallevel(bufnr, true)
      schedule(bufnr)
    end,
    desc = "[markdown.nvim] table render: conceallevel for a new window",
  })
  api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      vim.schedule(function()
        if S[bufnr] and api.nvim_buf_is_valid(bufnr) then set_conceallevel(bufnr, true) end
      end)
    end,
    desc = "[markdown.nvim] table render: give a window that left its conceallevel back",
  })
  api.nvim_create_autocmd("BufReadPost", {
    group = group,
    buffer = bufnr,
    callback = function()
      if S[bufnr] then
        S[bufnr].stamp, S[bufnr].look = "", ""
      end
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
  local rr = package.loaded["markdown.core.render"]
  if rr then rr.grid_changed(bufnr) end
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
  local rr = package.loaded["markdown.core.render"]
  if rr then rr.grid_changed(bufnr) end
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
