local Git = require("updater.git")
local Status = require("updater.status")
local Constants = require("updater.constants")
local M = {}

-- Cache for version tags
local version_cache = {
  tags = {},
  last_fetch = 0,
}

-- Get available versions (with caching)
function M.get_available_versions(config, callback)
  local now = os.time()
  if now - version_cache.last_fetch < Constants.VERSION_CACHE_TTL and #version_cache.tags > 0 then
    callback(version_cache.tags, nil)
    return
  end

  Git.get_version_tags(config, config.repo_path, function(tags, err)
    if err then
      callback({}, err)
      return
    end

    version_cache.tags = tags
    version_cache.last_fetch = now
    callback(tags, nil)
  end)
end

-- Check for uncommitted changes
function M.has_uncommitted_changes(config, callback)
  Git.has_uncommitted_changes(config, config.repo_path, callback)
end

-- Restore plugins via lazy.restore()
local function restore_lazy_plugins(callback)
  local ok, lazy = pcall(require, "lazy")
  if not ok then
    callback(false, "lazy.nvim not available")
    return
  end

  -- lazy.restore() restores plugins to versions in lazy-lock.json
  local restore_ok, restore_err = pcall(function()
    lazy.restore({ wait = true })
  end)

  if not restore_ok then
    callback(false, "Failed to restore plugins: " .. tostring(restore_err))
  else
    callback(true, nil)
  end
end

-- Restore mason tools via mason-lock
local function restore_mason_tools(callback)
  local ok, mason_lock = pcall(require, "mason-lock")
  if not ok then
    -- mason-lock not installed, skip silently
    callback(true, nil)
    return
  end

  local restore_ok, restore_err = pcall(function()
    mason_lock.restore_from_lockfile()
  end)

  if not restore_ok then
    callback(false, "Failed to restore mason tools: " .. tostring(restore_err))
  else
    callback(true, nil)
  end
end

