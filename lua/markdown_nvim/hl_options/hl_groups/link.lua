---@module 'markdown_nvim.hl_options.hl_groups.link'
---@brief Tame the underline on inline-link URLs/labels.
---@description
--- Neovim's built-in markdown treesitter highlights render `@markup.link.url`
--- (and often the label) with `underline = true`. When a link's URL is long and
--- the line soft-wraps, that underline runs the full width of the next screen
--- row — the "langer Unterstrich" artifact. We override ONLY the markdown-inline
--- language-scoped groups (`…​.markdown_inline`), so other filetypes keep their
--- own link styling. Colour is preserved; only underline/undercurl are dropped
--- (configurable via `opts.link_hl.underline`).

local M = {}

-- Language-scoped capture groups used by the markdown_inline parser. Overriding
-- these leaves the generic `@markup.link.*` (and every other language) untouched.
local GROUPS = {
  "@markup.link.url.markdown_inline",
  "@markup.link.label.markdown_inline",
}

--- Re-derive each group from its generic base and strip the underline.
---@param opts table  Resolved markdown.nvim config (reads opts.link_hl).
function M.apply(opts)
  opts = opts or {}
  local link_hl = opts.link_hl or {}
  -- Default: remove underline. Set link_hl.underline = true to keep it.
  local want_underline = link_hl.underline == true

  for _, group in ipairs(GROUPS) do
    -- Resolve the *generic* base (e.g. @markup.link.url) so we inherit the
    -- colorscheme's colour, then clear the underline attributes.
    local base_name = group:gsub("%.markdown_inline$", "")
    local base = vim.api.nvim_get_hl(0, { name = base_name, link = false })
    if type(base) ~= "table" then base = {} end

    base.underline = want_underline
    base.undercurl = false
    vim.api.nvim_set_hl(0, group, base)
  end
end

return M
