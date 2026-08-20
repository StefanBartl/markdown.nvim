---@module 'markdown.core.html_links'
---@brief Extract link-like targets from raw HTML embedded in markdown.
---@description
--- Markdown documents carry HTML for everything the markdown syntax cannot
--- express, and the commonest case by far is a captioned image:
---
---     <figure>
---       <img src="assets/start.png" alt="Start Screen">
---       <figcaption>Abbildung 1: Start Screen</figcaption>
---     </figure>
---
--- To `core.link_scan` that block used to be prose: no `[text](target)`, no
--- bare URL, so no link -- and everything downstream (hover previews, `ml`,
--- `:Markdown links show`, dead-link diagnostics, and images.nvim, which
--- resolves through this plugin) went blind the moment a picture gained a
--- caption. This module is the missing half: `src` / `href` attributes
--- reported in exactly the `Mkdn.Link` shape the markdown scanner already
--- produces, so no consumer has to know which syntax a target came from.
---
--- Regex, not a parser, on purpose. The input is not a document -- it is one
--- line of a markdown file that happens to contain a tag, usually written by
--- hand and usually well-formed. A treesitter `html` injection would be more
--- correct and would also make every consumer depend on a parser being
--- installed for something meant to just work.
---
--- Column spans cover the **whole tag**, not just the quoted attribute value:
--- the cursor sitting on `<img` or inside `alt="..."` still means "this
--- image", the same way `link_scan` treats `![alt](src)` as one span rather
--- than only the part inside the parentheses.

local M = {}

local api = vim.api

--- Attributes that name a target, per tag. `<a>` is `href`; everything that
--- embeds a resource is `src`. Tags not listed here are ignored entirely --
--- an unknown tag carrying a `src` is far more likely to be machinery than a
--- link the user wants to follow.
local TARGET_ATTR = {
  a = "href",
  img = "src",
  source = "src",
  video = "src",
  audio = "src",
  embed = "src",
  iframe = "src",
}

--- Tags whose target is a media resource and whose `alt` supplies link text.
local MEDIA = { img = true, source = true, video = true, audio = true, embed = true }

---@internal
--- Value of attribute `name`, single- or double-quoted, or unquoted.
---@param attrs string
---@param name string
---@return string|nil
local function attr(attrs, name)
  local v = attrs:match(name .. '%s*=%s*"([^"]*)"') or attrs:match(name .. "%s*=%s*'([^']*)'")
  if v then return v end
  -- Unquoted values (`<img src=a.png>`) are legal HTML and turn up in
  -- hand-written markdown often enough to be worth the extra pattern.
  return attrs:match(name .. "%s*=%s*([^%s>\"']+)")
end

---@internal
--- Decode the five entities that actually occur inside `src`/`href` -- a
--- hand-written query string nearly always uses `&amp;`.
---@param s string
---@return string
local function unescape(s)
  s = s:gsub("&amp;", "&")
  s = s:gsub("&lt;", "<")
  s = s:gsub("&gt;", ">")
  s = s:gsub("&quot;", '"')
  s = s:gsub("&#39;", "'")
  return s
end

---@internal
---@param s string
---@return string
local function strip_tags(s) return (s:gsub("<[^>]*>", "")) end

--- Every HTML target on a single line.
---
--- The span of an `<a ...>` reaches its closing `</a>` when that sits on the
--- same line, so hovering the link *text* works and not only the tag itself.
---@param line string
---@param lnum integer 1-based
---@return Mkdn.Link[]
function M.from_line(line, lnum)
  local out = {}
  if not line or line == "" or not line:find("<", 1, true) then return out end

  local from = 1
  while true do
    local s, e, tag, attrs = line:find("<%s*(%a[%w]*)([^>]*)>", from)
    if not s then break end
    from = e + 1

    local lower = tag:lower()
    local name = TARGET_ATTR[lower]
    local raw = name and attr(attrs, name)
    if raw and raw ~= "" then
      local target = unescape(vim.trim(raw))
      local col_end = e
      local text

      if lower == "a" then
        local ts, te, inner = line:find("(.-)</%s*[aA]%s*>", e + 1)
        if ts then
          text = vim.trim(strip_tags(inner))
          col_end = te
          from = te + 1
        end
      elseif MEDIA[lower] then
        text = attr(attrs, "alt")
        if text then text = vim.trim(text) end
      end
      if text == "" then text = nil end

      out[#out + 1] = {
        display = text and ("%s -> %s"):format(text, target) or target,
        target = target,
        text = text,
        kind = MEDIA[lower] and "html_media" or "html_link",
        lnum = lnum,
        col = s - 1,
        col_end = col_end - 1,
      }
    end
  end

  return out
end