-- Switch to a specific version tag
function M.switch_to_version(config, version, callback)
  local state = Status.state

  -- Prevent concurrent switches
  if state.is_switching_version then
    callback(false, "Version switch already in progress")
    return
  end

  state.is_switching_version = true

  -- Step 1: Check for uncommitted changes
  M.has_uncommitted_changes(config, function(has_changes, err)
    if err then
      state.is_switching_version = false
      callback(false, "Failed to check for changes: " .. err)
      return
    end

    if has_changes then
      state.is_switching_version = false
      callback(false, "Cannot switch: uncommitted changes exist. Commit or stash your changes first.")
      return
    end

    -- Step 2: Verify tag exists
    M.get_available_versions(config, function(tags, tags_err)
      if tags_err then
        state.is_switching_version = false
        callback(false, "Failed to fetch versions: " .. tags_err)
        return
      end

      local found = false
      for _, tag in ipairs(tags) do
        if tag == version then
          found = true
          break
        end
      end

      if not found then
        state.is_switching_version = false
        local available = table.concat(vim.list_slice(tags, 1, math.min(5, #tags)), ", ")
        callback(false, "Version " .. version .. " not found. Available: " .. available)
        return
      end

      -- Step 3: Checkout tag
      Git.checkout_tag(config, config.repo_path, version, function(checkout_ok, checkout_err)
        if not checkout_ok then
          state.is_switching_version = false
          callback(false, checkout_err)
          return
        end

        -- Step 4: Restore plugins
        vim.schedule(function()
          restore_lazy_plugins(function(lazy_ok, lazy_err)
            if not lazy_ok then
              vim.notify("Warning: " .. lazy_err .. ". Run :Lazy restore manually.", vim.log.levels.WARN)
            end

            -- Step 5: Restore mason tools
            restore_mason_tools(function(mason_ok, mason_err)
              if not mason_ok then
                vim.notify("Warning: " .. mason_err .. ". Run :MasonLockRestore manually.", vim.log.levels.WARN)
              end

              -- Step 6: Update state
              state.version_mode = "pinned"
              state.pinned_version = version
              state.current_tag = version
              state.is_switching_version = false

              callback(true, "Switched to " .. version)
            end)
          end)
        end)
      end)
    end)
  end)
end

-- Switch to latest (newest release tag)
function M.switch_to_latest(config, callback)
  local state = Status.state

  -- Prevent concurrent switches
  if state.is_switching_version then
    callback(false, "Version switch already in progress")
    return
  end

  state.is_switching_version = true

  -- Step 1: Check for uncommitted changes
  M.has_uncommitted_changes(config, function(has_changes, err)
    if err then
      state.is_switching_version = false
      callback(false, "Failed to check for changes: " .. err)
      return
    end

    if has_changes then
      state.is_switching_version = false
      callback(false, "Cannot switch: uncommitted changes exist. Commit or stash your changes first.")
      return
    end

    -- Step 2: Get the latest version tag
    M.get_available_versions(config, function(tags, tags_err)
      if tags_err then
        state.is_switching_version = false
        callback(false, "Failed to fetch versions: " .. tags_err)
        return
      end

      if #tags == 0 then
        state.is_switching_version = false
        callback(false, "No release tags found")
        return
      end

      -- First tag is the latest (sorted by version descending)
      local latest_tag = tags[1]

      -- Step 3: Checkout the latest tag
      Git.checkout_tag(config, config.repo_path, latest_tag, function(checkout_ok, checkout_err)
        if not checkout_ok then
          state.is_switching_version = false
          callback(false, checkout_err)
          return
        end

        -- Step 4: Restore plugins
        vim.schedule(function()
          restore_lazy_plugins(function(lazy_ok, lazy_err)
            if not lazy_ok then
              vim.notify("Warning: " .. lazy_err .. ". Run :Lazy restore manually.", vim.log.levels.WARN)
            end

            -- Step 5: Restore mason tools
            restore_mason_tools(function(mason_ok, mason_err)
              if not mason_ok then
                vim.notify("Warning: " .. mason_err .. ". Run :MasonLockRestore manually.", vim.log.levels.WARN)
              end

              -- Step 7: Update state
              -- When switching to latest, we're not "pinned" - we're on the latest release
              state.version_mode = "latest"
              state.pinned_version = nil
              state.current_tag = latest_tag
              state.is_switching_version = false

              callback(true, "Switched to " .. latest_tag)
            end)
          end)
        end)
      end)
    end)
  end)
end

-- Show interactive version picker
function M.show_version_picker(config)
  M.get_available_versions(config, function(tags, err)
    if err then
      vim.notify("Failed to fetch versions: " .. err, vim.log.levels.ERROR)
      return
    end

    if #tags == 0 then
      vim.notify("No version tags found. Create tags with 'git tag v1.0.0' to use version switching.", vim.log.levels.INFO)
      return
    end

    -- Mark current version and latest
    local current = Status.get_version_display()
    local latest_tag = tags[1] -- First tag is latest (sorted by version descending)
    local formatted_options = {}

    for i, tag in ipairs(tags) do
      local label = tag
      local annotations = {}

      if tag == latest_tag then
        table.insert(annotations, "latest")
      end
      if tag == current then
        table.insert(annotations, "current")
      end

      if #annotations > 0 then
        label = label .. " (" .. table.concat(annotations, ", ") .. ")"
      end

      table.insert(formatted_options, label)
    end

    vim.ui.select(formatted_options, {
      prompt = "Select dotfiles version:",
      format_item = function(item)
        return item
      end,
    }, function(choice, idx)
      if not choice or not idx then
        return
      end

      local selected = tags[idx]
      if selected == current then
        vim.notify("Already on " .. selected, vim.log.levels.INFO)
        return
      end

      M.switch_to_version(config, selected, function(success, msg)
        if success then
          vim.notify(msg, vim.log.levels.INFO)
        else
          vim.notify(msg, vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

-- Get completion list for command
function M.get_completion_list(config, arglead)
  arglead = arglead or ""

  -- Return cached tags
  local completions = {}
  for _, tag in ipairs(version_cache.tags) do
    if arglead == "" or tag:find(arglead, 1, true) == 1 then
      table.insert(completions, tag)
    end
  end

  return completions
end

-- Handle :DotfilesVersion command
function M.handle_command(config, arg)
  arg = arg or ""

  if arg == "" then
    -- No argument: show version picker
    M.show_version_picker(config)
  else
    -- Switch to specific version
    M.switch_to_version(config, arg, function(success, msg)
      if success then
        vim.notify(msg, vim.log.levels.INFO, { title = "Dotfiles Version" })
      else
        vim.notify(msg, vim.log.levels.ERROR, { title = "Dotfiles Version" })
      end
    end)
  end
end

-- Detect version mode on startup/refresh
function M.detect_version_mode(config, callback)
  Git.get_head_tag(config, config.repo_path, function(tag, err)
    local state = Status.state

    if tag then
      -- HEAD is on a tag
      state.current_tag = tag
      -- If we're on a tag and not explicitly set to latest, assume pinned
      if state.version_mode ~= "latest" or state.pinned_version == tag then
        state.version_mode = "pinned"
        state.pinned_version = tag
      end
    else
      state.current_tag = nil
      -- If not on a tag, we're on latest
      if state.version_mode ~= "pinned" then
        state.version_mode = "latest"
        state.pinned_version = nil
      end
    end

    if callback then
      callback()
    end
  end)
end

return M
