local Constants = require("updater.constants")
local Errors = require("updater.errors")
local M = {}

local validation_cache = {}

local function execute_command_async(cmd, timeout_key, config, callback)
  timeout_key = timeout_key or "default"
  local timeout = (config.timeouts[timeout_key] or config.timeouts.default) * 1000 -- Convert to ms

  vim.system({ "bash", "-c", cmd .. " 2>&1" }, {
    text = true,
    timeout = timeout,
  }, function(obj)
    vim.schedule(function()
      if obj.code == Constants.TIMEOUT_EXIT_CODE then
        callback(nil, Errors.timeout_error("Command execution", timeout / 1000))
      elseif obj.code ~= 0 then
        -- stderr is redirected to stdout, so check stdout for error message
        local err_msg = obj.stdout or obj.stderr or "Command failed with exit code " .. obj.code
        callback(nil, vim.trim(err_msg))
      else
        callback(obj.stdout, nil)
      end
    end)
  end)
end

function M.execute_command(git_cmd, timeout_key, operation_name, config, repo_path, callback)
  local cd_cmd = "cd " .. vim.fn.shellescape(repo_path) .. " && "
  local full_cmd = cd_cmd .. git_cmd

  execute_command_async(full_cmd, timeout_key, config, function(result, err)
    if err then
      if err:match("timed out") then
        Errors.notify_error(err, config, operation_name or "Git operation")
      end
      callback(nil, err)
    else
      callback(result and vim.trim(result), nil)
    end
  end)
end

local function parse_commit_line(line)
  local parts = vim.split(line, "|", { plain = true })
  if #parts < 4 then
    return nil
  end

  local hash = vim.trim(parts[1] or "")
  local message = vim.trim(parts[2] or "")
  local author = vim.trim(parts[3] or "")
  local date = vim.trim(parts[4] or "")

  message = message:gsub("\r", ""):gsub("\n.*", "")
  if #message > Constants.MAX_COMMIT_MESSAGE_LENGTH then
    message = message:sub(1, Constants.MAX_COMMIT_MESSAGE_LENGTH - 3) .. "..."
  end

  if hash ~= "" then
    return {
      hash = hash,
      message = message,
      author = author,
      date = date,
    }
  end

  return nil
end

local function parse_commits_from_output(result)
  local commits = {}
  if not result then
    return commits
  end

  for line in result:gmatch("[^\r\n]+") do
    local commit = parse_commit_line(line)
    if commit then
      table.insert(commits, commit)
    end
  end
  return commits
end

function M.get_current_commit(config, repo_path, callback)
  M.execute_command("git rev-parse HEAD", "status", "Git status check", config, repo_path, function(result, err)
    callback(result, err)
  end)
end

local function get_current_branch(config, repo_path, callback)
  if not config or not repo_path then
    callback("unknown", nil)
    return
  end
  M.execute_command(
    "git rev-parse --abbrev-ref HEAD",
    "status",
    "Git branch check",
    config,
    repo_path,
    function(result, err)
      callback(result or "unknown", err)
    end
  )
end

function M.get_ahead_behind_count(config, repo_path, branch, callback)
  if not config or not repo_path or not config.main_branch then
    callback(0, 0, nil)
    return
  end

  local main = config.main_branch
  local compare_with = "origin/" .. main

  M.execute_command(
    "git rev-list --left-right --count " .. branch .. "..." .. compare_with,
    "status",
    "Git count operation",
    config,
    repo_path,
    function(result, err)
      if not result then
        callback(0, 0, err)
        return
      end

      local ahead, behind = result:match("(%d+)%s+(%d+)")
      callback(tonumber(ahead) or 0, tonumber(behind) or 0, nil)
    end
  )
end

local function is_commit_in_branch(commit_hash, branch, config, repo_path, callback)
  M.execute_command(
    "git branch --contains " .. commit_hash .. " | grep -q " .. branch .. " && echo yes || echo no",
    "status",
    "Git branch check",
    config,
    repo_path,
    function(result, err)
      callback(result == "yes", err)
    end
  )
end

