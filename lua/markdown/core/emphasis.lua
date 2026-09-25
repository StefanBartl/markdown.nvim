---@module 'markdown.core.emphasis'
---@brief Marker-stripping rules for `**bold**`/`*italic*`/`~~struck~~` text.
---@description
--- Shared by heading_format (heading TEXT normalization) and body_format
--- (`:Markdown format`). Each function takes one PLAIN segment of text --
--- code spans, link targets, and raw HTML/autolinks are already carved out
--- by core.inline_segment before any of these run, so none of them need to
--- know about that.

local M = {}

--- Drop ALL emphasis/strikethrough markers: `*` runs and `~~` runs
--- unconditionally, `_` runs only on a word boundary (`foo_bar` survives,
--- `_bar_` does not). Used by `heading_format` and by
--- `:Markdown format strip-emphasis`.
---
--- Deliberately blunt: a run of 1 vs 2 vs 3 markers is genuinely ambiguous
--- (italic vs bold vs both) without a full CommonMark emphasis-matching
--- pass, so this removes all of it in one go rather than guessing.
---@param s string
---@return string
function M.strip_all(s)
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

--- Drop `**bold**` and boundary-safe `__bold__` markers, leaving a bare
--- `*italic*`/`_italic_` run untouched. A `***bold+italic***` run is peeled
--- symmetrically (two markers off each side), leaving `*italic*` behind --
--- there is deliberately no standalone "strip italic": telling it apart from
--- `**bold**`/`***both***` needs the same ambiguous run-length parse
--- `strip_all` avoids.
---
--- Intraword `__` (`foo__bar__baz`) is not emphasis in GFM and is left
--- alone, mirroring `strip_all`'s underscore boundary rule.
---@param s string
---@return string
function M.strip_bold(s)
  s = (s:gsub("%*%*(.-)%*%*", "%1"))

  local out, i, n = {}, 1, #s
  while i <= n do
    local consumed = false
    if s:sub(i, i + 1) == "__" then
      local before = i > 1 and s:sub(i - 1, i - 1) or ""
      if before == "" or before:match("[%s%p]") then
        local close = s:find("__", i + 2, true)
        if close then
          local after = s:sub(close + 2, close + 2)
          if after == "" or after:match("[%s%p]") then
            out[#out + 1] = s:sub(i + 2, close - 1)
            i = close + 2
            consumed = true
          end
        end
      end
    end
    if not consumed then
      out[#out + 1] = s:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Drop `~~struck~~` markers.
---@param s string
---@return string
function M.strip_strikethrough(s) return (s:gsub("~~(.-)~~", "%1")) end

return M
