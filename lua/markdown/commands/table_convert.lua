---@module 'markdown.commands.table_convert'
---@brief `:Markdown table convert [from=auto] [to=gfm]` -- a table in one format written in another.
---@description
--- Source: the `:'<,'>` range if there is one, otherwise the table under the cursor, otherwise
--- (csv / tsv only) the whole buffer. `from=auto` finds the table with every embedded format
--- (gfm, org, box) regardless of `table.formats`; `from=csv|tsv` reads the range as delimited text.
--- The lines of the source are replaced by the table in the `to=` format. What the target format
--- cannot keep (alignment in csv, row groups of an org table, formulas after it) is reported.

local notify = require("markdown.util.notify").create("[markdown.commands.table_convert]")
local registry = require("markdown.tables.registry")

local M = {}

local TARGETS = { "gfm", "org", "box", "csv", "tsv" }

---@param argv string[]
---@return { from: string, to: string }|nil opts, string|nil err
function M.parse_args(argv)
  local o = { from = "auto", to = "gfm" }
  for _, a in ipairs(argv or {}) do
    local key, val = a:match("^(%w+)=(.*)$")
    if key == "from" or key == "to" then
      o[key] = val:lower()
    elseif key then
      return nil, "unknown option '" .. key .. "='"
    else
      o.to = a:lower() -- a bare word is the target
    end
  end
  if o.from ~= "auto" and not vim.tbl_contains(TARGETS, o.from) then
    return nil, "from must be auto|" .. table.concat(TARGETS, "|")
  end
  if not vim.tbl_contains(TARGETS, o.to) then
    return nil, "to must be " .. table.concat(TARGETS, "|")
  end
  return o, nil
end

---The table `opts.from` describes at `lnum` (or in `range`) of `lines`.
---@param lines string[]
---@param o { from: string }
---@param lnum integer
---@param range? { [1]: integer, [2]: integer }
---@return table|nil tbl, string|nil err
function M.read(lines, o, lnum, range)
  local standalone = o.from == "csv" or o.from == "tsv"
  if standalone then
    local first, last = 1, #lines
    if range then
      first, last = range[1], range[2]
    end
    local tbl, err = registry.parse(o.from, vim.list_slice(lines, first, last))
    if not tbl then return nil, err end
    tbl.start_line, tbl.end_line = first, last
    tbl.raw_lines = vim.list_slice(lines, first, last)
    tbl.format = o.from
    return tbl, nil
  end
  local formats = o.from == "auto" and registry.embedded() or { o.from }
  local found = registry.find(lines, { formats = formats, skip_fences = true })
  for _, t in ipairs(found) do
    if range then
      if t.start_line <= range[2] and t.end_line >= range[1] then return t, nil end
    elseif lnum >= t.start_line and lnum <= t.end_line then
      return t, nil
    end
  end
  return nil, "no table found" .. (range and " in the range" or " under the cursor")
end

---Convert in `bufnr`.
---@param bufnr integer
---@param o { from: string, to: string }
---@param lnum integer
---@param range? { [1]: integer, [2]: integer }
---@return boolean ok, string|nil message, boolean|nil lossy
function M.convert(bufnr, o, lnum, range)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local tbl, err = M.read(lines, o, lnum, range)
  if not tbl then return false, err end
  if tbl.format == o.to then return false, "already " .. o.to end
  local out, werr = registry.render(o.to, tbl)
  if not out then return false, werr end
  local lost = registry.lossy(o.to, tbl)
  if o.to == "gfm" or o.to == "org" then
    local after = lines[tbl.end_line + 1]
    if tbl.format == "org" and after and after:match("^%s*#%+TBLFM") then
      lost[#lost + 1] = "the #+TBLFM formula line below the table (left in place, no longer valid)"
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, tbl.start_line - 1, tbl.end_line, false, out)
  local msg = ("%s -> %s (%d rows)"):format(tbl.format, o.to, #tbl.rows)
  if #lost > 0 then msg = msg .. "; not kept: " .. table.concat(lost, ", ") end
  return true, msg, #lost > 0
end

---`:Markdown table convert ...`
---@param argv string[]
---@param ctx? table
function M.run(argv, ctx)
  local o, err = M.parse_args(argv)
  if not o then
    notify.warn("table convert: " .. err)
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local range = (ctx and ctx.range and ctx.range > 0) and { ctx.line1, ctx.line2 } or nil
  local ok, msg, lossy = M.convert(bufnr, o, lnum, range)
  if not ok then
    notify.warn("table convert: " .. (msg or "failed"))
  elseif lossy then
    notify.warn("table convert: " .. msg)
  else
    notify.info("table convert: " .. msg)
  end
end

---@param arglead string
---@return string[]
function M.complete(arglead)
  local out = {}
  local function add(w)
    if vim.startswith(w, arglead) then out[#out + 1] = w end
  end
  add("from=auto")
  for _, f in ipairs(TARGETS) do
    add("from=" .. f)
    add("to=" .. f)
  end
  return out
end

return M
