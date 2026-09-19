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
  --
  -- Asserted by recording the setreg call rather than by reading the register
  -- back. With no OS clipboard provider -- every headless Linux runner, and
  -- what the CI log says: "clipboard: No provider" -- setreg("*") is a silent
  -- no-op and getreg("*") answers "" however correctly M.copy behaved. The
  -- claim this case makes is that the write still HAPPENS when the "+" write
  -- reported failure, so that is what it checks, and that holds on a machine
  -- with a provider and on one without alike.
  do
    local saved = package.loaded[LIB_PATH]
    package.loaded[LIB_PATH] = function(_text) return false end

    local real_setreg = vim.fn.setreg
    local selection_writes = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.setreg = function(reg, value, ...)
      if reg == "*" then selection_writes[#selection_writes + 1] = value end
      return real_setreg(reg, value, ...)
    end

    clipboard.copy("selection-probe-xyz")

    vim.fn.setreg = real_setreg
    package.loaded[LIB_PATH] = saved

    eq(
      selection_writes[1],
      "selection-probe-xyz",
      "copy: '*' register set even when '+' write failed"
    )
  end

  -- No lib.nvim: falls back to a direct setreg + round-trip verification via
  -- getreg.
  --
  -- The comment that used to sit here claimed "Neovim's registers hold the
  -- value in memory regardless of a provider, so the round trip succeeds".
  -- That is not true on a runner with no clipboard provider: setreg("+") is a
  -- silent no-op, getreg("+") answers "", and M.copy therefore reported false
  -- -- correctly, since nothing had been copied. The success path this case
  -- exists to cover was unreachable there, and the spec failed for a property
  -- of the runner rather than of the code.
  --
  -- Back the "+" register with a local so the round trip is real on every
  -- machine. What is under test is M.copy's own logic -- write, read back,
  -- report whether they agree -- not whether the host has xclip installed.
  do
    local saved = package.loaded[LIB_PATH]
    package.loaded[LIB_PATH] = nil
    package.preload[LIB_PATH] = function() error("synthetic: lib.nvim not installed") end

    local plus = ""
    local real_setreg, real_getreg = vim.fn.setreg, vim.fn.getreg
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.setreg = function(reg, value, ...)
      if reg == "+" then plus = value end
      return real_setreg(reg, value, ...)
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.getreg = function(reg, ...)
      if reg == "+" then return plus end
      return real_getreg(reg, ...)
    end

    local ok = clipboard.copy("fallback-probe")

    vim.fn.setreg, vim.fn.getreg = real_setreg, real_getreg
    package.preload[LIB_PATH] = nil
    package.loaded[LIB_PATH] = saved

    eq(ok, true, "copy: no-lib.nvim fallback reports success on a real round trip")
    eq(plus, "fallback-probe", "copy: '+' register actually holds the text")
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
