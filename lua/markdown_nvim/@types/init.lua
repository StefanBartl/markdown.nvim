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

--- Per-binding keymap override, keyed by the ids in
--- `markdown_nvim.bindings.keymaps.defaults()`:
---   * `false`                         disable this binding
---   * `string`                        remap to a new lhs (same mode)
---   * `{ lhs?: string, mode?: string|string[] }`  remap lhs and/or mode
---@alias Mkdn.KeymapOverride boolean|string|{ lhs?: string, mode?: string|string[] }

---@class Mkdn.MenuConfig
---@field enable boolean # Provide nvzone/menu entries at all. Default true.
---@field fold boolean # Include fold/unfold entries (shown on a heading). Default true.
---@field toc boolean # Include the Insert/Refresh TOC entry. Default true.
---@field refs boolean # Include the Sync References entry. Default true.

---@class Mkdn.LinkHL
---@field underline boolean # Keep the treesitter underline on inline-link URLs/labels. Default false.

---@alias Mkdn.RefsMode "off"|"save"|"live"
---@alias Mkdn.RefsOrphans "report"|"ignore"

---@class Mkdn.RefsConfig
---@field mode Mkdn.RefsMode # Automatic sync trigger. Manual commands work regardless.
---@field debounce_ms integer # Live-mode debounce in ms (generous; 1500–3000 sane).
---@field update_toc boolean # Refresh an existing TOC block on sync (never force-creates).
---@field orphans Mkdn.RefsOrphans # Whether to report links whose #anchor matches no heading.
---@field toc_header string # TOC header line to detect/refresh.

---@class Mkdn.FeaturesConfig
---@field disable? "all"|string[] # Turn off every gateable feature ("all") or the listed ones.
---@field enable? string[] # Re-enable features (applied after `disable`).
---@field just_enable? string[] # Hard allowlist: only these features on; wins over disable/enable.

---@class Mkdn.Config
---@field features Mkdn.FeaturesConfig # Feature gating (disable/enable/just_enable). See config.features().
---@field map_double_asterisk boolean # Map `**` in visual mode to toggle bold.
---@field map_wrap_link boolean # Map `<leader>[` to wrap the word/selection in a link.
---@field keep_inner_selection boolean # After toggling bold, keep the inner text selected.
---@field protect_h1 boolean # Protect H1 from being shifted down.
---@field use_zf_override boolean # Override `zf` to fold under the cursor.
---@field enable_autocmds boolean # Install FileType autocmds (keymaps + user commands).
---@field enable_keymaps boolean # Install buffer-local keymaps (requires enable_autocmds).
---@field ft_only boolean # Only activate for markdown filetypes.
---@field ensure_headline_spacing boolean # TOC refresh also ensures `[blank]---[blank]` between H2+ sections.
---@field keymaps table<string, Mkdn.KeymapOverride> # Per-binding disable/remap by id (see markdown_nvim.bindings.keymaps.defaults()).
---@field links Mkdn.LinksConfig
---@field open Mkdn.OpenConfig
---@field blockquote_hl Mkdn.BlockquoteHL
---@field fenced_fix Mkdn.FencedFix
---@field fenced_scope Mkdn.FencedScope # Treat markdown-family fenced blocks as their own document scope.
---@field menu Mkdn.MenuConfig # nvzone/menu integration entries (opt-out).
---@field link_hl Mkdn.LinkHL # Inline-link highlight tweaks (underline on long wrapped URLs).
---@field refs Mkdn.RefsConfig # Keep `#anchor` links + TOC in sync when headings are renamed.

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
