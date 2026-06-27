---@module 'markdown_nvim.config'
local M = {}

---@class Mkdn.Config
local DEFAULTS = {
  map_double_asterisk    = true,
  keep_inner_selection   = true,
  protect_h1             = false,
  use_zf_override        = true,
  enable_autocmds        = true,
  enable_keymaps         = true,
  ft_only                = true,
  ensure_headline_spacing = true,

  -- `:Markdown links show` picker backend: "hover_select" | "select"
  -- ("select" uses vim.ui.select; telescope/fzf can be added later).
  links = {
    picker = "hover_select",
  },

  blockquote_hl = {
    marker_fg  = "#6A9955",
    text_fg    = "#7EE787",
    text_bold  = true,
    text_italic = false,
  },

  fenced_fix = {
    inline_base_hl = { "DiagnosticWarn", "Special", "Constant", "String" },
    inline_style   = { italic = false, bold = false },
    delimiter_hl   = "Comment",
  },
}

local _cfg = vim.deepcopy(DEFAULTS)

---@param opts Mkdn.Config|nil
function M.setup(opts)
  _cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
end

---@return Mkdn.Config
function M.get()
  return _cfg
end

return M
