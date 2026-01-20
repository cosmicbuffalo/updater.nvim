local Git = require("updater.git")
local Status = require("updater.status")
local Plugins = require("updater.plugins")
local Progress = require("updater.progress")
local Spinner = require("updater.spinner")
local Cache = require("updater.cache")
local M = {}

local debug_module = nil
local function get_debug_module()
  if not debug_module then
    debug_module = require("updater.debug")
  end
  return debug_module
end

local function should_use_debug_mode()
  return Status.state.debug_enabled
    and (Status.state.debug_simulate_dotfiles > 0 or Status.state.debug_simulate_plugins > 0)
end

local function handle_error(operation_name, error_msg)
  local full_msg = string.format("[updater.nvim] Error in %s: %s", operation_name, tostring(error_msg))
  vim.notify(full_msg, vim.log.levels.ERROR)
  vim.api.nvim_err_writeln(full_msg)
end

local function safe_callback(render_callback, mode)
  if Status.state.is_open and render_callback then
    render_callback(mode or "normal")
  end
end

local function refresh_step_6_get_plugin_updates(config, callback)
  Plugins.get_plugin_updates(config, function(result)
    Status.state.plugin_updates = result.all_updates
    Status.state.plugins_behind = result.plugins_behind
    Status.state.plugins_ahead = result.plugins_ahead
    Status.state.has_plugin_updates = #result.all_updates > 0
    Status.state.has_plugins_behind = #result.plugins_behind > 0
    Status.state.has_plugins_ahead = #result.plugins_ahead > 0
    Status.state.last_check_time = os.time()

    -- Step 7: Update cache
    Cache.update_after_check(config.repo_path, Status.state, function()
      if callback then
        callback()
      end
    end)
  end)
end

local function refresh_step_5_get_commit_log(config, callback)
  Git.get_commit_log(
    config,
    config.repo_path,
    Status.state.current_branch,
    Status.state.ahead_count,
    Status.state.behind_count,
    function(commits, log_type, _)
      Status.state.commits = commits
      Status.state.log_type = log_type

      refresh_step_6_get_plugin_updates(config, callback)
    end
  )
end

local function refresh_step_4_are_commits_in_branch(config, callback)
  Git.are_commits_in_branch(
    Status.state.remote_commits,
    Status.state.current_branch,
    config,
    config.repo_path,
    function(commits_in_branch)
      Status.state.commits_in_branch = commits_in_branch

      refresh_step_5_get_commit_log(config, callback)
    end
  )
end

local function refresh_step_3_get_remote_commits(config, callback)
  Git.get_remote_commits_not_in_local(config, config.repo_path, Status.state.current_branch, function(remote_commits, _)
    Status.state.remote_commits = remote_commits
    Status.state.needs_update = #remote_commits > 0

    refresh_step_4_are_commits_in_branch(config, callback)
  end)
end

local function refresh_step_2_repo_status(config, callback)
  Git.get_repo_status(config, config.repo_path, function(status)
    if status.error then
      Status.state.needs_update = false
      Status.state.has_plugin_updates = false
      Status.state.has_plugins_behind = false
      Status.state.has_plugins_ahead = false
      Status.state.last_check_time = os.time()
      if callback then
        callback()
      end
      return
    end

    Status.state.current_branch = status.branch
    Status.state.ahead_count = status.ahead
    Status.state.behind_count = status.behind

    refresh_step_3_get_remote_commits(config, callback)
  end)
end

local function start_refresh_logic(config, callback)
  -- Step 1: Get current commit
  Git.get_current_commit(config, config.repo_path, function(commit, _)
    Status.state.current_commit = commit

    refresh_step_2_repo_status(config, callback)
  end)
end

local function refresh_data(config, callback)
  if should_use_debug_mode() then
    get_debug_module().simulate_refresh_data()
    if callback then
      callback()
    end
    return
  end

  start_refresh_logic(config, callback)
end