--- Every HTML target in `lines`; line numbers start at `first` (default 1).
---@param lines string[]
---@param first? integer
---@return Mkdn.Link[]
function M.from_lines(lines, first)
  first = first or 1
  local out = {}
  for i, line in ipairs(lines) do
    for _, link in ipairs(M.from_line(line, first + i - 1)) do
      out[#out + 1] = link
    end
  end
  return out
end

--- How far the enclosing-block search reaches in either direction. A figure
--- is a handful of lines by construction; a wider radius would start
--- attributing one block's image to the paragraph after the next one.
local BLOCK_RADIUS = 12

--- Text of the `<figcaption>` within `lines[open..close]`, tags stripped.
---@param lines string[]
---@param open integer
---@param close integer
---@return string|nil
function M.figcaption(lines, open, close)
  local joined = table.concat(vim.list_slice(lines, open, close), " ")
  local inner = joined:match("<%s*[fF][iI][gG][cC][aA][pP][tT][iI][oO][nN][^>]*>(.-)<%s*/")
  if not inner then return nil end
  local text = vim.trim((strip_tags(inner):gsub("%s+", " ")))
  if text == "" then return nil end
  return text
end

---@internal
--- The slice of `bufnr` around `row` a block search may look at.
---@param bufnr integer
---@param row integer 1-based
---@return string[]|nil lines
---@return integer first line number of `lines[1]`
---@return integer idx index of `row` within `lines`
local function window(bufnr, row)
  if not api.nvim_buf_is_valid(bufnr) then return nil, 0, 0 end
  local total = api.nvim_buf_line_count(bufnr)
  if row < 1 or row > total then return nil, 0, 0 end

  local first = math.max(1, row - BLOCK_RADIUS)
  local last = math.min(total, row + BLOCK_RADIUS)
  return api.nvim_buf_get_lines(bufnr, first - 1, last, false), first, row - first + 1
end

---@internal
--- Bounds of the `<tag>…</tag>` block containing `idx`, or nil for none.
---
--- Walks outwards from the cursor: opening tag above, closing tag below.
--- Stopping at the *other* delimiter first is what keeps a line that merely
--- sits between two unrelated blocks from matching one half of each -- the
--- difference between "inside a figure" and "near a figure", and the whole
--- reason this is a boundary walk rather than a fixed radius.
---@param lines string[]
---@param idx integer
---@param tag string lowercase, without brackets
---@return integer|nil open
---@return integer|nil close
local function enclosing_block(lines, idx, tag)
  local opening, closing = "<" .. tag, "</" .. tag

  local open
  for i = idx, 1, -1 do
    local l = lines[i]:lower()
    if i ~= idx and l:find(closing, 1, true) then break end
    if l:find(opening, 1, true) then
      open = i
      break
    end
  end
  if not open then return nil end

  local close
  for i = idx, #lines do
    local l = lines[i]:lower()
    if i ~= idx and i ~= open and l:find(opening, 1, true) then break end
    if l:find(closing, 1, true) then
      close = i
      break
    end
  end
  if not close then return nil end

  return open, close
end

---@internal
--- The first media link inside `lines[open..close]`, re-anchored onto `row`.
---
--- Re-anchoring matters because the caller located this link by row: the line
--- the tag was actually written on may be several away, and a consumer that
--- filters by column (`hover`) has to accept it wherever the cursor sits.
---@param lines string[]
---@param first integer
---@param open integer
---@param close integer
---@param row integer
---@param row_len integer byte length of the cursor's own line
---@return Mkdn.Link|nil
local function media_in_block(lines, first, open, close, row, row_len)
  local function anchor(link)
    link.lnum = row
    link.col = 0
    link.col_end = math.max(0, row_len)
    return link
  end

  for i = open, close do
    for _, link in ipairs(M.from_line(lines[i], first + i - 1)) do
      if link.kind == "html_media" then return anchor(link) end
    end
  end

  -- A tag broken across lines (`<img\n  src="x.png">`) is invisible to the
  -- per-line scan. Joining is safe *here* and nowhere else: the block's own
  -- boundaries are already known, so the join cannot reach into a picture the
  -- cursor is not actually inside.
  local joined = table.concat(vim.list_slice(lines, open, close), " ")
  for _, link in ipairs(M.from_line(joined, row)) do
    if link.kind == "html_media" then return anchor(link) end
  end

  return nil
end

--- The image of the `<figure>` block containing `row`, or nil.
---
--- This is what makes the *caption* line hoverable. A figure spreads one
--- logical thing over several lines, and the line a reader is most likely to
--- park on is the `<figcaption>` -- the one line that, taken alone, contains
--- no target at all. Resolving the block's `<img>` from anywhere inside it
--- makes the whole figure behave like the single `![alt](src)` it replaced.
---@param bufnr integer
---@param row integer 1-based
---@return Mkdn.Link|nil
function M.figure_at(bufnr, row)
  local lines, first, idx = window(bufnr, row)
  if not lines then return nil end

  local open, close = enclosing_block(lines, idx, "figure")
  if not open then return nil end
  ---@cast close integer

  local row_len = #(api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or "")
  local link = media_in_block(lines, first, open, close, row, row_len)
  if not link then return nil end

  -- The caption beats `alt` as a label when both exist: it is the text a
  -- reader actually sees rendered, and `alt` is often a terser duplicate.
  local caption = M.figcaption(lines, open, close)
  if caption then
    link.text = caption
    link.display = ("%s -> %s"):format(caption, link.target)
  end

  return link
end

--- The image of the media block containing `row` -- `<figure>` or, failing
--- that, `<picture>` -- or nil when `row` is inside neither.
---
--- The "or nil" is the load-bearing part. Callers used to answer this
--- question by scanning a fixed radius for any `src` at all, which made every
--- paragraph within a dozen lines of a picture look like that picture. A
--- block has ends; prose outside them is prose.
---@param bufnr integer
---@param row integer 1-based
---@return Mkdn.Link|nil
function M.media_at(bufnr, row)
  local link = M.figure_at(bufnr, row)
  if link then return link end

  local lines, first, idx = window(bufnr, row)
  if not lines then return nil end

  local open, close = enclosing_block(lines, idx, "picture")
  if not open then return nil end
  ---@cast close integer

  local row_len = #(api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or "")
  return media_in_block(lines, first, open, close, row, row_len)
end

return M
