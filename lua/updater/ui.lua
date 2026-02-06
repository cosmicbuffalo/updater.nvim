local Constants = require("updater.constants")
local Status = require("updater.status")
local ReleaseDetails = require("updater.release_details")
local Git = require("updater.git")
local M = {}

-- Create custom highlight groups
local function setup_highlight_groups()
  -- Italic white text for release titles
  vim.api.nvim_set_hl(0, "UpdaterReleaseTitle", { italic = true })
end

-- Ensure highlight groups are set up
setup_highlight_groups()

-- Generate a separator line that fills the available width
-- Accounts for 2-char left indent ("  ")
local function get_separator_line()
  local width = Status.state.window_width or 80
  -- Subtract indent (2) and small padding (2) for aesthetics
  local separator_width = width - 4
  if separator_width < 10 then
    separator_width = 10
  end
  return string.rep("─", separator_width)
end

-- Helper to build a release line with optional title and prerelease indicator
local function build_release_line(tag, is_expanded)
  local indicator = is_expanded and "▼ " or "▶ "
  local line = "  " .. indicator .. tag

  -- Add GitHub release title if available
  local title = Status.get_release_title(tag)
  if title and title ~= "" and title ~= tag then
    -- Truncate title if too long
    local max_title_len = 40
    if #title > max_title_len then
      title = title:sub(1, max_title_len - 3) .. "..."
    end
    line = line .. " - " .. title
  end

  -- Add prerelease indicator
  if Status.is_prerelease(tag) then
    line = line .. " (prerelease)"
  end

  return line
