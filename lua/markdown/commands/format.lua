---@module 'markdown.commands.format'
--- `:Markdown format <op>... [scope=%|cfile|cwd|PATH] [dry-run]` -- body-text
--- normalization: strip bold/strikethrough/all-emphasis markers, collapse
--- blank-line runs, trim trailing whitespace, normalize bullet-list markers.
--- See core/body_format.lua for exactly what each op does and does not touch
--- (a fenced code block, and inside a line a code span/link-target/autolink,
--- are always left alone).
---
--- Deliberately separate from `:Markdown headings format` (heading TEXT
--- normalization) and `:Markdown table format` (the GFM table formatter):
--- this one is body prose. Composing all three into one pipeline is left for
--- later -- today they stay three commands with their own option shapes.

local M = {}

local notify = require("markdown.util.notify").create("[markdown.commands.format]")
local body_format = require("markdown.core.body_format")
local scope_util = require("markdown.util.scope")

local VALID_OP = {}
for _, o in ipairs(body_format.OPS) do
  VALID_OP[o] = true
end

--- Parses `:Markdown format ARGS`.
---@param argv string[]
---@return string[] ops
---@return string? scope
---@return boolean dry_run
---@return string? err
local function parse_args(argv)
  local ops, scope, dry_run = {}, nil, false
  for _, raw in ipairs(argv) do
    local key, val = raw:match("^([%w_]+)=(.+)$")
    if key == "scope" then
      scope = val
    elseif raw == "dry-run" then
      dry_run = true
    elseif VALID_OP[raw] then
      ops[#ops + 1] = raw
    else
      return ops, scope, dry_run, string.format("Unknown argument: %q", raw)
    end
  end
  return ops, scope, dry_run, nil
end

---@internal
---@param resolved Mkdn.ScopeResult
---@param ops string[]
---@param dry_run boolean
local function run_on_files(resolved, ops, dry_run)
  local total_changed, files_touched, errors = 0, 0, {}
  for _, path in ipairs(resolved.paths) do
    local changed, err = body_format.format_file(path, ops, { dry_run = dry_run })
    if changed == nil then
      errors[#errors + 1] = err
    else
      total_changed = total_changed + changed
      if changed > 0 then files_touched = files_touched + 1 end
    end
  end

  if #errors > 0 then
    notify.warn(
      string.format(
        "format: %d/%d file(s) failed:\n  %s",
        #errors,
        #resolved.paths,
        table.concat(errors, "\n  ")
      )
    )
    return
  end

  notify.info(
    string.format(
      "format: %s%d line(s) across %d/%d file(s)",
      dry_run and "would change " or "changed ",
      total_changed,
      files_touched,
      #resolved.paths
    )
  )
end

--- Runs `:Markdown format <op>... [scope=...] [dry-run]`.
---@param argv string[]
---@param _ctx? table  Unused; matches the dispatcher's (argv, ctx) calling convention.
---@return nil
function M.run(argv, _ctx)
  local ops, scope, dry_run, err = parse_args(argv or {})
  if err then
    notify.error("format: " .. err)
    return
  end
  if #ops == 0 then
    notify.info(
      string.format(
        "Usage: :Markdown format <%s> ... [scope=%%|cfile|cwd|PATH] [dry-run]",
        table.concat(body_format.OPS, "|")
      )
    )
    return
  end

  local resolved, rerr = scope_util.resolve(scope)
  if not resolved then
    notify.warn("format: " .. rerr)
    return
  end

  if resolved.kind == "buffer" then
    local changed = body_format.format_buffer(resolved.bufnr, ops, { dry_run = dry_run })
    notify.info(
      string.format("format: %s%d line(s)", dry_run and "would change " or "changed ", changed)
    )
    return
  end

  run_on_files(resolved, ops, dry_run)
end

--- Completion for `:Markdown format` arguments: every op, plus the scope and
--- dry-run flags, offered at every slot (an open-ended run, like
--- `table format`'s options).
---@param arg_lead string
---@return string[]
function M.complete(arg_lead)
  local candidates = vim.list_extend({}, body_format.OPS)
  candidates[#candidates + 1] = "scope=%"
  candidates[#candidates + 1] = "scope=cfile"
  candidates[#candidates + 1] = "scope=cwd"
  candidates[#candidates + 1] = "dry-run"

  local out = {}
  for _, c in ipairs(candidates) do
    if vim.startswith(c, arg_lead) then out[#out + 1] = c end
  end
  return out
end

return M
