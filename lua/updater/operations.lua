local Git = require("updater.git")
local Status = require("updater.status")
local Plugins = require("updater.plugins")
local Progress = require("updater.progress")
local Spinner = require("updater.spinner")
local Constants = require("updater.constants")
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
	return config.debug.enabled
		and (config.debug.simulate_updates.dotfiles > 0 or config.debug.simulate_updates.plugins > 0)
end

function M.refresh_data(config)
	if should_use_debug_mode(config) then
		get_debug_module().simulate_refresh_data(config)
		return
	end
	Status.state.current_commit = Git.get_current_commit(config, config.repo_path)
	local status = Git.get_repo_status(config, config.repo_path)

	if not status.error then
		Status.state.current_branch = status.branch
		Status.state.ahead_count = status.ahead
		Status.state.behind_count = status.behind
		Status.state.remote_commits = Git.get_remote_commits_not_in_local(config, config.repo_path, status.branch)
		Status.state.commits_in_branch = Git.are_commits_in_branch(
			Status.state.remote_commits,
			Status.state.current_branch,
			config,
			config.repo_path
		)
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
end

function M.refresh(config, render_callback)
	Status.set_refreshing(true)
	Spinner.start_loading_spinner(render_callback)

	local progress_handler = Progress.handle_refresh_progress("Checking for updates...", "Fetching remote changes...")

	if Status.state.is_open and render_callback then
		render_callback("normal")
	end

	local delay = config.refresh.delay_ms

	vim.defer_fn(function()
		M.refresh_data(config)

		Status.set_refreshing(false)
		Status.reset_initial_load()
		Spinner.stop_loading_spinner()

		progress_handler.finish(Status.state.needs_update or Status.state.has_plugin_updates)

		if Status.state.is_open and render_callback then
			render_callback("normal")
		end
	end, delay)
end

function M.update_repo(config, render_callback)
	Status.set_updating(true)
	Spinner.start_loading_spinner(render_callback)
	if render_callback then
		render_callback("normal")
	end

	local branch = Git.get_current_branch(config, config.repo_path)
	local success, message = Git.update_repo(config, config.repo_path, branch)

	Status.set_updating(false)
	Spinner.stop_loading_spinner()

	if success then
		Status.state.needs_update = false
		Status.set_recently_updated_dotfiles(true)
	end

	M.refresh(config, render_callback)
end

function M.update_dotfiles_and_plugins(config, render_callback)
	Status.set_updating(true)
	if render_callback then
		render_callback("normal")
	end

	M.update_repo(config, render_callback)

	if not Status.state.is_updating then
		Plugins.install_plugin_updates(config, render_callback)
	end
end

function M.check_updates_silent(config)
	if config.debug.enabled then
		return get_debug_module().simulate_check_updates_silent(config)
	end

	M.refresh_data(config)
	return Status.state.needs_update or Status.state.has_plugin_updates
end

return M

