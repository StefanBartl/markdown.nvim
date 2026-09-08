---@module 'markdown.commands.headings'
--- `:Markdown headings format [key=value …]` — normalize heading *text*
--- (emphasis markers, whitespace, closing hashes, capitalization) across the
--- buffer, or across the given range.
---
--- With a range (`:'<,'>Markdown headings format`, `:10,20Markdown …`) only
--- those lines are touched; without one, the whole buffer is.
---
--- Every rule defaults to `config.heading_format` and can be overridden for
--- one invocation:
---
---   emphasis=on|off        strip `**`/`*`/`__`/`_`/`~~` markers
---   hashes=on|off          drop the closing `##` of `## Title ##`
---   whitespace=on|off      collapse space runs, trim the ends
---   punctuation=on|off     drop a trailing `.`/`,`/`;`/`:`
---   capitalize=first|title|off
---
--- Level shifting is `<C-Left>`/`<C-Right>` and lives in core.headings; the
--- `<C-S-…>` variants of those keys shift *and* run this formatter over the
--- heading they moved.
local M = {}

local notify = require("markdown.util.notify").create("[markdown.commands.headings]")

-- ---------------------------------------------------------------------------
-- argument parsing
-- ---------------------------------------------------------------------------

-- Argument name -> the Mkdn.HeadingFormatConfig field it sets. The command
-- vocabulary is deliberately shorter than the config keys: `emphasis=off`
-- reads better on a command line than `strip_emphasis=false`, and the config
-- table is where the long, self-describing names belong.
local BOOL_ARGS = {
  emphasis = "strip_emphasis",
  hashes = "strip_closing_hashes",
  whitespace = "collapse_whitespace",
  punctuation = "strip_trailing_punctuation",
}

local BOOL_VALUES = {
  on = true,
  ["true"] = true,
  yes = true,
  off = false,
  ["false"] = false,
  no = false,
}

local CAPITALIZE_VALUES = {
  first = "first",
  title = "title",
  off = false,
  none = false,
  ["false"] = false,
}

--- Turn `key=value` tokens into a Mkdn.HeadingFormatConfig override table.
---@param argv string[]
---@return Mkdn.HeadingFormatConfig|nil opts # nil when a token is unusable
local function parse_opts(argv)
  ---@type Mkdn.HeadingFormatConfig
  local opts = {}

  for _, token in ipairs(argv) do
    local key, value = token:match("^([%w_]+)=(.+)$")
    if not key then
      notify.warn(("headings format: expected key=value, got %q"):format(token))
      return nil
    end

    key, value = key:lower(), value:lower()

    if key == "capitalize" then
      local resolved = CAPITALIZE_VALUES[value]
      if resolved == nil then
        notify.warn(("headings format: capitalize=%s — expected first|title|off"):format(value))
        return nil
      end
      opts.capitalize = resolved
    elseif BOOL_ARGS[key] then
      local resolved = BOOL_VALUES[value]
      if resolved == nil then
        notify.warn(("headings format: %s=%s — expected on|off"):format(key, value))
        return nil
      end
      opts[BOOL_ARGS[key]] = resolved
    else
      notify.warn(("headings format: unknown option %q"):format(key))
      return nil
    end
  end

  return opts
end

-- ---------------------------------------------------------------------------
-- actions
-- ---------------------------------------------------------------------------

--- Run the formatter over the command's range, or the whole buffer.
---@param argv string[]
---@param ctx? table  { range?: integer, line1?: integer, line2?: integer }
local function do_format(argv, ctx)
  local opts = parse_opts(argv)
  if not opts then return end

  local bufnr = vim.api.nvim_get_current_buf()
  local fmt = require("markdown.core.heading_format")

  local changed, where
  if ctx and ctx.range and ctx.range > 0 then
    changed = fmt.format_range(bufnr, ctx.line1, ctx.line2, opts)
    where = ("lines %d-%d"):format(ctx.line1, ctx.line2)
  else
    changed = fmt.format_buffer(bufnr, opts)
    where = "the buffer"
  end

  if changed == 0 then
    notify.info(("No heading in %s needed formatting"):format(where))
  else
    notify.info(("Formatted %d heading%s"):format(changed, changed == 1 and "" or "s"))
  end
end

-- ---------------------------------------------------------------------------
-- dispatch
-- ---------------------------------------------------------------------------

local ACTIONS = {
  format = do_format,
}

--- Runs `:Markdown headings <action> [args]`.
---@param argv string[]
---@param ctx? table
---@return nil
function M.run(argv, ctx)
  argv = argv or {}
  local action = argv[1]

  if not action then
    notify.info(
      "Usage: :Markdown headings format [emphasis=on|off] [capitalize=first|title|off] …"
    )
    return
  end

  local fn = ACTIONS[action]
  if not fn then
    notify.warn(
      ("headings: unknown action %q — expected one of: %s"):format(
        action,
        table.concat(vim.tbl_keys(ACTIONS), ", ")
      )
    )
    return
  end

  fn(vim.list_slice(argv, 2), ctx)
end

--- Completion: the action first, then its `key=value` options.
---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local tokens = vim.split(vim.trim(cmdline), "%s+")
  -- tokens: {"Markdown", "headings", [action], [opt]...}
  local on_action = #tokens < 3 or (#tokens == 3 and arglead ~= "")

  local candidates = {}
  if on_action then
    candidates = vim.tbl_keys(ACTIONS)
  else
    -- Complete the value once a `key=` is already typed; otherwise the keys.
    local key = arglead:match("^([%w_]+)=")
    if key == "capitalize" then
      for value in pairs(CAPITALIZE_VALUES) do
        candidates[#candidates + 1] = "capitalize=" .. value
      end
    elseif key and BOOL_ARGS[key] then
      for value in pairs(BOOL_VALUES) do
        candidates[#candidates + 1] = key .. "=" .. value
      end
    else
      candidates[#candidates + 1] = "capitalize="
      for name in pairs(BOOL_ARGS) do
        candidates[#candidates + 1] = name .. "="
      end
    end
  end

  local out = {}
  for _, c in ipairs(candidates) do
    if vim.startswith(c, arglead) then out[#out + 1] = c end
  end
  table.sort(out)
  return out
end

return M
