---@module 'markdown.core.heading_format'
--- Normalize the *text* of ATX headings: drop emphasis markers, collapse
--- whitespace, remove closing hashes, capitalize.
---
--- The level is not this module's business — `core.headings` shifts levels and
--- never touches the text, this one rewrites the text and never touches the
--- level. `<C-S-Left>`/`<C-S-Right>` are the two composed: shift, then format
--- the line that moved.
---
--- What is left alone, and why: emphasis inside a code span is content rather
--- than markup, a link's target is not prose at all, and neither is a raw HTML
--- tag or an autolink. Those regions are copied through verbatim, so
--- `## **Fix** the \`--force\` [flag](docs/x.md)` becomes
--- `## Fix the \`--force\` [flag](docs/x.md)` and not something with a mangled
--- link or a stripped dash inside backticks.

local M = {}

local api = vim.api

---@class Mkdn.HeadingFormatConfig
---@field strip_emphasis? boolean # Drop `**`/`*`/`__`/`_`/`~~` markers from the text. Default true.
---@field strip_closing_hashes? boolean # `## Title ##` -> `## Title`. Default true.
---@field collapse_whitespace? boolean # Runs of spaces/tabs become one space; ends trimmed. Default true.
---@field strip_trailing_punctuation? boolean # Drop a trailing `.`/`,`/`;`/`:`. Default false.
---@field capitalize? false|"first"|"title" # Capitalize nothing, the first word, or every non-stopword. Default "first".
---@field stopwords? string[] # Words left lowercase by `capitalize = "title"`, unless first or last.

--- Words a title-case pass leaves lowercase in the middle of a heading. The
--- usual English closed-class set; the first and last word are capitalized
--- regardless, which is what makes it title case rather than sentence case.
---@type string[]
local STOPWORDS = {
  "a",
  "an",
  "and",
  "as",
  "at",
  "but",
  "by",
  "for",
  "from",
  "in",
  "into",
  "nor",
  "of",
  "on",
  "onto",
  "or",
  "over",
  "per",
  "the",
  "to",
  "up",
  "via",
  "vs",
  "with",
}

---@type Mkdn.HeadingFormatConfig
local DEFAULTS = {
  strip_emphasis = true,
  strip_closing_hashes = true,
  collapse_whitespace = true,
  strip_trailing_punctuation = false,
  capitalize = "first",
  stopwords = STOPWORDS,
}

--- The effective rules: defaults, then `config.heading_format`, then the
--- per-call overrides a command's arguments produce.
---@param opts? Mkdn.HeadingFormatConfig
---@return Mkdn.HeadingFormatConfig
local function resolve(opts)
  local user = require("markdown.config").get().heading_format or {}
  return vim.tbl_extend("force", DEFAULTS, user, opts or {})
end

-- ---------------------------------------------------------------------------
-- segmentation
-- ---------------------------------------------------------------------------

---@class Mkdn.HeadingFormat.Segment
---@field text string
---@field verbatim boolean # true: copied through untouched.

