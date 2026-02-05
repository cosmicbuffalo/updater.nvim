local Constants = require("updater.constants")
local M = {}

local function find_section_line(buffer, section_title_pattern)
  local line_count = vim.api.nvim_buf_line_count(buffer)
  for i = 0, line_count - 1 do
    local line = vim.api.nvim_buf_get_lines(buffer, i, i + 1, false)
    if #line > 0 and line[1] and string.match(line[1], section_title_pattern) then
      return i
    end
  end
  return nil
end

local function generate_branch_status(state, config)
  local lines = {}

  -- Build branch line with optional tag
  local branch_line = "  Branch: " .. state.current_branch
  if state.current_commit then
    local short_commit = state.current_commit:sub(1, 7)
    branch_line = branch_line .. " @ " .. short_commit
    -- Add current tag if on one (will be highlighted green later)
    if state.current_tag then
      branch_line = branch_line .. " [" .. state.current_tag .. "]"
    end
  end
  table.insert(lines, branch_line)

  if state.current_branch == config.main_branch then
    if state.ahead_count > 0 then
      table.insert(
        lines,
        string.format(
          "  Your %s branch is ahead of origin/%s by %d commits",
          config.main_branch,
          config.main_branch,
          state.ahead_count
        )
      )
    elseif state.behind_count > 0 then
      table.insert(
        lines,
        string.format(
          "  Your %s branch is behind origin/%s by %d commits",
          config.main_branch,
          config.main_branch,
          state.behind_count
        )
      )
    else
      table.insert(
        lines,
        string.format("  Your %s branch is in sync with origin/%s", config.main_branch, config.main_branch)
      )
    end
  else
    if state.ahead_count > 0 then
      table.insert(
        lines,
        string.format("  Your branch is ahead of origin/%s by %d commits", config.main_branch, state.ahead_count)
      )
    end
    if state.behind_count > 0 then
      table.insert(
        lines,
        string.format("  Your branch is behind origin/%s by %d commits", config.main_branch, state.behind_count)
      )
    end
  end

  return lines
end

-- Returns a table of { text = "...", hl_group = "..." } for status lines
local function generate_status_messages(state, config)
  local is_on_main = state.current_branch == config.main_branch
  local messages = {}

  if state.is_updating then
    table.insert(messages, {
      text = "  " .. M.get_loading_spinner(state) .. " Updating dotfiles... Please wait.",
      hl_group = "WarningMsg",
    })
    return messages
  elseif state.is_installing_plugins then
    table.insert(messages, {
      text = "  " .. M.get_loading_spinner(state) .. " Installing plugin updates... Please wait.",
      hl_group = "WarningMsg",
    })
    return messages
  elseif state.is_refreshing then
    local check_msg = is_on_main and "Checking for updates..." or "Seeing what's new on main..."
    if state.is_initial_load then
      table.insert(messages, {
        text = "  " .. M.get_loading_spinner(state) .. " " .. check_msg .. " Please wait.",
        hl_group = "WarningMsg",
      })
    else
      -- Background refresh with cached data - show subtle indicator
      table.insert(messages, {
        text = "  " .. M.get_loading_spinner(state) .. " " .. check_msg .. " Please wait. (showing cached data)",
        hl_group = "WarningMsg",
      })
    end
    return messages
  end

  -- Determine what updates are available
  local has_dotfile_updates = state.behind_count > 0
  local has_plugins_behind = state.has_plugins_behind or false
  local has_plugins_ahead = state.has_plugins_ahead or false
  local plugins_behind_count = state.plugins_behind and #state.plugins_behind or 0
  local plugins_ahead_count = state.plugins_ahead and #state.plugins_ahead or 0

  -- Build the green "updates available" message (only for actual updates)
  if has_dotfile_updates or has_plugins_behind then
    local update_parts = {}
    if has_dotfile_updates then
      table.insert(update_parts, "Dotfiles update")
    end
    if has_plugins_behind then
      table.insert(update_parts, tostring(plugins_behind_count) .. " plugin update(s)")
    end
    table.insert(messages, {
      text = "  " .. table.concat(update_parts, " and ") .. " available!",
      hl_group = "String",
    })
  else
    -- No actual updates - show up to date message
    if is_on_main then
      table.insert(messages, {
        text = "  Your dotfiles and plugins are up to date!",
        hl_group = "String",
      })
    else
      table.insert(messages, {
        text = "  Your current branch is up to date with the latest commits on main",
        hl_group = "String",
      })
    end
  end

  -- Add yellow warning for plugins ahead (downgrades available)
  if has_plugins_ahead then
    table.insert(messages, {
      text = "  " .. tostring(plugins_ahead_count) .. " plugin(s) ahead of lockfile (can be downgraded)",
      hl_group = "WarningMsg",
    })
  end

  return messages
