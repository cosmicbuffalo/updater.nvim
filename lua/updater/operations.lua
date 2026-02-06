local Config = require("updater.config")
local Git = require("updater.git")
local Status = require("updater.status")
local Plugins = require("updater.plugins")
local Progress = require("updater.progress")
local Spinner = require("updater.spinner")
local Cache = require("updater.cache")
local Version = require("updater.version")
local Constants = require("updater.constants")
local GitHub = require("updater.github")
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
  Plugins.get_plugin_updates(function(result)
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
    function(commits_in_branch)
      Status.state.commits_in_branch = commits_in_branch

      refresh_step_5_get_commit_log(config, callback)
    end
  )
end

local function refresh_step_3_get_remote_commits(config, callback)
  Git.get_remote_commits_not_in_local(Status.state.current_branch, function(remote_commits, _)
    Status.state.remote_commits = remote_commits

    -- In versioned_releases_only mode, needs_update is based on new release availability
    -- Otherwise, it's based on remote commits
    if config.versioned_releases_only then
      Status.state.needs_update = Status.state.has_new_release
    else
      Status.state.needs_update = #remote_commits > 0
    end

    refresh_step_4_are_commits_in_branch(config, callback)
  end)
end

local function refresh_step_2_repo_status(config, callback)
  Git.get_repo_status(function(status)
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

-- Fetch GitHub release data (async, non-blocking)
local function fetch_github_releases()
  GitHub.fetch_releases(function(releases, err)
    if err then
      -- Silently ignore errors - GitHub data is optional enhancement
      Status.state.github_releases = {}
    else
      Status.state.github_releases = releases
    end
    Status.state.github_releases_fetched = true
  end)
end

-- Fetch release information for versioned_releases_only mode
local function refresh_release_info(config, callback)
  -- Always fetch GitHub releases in the background (non-blocking)
  fetch_github_releases()

  if not config.versioned_releases_only then
    -- Even when not in versioned_releases_only mode, get current tag for display
    Git.get_head_tag(function(tag, _)
      Status.state.current_tag = tag
      callback()
    end)
    return
  end

  -- Check if we're on a detached HEAD
  Git.is_detached_head(function(is_detached, _)
    Status.state.is_detached_head = is_detached

    -- Get current release (latest tag reachable from HEAD)
    Git.get_latest_release_for_ref("HEAD", function(current_release, _)
      Status.state.current_release = current_release

      -- Also set current_tag if we're exactly on a tag
      Git.get_head_tag(function(head_tag, _)
        Status.state.current_tag = head_tag

        -- Get all version tags for comparison
        Git.get_version_tags(function(all_tags, _)
          -- Latest release is the first tag (sorted newest first)
          local latest_release = all_tags[1]
          Status.state.latest_remote_release = latest_release

          -- Get releases since current release
          Git.get_releases_since_tag(current_release, all_tags, function(releases_since, _)
            Status.state.releases_since_current = releases_since

            -- Determine if new release available based on whether there are releases since current
            Status.state.has_new_release = #releases_since > 0

            -- Get releases before current release (older releases)
            local max_previous = Constants.MAX_SECTION_ITEMS
            Git.get_releases_before_tag(current_release, all_tags, max_previous, function(releases_before, _)
              Status.state.releases_before_current = releases_before

              -- Get commits since release count (only meaningful if not exactly on a tag)
              if head_tag then
                -- We're exactly on a release tag, no commits since
                Status.state.commits_since_release = 0
                Status.state.commits_since_release_list = {}
                -- Still get release commit info for the "Releases since" section display
                Git.get_tag_commit_info(current_release, function(release_commit, _)
                  Status.state.release_commit = release_commit
                  callback()
                end)
              else
                -- We have commits after the release
                Git.get_commits_since_tag(current_release, function(count, _)
                  Status.state.commits_since_release = count

                  -- Get the actual list of commits since release
                  Git.get_commits_since_tag_list(current_release, function(commits, _)
                    Status.state.commits_since_release_list = commits

                    -- Get the release tag commit info
                    Git.get_tag_commit_info(current_release, function(release_commit, _)
                      Status.state.release_commit = release_commit
                      callback()
                    end)
                  end)
                end)
              end
            end)
          end)
        end)
      end)
    end)
  end)
end

local function start_refresh_logic(config, callback)
  -- Step 0: Get remote URL (for constructing GitHub links)
  Git.get_remote_url(function(remote_url, _)
    if remote_url then
      -- Convert SSH URL to HTTPS for browser links
      local https_url = remote_url
      if remote_url:match("^git@") then
        https_url = remote_url:gsub("^git@([^:]+):", "https://%1/"):gsub("%.git$", "")
      else
        https_url = remote_url:gsub("%.git$", "")
      end
      Status.state.remote_url = https_url
    end

    -- Step 1: Get current commit
    Git.get_current_commit(function(commit, _)
      Status.state.current_commit = commit

      -- Step 1.5: Set current tag
      Version.set_current_tag(function()
        -- Step 1.6: Fetch release information
        refresh_release_info(config, function()
          refresh_step_2_repo_status(config, callback)
        end)
      end)
    end)
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

local function update_git_repo(operation_name, callback)
  Git.update_repo(function(success, message)
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

function M.refresh(render_callback)
  local config = Config.get()
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

-- Silent refresh that doesn't show spinner or status messages
-- Used after version switch to reload state without UI interruption
function M.refresh_silent(callback)
  local config = Config.get()
  refresh_data(config, function()
    Status.state.is_initial_load = false
    if callback then
      callback()
    end
  end)
end

function M.update_repo(render_callback)
  local config = Config.get()
  -- Block legacy updates in versioned_releases_only mode
  if config.versioned_releases_only then
    local msg = "Use 'U' to update to latest, 's' to switch versions or :DotfilesVersion to select a release."
    vim.notify(msg, vim.log.levels.INFO, { title = "Updater" })
    return
  end

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
      update_git_repo("update_repo", function(success)
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

function M.update_dotfiles_and_plugins(render_callback)
  local config = Config.get()
  -- Block legacy updates in versioned_releases_only mode
  if config.versioned_releases_only then
    local msg = "Use 'U' to update to latest, 's' to switch versions or :DotfilesVersion to select a release."
    vim.notify(msg, vim.log.levels.INFO, { title = "Updater" })
    return
  end

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
      update_git_repo("update_dotfiles_and_plugins", function(success)
        if success then
          refresh_data(config, function()
            Plugins.install_plugin_updates(render_callback)
            done(true)
          end)
        else
          done(false)
        end
      end)
    end,
  }, render_callback)
end

function M.check_updates_silent(callback)
  local config = Config.get()
  if Status.state.debug_enabled then
    local result = get_debug_module().simulate_check_updates_silent()
    if callback then
      callback(result)
    end
    return
  end

  -- For versioned_releases_only mode, check for new releases
  local function check_release_and_finish(finish_callback)
    if config.versioned_releases_only then
      Git.get_latest_release_for_ref("HEAD", function(current_release, _)
        Status.state.current_release = current_release
        -- Get all version tags to find releases since current
        Git.get_version_tags(function(all_tags, _)
          local latest_release = all_tags[1]
          Status.state.latest_remote_release = latest_release
          -- Check if there are releases newer than current
          Git.get_releases_since_tag(current_release, all_tags, function(releases_since, _)
            Status.state.releases_since_current = releases_since
            Status.state.has_new_release = #releases_since > 0
            Status.state.needs_update = Status.state.has_new_release
            finish_callback()
          end)
        end)
      end)
    else
      finish_callback()
    end
  end

  Git.get_repo_status(function(status)
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

    -- In non-versioned mode, needs_update is based on commits behind
    if not config.versioned_releases_only then
      Status.state.needs_update = status.behind > 0
    end

    Plugins.get_plugin_updates(function(result)
      Status.state.plugin_updates = result.all_updates
      Status.state.plugins_behind = result.plugins_behind
      Status.state.plugins_ahead = result.plugins_ahead
      Status.state.has_plugin_updates = #result.all_updates > 0
      Status.state.has_plugins_behind = #result.plugins_behind > 0
      Status.state.has_plugins_ahead = #result.plugins_ahead > 0
      Status.state.last_check_time = os.time()

      check_release_and_finish(function()
        Cache.update_after_check(config.repo_path, Status.state, function()
          if callback then
            callback(Status.state.needs_update or Status.state.has_plugin_updates)
          end
        end)
      end)
    end)
  end)
end

return M
