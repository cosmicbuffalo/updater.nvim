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

-- Utility functions for timer management
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
	state.recently_updated_dotfiles = false
	state.recently_updated_plugins = false
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

M.state = state

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

