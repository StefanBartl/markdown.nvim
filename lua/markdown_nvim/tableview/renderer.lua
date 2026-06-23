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
      local len = #cell
      if not widths[col_idx] or len > widths[col_idx] then widths[col_idx] = len end
    end
  end
  return widths
end

local function align_cell(text, width, align)
  align = align or "left"
  local len = #text
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

local function set_buf_opt(buf, name, value)
  pcall(api.nvim_set_option_value, name, value, { scope = "local", buf = buf })
end

local function set_win_opt(win, name, value)
  pcall(api.nvim_set_option_value, name, value, { scope = "local", win = win })
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

function M.render_markdowntable(mt, opts)
  opts = merge(default_opts, opts or {})
  local lines = build_lines_from_markdowntable(mt)

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
      if #lines >= 1 and hl and hl.range then
        hl.range(buf, ns, header_hl, { 0, 0 }, { 0, -1 }, { inclusive = false })
      end
      if #lines >= 2 and hl and hl.range then
        hl.range(buf, ns, sep_hl, { 1, 0 }, { 1, -1 }, { inclusive = false })
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

M.render_table = M.render_markdowntable
M.toggle_table = M.toggle_markdowntable
M.close        = M.close_view

return M
