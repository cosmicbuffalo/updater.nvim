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
        callback(nil, obj.stderr or "Command failed with exit code " .. obj.code)
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

return M
