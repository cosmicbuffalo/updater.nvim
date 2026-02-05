local M = {}

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
  plugins_behind = {},
  plugins_ahead = {},
  has_plugin_updates = false,
  has_plugins_behind = false,
  has_plugins_ahead = false,

  -- Restart reminder state
  recently_updated_dotfiles = false,
  recently_updated_plugins = false,

  -- Spinner state
  loading_spinner_timer = nil,
  loading_spinner_frame = 1,

  -- Periodic check state
  periodic_timer = nil,

  -- Debug state
  debug_enabled = false,
  debug_simulate_dotfiles = 0,
  debug_simulate_plugins = 0,

  -- Version tracking state
  version_mode = "latest", -- "latest" | "pinned"
  pinned_version = nil, -- tag name when pinned
  current_tag = nil, -- tag if HEAD is exactly on one
  is_switching_version = false,

  -- Release tracking state (for versioned_releases_only mode)
  current_release = nil, -- latest release tag on current branch
  latest_remote_release = nil, -- latest release tag on remote main
  has_new_release = false, -- true if remote has newer release
  commits_since_release = 0, -- commits on branch after current_release
  commits_since_release_list = {}, -- actual commit objects since release
  release_commit = nil, -- commit info for the current release tag
  releases_since_current = {}, -- release tags newer than current release
  releases_before_current = {}, -- release tags older than current release
  is_detached_head = false, -- true if on detached HEAD
}

function M.stop_periodic_timer()
  if state.periodic_timer then
    state.periodic_timer:stop()
    state.periodic_timer:close()
    state.periodic_timer = nil
  end
end

function M.has_cached_data()
  return state.last_check_time ~= nil
end

function M.has_updates()
  return state.needs_update or state.has_plugin_updates or state.has_plugins_behind or state.has_plugins_ahead
end

function M.has_recent_updates()
  return state.recently_updated_dotfiles or state.recently_updated_plugins
end

function M.clear_recent_updates()
  state.recently_updated_dotfiles = false
  state.recently_updated_plugins = false
end

-- Status API for external consumers
function M.get()
  return {
    needs_update = state.needs_update,
    behind_count = state.behind_count,
    ahead_count = state.ahead_count,
    has_plugin_updates = state.has_plugin_updates,
    has_plugins_behind = state.has_plugins_behind,
    has_plugins_ahead = state.has_plugins_ahead,
    plugin_update_count = #state.plugin_updates,
    plugins_behind_count = #state.plugins_behind,
    plugins_ahead_count = #state.plugins_ahead,
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
  -- Only count plugins that are behind (need updates), not those ahead
  if state.has_plugins_behind then
    count = count + #state.plugins_behind
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

  -- Only show count for plugins that are behind (need updates)
  if state.has_plugins_behind then
    local plugin_count = #state.plugins_behind
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

-- Version tracking helpers
function M.is_pinned_to_version()
  return state.version_mode == "pinned" and state.pinned_version ~= nil
end

function M.get_version_display()
  if state.version_mode == "pinned" and state.pinned_version then
    return state.pinned_version
  elseif state.current_tag then
    return state.current_tag
  else
    return "latest"
  end
end

M.state = state

return M
