---@module 'markdown_nvim.core.table_mode'
---@brief A focused Lua reimplementation of vim-table-mode's core, fused with the
---       markdown.nvim table stack (reuses core.table_fmt for alignment).
---@description
--- Provides the most-used table-mode features without a Vimscript dependency:
---   * mode      — per-buffer auto-format: after each edit inside a GFM table the
---                 table is re-aligned (InsertLeave + TextChanged, debounced).
---   * tableize  — convert delimited text into a GFM table. The separator is
---                 auto-detected (tab/comma/2+ spaces) or named explicitly:
---                 csv, tsv, psv, scsv, space, spaces, a bare punctuation char,
---                 or a quoted literal like `" "`. Single-char separators honor
---                 RFC-4180 double quoting, and leading separators map to
---                 leading empty columns.
---   * motions   — jump to the previous / next cell on the current row.
--- Alignment is delegated to `core.table_fmt.format_table_at_cursor`, so the
--- header/cell alignment config and separator style stay consistent with
--- `:Markdown table format`.

local fmt = require("markdown_nvim.core.table_fmt")
local lib_debounce_buffer = require("lib.nvim.debounce.buffer")

local api = vim.api

local M = {}

-- Per-buffer state: augroup id and a re-entrancy guard so the reformat's own
-- buffer write does not retrigger the TextChanged handler. The debounce timer
-- itself is shared (buffer-scoped internally) — see `_debounce` below.
---@type table<integer, { aug: integer, busy: boolean }>
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

-- One shared, buffer-scoped debounce handle: `lib.nvim.debounce.buffer`
-- keeps an independent 120ms timer per bufnr internally, matching what the
-- old per-buffer `S[bufnr].timer` bookkeeping did by hand.
local _debounce = lib_debounce_buffer.new(function(bufnr)
  M.reformat(bufnr)
end, { ms = 120 })

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
  S[bufnr] = { aug = aug, busy = false }

  local function schedule()
    local st = S[bufnr]
    if not st or st.busy then return end
    _debounce.call(bufnr)
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
  _debounce.cancel(bufnr)
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

-- Named separator formats. Each maps to a single-character delimiter (the
-- common case: CSV, TSV, PSV, …) or the special "whitespace" run mode. Users
-- pass these as `:Markdown table tableize <name>`; a bare punctuation char or a
-- quoted literal (e.g. `" "`) is accepted too and treated as a literal
-- delimiter. Everything here is lower-cased before lookup.
---@type table<string, { char?: string, ws?: boolean, label: string }>
local FORMATS = {
  csv        = { char = ",",  label = "csv" },
  comma      = { char = ",",  label = "csv" },
  tsv        = { char = "\t", label = "tsv" },
  tab        = { char = "\t", label = "tsv" },
  ["\\t"]    = { char = "\t", label = "tsv" },
  psv        = { char = "|",  label = "psv" },
  pipe       = { char = "|",  label = "psv" },
  bar        = { char = "|",  label = "psv" },
  ssv        = { char = ";",  label = "scsv" },
  scsv       = { char = ";",  label = "scsv" },
  semicolon  = { char = ";",  label = "scsv" },
  colon      = { char = ":",  label = "colon" },
  space      = { char = " ",  label = "space" },
  spaces     = { ws = true,   label = "whitespace" },
  whitespace = { ws = true,   label = "whitespace" },
}

--- Strip a `sep=` / `separator=` prefix and one matching pair of surrounding
--- quotes from a raw separator argument. `sep="\t"` -> `\t`, `" "` -> ` `.
---@param spec string
---@return string
local function clean_spec(spec)
  spec = spec:gsub("^%s*separator%s*=%s*", ""):gsub("^%s*sep%s*=%s*", "")
  local q = spec:sub(1, 1)
  if (q == '"' or q == "'") and spec:sub(-1) == q and #spec >= 2 then
    spec = spec:sub(2, -2)
  end
  return spec
end

--- Resolve a separator spec into a split mode. Explicit `spec` wins; otherwise
--- auto-detect (tab, then comma, then runs of 2+ spaces). Returns:
---   "char", <char>  — split on a single literal char, CSV-style quoting honored
---   "ws",   "%s%s+" — split on runs of 2+ whitespace, no quoting
---@param lines string[]
---@param spec? string  format name, literal delimiter, or nil/"" for auto
---@return "char"|"ws" mode, string val, string label
local function resolve_delim(lines, spec)
  if spec ~= nil then spec = clean_spec(spec) end

  if spec == nil or spec == "" or spec:lower() == "auto" then
    local sample = ""
    for _, l in ipairs(lines) do if l:match("%S") then sample = l; break end end
    if sample:find("\t") then return "char", "\t", "tsv" end
    if sample:find(",") then return "char", ",", "csv" end
    if sample:find("%s%s+") then return "ws", "%s%s+", "whitespace" end
    return "char", "\t", "single-column" -- no delimiter present
  end

  local f = FORMATS[spec:lower()]
  if f then
    if f.ws then return "ws", "%s%s+", f.label end
    return "char", f.char, f.label
  end

  -- Fall through: a literal delimiter. A single char goes through the
  -- quoting-aware char splitter; a multi-char string is matched literally.
  if vim.fn.strchars(spec) == 1 then return "char", spec, spec end
  return "ws", vim.pesc(spec), spec
end

--- Split `line` on a single-character delimiter, honoring RFC-4180-style double
--- quoting: a field may be wrapped in `"..."` to contain the delimiter, and a
--- literal quote inside is written `""`. Each field is trimmed of outer spaces.
--- Consecutive delimiters yield empty fields, so leading delimiters produce
--- leading empty columns.
---@param line string
---@param sep string  single character
---@return string[]
local function split_char(line, sep)
  local out, buf = {}, {}
  local in_q, ws_only = false, true -- ws_only: field so far is empty/whitespace
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if in_q then
      if c == '"' then
        if line:sub(i + 1, i + 1) == '"' then buf[#buf + 1] = '"'; i = i + 1
        else in_q = false end
      else
        buf[#buf + 1] = c
      end
    elseif c == '"' and ws_only then
      in_q = true
      buf = {} -- drop any leading whitespace collected before the quote
    elseif c == sep then
      out[#out + 1] = vim.trim(table.concat(buf))
      buf, ws_only = {}, true
    else
      buf[#buf + 1] = c
      if not c:match("%s") then ws_only = false end
    end
    i = i + 1
  end
  out[#out + 1] = vim.trim(table.concat(buf))
  return out
end

--- Split `line` into trimmed fields on the (Lua-pattern) delimiter. Runs of the
--- pattern are single delimiters, so no empty fields are produced between them.
---@param line string
---@param pat string
---@return string[]
local function split_pattern(line, pat)
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
---@param delim? string  format name / literal separator / nil for auto-detect
---@return boolean ok, string|nil err
function M.tableize(bufnr, line1, line2, delim)
  bufnr = bufnr or api.nvim_get_current_buf()
  local raw = api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)

  local rows = {}
  for _, l in ipairs(raw) do
    if l:match("%S") then rows[#rows + 1] = l end
  end
  if #rows == 0 then return false, "tableize: no non-empty lines in range" end

  local mode, val = resolve_delim(rows, delim)
  local matrix = {}
  local cols = 0
  for _, l in ipairs(rows) do
    local f = (mode == "char") and split_char(l, val) or split_pattern(l, val)
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
