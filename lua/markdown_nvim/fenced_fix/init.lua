---@module 'markdown_nvim.fenced_fix'
local notify = require("markdown_nvim.util.notify").create("[markdown_nvim.fenced_fix]")
local autocmd = require("lib.nvim.autocmd")

local M = {}

M.opts = {
  inline_base_hl = { "DiagnosticWarn", "Special", "Constant", "String" },
  inline_style   = { bold = false, italic = false },
  delimiter_hl   = "Comment",
  enable_legacy  = true,
  enable_ts      = true,
}

local function safe_set(name, target)
  local ok, err = pcall(function()
    if type(target) == "string" then
      vim.api.nvim_set_hl(0, name, { link = target })
    else
      vim.api.nvim_set_hl(0, name, target or {})
    end
  end)
  if not ok then
    vim.schedule(function()
      notify.debug(("fenced_fix: failed to set %s: %s"):format(name, err))
    end)
  end
end

local function safe_clear(name)
  pcall(vim.api.nvim_set_hl, 0, name, {})
end

local function set_many(names, target)
  for _, n in ipairs(names) do safe_set(n, target) end
end

local function get_hl(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = true })
  if ok and type(hl) == "table" then return hl end
  return nil
end

local function first_existing_hl(candidates)
  for _, n in ipairs(candidates) do
    if get_hl(n) then return n end
  end
  return nil
end

function M.apply()
  local o = M.opts

  if o.enable_legacy then
    safe_clear("markdownCode")
    safe_set("markdownCodeDelimiter", o.delimiter_hl)
  end

  if o.enable_ts then
    safe_clear("@markup.raw")

    set_many({
      "@markup.raw.block",
      "@markup.fenced_code.block",
    }, "Normal")

    local base = first_existing_hl(o.inline_base_hl) or "Special"
    local style = o.inline_style or {}
    local base_hl = get_hl(base) or {}

    if (base_hl.fg or base_hl.bg) and next(style) ~= nil then
      safe_set("MarkdownInlineCode", {
        fg        = base_hl.fg,
        bg        = base_hl.bg,
        bold      = style.bold,
        italic    = style.italic,
        underline  = style.underline,
        undercurl  = style.undercurl,
      })
    else
      safe_set("MarkdownInlineCode", base)
    end

    set_many({
      "@markup.raw.inline",
      "@markup.raw.inline.markdown_inline",
      "@text.literal",
      "@text.literal.markdown_inline",
    }, "MarkdownInlineCode")

    set_many({
      "@markup.raw.delimiter",
      "@markup.raw.delimiter.markdown_inline",
      "@punctuation.delimiter.markdown",
      "@punctuation.delimiter.markdown_inline",
      "markdownCodeDelimiter",
    }, o.delimiter_hl)
  end
end

function M.setup(opts)
  if type(opts) == "table" then
    for k, v in pairs(opts) do M.opts[k] = v end
  end
  pcall(M.apply)
  return M
end

-- Raw nvim_create_augroup on purpose, not autocmd.group(): that caches by
-- name and would skip the clear on a second load of this module (e.g. a
-- hot-reload via package.loaded reset), leaving the previous ColorScheme
-- autocmd registered alongside the new one instead of replaced.
autocmd.create("ColorScheme", function()
  M.apply()
end, {
  group = vim.api.nvim_create_augroup("MarkdownNvimFencedFix", { clear = true }),
  desc = "Re-apply fenced fix after colorscheme changes",
})

return M