function M.get_commit_log(config, repo_path, current_branch, ahead_count, behind_count, callback)
  local main = config.main_branch
  local log_format = string.format('--format=format:"%%h|%%s|%%an|%%ar" -n %d', config.log_count)
  local git_cmd
  local log_type

  if current_branch == main then
    if behind_count > 0 then
      git_cmd = string.format("git log %s origin/%s ^HEAD", log_format, main)
      log_type = "remote"
    else
      git_cmd = string.format("git log %s HEAD", log_format)
      log_type = "local"
    end
  else
    if ahead_count > 0 then
      git_cmd = string.format("git log %s %s ^%s", log_format, current_branch, main)
      log_type = "local"
    else
      git_cmd = string.format("git log %s %s ^%s", log_format, main, current_branch)
      log_type = "remote"
    end
  end

  M.execute_command(git_cmd, "log", "Git log operation", config, repo_path, function(result, err)
    if not result then
      callback({}, log_type, err)
      return
    end

    callback(parse_commits_from_output(result), log_type, nil)
  end)
end

function M.get_remote_commits_not_in_local(config, repo_path, current_branch, callback)
  local main = config.main_branch
  local compare_with = "origin/" .. main

  local git_cmd = string.format(
    'git log -n %d --format=format:"%%h|%%s|%%an|%%ar" %s ^%s',
    config.log_count,
    compare_with,
    current_branch
  )

  M.execute_command(git_cmd, "log", "Git log operation", config, repo_path, function(result, err)
    if not result then
      callback({}, err)
      return
    end

    callback(parse_commits_from_output(result), nil)
  end)
end

function M.get_repo_status(config, repo_path, callback)
  M.execute_command("git fetch", "fetch", "Git fetch operation", config, repo_path, function(_, fetch_err)
    if fetch_err then
      callback({ error = true })
      return
    end

    get_current_branch(config, repo_path, function(branch, _)
      M.get_ahead_behind_count(config, repo_path, branch, function(ahead, behind, _)
        callback({
          branch = branch,
          ahead = ahead,
          behind = behind,
          is_main = branch == config.main_branch,
          error = false,
          up_to_date = behind == 0,
          has_local_changes = ahead > 0,
        })
      end)
    end)
  end)
end

local function has_uncommitted_changes(config, repo_path, callback)
  M.execute_command("git status --porcelain", "status", "Git status", config, repo_path, function(result, err)
    if err then
      callback(nil, err)
    else
      -- If output is non-empty, there are uncommitted changes
      local has_changes = result and #vim.trim(result) > 0
      callback(has_changes, nil)
    end
  end)
end

function M.rollback_to_commit(config, repo_path, commit_hash, callback)
  local rollback_cmd = "git merge --abort 2>/dev/null || true; git rebase --abort 2>/dev/null || true; git reset --hard "
    .. commit_hash
  M.execute_command(rollback_cmd, "default", "Rollback", config, repo_path, function(_, err)
    if err then
      callback(false, "Failed to rollback: " .. err)
    else
      callback(true, nil)
    end
  end)
end

function M.are_commits_in_branch(commits, branch, config, repo_path, callback)
  local result = {}
  local remaining = #commits

  if remaining == 0 then
    callback(result)
    return
  end

  for _, commit in ipairs(commits) do
    is_commit_in_branch(commit.hash, branch, config, repo_path, function(is_in_branch, _)
      result[commit.hash] = is_in_branch
      remaining = remaining - 1
      if remaining == 0 then
        callback(result)
      end
    end)
  end
end

local function fetch_updates_async(config, repo_path, callback)
  local cd_cmd = "cd " .. vim.fn.shellescape(repo_path) .. " && "

  execute_command_async(cd_cmd .. "git fetch origin " .. config.main_branch, "fetch", config, function(_, fetch_err)
    if fetch_err then
      local error_msg
      if fetch_err:match("timed out") then
        error_msg = "Git fetch operation timed out"
        vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.timeout.title })
      else
        error_msg = "Failed to fetch updates: " .. (fetch_err or "Unknown error")
        vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.error.title })
      end
      callback(false, error_msg)
      return
    end

    callback(true, nil)
  end)
end

