local Constants = require("updater.constants")
local Errors = require("updater.errors")
local M = {}

local function execute_command(cmd, timeout_key, config)
  timeout_key = timeout_key or "default"
  local timeout = config.timeouts[timeout_key] or config.timeouts.default

  -- Check if timeout utility is available
  if vim.fn.executable(config.timeout_utility) ~= 1 then
    vim.notify(
      string.format("Warning: %s command not found. Running command without timeout (may hang)", config.timeout_utility),
      vim.log.levels.WARN,
      { title = "Updater.nvim" }
    )
    -- Fall back to running command without timeout
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
      return nil, "Failed to execute command"
    end
    local result = handle:read("*a")
    handle:close()
    return result, nil
  end

  local timeout_cmd = string.format(
    "%s %ds bash -c %s || (exit_code=$?; if [ $exit_code -eq %d ]; then echo 'COMMAND_TIMED_OUT'; exit %d; else exit $exit_code; fi)",
    config.timeout_utility,
    timeout,
    vim.fn.shellescape(cmd .. " 2>&1"),
    Constants.TIMEOUT_EXIT_CODE,
    Constants.TIMEOUT_EXIT_CODE
  )

  local handle = io.popen(timeout_cmd)
  if not handle then
    return nil, "Failed to execute command"
  end

  local result = handle:read("*a")
  handle:close()

  if result and result:match("COMMAND_TIMED_OUT") then
    return nil, Errors.timeout_error("Command execution", timeout)
  end

  return result, nil
end

function M.execute_git_command(git_cmd, timeout_key, operation_name, config, repo_path)
  local cd_cmd = "cd " .. vim.fn.shellescape(repo_path) .. " && "
  local full_cmd = cd_cmd .. git_cmd
  local result, err = execute_command(full_cmd, timeout_key, config)

  if err then
    if err:match("timed out") then
      Errors.notify_error(err, config, operation_name or "Git operation")
    end
    return nil, err
  end

  return result and vim.trim(result), nil
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

function M.get_current_commit(config, repo_path)
  local result = M.execute_git_command("git rev-parse HEAD", "status", "Git status check", config, repo_path)
  return result
end

function M.get_current_branch(config, repo_path)
  if not config or not repo_path then
    return "unknown"
  end
  local result, err =
    M.execute_git_command("git rev-parse --abbrev-ref HEAD", "status", "Git branch check", config, repo_path)
  return result or "unknown"
end

function M.get_ahead_behind_count(config, repo_path)
  if not config or not repo_path or not config.main_branch then
    return 0, 0
  end
  local branch = M.get_current_branch(config, repo_path)
  local main = config.main_branch
  local compare_with = "origin/" .. main

  local result, err = M.execute_git_command(
    "git rev-list --left-right --count " .. branch .. "..." .. compare_with,
    "status",
    "Git count operation",
    config,
    repo_path
  )

  if not result then
    return 0, 0
  end

  local ahead, behind = result:match("(%d+)%s+(%d+)")
  return tonumber(ahead) or 0, tonumber(behind) or 0
end

local function is_commit_in_branch(commit_hash, branch, config, repo_path)
  local result, err = M.execute_git_command(
    "git branch --contains " .. commit_hash .. " | grep -q " .. branch .. " && echo yes || echo no",
    "status",
    "Git branch check",
    config,
    repo_path
  )
  return result == "yes"
end

function M.get_commit_log(config, repo_path, current_branch, ahead_count, behind_count)
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

  local result, err = M.execute_git_command(git_cmd, "log", "Git log operation", config, repo_path)
  if not result then
    return {}, log_type
  end

  return parse_commits_from_output(result), log_type
end

function M.get_remote_commits_not_in_local(config, repo_path, current_branch)
  local main = config.main_branch
  local compare_with = "origin/" .. main

  local git_cmd = string.format(
    'git log -n %d --format=format:"%%h|%%s|%%an|%%ar" %s ^%s',
    config.log_count,
    compare_with,
    current_branch
  )

  local result, err = M.execute_git_command(git_cmd, "log", "Git log operation", config, repo_path)
  if not result then
    return {}
  end

  return parse_commits_from_output(result)
