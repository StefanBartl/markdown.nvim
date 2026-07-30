-- TESTS/handler_image_spec.lua — image targets: system-app/in-nvim preview.
--
-- Mirrors handler_pdf_spec's shape. `mi` (markdown.handler.image.open) used
-- to always shell out to the system viewer; with snacks.nvim or image.nvim
-- installed it can render into a float instead:
--   * no provider installed   -> system viewer directly, no prompt.
--   * provider + preview="ask"     -> ask via markdown.util.picker.
--   * provider + preview="preview" -> preview, no prompt.
--   * provider + preview="system"  -> system viewer, no prompt.
-- A failing preview must fall back to the system viewer rather than leaving
-- the user with nothing.
---@diagnostic disable: missing-fields

return function(H)
  local eq = H.eq

  local function reset()
    package.loaded["markdown.handler.image"] = nil
    package.loaded["markdown.util.image_preview"] = nil
    package.loaded["markdown.util.picker"] = nil
    package.loaded["snacks"] = nil
    package.loaded["image"] = nil
  end

  --- Stub the preview module. `previewed` records the path it was asked for.
  ---@param available boolean
  ---@param result boolean  what preview() reports
  ---@return table state
  local function stub_preview(available, result)
    local state = { previewed = nil }
    package.loaded["markdown.util.image_preview"] = {
      available = function()
        return available
      end,
      detect = function()
        return available and "snacks" or nil
      end,
      preview = function(p)
        state.previewed = p
        return result, result and nil or "stubbed failure"
      end,
    }
    return state
  end

  --- Run `fn` with vim.ui.open stubbed; returns the path it was handed.
  ---@param fn fun()
  ---@return string|nil
  local function with_system_opener(fn)
    local opened = nil
    local orig = vim.ui.open
    vim.ui.open = function(p)
      opened = p
      return true, nil
    end
    local ok, err = pcall(fn)
    vim.ui.open = orig
    if not ok then
      error(err, 0)
    end
    return opened
  end

  -- Case 1: no provider installed -> system viewer, no prompt.
  do
    reset()
    local state = stub_preview(false, false)
    package.loaded["markdown.util.picker"] = {
      select = function()
        error("must not prompt when no preview provider is installed")
      end,
    }

    local opened = with_system_opener(function()
      require("markdown.handler.image").open_image("C:/img/pic.png")
    end)

    eq(opened, "C:/img/pic.png", "no provider -> opened via the system app")
    eq(state.previewed, nil, "no provider -> preview never attempted")
  end

  -- Case 2: provider installed, preview = "ask", user picks the preview.
  do
    reset()
    local state = stub_preview(true, true)
    package.loaded["markdown.util.picker"] = {
      select = function(items, opts, on_choose)
        eq(opts.prompt, "Open image with:", "picker prompt describes the choice")
        eq(#items, 2, "two choices are offered")
        on_choose(items[2]) -- "Preview in Neovim"
      end,
    }

    local image = require("markdown.handler.image")
    image.config.preview = "ask"
    image.open_image("C:/img/pic.png")

    eq(state.previewed, "C:/img/pic.png", "'Preview in Neovim' renders in-nvim")
  end

  -- Case 3: provider installed, preview = "ask", user picks the system app.
  do
    reset()
    local state = stub_preview(true, true)
    package.loaded["markdown.util.picker"] = {
      select = function(items, _opts, on_choose)
        on_choose(items[1]) -- "System app"
      end,
    }

    local opened = with_system_opener(function()
      local image = require("markdown.handler.image")
      image.config.preview = "ask"
      image.open_image("C:/img/pic.png")
    end)

    eq(opened, "C:/img/pic.png", "'System app' choice still opens via the system app")
    eq(state.previewed, nil, "'System app' choice does not preview")
  end

  -- Case 4: preview = "system" never prompts, even with a provider present.
  do
    reset()
    local state = stub_preview(true, true)
    package.loaded["markdown.util.picker"] = {
      select = function()
        error("preview='system' must not prompt")
      end,
    }

    local opened = with_system_opener(function()
      local image = require("markdown.handler.image")
      image.config.preview = "system"
      image.open_image("C:/img/pic.png")
    end)

    eq(opened, "C:/img/pic.png", "preview='system' goes straight to the system app")
    eq(state.previewed, nil, "preview='system' never previews")
  end

  -- Case 5: preview = "preview" never prompts either.
  do
    reset()
    local state = stub_preview(true, true)
    package.loaded["markdown.util.picker"] = {
      select = function()
        error("preview='preview' must not prompt")
      end,
    }

    local image = require("markdown.handler.image")
    image.config.preview = "preview"
    image.open_image("C:/img/pic.png")

    eq(state.previewed, "C:/img/pic.png", "preview='preview' renders in-nvim without asking")
  end

  -- Case 6: a failing preview falls back to the system viewer.
  --
  -- The user asked to see the image, not to use a particular renderer — an
  -- unsupported terminal must not mean nothing opens at all.
  do
    reset()
    local state = stub_preview(true, false) -- available, but preview() fails
    local opened = with_system_opener(function()
      local image = require("markdown.handler.image")
      image.config.preview = "preview"
      image.open_image("C:/img/pic.png")
    end)

    eq(state.previewed, "C:/img/pic.png", "preview was attempted")
    eq(opened, "C:/img/pic.png", "a failed preview falls back to the system viewer")
  end

  -- Case 7: a remote image always goes to the system handler (the browser) —
  -- there is no local file for a provider to read.
  do
    reset()
    local state = stub_preview(true, true)
    package.loaded["markdown.util.picker"] = {
      select = function()
        error("a URL target must not prompt")
      end,
    }

    local opened = with_system_opener(function()
      local image = require("markdown.handler.image")
      image.config.preview = "preview"
      image.open_image("https://example.com/pic.png")
    end)

    eq(opened, "https://example.com/pic.png", "a URL image opens with the system handler")
    eq(state.previewed, nil, "a URL image is never sent to a preview provider")
  end

  reset()
end