end

function M.generate_header(state, config)
  local header = { "" }

  -- Add branch status lines
  local branch_lines = generate_branch_status(state, config)
  for _, line in ipairs(branch_lines) do
    table.insert(header, line)
  end

  table.insert(header, "")

  -- Add status messages (may be multiple lines with different highlighting)
  local status_messages = generate_status_messages(state, config)
  local status_lines_start = #header -- 0-indexed line where status starts
  for _, msg in ipairs(status_messages) do
    table.insert(header, msg.text)
  end
  table.insert(header, "")

  return header, status_messages, status_lines_start
end

function M.generate_keybindings(state, config)
  local is_on_main = state.current_branch == config.main_branch
  local has_plugins_behind = state.has_plugins_behind or false
  local has_plugins_ahead = state.has_plugins_ahead or false
  local has_any_updates = state.behind_count > 0 or has_plugins_behind or has_plugins_ahead
  local lines = { "  Keybindings:" }
  local keybind_data = {} -- Track keybinds for highlighting

  -- U - Update all: Only show on main branch AND when there are updates available
  if is_on_main and has_any_updates then
    table.insert(lines, "    " .. config.keymap.update_all .. " - Update dotfiles + install plugin updates")
    table.insert(keybind_data, { key = config.keymap.update_all })
  end

  -- u - Update dotfiles: Only show if behind_count > 0
  if state.behind_count > 0 then
    local label = is_on_main and "Update dotfiles" or "Pull latest main into branch"
    table.insert(lines, "    " .. config.keymap.update .. " - " .. label)
    table.insert(keybind_data, { key = config.keymap.update })
  end

  -- i - Install plugins: Show if any plugin differences exist (behind or ahead)
  if has_plugins_behind or has_plugins_ahead then
    local label = has_plugins_ahead and "Update/Downgrade plugins (:Lazy restore)"
      or "Install plugin updates (:Lazy restore)"
    table.insert(lines, "    " .. config.keymap.install_plugins .. " - " .. label)
    table.insert(keybind_data, { key = config.keymap.install_plugins })
  end

  -- r - Refresh: Always show
  table.insert(lines, "    " .. config.keymap.refresh .. " - Refresh status")
  table.insert(keybind_data, { key = config.keymap.refresh })

  -- q - Close: Always show
  table.insert(lines, "    " .. config.keymap.close .. " - Close window")
  table.insert(keybind_data, { key = config.keymap.close })

  table.insert(lines, "")

  return lines, keybind_data
end

function M.generate_remote_commits_section(state, config)
  local remote_commit_info = {}
  if #state.remote_commits > 0 then
    table.insert(remote_commit_info, "  Commits on origin/" .. config.main_branch .. " not in your branch:")
    table.insert(remote_commit_info, "  " .. Constants.SEPARATOR_LINE)

    for _, commit in ipairs(state.remote_commits) do
      local status_indicator = state.commits_in_branch[commit.hash] and "✓" or "✗"
      local line = string.format(
        "  %s %s - %s (%s, %s)",
        status_indicator,
        commit.hash,
        commit.message,
        commit.author,
        commit.date
      )
      table.insert(remote_commit_info, line)
    end
    table.insert(remote_commit_info, "  ")
  end
  return remote_commit_info
end

function M.generate_plugin_updates_section(state)
  local plugin_update_info = {}
  -- Only show plugins that are behind (need updates)
  local plugins_behind = state.plugins_behind or {}
  if #plugins_behind > 0 then
    table.insert(plugin_update_info, "  Plugin updates available:")
    table.insert(plugin_update_info, "  " .. Constants.SEPARATOR_LINE)

    for _, plugin in ipairs(plugins_behind) do
      local line = "  " .. plugin.name .. " (" .. plugin.installed_commit .. " → " .. plugin.lockfile_commit .. ")"

      table.insert(plugin_update_info, line)
    end
    table.insert(plugin_update_info, "  ")
  end
  return plugin_update_info
end

function M.generate_plugins_ahead_section(state)
  local plugins_ahead_info = {}
  local plugins_ahead = state.plugins_ahead or {}
  if #plugins_ahead > 0 then
    table.insert(plugins_ahead_info, "  Plugins ahead of lockfile:")
    table.insert(plugins_ahead_info, "  " .. Constants.SEPARATOR_LINE)

    for _, plugin in ipairs(plugins_ahead) do
      -- Use reversed arrow to indicate lockfile is behind installed
      local line = "  " .. plugin.name .. " (" .. plugin.lockfile_commit .. " ← " .. plugin.installed_commit .. ")"
      table.insert(plugins_ahead_info, line)
    end
    table.insert(plugins_ahead_info, "  ")
  end
  return plugins_ahead_info
