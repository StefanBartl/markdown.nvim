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

---@class Mkdn.FencedScopeOps
---@field toc boolean # Scope TOC generation to the fenced block under the cursor.
---@field nav boolean # Scope heading navigation (next/prev, level) to the block.
---@field jump boolean # Scope anchor jump to the block.
---@field shift boolean # Scope whole-"buffer" heading shift to the block.
---@field fold boolean # Scope folding to the block (stretch; default off).

---@alias Mkdn.FencedScopeProvider "auto"|"color_my_ascii"|"builtin"

---@class Mkdn.FencedScope
---@field enable boolean # Master switch: treat markdown-family fenced blocks as their own document scope. Default true.
---@field langs string[] # Fence language tags whose blocks count as a markdown sub-document.
---@field provider Mkdn.FencedScopeProvider # Fence-detection backend. "auto" prefers color_my_ascii, falls back to the built-in scanner.
---@field operations Mkdn.FencedScopeOps # Per-operation opt-out.

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
---@field fenced_scope Mkdn.FencedScope # Treat markdown-family fenced blocks as their own document scope.

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
