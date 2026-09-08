-- TESTS/heading_format_spec.lua — heading TEXT normalization (core.heading_format).
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq
  local config = require("markdown.config")
  config.setup({})
  local fmt = require("markdown.core.heading_format")

  -- ── format_title: the individual rules ────────────────────────────────────

  eq(fmt.format_title("**Bold title**"), "Bold title", "bold markers stripped")
  eq(fmt.format_title("*italic* and **bold**"), "Italic and bold", "mixed emphasis stripped")
  eq(fmt.format_title("~~struck~~ out"), "Struck out", "strikethrough stripped")
  eq(fmt.format_title("_underscored_"), "Underscored", "boundary underscores stripped")

  -- The reason `_` is not stripped unconditionally: an identifier is not
  -- emphasis, and neither GitHub nor any other GFM renderer treats it as such.
  eq(fmt.format_title("the foo_bar helper"), "The foo_bar helper", "intra-word underscore kept")

  eq(fmt.format_title("Title ##"), "Title", "closing hashes dropped")
  eq(fmt.format_title("Too    many   spaces"), "Too many spaces", "whitespace collapsed")
  eq(fmt.format_title("  padded  "), "Padded", "ends trimmed")
  eq(fmt.format_title("lowercase start"), "Lowercase start", "first letter capitalized")

  -- Trailing punctuation is opt-in, and `?` survives even then.
  eq(fmt.format_title("Ends with a period."), "Ends with a period.", "punctuation kept by default")
  eq(
    fmt.format_title("Ends with a period.", { strip_trailing_punctuation = true }),
    "Ends with a period",
    "punctuation stripped on request"
  )
  eq(
    fmt.format_title("Why not?", { strip_trailing_punctuation = true }),
    "Why not?",
    "a question mark is not noise"
  )

  -- ── what is deliberately left alone ───────────────────────────────────────

  -- Emphasis inside a code span is content: `**kwargs` is Python, not bold.
  eq(fmt.format_title("Pass `**kwargs` through"), "Pass `**kwargs` through", "code span untouched")
  -- A link target is not prose; stripping an underscore out of it breaks it.
  eq(
    fmt.format_title("**See** [the notes](docs/my_notes.md)"),
    "See [the notes](docs/my_notes.md)",
    "link target untouched, label formatted"
  )
  eq(
    fmt.format_title('a <span class="x">tag</span> here'),
    'A <span class="x">tag</span> here',
    "raw HTML untouched"
  )

  -- ── capitalize modes ──────────────────────────────────────────────────────

  eq(fmt.format_title("hello world", { capitalize = false }), "hello world", "capitalize off")
  eq(
    fmt.format_title("the state of the art", { capitalize = "title" }),
    "The State of the Art",
    "title case keeps stopwords lowercase mid-heading"
  )
  -- First and last word are capitalized even when they are stopwords, which is
  -- what separates title case from sentence case.
  eq(
    fmt.format_title("of mice and men and", { capitalize = "title" }),
    "Of Mice and Men And",
    "first and last word always capitalized"
  )
  -- A word already carrying an inner capital is spelled the way its author
  -- meant it; "fixing" it would be damage.
  eq(
    fmt.format_title("the API and the iPhone", { capitalize = "title" }),
    "The API and the iPhone",
    "inner-capital words left alone"
  )

  -- A heading of pure markup would format to nothing; leaving `## ` behind is
  -- worse than doing nothing at all.
  local line, changed = fmt.format_line("## ****")
  eq(line, "## ****", "an all-markup heading is left as it was")
  eq(changed, false, "and reports no change")

  -- ── format_line: structure preserved ──────────────────────────────────────

  eq(({ fmt.format_line("### **deep** heading") })[1], "### Deep heading", "level preserved")
  eq(({ fmt.format_line("  ## indented") })[1], "  ## Indented", "indent preserved")
  eq(({ fmt.format_line("not a heading") })[1], "not a heading", "prose untouched")
  eq(({ fmt.format_line("####### seven") })[1], "####### seven", "7 hashes is not a heading")

  -- ── format_range over a buffer ────────────────────────────────────────────

  local buf = H.scratch("markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# **first**",
    "prose line",
    "## *second*",
    "```sh",
    "# **not a heading, a shell comment**",
    "```",
    "### third",
  })

  local n = fmt.format_range(buf, 1, 7)
  eq(n, 3, "all three headings rewritten, the fenced comment line untouched")

  local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(out[1], "# First", "H1 formatted")
  eq(out[2], "prose line", "prose untouched")
  eq(out[3], "## Second", "H2 formatted")
  eq(out[5], "# **not a heading, a shell comment**", "fenced content untouched")
  eq(out[7], "### Third", "H3 capitalized")

  -- A range starting inside a fenced block must still know it is inside one,
  -- which means reading the fence state from the top of the buffer.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "```sh",
    "# **still a shell comment**",
    "```",
  })
  eq(fmt.format_range(buf, 2, 2), 0, "fence state is read from line 1, not from the range")

  -- ── config.heading_format feeds the defaults ──────────────────────────────

  config.setup({ heading_format = { capitalize = "title", strip_emphasis = false } })
  eq(
    fmt.format_title("**the state** of the art"),
    "**The State** of the Art",
    "config supplies the defaults"
  )
  -- An explicit per-call option still wins over the config.
  eq(
    fmt.format_title("**the state** of the art", { capitalize = "first" }),
    "**The state** of the art",
    "per-call opts override the config"
  )
  config.setup({})
end