end

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

  -- First, collect all keybindings that will be shown
  local keybinds = {}

  -- U - Update all: Only show on main branch AND when there are updates available
  if is_on_main and has_any_updates then
    table.insert(keybinds, { key = config.keymap.update_all, desc = "Update dotfiles + install plugin updates" })
  end

  -- u - Update dotfiles: Only show if behind_count > 0
  if state.behind_count > 0 then
    local label = is_on_main and "Update dotfiles" or "Pull latest main into branch"
    table.insert(keybinds, { key = config.keymap.update, desc = label })
  end

  -- i - Install plugins: Show if any plugin differences exist (behind or ahead)
  if has_plugins_behind or has_plugins_ahead then
    local label = has_plugins_ahead and "Update/Downgrade plugins (:Lazy restore)"
      or "Install plugin updates (:Lazy restore)"
    table.insert(keybinds, { key = config.keymap.install_plugins, desc = label })
  end

  -- r - Refresh: Always show
  table.insert(keybinds, { key = config.keymap.refresh, desc = "Refresh status" })

  -- q - Close: Always show
  table.insert(keybinds, { key = config.keymap.close, desc = "Close window" })

  -- Find max key length for alignment
  local max_key_len = 0
  for _, kb in ipairs(keybinds) do
    if #kb.key > max_key_len then
      max_key_len = #kb.key
    end
  end

  -- Build lines with aligned dashes
  local lines = { "  Keybindings:" }
  local keybind_data = {}

  for _, kb in ipairs(keybinds) do
    local padding = string.rep(" ", max_key_len - #kb.key)
    table.insert(lines, "    " .. kb.key .. padding .. " - " .. kb.desc)
    table.insert(keybind_data, { key = kb.key })
  end

  table.insert(lines, "")

  return lines, keybind_data
end

function M.generate_remote_commits_section(state, config)
  local remote_commit_info = {}
  if #state.remote_commits > 0 then
    table.insert(remote_commit_info, "  " .. get_separator_line())
    table.insert(remote_commit_info, "  Commits on origin/" .. config.main_branch .. " not in your branch:")

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
    table.insert(plugin_update_info, "  " .. get_separator_line())
    table.insert(plugin_update_info, "  Plugin updates available:")

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
    table.insert(plugins_ahead_info, "  " .. get_separator_line())
    table.insert(plugins_ahead_info, "  Plugins ahead of lockfile:")

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
    table.insert(restart_info, "  " .. get_separator_line())
    table.insert(restart_info, "  ⚠️  Restart Recommended")

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
    "  " .. get_separator_line(),
    log_title,
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
  elseif state.is_switching_version and state.switching_to_version then
    table.insert(messages, {
      text = "  " .. M.get_loading_spinner(state) .. " Switching to release " .. state.switching_to_version .. "...",
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

  -- Check if we just switched versions
  if state.recently_switched_to then
    -- Determine if this was an upgrade or downgrade
    local action = "Updated"
    if state.switched_from_version then
      local cmp = Git.compare_version_tags(state.switched_from_version, state.recently_switched_to)
      if cmp > 0 then
        action = "Downgraded"
      end
    end
    local prefix = "  " .. action .. " your neovim dotfiles to "
    table.insert(messages, {
      text = prefix .. state.recently_switched_to .. "!",
      hl_group = "String",
      -- Highlight the version in green
      tag_start = #prefix,
      tag_end = #prefix + #state.recently_switched_to,
      tag_hl = "String",
    })
    table.insert(messages, {
      text = "  ⚠️  Don't forget to restart neovim to reload the updates!",
      hl_group = "WarningMsg",
    })
    return messages
  end

  -- Check for new release
  if state.has_new_release and state.latest_remote_release then
    local prefix = "  New release available!: "
    table.insert(messages, {
      text = prefix .. state.latest_remote_release,
      hl_group = "WarningMsg", -- Yellow for the prefix
      -- Special handling: highlight the tag portion in green
      tag_start = #prefix,
      tag_hl = "String",
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
  -- First, collect all keybindings
  local keybinds = {}

  -- q - Close (first)
  table.insert(keybinds, { key = config.keymap.close, desc = "Close window" })

  -- r - Refresh
  table.insert(keybinds, { key = config.keymap.refresh, desc = "Check for new releases" })

  -- Enter - Toggle release details
  table.insert(keybinds, { key = "<CR>", desc = "Toggle release details" })

  -- s - Switch to release
  table.insert(keybinds, { key = "s", desc = "Switch to release" })

  -- y - Copy GitHub URL
  table.insert(keybinds, { key = "y", desc = "Copy URL to clipboard" })

  -- U - Update to latest release (always shown, but may be disabled)
  local u_label = "Update to latest release"
  -- Check if we're ahead of the latest release (on latest tag but with commits after it)
  local is_on_latest_tag = state.current_release == state.latest_remote_release
  local has_commits_after_tag = (state.commits_since_release or 0) > 0
  local is_ahead_of_latest = is_on_latest_tag and has_commits_after_tag

  if is_ahead_of_latest then
    u_label = u_label .. " (disabled, ahead of latest release)"
  elseif not state.has_new_release then
    u_label = u_label .. " (disabled, already on latest release)"
  end
  table.insert(keybinds, { key = config.keymap.update_all, desc = u_label })

  -- Find max key length for alignment
  local max_key_len = 0
  for _, kb in ipairs(keybinds) do
    if #kb.key > max_key_len then
      max_key_len = #kb.key
    end
  end

  -- Build lines with aligned dashes
  local lines = { "  Keybindings:" }
  local keybind_data = {}

  for _, kb in ipairs(keybinds) do
    local padding = string.rep(" ", max_key_len - #kb.key)
    table.insert(lines, "    " .. kb.key .. padding .. " - " .. kb.desc)
    table.insert(keybind_data, { key = kb.key })
  end

  table.insert(lines, "")

  return lines, keybind_data
end

-- Returns: lines table, commit_lines table (maps relative line index to commit hash for navigable lines)
function M.generate_commits_since_release_section(state, config)
  local lines = {}
  local commit_lines = {} -- relative line index -> commit hash

  -- Only show if there are actual commits since the release (not on a tag)
  local commits_list = state.commits_since_release_list or {}
  if #commits_list > 0 and not state.current_tag then
    table.insert(lines, "  " .. get_separator_line())
    table.insert(lines, "  Commits since " .. (state.current_release or "release") .. ":")

    -- Show commits newer than the release (with yellow commit SHAs)
    local current_hash = state.current_commit or ""

    for _, commit in ipairs(commits_list) do
      local indicator = "  "
      if commit.hash == current_hash:sub(1, #commit.hash) then
        indicator = "→ "
      end
      local line = "  " .. indicator .. commit.hash .. " - " .. commit.message
      if commit.author and commit.author ~= "" then
        line = line .. " by " .. commit.author
      end
      table.insert(lines, line)
      commit_lines[#lines] = commit.hash
    end

    table.insert(lines, "  ")
  end

  return lines, commit_lines
end

-- Generate current release section (always shown if we have a current release)
-- Returns: lines table, release_lines table (maps relative line index to tag)
function M.generate_current_release_section(state, config)
  local lines = {}
  local release_lines = {} -- relative line index -> tag

  if state.current_release then
    table.insert(lines, "  " .. get_separator_line())
    table.insert(lines, "  Current release:")

    -- Show current release
    local is_expanded = Status.is_release_expanded(state.current_release)
    local current_line = build_release_line(state.current_release, is_expanded)
    local current_hash = nil
    local current_message = nil
    local current_author = nil
    if state.release_commit then
      local rc = state.release_commit
      current_hash = rc.hash
      current_message = rc.message
      current_author = rc.author
    end
    table.insert(lines, current_line)
    release_lines[#lines] = state.current_release

    -- Add expanded details for current release
    if is_expanded then
      local detail_lines = ReleaseDetails.generate_detail_lines(state.current_release, "      ", current_hash, current_message, current_author)
      for _, detail_line in ipairs(detail_lines) do
        table.insert(lines, detail_line)
      end
    end

    table.insert(lines, "  ")
  end

  return lines, release_lines
end

-- Generate releases since section (only releases newer than current)
-- Returns: lines table, release_lines table (maps relative line index to tag)
function M.generate_releases_since_section(state, config)
  local lines = {}
  local release_lines = {} -- relative line index -> tag
  local releases_since = state.releases_since_current or {}

  -- Only show if there are newer releases
  if state.current_release and #releases_since > 0 then
    table.insert(lines, "  " .. get_separator_line())
    table.insert(lines, "  Releases since " .. state.current_release .. ":")

    -- Show newer releases (newest first)
    for _, release in ipairs(releases_since) do
      local is_expanded = Status.is_release_expanded(release.tag)
      local line = build_release_line(release.tag, is_expanded)
      table.insert(lines, line)
      release_lines[#lines] = release.tag

      -- Add expanded details if this release is expanded
      if is_expanded then
        local detail_lines = ReleaseDetails.generate_detail_lines(release.tag, "      ", release.hash, release.message, release.author)
        for _, detail_line in ipairs(detail_lines) do
          table.insert(lines, detail_line)
        end
      end
    end

    table.insert(lines, "  ")
  end

  return lines, release_lines
end

-- Generate previous releases section with expansion support
-- Returns: lines table, release_lines table (maps relative line index to tag)
function M.generate_previous_releases_section(state, config)
  local lines = {}
  local release_lines = {} -- relative line index -> tag
  local releases_before = state.releases_before_current or {}

  -- Show if there are older releases
  if #releases_before > 0 then
    table.insert(lines, "  " .. get_separator_line())
    table.insert(lines, "  Previous releases:")

    -- Show older releases (already sorted newest first, so closest to current is first)
    local max_items = Constants.MAX_SECTION_ITEMS
    local count = math.min(#releases_before, max_items)
    for i = 1, count do
      local release = releases_before[i]
      local is_expanded = Status.is_release_expanded(release.tag)
      local line = build_release_line(release.tag, is_expanded)
      table.insert(lines, line)
      release_lines[#lines] = release.tag

      -- Add expanded details if this release is expanded
      if is_expanded then
        local detail_lines = ReleaseDetails.generate_detail_lines(release.tag, "      ", release.hash, release.message, release.author)
        for _, detail_line in ipairs(detail_lines) do
          table.insert(lines, detail_line)
        end
      end
    end

    -- Show ellipsis if there are more releases
    if #releases_before > max_items then
      table.insert(lines, "    ... and " .. (#releases_before - max_items) .. " more")
    end

    table.insert(lines, "  ")
  end

  return lines, release_lines
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

  -- During loading, only show close keybind (full keybinds appear after loading)
  table.insert(lines, "    " .. config.keymap.close .. " - Close window")
  table.insert(lines, "")
  table.insert(lines, "  Loading repository information...")
  table.insert(lines, "  This may take a moment.")
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

    if msg.tag_start and msg.tag_hl then
      -- Special case: split highlighting (e.g., "New release available: v1.2.0")
      -- First part in msg.hl_group, tag part in msg.tag_hl
      add_highlight(buffer, ns_id, msg.hl_group, line_num, 2, msg.tag_start)
      add_highlight(buffer, ns_id, msg.tag_hl, line_num, msg.tag_start, -1)
    else
      -- Normal case: single highlight for the whole line
      add_highlight(buffer, ns_id, msg.hl_group, line_num, 2, -1)
    end
  end
end

local function highlight_keybindings(buffer, ns_id, keybindings_start, keybind_data)
  for i, data in ipairs(keybind_data) do
    local line_num = keybindings_start + i - 1
    add_highlight(buffer, ns_id, "Statement", line_num, 4, 4 + #data.key)

    -- Check for "(disabled, ...)" text and highlight it as Comment
    local line = vim.api.nvim_buf_get_lines(buffer, line_num, line_num + 1, false)
    if line and line[1] then
      local disabled_start = line[1]:find("%(disabled,")
      if disabled_start then
        add_highlight(buffer, ns_id, "Comment", line_num, disabled_start - 1, -1)
      end
    end
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

      -- Highlight individual commits after title (separator is above title now)
      local commit_start_line = section_line + 1
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

      -- Highlight plugin names and commits after title (separator is above title now)
      local plugin_start_line = section_line + 1
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

      -- Highlight plugin names and commits after title (separator is above title now)
      -- Format: "plugin-name (lockfile <- installed)"
      local plugin_start_line = section_line + 1
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

  -- Start highlighting commits after the title (separator is above title now)
  local commit_start_line = section_line + 1

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
  -- Line 1: Branch (now the only header line)
  -- Highlight "Branch: " prefix, then highlight the current_tag in FloatTitle if present
  local line = vim.api.nvim_buf_get_lines(buffer, 1, 2, false)
  if #line > 0 and line[1] then
    local line_content = line[1]
    -- Check if current_tag is in the line
    if state.current_tag then
      local tag_start = line_content:find(vim.pesc(state.current_tag), 1, true)
      if tag_start then
        -- Highlight everything before tag in Directory
        add_highlight(buffer, ns_id, "Directory", 1, 2, tag_start - 1)
        -- Highlight the tag in FloatTitle
        add_highlight(buffer, ns_id, "FloatTitle", 1, tag_start - 1, tag_start - 1 + #state.current_tag)
        -- Highlight everything after tag in Directory
        add_highlight(buffer, ns_id, "Directory", 1, tag_start - 1 + #state.current_tag, -1)
      else
        add_highlight(buffer, ns_id, "Directory", 1, 2, -1)
      end
    else
      add_highlight(buffer, ns_id, "Directory", 1, 2, -1)
    end
  else
    add_highlight(buffer, ns_id, "Directory", 1, 2, -1)
  end
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

  -- Highlight section title, with the current release tag in FloatTitle
  local prefix = "  Commits since "
  local tag_start = #prefix
  local tag_end = tag_start + #state.current_release
  add_highlight(buffer, ns_id, "Title", section_line, 2, tag_start)
  add_highlight(buffer, ns_id, "FloatTitle", section_line, tag_start, tag_end)
  add_highlight(buffer, ns_id, "Title", section_line, tag_end, -1)

  -- Start after title (separator is above title now)
  local commit_start_line = section_line + 1
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

      -- Highlight author in Comment if present
      if commit.author and commit.author ~= "" then
        local author_pattern = " by " .. vim.pesc(commit.author)
        local author_start = line_content:find(author_pattern, 1, true)
        if author_start then
          add_highlight(buffer, ns_id, "Comment", line_num, author_start - 1, -1)
        end
      end
    end
  end

end

-- Helper to highlight a release line with fold indicator
-- tag_hl_group: highlight group for the tag (e.g., "String", "FloatTitle"), or nil for default
local function highlight_release_line_with_indicator(buffer, ns_id, line_num, release, tag_hl_group)
  local line = vim.api.nvim_buf_get_lines(buffer, line_num, line_num + 1, false)
  if not line or not line[1] then
    return
  end

  local content = line[1]

  -- Find the fold indicator (▶ or ▼) - these are 3 bytes each in UTF-8
  local indicator_start = content:find("[▶▼]")
  if not indicator_start then
    return
  end

  -- Highlight fold indicator (same color whether folded or unfolded)
  add_highlight(buffer, ns_id, "Comment", line_num, indicator_start - 1, indicator_start + 2)

  -- Find and highlight tag (directly after indicator, before " - " or " (" or end of line)
  -- The indicator is 3 bytes (UTF-8) + 1 space, then the tag starts
  local tag_start = indicator_start + 4 -- After "▶ " (3 bytes + 1 space)

  -- Find where tag ends - could be " - " (title) or " (" (prerelease) or end of line
  local tag_end_dash = content:find(" %- ", tag_start)
  local tag_end_paren = content:find(" %(", tag_start)
  local tag_end = #content + 1

  if tag_end_dash and (not tag_end_paren or tag_end_dash < tag_end_paren) then
    tag_end = tag_end_dash
  elseif tag_end_paren then
    tag_end = tag_end_paren
  end

  -- Only apply tag highlight if a specific group is requested (nil = use buffer default)
  if tag_hl_group then
    add_highlight(buffer, ns_id, tag_hl_group, line_num, tag_start - 1, tag_end - 1)
  end

  -- Highlight title if present (after " - ") - white italic
  if tag_end_dash then
    local title_start = tag_end_dash + 3 -- After " - "
    local title_end = tag_end_paren or #content + 1
    if title_start < title_end then
      add_highlight(buffer, ns_id, "UpdaterReleaseTitle", line_num, title_start - 1, title_end - 1)
    end
  end

  -- Highlight prerelease indicator if present
  local prerelease_start = content:find("%(prerelease%)")
  if prerelease_start then
    add_highlight(buffer, ns_id, "Comment", line_num, prerelease_start - 1, prerelease_start + 11)
  end
end

-- Helper to highlight expanded detail lines
local function highlight_detail_lines(buffer, ns_id, start_line, tag)
  local details = Status.get_release_details(tag)
  if not details then
    return 0
  end

  local line_count = vim.api.nvim_buf_line_count(buffer)
  local lines_highlighted = 0

  for i = start_line, line_count - 1 do
    local line = vim.api.nvim_buf_get_lines(buffer, i, i + 1, false)
    if not line or not line[1] then
      break
    end

    local content = line[1]

    -- Check if this is still a detail line (starts with spaces, has a label:)
    if not content:match("^%s+%S+:") then
      -- Not a detail line anymore, stop
      break
    end

    lines_highlighted = lines_highlighted + 1

    -- Highlight the label (before the colon)
    local label_end = content:find(":")
    if label_end then
      add_highlight(buffer, ns_id, "Comment", i, 0, label_end)

      -- Extract the label to check for special handling
      local label = content:match("^%s*(%S+):")

      -- Special highlighting for specific values
      local value = content:sub(label_end + 1):match("^%s*(.+)")
      if value then
        local value_start = content:find(value, label_end + 1, true)
        if value_start then
          -- Highlight commit hash in yellow (just the hash part, not the message)
          if label == "commit" then
            -- Format is "hash - message by author" or "hash - message" or just "hash"
            local hash_end = value:find(" %-")
            if hash_end then
              -- Highlight just the hash
              add_highlight(buffer, ns_id, "WarningMsg", i, value_start - 1, value_start + hash_end - 2)
              -- Highlight "by author" part in Comment if present
              local by_start = value:find(" by ")
              if by_start then
                add_highlight(buffer, ns_id, "Comment", i, value_start + by_start - 2, -1)
              end
            else
              -- No message, highlight the whole value (but check for "by" still)
              local by_start = value:find(" by ")
              if by_start then
                add_highlight(buffer, ns_id, "WarningMsg", i, value_start - 1, value_start + by_start - 2)
                add_highlight(buffer, ns_id, "Comment", i, value_start + by_start - 2, -1)
              else
                add_highlight(buffer, ns_id, "WarningMsg", i, value_start - 1, -1)
              end
            end
          -- Highlight date: the parenthesized portion (MM-DD-YY) in Comment
          elseif label == "date" then
            local paren_start = value:find("%(")
            if paren_start then
              add_highlight(buffer, ns_id, "Comment", i, value_start + paren_start - 2, -1)
            end
          -- Highlight status values with different colors
          elseif label == "status" then
            if value:match("^release") then
              add_highlight(buffer, ns_id, "String", i, value_start - 1, value_start + 6) -- "release" in green
            elseif value:match("^prerelease") then
              add_highlight(buffer, ns_id, "WarningMsg", i, value_start - 1, value_start + 9) -- "prerelease" in yellow
            else
              -- "tag" or unknown - gray, highlight just "tag" part
              add_highlight(buffer, ns_id, "Comment", i, value_start - 1, value_start + 2) -- "tag" in gray
            end
            -- If there's a parenthetical hint, highlight it in Comment
            local paren_start = value:find("%(")
            if paren_start then
              add_highlight(buffer, ns_id, "Comment", i, value_start + paren_start - 2, -1)
            end
          -- Highlight URLs as links
          elseif value:match("^https?://") then
            add_highlight(buffer, ns_id, "Underlined", i, value_start - 1, -1)
          -- Highlight +X/-Y stats with colors (diff row)
          elseif value:match("^%+%d+/%-") then
            local plus_end = value:find("/")
            if plus_end then
              add_highlight(buffer, ns_id, "DiffAdd", i, value_start - 1, value_start + plus_end - 2)
              local minus_start = value:find("%-", plus_end)
              if minus_start then
                local minus_end = value:find(" ", minus_start) or #value + 1
                add_highlight(buffer, ns_id, "DiffDelete", i, value_start + minus_start - 2, value_start + minus_end - 2)
              end
            end
          -- Highlight "no changes" in Comment for diff/plugins/dependencies
          elseif value == "no changes" then
            add_highlight(buffer, ns_id, "Comment", i, value_start - 1, -1)
          -- Highlight plugins/dependencies with changes in yellow
          elseif (label == "plugins" or label == "dependencies") and value:match("%d+ updated") then
            add_highlight(buffer, ns_id, "WarningMsg", i, value_start - 1, -1)
          end
        end
      end
    end
  end

  return lines_highlighted
end

function M.highlight_current_release(buffer, ns_id, state)
  if not state.current_release then
    return
  end

  local section_line = find_section_line(buffer, "Current release:")
  if not section_line then
    return
  end

  -- Highlight section title
  add_highlight(buffer, ns_id, "Title", section_line, 2, -1)

  -- Start after title (separator is above title now)
  local current_line = section_line + 1

  -- Highlight the current release line with FloatTitle (same as window title)
  local current_release_obj = {
    tag = state.current_release,
    hash = state.release_commit and state.release_commit.hash or nil,
  }
  highlight_release_line_with_indicator(buffer, ns_id, current_line, current_release_obj, "FloatTitle")
  current_line = current_line + 1

  -- If current release is expanded, highlight its details
  if Status.is_release_expanded(state.current_release) then
    highlight_detail_lines(buffer, ns_id, current_line, state.current_release)
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

  -- Highlight section title, with the current release tag in FloatTitle
  local prefix = "  Releases since "
  local tag_start = #prefix
  local tag_end = tag_start + #state.current_release
  add_highlight(buffer, ns_id, "Title", section_line, 2, tag_start)
  add_highlight(buffer, ns_id, "FloatTitle", section_line, tag_start, tag_end)
  add_highlight(buffer, ns_id, "Title", section_line, tag_end, -1)

  -- Start after title (separator is above title now)
  local current_line = section_line + 1

  -- Highlight each release line and its expanded details
  -- First release (index 1) is the latest - highlight in green
  -- First release (latest) in green, others use buffer default
  for i, release in ipairs(releases_since) do
    local tag_hl = (i == 1) and "String" or nil
    highlight_release_line_with_indicator(buffer, ns_id, current_line, release, tag_hl)
    current_line = current_line + 1

    -- If expanded, highlight detail lines
    if Status.is_release_expanded(release.tag) then
      local detail_count = highlight_detail_lines(buffer, ns_id, current_line, release.tag)
      current_line = current_line + detail_count
    end
  end
end

-- Legacy function kept for compatibility but now uses dynamic line detection
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

  -- Start after title (separator is above title now)
  local current_line = section_line + 1

  -- Highlight each release line and its expanded details (buffer default)
  local max_items = Constants.MAX_SECTION_ITEMS
  local count = math.min(#releases_before, max_items)
  for i = 1, count do
    local release = releases_before[i]
    highlight_release_line_with_indicator(buffer, ns_id, current_line, release, nil)
    current_line = current_line + 1

    -- If expanded, highlight detail lines
    if Status.is_release_expanded(release.tag) then
      local detail_count = highlight_detail_lines(buffer, ns_id, current_line, release.tag)
      current_line = current_line + detail_count
    end
  end

  -- Highlight the "... and X more" line if present
  if #releases_before > max_items then
    add_highlight(buffer, ns_id, "Comment", current_line, 4, -1)
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
  M.highlight_current_release(state.buffer, ns_id, state)
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

  -- Only the close keybind is shown during loading (line 6, 0-indexed)
  local keybind_line = 6
  local close_key = config.keymap.close
  add_highlight(state.buffer, ns_id, "Statement", keybind_line, 4, 4 + #close_key)
end

function M.get_loading_spinner(state)
  return Constants.SPINNER_FRAMES[state.loading_spinner_frame] or Constants.SPINNER_FRAMES[1]
end

return M
