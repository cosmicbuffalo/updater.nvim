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

-- Get the directory path for a plugin's local git repository
local function get_plugin_dir(plugin_name)
  local ok, lazy_config = pcall(require, "lazy.core.config")
  if not ok then
    return nil
  end

  local plugin = lazy_config.plugins[plugin_name]
  if not plugin then
    return nil
  end

  return plugin.dir
end

-- Get the unix timestamp for a specific commit in a plugin's local git repo
local function get_commit_timestamp(plugin_dir, commit_hash, callback)
  if not plugin_dir or not commit_hash then
    callback(nil, "Missing plugin_dir or commit_hash")
    return
  end

  local cmd = "cd " .. vim.fn.shellescape(plugin_dir) .. " && git log -1 --format=%ct " .. commit_hash .. " 2>/dev/null"

  vim.system({ "bash", "-c", cmd }, { text = true, timeout = 5000 }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 or not obj.stdout or obj.stdout == "" then
        -- Commit not found or error - return nil
        callback(nil, nil)
      else
        local timestamp = tonumber(vim.trim(obj.stdout))
        callback(timestamp, nil)
      end
    end)
  end)
end

-- Get timestamps for multiple plugins' commits in batch
local function get_commit_timestamps_batch(plugin_list, callback)
  local results = {}
  local total_operations = #plugin_list * 2 -- 2 timestamps per plugin (installed + lockfile)
  local completed = 0

  if total_operations == 0 then
    callback(results)
    return
  end

  for _, plugin in ipairs(plugin_list) do
    results[plugin.name] = { installed_ts = nil, lockfile_ts = nil }

    -- Get installed commit timestamp
    get_commit_timestamp(plugin.dir, plugin.installed_commit_full, function(ts, _)
      results[plugin.name].installed_ts = ts
      completed = completed + 1
      if completed == total_operations then
        callback(results)
      end
    end)

    -- Get lockfile commit timestamp
    get_commit_timestamp(plugin.dir, plugin.lockfile_commit_full, function(ts, _)
      results[plugin.name].lockfile_ts = ts
      completed = completed + 1
      if completed == total_operations then
        callback(results)
      end
    end)
  end
end

-- Get plugin updates asynchronously with direction detection (behind/ahead)
function M.get_plugin_updates_async(config, callback)
  local empty_result = { all_updates = {}, plugins_behind = {}, plugins_ahead = {} }

  if not config then
    vim.notify("Config is required for checking plugin updates", vim.log.levels.WARN, { title = "Plugin Updates" })
    callback(empty_result)
    return
  end

  if not config.repo_path or config.repo_path == "" then
    vim.notify("Invalid repository path for plugin updates", vim.log.levels.WARN, { title = "Plugin Updates" })
    callback(empty_result)
    return
  end

  if not M.is_lazy_available() then
    callback(empty_result)
    return
  end

  local lockfile_path = config.repo_path .. "/lazy-lock.json"
  local lockfile_data = read_lockfile(lockfile_path)

  if not lockfile_data or type(lockfile_data) ~= "table" then
    callback(empty_result)
    return
  end

  -- First pass: identify plugins with mismatched commits and collect their info
  local plugins_with_diff = {}
  for plugin_name, lock_info in pairs(lockfile_data) do
    if type(plugin_name) == "string" and type(lock_info) == "table" then
      local installed_commit = M.get_installed_plugin_commit(plugin_name)
      local plugin_dir = get_plugin_dir(plugin_name)

      if installed_commit and lock_info.commit and type(lock_info.commit) == "string" then
        if installed_commit ~= lock_info.commit then
          table.insert(plugins_with_diff, {
            name = plugin_name,
            dir = plugin_dir,
            installed_commit = installed_commit:sub(1, 7),
            lockfile_commit = lock_info.commit:sub(1, 7),
            installed_commit_full = installed_commit,
            lockfile_commit_full = lock_info.commit,
            branch = lock_info.branch or "main",
          })
        end
      end
    end
  end

  -- If no differences found, return immediately
  if #plugins_with_diff == 0 then
    callback(empty_result)
    return
  end

  -- Second pass: get timestamps and categorize
  get_commit_timestamps_batch(plugins_with_diff, function(timestamps)
    local all_updates = {}
    local plugins_behind = {}
    local plugins_ahead = {}

    for _, plugin in ipairs(plugins_with_diff) do
      local ts_data = timestamps[plugin.name] or {}
      local installed_ts = ts_data.installed_ts
      local lockfile_ts = ts_data.lockfile_ts

      -- Determine direction based on timestamps
      -- Default to "behind" if we can't determine (conservative approach)
      local direction = "behind"
      if installed_ts and lockfile_ts then
        if installed_ts > lockfile_ts then
          direction = "ahead"
        else
          direction = "behind"
        end
      end

      local update_info = {
        name = plugin.name,
        installed_commit = plugin.installed_commit,
        lockfile_commit = plugin.lockfile_commit,
        branch = plugin.branch,
        direction = direction,
      }

      table.insert(all_updates, update_info)

      if direction == "ahead" then
        table.insert(plugins_ahead, update_info)
      else
        table.insert(plugins_behind, update_info)
      end
    end

    callback({
      all_updates = all_updates,
      plugins_behind = plugins_behind,
      plugins_ahead = plugins_ahead,
    })
  end)
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
    vim.notify("Cannot install plugin updates: lazy.nvim not found", vim.log.levels.ERROR, { title = "Plugin Updates" })
    return
  end

  Status.state.is_installing_plugins = true
  Spinner.start_loading_spinner(render_callback)
  if render_callback then
    render_callback("normal")
  end

  -- Use vim.system for async execution
  local cmd = "cd "
    .. vim.fn.shellescape(config.repo_path)
    .. " && nvim --headless +'lua require(\"lazy\").restore({wait=true})' +qa"

  vim.system({ "bash", "-c", cmd }, { text = true }, function(obj)
    vim.schedule(function()
      Status.state.is_installing_plugins = false
      Spinner.stop_loading_spinner()

      local result = obj.stdout or ""
      if obj.code ~= 0 or result:match("error") or result:match("Error") then
        vim.notify(
          "Failed to install plugin updates: " .. (result ~= "" and result or "Unknown error"),
          vim.log.levels.ERROR,
          { title = "Plugin Updates" }
        )
      else
        vim.notify("Successfully restored plugins from lockfile!", vim.log.levels.INFO, { title = "Plugin Updates" })
        -- Re-check plugin status asynchronously to update all state fields
        M.get_plugin_updates_async(config, function(plugin_result)
          Status.state.plugin_updates = plugin_result.all_updates
          Status.state.plugins_behind = plugin_result.plugins_behind
          Status.state.plugins_ahead = plugin_result.plugins_ahead
          Status.state.has_plugin_updates = #plugin_result.all_updates > 0
          Status.state.has_plugins_behind = #plugin_result.plugins_behind > 0
          Status.state.has_plugins_ahead = #plugin_result.plugins_ahead > 0
          Status.state.recently_updated_plugins = true

          if render_callback then
            render_callback("normal")
          end
        end)
        return -- Don't call render_callback here, it's called in the async callback
      end

      if render_callback then
        render_callback("normal")
      end
    end)
  end)
end

return M