end

function M.get_repo_status(config, repo_path)
  local _, fetch_err = M.execute_git_command("git fetch", "fetch", "Git fetch operation", config, repo_path)
  if fetch_err then
    return { error = true }
  end

  local branch = M.get_current_branch(config, repo_path)
  local ahead, behind = M.get_ahead_behind_count(config, repo_path)

  return {
    branch = branch,
    ahead = ahead,
    behind = behind,
    is_main = branch == config.main_branch,
    error = false,
    up_to_date = behind == 0,
    has_local_changes = ahead > 0,
  }
end

function M.are_commits_in_branch(commits, branch, config, repo_path)
  local result = {}
  for _, commit in ipairs(commits) do
    result[commit.hash] = is_commit_in_branch(commit.hash, branch, config, repo_path)
  end
  return result
end

local function fetch_updates(config, repo_path)
  local cd_cmd = "cd " .. vim.fn.shellescape(repo_path) .. " && "
  local _fetch_result, fetch_err = execute_command(cd_cmd .. "git fetch origin " .. config.main_branch, "fetch", config)

  if fetch_err then
    local error_msg
    if fetch_err == "timeout" then
      error_msg = "Git fetch operation timed out"
      vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.timeout.title })
    else
      error_msg = "Failed to fetch updates: " .. (fetch_err or "Unknown error")
      vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.error.title })
    end
    return false, error_msg
  end

  return true, nil
end

local function execute_update_command(config, repo_path, current_branch)
  local cd_cmd = "cd " .. vim.fn.shellescape(repo_path) .. " && "
  local cmd, timeout_key

  if current_branch == config.main_branch then
    cmd = "git pull --rebase --autostash origin " .. config.main_branch
    timeout_key = "pull"
  else
    cmd = "git merge origin/" .. config.main_branch .. " --no-edit"
    timeout_key = "merge"
  end

  local result, err = execute_command(cd_cmd .. cmd, timeout_key, config)
  return result, err, timeout_key
end

local function handle_update_result(config, current_branch, result, err, timeout_key)
  if err then
    local error_msg
    if err == "timeout" then
      error_msg = "Git " .. timeout_key .. " operation timed out"
      vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.timeout.title })
    else
      error_msg = "Failed to update: " .. (result or err or "Unknown error")
      vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.error.title })
    end
    return false, error_msg
  elseif not result or result:match("error") or result:match("Error") or result:match("conflict") then
    local error_msg = "Failed to update: " .. (result or "Unknown error")
    vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.error.title })
    return false, error_msg
  else
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
    return true, success_msg
  end
end

function M.update_repo(config, repo_path, current_branch)
  -- Step 1: Fetch updates
  local fetch_success, fetch_error = fetch_updates(config, repo_path)
  if not fetch_success then
    return false, fetch_error
  end

  -- Step 2: Execute update command
  local result, err, timeout_key = execute_update_command(config, repo_path, current_branch)

  -- Step 3: Handle result
  return handle_update_result(config, current_branch, result, err, timeout_key)
end

function M.validate_git_repository(path)
  if not path then
    return false, "No repository path provided"
  end

  local git_dir = path .. "/.git"
  if vim.fn.isdirectory(git_dir) == 0 and vim.fn.filereadable(git_dir) == 0 then
    return false, "Directory is not a git repository (no .git found): " .. path
  end

  local test_cmd = "cd " .. vim.fn.shellescape(path) .. " && git rev-parse --is-inside-work-tree"
  local handle = io.popen(test_cmd .. " 2>/dev/null")
  if not handle then
    return false, "Failed to validate git repository"
  end

  local result = handle:read("*a")
  handle:close()

  if not result or vim.trim(result) ~= "true" then
    return false, "Directory is not a valid git repository: " .. path
  end

  return true
end

return M
