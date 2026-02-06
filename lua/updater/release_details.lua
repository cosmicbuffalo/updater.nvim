local Git = require("updater.git")
local Status = require("updater.status")
local Health = require("updater.health")
local M = {}

-- Helper to get release title, preferring GitHub API data
local function get_title_for_tag(tag, fallback_details)
  -- Prefer GitHub release title
  local github_title = Status.get_release_title(tag)
  if github_title and github_title ~= "" then
    return github_title
  end
  -- Fall back to git tag title
  return fallback_details and fallback_details.title or nil
end

-- Helper to get release description, preferring GitHub API data
local function get_description_for_tag(tag, fallback_details)
  -- Prefer GitHub release body (release notes)
  local github_body = Status.get_release_body(tag)
  if github_body and github_body ~= "" then
    return github_body
  end
  -- Fall back to git tag description
  return fallback_details and fallback_details.description or nil
end

-- Map of buffer line numbers to release tags
-- This is rebuilt each time the buffer is rendered
M.line_to_release = {}

-- Map of buffer line numbers to commit hashes
-- This is rebuilt each time the buffer is rendered
M.line_to_commit = {}

-- All navigable line numbers (sorted)
M.navigable_lines = {}

-- All release line numbers (sorted, subset of navigable_lines)
M.release_lines = {}

-- All release tags in order (for finding previous tags)
M.all_tags = {}

-- Clear the line mapping (called before re-rendering)
function M.clear_line_mapping()
  M.line_to_release = {}
  M.line_to_commit = {}
  M.navigable_lines = {}
  M.release_lines = {}
end

-- Register a release line (called during rendering)
function M.register_release_line(line_num, tag)
  M.line_to_release[line_num] = tag
  table.insert(M.navigable_lines, line_num)
  table.insert(M.release_lines, line_num)
end

-- Register a commit line (called during rendering)
function M.register_commit_line(line_num, commit_hash)
  M.line_to_commit[line_num] = commit_hash
  table.insert(M.navigable_lines, line_num)
end

-- Register a navigable line (not necessarily a release or commit)
function M.register_navigable_line(line_num)
  table.insert(M.navigable_lines, line_num)
end

-- Get commit hash at a specific line (0-indexed)
function M.get_commit_at_line(line_num)
  return M.line_to_commit[line_num]
end

-- Sort navigable lines (call after all lines registered)
function M.sort_navigable_lines()
  table.sort(M.navigable_lines)
  table.sort(M.release_lines)
end

-- Get the first release line (for initial cursor positioning)
function M.get_first_release_line()
  if #M.release_lines > 0 then
    return M.release_lines[1]
  end
  return nil
end

-- Get the nearest navigable line to a given line
function M.get_nearest_navigable_line(line_num)
  if #M.navigable_lines == 0 then
    return nil
  end

  local best_line = M.navigable_lines[1]
  local best_dist = math.abs(line_num - best_line)

  for _, nav_line in ipairs(M.navigable_lines) do
    local dist = math.abs(line_num - nav_line)
    if dist < best_dist then
      best_dist = dist
      best_line = nav_line
    end
  end

  return best_line
end

