local Git = require("updater.git")
local Status = require("updater.status")
local M = {}

-- Map of buffer line numbers to release tags
-- This is rebuilt each time the buffer is rendered
M.line_to_release = {}

-- All release tags in order (for finding previous tags)
M.all_tags = {}

-- Clear the line mapping (called before re-rendering)
function M.clear_line_mapping()
  M.line_to_release = {}
end

-- Register a release line (called during rendering)
function M.register_release_line(line_num, tag)
  M.line_to_release[line_num] = tag
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
function M.toggle_release(config, tag, render_callback)
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
      Git.get_release_details(config, config.repo_path, tag, prev_tag, function(details, _)
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
function M.generate_detail_lines(tag, indent, commit_hash, commit_message)
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

  -- Add detail lines in order: commit, date, url, title, lines, plugins, dependencies
  -- Use commit_hash parameter if provided, otherwise try details.commit
  local hash = commit_hash or details.commit
  local message = commit_message or ""
  -- Combine hash and message on the same line
  local commit_value = hash
  if message and message ~= "" then
    commit_value = hash .. " - " .. message
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
  add_line("url", details.url)
  add_line("title", details.title)

  -- Lines changed
  if details.lines_added > 0 or details.lines_deleted > 0 then
    local lines_str = string.format("+%d/-%d (%d files)",
      details.lines_added, details.lines_deleted, details.lines_changed)
    add_line("lines", lines_str)
  else
    add_line("lines", "no changes")
  end

  -- Plugin changes (always show)
  if details.plugin_changes > 0 then
    add_line("plugins", tostring(details.plugin_changes) .. " updated")
  else
    add_line("plugins", "0 updated")
  end

  -- Mason/dependencies changes (always show)
  if details.mason_changes > 0 then
    add_line("dependencies", tostring(details.mason_changes) .. " updated")
  else
    add_line("dependencies", "0 updated")
  end

  if details.description then
    -- Wrap description if too long
    local max_width = 60
    local desc = details.description
    if #desc > max_width then
      -- Simple word wrap
      local wrapped = {}
      local current_line = ""
      for word in desc:gmatch("%S+") do
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

      -- First line with label
      if #wrapped > 0 then
        local padding = string.rep(" ", label_width - 12) -- "description" length
        table.insert(lines, indent .. "description:" .. padding .. wrapped[1])
        -- Continuation lines
        local cont_indent = indent .. string.rep(" ", label_width)
        for i = 2, #wrapped do
          table.insert(lines, cont_indent .. wrapped[i])
        end
      end
    else
      add_line("description", desc)
    end
  end

  return lines
end

return M
