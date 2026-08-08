---@module 'markdown.tableview.renderer'
local M = {}

local hl = vim.highlight
local api = vim.api
local window = require("lib.nvim.window")
local notify = require("markdown.util.notify").create("[markdown.tableview.renderer]")

local state = {
  buf = nil,
  win = nil,
  namespace = api.nvim_create_namespace("markdown_tableview"),

  -- Interactive resize/row-edit state (see M.resize_current_column /
  -- M.move_current_row / M.write_back): the currently-shown table(s), how
  -- they're laid out, and per-column width overrides. Reset on every fresh
  -- render_markdowntable / render_tables call; carried across an internal
  -- `rerender()` call so the overrides survive repeated Alt-key presses.
  tables        = nil, ---@type table[]|nil
  style         = nil, ---@type "markdown"|"box"|nil
  single        = nil, ---@type boolean|nil  true = render_markdowntable's own (unlabeled) layout
  opts          = nil,
  col_overrides = {},  ---@type table<integer, table<integer, integer>>  [table_idx][col_idx] = extra width
  -- [line_idx(0-indexed)] = { table_idx = integer, row_idx = integer }  (row_idx 0 = header)
  row_map       = nil, ---@type table<integer, { table_idx: integer, row_idx: integer }>|nil
}

local default_opts = {
  floating       = true,
  max_width_frac = 0.85,
  max_height_frac = 0.75,
  border         = "rounded",
  highlight = {
    header    = "Title",
    separator = "Comment",
    cell      = "Normal",
  },
}

local function merge(a, b)
  local out = {}
  for k, v in pairs(a) do out[k] = v end
  if b then for k, v in pairs(b) do out[k] = v end end
  return out
end

