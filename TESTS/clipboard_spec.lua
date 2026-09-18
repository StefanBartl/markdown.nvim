-- TESTS/clipboard_spec.lua — util.clipboard: M.copy()'s return value.
--
-- Regression coverage for the recent fix (commit 0d8f0ad): M.copy() used to
-- discard lib.nvim's writer's return value and, in the no-lib.nvim fallback,
-- trusted a bare pcall(setreg) not raising as proof of a copy -- setreg("+",
-- ...) never raises for lack of a provider, it just silently does nothing.
-- M.copy now returns whether the "+" register actually holds the text.
--
-- The require inside M.copy() is a fresh pcall(require, ...) on every call
-- (not bound to an upvalue at module load time), so package.loaded can be
-- stubbed right before each call rather than before requiring clipboard.lua.

return function(H)
  local eq = H.eq
  local clipboard = require("markdown.util.clipboard")

  local LIB_PATH = "lib.nvim.cross.copy_to_clipboard"

  -- lib.nvim present: M.copy forwards its writer's return value verbatim.
  do
    local saved = package.loaded[LIB_PATH]

    package.loaded[LIB_PATH] = function(_text) return true end
    eq(clipboard.copy("hello"), true, "copy: forwards lib.nvim's writer returning true")

    package.loaded[LIB_PATH] = function(_text) return false end
    eq(clipboard.copy("hello"), false, "copy: forwards lib.nvim's writer returning false")

    package.loaded[LIB_PATH] = saved
  end

  -- The "*" (selection) register is always set locally, regardless of the
  -- "+" outcome -- this is documented, unconditional behavior.
  do
    local saved = package.loaded[LIB_PATH]
    package.loaded[LIB_PATH] = function(_text) return false end
    clipboard.copy("selection-probe-xyz")
    package.loaded[LIB_PATH] = saved
    eq(
      vim.fn.getreg("*"),
      "selection-probe-xyz",
      "copy: '*' register set even when '+' write failed"
    )
  end

  -- No lib.nvim: falls back to a direct setreg + round-trip verification via
  -- getreg. In this headless suite there is no OS clipboard provider, but
  -- Neovim's registers hold the value in memory regardless of a provider, so
  -- the round-trip check succeeds and BUG regression (the round trip not
  -- being checked at all) is instead exercised below by forcing a mismatch.
  do
    local saved = package.loaded[LIB_PATH]
    package.loaded[LIB_PATH] = nil
    package.preload[LIB_PATH] = function() error("synthetic: lib.nvim not installed") end

    local ok = clipboard.copy("fallback-probe")
    eq(ok, true, "copy: no-lib.nvim fallback reports success on a real round trip")
    eq(vim.fn.getreg("+"), "fallback-probe", "copy: '+' register actually holds the text")

    package.preload[LIB_PATH] = nil
    package.loaded[LIB_PATH] = saved
  end

  -- BUG regression: the fallback must not just trust a non-raising setreg --
  -- it verifies the round trip. Force getreg to disagree with what was set
  -- (simulating "setreg silently did nothing", the exact scenario the old
  -- bare-pcall check could not detect) and confirm copy() now reports false.
  do
    local saved = package.loaded[LIB_PATH]
    package.loaded[LIB_PATH] = nil
    package.preload[LIB_PATH] = function() error("synthetic: lib.nvim not installed") end

    local real_getreg = vim.fn.getreg
    vim.fn.getreg = function(reg)
      if reg == "+" then return "" end -- simulate "the write silently did nothing"
      return real_getreg(reg)
    end

    local ok = clipboard.copy("will-not-really-land")
    vim.fn.getreg = real_getreg
    package.preload[LIB_PATH] = nil
    package.loaded[LIB_PATH] = saved

    eq(
      ok,
      false,
      "BUG regression: copy() reports false when the '+' register doesn't actually hold the text"
    )
  end
end
