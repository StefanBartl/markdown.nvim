---@module 'markdown.core.heading_gaps'
--- Detect (and optionally fix) skipped heading levels, e.g. an H1 followed
--- directly by an H3 with no H2 in between.

local notify = require("markdown.util.notify").create("[markdown.core.heading_gaps]")

local M = {}

-- A fenced-code delimiter line: 3+ backticks or 3+ tildes, then an optional
-- info string. `{3,}` is NOT a Lua-pattern quantifier (it matches the literal
-- characters `{3,}`), so three-or-more is spelled out explicitly.
local FENCE_LINE = "^%s*[`~][`~][`~]+%S*%s*$"

---@class Mkdn.HeadingGap
---@field lnum integer      1-based line of the offending heading
---@field level integer     Its actual level (e.g. 3 for `###`)
---@field prev_level integer Level of the heading immediately before it
---@field expected integer  Level it should be to close the gap (prev_level + 1)
---@field title string      Heading text (without the `#` markers)

--- Scan `bufnr` for headings whose level jumps more than one deeper than the
--- previous heading (fence-aware). The very first heading in the buffer can
--- never be a gap regardless of its level.
---@param bufnr integer
---@return Mkdn.HeadingGap[]
function M.find_gaps(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local gaps = {}
  local in_fence = false
  local last_level = 0

  for i, line in ipairs(lines) do
    if line:match(FENCE_LINE) then
      in_fence = not in_fence
    elseif not in_fence then
      local hashes, title = line:match("^(%s*#+)%s+(.*%S)")
      if hashes and title then
        local level = #hashes:gsub("%s", "")
        if last_level > 0 and level > last_level + 1 then
          gaps[#gaps + 1] = {
            lnum = i,
            level = level,
            prev_level = last_level,
            expected = last_level + 1,
            title = title,
          }
          last_level = last_level + 1 -- the outline continues as if it were fixed
        else
          last_level = level
        end
      end
    end
  end

  return gaps
end

--- Rewrite each gap's heading line so its level closes the gap
--- (e.g. `#### Title` -> `## Title` when `expected == 2`).
---@param bufnr integer
---@param gaps Mkdn.HeadingGap[]
function M.fix_gaps(bufnr, gaps)
  for _, g in ipairs(gaps) do
    local line = vim.api.nvim_buf_get_lines(bufnr, g.lnum - 1, g.lnum, false)[1]
    if line then
      local indent, rest = line:match("^(%s*)#+%s+(.*)$")
      if indent and rest then
        local fixed = string.format("%s%s %s", indent, string.rep("#", g.expected), rest)
        vim.api.nvim_buf_set_lines(bufnr, g.lnum - 1, g.lnum, false, { fixed })
      end
    end
  end
end

--- Detect heading-level gaps and, if any are found, notify and offer to fix
--- them immediately. Used automatically by `<leader>toc` / `:Markdown toc`
--- (gated by the `check_heading_gaps` config option, default `true`) and
--- explicitly via `:Markdown gaps`.
---@param bufnr? integer
---@param opts? { silent_ok?: boolean } silent_ok: skip the "no gaps" notice
---@return Mkdn.HeadingGap[]
function M.check(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = opts or {}

  local gaps = M.find_gaps(bufnr)
  if #gaps == 0 then
    if not opts.silent_ok then notify.info("No heading-level gaps found") end
    return gaps
  end

  local lines_desc = {}
  for _, g in ipairs(gaps) do
    lines_desc[#lines_desc + 1] = string.format(
      '  line %d: "%s" is H%d, expected H%d (previous heading is H%d)',
      g.lnum,
      g.title,
      g.level,
      g.expected,
      g.prev_level
    )
  end

  notify.warn(
    string.format(
      "Found %d heading-level gap%s:\n%s",
      #gaps,
      #gaps == 1 and "" or "s",
      table.concat(lines_desc, "\n")
    )
  )

  local choice = vim.fn.confirm("Fix heading-level gaps now?", "&Yes\n&No", 2)
  if choice == 1 then
    M.fix_gaps(bufnr, gaps)
    notify.info(string.format("Fixed %d heading-level gap%s", #gaps, #gaps == 1 and "" or "s"))
  end

  return gaps
end

return M
