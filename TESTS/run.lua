-- TESTS/run.lua — headless test runner for markdown.nvim.
--
-- Run from the repo root:
--   nvim --headless -u NONE -c "set rtp+=." -c "luafile TESTS/run.lua" -c "qa!"
-- or:
--   nvim --headless -u NONE -c "set rtp+=." -l TESTS/run.lua
--
-- Loads every *_spec.lua listed below, runs it against the shared harness,
-- prints a per-spec result, and exits non-zero on the first failing spec.

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local H = dofile(dir .. "harness.lua")

-- markdown.nvim depends on lib.nvim at runtime (core/table_mode.lua's
-- auto-format debounce), so the suite needs it on the runtimepath.
--
-- A sibling checkout wins over the plugin-manager copy on purpose: the
-- bootstrap clone under stdpath("data")/lazy is frequently older than the
-- working checkout, and testing against a stale lib.nvim gives misleading
-- failures. `$LIB_NVIM_PATH` overrides both (useful in CI).
local function add_lib_nvim()
  -- Built by appending, not as a literal: an unset $LIB_NVIM_PATH would put a
  -- nil at index 1 and `ipairs` would stop before checking anything.
  local candidates = {}
  if vim.env.LIB_NVIM_PATH then
    candidates[#candidates + 1] = vim.env.LIB_NVIM_PATH
  end
  candidates[#candidates + 1] = vim.fn.getcwd() .. "/../lib.nvim"
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"

  for _, path in ipairs(candidates) do
    -- Normalize first: the sibling candidate contains a ".." segment and the
    -- stdpath one mixes separators on Windows; the runtimepath module searcher
    -- does not resolve either, so an unnormalized entry silently finds nothing.
    local norm = vim.fs.normalize(path)
    if vim.fn.isdirectory(norm .. "/lua/lib") == 1 then
      vim.opt.rtp:append(norm)
      -- rtp alone is not enough here: the runtimepath searcher does not pick
      -- up entries appended after startup. lib.nvim's own README prescribes
      -- registering it on package.path as well (the C require searcher is the
      -- fallback that always applies).
      package.path = table.concat({
        norm .. "/lua/?.lua",
        norm .. "/lua/?/init.lua",
        package.path,
      }, ";")
      return norm
    end
  end
  return nil
end

local lib_path = add_lib_nvim()
if not lib_path then
  print("FAIL  cannot locate lib.nvim (a runtime dependency of markdown.nvim).")
  print("      Set $LIB_NVIM_PATH, or check it out next to this repo.")
  os.exit(1)
end

local specs = {
  "config_spec.lua",
  "path_spec.lua",
  "file_refs_spec.lua",
  "table_fmt_spec.lua",
  "table_fmt_config_spec.lua",
  "html_table_import_spec.lua",
  "blockquote_theme_spec.lua",
  "link_scan_spec.lua",
  "link_diagnostics_spec.lua",
  "picker_spec.lua",
  "toc_config_spec.lua",
  "headings_spec.lua",
  "handler_spec.lua",
  "handler_pdf_spec.lua",
  "handler_image_spec.lua",
  "tableview_spec.lua",
  "tableview_alignment_spec.lua",
  "tableview_resize_spec.lua",
  "browser_session_spec.lua",
  "fenced_scope_spec.lua",
  "session_features_spec.lua",
}

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(dir .. name)
  local ok, err = pcall(run, H)
  if ok then
    print(("ok    %s"):format(name))
  else
    failed = failed + 1
    print(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  print(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

print("\nMARKDOWN_TESTS_OK")
