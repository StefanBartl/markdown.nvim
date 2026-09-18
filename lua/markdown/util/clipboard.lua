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
---@return boolean ok  whether `text` actually reached the "+" register --
---  false when there is no clipboard provider and no external tool (the
---  "*" register is still set either way, see below)
function M.copy(text)
  local ok, copy_to_clipboard = pcall(require, "lib.nvim.cross.copy_to_clipboard")
  local copied
  if ok and type(copy_to_clipboard) == "function" then
    copied = copy_to_clipboard(text)
  else
    -- No lib.nvim: the same round-trip check it does internally -- a bare
    -- `setreg` succeeding is not proof of anything without a provider.
    copied = false
    if pcall(vim.fn.setreg, "+", text) then
      local get_ok, got = pcall(vim.fn.getreg, "+")
      copied = get_ok and got == text
    end
  end
  vim.fn.setreg("*", text)
  return copied
end

return M