-- Execute update command (pull or merge)
-- For non-main branches, uses git stash to handle uncommitted changes
local function execute_update_command(config, repo_path, current_branch, has_uncommitted, callback)
  local cd_cmd = "cd " .. vim.fn.shellescape(repo_path) .. " && "
  local cmd, timeout_key

  if current_branch == config.main_branch then
    local pull_flags = {}

    if config.git and config.git.rebase then
      table.insert(pull_flags, "--rebase")
    end

    if config.git and config.git.autostash then
      table.insert(pull_flags, "--autostash")
    end

    local flags_str = #pull_flags > 0 and (" " .. table.concat(pull_flags, " ")) or ""
    cmd = "git pull" .. flags_str .. " origin " .. config.main_branch
    timeout_key = "pull"
  else
    -- For non-main branches, stash changes before merge, then pop after
    if has_uncommitted then
      cmd = "git stash push -m 'updater-auto-stash' && "
        .. "git merge origin/"
        .. config.main_branch
        .. " --no-edit && "
        .. "git stash pop"
    else
      cmd = "git merge origin/" .. config.main_branch .. " --no-edit"
    end
    timeout_key = "merge"
  end

  execute_command_async(cd_cmd .. cmd, timeout_key, config, function(result, err)
    callback(result, err, timeout_key)
  end)
end

-- Check if result indicates a merge/rebase conflict or failure that needs rollback
local function needs_rollback(result, err)
  if err then
    return true
  end
  if not result then
    return true
  end
  -- Check for common conflict/failure patterns
  local failure_patterns = {
    "CONFLICT",
    "Automatic merge failed",
    "merge failed",
    "could not apply",
    "error:",
    "fatal:",
    "Cannot merge",
    "Merge conflict",
    "rebase failed",
  }
  for _, pattern in ipairs(failure_patterns) do
    if result:match(pattern) then
      return true
    end
  end
  return false
end

-- Handle update result and notify user
-- Returns: success, message, needs_rollback
local function handle_update_result(config, current_branch, result, err, timeout_key)
  if err then
    local error_msg
    local rollback_needed = true
    if err:match("timed out") then
      error_msg = "Git " .. timeout_key .. " operation timed out"
      vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.timeout.title })
    else
      error_msg = "Failed to update: " .. (err or "Unknown error")
      vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.error.title })
    end
    return false, error_msg, rollback_needed
  end

  -- Check for conflict or failure patterns in result
  if needs_rollback(result, nil) then
    local error_msg = "Merge conflict or error detected. Rolling back to previous state."
    if result and result:match("CONFLICT") then
      error_msg = "Merge conflict detected. Your branch has been restored to its previous state."
    end
    vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.error.title })
    return false, error_msg, true
  end

  local success_msg
  if result:match("Already up to date") then
    success_msg = "Already up to date with origin/" .. config.main_branch
  else
    if current_branch == config.main_branch then
      success_msg = "Successfully pulled changes from origin/" .. config.main_branch
    else
      success_msg = "Successfully merged origin/" .. config.main_branch .. " into " .. current_branch
    end
  end
  vim.notify(success_msg, vim.log.levels.INFO, { title = config.notify.updated.title })
  return true, success_msg, false
end

