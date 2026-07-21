---@module 'markdown.util.clipboard'
---@description
--- Delegates the `+` register write to `lib.nvim.cross.copy_to_clipboard`
--- when present (soft dependency, matching this repo's `util/notify.lua`
--- pattern) — that helper additionally covers the OS-tool fallback chain
--- (pbcopy/clip.exe/wl-copy/xclip/xsel/WSL) when Neovim's own `+` register
--- write fails, which the previous bare `setreg` call never attempted.
--- The `*` (selection) register is always set locally too, since the shared
--- helper only targets `+`.

local M = {}

---@param text string
function M.copy(text)
  local ok, copy_to_clipboard = pcall(require, "lib.nvim.cross.copy_to_clipboard")
  if ok and type(copy_to_clipboard) == "function" then
    copy_to_clipboard(text)
  else
    vim.fn.setreg("+", text)
  end
  vim.fn.setreg("*", text)
end

return M
