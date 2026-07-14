---@module 'markdown_nvim.tableview.renderer'
local M = {}

local hl = vim.highlight
local api = vim.api

local state = {
  buf = nil,
  win = nil,
  namespace = api.nvim_create_namespace("markdown_nvim_tableview"),
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

local function compute_col_widths(matrix)
  local widths = {}
  for _, row in ipairs(matrix) do
    for col_idx, cell in ipairs(row) do
      local len = display_width(cell)
      if not widths[col_idx] or len > widths[col_idx] then widths[col_idx] = len end
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

local function build_lines_from_markdowntable(mt)
  local matrix = table_to_matrix(mt)
  if #matrix == 0 then return {} end
  local widths = compute_col_widths(matrix)
  local lines = {}

  table.insert(lines, format_row_with_alignment(matrix[1], widths, mt.alignments))

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
  end

  return lines
end

--- Build a Unicode box-drawing ("spreadsheet") rendering of the table, with a
--- full grid: top border, header row, a double-rule header separator, each data
--- row separated by a rule, and a bottom border. Column widths reuse the same
--- content-width calc as the markdown renderer.
---@param mt table
---@return string[]
local function build_box_lines(mt)
  local matrix = table_to_matrix(mt)
  if #matrix == 0 then return {} end
  local widths = compute_col_widths(matrix)

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
  lines[#lines + 1] = border("┌", "┬", "┐", "─")
  lines[#lines + 1] = row(matrix[1])
  lines[#lines + 1] = border("╞", "╪", "╡", "═")
  for r = 2, #matrix do
    lines[#lines + 1] = row(matrix[r])
    if r < #matrix then lines[#lines + 1] = border("├", "┼", "┤", "─") end
  end
  lines[#lines + 1] = border("└", "┴", "┘", "─")
  return lines
end

local function set_buf_opt(buf, name, value)
  pcall(api.nvim_set_option_value, name, value, { scope = "local", buf = buf })
end

local function set_win_opt(win, name, value)
  pcall(api.nvim_set_option_value, name, value, { scope = "local", win = win })
end

--- Bind `q` and `<Esc>` on the floating preview buffer to close it. `M.close_view`
--- is resolved at call time, so this is safe even though it's defined below.
---@param buf integer
local function set_close_keymaps(buf)
  local function close() M.close_view() end
  local map_opts = { buffer = buf, nowait = true, silent = true, desc = "[markdown.nvim] Close TableView" }
  vim.keymap.set("n", "q", close, map_opts)
  vim.keymap.set("n", "<Esc>", close, map_opts)
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
  set_buf_opt(state.buf, "buftype", "nofile")
  set_close_keymaps(state.buf)

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

  return state.buf, state.win
end

local function clear_highlights(buf)
  pcall(api.nvim_buf_clear_namespace, buf, state.namespace, 0, -1)
end

--- Build the stacked lines for every table in `tables` (rendered one after
--- another, separated by a blank line), plus per-table highlight metadata so
--- the caller can re-derive header/separator/label rows in the combined
--- buffer. A short "── Table i/N (line L) ──" label precedes each table when
--- there is more than one; a table with `.source` set (read from a file on
--- disk — the %/path/cwd scopes) is always labelled with its file path, even
--- when it is the only table, so it stays clear which table came from where
--- while scrolling a long, possibly multi-file stack.
---@param tables table[]  markdown_nvim.tableview.parser table objects (optionally with `.source`)
---@param style "markdown"|"box"
---@return string[] lines
---@return { header_line: integer, sep_lines: integer[], label_line: integer|nil }[] blocks
local function build_stacked_lines(tables, style)
  local box = style == "box"
  local lines = {}
  local blocks = {}

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
    local table_lines = box and build_box_lines(mt) or build_lines_from_markdowntable(mt)

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

    local sep_abs = {}
    for _, i in ipairs(sep_local) do sep_abs[#sep_abs + 1] = block_start + i end

    blocks[#blocks + 1] = {
      header_line = block_start + header_local,
      sep_lines   = sep_abs,
      label_line  = label_line,
    }
  end

  return lines, blocks
end

function M.render_markdowntable(mt, opts)
  opts = merge(default_opts, opts or {})
  local box = opts.style == "box"
  local lines = box and build_box_lines(mt) or build_lines_from_markdowntable(mt)

  if opts.floating then
    local buf, _ = ensure_view(opts)
    if not (buf and api.nvim_buf_is_valid(buf)) then return end

    set_buf_opt(state.buf, "modifiable", true)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    set_buf_opt(state.buf, "modifiable", false)

    clear_highlights(buf)

    pcall(function()
      local ns = state.namespace
      local header_hl = opts.highlight and opts.highlight.header or "Title"
      local sep_hl = opts.highlight and opts.highlight.separator or "Comment"
      -- Box: line 0 = top border, line 1 = header row, line 2 = header rule.
      -- Markdown: line 0 = header row, line 1 = separator.
      local header_line = box and 1 or 0
      if hl and hl.range then
        if #lines > header_line then
          hl.range(buf, ns, header_hl, { header_line, 0 }, { header_line, -1 }, { inclusive = false })
        end
        if box then
          -- Dim every border/rule line (they don't start with the │ cell edge).
          for i = 0, #lines - 1 do
            if i ~= header_line and not (lines[i + 1] or ""):match("^│") then
              hl.range(buf, ns, sep_hl, { i, 0 }, { i, -1 }, { inclusive = false })
            end
          end
        elseif #lines >= 2 then
          hl.range(buf, ns, sep_hl, { 1, 0 }, { 1, -1 }, { inclusive = false })
        end
      end
    end)
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
  local lines, blocks = build_stacked_lines(tables, style)

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

  set_buf_opt(state.buf, "modifiable", true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  set_buf_opt(state.buf, "modifiable", false)

  clear_highlights(buf)
  pcall(function()
    local ns = state.namespace
    local header_hl = opts.highlight and opts.highlight.header or "Title"
    local sep_hl = opts.highlight and opts.highlight.separator or "Comment"
    if hl and hl.range then
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
    end
  end)
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

M.render_table = M.render_markdowntable
M.toggle_table = M.toggle_markdowntable
M.close        = M.close_view

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
