local Git = require("updater.git")
local Status = require("updater.status")
local Plugins = require("updater.plugins")
local Progress = require("updater.progress")
local Spinner = require("updater.spinner")
local Cache = require("updater.cache")
local M = {}

-- Centralized debug loading
local debug_module = nil
local function get_debug_module()
  if not debug_module then
    debug_module = require("updater.debug")
  end
  return debug_module
end

-- Check if debug mode should override operation
local function should_use_debug_mode(config)
  return Status.state.debug_enabled
    and (Status.state.debug_simulate_dotfiles > 0 or Status.state.debug_simulate_plugins > 0)
end

-- Unified error handling function
local function handle_error(operation_name, error_msg)
  local full_msg = string.format("[updater.nvim] Error in %s: %s", operation_name, tostring(error_msg))
  vim.notify(full_msg, vim.log.levels.ERROR)
  vim.api.nvim_err_writeln(full_msg)
end

-- Unified callback handling
local function safe_callback(render_callback, mode)
  if Status.state.is_open and render_callback then
    render_callback(mode or "normal")
  end
end

-- Common git update logic
local function update_git_repo(config, operation_name)
  local branch = Git.get_current_branch(config, config.repo_path)
  local success, message = Git.update_repo(config, config.repo_path, branch)

  if success then
    Status.state.needs_update = false
    Status.state.recently_updated_dotfiles = true
  else
    handle_error(operation_name, message or "Git update failed")
  end

  return success
end

-- Simple operation runner with common setup/cleanup and progress
local function run_operation(options, render_callback)
  -- Set operation status
  if options.status_field then
    Status.state[options.status_field] = true
  end

  Spinner.start_loading_spinner(render_callback)
  safe_callback(render_callback)

  -- Setup progress notification if config provided
  local progress_handler = nil
  if options.progress then
    progress_handler = Progress.handle_refresh_progress(options.progress.title, options.progress.message)
  end

  -- Handle delayed execution (for refresh operation)
  local execute_operation = function()
    local success, error_msg = pcall(options.operation)

    -- Always cleanup, regardless of success
    if options.status_field then
      Status.state[options.status_field] = false
    end
    Spinner.stop_loading_spinner()

    if not success then
      handle_error(options.name, error_msg)
      if progress_handler then
        progress_handler.finish(false)
      end
    else
      -- Finish progress with success state if provided
      if progress_handler and options.progress and options.progress.success_check then
        progress_handler.finish(options.progress.success_check())
      elseif progress_handler then
        progress_handler.finish(true)
      end
    end

    safe_callback(render_callback)
    return success
  end

  -- Execute immediately or with delay
  if options.delay_ms then
    vim.defer_fn(execute_operation, options.delay_ms)
  else
    return execute_operation()
  end
end

local function refresh_data(config)
  local success, error_msg = pcall(function()
    if should_use_debug_mode(config) then
      get_debug_module().simulate_refresh_data()
      return
    end

    Status.state.current_commit = Git.get_current_commit(config, config.repo_path)
    local status = Git.get_repo_status(config, config.repo_path)

    if not status.error then
      Status.state.current_branch = status.branch
      Status.state.ahead_count = status.ahead
      Status.state.behind_count = status.behind
      Status.state.remote_commits = Git.get_remote_commits_not_in_local(config, config.repo_path, status.branch)
      Status.state.commits_in_branch =
        Git.are_commits_in_branch(Status.state.remote_commits, Status.state.current_branch, config, config.repo_path)
      Status.state.needs_update = #Status.state.remote_commits > 0
    else
      Status.state.needs_update = false
    end

    Status.state.commits, Status.state.log_type = Git.get_commit_log(
      config,
      config.repo_path,
      Status.state.current_branch,
      Status.state.ahead_count,
      Status.state.behind_count
    )
    Status.state.plugin_updates = Plugins.get_plugin_updates(config)
    Status.state.has_plugin_updates = #Status.state.plugin_updates > 0
    Status.state.last_check_time = os.time()

    -- Persist to cache for cross-instance sharing
    Cache.update_after_check(config.repo_path, {
      current_commit = Status.state.current_commit,
      branch = Status.state.current_branch,
      behind_count = Status.state.behind_count,
      ahead_count = Status.state.ahead_count,
      needs_update = Status.state.needs_update,
      has_plugin_updates = Status.state.has_plugin_updates,
    })
  end)

  if not success then
    handle_error("refresh_data", error_msg)
    -- Set safe defaults on error
    Status.state.needs_update = false
    Status.state.has_plugin_updates = false
    Status.state.last_check_time = os.time()
  end
end

function M.refresh(config, render_callback)
  run_operation({
    name = "refresh",
    status_field = "is_refreshing",
    delay_ms = 1200,
    progress = {
      title = "Updater",
      message = "Checking for updates...",
      success_check = function()
        return Status.state.needs_update or Status.state.has_plugin_updates
      end,
    },
    operation = function()
      refresh_data(config)
      -- Reset initial load flag after refresh
      Status.state.is_initial_load = false
    end,
  }, render_callback)
end

function M.update_repo(config, render_callback)
  run_operation({
    name = "update_repo",
    status_field = "is_updating",
    progress = {
      title = "Updater",
      message = "Pulling latest changes...",
      success_check = function()
        return not Status.state.needs_update
      end,
    },
    operation = function()
      update_git_repo(config, "update_repo")
      refresh_data(config)
    end,
  }, render_callback)
end

function M.update_dotfiles_and_plugins(config, render_callback)
  run_operation({
    name = "update_dotfiles_and_plugins",
    status_field = "is_updating",
    progress = {
      title = "Updater",
      message = "Updating dotfiles and plugins...",
      success_check = function()
        return not Status.state.needs_update and not Status.state.has_plugin_updates
      end,
    },
    operation = function()
      update_git_repo(config, "update_dotfiles_and_plugins")
      refresh_data(config)

      if not Status.state.is_updating then
        Plugins.install_plugin_updates(config, render_callback)
      end
    end,
  }, render_callback)
end

function M.check_updates_silent(config)
  local success, result = pcall(function()
    if Status.state.debug_enabled then
      return get_debug_module().simulate_check_updates_silent()
    end

    refresh_data(config)
    return Status.state.needs_update or Status.state.has_plugin_updates
  end)

  if not success then
    handle_error("check_updates_silent", result)
    return false
  end

  return result
end

return M
