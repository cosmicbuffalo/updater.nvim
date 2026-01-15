local Config = require("updater.config")
local Status = require("updater.status")
local Window = require("updater.window")
local Operations = require("updater.operations")
local Plugins = require("updater.plugins")
local Periodic = require("updater.periodic")
local Spinner = require("updater.spinner")
local Git = require("updater.git")
local Utils = require("updater.utils")
local Cache = require("updater.cache")
local M = {}

-- Expose status module for external integrations
M.status = Status

local config = {}

-- Get current config (for health checks and external integrations)
function M.get_config()
  return config
end
local state = Status.state -- Local reference for DRY code

local function render_callback(mode)
  if mode == "loading" then
    Window.render_loading_state(config)
  else
    Window.render(config)
  end
end

function M.open()
  if state.is_open then
    if vim.api.nvim_win_is_valid(state.window) then
      vim.api.nvim_set_current_win(state.window)
      return
    else
      state.is_open = false
    end
  end

  Window.create_window(config)

  -- Setup keymaps with callbacks
  Window.setup_keymaps(config, {
    close = M.close,
    update = function()
      Operations.update_repo(config, render_callback)
    end,
    refresh = function()
      Operations.refresh(config, render_callback)
    end,
    install_plugins = function()
      Plugins.install_plugin_updates(config, render_callback)
    end,
    update_all = function()
      Operations.update_dotfiles_and_plugins(config, render_callback)
    end,
  })

  Window.setup_autocmds(M.close)

  if Status.has_cached_data() then
    Window.render(config)
  else
    state.is_initial_load = true
    Window.render_loading_state(config)
  end

  vim.defer_fn(function()
    Operations.refresh(config, render_callback)
  end, 10)
end

function M.close()
  Spinner.stop_loading_spinner()
  Window.close()
end

function M.refresh()
  Operations.refresh(config, render_callback)
end

-- Async check for updates (non-blocking)
function M.check_updates()
  -- First validate the git repository (async, with caching)
  Git.validate_git_repository(config.repo_path, function(is_valid, validation_err)
    if not is_valid then
      vim.notify(
        "Invalid git repository: " .. (validation_err or "unknown error"),
        vim.log.levels.ERROR,
        { title = config.notify.error.title }
      )
      return
    end

    -- Now check for updates asynchronously
    Git.get_repo_status(config, config.repo_path, function(status)
      if status.error then
        vim.notify(config.notify.error.message, vim.log.levels.ERROR, { title = config.notify.error.title })
        return
      end

      state.current_branch = status.branch
      state.ahead_count = status.ahead
      state.behind_count = status.behind
      state.needs_update = status.behind > 0
      state.last_check_time = os.time()

      Cache.update_after_check(config.repo_path, state, function()
        if state.needs_update then
          local message = Utils.generate_outdated_message(config, status)
          vim.notify(message, vim.log.levels.WARN, { title = config.notify.outdated.title })
        else
          local message = Utils.generate_up_to_date_message(config, status)
          vim.notify(message, vim.log.levels.INFO, { title = config.notify.up_to_date.title })
        end
      end)
    end)
  end)
end

function M.start_periodic_check()
  Periodic.stop_periodic_check()
  Periodic.setup_periodic_check(config)
end

function M.stop_periodic_check()
  Periodic.stop_periodic_check()
end

local function load_debug_module()
  local debug = require("updater.debug")
  debug.init(config)
  return debug
end

local function setup_user_commands()
  vim.api.nvim_create_user_command("UpdaterOpen", M.open, { desc = "Open Updater" })
  vim.api.nvim_create_user_command("UpdaterCheck", M.check_updates, { desc = "Check for updates" })
  vim.api.nvim_create_user_command(
    "UpdaterStartChecking",
    M.start_periodic_check,
    { desc = "Start periodic update checking" }
  )
  vim.api.nvim_create_user_command(
    "UpdaterStopChecking",
    M.stop_periodic_check,
    { desc = "Stop periodic update checking" }
  )

  vim.api.nvim_create_user_command("UpdaterDebugToggle", function()
    local debug = load_debug_module()
    debug.register_commands()
    debug.toggle_debug_mode()
  end, { desc = "Toggle Updater debug mode" })
end

function M.setup(opts)
  -- Disable plugin in headless mode
  if vim.fn.has("nvim") == 1 and (vim.g.headless or vim.v.argv[2] == "--headless" or vim.v.argv[3] == "--headless") then
    return
  end

  local setup_config, error_msg = Config.setup_config(opts)
  if not setup_config then
    vim.notify(error_msg, vim.log.levels.ERROR, { title = "Updater Configuration" })
    return
  end

  config = setup_config

  vim.keymap.set("n", config.keymap.open, M.open, { noremap = true, silent = true, desc = "Open Updater" })
  setup_user_commands()

  Periodic.setup_startup_check(config, M.check_updates)
  Periodic.setup_periodic_check(config)
end

return M