-- Update repo (fetch + pull/merge with rollback on failure)
function M.update_repo(config, repo_path, callback)
  -- Get current branch first
  get_current_branch(config, repo_path, function(current_branch, branch_err)
    if branch_err or not current_branch or current_branch == "unknown" then
      callback(false, "Failed to get current branch: " .. (branch_err or "Unknown error"))
      return
    end

    -- Step 1: Save current HEAD for potential rollback
    M.get_current_commit(config, repo_path, function(saved_head, head_err)
      if head_err or not saved_head then
        callback(false, "Failed to save current state: " .. (head_err or "Unknown error"))
        return
      end

      -- Step 2: Check for uncommitted changes
      has_uncommitted_changes(config, repo_path, function(has_uncommitted, status_err)
        if status_err then
          callback(false, "Failed to check working directory status: " .. status_err)
          return
        end

        -- Step 3: Fetch updates
        fetch_updates_async(config, repo_path, function(fetch_success, fetch_error)
          if not fetch_success then
            callback(false, fetch_error)
            return
          end

          -- Step 4: Execute update command
          execute_update_command(config, repo_path, current_branch, has_uncommitted, function(result, err, timeout_key)
            -- Step 5: Handle result
            local success, message, rollback_needed =
              handle_update_result(config, current_branch, result, err, timeout_key)

            -- Step 6: Rollback if needed
            if rollback_needed then
              M.rollback_to_commit(config, repo_path, saved_head, function(rollback_success, rollback_err)
                if not rollback_success then
                  local full_error = message .. " Rollback also failed: " .. (rollback_err or "Unknown error")
                  vim.notify(full_error, vim.log.levels.ERROR, { title = config.notify.error.title })
                  callback(false, full_error)
                else
                  vim.notify(
                    "Operation failed but your branch has been restored to its previous state.",
                    vim.log.levels.WARN,
                    { title = config.notify.error.title }
                  )
                  callback(false, message)
                end
              end)
            else
              callback(success, message)
            end
          end)
        end)
      end)
    end)
  end)
end

function M.validate_git_repository(path, callback)
  if not path then
    callback(false, "No repository path provided")
    return
  end

  if validation_cache[path] ~= nil then
    callback(validation_cache[path], validation_cache[path] == false and "Cached: invalid git repository" or nil)
    return
  end

  -- Quick check: does .git exist?
  local git_dir = path .. "/.git"
  if vim.fn.isdirectory(git_dir) == 0 and vim.fn.filereadable(git_dir) == 0 then
    validation_cache[path] = false
    callback(false, "Directory is not a git repository (no .git found): " .. path)
    return
  end

  -- Full validation async
  local test_cmd = "cd " .. vim.fn.shellescape(path) .. " && git rev-parse --is-inside-work-tree"
  vim.system({ "bash", "-c", test_cmd }, { text = true, timeout = 5000 }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 or not obj.stdout or vim.trim(obj.stdout) ~= "true" then
        validation_cache[path] = false
        callback(false, "Directory is not a valid git repository: " .. path)
      else
        validation_cache[path] = true
        callback(true, nil)
      end
    end)
  end)
end

-- Clear validation cache (useful for testing or after repo changes)
function M.clear_validation_cache()
  validation_cache = {}
end

-- Get validation status for a path (returns: nil if not checked, true if valid, false if invalid)
function M.get_validation_status(path)
  return validation_cache[path]
end

-- Get list of version tags sorted by semantic version (newest first)
function M.get_version_tags(config, repo_path, callback)
  local pattern = config.version_tag_pattern or "v*"
  -- Fetch tags first, then list them sorted by version
  M.execute_command(
    "git fetch --tags --quiet && git tag -l " .. vim.fn.shellescape(pattern) .. " --sort=-version:refname",
    "status",
    "Git tag list",
    config,
    repo_path,
    function(result, err)
      if err then
        callback({}, err)
        return
      end

      local tags = {}
      if result then
        for line in result:gmatch("[^\r\n]+") do
          local tag = vim.trim(line)
          if tag ~= "" then
            table.insert(tags, tag)
          end
        end
      end
      callback(tags, nil)
    end
  )
end

-- Check if HEAD is on a tag, returns tag name or nil
function M.get_head_tag(config, repo_path, callback)
  M.execute_command(
    "git describe --tags --exact-match HEAD 2>/dev/null || echo ''",
    "status",
    "Git tag check",
    config,
    repo_path,
    function(result, err)
      if err then
        callback(nil, err)
        return
      end

      local tag = result and vim.trim(result) or ""
      if tag == "" then
        callback(nil, nil)
      else
        callback(tag, nil)
      end
    end
  )
end

-- Checkout a specific tag (creates detached HEAD)
function M.checkout_tag(config, repo_path, tag_name, callback)
  -- First, discard any lockfile changes that might block checkout
  -- Then checkout the tag in a single command chain
  local discard_lockfiles = "git checkout -- lazy-lock.json mason-lock.json 2>/dev/null || true"
  local checkout_tag = "git checkout " .. vim.fn.shellescape(tag_name)
  local combined_cmd = discard_lockfiles .. " && " .. checkout_tag

  M.execute_command(
    combined_cmd,
    "default",
    "Git checkout tag",
    config,
    repo_path,
    function(result, err)
      if err then
        callback(false, "Failed to checkout tag: " .. (err or "unknown error"))
      else
        callback(true, nil)
      end
    end
  )
