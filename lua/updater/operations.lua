local Git = require("updater.git")
local Status = require("updater.status")
local Plugins = require("updater.plugins")
local Progress = require("updater.progress")
local Spinner = require("updater.spinner")
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
		Status.set_recently_updated_dotfiles(true)
	else
		handle_error(operation_name, message or "Git update failed")
	end
	
	return success
end

-- Operation wrapper with common setup/cleanup and progress
local function with_operation(operation_name, status_setter, cleanup_fn, progress_config)
	return function(config, render_callback, operation_fn)
		status_setter(true)
		Spinner.start_loading_spinner(render_callback)
		safe_callback(render_callback)

		-- Setup progress notification if config provided
		local progress_handler = nil
		if progress_config then
			progress_handler = Progress.handle_refresh_progress(progress_config.title, progress_config.initial_message)
		end

		local success, error_msg = pcall(operation_fn)

		-- Always cleanup, regardless of success
		cleanup_fn()
		Spinner.stop_loading_spinner()

		if not success then
			handle_error(operation_name, error_msg)
			if progress_handler then
				progress_handler.finish(false) -- Show failure state
			end
		else
			-- Finish progress with success state if provided
			if progress_handler and progress_config.success_check then
				progress_handler.finish(progress_config.success_check())
			elseif progress_handler then
				progress_handler.finish(true) -- Default to success
			end
		end

		safe_callback(render_callback)
		return success
	end
end

local function refresh_data(config)
	local success, error_msg = pcall(function()
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
	Status.set_refreshing(true)
	Spinner.start_loading_spinner(render_callback)

	local progress_handler = Progress.handle_refresh_progress("Updater", "Checking for updates...")
	safe_callback(render_callback)

	local delay = config.refresh.delay_ms

	vim.defer_fn(function()
		local success, error_msg = pcall(function()
			refresh_data(config)
		end)

		-- Always cleanup, regardless of success
		Status.set_refreshing(false)
		Status.reset_initial_load()
		Spinner.stop_loading_spinner()

		if not success then
			handle_error("refresh", error_msg)
			progress_handler.finish(false)
		else
			progress_handler.finish(Status.state.needs_update or Status.state.has_plugin_updates)
		end

		safe_callback(render_callback)
	end, delay)
end

function M.update_repo(config, render_callback)
	with_operation(
		"update_repo", 
		Status.set_updating, 
		function() Status.set_updating(false) end,
		{
			title = "Updating Dotfiles",
			initial_message = "Pulling latest changes...",
			success_check = function() 
				return not Status.state.needs_update 
			end
		}
	)(
		config, 
		render_callback, 
		function()
			update_git_repo(config, "update_repo")
			refresh_data(config)
		end
	)
end

function M.update_dotfiles_and_plugins(config, render_callback)
	with_operation(
		"update_dotfiles_and_plugins", 
		Status.set_updating, 
		function() Status.set_updating(false) end,
		{
			title = "Updating All",
			initial_message = "Updating dotfiles and plugins...",
			success_check = function() 
				return not Status.state.needs_update and not Status.state.has_plugin_updates
			end
		}
	)(
		config,
		render_callback,
		function()
			update_git_repo(config, "update_dotfiles_and_plugins")
			refresh_data(config)
			
			if not Status.state.is_updating then
				Plugins.install_plugin_updates(config, render_callback)
			end
		end
	)
end

function M.check_updates_silent(config)
	local success, result = pcall(function()
		if config.debug.enabled then
			return get_debug_module().simulate_check_updates_silent(config)
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

