---@module 'markdown.types'
---@brief Central type declarations for markdown.nvim.
---@description
--- Keeps the source files free of large annotation blocks. Every type shared
--- across more than one module (or large enough to clutter its file) lives here.
--- This file intentionally returns an empty table; it exists purely for the Lua
--- language server.

-- #####################################################################
-- config/DEFAULTS.lua

---@alias Mkdn.LinkPicker "hover_select"|"select"|"telescope"|"fzf"

---@alias Mkdn.LinkDiagnosticsMode "off"|"save"

---@class Mkdn.LinkDiagnosticsConfig
---@field mode Mkdn.LinkDiagnosticsMode # "off" (manual `:Markdown links check` only) | "save" (also rerun on BufWritePost). Default "off".

---@class Mkdn.LinksConfig
---@field picker Mkdn.LinkPicker # `:Markdown links show` picker backend.
---@field diagnostics Mkdn.LinkDiagnosticsConfig # Dead-link / duplicate-anchor checking (see `core.link_diagnostics`).
---@field sanitize_on_save boolean # Run `:Markdown links sanitize` on the buffer before every write. Default true.

---@class Mkdn.ListConfig
---@field picker Mkdn.LinkPicker # `:Markdown list` picker backend (same vocabulary as `links.picker`).

---@class Mkdn.OpenConfig
---@field external_extensions string[] # Extensions launched with the system app; others open via `:edit`.