local function update_git_repo(config, operation_name, callback)
  Git.update_repo(config, config.repo_path, function(success, message)
    if success then
      Status.state.needs_update = false
      Status.state.recently_updated_dotfiles = true
    else
      handle_error(operation_name, message or "Git update failed")
    end

    if callback then
      callback(success)
    end
  end)
end

local function run_operation(options, render_callback)
  local start_time = vim.uv.now()

  if options.status_field then
    Status.state[options.status_field] = true
  end

  Spinner.start_loading_spinner(render_callback)
  safe_callback(render_callback)

  local progress_handler = nil
  if options.progress then
    progress_handler = Progress.handle_refresh_progress(options.progress.title, options.progress.message)
  end

  local cleanup = function(success)
    if options.status_field then
      Status.state[options.status_field] = false
    end
    Spinner.stop_loading_spinner()

    if not success then
      if progress_handler then
        progress_handler.finish(false)
      end
    else
      if progress_handler and options.progress and options.progress.success_check then
        progress_handler.finish(options.progress.success_check())
      elseif progress_handler then
        progress_handler.finish(true)
      end
    end

    safe_callback(render_callback)
  end

  local execute = function()
    options.operation(function(success, error_msg)
      if error_msg then
        handle_error(options.name, error_msg)
      end

      if options.min_display_time_ms then
        local elapsed = vim.uv.now() - start_time
        local remaining = options.min_display_time_ms - elapsed
        if remaining > 0 then
          vim.defer_fn(function()
            cleanup(success ~= false)
          end, remaining)
          return
        end
      end

      cleanup(success ~= false)
    end)
  end

  if options.delay_ms then
    vim.defer_fn(execute, options.delay_ms)
  else
    execute()
  end
end

function M.refresh(config, render_callback)
  run_operation({
    name = "refresh",
    status_field = "is_refreshing",
    delay_ms = 100, -- Small delay to let UI render first
    min_display_time_ms = 2000, -- Ensure loading state is visible long enough to read
    progress = {
      title = "Updater",
      message = "Checking for updates...",
      success_check = function()
        return Status.state.needs_update or Status.state.has_plugin_updates
      end,
    },
    operation = function(done)
      refresh_data(config, function()
        Status.state.is_initial_load = false
        done(true)
      end)
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
    operation = function(done)
      update_git_repo(config, "update_repo", function(success)
        if success then
          refresh_data(config, function()
            done(true)
          end)
        else
          done(false)
        end
      end)
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
    operation = function(done)
      update_git_repo(config, "update_dotfiles_and_plugins", function(success)
        if success then
          refresh_data(config, function()
            Plugins.install_plugin_updates(config, render_callback)
            done(true)
          end)
        else
          done(false)
        end
      end)
    end,
  }, render_callback)
end

function M.check_updates_silent(config, callback)
  if Status.state.debug_enabled then
    local result = get_debug_module().simulate_check_updates_silent()
    if callback then
      callback(result)
    end
    return
  end

  Git.get_repo_status(config, config.repo_path, function(status)
    if status.error then
      Status.state.needs_update = false
      Status.state.has_plugin_updates = false
      Status.state.has_plugins_behind = false
      Status.state.has_plugins_ahead = false
      if callback then
        callback(false)
      end
      return
    end

    Status.state.current_branch = status.branch
    Status.state.ahead_count = status.ahead
    Status.state.behind_count = status.behind
    Status.state.needs_update = status.behind > 0

    Plugins.get_plugin_updates(config, function(result)
      Status.state.plugin_updates = result.all_updates
      Status.state.plugins_behind = result.plugins_behind
      Status.state.plugins_ahead = result.plugins_ahead
      Status.state.has_plugin_updates = #result.all_updates > 0
      Status.state.has_plugins_behind = #result.plugins_behind > 0
      Status.state.has_plugins_ahead = #result.plugins_ahead > 0
      Status.state.last_check_time = os.time()

      Cache.update_after_check(config.repo_path, Status.state, function()
        if callback then
          callback(Status.state.needs_update or Status.state.has_plugin_updates)
        end
      end)
    end)
  end)
end

return M
