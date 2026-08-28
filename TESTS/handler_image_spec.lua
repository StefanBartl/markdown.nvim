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
    package.loaded["lib.nvim.image_preview"] = nil
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
    package.loaded["lib.nvim.image_preview"] = {
      available = function() return available end,
      detect = function() return available and "snacks" or nil end,
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
    if not ok then error(err, 0) end
    return opened
  end

  -- Case 0: what counts as an image target under the cursor.
  --
  -- The interesting half is the negative: `extract` used to scan a fixed
  -- radius for any `<img src>` at all, so a paragraph a few lines under a
  -- figure claimed to *be* that figure and `ma`/`mi` opened it. A block has
  -- ends; prose outside them is prose.
  do
    reset()
    local image = require("markdown.handler.image")

    eq(image.extract("![alt](pic.png)"), "pic.png", "extract: markdown image")
    eq(image.extract("[doc](notes.md)"), nil, "extract: a plain link is not an image")
    eq(image.extract('<img src="pic.png">'), "pic.png", "extract: img on the line itself")

    local buf = H.scratch("markdown")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Doc", -- 1
      "", -- 2
      "<figure>", -- 3
      '  <img src="assets/start.png" alt="Start Screen">', -- 4
      "  <figcaption>Abbildung 1: Start Screen</figcaption>", -- 5
      "</figure>", -- 6
      "", -- 7
      "Prosa, die zufaellig unter einer Abbildung steht.", -- 8
      "", -- 9
      "<picture>", -- 10
      '  <source src="wide.webp">', -- 11
      "</picture>", -- 12
    })

    local function extract_at(row)
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
      return image.extract(line)
    end

    eq(extract_at(5), "assets/start.png", "extract: figcaption line resolves the figure")
    eq(extract_at(6), "assets/start.png", "extract: closing tag resolves the figure")
    eq(extract_at(3), "assets/start.png", "extract: opening tag resolves the figure")
    eq(extract_at(11), "wide.webp", "extract: a <picture> block resolves too")

    eq(extract_at(8), nil, "extract: prose near a figure is not the figure")
    eq(extract_at(1), nil, "extract: a heading near a figure is not the figure")
    eq(extract_at(9), nil, "extract: the gap between two blocks belongs to neither")

    vim.api.nvim_win_set_cursor(0, { 8, 0 })
    eq(
      image.is_image_line("Prosa, die zufaellig unter einer Abbildung steht."),
      false,
      "is_image_line: false for prose that merely sits near a picture"
    )

    vim.api.nvim_buf_delete(buf, { force = true })
  end

  -- Case 1: no provider installed -> system viewer, no prompt.
  do
    reset()
    local state = stub_preview(false, false)
    package.loaded["markdown.util.picker"] = {
      select = function() error("must not prompt when no preview provider is installed") end,
    }

    local opened = with_system_opener(
      function() require("markdown.handler.image").open_image("C:/img/pic.png") end
    )

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
      select = function() error("preview='system' must not prompt") end,
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
      select = function() error("preview='preview' must not prompt") end,
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
      select = function() error("a URL target must not prompt") end,
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
