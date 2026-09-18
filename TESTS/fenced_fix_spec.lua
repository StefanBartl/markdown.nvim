-- TESTS/fenced_fix_spec.lua — fenced_fix: re-applies a small cascade of
-- highlight-group overrides for fenced code (legacy + treesitter groups),
-- re-run on ColorScheme. Covers M.apply()'s branching and M.setup()'s
-- opts-merge; the augroup registration itself already uses the safe
-- raw-nvim_create_augroup(clear=true) pattern (see scope_spec.lua for the
-- regression this repo has of the OTHER, unsafe form).

return function(H)
  local eq, ok = H.eq, H.ok
  local fenced_fix = require("markdown.fenced_fix")

  ---@param name string
  ---@return table
  local function hl(name) return vim.api.nvim_get_hl(0, { name = name, link = true }) end

  -- Reset to documented defaults before each block below (M.opts is shared
  -- module state, mutated in place by M.setup).
  local function reset_opts()
    fenced_fix.opts.inline_base_hl = { "DiagnosticWarn", "Special", "Constant", "String" }
    fenced_fix.opts.inline_style = { bold = false, italic = false }
    fenced_fix.opts.delimiter_hl = "Comment"
    fenced_fix.opts.enable_legacy = true
    fenced_fix.opts.enable_ts = true
  end

  -- ── Default M.apply(): both legacy and treesitter groups are set. ──
  do
    reset_opts()
    fenced_fix.apply()

    ok(vim.tbl_isempty(hl("markdownCode")), "apply: legacy markdownCode is cleared")
    eq(hl("markdownCodeDelimiter").link, "Comment", "apply: legacy delimiter links to delimiter_hl")

    eq(hl("@markup.raw.block").link, "Normal", "apply: ts block group links to Normal")
    eq(
      hl("@markup.fenced_code.block").link,
      "Normal",
      "apply: ts fenced_code group links to Normal"
    )

    -- DiagnosticWarn has a real fg in a bare headless session, and the
    -- default inline_style table is non-empty (bold=false, italic=false are
    -- still keys), so MarkdownInlineCode gets built as a direct color+style
    -- override rather than a plain link.
    local inline = vim.api.nvim_get_hl(0, { name = "MarkdownInlineCode" })
    local warn_fg = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn" }).fg
    eq(inline.fg, warn_fg, "apply: MarkdownInlineCode inherits its base group's fg")
    eq(inline.link, nil, "apply: MarkdownInlineCode is a direct override, not a link, here")

    eq(
      hl("@markup.raw.inline").link,
      "MarkdownInlineCode",
      "apply: inline code groups link to MarkdownInlineCode"
    )
    eq(
      hl("@markup.raw.delimiter").link,
      "Comment",
      "apply: raw delimiter group links to delimiter_hl"
    )
  end

  -- ── enable_legacy = false: legacy groups are left alone. ──
  do
    reset_opts()
    -- Give markdownCode a distinctive marker first so "untouched" is checkable.
    vim.api.nvim_set_hl(0, "markdownCode", { link = "Comment" })
    fenced_fix.opts.enable_legacy = false
    fenced_fix.apply()
    eq(hl("markdownCode").link, "Comment", "apply: enable_legacy=false leaves markdownCode alone")
  end

  -- ── enable_ts = false: treesitter groups are left alone. ──
  do
    reset_opts()
    vim.api.nvim_set_hl(0, "@markup.raw.block", { link = "Comment" })
    fenced_fix.opts.enable_ts = false
    fenced_fix.apply()
    eq(
      hl("@markup.raw.block").link,
      "Comment",
      "apply: enable_ts=false leaves @markup.raw.block alone"
    )
  end

  -- ── Custom delimiter_hl is honored throughout. ──
  do
    reset_opts()
    fenced_fix.opts.delimiter_hl = "WarningMsg"
    fenced_fix.apply()
    eq(
      hl("markdownCodeDelimiter").link,
      "WarningMsg",
      "apply: custom delimiter_hl reaches the legacy delimiter group"
    )
    eq(
      hl("@markup.raw.delimiter").link,
      "WarningMsg",
      "apply: custom delimiter_hl reaches the ts delimiter group too"
    )
  end

  -- ── M.setup(opts): merges into M.opts and immediately re-applies. ──
  do
    reset_opts()
    fenced_fix.setup({ delimiter_hl = "ErrorMsg", enable_legacy = false })
    eq(fenced_fix.opts.delimiter_hl, "ErrorMsg", "setup: opts merged into M.opts")
    eq(fenced_fix.opts.enable_legacy, false, "setup: boolean override merged too")
    ok(fenced_fix.opts.enable_ts, "setup: unspecified keys keep their previous value")
    eq(
      hl("@markup.raw.delimiter").link,
      "ErrorMsg",
      "setup: apply() actually ran with the merged opts"
    )
  end

  reset_opts()
  fenced_fix.apply()
end
