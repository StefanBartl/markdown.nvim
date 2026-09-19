-- docs/TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by docs/TESTS/run.lua.

local H = {}

--- Assert equality; raises a descriptive error on mismatch (caught by the runner).
---@param a any # actual
---@param b any # expected
---@param msg string|nil
function H.eq(a, b, msg)
  if a ~= b then
    error(("FAIL %s: expected %q, got %q"):format(msg or "", tostring(b), tostring(a)), 2)
  end
end

--- Assert a truthy value.
---@param v any
---@param msg string|nil
function H.ok(v, msg)
  if not v then error(("FAIL %s: expected truthy, got %q"):format(msg or "", tostring(v)), 2) end
end

--- Fresh scratch buffer, made current, with an optional filetype.
---@param ft string|nil
---@return integer bufnr
function H.scratch(ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  if ft then vim.bo[buf].filetype = ft end
  return buf
end

--- Create a fixture directory under $TMPDIR and answer its CANONICAL path,
--- slash-separated.
---
--- Why this exists rather than `tempname() .. "/name"` inline: on macOS
--- $TMPDIR lives under `/var`, which is a symlink to `/private/var`.
--- `tempname()` hands back the unresolved spelling, but `:cd`, a buffer name
--- and anything that goes through `fs_realpath` hand back the resolved one.
--- A spec that builds its expectation from the raw path and compares it
--- against a path the editor produced is then comparing two spellings of one
--- directory, and fails on macOS while the code under test is correct.
--- Resolving once, here, keeps both sides in the same spelling everywhere.
---@param name string  fixture directory name
---@return string root  canonical, slash-separated, guaranteed to exist
function H.tmproot(name)
  local uv = vim.uv or vim.loop
  local base = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
  local root = (base .. "/" .. name):gsub("\\", "/")
  vim.fn.mkdir(root, "p")
  local real = uv.fs_realpath(root)
  return (real and real:gsub("\\", "/")) or root
end

return H