--- Screen-column width of `str`, not its byte length. Table cells routinely
--- contain multi-byte UTF-8 (German umlauts ü/ö/ä, em dashes —, ellipses …,
--- curly quotes „", arrows →, …), which are 2-3 bytes but occupy a single
--- screen column; padding by `#str` (byte length) over-pads such cells and
--- drifts the `|` column separators out of alignment across rows.
---@param str string
---@return integer
local function display_width(str)
  local ok, w = pcall(vim.fn.strdisplaywidth, str)
  return ok and w or #str
end

--- Every DISPLAY column (not byte column) at which a `|` or box-drawing `│`
--- cell divider occurs on `line`. Iterates by character (via strcharpart), not
--- byte, so a preceding multi-byte character (ü, —, …, „", →, …) advances the
--- running column by its actual screen width rather than its byte count.
---@param line string
---@return integer[]
local function divider_columns(line)
  local cols = {}
  local col = 0
  local nchars = vim.fn.strchars(line)
  for i = 0, nchars - 1 do
    local ch = vim.fn.strcharpart(line, i, 1)
    if ch == "|" or ch == "│" then
      cols[#cols + 1] = col
    end
    col = col + display_width(ch)
  end
  return cols
end

--- 1-based index of the cell `dispcol` (a 0-indexed DISPLAY column) falls
--- inside on `line`, or nil when `line` has fewer than two dividers or
--- `dispcol` is outside every cell (e.g. past the last divider).
---@param line string
---@param dispcol integer
---@return integer|nil
local function cell_index_at(line, dispcol)
  local cols = divider_columns(line)
  if #cols < 2 then return nil end
  for i = 1, #cols - 1 do
    if dispcol >= cols[i] and dispcol < cols[i + 1] then
      return i
    end
  end
  return nil
end

--- Convert a 0-indexed BYTE column (as `nvim_win_get_cursor` reports) to a
--- 0-indexed DISPLAY column on `line`.
---@param line string
---@param bytecol integer
---@return integer
local function byte_to_display_col(line, bytecol)
  return display_width(line:sub(1, bytecol))
end

--- Convert a 0-indexed DISPLAY column back to a 0-indexed BYTE column on
--- `line` (the inverse of byte_to_display_col), for restoring the cursor
--- after a rerender changes byte offsets (multi-byte content, width changes).
---@param line string
---@param dispcol integer
---@return integer
local function display_col_to_byte(line, dispcol)
  local col = 0
  local nchars = vim.fn.strchars(line)
  local bytepos = 0
  for i = 0, nchars - 1 do
    if col >= dispcol then return bytepos end
    local ch = vim.fn.strcharpart(line, i, 1)
    bytepos = bytepos + #ch
    col = col + display_width(ch)
  end
  return bytepos
end

local function table_to_matrix(mt)
  local matrix = {}
  local header_cells = {}
  for _, c in ipairs(mt.header.cells) do
    table.insert(header_cells, tostring(c.content or ""))
  end
  table.insert(matrix, header_cells)
  for _, r in ipairs(mt.rows) do
    local row_cells = {}
    for _, c in ipairs(r.cells) do table.insert(row_cells, tostring(c.content or "")) end
    table.insert(matrix, row_cells)
  end
  return matrix
end

--- Natural per-column content width, plus `overrides[col_idx]` extra padding
--- (from an interactive widen — see M.resize_current_column). Overrides only
--- ever ADD to the natural width: narrowing below it would leave the column's
--- widest cell overflowing past the padded width of shorter cells in the same
--- column, breaking `|` divider alignment down the column.
---@param matrix string[][]
---@param overrides? table<integer, integer>
---@return integer[]
local function compute_col_widths(matrix, overrides)
  local widths = {}
  for _, row in ipairs(matrix) do
    for col_idx, cell in ipairs(row) do
      local len = display_width(cell)
      if not widths[col_idx] or len > widths[col_idx] then widths[col_idx] = len end
    end
  end
  if overrides then
    for col_idx, extra in pairs(overrides) do
      if widths[col_idx] and extra and extra > 0 then
        widths[col_idx] = widths[col_idx] + extra
      end
    end
  end
  return widths
end

local function align_cell(text, width, align)
  align = align or "left"
  local len = display_width(text)
  if width <= len then return text end
  local pad = width - len
  if align == "left" then
    return text .. string.rep(" ", pad)
  elseif align == "right" then
    return string.rep(" ", pad) .. text
  else
    local left = math.floor(pad / 2)
    return string.rep(" ", left) .. text .. string.rep(" ", pad - left)
  end
end

local function format_row_with_alignment(row, widths, alignments)
  local parts = {}
  for i = 1, #widths do
    parts[i] = align_cell(row[i] or "", widths[i], alignments[i] or "left")
  end
  return "| " .. table.concat(parts, " | ") .. " |"
end

--- Build the aligned-Markdown rendering of the table. Alongside the lines, a
--- `row_map` is returned: `row_map[i]` (0-indexed, matching `lines`) is `0`
--- for the header row, a 1-based index into `mt.rows` for a data row, or nil
--- for the separator (no cell content on that line) — used to resolve which
--- table row the cursor is on for the interactive resize/row-edit keymaps.
---@param mt table
---@param overrides? table<integer, integer>
---@return string[] lines
---@return table<integer, integer> row_map
local function build_lines_from_markdowntable(mt, overrides)
  local matrix = table_to_matrix(mt)
  if #matrix == 0 then return {}, {} end
  local widths = compute_col_widths(matrix, overrides)
  local lines = {}
  local row_map = {}

  table.insert(lines, format_row_with_alignment(matrix[1], widths, mt.alignments))
  row_map[#lines - 1] = 0

  local sep_parts = {}
  for i, w in ipairs(widths) do
    local align = mt.alignments[i] or "left"
    if align == "center" then
      sep_parts[i] = ":" .. string.rep("-", math.max(1, w - 2)) .. ":"
    elseif align == "right" then
      sep_parts[i] = string.rep("-", math.max(1, w - 1)) .. ":"
    else
      sep_parts[i] = ":" .. string.rep("-", math.max(1, w - 1))
    end
  end
  table.insert(lines, "| " .. table.concat(sep_parts, " | ") .. " |")

  for ridx = 2, #matrix do
    table.insert(lines, format_row_with_alignment(matrix[ridx], widths, mt.alignments))
    row_map[#lines - 1] = ridx - 1
  end

  return lines, row_map
end

--- Build a Unicode box-drawing ("spreadsheet") rendering of the table, with a
--- full grid: top border, header row, a double-rule header separator, each data
--- row separated by a rule, and a bottom border. Column widths reuse the same
--- content-width calc as the markdown renderer. Returns a row_map like
--- build_lines_from_markdowntable (0 = header row, 1-based = data row, nil =
--- a border/rule line with no cell content).
---@param mt table
---@param overrides? table<integer, integer>
---@return string[] lines
---@return table<integer, integer> row_map
local function build_box_lines(mt, overrides)
  local matrix = table_to_matrix(mt)
  if #matrix == 0 then return {}, {} end
  local widths = compute_col_widths(matrix, overrides)

  local function border(left, mid, right, fill)
    local parts = {}
    for _, w in ipairs(widths) do parts[#parts + 1] = string.rep(fill, w + 2) end
    return left .. table.concat(parts, mid) .. right
  end
  local function row(cells)
    local parts = {}
    for i, w in ipairs(widths) do
      parts[#parts + 1] = " " .. align_cell(cells[i] or "", w, (mt.alignments and mt.alignments[i]) or "left") .. " "
    end
    return "│" .. table.concat(parts, "│") .. "│"
  end

  local lines = {}
  local row_map = {}
  lines[#lines + 1] = border("┌", "┬", "┐", "─")
  lines[#lines + 1] = row(matrix[1])
  row_map[#lines - 1] = 0
  lines[#lines + 1] = border("╞", "╪", "╡", "═")
  for r = 2, #matrix do
    lines[#lines + 1] = row(matrix[r])
    row_map[#lines - 1] = r - 1
    if r < #matrix then lines[#lines + 1] = border("├", "┼", "┤", "─") end
  end
  lines[#lines + 1] = border("└", "┴", "┘", "─")
  return lines, row_map
end

local function set_buf_opt(buf, name, value)
  pcall(api.nvim_set_option_value, name, value, { scope = "local", buf = buf })
end

local function set_win_opt(win, name, value)
  pcall(api.nvim_set_option_value, name, value, { scope = "local", win = win })
end

--- The header_line/sep_lines "block" for a single, unlabeled table's own
--- lines — i.e. exactly what render_markdowntable's (pre-refactor) inline
--- highlight computation used to derive, extracted so `rerender()` can reuse
--- it after a resize/row-edit.
---@param lines string[]
---@param box boolean
---@return { header_line: integer, sep_lines: integer[], label_line: nil }
local function compute_single_highlight_block(lines, box)
  local header_line = box and 1 or 0
  local sep_lines = {}
  if box then
    for i = 0, #lines - 1 do
      if i ~= header_line and not (lines[i + 1] or ""):match("^│") then
        sep_lines[#sep_lines + 1] = i
      end
    end
  elseif #lines >= 2 then
    sep_lines[1] = 1
  end
  return { header_line = header_line, sep_lines = sep_lines, label_line = nil }
end

--- Apply header/separator/label highlights for one or more rendered blocks
--- (see build_stacked_lines / compute_single_highlight_block) to `buf`.
---@param buf integer
---@param lines string[]
---@param blocks { header_line: integer, sep_lines: integer[], label_line: integer|nil }[]
---@param opts table
local function apply_blocks_highlight(buf, lines, blocks, opts)
  pcall(function()
    local ns = state.namespace
    local header_hl = opts.highlight and opts.highlight.header or "Title"
    local sep_hl = opts.highlight and opts.highlight.separator or "Comment"
    if not (hl and hl.range) then return end
    for _, block in ipairs(blocks) do
      if block.label_line then
        hl.range(buf, ns, sep_hl, { block.label_line, 0 }, { block.label_line, -1 }, { inclusive = false })
      end
      if #lines > block.header_line then
        hl.range(buf, ns, header_hl, { block.header_line, 0 }, { block.header_line, -1 }, { inclusive = false })
      end
      for _, sl in ipairs(block.sep_lines) do
        hl.range(buf, ns, sep_hl, { sl, 0 }, { sl, -1 }, { inclusive = false })
      end
    end
  end)
end

--- Resolve the buffer cell (table index / row index / column index) under
--- the cursor in the floating TableView, using `state.row_map` (built by the
--- last render/rerender). Returns nil when the view isn't open, the cursor is
--- on a line with no cell content (border, separator, multi-table label), or
--- past the last divider.
---@return { table_idx: integer, row_idx: integer, col_idx: integer }|nil
local function resolve_cursor_target()
  if not (state.win and api.nvim_win_is_valid(state.win) and state.buf and api.nvim_buf_is_valid(state.buf)) then
    return nil
  end
  if not state.row_map then return nil end

  local cur = api.nvim_win_get_cursor(state.win)
  local line_idx0 = cur[1] - 1
  local entry = state.row_map[line_idx0]
  if not entry then return nil end

  local line = api.nvim_buf_get_lines(state.buf, line_idx0, line_idx0 + 1, false)[1]
  if not line then return nil end

  local dispcol = byte_to_display_col(line, cur[2])
  local col_idx = cell_index_at(line, dispcol)
  if not col_idx then return nil end

  return { table_idx = entry.table_idx, row_idx = entry.row_idx, col_idx = col_idx }
end

local function ensure_view(opts)
  opts = opts or {}

  if state.buf and api.nvim_buf_is_valid(state.buf) then
    if state.win and api.nvim_win_is_valid(state.win) then
      return state.buf, state.win
    end
  end

  if not (state.buf and api.nvim_buf_is_valid(state.buf)) then
    state.buf = api.nvim_create_buf(false, true)
  end

  set_buf_opt(state.buf, "bufhidden", "wipe")
  set_buf_opt(state.buf, "filetype", "markdown-tableview")
  set_buf_opt(state.buf, "modifiable", false)
  -- "acwrite" (not "nofile"): `:write` on a nofile buffer always errors with
  -- E382 ("Cannot write, 'buftype' option is set"), even with a BufWriteCmd
  -- autocommand registered — Neovim only dispatches to BufWriteCmd for
  -- acwrite, and only once the buffer has a name (E32 otherwise). This is
  -- what M.write_back()'s `:w` support (see the BufWriteCmd below) requires.
  set_buf_opt(state.buf, "buftype", "acwrite")
  pcall(api.nvim_buf_set_name, state.buf, string.format("markdown-tableview://%d", state.buf))

  local max_w = math.floor(vim.o.columns * (opts.max_width_frac or default_opts.max_width_frac))
  local max_h = math.floor(vim.o.lines * (opts.max_height_frac or default_opts.max_height_frac))
  local width = opts.width or math.min(math.max(40, max_w), vim.o.columns - 4)
  local height = opts.height or math.min(math.max(6, max_h), vim.o.lines - 4)

  local win_opts = {
    relative = "editor",
    width    = width,
    height   = height,
    col      = math.floor((vim.o.columns - width) / 2),
    row      = math.floor((vim.o.lines - height) / 2),
    style    = "minimal",
    border   = opts.border or default_opts.border,
  }

  if state.win and not api.nvim_win_is_valid(state.win) then state.win = nil end

  state.win = api.nvim_open_win(state.buf, true, win_opts)

  set_win_opt(state.win, "wrap", false)
  set_win_opt(state.win, "cursorline", false)
  set_win_opt(state.win, "number", false)
  set_win_opt(state.win, "relativenumber", false)

  window.nice_quit(state.win, { force = true })

  -- Interactive resize/row-move: buffer-local, Normal mode only, scoped to
  -- this TableView popup — never active outside it. Dispatched through `M.*`
  -- (not raw locals) so these can be bound here regardless of where
  -- resize_current_column/move_current_row end up defined in the file.
  --
  -- Both the arrow-key and h/j/k/l forms are bound to the same action: some
  -- terminals/multiplexers intercept Alt+Arrow (commonly Up/Down, for
  -- scrollback or pane navigation) before Neovim ever sees it, so the
  -- Vim-motion letters are a reliable fallback rather than the only way in.
  local map_opts = { buffer = state.buf, nowait = true, silent = true }
  local function bind(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, vim.tbl_extend("force", map_opts, { desc = "[markdown.nvim] TableView: " .. desc }))
  end
  bind("<M-Right>", function() M.resize_current_column(1) end, "widen current column")
  bind("<M-l>",     function() M.resize_current_column(1) end, "widen current column")
  bind("<M-Left>",  function() M.resize_current_column(-1) end, "narrow current column")
  bind("<M-h>",     function() M.resize_current_column(-1) end, "narrow current column")
  bind("<M-Up>",    function() M.move_current_row(-1) end, "move current row up")
  bind("<M-k>",     function() M.move_current_row(-1) end, "move current row up")
  bind("<M-Down>",  function() M.move_current_row(1) end, "move current row down")
  bind("<M-j>",     function() M.move_current_row(1) end, "move current row down")

  -- `:w` in the popup writes row-order/content edits back to wherever the
  -- table(s) actually came from (source buffer or file — see M.write_back).
  -- BufWriteCmd is the standard way to give a `nofile` buffer a working `:w`.
  api.nvim_create_autocmd("BufWriteCmd", {
    buffer = state.buf,
    callback = function() M.write_back() end,
    desc = "[markdown.nvim] TableView: write row edits back to source",
  })

  return state.buf, state.win
end

local function clear_highlights(buf)
  pcall(api.nvim_buf_clear_namespace, buf, state.namespace, 0, -1)
end

--- Build the stacked lines for every table in `tables` (rendered one after
--- another, separated by a blank line), plus per-table highlight metadata so
--- the caller can re-derive header/separator/label rows in the combined
--- buffer, and a combined row_map (see build_lines_from_markdowntable) tagging
--- each line with which table/row it belongs to. A short "── Table i/N (line
--- L) ──" label precedes each table when there is more than one; a table with
--- `.source` set (read from a file on disk — the %/path/cwd scopes) is always
--- labelled with its file path, even when it is the only table, so it stays
--- clear which table came from where while scrolling a long, possibly
--- multi-file stack.
---@param tables table[]  markdown.tableview.parser table objects (optionally with `.source`)
---@param style "markdown"|"box"
---@param overrides_by_table? table<integer, table<integer, integer>>
---@return string[] lines
---@return { header_line: integer, sep_lines: integer[], label_line: integer|nil }[] blocks
---@return table<integer, { table_idx: integer, row_idx: integer }> row_map
local function build_stacked_lines(tables, style, overrides_by_table)
  local box = style == "box"
  local lines = {}
  local blocks = {}
  local row_map = {}

  for idx, mt in ipairs(tables) do
    if idx > 1 then lines[#lines + 1] = "" end

    -- A table read from disk (`.source` set by parser.get_tables_from_file, for
    -- the %/path/cwd scopes) always gets a label naming its file, even when it
    -- is the only table shown; a same-buffer stack only labels when there is
    -- more than one table (unchanged from the single-file behaviour).
    local label_line = nil
    if mt.source then
      label_line = #lines
      lines[#lines + 1] = string.format("── %s:%d  (Table %d/%d) ──", mt.source, mt.start_line or 0, idx, #tables)
    elseif #tables > 1 then
      label_line = #lines
      lines[#lines + 1] = string.format("── Table %d/%d (line %d) ──", idx, #tables, mt.start_line or 0)
    end

    local block_start = #lines -- 0-indexed row of this table's first line
    local overrides = overrides_by_table and overrides_by_table[idx]
    -- NOT `box and f() or g()`: that ternary idiom truncates multi-return to a
    -- single value, silently dropping table_row_map.
    local table_lines, table_row_map
    if box then
      table_lines, table_row_map = build_box_lines(mt, overrides)
    else
      table_lines, table_row_map = build_lines_from_markdowntable(mt, overrides)
    end

    -- Header/separator rows, computed relative to table_lines first (0-indexed)
    -- so the box-vs-markdown logic below matches render_markdowntable exactly,
    -- then offset by block_start for the combined buffer.
    local header_local = box and 1 or 0
    local sep_local = {}
    if box then
      for i = 0, #table_lines - 1 do
        if i ~= header_local and not (table_lines[i + 1] or ""):match("^│") then
          sep_local[#sep_local + 1] = i
        end
      end
    elseif #table_lines >= 2 then
      sep_local[1] = 1
    end

    for _, l in ipairs(table_lines) do lines[#lines + 1] = l end

    for i, r in pairs(table_row_map) do
      row_map[block_start + i] = { table_idx = idx, row_idx = r }
    end

    local sep_abs = {}
    for _, i in ipairs(sep_local) do sep_abs[#sep_abs + 1] = block_start + i end

    blocks[#blocks + 1] = {
      header_line = block_start + header_local,
      sep_lines   = sep_abs,
      label_line  = label_line,
    }
  end

  return lines, blocks, row_map
end

--- Rebuild and redraw the floating TableView from `state.tables` /
--- `state.style` / `state.col_overrides`, WITHOUT resetting them — used by
--- the interactive resize/row-edit keymaps after mutating `state.tables[i]`
--- or `state.col_overrides[i]`. No-op (returns nil) when the view isn't open.
---@return string[]|nil lines the newly-rendered lines, or nil if not open
local function rerender()
  if not (state.buf and api.nvim_buf_is_valid(state.buf) and state.tables and state.style) then
    return nil
  end

  local box = state.style == "box"
  local lines, blocks, row_map

  if state.single then
    local mt = state.tables[1]
    local overrides = state.col_overrides[1]
    local raw_row_map
    if box then
      lines, raw_row_map = build_box_lines(mt, overrides)
    else
      lines, raw_row_map = build_lines_from_markdowntable(mt, overrides)
    end
    row_map = {}
    for i, r in pairs(raw_row_map) do row_map[i] = { table_idx = 1, row_idx = r } end
    blocks = { compute_single_highlight_block(lines, box) }
  else
    lines, blocks, row_map = build_stacked_lines(state.tables, state.style, state.col_overrides)
  end

  state.row_map = row_map

  set_buf_opt(state.buf, "modifiable", true)
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  set_buf_opt(state.buf, "modifiable", false)

  clear_highlights(state.buf)
  apply_blocks_highlight(state.buf, lines, blocks, state.opts or default_opts)

  return lines
end

--- rerender() plus best-effort cursor restore: land back on the same
--- (table_idx, row_idx, col_idx) cell `ctx` pointed at before the mutation —
--- clamped into range if a row removal shifted things — so repeated Alt-key
--- presses keep acting on the same cell instead of the cursor jumping.
---@param ctx { table_idx: integer, row_idx: integer, col_idx: integer }
local function rerender_preserving_cursor(ctx)
  local lines = rerender()
  if not lines or not state.row_map then return end
  if not (state.win and api.nvim_win_is_valid(state.win)) then return end

  local target_row = ctx.row_idx
  local mt = state.tables and state.tables[ctx.table_idx]
  if mt then
    target_row = math.max(0, math.min(target_row, #mt.rows))
  end

  local target_line = nil
  for i = 0, #lines - 1 do
    local e = state.row_map[i]
    if e and e.table_idx == ctx.table_idx and e.row_idx == target_row then
      target_line = i
      break
    end
  end
  if not target_line then return end

  local new_line = lines[target_line + 1] or ""
  local cols = divider_columns(new_line)
  local dispcol = cols[ctx.col_idx] or 0
  local target_disp = math.min(dispcol + 2, display_width(new_line)) -- +2: past "| "
  local bytecol = display_col_to_byte(new_line, target_disp)

  pcall(api.nvim_win_set_cursor, state.win, { target_line + 1, bytecol })
end

function M.render_markdowntable(mt, opts)
  opts = merge(default_opts, opts or {})
  local box = opts.style == "box"
  local lines, row_map
  if box then
    lines, row_map = build_box_lines(mt)
  else
    lines, row_map = build_lines_from_markdowntable(mt)
  end

  if opts.floating then
    local buf, _ = ensure_view(opts)
    if not (buf and api.nvim_buf_is_valid(buf)) then return end

    state.tables = { mt }
    state.style = box and "box" or "markdown"
    state.single = true
    state.opts = opts
    state.col_overrides = {}
    state.row_map = {}
    for i, r in pairs(row_map) do state.row_map[i] = { table_idx = 1, row_idx = r } end

    set_buf_opt(state.buf, "modifiable", true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    set_buf_opt(state.buf, "modifiable", false)

    clear_highlights(buf)
    apply_blocks_highlight(buf, lines, { compute_single_highlight_block(lines, box) }, opts)
  else
    local buf = api.nvim_create_buf(true, false)
    api.nvim_buf_set_name(buf, opts.bufname or "[Markdown Table]")
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    pcall(api.nvim_set_option_value, "filetype", "markdown", { scope = "local", buf = buf })
    api.nvim_set_current_buf(buf)
  end
end

function M.close_view()
  if state.win and api.nvim_win_is_valid(state.win) then
    pcall(api.nvim_win_close, state.win, true)
  end
  if state.buf and api.nvim_buf_is_valid(state.buf) then
    pcall(api.nvim_buf_delete, state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.tables = nil
  state.style = nil
  state.single = nil
  state.opts = nil
  state.col_overrides = {}
  state.row_map = nil
end

function M.toggle_markdowntable(mt, opts)
  if state.win and api.nvim_win_is_valid(state.win) then
    M.close_view()
    return
  end
  M.render_markdowntable(mt, opts)
end

--- Render every table in `tables`, stacked one after another (see
--- build_stacked_lines). Used when the cursor is not on any table, or when the
--- caller explicitly asked for the whole buffer (`TableViewToggle %`).
---@param tables table[]
---@param opts? table
function M.render_tables(tables, opts)
  opts = merge(default_opts, opts or {})
  local style = opts.style == "box" and "box" or "markdown"
  local lines, blocks, row_map = build_stacked_lines(tables, style)

  if not opts.floating then
    local buf = api.nvim_create_buf(true, false)
    api.nvim_buf_set_name(buf, opts.bufname or "[Markdown Tables]")
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    pcall(api.nvim_set_option_value, "filetype", "markdown", { scope = "local", buf = buf })
    api.nvim_set_current_buf(buf)
    return
  end

  local buf, _ = ensure_view(opts)
  if not (buf and api.nvim_buf_is_valid(buf)) then return end

  state.tables = tables
  state.style = style
  state.single = false
  state.opts = opts
  state.col_overrides = {}
  state.row_map = row_map

  set_buf_opt(state.buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  set_buf_opt(state.buf, "modifiable", false)

  clear_highlights(buf)
  apply_blocks_highlight(buf, lines, blocks, opts)
end

--- Toggle the stacked all-tables preview (see render_tables).
---@param tables table[]
---@param opts? table
function M.toggle_tables(tables, opts)
  if state.win and api.nvim_win_is_valid(state.win) then
    M.close_view()
    return
  end
  M.render_tables(tables, opts)
end

--- Widen (delta > 0) or narrow (delta < 0) the column under the cursor in the
--- floating TableView, by one column of extra padding. Never narrows below
--- the column's natural content width — that would leave the widest cell in
--- the column overflowing past the (now too-narrow) padded width used for
--- shorter cells in the same column on other rows, breaking `|` divider
--- alignment down the column. No-op when the cursor isn't on a table cell
--- (e.g. a border/label/separator line) or the view isn't open.
---@param delta integer +1 to widen, -1 to narrow
function M.resize_current_column(delta)
  local ctx = resolve_cursor_target()
  if not ctx then return end

  state.col_overrides[ctx.table_idx] = state.col_overrides[ctx.table_idx] or {}
  local overrides = state.col_overrides[ctx.table_idx]
  local current = overrides[ctx.col_idx] or 0
  local new_value = math.max(0, current + delta)
  if new_value == current then return end

  overrides[ctx.col_idx] = new_value
  rerender_preserving_cursor(ctx)
end

--- Swap the row under the cursor with the row above (delta < 0) or below
--- (delta > 0) it, reordering `state.tables[i].rows` in place. This is a
--- DISPLAY-only mutation of the in-memory preview until `M.write_back` (`:w`
--- in the popup) persists it. No-op on the header row (nothing to swap it
--- against), at either edge (no row above the first / below the last), or
--- when the cursor isn't on a table row or the view isn't open.
---@param delta integer -1 to move up, +1 to move down
function M.move_current_row(delta)
  local ctx = resolve_cursor_target()
  if not ctx then return end
  if ctx.row_idx == 0 then return end -- header row: nothing to reorder it against

  local mt = state.tables and state.tables[ctx.table_idx]
  if not mt then return end

  local target_idx = ctx.row_idx + delta
  if target_idx < 1 or target_idx > #mt.rows then return end

  mt.rows[ctx.row_idx], mt.rows[target_idx] = mt.rows[target_idx], mt.rows[ctx.row_idx]

  rerender_preserving_cursor({ table_idx = ctx.table_idx, row_idx = target_idx, col_idx = ctx.col_idx })
end

--- Write every currently-shown table's content — including any row reorders
--- from `M.move_current_row` — back to wherever it came from: the live
--- source buffer (`mt.bufnr`, set by parser.get_tables) if it's still valid,
--- otherwise the file directly (`mt.source`, set by parser.get_tables_from_file
--- for the %/cwd/path scopes). Bound to `:w` in the popup (see ensure_view's
--- BufWriteCmd). A table with neither (e.g. a hand-built `mt` with no parser
--- origin) is silently skipped — nowhere to write it back to.
---
--- Deliberately writes NATURAL column widths (no col_overrides): widening a
--- column in the popup is a reading aid, not something that should pad out
--- the saved file with extra spaces the row content doesn't need.
function M.write_back()
  if not state.tables then return end

  local wrote_buf, wrote_file, skipped = 0, 0, 0

  for _, mt in ipairs(state.tables) do
    local lines = build_lines_from_markdowntable(mt) -- natural widths, ignores col_overrides

    if mt.bufnr and api.nvim_buf_is_valid(mt.bufnr) then
      api.nvim_buf_set_lines(mt.bufnr, mt.start_line - 1, mt.end_line, false, lines)
      wrote_buf = wrote_buf + 1
    elseif mt.source then
      local ok, file_lines = pcall(vim.fn.readfile, mt.source)
      if ok and file_lines then
        local new_content = {}
        for i = 1, mt.start_line - 1 do new_content[#new_content + 1] = file_lines[i] end
        vim.list_extend(new_content, lines)
        for i = mt.end_line + 1, #file_lines do new_content[#new_content + 1] = file_lines[i] end
        vim.fn.writefile(new_content, mt.source)
        wrote_file = wrote_file + 1
      else
        skipped = skipped + 1
      end
    else
      skipped = skipped + 1
    end
  end

  if state.buf and api.nvim_buf_is_valid(state.buf) then
    vim.bo[state.buf].modified = false
  end

  if wrote_buf == 0 and wrote_file == 0 then
    notify.warn("TableView: nothing to write back (no source buffer/file for the shown table(s))")
    return
  end

  local parts = {}
  if wrote_buf > 0 then parts[#parts + 1] = string.format("%d buffer(s)", wrote_buf) end
  if wrote_file > 0 then parts[#parts + 1] = string.format("%d file(s) on disk", wrote_file) end
  local msg = "TableView: wrote back to " .. table.concat(parts, ", ")
  if skipped > 0 then msg = msg .. string.format(" (%d table(s) skipped: no known source)", skipped) end
  if wrote_file > 0 then msg = msg .. " — buffer edits are NOT auto-saved, files on disk were" end
  notify.info(msg)
end

M.render_table = M.render_markdowntable
M.toggle_table = M.toggle_markdowntable
M.close        = M.close_view

--- Verify that a rendered table block (as returned by build_lines_from_
--- markdowntable / build_box_lines / render_tables' stacked output) has every
--- `|`/`│` divider at the same DISPLAY column on every line that has any —
--- i.e. the table is actually visually aligned, not just byte-aligned. This is
--- the de-facto check for the "content with umlauts/em-dashes/curly quotes
--- drifts the columns" bug class: run it over rendered output (in a test, or
--- ad hoc via `:lua print(require(...).validate_alignment(lines))`) rather
--- than eyeballing a screenshot.
---@param lines string[]
---@return boolean ok
---@return string|nil err  description of the first mismatch found
function M.validate_alignment(lines)
  local reference, reference_lineno = nil, nil
  for lineno, line in ipairs(lines) do
    local cols = divider_columns(line)
    if #cols > 0 then
      if not reference then
        reference, reference_lineno = cols, lineno
      elseif #cols ~= #reference then
        return false, string.format(
          "line %d has %d divider(s), line %d (reference) has %d",
          lineno, #cols, reference_lineno, #reference)
      else
        for i, c in ipairs(cols) do
          if c ~= reference[i] then
            return false, string.format(
              "line %d: divider %d is at display column %d, expected %d (from line %d)",
              lineno, i, c, reference[i], reference_lineno)
          end
        end
      end
    end
  end
  return true, nil
end

return M
