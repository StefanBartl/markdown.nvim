-- TESTS/health_spec.lua — `:checkhealth markdown` (lua/markdown/health.lua).
--
-- Drives M.check() with vim.health replaced by a recorder, asserting on what
-- was reported rather than a return value the function doesn't have (health
-- reporters are all side effect).

return function(H)
  local eq, ok = H.eq, H.ok

  ---@return table report
  ---@return table recorder
  local function recorder()
    local report = { ok = {}, info = {}, warn = {}, error = {}, start = {} }
    return report,
      {
        start = function(name) report.start[#report.start + 1] = name end,
        ok = function(msg) report.ok[#report.ok + 1] = msg end,
        info = function(msg) report.info[#report.info + 1] = msg end,
        warn = function(msg) report.warn[#report.warn + 1] = msg end,
        error = function(msg) report.error[#report.error + 1] = msg end,
      }
  end

  ---@param list string[]
  ---@param needle string
  ---@return boolean
  local function says(list, needle)
    for _, msg in ipairs(list) do
      if tostring(msg):find(needle, 1, true) then return true end
    end
    return false
  end

  ---@return table report
  local function checkhealth()
    local report, rec = recorder()
    local original = vim.health
    vim.health = rec
    local run_ok, err = pcall(require("markdown.health").check)
    vim.health = original
    if not run_ok then error(err, 0) end
    return report
  end

  require("markdown.config").setup({})

  -- ── A healthy checkout reports the plugin name and no errors. ──
  local report = checkhealth()
  eq(report.start[1], "markdown.nvim", "the report opens with the plugin name")
  eq(#report.error, 0, "a healthy checkout (lib.nvim present) reports no errors")
  ok(says(report.ok, "lib.nvim detected"), "lib.nvim is reported as present")
  ok(says(report.info, "links sanitize_on_save"), "config sanity is reported")
  ok(says(report.info, "fenced_scope"), "fenced_scope status is reported")

  -- links.picker sanity: a bad value warns, a good one is informational only.
  require("markdown.config").setup({ links = { picker = "bogus" } })
  report = checkhealth()
  ok(says(report.warn, "links.picker"), "an invalid links.picker value is warned about")

  require("markdown.config").setup({ links = { picker = "select" } })
  report = checkhealth()
  ok(says(report.info, "links picker: select"), "a valid links.picker value is reported as info")
  eq(#report.warn, 0, "and does not also warn")

  -- fenced_scope disabled is reported distinctly from enabled.
  require("markdown.config").setup({ fenced_scope = { enable = false } })
  report = checkhealth()
  ok(says(report.info, "fenced_scope: disabled"), "fenced_scope.enable=false is reported")

  -- fenced_scope provider='color_my_ascii' explicitly requested but
  -- unavailable warns (rather than silently using the fallback) — simulated
  -- at the require seam since color_my_ascii may or may not be on the rtp.
  do
    local saved = package.loaded["color_my_ascii"]
    package.loaded["color_my_ascii"] = nil
    package.preload["color_my_ascii"] = function() error("synthetic: not installed") end
    require("markdown.config").setup({ fenced_scope = { provider = "color_my_ascii" } })
    report = checkhealth()
    package.preload["color_my_ascii"] = nil
    package.loaded["color_my_ascii"] = saved
    ok(
      says(report.warn, "fenced_scope provider 'color_my_ascii' requested but"),
      "an explicitly requested but unavailable color_my_ascii provider warns"
    )
  end

  require("markdown.config").setup({})

  -- ── Regression: a missing lib.nvim used to crash the whole report. ──
  -- health.lua reported "lib.nvim not found" via `error_(...)` and then, a
  -- few lines later, unconditionally re-required the exact same module to
  -- hand the report off to it — raising and aborting the report right after
  -- the warning that was supposed to explain why. Simulated at the require
  -- seam (composer is a real sibling checkout in this suite otherwise)
  -- rather than by actually uninstalling lib.nvim.
  do
    local PATH = "lib.nvim.bindings.usercmd.composer"
    local saved = package.loaded[PATH]
    package.loaded[PATH] = nil
    package.preload[PATH] = function() error("synthetic: lib.nvim not installed") end

    local run_ok, run_err = pcall(function() report = checkhealth() end)

    package.preload[PATH] = nil
    package.loaded[PATH] = saved

    ok(
      run_ok,
      ("BUG regression: checkhealth must complete rather than raise when lib.nvim is missing (%s)"):format(
        tostring(run_err)
      )
    )
    ok(says(report.error, "lib.nvim not found"), "and still reports the missing dependency")
    ok(not says(report.ok, "lib.nvim detected"), "and does not also claim lib.nvim is present")
  end

  require("markdown.config").setup({})

  -- ── config module itself failing to load is reported, not raised. ──
  do
    package.loaded["markdown.config"] = nil
    package.preload["markdown.config"] = function() error("synthetic: config broken") end
    local run_ok = pcall(function() report = checkhealth() end)
    package.preload["markdown.config"] = nil
    package.loaded["markdown.config"] = nil
    require("markdown.config").setup({}) -- restore the real module for later specs
    ok(run_ok, "checkhealth completes even when markdown.config itself fails to load")
    ok(says(report.warn, "config module failed to load"), "and reports why")
  end
end