end

function M.generate_restart_reminder_section(state)
  local restart_info = {}

  if state.recently_updated_dotfiles or state.recently_updated_plugins then
    table.insert(restart_info, "  ⚠️  Restart Recommended")
    table.insert(restart_info, "  " .. Constants.SEPARATOR_LINE)

    local updated_items = {}
    if state.recently_updated_dotfiles then
      table.insert(updated_items, "dotfiles")
    end
    if state.recently_updated_plugins then
      table.insert(updated_items, "plugins")
    end

    local items_text = table.concat(updated_items, " and ")
    table.insert(restart_info, "  " .. items_text:sub(1, 1):upper() .. items_text:sub(2) .. " have been updated.")
    table.insert(restart_info, "  You may need to restart Neovim for all changes to take effect.")
    table.insert(restart_info, "  ")
    table.insert(restart_info, "  💡 Tip: Save your session, restart nvim, then load your session")
    table.insert(restart_info, "     to minimize interruptions to your workflow.")
    table.insert(restart_info, "  ")
    table.insert(restart_info, "  Commands: :mksession | :qa | nvim -S")
    table.insert(restart_info, "  ")
  end

  return restart_info
end

function M.generate_commit_log(state, config)
  local log_title = state.log_type == "remote"
      and "  Commits from origin/" .. config.main_branch .. " not in your branch:"
    or "  Local commits on " .. state.current_branch .. ":"

  local log_lines = {
    log_title,
    "  " .. Constants.SEPARATOR_LINE,
  }

  local current_hash = state.current_commit
  for _, commit in ipairs(state.commits) do
    local indicator = "  "
    if commit.hash == current_hash:sub(1, #commit.hash) then
      indicator = "→ "
    end

    local line = "  "
      .. indicator
      .. commit.hash
      .. " - "
      .. commit.message
      .. " ("
      .. commit.author
      .. ", "
      .. commit.date
      .. ")"
    table.insert(log_lines, line)
  end

  return log_lines
end

-- ============================================================================
-- Release-focused UI (for versioned_releases_only mode)
-- ============================================================================

local function generate_release_branch_status(state, config)
  local lines = {}

  -- Show current release prominently
  local release_line = "  Current Release: "
  if state.current_release then
    release_line = release_line .. state.current_release
  else
    release_line = release_line .. "(no release)"
  end
  table.insert(lines, release_line)

  -- Show branch info with detached HEAD handling
  local branch_display = state.current_branch
  if state.is_detached_head or state.current_branch == "HEAD" then
    branch_display = "detached HEAD"
    if state.current_tag then
      branch_display = branch_display .. " at " .. state.current_tag
    end
  end

  local branch_line = "  Branch: " .. branch_display
  -- Only show commits since release if we're not exactly on a tag
  if not state.current_tag and state.commits_since_release > 0 then
    branch_line = branch_line .. " (+" .. state.commits_since_release .. " commits since release)"
  end
  table.insert(lines, branch_line)

  return lines
end

local function generate_release_status_messages(state, config)
  local messages = {}

  if state.is_updating then
    table.insert(messages, {
      text = "  " .. M.get_loading_spinner(state) .. " Updating to latest release... Please wait.",
      hl_group = "WarningMsg",
    })
    return messages
  elseif state.is_installing_plugins then
    table.insert(messages, {
      text = "  " .. M.get_loading_spinner(state) .. " Installing plugin updates... Please wait.",
      hl_group = "WarningMsg",
    })
    return messages
  elseif state.is_refreshing then
    table.insert(messages, {
      text = "  " .. M.get_loading_spinner(state) .. " Checking for new releases... Please wait.",
      hl_group = "WarningMsg",
    })
    return messages
  end

  -- Check for new release
  if state.has_new_release and state.latest_remote_release then
    table.insert(messages, {
      text = "  New release available: " .. state.latest_remote_release,
      hl_group = "String",
    })
  else
    table.insert(messages, {
      text = "  You are on the latest release!",
      hl_group = "String",
    })
  end

  -- Show plugin status
  local has_plugins_behind = state.has_plugins_behind or false
  if has_plugins_behind then
    local plugins_behind_count = state.plugins_behind and #state.plugins_behind or 0
    table.insert(messages, {
      text = "  " .. tostring(plugins_behind_count) .. " plugin update(s) available",
      hl_group = "String",
    })
  end

  return messages
end

function M.generate_release_header(state, config)
  local header = { "" }

  -- Add release-focused branch status
  local branch_lines = generate_release_branch_status(state, config)
  for _, line in ipairs(branch_lines) do
    table.insert(header, line)
  end

  table.insert(header, "")

  -- Add release status messages
  local status_messages = generate_release_status_messages(state, config)
  local status_lines_start = #header
  for _, msg in ipairs(status_messages) do
    table.insert(header, msg.text)
  end
  table.insert(header, "")

  return header, status_messages, status_lines_start
end

function M.generate_release_keybindings(state, config)
  local lines = { "  Keybindings:" }
  local keybind_data = {}

  -- U - Update to latest release (when new release available)
  if state.has_new_release then
    table.insert(lines, "    " .. config.keymap.update_all .. " - Update to latest release")
    table.insert(keybind_data, { key = config.keymap.update_all })
  end

  -- i - Install plugins (if plugin updates available)
  if state.has_plugins_behind or state.has_plugins_ahead then
    table.insert(lines, "    " .. config.keymap.install_plugins .. " - Sync plugins to release lockfile")
    table.insert(keybind_data, { key = config.keymap.install_plugins })
  end

  -- r - Refresh
  table.insert(lines, "    " .. config.keymap.refresh .. " - Check for new releases")
  table.insert(keybind_data, { key = config.keymap.refresh })

  -- q - Close
  table.insert(lines, "    " .. config.keymap.close .. " - Close window")
  table.insert(keybind_data, { key = config.keymap.close })

  table.insert(lines, "")

  return lines, keybind_data
end

function M.generate_commits_since_release_section(state, config)
  local lines = {}

  -- Only show if there are actual commits since the release (not on a tag)
  local commits_list = state.commits_since_release_list or {}
  if #commits_list > 0 and not state.current_tag then
    table.insert(lines, "  Commits since " .. (state.current_release or "release") .. ":")
    table.insert(lines, "  " .. Constants.SEPARATOR_LINE)

    -- Show commits newer than the release (with yellow commit SHAs)
    local current_hash = state.current_commit or ""

    for _, commit in ipairs(commits_list) do
      local indicator = "  "
      if commit.hash == current_hash:sub(1, #commit.hash) then
        indicator = "→ "
      end
      local line = "  " .. indicator .. commit.hash .. " - " .. commit.message
      table.insert(lines, line)
    end

    -- Show the release commit at the bottom (with green tag before the message)
    if state.release_commit then
      local rc = state.release_commit
      local tag = rc.tag or state.current_release
      local line = "    " .. rc.hash .. " - [" .. tag .. "] " .. rc.message
      table.insert(lines, line)
    end

    table.insert(lines, "  ")
  end

  return lines
end

function M.generate_releases_since_section(state, config)
  local lines = {}
  local releases_since = state.releases_since_current or {}

  -- Show if there are newer releases available
  if #releases_since > 0 then
    table.insert(lines, "  Releases since " .. (state.current_release or "current") .. ":")
    table.insert(lines, "  " .. Constants.SEPARATOR_LINE)

    -- Show newer releases (newest first, reversed so current is at bottom)
    -- releases_since is already sorted newest first, show them in that order
    for _, release in ipairs(releases_since) do
      local line = "    " .. release.hash .. " - [" .. release.tag .. "] " .. release.message
      table.insert(lines, line)
    end

    -- Show current release at the bottom
    if state.current_release then
      local current_line = "  → "
      if state.release_commit then
        local rc = state.release_commit
        current_line = current_line .. rc.hash .. " - [" .. state.current_release .. "] " .. rc.message .. " (current)"
      else
        -- Fallback if we don't have commit info
        current_line = current_line .. "[" .. state.current_release .. "] (current)"
      end
      table.insert(lines, current_line)
    end

    table.insert(lines, "  ")
  end

  return lines
end

function M.generate_previous_releases_section(state, config)
  local lines = {}
  local releases_before = state.releases_before_current or {}

  -- Show if there are older releases
  if #releases_before > 0 then
    table.insert(lines, "  Previous releases:")
    table.insert(lines, "  " .. Constants.SEPARATOR_LINE)

    -- Show older releases (already sorted newest first, so closest to current is first)
    local max_items = Constants.MAX_SECTION_ITEMS
    local count = math.min(#releases_before, max_items)
    for i = 1, count do
      local release = releases_before[i]
      local line = "    " .. release.hash .. " - [" .. release.tag .. "] " .. release.message
      table.insert(lines, line)
    end

    -- Show ellipsis if there are more releases
    if #releases_before > max_items then
      table.insert(lines, "    ... and " .. (#releases_before - max_items) .. " more")
    end

    table.insert(lines, "  ")
  end

  return lines
end

function M.generate_loading_state(state, config)
  local is_on_main = state.current_branch == config.main_branch
  local loading_msg = is_on_main and "Checking for updates..." or "Seeing what's new on main..."

  local lines = {
    "",
    "  Branch: " .. (state.current_branch ~= "" and state.current_branch or "Loading..."),
    "",
    "  " .. M.get_loading_spinner(state) .. " " .. loading_msg .. " Please wait.",
    "",
    "  Keybindings:",
  }

  -- During loading, show appropriate keybinds based on branch
  if is_on_main then
    table.insert(lines, "    " .. config.keymap.update_all .. " - Update dotfiles + install plugin updates")
  end
  table.insert(
    lines,
    "    " .. config.keymap.update .. " - " .. (is_on_main and "Update dotfiles" or "Pull latest main into branch")
  )
  table.insert(lines, "    " .. config.keymap.install_plugins .. " - Install plugin updates (:Lazy restore)")
  table.insert(lines, "    " .. config.keymap.refresh .. " - Refresh status")
  table.insert(lines, "    " .. config.keymap.close .. " - Close window")
  table.insert(lines, "")
  table.insert(lines, "  Loading repository information...")
  table.insert(lines, "  This may take a moment if checking remote updates.")
  table.insert(lines, "")

  return lines
end

local function add_highlight(buffer, ns_id, hl_group, line, col_start, col_end)
  vim.api.nvim_buf_add_highlight(buffer, ns_id, hl_group, line, col_start, col_end)
end

local function highlight_header(buffer, ns_id, state)
  -- Highlight the branch line
  local line = vim.api.nvim_buf_get_lines(buffer, 1, 2, false)[1] or ""
  add_highlight(buffer, ns_id, "Directory", 1, 2, -1)

  -- If there's a tag in brackets, highlight it green
  if state.current_tag then
    local tag_start = line:find("%[" .. vim.pesc(state.current_tag) .. "%]")
    if tag_start then
      add_highlight(buffer, ns_id, "String", 1, tag_start - 1, tag_start + #state.current_tag + 1)
    end
  end
end

local function highlight_status(buffer, ns_id, status_messages, status_lines_start)
  for i, msg in ipairs(status_messages) do
    local line_num = status_lines_start + i - 1
    add_highlight(buffer, ns_id, msg.hl_group, line_num, 2, -1)
  end
end

local function highlight_keybindings(buffer, ns_id, keybindings_start, keybind_data)
  for i, data in ipairs(keybind_data) do
    local line_num = keybindings_start + i - 1
    add_highlight(buffer, ns_id, "Statement", line_num, 4, 4 + #data.key)
  end
end

local function highlight_restart_reminder(buffer, ns_id, state, restart_reminder_line)
  if state.recently_updated_dotfiles or state.recently_updated_plugins then
    add_highlight(buffer, ns_id, "WarningMsg", restart_reminder_line, 2, -1) -- "⚠️  Restart Recommended"
    add_highlight(buffer, ns_id, "DiagnosticInfo", restart_reminder_line + 6, 2, 6) -- "💡 Tip:" emoji
    add_highlight(buffer, ns_id, "String", restart_reminder_line + 6, 7, 11) -- "Tip:" text
    add_highlight(buffer, ns_id, "Comment", restart_reminder_line + 9, 2, -1) -- "Commands:" line
  end
end

local function highlight_remote_commits(buffer, ns_id, state, config)
  if #state.remote_commits > 0 then
    local title_pattern = "Commits on origin/" .. config.main_branch .. " not in your branch:"
    local section_line = find_section_line(buffer, vim.pesc(title_pattern))

    if section_line then
      -- Highlight section title
      add_highlight(buffer, ns_id, "Title", section_line, 2, -1)

      -- Highlight individual commits after title and separator
      local commit_start_line = section_line + 2
      for i = 1, #state.remote_commits do
        local line_num = commit_start_line + i - 1
        add_highlight(buffer, ns_id, "Statement", line_num, 2, 3) -- Status indicator
        add_highlight(buffer, ns_id, "Directory", line_num, 4, 13) -- Commit hash
        add_highlight(buffer, ns_id, "Comment", line_num, state.remote_commits[i].message:len() + 17, -1) -- Author/date
      end
    end
  end
end

local function highlight_plugin_updates(buffer, ns_id, state)
  local plugins_behind = state.plugins_behind or {}
  if #plugins_behind > 0 then
    local title_pattern = "Plugin updates available:"
    local section_line = find_section_line(buffer, vim.pesc(title_pattern))

    if section_line then
      -- Highlight section title
      add_highlight(buffer, ns_id, "Title", section_line, 2, -1)

      -- Highlight plugin names and commits after title and separator
      local plugin_start_line = section_line + 2
      for i = 1, #plugins_behind do
        local line_num = plugin_start_line + i - 1
        local plugin = plugins_behind[i]
        local name_end = 2 + #plugin.name
        local installed_start = name_end + 2
        local installed_end = installed_start + #plugin.installed_commit
        local lockfile_start = installed_end + 5
        local lockfile_end = lockfile_start + #plugin.lockfile_commit

        add_highlight(buffer, ns_id, "Directory", line_num, 2, name_end) -- Plugin name
        add_highlight(buffer, ns_id, "Constant", line_num, installed_start, installed_end) -- Installed commit (old)
        add_highlight(buffer, ns_id, "String", line_num, lockfile_start, lockfile_end) -- Lockfile commit (new)
      end
    end
  end
end

local function highlight_plugins_ahead(buffer, ns_id, state)
  local plugins_ahead = state.plugins_ahead or {}
  if #plugins_ahead > 0 then
    local title_pattern = "Plugins ahead of lockfile:"
    local section_line = find_section_line(buffer, vim.pesc(title_pattern))

    if section_line then
      -- Highlight section title
      add_highlight(buffer, ns_id, "Title", section_line, 2, -1)

      -- Highlight plugin names and commits after title and separator
      -- Format: "plugin-name (lockfile <- installed)"
      local plugin_start_line = section_line + 2
      for i = 1, #plugins_ahead do
        local line_num = plugin_start_line + i - 1
        local plugin = plugins_ahead[i]
        local name_end = 2 + #plugin.name
        local lockfile_start = name_end + 2
        local lockfile_end = lockfile_start + #plugin.lockfile_commit
        local installed_start = lockfile_end + 5 -- " ← " is 5 bytes (3 char arrow + 2 spaces)
        local installed_end = installed_start + #plugin.installed_commit

        add_highlight(buffer, ns_id, "WarningMsg", line_num, 2, name_end) -- Plugin name (yellow to match downgrade warning)
        add_highlight(buffer, ns_id, "DiagnosticWarn", line_num, lockfile_start, lockfile_end) -- Lockfile commit (old)
        add_highlight(buffer, ns_id, "String", line_num, installed_start, installed_end) -- Installed commit (new)
      end
    end
  end
end

local function highlight_commit_log(buffer, ns_id, state, config)
  -- Search for commit log section by title pattern
  local title_pattern = state.log_type == "remote"
      and "Commits from origin/" .. config.main_branch .. " not in your branch:"
    or "Local commits on " .. state.current_branch .. ":"

  local section_line = find_section_line(buffer, vim.pesc(title_pattern))
  if not section_line then
    return -- Section not found
  end

  -- Highlight the section title
  add_highlight(buffer, ns_id, "Title", section_line, 2, -1)

  -- Start highlighting commits after the title and separator line
  local commit_start_line = section_line + 2

  for i, commit in ipairs(state.commits) do
    local line_num = commit_start_line + i - 1
    local line = vim.api.nvim_buf_get_lines(buffer, line_num, line_num + 1, false)
    if #line > 0 and line[1] and #line[1] > 2 then
      local line_content = line[1]
      local indicator = vim.fn.strcharpart(line_content, 2, 1)
      local is_current = indicator == "→"

      -- Line format: "  [indicator][hash] - [message] ([author], [date])"
      local hash_start = 4
      local hash_end = hash_start + #commit.hash

      if is_current then
        -- Highlight current commit indicator
        add_highlight(buffer, ns_id, "String", line_num, 2, 2 + 2)
        hash_end = hash_end + 2
      end

      add_highlight(buffer, ns_id, "Directory", line_num, hash_start, hash_end)

      local author_section_start = string.find(line_content, " %(")
      if author_section_start then
        add_highlight(buffer, ns_id, "Comment", line_num, author_section_start, -1)
      end
    end
  end
end

function M.apply_highlighting(
  state,
  config,
  status_messages,
  status_lines_start,
  keybindings_start,
  keybind_data,
  restart_reminder_line
)
  local ns_id = vim.api.nvim_create_namespace("DotfilesUpdater")
  vim.api.nvim_buf_clear_namespace(state.buffer, ns_id, 0, -1)

  highlight_header(state.buffer, ns_id, state)
  highlight_status(state.buffer, ns_id, status_messages, status_lines_start)
  highlight_keybindings(state.buffer, ns_id, keybindings_start, keybind_data)
  highlight_restart_reminder(state.buffer, ns_id, state, restart_reminder_line)
  highlight_remote_commits(state.buffer, ns_id, state, config)
  highlight_plugin_updates(state.buffer, ns_id, state)
  highlight_plugins_ahead(state.buffer, ns_id, state)
  highlight_commit_log(state.buffer, ns_id, state, config)
end

-- Highlighting for release-focused UI
local function highlight_release_header(buffer, ns_id, state)
  -- Line 1: Current Release
  add_highlight(buffer, ns_id, "Title", 1, 2, 19) -- "Current Release:"
  if state.current_release then
    add_highlight(buffer, ns_id, "String", 1, 19, -1) -- Release tag in green
  end

  -- Line 2: Branch
  add_highlight(buffer, ns_id, "Directory", 2, 2, -1)
end

local function highlight_commits_since_release(buffer, ns_id, state)
  if not state.current_release then
    return
  end

  local title_pattern = "Commits since " .. vim.pesc(state.current_release) .. ":"
  local section_line = find_section_line(buffer, title_pattern)

  if not section_line then
    return
  end

  -- Highlight section title
  add_highlight(buffer, ns_id, "Title", section_line, 2, -1)

  -- Start after title and separator
  local commit_start_line = section_line + 2
  local commits_list = state.commits_since_release_list or {}
  local current_hash = state.current_commit or ""

  -- Highlight commits since release (yellow commit SHAs)
  for i, commit in ipairs(commits_list) do
    local line_num = commit_start_line + i - 1
    local line = vim.api.nvim_buf_get_lines(buffer, line_num, line_num + 1, false)
    if #line > 0 and line[1] then
      local line_content = line[1]
      local is_current = line_content:match("^  →")

      -- Find the hash position
      local hash_start = is_current and 4 or 4
      local hash_end = hash_start + #commit.hash

      if is_current then
        -- Highlight current commit indicator in green
        add_highlight(buffer, ns_id, "String", line_num, 2, 4)
        -- Highlight commit hash in yellow with offset for glyph
        add_highlight(buffer, ns_id, "WarningMsg", line_num, hash_start, hash_end + 2)
      else
        -- Highlight commit hash in yellow
        add_highlight(buffer, ns_id, "WarningMsg", line_num, hash_start, hash_end)
      end

    end
  end

  -- Highlight the release commit line (last line before the empty line)
  if state.release_commit then
    local release_line_num = commit_start_line + #commits_list
    local line = vim.api.nvim_buf_get_lines(buffer, release_line_num, release_line_num + 1, false)
    if #line > 0 and line[1] then
      local rc = state.release_commit
      local tag = rc.tag or state.current_release

      -- Format: "    hash - [tag] message"
      -- Hash starts at position 4 (after "    ")
      local hash_start = 4
      local hash_end = hash_start + #rc.hash

      -- Tag starts after "hash - [" = hash_end + 4
      local tag_bracket_start = hash_end + 3  -- " - ["
      local tag_bracket_end = tag_bracket_start + #tag + 2  -- includes []

      -- Highlight hash in yellow
      add_highlight(buffer, ns_id, "WarningMsg", release_line_num, hash_start, hash_end)

      -- Highlight tag in green (including brackets)
      add_highlight(buffer, ns_id, "String", release_line_num, tag_bracket_start, tag_bracket_end)
    end
  end
end

function M.highlight_releases_since(buffer, ns_id, state)
  if not state.current_release then
    return
  end

  local releases_since = state.releases_since_current or {}
  if #releases_since == 0 then
    return
  end

  local title_pattern = "Releases since " .. vim.pesc(state.current_release) .. ":"
  local section_line = find_section_line(buffer, title_pattern)

  if not section_line then
    return
  end

  -- Highlight section title
  add_highlight(buffer, ns_id, "Title", section_line, 2, -1)

  -- Start after title and separator
  local release_start_line = section_line + 2

  -- Highlight each release line
  -- Format: "    hash - [tag] message"
  for i, release in ipairs(releases_since) do
    local line_num = release_start_line + i - 1
    local line = vim.api.nvim_buf_get_lines(buffer, line_num, line_num + 1, false)
    if #line > 0 and line[1] then
      -- Hash starts at position 4 (after "    ")
      local hash_start = 4
      local hash_end = hash_start + #release.hash

      -- Tag starts after "hash - [" = hash_end + 4
      local tag_bracket_start = hash_end + 3  -- " - ["
      local tag_bracket_end = tag_bracket_start + #release.tag + 2  -- includes []

      -- Highlight hash in yellow
      add_highlight(buffer, ns_id, "WarningMsg", line_num, hash_start, hash_end)

      -- Highlight tag in green (including brackets)
      add_highlight(buffer, ns_id, "String", line_num, tag_bracket_start, tag_bracket_end)
    end
  end

  -- Highlight the current release line (with arrow indicator)
  if state.release_commit then
    local current_line_num = release_start_line + #releases_since
    local line = vim.api.nvim_buf_get_lines(buffer, current_line_num, current_line_num + 1, false)
    if #line > 0 and line[1] then
      local rc = state.release_commit

      -- Format: "  → hash - [tag] message (current)"
      -- Arrow indicator
      add_highlight(buffer, ns_id, "String", current_line_num, 2, 4)

      -- Hash starts after "  → " (position 4 + 2 for arrow width)
      local hash_start = 4 + 2
      local hash_end = hash_start + #rc.hash

      -- Tag bracket position
      local tag_bracket_start = hash_end + 3  -- " - ["
      local tag_bracket_end = tag_bracket_start + #state.current_release + 2

      -- Highlight hash in yellow
      add_highlight(buffer, ns_id, "WarningMsg", current_line_num, hash_start, hash_end)

      -- Highlight tag in green
      add_highlight(buffer, ns_id, "String", current_line_num, tag_bracket_start, tag_bracket_end)

      -- Highlight "(current)" at the end
      local current_text = line[1]
      local current_start = current_text:find("%(current%)")
      if current_start then
        add_highlight(buffer, ns_id, "Comment", current_line_num, current_start - 1, -1)
      end
    end
  end
end

function M.highlight_previous_releases(buffer, ns_id, state)
  local releases_before = state.releases_before_current or {}
  if #releases_before == 0 then
    return
  end

  local title_pattern = "Previous releases:"
  local section_line = find_section_line(buffer, vim.pesc(title_pattern))

  if not section_line then
    return
  end

  -- Highlight section title
  add_highlight(buffer, ns_id, "Title", section_line, 2, -1)

  -- Start after title and separator
  local release_start_line = section_line + 2

  -- Highlight each release line
  -- Format: "    hash - [tag] message"
  local max_items = Constants.MAX_SECTION_ITEMS
  local count = math.min(#releases_before, max_items)
  for i = 1, count do
    local release = releases_before[i]
    local line_num = release_start_line + i - 1
    local line = vim.api.nvim_buf_get_lines(buffer, line_num, line_num + 1, false)
    if #line > 0 and line[1] then
      -- Hash starts at position 4 (after "    ")
      local hash_start = 4
      local hash_end = hash_start + #release.hash

      -- Tag starts after "hash - [" = hash_end + 4
      local tag_bracket_start = hash_end + 3  -- " - ["
      local tag_bracket_end = tag_bracket_start + #release.tag + 2  -- includes []

      -- Highlight hash in yellow
      add_highlight(buffer, ns_id, "WarningMsg", line_num, hash_start, hash_end)

      -- Highlight tag in green (including brackets)
      add_highlight(buffer, ns_id, "String", line_num, tag_bracket_start, tag_bracket_end)
    end
  end

  -- Highlight the "... and X more" line if present
  if #releases_before > max_items then
    local more_line_num = release_start_line + count
    add_highlight(buffer, ns_id, "Comment", more_line_num, 4, -1)
  end
end

function M.apply_release_highlighting(
  state,
  config,
  status_messages,
  status_lines_start,
  keybindings_start,
  keybind_data,
  restart_reminder_line
)
  local ns_id = vim.api.nvim_create_namespace("DotfilesUpdater")
  vim.api.nvim_buf_clear_namespace(state.buffer, ns_id, 0, -1)

  highlight_release_header(state.buffer, ns_id, state)
  highlight_status(state.buffer, ns_id, status_messages, status_lines_start)
  highlight_keybindings(state.buffer, ns_id, keybindings_start, keybind_data)
  highlight_restart_reminder(state.buffer, ns_id, state, restart_reminder_line)
  highlight_commits_since_release(state.buffer, ns_id, state)
  M.highlight_releases_since(state.buffer, ns_id, state)
  M.highlight_previous_releases(state.buffer, ns_id, state)
  highlight_plugin_updates(state.buffer, ns_id, state)
  highlight_plugins_ahead(state.buffer, ns_id, state)
end

function M.apply_loading_state_highlighting(state, config)
  local ns_id = vim.api.nvim_create_namespace("DotfilesUpdater")
  vim.api.nvim_buf_clear_namespace(state.buffer, ns_id, 0, -1)
  add_highlight(state.buffer, ns_id, "Directory", 1, 2, -1)
  add_highlight(state.buffer, ns_id, "WarningMsg", 3, 2, -1)

  local is_on_main = state.current_branch == config.main_branch

  -- Keybindings start at line 6 (0-indexed = 5), after "Keybindings:" header
  local keybind_line = 6

  -- Build keybinds list based on branch
  local keybinds = {}
  if is_on_main then
    table.insert(keybinds, config.keymap.update_all)
  end
  table.insert(keybinds, config.keymap.update)
  table.insert(keybinds, config.keymap.install_plugins)
  table.insert(keybinds, config.keymap.refresh)
  table.insert(keybinds, config.keymap.close)

  for i, key in ipairs(keybinds) do
    add_highlight(state.buffer, ns_id, "Statement", keybind_line + i - 1, 4, 4 + #key)
  end
end

function M.get_loading_spinner(state)
  return Constants.SPINNER_FRAMES[state.loading_spinner_frame] or Constants.SPINNER_FRAMES[1]
end

return M
