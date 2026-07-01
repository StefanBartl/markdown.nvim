---@module 'markdown_nvim.config.DEFAULTS'
---@brief Immutable default configuration for markdown.nvim.
---@description
--- Single source of truth for every configurable value. `markdown_nvim.config`
--- deep-merges user options on top of this table. Never mutate it at runtime.

---@alias Mkdn.LinkPicker "hover_select"|"select"

---@class Mkdn.LinksConfig
---@field picker Mkdn.LinkPicker # `:Markdown links show` picker backend.

---@class Mkdn.OpenConfig
---@field external_extensions string[] # Extensions launched with the system app; others open via `:edit`.

---@class Mkdn.BlockquoteHL
---@field marker_fg string # Color for the `>` marker token.
---@field text_fg string # Color for the text after `>`.
---@field text_bold boolean
---@field text_italic boolean

---@class Mkdn.FencedFixStyle
---@field italic boolean
---@field bold boolean

---@class Mkdn.FencedFix
---@field inline_base_hl string[] # Candidate highlight groups for inline `code` (first that exists wins).
---@field inline_style Mkdn.FencedFixStyle # Extra style flags for inline code.
---@field delimiter_hl string # Highlight group for the backtick delimiters (`` ` ``).

---@class Mkdn.Config
---@field map_double_asterisk boolean # Map `**` in visual mode to toggle bold.
---@field map_wrap_link boolean # Map `<leader>[` to wrap the word/selection in a link.
---@field keep_inner_selection boolean # After toggling bold, keep the inner text selected.
---@field protect_h1 boolean # Protect H1 from being shifted down.
---@field use_zf_override boolean # Override `zf` to fold under the cursor.
---@field enable_autocmds boolean # Install FileType autocmds (keymaps + user commands).
---@field enable_keymaps boolean # Install buffer-local keymaps (requires enable_autocmds).
---@field ft_only boolean # Only activate for markdown filetypes.
---@field ensure_headline_spacing boolean # TOC refresh also ensures `[blank]---[blank]` between H2+ sections.
---@field links Mkdn.LinksConfig
---@field open Mkdn.OpenConfig
---@field blockquote_hl Mkdn.BlockquoteHL
---@field fenced_fix Mkdn.FencedFix

---@type Mkdn.Config
local DEFAULTS = {
  map_double_asterisk    = true,
  map_wrap_link          = true,
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

return DEFAULTS
