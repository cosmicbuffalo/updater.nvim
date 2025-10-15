-- Example lualine integration for updater.nvim

-- Basic integration example
local basic_updater_component = {
  function()
    return require("updater").status.get_update_text()
  end,
  cond = function()
    return require("updater").status.has_updates()
  end,
  color = { fg = "#ff9e64" }, -- Orange color for updates
  on_click = function()
    require("updater").open()
  end,
}

-- Advanced integration with dynamic colors and icons
local advanced_updater_component = {
  function()
    return require("updater").status.get_update_text("icon")
  end,
  cond = function()
    return require("updater").status.has_updates()
  end,
  color = function()
    local status = require("updater").status.get()
    -- Different colors based on update type
    if status.needs_update and status.has_plugin_updates then
      return { fg = "#f7768e" } -- Red for both types
    elseif status.needs_update then
      return { fg = "#ff9e64" } -- Orange for dotfiles
    else
      return { fg = "#9ece6a" } -- Green for plugins only
    end
  end,
  on_click = function()
    require("updater").open()
  end,
}

-- Minimal integration (just shows count)
local minimal_updater_component = {
  function()
    local count = require("updater").status.get_update_count()
    return count > 0 and "󰚰 " .. count or ""
  end,
  cond = function()
    return require("updater").status.has_updates()
  end,
  color = { fg = "#ff9e64" },
  on_click = function()
    require("updater").open()
  end,
}

-- Example lualine setup
require("lualine").setup({
  sections = {
    lualine_x = {
      -- Choose one of the components above
      advanced_updater_component,

      -- Your other components
      "encoding",
      "fileformat",
      "filetype",
    },
  },
})
