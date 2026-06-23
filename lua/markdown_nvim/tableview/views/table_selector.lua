---@module 'markdown_nvim.tableview.views.table_selector'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.tableview.views.table_selector]")

local api = vim.api
local ui = require("markdown_nvim.tableview.renderer")

local function set_buf_opt(buf, name, value)
  pcall(api.nvim_set_option_value, name, value, { scope = "local", buf = buf })
end

local function set_win_opt(win, name, value)
  pcall(api.nvim_set_option_value, name, value, { scope = "local", win = win })
end

return function(tables)
  if not tables or #tables == 0 then return end

  local lines = {}
  for i, t in ipairs(tables) do
    local headers = {}
    if t.header and t.header.cells then
      for _, c in ipairs(t.header.cells) do
        table.insert(headers, c.content or "")
      end
    end
    local header_preview = (#headers > 0) and table.concat(headers, ", ") or ("Table@" .. tostring(t.start_line))
    table.insert(lines, string.format("%d: col %d; %s (%d rows)", i, t.start_line or 0, header_preview, #t.rows))
  end

  local sel_buf = api.nvim_create_buf(false, true)
  if not sel_buf then
    notify.error("Failed to create selector buffer")
    return
  end

  api.nvim_buf_set_lines(sel_buf, 0, -1, false, lines)
  set_buf_opt(sel_buf, "bufhidden", "wipe")
  set_buf_opt(sel_buf, "buftype", "nofile")
  set_buf_opt(sel_buf, "modifiable", false)
  set_buf_opt(sel_buf, "filetype", "markdown")

  local maxlen = 0
  for _, l in ipairs(lines) do
    local ln = vim.fn.strdisplaywidth(l)
    if ln > maxlen then maxlen = ln end
  end
  local width = math.min(maxlen + 4, vim.o.columns - 10)
  local height = math.min(#lines, math.max(6, math.floor(vim.o.lines * 0.4)))

  local win_opts = {
    relative = "editor",
    width    = width,
    height   = height,
    col      = math.floor((vim.o.columns - width) / 2),
    row      = math.floor((vim.o.lines - height) / 2),
    style    = "minimal",
    border   = "rounded",
  }

  local sel_win = api.nvim_open_win(sel_buf, true, win_opts)
  if not sel_win then
    notify.error("Failed to open selector window")
    pcall(api.nvim_buf_delete, sel_buf, { force = true })
    return
  end

  set_win_opt(sel_win, "cursorline", true)
  set_win_opt(sel_win, "wrap", false)
  set_win_opt(sel_win, "number", false)
  set_win_opt(sel_win, "relativenumber", false)

  local function close_selector()
    if sel_win and api.nvim_win_is_valid(sel_win) then
      pcall(api.nvim_win_close, sel_win, true)
    end
    if sel_buf and api.nvim_buf_is_valid(sel_buf) then
      pcall(api.nvim_buf_delete, sel_buf, { force = true })
    end
  end

  api.nvim_buf_set_keymap(sel_buf, "n", "<CR>", "", {
    nowait = true, noremap = true, silent = true,
    callback = function()
      local r = api.nvim_win_get_cursor(sel_win)[1]
      if r < 1 or r > #tables then
        notify.warn("Invalid selection")
        return
      end
      local sel = tables[r]
      close_selector()
      ui.render_table(sel, { floating = true })
    end,
  })

  for _, key in ipairs({ "q", "<Esc>" }) do
    api.nvim_buf_set_keymap(sel_buf, "n", key, "", {
      nowait = true, noremap = true, silent = true,
      callback = function() close_selector() end,
    })
  end

  api.nvim_win_set_cursor(sel_win, { 1, 0 })
end
