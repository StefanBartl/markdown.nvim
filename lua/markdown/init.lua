---@module 'markdown'
--- markdown.nvim — a self-contained Markdown toolkit for Neovim.
--- Contains: heading navigation/shift, TOC, folding, bold wrap,
--- blockquote HL, fenced-code fix, anchor/url/image handler,
--- table viewer, and :Markdown commands.
local M = {}

local _setup_done = false

---@param opts Mkdn.Config|nil
function M.setup(opts)
  if _setup_done then return end
  _setup_done = true

  local cfg_mod = require("markdown.config")
  cfg_mod.setup(opts or {})
  local cfg = cfg_mod.get()

  -- HL options (blockquote + link_hl + ColorScheme). Each part is gated
  -- internally by its feature ("hl" / "link_hl").
  if cfg_mod.feature_enabled("hl") or cfg_mod.feature_enabled("link_hl") then
    require("markdown.hl_options").setup(cfg)
  end

  -- Fenced-code fix (inline code / fenced block highlights)
  if cfg_mod.feature_enabled("fenced_fix") then
    local ff_opts = cfg.fenced_fix or {}
    require("markdown.fenced_fix").setup(ff_opts)
  end

  -- Handler-local settings that are user-configurable. The handlers keep
  -- their own `M.config` defaults so they stay usable standalone (and so a
  -- direct `require(...).config.x = y` still works); this only overrides the
  -- keys the central config actually surfaces.
  if type(cfg.image) == "table" and cfg.image.preview ~= nil then
    require("markdown.handler.image").config.preview = cfg.image.preview
  end

  -- All keymaps, user commands and autocmds (see markdown.bindings).
  require("markdown.bindings").setup(cfg)
end

-- Public façade -----------------------------------------------------------

--- Named editing actions for manual remapping (no `<Plug>` layer). E.g.:
---   vim.keymap.set("n", "<F2>", require("markdown").actions.fold_toggle,
---     { buffer = true, desc = "Fold toggle" })
M.actions = setmetatable({}, {
  __index = function(_, k) return require("markdown.bindings.actions")[k] end,
})

M.foldexpr = function(lnum) return require("markdown.core.fold").foldexpr(lnum) end
M.goto_prev_heading = function() require("markdown.core.headings").goto_prev_heading() end
M.goto_next_heading = function() require("markdown.core.headings").goto_next_heading() end
M.toggle_visual_bold = function() require("markdown.core.wrap").toggle_visual_bold() end

M.update_toc = function(header, opts) require("markdown.core.toc").update_markdown_toc(header, opts) end

M.handle_cursor_action = function() require("markdown.handler").handle_cursor_action() end

---Preview the link target under the cursor in a float. Normally triggered by
---the `hover` autocmds; call it directly for an on-demand hover (a keymap,
---say), which bypasses the enabled flag.
---@return boolean shown
M.hover = function() return require("markdown.hover").show({ force = true }) end

---Close an open hover preview.
M.hover_hide = function() require("markdown.hover").hide() end

---Apply H2-level blank-line separators to the current (or given) buffer.
---@param bufnr? integer  defaults to current buffer
---@param opts?  { notify?: boolean }
M.apply_headline_separators = function(bufnr, opts)
  require("markdown.core.headline_spacing").apply_headl_separators(
    bufnr or vim.api.nvim_get_current_buf(),
    opts or { notify = true }
  )
end

---Find every markdown file under `opts.root` (default cwd) that links to
---`target_path`. Read-only — pure search, does not touch buffers or files.
---Uses a ripgrep prefilter when available for speed.
---@param target_path string  Absolute filesystem path to search for.
---@param opts? { root?: string }
---@return MarkdownFileRef[]
M.find_references = function(target_path, opts)
  return require("markdown.core.file_refs").find_references(target_path, opts)
end

---Async variant of `find_references`: runs candidate discovery off the main
---loop; `callback` receives the ref list, scheduled on the main loop.
---@param target_path string
---@param opts? { root?: string }
---@param callback fun(refs: MarkdownFileRef[])
M.find_references_async = function(target_path, opts, callback)
  return require("markdown.core.file_refs").find_references_async(target_path, opts, callback)
end

---Re-express a moved/renamed target in the same style a found ref used
---(absolute stays absolute, `./x` → `./y`, `docs/x` → `docs/y`). For callers
---rewriting links after a rename/move.
---@param ref MarkdownFileRef
---@param new_abs_path string
---@return string
M.retarget = function(ref, new_abs_path)
  return require("markdown.core.file_refs").retarget(ref, new_abs_path)
end

return M
