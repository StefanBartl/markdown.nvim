---@module 'markdown.hover.preview.text'
---@brief Previews that are just "some lines of a file": markdown, plain
---files, directories, and in-page anchors.
---@description
--- All synchronous — these read at most `max_lines` lines and never touch
--- the network. Reading is capped by line count rather than by file size, so
--- a 300 MB log with one very long line costs the same as a short one.

local M = {}

local api = vim.api

---@internal
--- Read at most `limit` lines from `path`. Uses `io.lines` rather than
--- `fs.read` + split so a huge file is not slurped into memory just to show
--- its first 20 lines.
---@param path string
---@param limit integer
---@return string[] lines
---@return boolean truncated
local function head(path, limit)
  local out = {}
  local f = io.open(path, "r")
  if not f then return out, false end
  local truncated = false
  for line in f:lines() do
    if #out >= limit then
      truncated = true
      break
    end
    -- Strip a CR left by a CRLF file so the float does not render `^M`.
    out[#out + 1] = (line:gsub("\r$", ""))
  end
  f:close()
  return out, truncated
end

---@internal
---@param n integer
---@return string
local function human_size(n)
  local ok, strings = pcall(require, "lib.lua.strings.format")
  if ok and strings and strings.format_bytes then return strings.format_bytes(n) end
  return tostring(n) .. " B"
end

--- Preview a markdown or plain-text file.
---@param target Mkdn.Hover.Target
---@param opts Mkdn.Hover.PreviewOpts
---@return Mkdn.Hover.Content
function M.file(target, opts)
  local limit = opts.max_lines or 20
  local lines, truncated = head(target.path, limit)

  if #lines == 0 then
    return {
      lines = { ("(empty file, %s)"):format(human_size(target.size or 0)) },
      title = vim.fs.basename(target.path),
    }
  end

  if truncated then lines[#lines + 1] = "…" end

  return {
    lines = lines,
    -- Markdown gets its own filetype so the float renders headings/emphasis
    -- with the user's markdown highlighting; anything else is left plain
    -- rather than guessed, since a wrong ftplugin can be slow or noisy.
    filetype = target.type == "markdown" and "markdown" or nil,
    title = vim.fs.basename(target.path),
  }
end

--- Preview the section of a markdown file that `target.anchor` names — the
--- heading line plus the body under it. Falls back to the file preview when
--- the anchor is not found, which is more useful than an error: the file
--- still exists, only the fragment is wrong.
---@param target Mkdn.Hover.Target
---@param opts Mkdn.Hover.PreviewOpts
---@return Mkdn.Hover.Content
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
---@param target Mkdn.Hover.Target
---@param opts Mkdn.Hover.PreviewOpts
---@param bufnr integer
---@return Mkdn.Hover.Content
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

--- Preview a directory: its entries, directories first.
---@param target Mkdn.Hover.Target
---@param opts Mkdn.Hover.PreviewOpts
---@return Mkdn.Hover.Content
function M.directory(target, opts)
  local limit = opts.max_lines or 20
  local uv = vim.uv or vim.loop

  local handle = uv.fs_scandir(target.path)
  if not handle then
    return { lines = { "(cannot read directory)" }, title = vim.fs.basename(target.path) }
  end

  local dirs, files = {}, {}
  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then break end
    if kind == "directory" then
      dirs[#dirs + 1] = name .. "/"
    else
      files[#files + 1] = name
    end
  end
  table.sort(dirs)
  table.sort(files)

  local out = {}
  for _, entry in ipairs(dirs) do
    out[#out + 1] = entry
  end
  for _, entry in ipairs(files) do
    out[#out + 1] = entry
  end

  local total = #out
  if total == 0 then out = { "(empty directory)" } end
  if #out > limit then
    out = vim.list_slice(out, 1, limit)
    out[#out + 1] = ("… (%d entries)"):format(total)
  end

  return { lines = out, title = vim.fs.basename(target.path) .. "/" }
end

--- Preview for a target that does not exist.
---@param target Mkdn.Hover.Target
---@return Mkdn.Hover.Content
function M.missing(target)
  local lines = { target.reason or "target not found" }
  if target.path then lines[#lines + 1] = target.path end
  return { lines = lines, title = "broken link" }
end

return M