end

-- Expose uncommitted changes check (already exists as local, make it public)
-- Check if a file path is a lockfile that can be auto-discarded
local function is_lockfile(filepath)
  return filepath:match("lazy%-lock%.json$") or filepath:match("mason%-lock%.json$")
end

-- Parse git status porcelain output into list of changed files
local function parse_status_files(status_output)
  local files = {}
  if not status_output or status_output == "" then
    return files
  end

  for line in status_output:gmatch("[^\n]+") do
    -- Porcelain format: XY filename (where XY is 2-char status)
    local filepath = line:match("^.. (.+)$")
    if filepath then
      -- Handle renamed files (old -> new format)
      local renamed = filepath:match("^.+ %-> (.+)$")
      if renamed then
        filepath = renamed
      end
      table.insert(files, filepath)
    end
  end
  return files
end

function M.has_uncommitted_changes(config, repo_path, callback)
  M.execute_command("git status --porcelain", "status", "Git status", config, repo_path, function(result, err)
    if err then
      callback(nil, err)
      return
    end

    local trimmed = result and vim.trim(result) or ""
    if trimmed == "" then
      -- No changes at all
      callback(false, nil)
      return
    end

    -- Parse the changed files
    local changed_files = parse_status_files(trimmed)

    -- Check if ALL changed files are lockfiles
    local non_lockfile_changes = {}
    local lockfile_changes = {}

    for _, filepath in ipairs(changed_files) do
      if is_lockfile(filepath) then
        table.insert(lockfile_changes, filepath)
      else
        table.insert(non_lockfile_changes, filepath)
      end
    end

    if #non_lockfile_changes > 0 then
      -- There are non-lockfile changes, block the update
      callback(true, nil)
    elseif #lockfile_changes > 0 then
      -- Only lockfile changes - discard them and proceed
      local checkout_cmd = "git checkout --"
      for _, filepath in ipairs(lockfile_changes) do
        checkout_cmd = checkout_cmd .. " " .. vim.fn.shellescape(filepath)
      end

      M.execute_command(checkout_cmd, "checkout", "Discard lockfile changes", config, repo_path, function(_, checkout_err)
        if checkout_err then
          -- Failed to discard, treat as having changes
          callback(true, nil)
        else
          -- Successfully discarded lockfile changes
          callback(false, nil)
        end
      end)
    else
      -- No changes (shouldn't reach here, but handle it)
      callback(false, nil)
    end
  end)
end

-- Get the latest release tag that is an ancestor of the given ref (or HEAD)
-- This finds the most recent version tag reachable from the current commit
function M.get_latest_release_for_ref(config, repo_path, ref, callback)
  ref = ref or "HEAD"
  local pattern = config.version_tag_pattern or "v*"
  M.execute_command(
    "git describe --tags --abbrev=0 --match " .. vim.fn.shellescape(pattern) .. " " .. ref .. " 2>/dev/null || echo ''",
    "status",
    "Git release check",
    config,
    repo_path,
    function(result, err)
      if err then
        callback(nil, err)
        return
      end

      local tag = result and vim.trim(result) or ""
      if tag == "" then
        callback(nil, nil)
      else
        callback(tag, nil)
      end
    end
  )
end

-- Get the latest release tag on the remote main branch
function M.get_latest_remote_release(config, repo_path, callback)
  local main = config.main_branch or "main"
  M.get_latest_release_for_ref(config, repo_path, "origin/" .. main, callback)
end

-- Count commits between a tag and HEAD (commits since release)
function M.get_commits_since_tag(config, repo_path, tag, callback)
  if not tag then
    callback(0, nil)
    return
  end

  M.execute_command(
    "git rev-list " .. vim.fn.shellescape(tag) .. "..HEAD --count",
    "status",
    "Git commit count",
    config,
    repo_path,
    function(result, err)
      if err then
        callback(0, err)
        return
      end

      local count = tonumber(vim.trim(result or "0")) or 0
      callback(count, nil)
    end
  )
end

-- Compare two version tags to see if remote is newer
-- Returns: 1 if tag1 > tag2, -1 if tag1 < tag2, 0 if equal
function M.compare_version_tags(tag1, tag2)
  if not tag1 and not tag2 then
    return 0
  end
  if not tag1 then
    return -1
  end
  if not tag2 then
    return 1
  end

  -- Extract version numbers from tags like "v1.2.3" or "v1.2.3-pre"
  local function parse_version(tag)
    -- Match version with optional prerelease suffix
    local major, minor, patch, prerelease = tag:match("v?(%d+)%.?(%d*)%.?(%d*)%-?(.*)")
    return {
      tonumber(major) or 0,
      tonumber(minor) or 0,
      tonumber(patch) or 0,
      prerelease or "",
    }
  end

  local v1 = parse_version(tag1)
  local v2 = parse_version(tag2)

  -- Compare major, minor, patch
  for i = 1, 3 do
    if v1[i] > v2[i] then
      return 1
    elseif v1[i] < v2[i] then
      return -1
    end
  end

  -- If versions are equal, compare prerelease (no prerelease > prerelease)
  -- e.g., v1.0.0 > v1.0.0-pre, v1.0.0-pre2 > v1.0.0-pre1
  local pre1 = v1[4]
  local pre2 = v2[4]

  if pre1 == "" and pre2 ~= "" then
    return 1 -- No prerelease > prerelease
  elseif pre1 ~= "" and pre2 == "" then
    return -1 -- Prerelease < no prerelease
  elseif pre1 ~= pre2 then
    -- Simple string comparison for prerelease (works for pre1/pre2/etc)
    if pre1 > pre2 then
      return 1
    elseif pre1 < pre2 then
      return -1
    end
  end

  return 0
end

-- Get the list of commits since a tag (for display)
function M.get_commits_since_tag_list(config, repo_path, tag, callback)
  if not tag then
    callback({}, nil)
    return
  end

  local log_format = '--format=format:"%h|%s|%an|%ar"'
  M.execute_command(
    "git log " .. log_format .. " " .. vim.fn.shellescape(tag) .. "..HEAD",
    "log",
    "Git commits since tag",
    config,
    repo_path,
    function(result, err)
      if err then
        callback({}, err)
        return
      end

      local commits = {}
      if result then
        for line in result:gmatch("[^\r\n]+") do
          local parts = vim.split(line, "|", { plain = true })
          if #parts >= 4 then
            table.insert(commits, {
              hash = vim.trim(parts[1] or ""),
              message = vim.trim(parts[2] or ""),
              author = vim.trim(parts[3] or ""),
              date = vim.trim(parts[4] or ""),
            })
          end
        end
      end
      callback(commits, nil)
    end
  )
end

-- Get the commit info for a specific tag
function M.get_tag_commit_info(config, repo_path, tag, callback)
  if not tag then
    callback(nil, nil)
    return
  end

  local log_format = '--format=format:"%h|%s|%an|%ar"'
  M.execute_command(
    "git log " .. log_format .. " -1 " .. vim.fn.shellescape(tag),
    "log",
    "Git tag commit",
    config,
    repo_path,
    function(result, err)
      if err then
        callback(nil, err)
        return
      end

      if result then
        local parts = vim.split(result, "|", { plain = true })
        if #parts >= 4 then
          callback({
            hash = vim.trim(parts[1] or ""),
            message = vim.trim(parts[2] or ""),
            author = vim.trim(parts[3] or ""),
            date = vim.trim(parts[4] or ""),
            tag = tag,
          }, nil)
          return
        end
      end
      callback(nil, nil)
    end
  )
end

-- Get releases (tags) between current tag and latest tag
-- Returns tags newer than current_tag, sorted newest first
function M.get_releases_since_tag(config, repo_path, current_tag, all_tags, callback)
  if not current_tag or not all_tags or #all_tags == 0 then
    callback({}, nil)
    return
  end

  -- all_tags is sorted newest first, so we collect tags until we hit current_tag
  local releases_since = {}
  for _, tag in ipairs(all_tags) do
    if tag == current_tag then
      break
    end
    table.insert(releases_since, tag)
  end

  -- Get commit info for each release
  local results = {}
  local remaining = #releases_since

  if remaining == 0 then
    callback({}, nil)
    return
  end

  for i, tag in ipairs(releases_since) do
    M.get_tag_commit_info(config, repo_path, tag, function(commit_info, _)
      results[i] = commit_info or { tag = tag, hash = "", message = "", author = "", date = "" }
      remaining = remaining - 1
      if remaining == 0 then
        -- Filter out nil entries and return in order
        local final = {}
        for j = 1, #releases_since do
          if results[j] then
            table.insert(final, results[j])
          end
        end
        callback(final, nil)
      end
    end)
  end
end

-- Get releases before (older than) a given tag
-- Returns tags sorted newest first (closest to current first)
function M.get_releases_before_tag(config, repo_path, current_tag, all_tags, max_count, callback)
  if not current_tag or not all_tags or #all_tags == 0 then
    callback({}, nil)
    return
  end

  -- all_tags is sorted newest first, so we collect tags after we hit current_tag
  local releases_before = {}
  local found_current = false
  for _, tag in ipairs(all_tags) do
    if found_current then
      table.insert(releases_before, tag)
      if max_count and #releases_before >= max_count then
        break
      end
    elseif tag == current_tag then
      found_current = true
    end
  end

  -- Get commit info for each release
  local results = {}
  local remaining = #releases_before

  if remaining == 0 then
    callback({}, nil)
    return
  end

  for i, tag in ipairs(releases_before) do
    M.get_tag_commit_info(config, repo_path, tag, function(commit_info, _)
      results[i] = commit_info or { tag = tag, hash = "", message = "", author = "", date = "" }
      remaining = remaining - 1
      if remaining == 0 then
        -- Filter out nil entries and return in order
        local final = {}
        for j = 1, #releases_before do
          if results[j] then
            table.insert(final, results[j])
          end
        end
        callback(final, nil)
      end
    end)
  end
end

-- Check if we're on a detached HEAD
function M.is_detached_head(config, repo_path, callback)
  M.execute_command(
    "git symbolic-ref -q HEAD >/dev/null 2>&1 && echo 'attached' || echo 'detached'",
    "status",
    "Git HEAD check",
    config,
    repo_path,
    function(result, err)
      if err then
        callback(false, err)
        return
      end
      callback(vim.trim(result or "") == "detached", nil)
    end
  )
end

-- Get the previous tag before a given tag (for diff comparison)
function M.get_previous_tag(config, repo_path, tag, all_tags, callback)
  if not tag or not all_tags then
    callback(nil, nil)
    return
  end

  local found_current = false
  for _, t in ipairs(all_tags) do
    if found_current then
      callback(t, nil)
      return
    end
    if t == tag then
      found_current = true
    end
  end
  callback(nil, nil) -- No previous tag found
end

-- Get release details for a tag
function M.get_release_details(config, repo_path, tag, prev_tag, callback)
  if not tag then
    callback(nil, "No tag provided")
    return
  end

  -- Get Status for remote_url
  local Status = require("updater.status")

  -- Build release URL from remote_url if available
  local release_url = nil
  if Status.state.remote_url then
    release_url = Status.state.remote_url .. "/releases/tag/" .. tag
  end

  local details = {
    tag = tag,
    commit = nil,
    date = nil,
    url = release_url,
    title = nil,
    description = nil,
    lines_added = 0,
    lines_deleted = 0,
    lines_changed = 0,
    plugin_changes = 0,
    mason_changes = 0,
  }

  local pending = 5 -- Number of async operations
  local function check_done()
    pending = pending - 1
    if pending == 0 then
      callback(details, nil)
    end
  end

  -- 1. Get tag commit hash
  M.execute_command(
    "git rev-list -n 1 " .. vim.fn.shellescape(tag),
    "log",
    "Git tag commit",
    config,
    repo_path,
    function(result, _)
      if result then
        details.commit = vim.trim(result):sub(1, 7) -- Short hash
      end
      check_done()
    end
  )

  -- 2. Get tag date
  M.execute_command(
    "git log -1 --format=%ai " .. vim.fn.shellescape(tag),
    "log",
    "Git tag date",
    config,
    repo_path,
    function(result, _)
      if result then
        details.date = vim.trim(result):sub(1, 10) -- Just the date part YYYY-MM-DD
      end
      check_done()
    end
  )

  -- 3. Get tag message (title and description)
  M.execute_command(
    "git tag -l --format='%(contents:subject)|%(contents:body)' " .. vim.fn.shellescape(tag),
    "tag",
    "Git tag message",
    config,
    repo_path,
    function(result, _)
      if result then
        local parts = vim.split(result, "|", { plain = true })
        details.title = vim.trim(parts[1] or "")
        details.description = vim.trim(parts[2] or "")
        -- Clean up empty values
        if details.title == "" then
          details.title = nil
        end
        if details.description == "" then
          details.description = nil
        end
      end
      check_done()
    end
  )

  -- 4. Get diff stats
  -- If prev_tag exists, compare between tags; otherwise show stats for the tag's commit
  local diff_cmd
  if prev_tag then
    diff_cmd = "git diff --shortstat " .. vim.fn.shellescape(prev_tag) .. ".." .. vim.fn.shellescape(tag)
  else
    -- For the first tag, show the commit's own stats
    diff_cmd = "git show --shortstat --format='' " .. vim.fn.shellescape(tag)
  end

  M.execute_command(
    diff_cmd,
    "diff",
    "Git diff stats",
    config,
    repo_path,
    function(result, _)
      if result then
        -- Parse "X files changed, Y insertions(+), Z deletions(-)"
        local added = result:match("(%d+) insertion")
        local deleted = result:match("(%d+) deletion")
        local changed = result:match("(%d+) file")
        details.lines_added = tonumber(added) or 0
        details.lines_deleted = tonumber(deleted) or 0
        details.lines_changed = tonumber(changed) or 0
      end
      check_done()
    end
  )

  -- 5. Get plugin and mason lock changes
  -- If prev_tag exists, compare between tags; otherwise show stats for the tag's commit
  local numstat_cmd
  if prev_tag then
    numstat_cmd = "git diff --numstat " .. vim.fn.shellescape(prev_tag) .. ".." .. vim.fn.shellescape(tag)
  else
    -- For the first tag, show the commit's own file stats
    numstat_cmd = "git show --numstat --format='' " .. vim.fn.shellescape(tag)
  end

  M.execute_command(
    numstat_cmd,
    "diff",
    "Git lockfile changes",
    config,
    repo_path,
    function(result, _)
      if result then
        for line in result:gmatch("[^\n]+") do
          local added, deleted, file = line:match("(%d+)%s+(%d+)%s+(.+)")
          if file then
            local changes = (tonumber(added) or 0) + (tonumber(deleted) or 0)
            -- Check if this is a lazy lockfile (could be at any path)
            if file:match("lazy%-lock%.json$") then
              -- Each plugin change typically has 2 lines (old and new commit)
              details.plugin_changes = math.floor(changes / 2)
            -- Check if this is a mason lockfile
            elseif file:match("mason%-lock%.json$") then
              details.mason_changes = math.floor(changes / 2)
            end
          end
        end
      end
      check_done()
    end
  )

  -- Construct GitHub URL
  M.get_remote_url(config, repo_path, function(remote_url, _)
    if remote_url then
      -- Convert git URL to HTTPS URL for releases
      local https_url = remote_url
        :gsub("git@github%.com:", "https://github.com/")
        :gsub("%.git$", "")
      details.url = https_url .. "/releases/tag/" .. tag
    end
  end)
end

-- Get remote URL for the repo
function M.get_remote_url(config, repo_path, callback)
  M.execute_command(
    "git remote get-url origin",
    "remote",
    "Git remote URL",
    config,
    repo_path,
    function(result, err)
      if err then
        callback(nil, err)
        return
      end
      callback(vim.trim(result or ""), nil)
    end
  )
end

return M