-- hover/*.lua
--
-- The hover framework moved to `lib.nvim.hover`; its internal types live
-- there as `Lib.Hover.*`. What stays here is the plugin-facing config block,
-- which markdown.nvim owns and hands to `lib.nvim.hover.setup`.

---@alias Mkdn.HoverTrigger Lib.HoverTrigger
---@alias Mkdn.HoverUrlConfig Lib.HoverUrlConfig
---@alias Mkdn.HoverConfig Lib.HoverConfig

---@class Mkdn.BlockquoteHL
---@field marker_fg? string # Color for the `>` marker token. Unset: derived from the active colorscheme.
---@field text_fg? string # Color for the text after `>`. Unset: derived from the active colorscheme.
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
--- `markdown.bindings.keymaps.defaults()` and
--- `markdown.bindings.keymaps.tableview_defaults()`:
---   * `false`                         disable this binding
---   * `string`                        remap to a new lhs (same mode)
---   * `string[]`                      several keys for the same action
---   * `{ lhs?: string, mode?: string|string[] }`  remap lhs and/or mode
---
--- An id that matches no binding is reported (with its nearest match) rather
--- than silently ignored.
---@alias Mkdn.KeymapOverride boolean|string|string[]|{ lhs?: string, mode?: string|string[] }

---@alias Mkdn.TableAlign "left"|"center"|"right"

---@class Mkdn.TableColOverride
---@field col integer|string # 1-based column index, or a header-cell name (case-insensitive).
---@field align? Mkdn.TableAlign
---@field max? integer # Width-limited wrapping: per-column max width override.
---@field min? integer # Width-limited wrapping: per-column min width override.

---@class Mkdn.TableWrapConfig
---@field enabled boolean # When true, plain `:Markdown table format`/table mode also wrap. Default false.
---@field auto boolean # Fit column widths to the window instead of a fixed `max`. Default false.
---@field min integer # Minimum column width (chars). Default 3.
---@field max? integer # Maximum column width; nil = unlimited (still capped by `auto`).
---@field pad integer # Cell padding (spaces each side of content). Default 1.
---@field join string # `:MDTableUnwrap` continuation-cell join separator (" " or "<br>"). Default " ".
---@field soft_break_chars string # Extra break points, in addition to whitespace.
---@field continuation_marker string # Virtual-text gutter hint on continuation rows. Default "↳".
---@field flavor "github"|"loose" # "github": strict GFM (min 3 dashes, spaced separator). Default "github".
---@field auto_resize boolean # Debounced reflow of auto-mode tables on VimResized/WinResized. Default false.
---@field resize_debounce_ms integer # Default 300.
---@field selective_reflow boolean # BufWritePre: only reflow tables that actually changed. Default false.

---@class Mkdn.TableConfig
---@field header_align Mkdn.TableAlign # Default header-row alignment for `:Markdown table format`.
---@field entry_align Mkdn.TableAlign # Default body-row alignment.
---@field col_overrides? Mkdn.TableColOverride[] # Per-column alignment overrides applied on every format.
---@field wrap Mkdn.TableWrapConfig # Width-limited wrapping (`:MDTable*` commands).
---@field wrap_profiles table<string, table> # Named wrap-opt presets for `:MDTableProfile`.

---@class Mkdn.TableViewConfig
---@field style "markdown"|"box" # Default float style for `view toggle` / <leader>tvt.

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
---@field toc_header? string # TOC header line to detect/refresh. Unset falls back to `toc.header`.

---@alias Mkdn.AnchorStyle "gfm"|"keep-case"

--- What `mi` does with an image when an in-Neovim preview provider
--- (snacks.nvim or image.nvim) is installed. With neither installed, every
--- value behaves like "system".
---@alias Mkdn.ImagePreviewMode "ask"|"preview"|"system"

--- Which in-Neovim image preview provider was detected, if any.
---@alias Mkdn.ImageProvider "snacks"|"image.nvim"

---@class Mkdn.ImageConfig
---@field preview Mkdn.ImagePreviewMode # System viewer vs. in-Neovim float. Default "ask".

---@class Mkdn.UnderlineHeadingsConfig
---@field char string # Underline character drawn below each ATX heading's text. Default "=".

---@class Mkdn.TocConfig
---@field header string # TOC header line, e.g. "## Table of content".
---@field marker string # Bullet marker prefix for each TOC entry (e.g. "-" or "*").
---@field min_level integer # Default lowest heading level included.
---@field max_level integer # Default highest heading level included.
---@field anchor_style Mkdn.AnchorStyle # Slug style; shared with core.refs so anchors stay in sync. Default "gfm".
---@field anchor_separator string # Word separator in generated anchors. Default "-".

---@class Mkdn.FeaturesConfig
---@field disable? "all"|string[] # Turn off every gateable feature ("all") or the listed ones.
---@field enable? string[] # Re-enable features (applied after `disable`).
---@field just_enable? string[] # Hard allowlist: only these features on; wins over disable/enable.

---@class Mkdn.Config
---@field features? Mkdn.FeaturesConfig # Feature gating (disable/enable/just_enable). See config.features().
---@field map_double_asterisk? boolean # Map `**` in visual mode to toggle bold.
---@field map_wrap_link? boolean # Map `<leader>[` to wrap the word/selection in a link.
---@field keep_inner_selection? boolean # After toggling bold, keep the inner text selected.
---@field protect_h1? boolean # Protect H1 from being shifted down.
---@field use_zf_override? boolean # Override `zf` to fold under the cursor.
---@field enable_autocmds? boolean # Install FileType autocmds (keymaps + user commands).
---@field enable_keymaps? boolean # Install buffer-local keymaps (requires enable_autocmds).
---@field ft_only? boolean # Only activate for markdown filetypes.
---@field ensure_headline_spacing? boolean # TOC refresh also ensures `[blank]---[blank]` between H2+ sections.
---@field underline_headings? Mkdn.UnderlineHeadingsConfig # `:MarkdownNvimUnderlineHeadings` underline character.
---@field check_heading_gaps? boolean # TOC refresh also reports skipped heading levels (e.g. H1 -> H3) and offers to fix them.
---@field keymaps? table<string, Mkdn.KeymapOverride> # Per-binding disable/remap by id (see markdown.bindings.keymaps.defaults()).
---@field links? Mkdn.LinksConfig
---@field list? Mkdn.ListConfig # `:Markdown list` picker backend.
---@field hover? Mkdn.HoverConfig # Link-target preview under the cursor (see `markdown.hover`).
---@field image? Mkdn.ImageConfig # Following an image target: system viewer vs. in-Neovim preview.
---@field open? Mkdn.OpenConfig
---@field blockquote_hl? Mkdn.BlockquoteHL
---@field fenced_fix? Mkdn.FencedFix
---@field fenced_scope? Mkdn.FencedScope # Treat markdown-family fenced blocks as their own document scope.
---@field tableview? Mkdn.TableViewConfig # Default TableView float style ("markdown" | "box").
---@field menu? Mkdn.MenuConfig # nvzone/menu integration entries (opt-out).
---@field link_hl? Mkdn.LinkHL # Inline-link highlight tweaks (underline on long wrapped URLs).
---@field refs? Mkdn.RefsConfig # Keep `#anchor` links + TOC in sync when headings are renamed.
---@field toc? Mkdn.TocConfig # TOC header/marker/level defaults for `<leader>toc` / `:Markdown toc`.
---@field table? Mkdn.TableConfig # Default alignment/overrides for `:Markdown table format`.

-- #####################################################################
-- core/link_scan.lua

---@class Mkdn.Link
---@field display string # Human-readable label for pickers.
---@field target string # The resolved URL / path / anchor.
---@field text? string # Link text for `[text](target)`, `alt` for `<img>`, the `<figcaption>` for a figure.
---@field kind "mdlink"|"url"|"html_media"|"html_link" # `html_*` come from `core.html_links`.
---@field lnum integer # 1-based source line.
---@field col integer # 0-based byte column of the match start.
---@field col_end integer # 0-based byte column of the match end (inclusive).
---@field file? string # Source file path (set for cross-file scans).

-- #####################################################################
-- core/heading_scan.lua

---@class Mkdn.Heading
---@field level integer # 1-6, the number of leading `#`.
---@field title string # Heading text with the `#`s and surrounding space stripped.
---@field lnum integer # 1-based source line.
---@field file? string # Source file path (set for file/cwd scans, absent for buffer scans).

--- One `vim.diagnostic`-shaped entry from `core.link_diagnostics.collect()`.
---@class Mkdn.LinkDiagnostic
---@field lnum integer # 0-based line.
---@field col integer # 0-based start column.
---@field end_col integer # 0-based end column.
---@field severity integer # `vim.diagnostic.severity.*`.
---@field message string
---@field source "markdown_links"

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
