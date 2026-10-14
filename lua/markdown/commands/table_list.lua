---@module 'markdown.commands.table_list'
---@brief `:Markdown table list [scope=...] [style=...]` -- the tables of a scope in a picker.
---@description
--- Every GFM table of the scope is one entry (`file:line  header  (n rows)`).
--- With pickers.nvim the preview window switches between the file around the
--- table ("normal") and the table alone, formatted ("table"), with `<M-t>`;
--- without it the entries go through the built-in chooser. Choosing an entry
--- jumps to the table.
---
--- Scope: `%` / `buffer` (default), `cwd`, `cfile`, or a file / directory;
--- `scope=` is optional, a bare value works as well.

local notify = require("markdown.util.notify").create("[markdown.commands.table_list]")
local parser = require("markdown.tableview.parser")

local M = {}

---@internal
---@return Mkdn.TableListConfig
local function cfg()
  local ok, config = pcall(require, "markdown.config")
  local t = ok and config.get().table or {}
  return vim.tbl_extend("force", { picker = "auto", style = "grid" }, t.list or {})
end

---Split the arguments: `scope=X` or a bare X is the scope, `style=` the preview style.
---@param argv string[]
---@return { scope?: string, style?: string }|nil opts
---@return string|nil err
function M.parse_args(argv)
  local opts = {}
  for _, a in ipairs(argv or {}) do
    local key, val = a:match("^(%w+)=(.*)$")
    if key == "scope" then
      opts.scope = val
    elseif key == "style" then
      if val ~= "grid" and val ~= "markdown" then return nil, "style must be grid or markdown" end
      opts.style = val
    elseif key then
      return nil, "unknown option '" .. key .. "='"
    elseif opts.scope == nil then
      opts.scope = a
    else
      return nil, "unexpected argument '" .. a .. "'"
    end
  end
  return opts, nil
end

---@internal
---@param lines string[]
---@param style string
---@return string[]
local function table_only(lines, style)
  if style == "markdown" then
    local out = require("lib.nvim.markdown.table").format_lines(lines)
    return out
  end
  return require("markdown.core.table_render").to_lines(lines)
end

---@internal
---One entry of the picker for table `t` of `name` (`bufnr` set for a buffer).
---@param t table  # from tableview.parser
---@param name string
---@param style string
---@param bufnr integer|nil
---@param buf_lines string[]|nil  # the buffer's current lines (an unsaved buffer previews these)
---@return table item
local function make_item(t, name, style, bufnr, buf_lines)
  local heads = {}
  for _, c in ipairs((t.header and t.header.cells) or {}) do
    heads[#heads + 1] = vim.trim(c.content or "")
  end
  local shown = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]"
  local text = ("%s:%d  %s  (%d rows)"):format(
    shown,
    t.start_line,
    table.concat(heads, " | "),
    #t.rows
  )

  local normal
  if bufnr and (vim.bo[bufnr].modified or name == "" or vim.fn.filereadable(name) == 0) then
    -- Not on disk as shown: preview the buffer's own text.
    normal = { lines = buf_lines, ft = "markdown", line = t.start_line }
  else
    normal = { file = name, line = t.start_line }
  end
  return {
    text = text,
    file = normal.file,
    line = t.start_line,
    previews = {
      normal = normal,
      table = {
        lines = table_only(t.raw_lines, style),
        ft = style == "markdown" and "markdown" or "",
      },
    },
    path = name,
    bufnr = bufnr,
    start_line = t.start_line,
    end_line = t.end_line,
  }
end

---Every table of `scope` as picker entries.
---@param scope string|nil
---@param style? string
---@return table[]|nil items
---@return string|nil err
function M.collect(scope, style)
  style = style or cfg().style
  local res, err = require("markdown.util.scope").resolve(scope)
  if not res then return nil, err end

  local items = {}
  if res.kind == "buffer" then
    local bufnr = res.bufnr
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local name = vim.api.nvim_buf_get_name(bufnr)
    for _, t in ipairs(parser.get_tables(bufnr)) do
      items[#items + 1] = make_item(t, name, style, bufnr, lines)
    end
  else
    for _, path in ipairs(res.paths or {}) do
      for _, t in ipairs(parser.get_tables_from_file(path)) do
        items[#items + 1] = make_item(t, path, style, nil, nil)
      end
    end
  end
  if #items == 0 then return nil, "no tables found" end
  return items, nil
end

---Jump to the table of `item`.
---@param item table
function M.open(item)
  if item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr) then
    vim.api.nvim_set_current_buf(item.bufnr)
  elseif item.path and item.path ~= "" then
    vim.cmd.edit(vim.fn.fnameescape(item.path))
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { item.start_line, 0 })
  vim.cmd("normal! zz")
end

---pickers.nvim's engine when it can show switchable previews, else nil.
---@internal
---@return table|nil engine
local function pickers_engine()
  if cfg().picker == "builtin" then return nil end
  if not pcall(require, "pickers.preview_modes") then return nil end -- an older pickers.nvim
  local ok, engines = pcall(require, "pickers.engines")
  if not ok then return nil end
  local engine = engines.load()
  return (engine and engine.pick_item) and engine or nil
end

---Show `items` in a picker; `on_choose` gets the chosen one.
---@param items table[]
---@param on_choose fun(item: table)
function M.pick(items, on_choose)
  local engine = pickers_engine()
  if engine then
    engine.pick_item({
      prompt = "Markdown tables",
      items = items,
      preview_modes = { "normal", "table" },
      on_select = on_choose,
    })
    return
  end
  require("markdown.util.picker").select(items, {
    prompt = "Markdown tables",
    format = function(it) return it.text end,
    backend = (require("markdown.config").get().links or {}).picker or "hover_select",
  }, on_choose)
end

---`:Markdown table list [scope=...] [style=...]`
---@param argv string[]
function M.run(argv)
  local opts, err = M.parse_args(argv)
  if not opts then
    notify.warn("table list: " .. err)
    return
  end
  local items, cerr = M.collect(opts.scope, opts.style)
  if not items then
    notify.info("table list: " .. (cerr or "nothing to show"))
    return
  end
  M.pick(items, M.open)
end

return M
