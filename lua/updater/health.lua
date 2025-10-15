local Git = require("updater.git")
local Plugins = require("updater.plugins")
local Progress = require("updater.progress")

local M = {}

-- Health check result structure
local function create_health_result(check, status, message)
  return {
    check = check,
    status = status,
    message = message,
  }
end

-- Individual health check functions
local function check_git_repository(config)
  local is_git_repo, git_err = Git.validate_git_repository(config.repo_path)
  return create_health_result(
    "Git Repository",
    is_git_repo and "✓ OK" or "✗ FAIL",
    is_git_repo and ("Valid git repository: " .. config.repo_path) or git_err
  )
end

local function check_git_command()
  local git_ok = vim.fn.executable("git") == 1
  return create_health_result(
    "Git Command",
    git_ok and "✓ OK" or "✗ FAIL",
    git_ok and "git command available" or "git command not found in PATH"
  )
end

local function check_timeout_utility(config)
  local timeout_ok = vim.fn.executable(config.timeout_utility) == 1
  return create_health_result(
    "Timeout Utility",
    timeout_ok and "✓ OK" or "⚠ WARN",
    timeout_ok and (config.timeout_utility .. " command available")
      or (config.timeout_utility .. " not found - operations may hang")
  )
end

local function check_lazy_nvim()
  local lazy_ok = Plugins.is_lazy_available()
  return create_health_result(
    "Lazy.nvim",
    lazy_ok and "✓ OK" or "⚠ INFO",
    lazy_ok and "lazy.nvim available - plugin updates enabled" or "lazy.nvim not found - plugin updates disabled"
  )
end

local function check_fidget_nvim()
  local fidget_ok = Progress.is_fidget_available()
  return create_health_result(
    "Fidget.nvim",
    fidget_ok and "✓ OK" or "⚠ INFO",
    fidget_ok and "fidget.nvim available - progress indicators enabled"
      or "fidget.nvim not found - will use notifications only"
  )
end

local function check_remote_connectivity(config)
  local remote_cmd = "cd " .. vim.fn.shellescape(config.repo_path) .. " && git ls-remote --exit-code origin HEAD"
  local remote_handle = io.popen(remote_cmd .. " 2>/dev/null")
  local remote_ok = false

  if remote_handle then
    local result = remote_handle:read("*a")
    remote_handle:close()
    remote_ok = result and result ~= ""
  end

  return create_health_result(
    "Remote Connectivity",
    remote_ok and "✓ OK" or "⚠ WARN",
    remote_ok and "Can connect to remote repository" or "Cannot connect to remote - check network/credentials"
  )
end

local function check_debug_module(config)
  local debug_status = "not loaded"
  local debug_check_status = "ℹ INFO"

  if Status.state.debug_enabled then
    local ok, debug_module = pcall(require, "updater.debug")
    if ok and debug_module.is_loaded() then
      debug_status = debug_module.get_status()
      debug_check_status = "⚠ DEBUG"
    else
      debug_status = "enabled but module failed to load"
      debug_check_status = "✗ FAIL"
    end
  end

  return create_health_result("Debug Module", debug_check_status, "Debug mode: " .. debug_status)
end

-- Run all health checks and return results
local function run_all_checks(config)
  local checks = {
    check_git_repository(config),
    check_git_command(),
    check_timeout_utility(config),
    check_lazy_nvim(),
    check_fidget_nvim(),
    check_remote_connectivity(config),
    check_debug_module(config),
  }

  return checks
end

-- Display health check results in a buffer
local function display_health_results(health_results)
  local lines = { "# updater.nvim Health Check", "" }

  for _, item in ipairs(health_results) do
    table.insert(lines, string.format("## %s: %s", item.check, item.status))
    table.insert(lines, "   " .. item.message)
    table.insert(lines, "")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  vim.cmd("split")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, "updater-health")
end

-- Main health check function that combines everything
function M.health_check(config)
  local health_results = run_all_checks(config)
  display_health_results(health_results)
end

return M
