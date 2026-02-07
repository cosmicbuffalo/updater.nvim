local Config = require("updater.config")
local Status = require("updater.status")
local Utils = require("updater.utils")
local Errors = require("updater.errors")
local M = {}

function M.init()
  -- No-op, kept for backwards compatibility
  -- Config is now retrieved via Config.get()
end

function M.toggle_debug_mode()
  local config = Config.get()
  if not config then
    Errors.notify_error("Debug module not initialized", "Debug module")
    return
  end

  if Status.state.debug_enabled then
    -- Disable debug mode
    Status.state.debug_enabled = false
    vim.notify("Updater debug mode disabled", vim.log.levels.INFO, { title = "Updater Debug" })
  else
    -- Enable debug mode with defaults if not set
    Status.state.debug_enabled = true
    if Status.state.debug_simulate_dotfiles == 0 and Status.state.debug_simulate_plugins == 0 then
      Status.state.debug_simulate_dotfiles = 2
      Status.state.debug_simulate_plugins = 3
    end

    local dotfiles = Status.state.debug_simulate_dotfiles
    local plugins = Status.state.debug_simulate_plugins
    vim.notify(
      string.format("Updater debug mode: simulating %d dotfile update(s), %d plugin update(s)", dotfiles, plugins),
      vim.log.levels.INFO,
      { title = "Updater Debug" }
    )
  end

  -- Trigger immediate check for lualine updates
  local Operations = require("updater.operations")
  Operations.check_updates_silent()

  -- Refresh if window is open
  if Status.state.is_open then
    Operations.refresh(Utils.create_render_callback())
  end
end

function M.simulate_updates(dotfile_updates, plugin_updates)
  local config = Config.get()
  if not config then
    Errors.notify_error("Debug module not initialized", "Debug module")
    return
  end

  -- Enable debug mode if not already enabled
  if not Status.state.debug_enabled then
    Status.state.debug_enabled = true
  end

  Status.state.debug_simulate_dotfiles = dotfile_updates
  Status.state.debug_simulate_plugins = plugin_updates

  vim.notify(
    string.format(
      "Updater debug mode: simulating %d dotfile update(s), %d plugin update(s)",
      dotfile_updates,
      plugin_updates
    ),
    vim.log.levels.INFO,
    { title = "Updater Debug" }
  )

  -- Trigger immediate check for lualine updates
  local Operations = require("updater.operations")
  Operations.check_updates_silent()

  -- Refresh if window is open
  if Status.state.is_open then
    Operations.refresh(Utils.create_render_callback())
  end
end

function M.disable_debug_mode()
  local config = Config.get()
  if not config then
    Errors.notify_error("Debug module not initialized", "Debug module")
    return
  end

  Status.state.debug_enabled = false
  vim.notify("Updater debug mode disabled", vim.log.levels.INFO, { title = "Updater Debug" })

  -- Trigger immediate check for lualine updates
  local Operations = require("updater.operations")
  Operations.check_updates_silent()

  -- Refresh if window is open
  if Status.state.is_open then
    Operations.refresh(Utils.create_render_callback())
  end
end

function M.simulate_check_updates_silent()
  -- This function handles the debug simulation logic from operations.lua
  if not Status.state.debug_enabled then
    return false
  end

  Status.state.current_branch = "debug-branch"
  Status.state.ahead_count = 0
  Status.state.behind_count = Status.state.debug_simulate_dotfiles
  Status.state.last_check_time = os.time()
  Status.state.needs_update = Status.state.debug_simulate_dotfiles > 0

  Status.state.plugin_updates = {}
  for i = 1, Status.state.debug_simulate_plugins do
    table.insert(Status.state.plugin_updates, {
      name = "test-plugin-" .. i,
      installed_commit = "abc123" .. i,
      lockfile_commit = "def456" .. i,
      branch = "main",
    })
  end
  Status.state.has_plugin_updates = #Status.state.plugin_updates > 0

  return Status.state.needs_update or Status.state.has_plugin_updates
end

function M.simulate_refresh_data()
  -- This function provides comprehensive debug simulation for the TUI
  local dotfiles_count = Status.state.debug_simulate_dotfiles
  local plugins_count = Status.state.debug_simulate_plugins

  -- Simulate basic git status
  Status.state.current_branch = "debug-branch"
  Status.state.current_commit = "abc1234"
  Status.state.ahead_count = 0
  Status.state.behind_count = dotfiles_count
  Status.state.needs_update = dotfiles_count > 0
  Status.state.last_check_time = os.time()

  -- Simulate remote commits if there are dotfile updates
  Status.state.remote_commits = {}
  if dotfiles_count > 0 then
    for i = 1, math.min(dotfiles_count, 5) do -- Limit to 5 fake commits for readability
      table.insert(Status.state.remote_commits, {
        hash = string.format("def%04d", 1000 + i),
        message = string.format("Debug commit %d: Sample change %d", i, i),
        author = "Debug User",
        date = "2024-01-" .. string.format("%02d", i),
        is_merge = false,
      })
    end
    Status.state.commits_in_branch = Status.state.remote_commits
    Status.state.log_type = "remote"
  else
    Status.state.commits_in_branch = {}
    Status.state.log_type = "local"
  end

  -- Simulate commit log (mix of local and remote commits)
  Status.state.commits = {}
  -- Add some local commits first
  for i = 1, 3 do
    table.insert(Status.state.commits, {
      hash = string.format("loc%04d", 2000 + i),
      message = string.format("Local commit %d: Development work", i),
      author = "Local Dev",
      date = "2024-01-" .. string.format("%02d", 10 + i),
      is_merge = false,
    })
  end
  -- Add the remote commits
  for _, commit in ipairs(Status.state.remote_commits) do
    table.insert(Status.state.commits, commit)
  end

  -- Simulate plugin updates
  Status.state.plugin_updates = {}
  for i = 1, plugins_count do
    table.insert(Status.state.plugin_updates, {
      name = "debug-plugin-" .. i,
      installed_commit = string.format("old%04d", 3000 + i),
      lockfile_commit = string.format("new%04d", 4000 + i),
      branch = "main",
    })
  end
  Status.state.has_plugin_updates = plugins_count > 0
end

local commands_registered = false

function M.register_commands()
  if commands_registered then
    return
  end

  vim.api.nvim_create_user_command("UpdaterDebugSimulate", function(cmd_opts)
    local args = vim.split(cmd_opts.args, "%s+")
    local dotfiles = tonumber(args[1])
    local plugins = tonumber(args[2])

    if not dotfiles or not plugins then
      vim.notify("Usage: UpdaterDebugSimulate <dotfiles> <plugins>", vim.log.levels.ERROR, { title = "Updater Debug" })
      return
    end

    M.simulate_updates(dotfiles, plugins)
  end, {
    nargs = "+",
    desc = "Enable debug mode and simulate updates (args: dotfile_count plugin_count)",
  })

  vim.api.nvim_create_user_command("UpdaterDebugDisable", M.disable_debug_mode, { desc = "Disable debug mode" })

  commands_registered = true
end

function M.is_loaded()
  return Config.get() ~= nil
end

function M.get_status()
  local config = Config.get()
  if not config then
    return "not loaded"
  end

  if Status.state.debug_enabled then
    local sim_dotfiles = Status.state.debug_simulate_dotfiles
    local sim_plugins = Status.state.debug_simulate_plugins

    if sim_dotfiles > 0 or sim_plugins > 0 then
      return string.format("enabled (simulating %dd %dp)", sim_dotfiles, sim_plugins)
    else
      return "enabled"
    end
  else
    return "loaded but disabled"
  end
end

return M
