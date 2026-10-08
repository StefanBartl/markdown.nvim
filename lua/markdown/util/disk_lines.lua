---@module 'markdown.util.disk_lines'
--- Read and write a file as a list of lines WITHOUT losing how it was stored.
---
--- `vim.fn.readfile(path)` / `vim.fn.writefile(lines, path)` (the plain, text-mode
--- pair) throw three things away on the way through: the UTF-8 byte order mark,
--- the CRLF line terminators and whether the last line was terminated at all.
--- A formatter that read and wrote a file that way turned every changed CRLF
--- file into a whole-file diff. `read` keeps all three in a `meta` table and
--- `write` puts them back, so only the lines an op actually changed differ.
---
--- Line endings follow Neovim's own default ('fileformats' = unix,dos): a file
--- is CRLF only when EVERY terminated line ends in CR LF. A file that mixes
--- the two is LF, and the CR stays at the end of the lines that had one -- the
--- same thing the buffer path shows -- so it is written back byte for byte.

local M = {}

local BOM = "\239\187\191"

---@class Mkdn.DiskLinesMeta
---@field bom boolean            the file started with a UTF-8 byte order mark
---@field crlf boolean           every terminated line ended in CR LF
---@field final_newline boolean  the last line was terminated

--- Read `path` as lines, remembering its BOM, line ending and final newline.
--- Raises (E484) like `readfile` when the file cannot be read; callers pcall it.
---@param path string
---@return string[] lines  without BOM and without the CR of a CRLF terminator
---@return Mkdn.DiskLinesMeta meta
function M.read(path)
  -- Binary mode: keeps the CRs and the BOM, and a terminated last line shows
  -- up as one extra empty item (the file's own end of file, not a blank line).
  local lines = vim.fn.readfile(path, "b")

  local final_newline = #lines > 0 and lines[#lines] == ""
  if final_newline then lines[#lines] = nil end

  local bom = false
  if lines[1] and lines[1]:sub(1, 3) == BOM then
    bom = true
    lines[1] = lines[1]:sub(4)
  end

  -- An unterminated last line carries no line ending, so it does not vote.
  local terminated = final_newline and #lines or (#lines - 1)
  local crlf = terminated > 0
  for i = 1, terminated do
    if lines[i]:sub(-1) ~= "\r" then
      crlf = false
      break
    end
  end
  if crlf then
    for i = 1, terminated do
      lines[i] = lines[i]:sub(1, -2)
    end
  end

  return lines, { bom = bom, crlf = crlf, final_newline = final_newline }
end

--- Write `lines` to `path` with the BOM, line ending and final newline `meta`
--- (from `read`) describes. Does not raise.
---@param path string
---@param lines string[]
---@param meta Mkdn.DiskLinesMeta
---@return boolean ok
function M.write(path, lines, meta)
  local out = {}
  local n = #lines
  -- Only a terminated line gets the CR; the last line of a file without a
  -- final newline has no terminator to put it in front of.
  local last_terminated = meta.final_newline and n or (n - 1)
  for i = 1, n do
    local line = lines[i]
    if meta.crlf and i <= last_terminated then line = line .. "\r" end
    out[i] = line
  end
  if meta.bom and out[1] then out[1] = BOM .. out[1] end
  -- Binary mode writes no NL after the last item; an empty last item is what
  -- makes the file end in one.
  if meta.final_newline and n > 0 then out[#out + 1] = "" end

  local ok, res = pcall(vim.fn.writefile, out, path, "b")
  return ok and res == 0
end

return M