-- Get the next navigable line (for j/down movement)
function M.get_next_navigable_line(line_num)
  for _, nav_line in ipairs(M.navigable_lines) do
    if nav_line > line_num then
      return nav_line
    end
  end
  -- Wrap to first or stay at end
  return M.navigable_lines[#M.navigable_lines]
end

-- Get the previous navigable line (for k/up movement)
function M.get_prev_navigable_line(line_num)
  local prev = M.navigable_lines[1]
  for _, nav_line in ipairs(M.navigable_lines) do
    if nav_line >= line_num then
      return prev
    end
    prev = nav_line
  end
  return prev
end

-- Set all tags (for finding previous tags)
function M.set_all_tags(tags)
  M.all_tags = tags or {}
end

-- Get the release tag at a given line number
function M.get_release_at_line(line_num)
  return M.line_to_release[line_num]
end

-- Find the previous tag for a given tag
function M.get_previous_tag(tag)
  local found_current = false
  for _, t in ipairs(M.all_tags) do
    if found_current then
      return t
    end
    if t == tag then
      found_current = true
    end
  end
  return nil
end

-- Toggle expansion and fetch details if needed
function M.toggle_release(tag, render_callback)
  if not tag then
    return
  end

  -- Toggle the expansion state
  Status.toggle_release_expansion(tag)

  -- If now expanded and no cached details, fetch them
  if Status.is_release_expanded(tag) and not Status.get_release_details(tag) then
    if not Status.is_fetching_release_details(tag) then
      Status.set_fetching_release_details(tag, true)

      local prev_tag = M.get_previous_tag(tag)
      Git.get_release_details(tag, prev_tag, function(details, _)
        Status.set_fetching_release_details(tag, false)
        if details then
          Status.set_release_details(tag, details)
        end
        -- Re-render to show the details
        if render_callback then
          render_callback()
        end
      end)
    end
  else
    -- Re-render immediately (collapsing or already have details)
    if render_callback then
      render_callback()
    end
  end
end

-- Generate detail lines for an expanded release
function M.generate_detail_lines(tag, indent, commit_hash, commit_message, commit_author)
  local lines = {}
  indent = indent or "      "

  local details = Status.get_release_details(tag)

  if Status.is_fetching_release_details(tag) then
    table.insert(lines, indent .. "Loading...")
    return lines
  end

  if not details then
    return lines
  end

  -- Calculate label width for alignment
  local label_width = 14 -- "dependencies: " is the longest

  local function add_line(label, value)
    if value and value ~= "" then
      local padding = string.rep(" ", label_width - #label - 1)
      table.insert(lines, indent .. label .. ":" .. padding .. value)
    end
  end

  -- Get title and description from GitHub if available, otherwise from git tag
  local title = get_title_for_tag(tag, details)
  local description = get_description_for_tag(tag, details)

  -- Determine status: prerelease, release, or tag (no GitHub release)
  local github_release = Status.get_github_release(tag)
  local status_value
  if github_release then
    if github_release.prerelease then
      status_value = "prerelease"
    else
      status_value = "release"
    end
  else
    status_value = "tag"
  end

  -- Add detail lines in order: commit, date, status, url, title, lines, plugins, dependencies
  -- Use commit_hash parameter if provided, otherwise try details.commit
  local hash = commit_hash or details.commit
  local message = commit_message or ""
  local author = commit_author or ""
  -- Combine hash, message, and author on the same line
  local commit_value = hash
  if message and message ~= "" then
    commit_value = hash .. " - " .. message
  end
  if author and author ~= "" then
    commit_value = commit_value .. " by " .. author
  end
  add_line("commit", commit_value)

  -- Format date as "X days ago (MM-DD-YY)"
  if details.date then
    local date_value = details.date
    -- Parse YYYY-MM-DD format
    local year, month, day = details.date:match("(%d+)-(%d+)-(%d+)")
    if year and month and day then
      -- Calculate days ago
      local tag_time = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day) })
      local now = os.time()
      local diff_seconds = now - tag_time
      local days_ago = math.floor(diff_seconds / 86400)

      -- Format as MM-DD-YY
      local formatted_date = string.format("%s-%s-%s", month, day, year:sub(-2))

      if days_ago == 0 then
        date_value = "today (" .. formatted_date .. ")"
      elseif days_ago == 1 then
        date_value = "1 day ago (" .. formatted_date .. ")"
      else
        date_value = days_ago .. " days ago (" .. formatted_date .. ")"
      end
    end
    add_line("date", date_value)
  end

  -- Always show status (with hint if no GitHub release data and not authenticated)
  if status_value == "tag" and Health.get_github_api_method() ~= "gh" then
    add_line("status", status_value .. " (authenticate with gh cli to see release metadata)")
  else
    add_line("status", status_value)
  end

  add_line("url", details.url)

  -- Diff stats
  if details.lines_added > 0 or details.lines_deleted > 0 then
    local file_word = details.lines_changed == 1 and "file" or "files"
    local diff_str = string.format("+%d/-%d (%d %s)",
      details.lines_added, details.lines_deleted, details.lines_changed, file_word)
    add_line("diff", diff_str)
  else
    add_line("diff", "no changes")
  end

  -- Plugin changes (always show)
  if details.plugin_changes > 0 then
    add_line("plugins", tostring(details.plugin_changes) .. " updated")
  else
    add_line("plugins", "no changes")
  end

  -- Mason/dependencies changes (always show)
  if details.mason_changes > 0 then
    add_line("dependencies", tostring(details.mason_changes) .. " updated")
  else
    add_line("dependencies", "no changes")
  end

  -- Title directly above description
  -- Skip title if it's the same as the commit message (common for tag-only releases)
  if title and title ~= message then
    add_line("title", title)
  end

  if description then
    -- Clean up description (remove excessive newlines, trim)
    local desc = description:gsub("\r\n", "\n"):gsub("\n\n+", "\n"):gsub("^%s+", ""):gsub("%s+$", "")

    -- Limit to first few lines for display
    local max_lines = 5
    local desc_lines = {}
    local line_count = 0
    for line in desc:gmatch("[^\n]+") do
      line_count = line_count + 1
      if line_count <= max_lines then
        table.insert(desc_lines, line)
      end
    end

    if line_count > max_lines then
      table.insert(desc_lines, "... (" .. (line_count - max_lines) .. " more lines)")
    end

    -- Wrap each line if too long
    local max_width = 60
    local final_lines = {}
    for _, line in ipairs(desc_lines) do
      if #line > max_width then
        -- Simple word wrap
        local wrapped = {}
        local current_line = ""
        for word in line:gmatch("%S+") do
          if #current_line + #word + 1 > max_width then
            if current_line ~= "" then
              table.insert(wrapped, current_line)
            end
            current_line = word
          else
            if current_line ~= "" then
              current_line = current_line .. " " .. word
            else
              current_line = word
            end
          end
        end
        if current_line ~= "" then
          table.insert(wrapped, current_line)
        end
        for _, w in ipairs(wrapped) do
          table.insert(final_lines, w)
        end
      else
        table.insert(final_lines, line)
      end
    end

    -- First line with label
    if #final_lines > 0 then
      local padding = string.rep(" ", label_width - 12) -- "description" length
      table.insert(lines, indent .. "description:" .. padding .. final_lines[1])
      -- Continuation lines
      local cont_indent = indent .. string.rep(" ", label_width)
      for i = 2, #final_lines do
        table.insert(lines, cont_indent .. final_lines[i])
      end
    end
  end

  return lines
end

return M
