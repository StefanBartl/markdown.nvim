-- TESTS/testing_config_spec.lua -- pins the guard modes of .testing.lua.
--
-- Regression: `guards.deprecation` stayed on "warn" after the one deprecated call that had
-- justified it (`vim.highlight` in tableview/renderer.lua) was gone, so a new use of a deprecated
-- API in the plugin or a spec only printed a warning instead of failing the run. All four guards
-- must stay "error"; a relaxation has to be a deliberate change that touches this spec too.

return function(H)
  local eq, ok = H.eq, H.ok

  -- The repo root is the directory that holds lua/markdown (it is on the runtimepath of every spec).
  local init = vim.api.nvim_get_runtime_file("lua/markdown/init.lua", false)[1]
  ok(init ~= nil, "lua/markdown/init.lua is on the runtimepath")
  local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(init))))
  local path = root .. "/.testing.lua"
  ok(vim.uv.fs_stat(path) ~= nil, ".testing.lua exists at the repo root: " .. path)

  local chunk, err = loadfile(path)
  ok(chunk ~= nil, ".testing.lua loads: " .. tostring(err))
  local cfg = chunk()
  ok(type(cfg) == "table", ".testing.lua returns a table")
  ok(type(cfg.guards) == "table", ".testing.lua configures guards")

  --- A guard is configured as a bare mode or as `{ mode = ... }`.
  ---@param name string
  ---@return string|nil
  local function mode_of(name)
    local g = cfg.guards[name]
    if type(g) == "table" then return g.mode end
    return g
  end

  for _, name in ipairs({ "fs", "state", "process_net", "deprecation" }) do
    eq(mode_of(name), "error", "guards." .. name .. " is checked strictly")
  end

  -- The strict mode is only sustainable while the plugin itself is deprecation-free: the one
  -- former offender may only use the deprecated name as the fallback of `vim.hl`.
  local renderer = root .. "/lua/markdown/tableview/renderer.lua"
  local lines = vim.fn.readfile(renderer)
  local found = false
  for _, line in ipairs(lines) do
    if line:find("vim.highlight", 1, true) and not line:match("^%s*%-%-") then
      found = true
      ok(
        line:find("vim.hl or vim.highlight", 1, true),
        "renderer: vim.highlight only as the fallback of vim.hl"
      )
    end
  end
  ok(found, "renderer.lua still resolves the highlight helper (fixture sanity)")
end
