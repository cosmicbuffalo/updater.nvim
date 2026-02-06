local Git = require("updater.git")
local Status = require("updater.status")
local Spinner = require("updater.spinner")
local Constants = require("updater.constants")
local Operations -- Lazy loaded to avoid circular dependency
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

-- Check if mason-lock plugin is installed
local function has_mason_lock()
  local ok = pcall(require, "mason-lock")
  return ok
end

-- Restore plugins and mason tools in a headless Neovim instance
-- This avoids opening the Lazy UI or Mason UI in the current session
local function restore_in_headless(callback)
  -- Check if mason-lock is available before including it in the script
  local include_mason = has_mason_lock()

  -- Build the restore script
  local restore_script = [[
vim.schedule(function()
  -- Wait a bit for plugins to initialize
  vim.defer_fn(function()
    -- Restore lazy plugins silently
    local lazy_ok, lazy = pcall(require, "lazy")
    if lazy_ok then
      -- Use pcall to catch any errors
      pcall(function()
        lazy.restore({ wait = true })
      end)
    end
]]

  if include_mason then
    restore_script = restore_script .. [[
    -- Restore mason tools
    local mason_ok, mason_lock = pcall(require, "mason-lock")
    if mason_ok then
      pcall(function()
        mason_lock.restore_from_lockfile()
      end)
    end
]]
  end

  restore_script = restore_script .. [[
    -- Exit after operations complete
    vim.defer_fn(function()
      vim.cmd("qa!")
    end, 500)
  end, 100)
end)
]]

  -- Write to temp file
  local script_path = vim.fn.tempname() .. "_restore.lua"
  local f = io.open(script_path, "w")
  if not f then
    callback(false, "Failed to create restore script")
    return
  end
  f:write(restore_script)
  f:close()

  -- Run headless Neovim with the user's config
  local handle = vim.fn.jobstart({
    "nvim",
    "--headless",
    "-c",
    "luafile " .. script_path,
  }, {
    on_exit = function(_, code)
      -- Clean up temp file
      os.remove(script_path)

      vim.schedule(function()
        if code == 0 then
          callback(true, nil)
        else
          callback(false, "Restore process exited with code " .. code)
        end
      end)
    end,
    stdout_buffered = true,
    stderr_buffered = true,
  })

  if handle <= 0 then
    os.remove(script_path)
    callback(false, "Failed to start restore process")
  end
end

-- Switch to a specific version tag
-- Helper to clear switching state on error
local function clear_switching_state(state)
  state.is_switching_version = false
  state.switching_to_version = nil
  Spinner.stop_loading_spinner()
end

function M.switch_to_version(config, version, callback, render_callback)
  local state = Status.state

  -- Prevent concurrent switches
  if state.is_switching_version then
    callback(false, "Version switch already in progress")
    return
  end

  state.is_switching_version = true
  state.switching_to_version = version
  state.recently_switched_to = nil -- Clear any previous success message

  -- Capture previous version for upgrade/downgrade detection
  local previous_release = state.current_release

  -- Start spinner and render immediately
  Spinner.start_loading_spinner(render_callback)
  if render_callback then
    render_callback()
  end

  -- Step 1: Check for uncommitted changes
  M.has_uncommitted_changes(config, function(has_changes, err)
    if err then
      clear_switching_state(state)
      callback(false, "Failed to check for changes: " .. err)
      return
    end

    if has_changes then
      clear_switching_state(state)
      callback(false, "Cannot switch: uncommitted changes exist. Commit or stash your changes first.")
      return
    end

    -- Step 2: Verify tag exists
    M.get_available_versions(config, function(tags, tags_err)
      if tags_err then
        clear_switching_state(state)
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
        clear_switching_state(state)
        local available = table.concat(vim.list_slice(tags, 1, math.min(5, #tags)), ", ")
        callback(false, "Version " .. version .. " not found. Available: " .. available)
        return
      end

      -- Step 3: Checkout tag
      Git.checkout_tag(config, config.repo_path, version, function(checkout_ok, checkout_err)
        if not checkout_ok then
          clear_switching_state(state)
          callback(false, checkout_err)
          return
        end

        -- Step 4: Restore plugins and mason tools in headless instance
        vim.schedule(function()
          restore_in_headless(function(restore_ok, restore_err)
            if not restore_ok then
              vim.notify(
                "Warning: " .. (restore_err or "unknown error") .. ". Run :Lazy restore manually.",
                vim.log.levels.WARN
              )
            end

            -- Step 5: Refresh state silently (like opening the TUI fresh)
            -- Lazy load Operations to avoid circular dependency
            if not Operations then
              Operations = require("updater.operations")
            end

            Operations.refresh_silent(config, function()
              -- Step 6: Set version switch specific state (not part of refresh)
              state.is_switching_version = false
              state.switching_to_version = nil
              state.recently_switched_to = version
              state.switched_from_version = previous_release

              Spinner.stop_loading_spinner()
              callback(true, "Switched to " .. version)
            end)
          end)
        end)
      end)
    end)
  end)
end

-- Switch to latest (newest release tag)
function M.switch_to_latest(config, callback, render_callback)
  -- Get the latest version tag first
  M.get_available_versions(config, function(tags, tags_err)
    if tags_err then
      callback(false, "Failed to fetch versions: " .. tags_err)
      return
    end

    if #tags == 0 then
      callback(false, "No release tags found")
      return
    end

    -- First tag is the latest (sorted by version descending)
    local latest_tag = tags[1]

    -- Use switch_to_version to do the actual switch (latest is just another version)
    M.switch_to_version(config, latest_tag, callback, render_callback)
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

    for _, tag in ipairs(tags) do
      local label = tag

      -- Add release title from GitHub API if available
      local release_title = Status.get_release_title(tag)
      if release_title and release_title ~= "" and release_title ~= tag then
        label = label .. " - " .. release_title
      end

      -- Build annotations
      local annotations = {}

      -- Add prerelease indicator if from GitHub API
      if Status.is_prerelease(tag) then
        table.insert(annotations, "prerelease")
      end
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
function M.get_completion_list(_config, arglead)
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

function M.set_current_tag(config, callback)
  Git.get_head_tag(config, config.repo_path, function(tag, _err)
    local state = Status.state
    state.current_tag = tag

    if callback then
      callback()
    end
  end)
end

return M
