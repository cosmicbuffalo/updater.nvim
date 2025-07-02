local Status = require("updater.status")
local Spinner = require("updater.spinner")
local M = {}

local function read_lockfile(lockfile_path)
	if not lockfile_path or lockfile_path == "" then
		return {}
	end
	
	local file = io.open(lockfile_path, "r")
	if not file then
		-- Lockfile doesn't exist, which is normal for fresh installs
		return {}
	end
	
	local content = file:read("*a")
	file:close()
	
	if not content or content == "" then
		return {}
	end
	
	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		-- Log error but don't crash - malformed lockfile
		vim.notify("Warning: Could not parse lazy-lock.json: " .. (data or "invalid JSON"), vim.log.levels.WARN)
		return {}
	end
	
	if type(data) ~= "table" then
		vim.notify("Warning: lazy-lock.json does not contain expected format", vim.log.levels.WARN)
		return {}
	end
	
	return data
end

function M.is_lazy_available()
	local ok, _ = pcall(require, "lazy.core.config")
	return ok
end

function M.get_installed_plugin_commit(plugin_name)
	if not M.is_lazy_available() then
		return nil
	end

	local ok, lazy_config = pcall(require, "lazy.core.config")
	if not ok then
		return nil
	end

	local plugin = lazy_config.plugins[plugin_name]
	if not plugin or not plugin._.installed then
		return nil
	end

	local git_ok, Git = pcall(require, "lazy.manage.git")
	if not git_ok then
		return nil
	end

	local info = Git.info(plugin.dir)
	if info then
		return info.commit
	end

	return nil
end

function M.get_plugin_updates(config)
	local plugin_updates = {}

	if not config then
		vim.notify("Config is required for checking plugin updates", vim.log.levels.WARN, { title = "Plugin Updates" })
		return plugin_updates
	end

	if not config.repo_path or config.repo_path == "" then
		vim.notify("Invalid repository path for plugin updates", vim.log.levels.WARN, { title = "Plugin Updates" })
		return plugin_updates
	end

	if not M.is_lazy_available() then
		return plugin_updates
	end

	local lockfile_path = config.repo_path .. "/lazy-lock.json"
	local lockfile_data = read_lockfile(lockfile_path)
	
	if not lockfile_data or type(lockfile_data) ~= "table" then
		-- read_lockfile already handles errors, just return empty updates
		return plugin_updates
	end

	for plugin_name, lock_info in pairs(lockfile_data) do
		if type(plugin_name) == "string" and type(lock_info) == "table" then
			local installed_commit = M.get_installed_plugin_commit(plugin_name)

			if installed_commit and lock_info.commit and type(lock_info.commit) == "string" then
				if installed_commit ~= lock_info.commit then
					table.insert(plugin_updates, {
						name = plugin_name,
						installed_commit = installed_commit:sub(1, 7),
						lockfile_commit = lock_info.commit:sub(1, 7),
						branch = lock_info.branch or "main",
					})
				end
			end
		end
	end

	return plugin_updates
end

function M.install_plugin_updates(config, render_callback)
	if not config then
		vim.notify("Config is required for plugin updates", vim.log.levels.ERROR, { title = "Plugin Updates" })
		return
	end
	
	if not config.repo_path or config.repo_path == "" then
		vim.notify("Invalid repository path for plugin updates", vim.log.levels.ERROR, { title = "Plugin Updates" })
		return
	end

	if not M.is_lazy_available() then
		vim.notify(
			"Cannot install plugin updates: lazy.nvim not found",
			vim.log.levels.ERROR,
			{ title = "Plugin Updates" }
		)
		return
	end

	Status.set_installing_plugins(true)
	Spinner.start_loading_spinner(render_callback)
	if render_callback then render_callback("normal") end

	local cmd = "cd "
		.. vim.fn.shellescape(config.repo_path)
		.. " && nvim --headless +'lua require(\"lazy\").restore({wait=true})' +qa"
	local handle = io.popen(cmd)
	if not handle then
		Status.set_installing_plugins(false)
		Spinner.stop_loading_spinner()
		vim.notify("Failed to execute plugin restore command", vim.log.levels.ERROR, { title = "Plugin Updates" })
		return
	end
	
	local result = handle:read("*a")
	local success = handle:close()

	Status.set_installing_plugins(false)
	Spinner.stop_loading_spinner()

	if not result or result:match("error") or result:match("Error") then
		vim.notify(
			"Failed to install plugin updates: " .. (result or "Unknown error"),
			vim.log.levels.ERROR,
			{ title = "Plugin Updates" }
		)
	else
		vim.notify("Successfully restored plugins from lockfile!", vim.log.levels.INFO, { title = "Plugin Updates" })
		Status.state.plugin_updates = M.get_plugin_updates(config)
		Status.state.has_plugin_updates = #Status.state.plugin_updates > 0
		Status.set_recently_updated_plugins(true)
	end

	if render_callback then render_callback("normal") end
end

return M