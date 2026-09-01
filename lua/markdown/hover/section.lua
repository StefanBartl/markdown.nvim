---@module 'markdown.hover.section'
---@brief The two hover previews that genuinely need markdown knowledge.
---@description
--- Everything else about the hover is `hover.nvim` — classification, the
--- float, file/directory/URL previews, the debounce, the cache, bare-path
--- detection. What stayed here is the part a library cannot do: resolving
--- `#some-heading` against a document. That means GFM slugging
--- (`markdown.core.slug`) and heading parsing, which is markdown semantics,
--- not path handling.
---
--- Both are registered as previews through `hover.registry` (see
--- `markdown.hover`), so the framework reaches them without knowing this file
--- exists — and without markdown.nvim installed it simply falls back to
--- showing the file's first lines, which is the honest answer when nothing
--- present can resolve a fragment.

local M = {}

local api = vim.api

--- Preview a plain file, used as the fallback when an anchor does not
--- resolve. Delegates to the library rather than re-reading the file here.
---@param target Hover.Target
---@param opts Hover.PreviewOpts
---@return Hover.Content
function M.file(target, opts) return require("hover.preview.text").file(target, opts) end

--- Preview the section of a markdown file that `target.anchor` names — the
--- heading line plus the body under it. Falls back to the file preview when
--- the anchor is not found, which is more useful than an error: the file
--- still exists, only the fragment is wrong.
---@param target Hover.Target
---@param opts Hover.PreviewOpts
---@return Hover.Content
function M.file_anchor(target, opts)
  local limit = opts.max_lines or 20
  local slug = require("markdown.core.slug")

  local all = {}
  local f = io.open(target.path, "r")
  if not f then return M.file(target, opts) end
  for line in f:lines() do
    all[#all + 1] = (line:gsub("\r$", ""))
  end
  f:close()

  local wanted = (target.anchor or ""):lower()
  local start_idx
  for i, line in ipairs(all) do
    local hashes, title = line:match("^(#+)%s+(.*)$")
    if hashes and slug.gfm(title):lower() == wanted then
      start_idx = i
      break
    end
  end

  if not start_idx then
    local content = M.file(target, opts)
    content.title = ("%s (#%s not found)"):format(vim.fs.basename(target.path), target.anchor)
    return content
  end

  local out = { all[start_idx] }
  local level = #(all[start_idx]:match("^(#+)") or "#")
  for i = start_idx + 1, #all do
    if #out >= limit then
      out[#out + 1] = "…"
      break
    end
    local hashes = all[i]:match("^(#+)%s")
    -- Stop at the next heading of the same or a higher level: that is where
    -- this section ends.
    if hashes and #hashes <= level then break end
    out[#out + 1] = all[i]
  end

  return { lines = out, filetype = "markdown", title = vim.fs.basename(target.path) }
end

--- Preview an in-page anchor: the section it points at inside the current
--- buffer.
---@param target Hover.Target
---@param opts Hover.PreviewOpts
---@param bufnr integer
---@return Hover.Content
function M.anchor(target, opts, bufnr)
  local limit = opts.max_lines or 20
  local slug = require("markdown.core.slug")
  local all = api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local wanted = (target.anchor or ""):lower()
  local start_idx
  for i, line in ipairs(all) do
    local hashes, title = line:match("^(#+)%s+(.*)$")
    if hashes and slug.gfm(title):lower() == wanted then
      start_idx = i
      break
    end
  end

  if not start_idx then
    return {
      lines = { ("no heading matches #%s in this document"):format(target.anchor or "") },
      title = "broken anchor",
    }
  end

  local out = { all[start_idx] }
  local level = #(all[start_idx]:match("^(#+)") or "#")
  for i = start_idx + 1, #all do
    if #out >= limit then
      out[#out + 1] = "…"
      break
    end
    local hashes = all[i]:match("^(#+)%s")
    if hashes and #hashes <= level then break end
    out[#out + 1] = all[i]
  end

  return { lines = out, filetype = "markdown", title = ("line %d"):format(start_idx) }
end

return M
