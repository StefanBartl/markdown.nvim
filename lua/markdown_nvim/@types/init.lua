---@module 'markdown_nvim.types'
---@brief Central type declarations for markdown.nvim.
---@description
--- Keeps the source files free of large annotation blocks. Every type shared
--- across more than one module (or large enough to clutter its file) lives here.
--- This file intentionally returns an empty table; it exists purely for the Lua
--- language server.

-- #####################################################################
-- config/DEFAULTS.lua

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

-- #####################################################################
-- core/link_scan.lua

---@class Mkdn.Link
---@field display string # Human-readable label for pickers.
---@field target string # The resolved URL / path / anchor.
---@field text? string # Link text for `[text](target)`.
---@field kind "mdlink"|"url"
---@field lnum integer # 1-based source line.
---@field col integer # 0-based byte column of the match start.
---@field col_end integer # 0-based byte column of the match end (inclusive).
---@field file? string # Source file path (set for cross-file scans).

-- #####################################################################
-- util/picker.lua

---@class Mkdn.PickerOpts
---@field prompt? string
---@field format? fun(item: any): string
---@field backend? string

-- #####################################################################
-- util/platform.lua

---@alias Mkdn.OS "windows"|"macos"|"unix"

return {}
