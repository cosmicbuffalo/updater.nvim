local M = {}

-- Private state object
local state = {
	-- Window/UI state
	is_open = false,
	buffer = nil,
	window = nil,
	is_initial_load = false,

	-- Operation states
	is_updating = false,
	is_refreshing = false,
	is_installing_plugins = false,

	-- Git status
	current_branch = "unknown",
	current_commit = nil,
	ahead_count = 0,
	behind_count = 0,
	needs_update = false,
	last_check_time = nil,

	-- Commit data
	commits = {},
	remote_commits = {},
	commits_in_branch = {},
	log_type = "local",

	-- Plugin data
	plugin_updates = {},
	has_plugin_updates = false,

	-- Restart reminder state
	recently_updated_dotfiles = false,
	recently_updated_plugins = false,

	-- Spinner state
	loading_spinner_timer = nil,
	loading_spinner_frame = 1,

	-- Periodic check state
	periodic_timer = nil,
}

-- State getters
function M.get_state()
	-- Return a read-only copy to prevent direct mutations
	return vim.tbl_deep_extend("force", {}, state)
end

function M.get_state_value(key)
	return state[key]
end

-- Window state management
function M.set_window_state(is_open, buffer, window)
	state.is_open = is_open or false
	state.buffer = buffer
	state.window = window
end

function M.set_initial_load(value)
	state.is_initial_load = value or false
end

function M.reset_initial_load()
	state.is_initial_load = false
end

-- Operation state management
function M.set_updating(value)
	state.is_updating = value or false
end

function M.set_refreshing(value)
	state.is_refreshing = value or false
end

function M.set_installing_plugins(value)
	state.is_installing_plugins = value or false
end

-- Git state management
function M.set_git_status(branch, commit, ahead, behind, needs_update, last_check)
	state.current_branch = branch or "unknown"
	state.current_commit = commit
	state.ahead_count = ahead or 0
	state.behind_count = behind or 0
	state.needs_update = needs_update or false
	if last_check then
		state.last_check_time = last_check
	end
end

function M.set_branch(branch)
	state.current_branch = branch or "unknown"
end

function M.set_commit(commit)
	state.current_commit = commit
end

function M.set_ahead_behind(ahead, behind)
	state.ahead_count = ahead or 0
	state.behind_count = behind or 0
end

function M.set_needs_update(value)
	state.needs_update = value or false
end

function M.set_last_check_time(time)
	state.last_check_time = time or os.time()
end

-- Commit data management
function M.set_commits(commits, log_type)
	state.commits = commits or {}
	state.log_type = log_type or "local"
end

function M.set_remote_commits(commits)
	state.remote_commits = commits or {}
end

function M.set_commits_in_branch(commits)
	state.commits_in_branch = commits or {}
end

-- Plugin state management
function M.set_plugin_updates(updates)
	state.plugin_updates = updates or {}
	state.has_plugin_updates = #state.plugin_updates > 0
end

function M.add_plugin_update(plugin_update)
	table.insert(state.plugin_updates, plugin_update)
	state.has_plugin_updates = true
end

function M.clear_plugin_updates()
	state.plugin_updates = {}
	state.has_plugin_updates = false
end

-- Restart reminder state
function M.set_recently_updated_dotfiles(value)
	state.recently_updated_dotfiles = value or false
end

function M.set_recently_updated_plugins(value)
	state.recently_updated_plugins = value or false
end

-- Spinner state management
function M.set_spinner_timer(timer)
	state.loading_spinner_timer = timer
end

function M.set_spinner_frame(frame)
	state.loading_spinner_frame = frame or 1
end

function M.update_spinner_frame()
	local Constants = require("updater.constants")
	state.loading_spinner_frame = (state.loading_spinner_frame % #Constants.SPINNER_FRAMES) + 1
end

-- Periodic timer management
function M.set_periodic_timer(timer)
	state.periodic_timer = timer
end

function M.get_periodic_timer()
	return state.periodic_timer
end

function M.stop_periodic_timer()
	if state.periodic_timer then
		state.periodic_timer:stop()
		state.periodic_timer:close()
		state.periodic_timer = nil
	end
end

-- Utility functions
function M.has_cached_data()
	return state.last_check_time ~= nil
end

function M.has_updates()
	return state.needs_update or state.has_plugin_updates
end

-- High-level API functions for external use
function M.clear_recent_updates()
	M.set_recently_updated_dotfiles(false)
	M.set_recently_updated_plugins(false)
end

function M.has_recent_updates()
	return state.recently_updated_dotfiles or state.recently_updated_plugins
end

-- Status API for external consumers
function M.get()
	return {
		needs_update = state.needs_update,
		behind_count = state.behind_count,
		ahead_count = state.ahead_count,
		has_plugin_updates = state.has_plugin_updates,
		plugin_update_count = #state.plugin_updates,
		current_branch = state.current_branch,
		last_check_time = state.last_check_time,
		is_updating = state.is_updating,
		is_installing_plugins = state.is_installing_plugins,
		is_refreshing = state.is_refreshing,
	}
end

function M.get_update_count()
	local count = 0
	if state.needs_update then
		count = count + state.behind_count
	end
	if state.has_plugin_updates then
		count = count + #state.plugin_updates
	end
	return count
end

function M.get_update_text(format)
	format = format or "default"

	if not M.has_updates() then
		return ""
	end

	local parts = {}

	if state.needs_update then
		if format == "short" then
			table.insert(parts, state.behind_count .. "d") -- d for dotfiles
		elseif format == "icon" then
			table.insert(parts, "󰚰 " .. state.behind_count)
		else
			table.insert(parts, state.behind_count .. " dotfile" .. (state.behind_count == 1 and "" or "s"))
		end
	end

	if state.has_plugin_updates then
		local plugin_count = #state.plugin_updates
		if format == "short" then
			table.insert(parts, plugin_count .. "p") -- p for plugins
		elseif format == "icon" then
			table.insert(parts, "󰏖 " .. plugin_count)
		else
			table.insert(parts, plugin_count .. " plugin" .. (plugin_count == 1 and "" or "s"))
		end
	end

	if format == "short" or format == "icon" then
		return table.concat(parts, " ")
	else
		return table.concat(parts, ", ") .. " update" .. (M.get_update_count() == 1 and "" or "s")
	end
end

-- Backward compatibility - expose state object for direct access
-- TODO: Remove this and migrate all direct access to use setter functions
M.state = state

-- State reset/cleanup
function M.reset_all()
	-- Reset to initial state but preserve certain values
	local preserved_config = {
		buffer = state.buffer,
		window = state.window,
		is_open = state.is_open,
	}

	state = {
		-- Window/UI state
		is_open = preserved_config.is_open,
		buffer = preserved_config.buffer,
		window = preserved_config.window,
		is_initial_load = false,

		-- Operation states
		is_updating = false,
		is_refreshing = false,
		is_installing_plugins = false,

		-- Git status
		current_branch = "unknown",
		current_commit = nil,
		ahead_count = 0,
		behind_count = 0,
		needs_update = false,
		last_check_time = nil,

		-- Commit data
		commits = {},
		remote_commits = {},
		commits_in_branch = {},
		log_type = "local",

		-- Plugin data
		plugin_updates = {},
		has_plugin_updates = false,

		-- Restart reminder state
		recently_updated_dotfiles = false,
		recently_updated_plugins = false,

		-- Spinner state
		loading_spinner_timer = nil,
		loading_spinner_frame = 1,

		-- Periodic check state
		periodic_timer = nil,
	}
end

return M