--- Split heading text into alternating plain and protected segments.
---
--- Protected: code spans (a backtick run and its matching close), the `](…)`
--- target of an inline link or image, and `<…>` autolinks / raw HTML tags. A
--- segment is never split or merged afterwards, so every later rule can be
--- written as a plain string transform over one segment.
---@param s string
---@return Mkdn.HeadingFormat.Segment[]
local function segment(s)
  ---@type Mkdn.HeadingFormat.Segment[]
  local segs = {}
  local plain = {}
  local i, n = 1, #s

  local function flush()
    if #plain > 0 then
      segs[#segs + 1] = { text = table.concat(plain), verbatim = false }
      plain = {}
    end
  end

  local function take(text)
    flush()
    segs[#segs + 1] = { text = text, verbatim = true }
    i = i + #text
  end

  while i <= n do
    local c = s:sub(i, i)
    local before = i

    if c == "`" then
      local _, run_end = s:find("^`+", i)
      local fence = s:sub(i, run_end)
      -- `true` for a plain find: a backtick run is not a pattern, and the
      -- closing run must match the opening one exactly.
      local close_start = s:find(fence, run_end + 1, true)
      if close_start then take(s:sub(i, close_start + #fence - 1)) end
    elseif c == "]" and s:sub(i + 1, i + 1) == "(" then
      -- `%b()` so a target with nested parens (a Wikipedia URL, say) is taken
      -- whole rather than cut at the first `)`.
      local target = s:match("^%b()", i + 1)
      if target then take("]" .. target) end
    elseif c == "<" then
      local tag = s:match("^<[^<>%s][^<>]*>", i)
      if tag then take(tag) end
    end

    if i == before then
      plain[#plain + 1] = c
      i = i + 1
    end
  end

  flush()
  return segs
end

-- ---------------------------------------------------------------------------
-- rules
-- ---------------------------------------------------------------------------

--- Drop emphasis markers from one plain segment.
---
--- `*` runs and `~~` strikethrough go unconditionally: a literal asterisk
--- in a heading is markup far more often than not, while a lone `~` (a
--- `~/path`) is left alone. `_` is the opposite case —
--- `foo_bar` is an identifier, and GitHub does not emphasize an intra-word
--- underscore either — so only runs sitting on a word boundary are dropped.
---@param s string
---@return string
local function strip_emphasis(s)
  s = (s:gsub("%*+", ""))
  s = (s:gsub("~~+", ""))

  local src = s
  s = (
    src:gsub("()(_+)()", function(a, run, b)
      local before = a > 1 and src:sub(a - 1, a - 1) or ""
      local after = src:sub(b, b)
      local opens = (before == "" or before:match("[%s%p]"))
        and after ~= ""
        and not after:match("%s")
      local closes = (after == "" or after:match("[%s%p]"))
        and before ~= ""
        and not before:match("%s")
      if opens or closes then return "" end
      return run
    end)
  )

  return s
end

--- Uppercase the first letter of `word`, unless it already carries an
--- uppercase letter past the first: `API`, `iPhone`, `GitHub` are spelled the
--- way their author meant them, and a capitalization pass that "fixes" them is
--- doing damage, not formatting. An all-lowercase name (`nvim-treesitter`)
--- carries no such signal and is capitalized like any other word -- add it to
--- `stopwords` if a title must keep it lowercase.
---@param word string
---@return string
local function capitalize_word(word)
  if word:sub(2):match("%u") then return word end
  return (word:gsub("^%l", string.upper))
end

--- Apply `capitalize = "title"` across every plain segment.
---
--- Two passes because the rule needs to know the last word before it can
--- decide about the first: stopwords stay lowercase in the middle of a
--- heading, but the opening and closing word are always capitalized.
---@param segs Mkdn.HeadingFormat.Segment[]
---@param stopwords table<string, boolean>
local function apply_title_case(segs, stopwords)
  local WORD = "[%a][%w'%-]*"

  local total = 0
  for _, seg in ipairs(segs) do
    if not seg.verbatim then
      for _ in seg.text:gmatch(WORD) do
        total = total + 1
      end
    end
  end
  if total == 0 then return end

  local seen = 0
  for _, seg in ipairs(segs) do
    if not seg.verbatim then
      seg.text = (
        seg.text:gsub(WORD, function(word)
          seen = seen + 1
          if seen == 1 or seen == total then return capitalize_word(word) end
          if stopwords[word:lower()] then return word:lower() end
          return capitalize_word(word)
        end)
      )
    end
  end
end

--- Apply `capitalize = "first"`: the first letter of the heading, nothing else.
---@param segs Mkdn.HeadingFormat.Segment[]
local function apply_first_capital(segs)
  for _, seg in ipairs(segs) do
    if not seg.verbatim and seg.text:match("%a") then
      seg.text = (seg.text:gsub("(%a)", string.upper, 1))
      return
    end
    -- A protected segment carrying letters (a code span opening the heading)
    -- is the heading's first word, and it is quoted content: stop rather than
    -- capitalize whatever plain word happens to come after it.
    if seg.verbatim and seg.text:match("%a") then return end
  end
end

-- ---------------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------------

--- Format the text of one heading, given the text alone (no `#` prefix).
---@param title string
---@param opts? Mkdn.HeadingFormatConfig
---@return string
function M.format_title(title, opts)
  local o = resolve(opts)

  -- Closing hashes are a suffix of the whole title, so they come off before
  -- segmentation rather than out of the last segment.
  if o.strip_closing_hashes ~= false then title = (title:gsub("%s+#+%s*$", "")) end

  local segs = segment(title)
  if #segs == 0 then return "" end

  if o.strip_emphasis ~= false then
    for _, seg in ipairs(segs) do
      if not seg.verbatim then seg.text = strip_emphasis(seg.text) end
    end
  end

  if o.collapse_whitespace ~= false then
    for _, seg in ipairs(segs) do
      if not seg.verbatim then seg.text = (seg.text:gsub("[ \t]+", " ")) end
    end
    -- Trim the outer ends only: an inner run of spaces has already been
    -- collapsed, and a space next to a protected segment is a real separator.
    if not segs[1].verbatim then segs[1].text = (segs[1].text:gsub("^%s+", "")) end
    local last = segs[#segs]
    if not last.verbatim then last.text = (last.text:gsub("%s+$", "")) end
  end

  if o.strip_trailing_punctuation then
    local last = segs[#segs]
    -- `?` and `!` carry meaning in a heading ("Why?"), so they stay; a
    -- sentence-ending `.`/`,`/`;`/`:` is the noise this rule is about.
    if not last.verbatim then last.text = (last.text:gsub("[%.,;:]+%s*$", "")) end
  end

  if o.capitalize == "title" then
    local set = {}
    for _, w in ipairs(o.stopwords or STOPWORDS) do
      set[w:lower()] = true
    end
    apply_title_case(segs, set)
  elseif o.capitalize ~= false and o.capitalize ~= nil then
    apply_first_capital(segs)
  end

  local out = {}
  for _, seg in ipairs(segs) do
    out[#out + 1] = seg.text
  end
  return table.concat(out)
end

--- Format one buffer line. A line that is not an ATX heading comes back
--- unchanged — the caller may hand over a whole range without pre-filtering.
---@param line string
---@param opts? Mkdn.HeadingFormatConfig
---@return string line
---@return boolean changed
function M.format_line(line, opts)
  local indent, hashes, gap, title = line:match("^(%s*)(#+)(%s+)(.*)$")
  if not hashes or #hashes > 6 then return line, false end

  local formatted = M.format_title(title, opts)
  -- An empty result means the rules ate the entire heading (a heading of pure
  -- emphasis markers). Leaving `## ` behind would be worse than doing nothing.
  if formatted == "" then return line, false end

  local o = resolve(opts)
  local sep = (o.collapse_whitespace ~= false) and " " or gap
  local out = indent .. hashes .. sep .. formatted
  return out, out ~= line
end

--- Format every heading in `[srow, erow]` (1-indexed, inclusive).
---
--- Fenced code blocks are skipped for the same reason `core.headings` skips
--- them when shifting: a `#` line inside a fence is a shell comment or nested
--- markdown, not a heading of this document.
---@param bufnr integer
---@param srow integer
---@param erow integer
---@param opts? Mkdn.HeadingFormatConfig
---@return integer changed # Number of heading lines rewritten.
function M.format_range(bufnr, srow, erow, opts)
  if type(srow) ~= "number" or type(erow) ~= "number" then return 0 end
  if srow < 1 or erow < srow then return 0 end

  bufnr = (bufnr == nil or bufnr == 0) and api.nvim_get_current_buf() or bufnr
  if not (api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr)) then return 0 end

  local last = api.nvim_buf_line_count(bufnr)
  erow = math.min(erow, last)
  if srow > last then return 0 end

  -- Fence state has to be read from the top of the buffer: a range starting
  -- inside a fenced block would otherwise look like ordinary prose.
  local in_fence = false
  local fence_pat = "^%s*[`~][`~][`~]+%S*%s*$"
  for _, line in ipairs(api.nvim_buf_get_lines(bufnr, 0, srow - 1, false)) do
    if line:match(fence_pat) then in_fence = not in_fence end
  end

  local lines = api.nvim_buf_get_lines(bufnr, srow - 1, erow, false)
  local changed = 0
  for i, line in ipairs(lines) do
    if line:match(fence_pat) then
      in_fence = not in_fence
    elseif not in_fence then
      local out, did = M.format_line(line, opts)
      if did then
        lines[i] = out
        changed = changed + 1
      end
    end
  end

  if changed > 0 then
    local view = vim.fn.winsaveview()
    api.nvim_buf_set_lines(bufnr, srow - 1, erow, false, lines)
    vim.fn.winrestview(view)
  end
  return changed
end

--- Format every heading in the buffer.
---@param bufnr integer
---@param opts? Mkdn.HeadingFormatConfig
---@return integer changed
function M.format_buffer(bufnr, opts)
  bufnr = (bufnr == nil or bufnr == 0) and api.nvim_get_current_buf() or bufnr
  if not (api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_is_valid(bufnr)) then return 0 end
  return M.format_range(bufnr, 1, api.nvim_buf_line_count(bufnr), opts)
end

return M
