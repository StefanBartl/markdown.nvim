---@module 'markdown.util.image_preview'
---@brief In-Neovim image preview via snacks.nvim or image.nvim (soft deps).
---@description
--- Both are optional. `detect()` reports which one is installed, and
--- `preview()` renders a file into a floating window using it. Neither is
--- required: with no provider installed the image handler keeps its previous
--- behaviour of shelling out to the system viewer, with no prompt.
---
--- The two providers need different treatment:
---
---   snacks.nvim  — `Snacks.image` hooks buffer loading for image files, so
---                  the float only has to `:edit` the path and snacks renders
---                  it. Nothing to place or clean up by hand.
---   image.nvim   — has no buffer hook; an image object is built from the
---                  file and rendered into the float's window explicitly, and
---                  must be cleared when that window closes.

local M = {}

---@alias Markdown.ImageProvider "snacks"|"image.nvim"

---Which in-Neovim preview provider is available, if any.
---
---snacks is preferred when both are installed: it renders through its own
---buffer hook, so it needs no explicit placement or teardown and degrades
---more gracefully on terminals without an image protocol.
---@return Markdown.ImageProvider|nil
function M.detect()
  local ok_snacks, snacks = pcall(require, "snacks")
  if ok_snacks and type(snacks) == "table" and snacks.image then
    return "snacks"
  end

  local ok_image = pcall(require, "image")
  if ok_image then
    return "image.nvim"
  end

  return nil
end

---Whether an in-Neovim preview is possible at all.
---@return boolean
function M.available()
  return M.detect() ~= nil
end

---Float geometry: a centred window at 80% of the editor, clamped so a very
---large or very small editor still yields something usable.
---@return table win_opts
local function float_opts()
  local width = math.max(20, math.floor(vim.o.columns * 0.8))
  local height = math.max(10, math.floor(vim.o.lines * 0.8))
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
  }
end

---Close `win` (and its buffer) on q/<Esc>, and run `on_close` when it goes.
---@param buf integer
---@param win integer
---@param on_close fun()|nil
local function wire_close(buf, win, on_close)
  local function close()
    if on_close then
      pcall(on_close)
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, close, { buffer = buf, nowait = true, silent = true })
  end

  -- Also covers the window being closed some other way (:q, <C-w>c), so an
  -- image.nvim placement is never left rendered over an unrelated buffer.
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if on_close then
        pcall(on_close)
      end
    end,
  })
end

---Preview `path` in a floating window.
---@param path string  Absolute path to an image file
---@return boolean ok
---@return string|nil err
function M.preview(path)
  local provider = M.detect()
  if not provider then
    return false, "no image preview provider installed (snacks.nvim or image.nvim)"
  end

  if provider == "snacks" then
    -- Snacks renders image files through its own buffer hook, so opening the
    -- path in the float is all that is needed.
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, float_opts())
    local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
    if not ok then
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      return false, tostring(err)
    end
    -- :edit replaced the scratch buffer with the file's own.
    wire_close(vim.api.nvim_win_get_buf(win), win, nil)
    return true
  end

  -- image.nvim: build and render explicitly, then clear on close.
  local image = require("image")
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, float_opts())

  local ok, img = pcall(image.from_file, path, {
    window = win,
    buffer = buf,
    with_virtual_padding = true,
  })

  if not ok or not img then
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    return false, ("image.nvim could not load %s: %s"):format(path, tostring(img))
  end

  local ok_render, render_err = pcall(function()
    img:render()
  end)
  if not ok_render then
    pcall(function()
      img:clear()
    end)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    return false, tostring(render_err)
  end

  wire_close(buf, win, function()
    img:clear()
  end)
  return true
end

return M
