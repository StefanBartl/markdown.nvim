-- TESTS/table_format_wrap_spec.lua -- `:Markdown table format` / <leader>mtf honour a maximum
-- column width (core.table_wrap): long cells wrap onto shared continuation rows.
---@diagnostic disable: missing-fields

return function(H)
  local eq, ok = H.eq, H.ok
  local tf = require("markdown.core.table_fmt")
  local tcmd = require("markdown.commands.table")
  local mdtable = require("markdown.commands.mdtable")

  local function open(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    return buf
  end

  local function get(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end

  local SRC = {
    "| Syntax | Meaning | Example |",
    "|---|---|---|",
    "| `a` | stdout of the left command becomes stdin of the right one | `ls` |",
    "| `b` | short | `npx vitest run --reporter verbose --bail` |",
  }

  -- parse_args: max= / wrap / nowrap / auto
  local o = tf.parse_args({ "max=25", "wrap" })
  eq(o.max, 25, "max=25 parsed")
  eq(o.wrap, true, "wrap flag parsed")
  eq(tf.parse_args({ "nowrap" }).wrap, false, "nowrap flag parsed")
  eq(tf.parse_args({ "auto" }).auto, true, "auto flag parsed")
  local _, err = tf.parse_args({ "max=abc" })
  ok(err ~= nil, "max=abc is rejected")
  _, err = tf.parse_args({ "max=0" })
  ok(err ~= nil, "max=0 is rejected")

  -- wants_wrap: explicit flag > max/auto > config
  eq(mdtable.wants_wrap({ wrap = false, max = 20 }), false, "nowrap beats max")
  eq(mdtable.wants_wrap({ max = 20 }), true, "max implies wrapping")
  eq(mdtable.wants_wrap({}), false, "off by default")

  -- natural format (no flag) keeps one physical row per record
  local buf = open(SRC)
  tcmd.run({ "format" })
  eq(#get(buf), 4, "plain format does not wrap")

  -- max=20: continuation rows appear, every row keeps three columns
  buf = open(SRC)
  tcmd.run({ "format", "max=20" })
  local out = get(buf)
  ok(#out > 4, "max=20 wraps long cells onto extra rows")
  for i, l in ipairs(out) do
    eq(#tf.parse_row(l), 3, "row " .. i .. " keeps 3 columns")
  end

  -- row `a` overflows in two columns (Meaning, Example is short): physical rows of
  -- `a` = lines before the `b` row, minus header and separator. The longest cell
  -- decides the count; the other column reuses those rows instead of adding its own.
  local b_at
  for i, l in ipairs(out) do
    if tf.parse_row(l)[1] == "`b`" then b_at = i end
  end
  local wrapped = require("markdown.core.table_wrap").wrap_cell(
    "stdout of the left command becomes stdin of the right one",
    20,
    {}
  )
  eq(b_at - 3, #wrapped, "row a occupies exactly as many rows as its longest cell needs")

  -- idempotent at the same width
  local first = get(buf)
  tcmd.run({ "format", "max=20" })
  eq(
    table.concat(get(buf), "\n"),
    table.concat(first, "\n"),
    "formatting twice at the same max is stable"
  )

  -- nowrap overrides table.wrap.enabled
  require("markdown.config").setup({ table = { wrap = { enabled = true, max = 20 } } })
  buf = open(SRC)
  tcmd.run({ "format" })
  ok(#get(buf) > 4, "table.wrap.enabled = true makes plain format wrap at wrap.max")
  buf = open(SRC)
  tcmd.run({ "format", "nowrap" })
  eq(#get(buf), 4, "nowrap wins over table.wrap.enabled")
  require("markdown.config").setup({})

  -- wrap with neither max nor auto uses the default cap
  buf = open({
    "| A | B |",
    "|---|---|",
    "| " .. string.rep("word ", 30) .. "| x |",
  })
  tcmd.run({ "format", "wrap" })
  for _, l in ipairs(get(buf)) do
    ok(
      vim.fn.strdisplaywidth(l) <= mdtable.DEFAULT_FORMAT_MAX + 12,
      "line within the default cap: " .. l
    )
  end
end
