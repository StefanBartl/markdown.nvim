---@module 'markdown.core.body_format'
---@brief Body-text normalization for `:Markdown format`.
---@description
--- Strip bold/strikethrough/all-emphasis markers, collapse runs of blank
--- lines, trim trailing whitespace, and normalize bullet-list markers --
--- across a whole buffer or a file on disk, not just heading text (see
--- core/heading_format.lua for that one).
---
--- Every marker-stripping op runs through core.inline_segment first, so a
--- code span, a link's `](target)`, and a `<...>` autolink/raw HTML tag are
--- always copied through verbatim rather than treated as prose -- the same
--- contract heading_format.lua uses. A fenced code block is opaque end to
--- end, and a leading YAML front-matter block (`---` ... `---` at the very
--- top of the file) is left untouched too.

local api = vim.api
local inline_segment = require("markdown.core.inline_segment")
local emphasis = require("markdown.core.emphasis")

local M = {}

local FENCE_PAT = "^%s*[`~][`~][`~]+%S*%s*$"

--- Apply `fn` to every plain (non-protected) segment of `line`.
---@param line string
---@param fn fun(text: string): string
---@return string line
---@return boolean changed
local function apply_plain(line, fn)
  local segs = inline_segment.segment(line)
  local changed = false
  for _, seg in ipairs(segs) do
    if not seg.verbatim then
      local new = fn(seg.text)
      if new ~= seg.text then
        seg.text = new
        changed = true
      end
    end
  end
  if not changed then return line, false end
  local out = {}
  for _, seg in ipairs(segs) do
    out[#out + 1] = seg.text
  end
  return table.concat(out), true
end

--- Per-line ops: `line -> (line, changed)`. `collapse-blank-lines` is not
--- here -- it needs neighboring lines, so it runs as its own whole-buffer
--- pass in `format_lines` below.
---@type table<string, fun(line: string): string, boolean>
local LINE_OPS = {
  ["strip-bold"] = function(line) return apply_plain(line, emphasis.strip_bold) end,
  ["strip-strikethrough"] = function(line) return apply_plain(line, emphasis.strip_strikethrough) end,
  ["strip-emphasis"] = function(line) return apply_plain(line, emphasis.strip_all) end,
  ["trim-trailing-space"] = function(line)
    -- Two or more trailing spaces after real content is a hard line break
    -- (GFM): normalized down to exactly two, never stripped to zero. A
    -- trailing tab, a single trailing space, or trailing whitespace on an
    -- otherwise-blank line is just noise and goes entirely.
    local body, trail = line:match("^(.-)([ \t]*)$")
    if trail == "" then return line, false end
    local hard_break = body ~= "" and #trail >= 2 and trail:match("^ +$") ~= nil
    local out = hard_break and (body .. "  ") or body
    return out, out ~= line
  end,
  ["normalize-list-markers"] = function(line)
    local indent, marker, rest = line:match("^(%s*)([*+])(%s+%S.*)$")
    if not marker then return line, false end
    return indent .. "-" .. rest, true
  end,
}

--- Names every op below understands, for the command layer's validation and
--- completion.
---@type string[]
M.OPS = {
  "strip-bold",
  "strip-strikethrough",
  "strip-emphasis",
  "collapse-blank-lines",
  "trim-trailing-space",
  "normalize-list-markers",
}

--- Collapse runs of 2+ blank lines into 1. Fenced-block content is left
--- alone (blank lines inside a code sample are the sample's, not this
--- document's prose).
---@param lines string[]
---@return string[] out
---@return integer removed
local function collapse_blank_lines(lines)
  local out, removed, prev_blank, in_fence = {}, 0, false, false
  for _, line in ipairs(lines) do
    if line:match(FENCE_PAT) then
      in_fence = not in_fence
      out[#out + 1] = line
      prev_blank = false
    elseif in_fence then
      out[#out + 1] = line
      prev_blank = false
    else
      local blank = line:match("^%s*$") ~= nil
      if blank and prev_blank then
        removed = removed + 1
      else
        out[#out + 1] = line
      end
      prev_blank = blank
    end
  end
  return out, removed
end

--- Apply every per-line op in `ops` (in order) to each line, skipping a
--- fenced code block or a leading YAML front-matter block entirely.
---@param lines string[]
---@param ops string[]
---@return string[] out
---@return integer changed
local function apply_line_ops(lines, ops)
  local fns = {}
  for _, op in ipairs(ops) do
    if LINE_OPS[op] then fns[#fns + 1] = LINE_OPS[op] end
  end

  local out, changed = {}, 0
  local in_fence = false
  local in_front_matter = lines[1] == "---"
  for idx, line in ipairs(lines) do
    if in_front_matter then
      out[idx] = line
      if idx > 1 and line == "---" then in_front_matter = false end
    elseif line:match(FENCE_PAT) then
      in_fence = not in_fence
      out[idx] = line
    elseif in_fence then
      out[idx] = line
    else
      local cur, line_changed = line, false
      for _, fn in ipairs(fns) do
        local new, did = fn(cur)
        if did then
          cur = new
          line_changed = true
        end
      end
      out[idx] = cur
      if line_changed then changed = changed + 1 end
    end
  end
  return out, changed
end

--- Run `ops` over `lines`, returning the result and a total change count
--- (lines rewritten by a per-line op, plus blank lines removed).
---@param lines string[]
---@param ops string[]
---@return string[] out
---@return integer changed
local function format_lines(lines, ops)
  local out, changed = apply_line_ops(lines, ops)
  for _, op in ipairs(ops) do
    if op == "collapse-blank-lines" then
      local collapsed, removed = collapse_blank_lines(out)
      out, changed = collapsed, changed + removed
      break
    end
  end
  return out, changed
end

--- Format every line of `bufnr` in place.
---@param bufnr integer
---@param ops string[]
---@param opts? { dry_run?: boolean }
---@return integer changed
function M.format_buffer(bufnr, ops, opts)
  opts = opts or {}
  bufnr = (bufnr == nil or bufnr == 0) and api.nvim_get_current_buf() or bufnr
  if not (api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr)) then return 0 end

  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out, changed = format_lines(lines, ops)
  if changed > 0 and not opts.dry_run then
    local is_current = bufnr == api.nvim_get_current_buf()
    local view = is_current and vim.fn.winsaveview() or nil
    api.nvim_buf_set_lines(bufnr, 0, -1, false, out)
    if view then vim.fn.winrestview(view) end
  end
  return changed
end

--- Format a file on disk (independent of any open buffer).
---@param path string
---@param ops string[]
---@param opts? { dry_run?: boolean }
---@return integer|nil changed
---@return string|nil err
function M.format_file(path, ops, opts)
  opts = opts or {}
  if vim.fn.filereadable(path) == 0 then
    return nil, string.format("File not readable: %q", path)
  end

  local lines = vim.fn.readfile(path)
  local out, changed = format_lines(lines, ops)
  if changed > 0 and not opts.dry_run then
    if vim.fn.writefile(out, path) == -1 then
      return nil, string.format("Failed to write %q", path)
    end
  end
  return changed, nil
end

return M
