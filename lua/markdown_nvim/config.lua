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

  -- How followed file targets open. Media/binary extensions launch the system
  -- application; everything else (text-like) opens in the current window via
  -- :edit. Extend this list to taste.
  open = {
    external_extensions = {
      "png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "ico", "tif", "tiff",
      "pdf",
      "mp4", "mkv", "mov", "avi", "webm", "wmv", "flv",
      "mp3", "wav", "flac", "ogg", "m4a",
      "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp",
      "zip", "tar", "gz", "tgz", "7z", "rar",
      "exe", "msi", "dmg", "app",
    },
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
