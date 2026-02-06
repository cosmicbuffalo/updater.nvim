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
local Version = require("updater.version")
local ReleaseDetails = require("updater.release_details")
local M = {}

-- Expose status module for external integrations
M.status = Status

local config = {}

function M.get_config()
  return config
end
local state = Status.state

local function render_callback(mode, opts)
  if mode == "loading" then
    Window.render_loading_state(config)
  else
    Window.render(config, opts)
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
      if config.versioned_releases_only then
        -- In versioned releases mode, switch to the latest release tag
        -- Same behavior as hitting 's' on the latest release
        Version.switch_to_latest(config, function(success, msg)
          if success then
            -- Just render to show the success message, don't refresh
            render_callback()
          else
            vim.notify(msg, vim.log.levels.ERROR, { title = "Updater" })
          end
        end, render_callback)
      else
        Operations.update_dotfiles_and_plugins(config, render_callback)
      end
    end,
    toggle_release = function()
      -- Get current cursor position (1-indexed in vim)
      local cursor_pos = vim.api.nvim_win_get_cursor(state.window)
      local cursor_line = cursor_pos[1] - 1 -- Convert to 0-indexed for line mapping
      local cursor_col = cursor_pos[2]
      local tag = ReleaseDetails.get_release_at_line(cursor_line)
      if tag then
        -- Create a callback that restores cursor position after render
        local restore_cursor_callback = function()
          render_callback()
          -- Restore cursor position after render
          vim.schedule(function()
            if state.window and vim.api.nvim_win_is_valid(state.window) then
              -- Clamp line to buffer bounds
              local line_count = vim.api.nvim_buf_line_count(state.buffer)
              local target_line = math.min(cursor_pos[1], line_count)
              vim.api.nvim_win_set_cursor(state.window, { target_line, cursor_col })
            end
          end)
        end
        ReleaseDetails.toggle_release(config, tag, restore_cursor_callback)
      end
    end,
    switch_to_release = function()
      -- Get current cursor position (1-indexed in vim)
      local cursor_pos = vim.api.nvim_win_get_cursor(state.window)
      local cursor_line = cursor_pos[1] - 1 -- Convert to 0-indexed for line mapping
      local tag = ReleaseDetails.get_release_at_line(cursor_line)
      if tag then
        -- Check if already on this release
        if state.current_release == tag then
          vim.notify("Already on " .. tag, vim.log.levels.ERROR, { title = "Updater" })
          return
        end
        -- Create a callback that positions cursor on the switched-to tag
        local switch_render_callback = function(mode)
          render_callback(mode, { cursor_on_tag = tag })
        end
        Version.switch_to_version(config, tag, function(success, msg)
          if success then
            -- Render with cursor on the tag we switched to
            switch_render_callback()
          else
            vim.notify(msg, vim.log.levels.ERROR, { title = "Updater" })
          end
        end, switch_render_callback)
      end
    end,
    copy_release_url = function()
      -- Get current cursor position (1-indexed in vim)
      local cursor_pos = vim.api.nvim_win_get_cursor(state.window)
      local cursor_line = cursor_pos[1] - 1 -- Convert to 0-indexed for line mapping
      local tag = ReleaseDetails.get_release_at_line(cursor_line)
      if tag then
        -- Get the release details to find the URL
        local details = Status.get_release_details(tag)
        if details and details.url then
          vim.fn.setreg("+", details.url)
          vim.fn.setreg("*", details.url)
          vim.notify("Copied: " .. details.url, vim.log.levels.INFO, { title = "Updater" })
        else
          -- Construct URL from config if details not loaded
          local remote_url = config.github_url or config.remote_url
          if remote_url then
            local url = remote_url:gsub("%.git$", "") .. "/releases/tag/" .. tag
            vim.fn.setreg("+", url)
            vim.fn.setreg("*", url)
            vim.notify("Copied: " .. url, vim.log.levels.INFO, { title = "Updater" })
          else
            vim.notify("Could not determine release URL", vim.log.levels.WARN, { title = "Updater" })
          end
        end
      end
    end,
  })

  Window.setup_autocmds(M.close, config)

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

  vim.api.nvim_create_user_command("DotfilesVersion", function(opts)
    Version.handle_command(config, opts.args and vim.trim(opts.args) or "")
  end, {
    nargs = "?",
    complete = function(arglead)
      return Version.get_completion_list(config, arglead)
    end,
    desc = "Switch dotfiles to a specific version or show available versions",
  })
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
