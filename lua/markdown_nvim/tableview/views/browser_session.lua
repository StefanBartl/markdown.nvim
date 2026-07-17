---@module 'markdown_nvim.tableview.views.browser_session'
---@brief Shared "reuse one tab" plumbing for the TableView browser exports.
---@description
--- browser_basic.lua / browser_niceified.lua used to write a fresh
--- `vim.fn.tempname()` file and hand it to the system opener on every call —
--- over a longer session (repeatedly checking a table while editing it) that
--- piles up one browser tab per call.
---
--- This plugin has no server/socket (README: "No external tools required. All
--- features run on built-in Neovim APIs."), so there is no live channel back
--- into an already-open tab. Real reuse is therefore built from three parts:
---   1. a FIXED file path per style, so repeated calls overwrite the same file
---      instead of creating a new one;
---   2. the system opener is invoked only once per style per Neovim session —
---      after that, calls just rewrite the file;
---   3. a small script embedded in the page polls-and-reloads on an interval,
---      so the already-open tab picks up the new content on its own, with the
---      scroll position preserved across the reload.
--- `force_new` (the `reopen` argument on `:Markdown table view browser`)
--- resets the "already opened" flag for when the tab was closed by hand.
local M = {}

local platform = require("markdown_nvim.util.platform")

---@type table<string, boolean>
local opened = {}

---@param style_key string
---@return string
local function fixed_path(style_key)
  local dir = vim.fn.stdpath("cache") .. "/markdown_nvim"
  vim.fn.mkdir(dir, "p")
  return dir .. "/tableview_" .. style_key .. ".html"
end

-- Reloads the page on an interval so an already-open tab shows fresh content
-- without a new tab ever being spawned, and restores the scroll position
-- across the reload so repeated checks don't keep jumping back to the top.
local AUTO_REFRESH_SCRIPT = [[
<script>
(function () {
  var KEY = 'markdown_nvim_tableview_scroll';
  var y = sessionStorage.getItem(KEY);
  if (y !== null) window.scrollTo(0, parseInt(y, 10) || 0);
  window.addEventListener('pagehide', function () {
    sessionStorage.setItem(KEY, String(window.scrollY));
  });
  setInterval(function () { window.location.reload(); }, 1500);
})();
</script>
]]

--- Write `html` to the fixed file for `style_key` and open it in the system
--- browser — but only the first time per style per Neovim session; later
--- calls just update the file, and the page's own auto-refresh picks it up.
---@param html string full HTML document
---@param style_key string "basic" | "niceified" — one fixed tab per style
---@param force_new boolean|nil force a fresh tab even if one was opened before
---@return boolean ok, string|nil err
function M.show(html, style_key, force_new)
  local path = fixed_path(style_key)

  local with_refresh = html:gsub("</body>", AUTO_REFRESH_SCRIPT .. "</body>", 1)

  local fh, err = io.open(path, "w")
  if not fh then
    return false, "failed to write preview file: " .. tostring(err)
  end
  fh:write(with_refresh)
  fh:close()

  if force_new then
    opened[style_key] = false
  end
  if opened[style_key] then
    -- A tab is presumably already open; it will pick up the new content on
    -- its next auto-refresh tick.
    return true
  end

  local ok, open_err = platform.open(path)
  if ok then
    opened[style_key] = true
  end
  return ok, open_err
end

-- Exposed for tests only.
M._opened = opened
M._fixed_path = fixed_path

return M
