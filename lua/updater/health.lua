local M = {}

local health = vim.health

function M.check()
  health.start("updater.nvim")

  if vim.fn.executable("git") == 1 then
    health.ok("git command available")
  else
    health.error("git command not found in PATH", { "Install git and ensure it's in your PATH" })
  end

  local timeout_utility = "timeout"
  if vim.fn.executable(timeout_utility) == 1 then
    health.ok(timeout_utility .. " command available")
  else
    health.warn(timeout_utility .. " command not found", {
      "Git operations may hang without timeout protection",
      "Install coreutils or equivalent to get the timeout command",
    })
  end

  local nvim_version = vim.version()
  if nvim_version.major > 0 or (nvim_version.major == 0 and nvim_version.minor >= 10) then
    health.ok("Neovim version " .. tostring(nvim_version) .. " (0.10+ required for async operations)")
  else
    health.error("Neovim version " .. tostring(nvim_version) .. " is too old", {
      "updater.nvim requires Neovim 0.10 or later for vim.system() support",
      "Please upgrade Neovim",
    })
  end

  local ok, updater = pcall(require, "updater")
  if not ok then
    health.error("Failed to load updater module")
    return
  end

  local status_ok, Status = pcall(require, "updater.status")
  if not status_ok then
    health.error("Failed to load updater.status module")
    return
  end

  local plugins_ok, Plugins = pcall(require, "updater.plugins")
  if plugins_ok and Plugins.is_lazy_available() then
    health.ok("lazy.nvim detected - plugin update tracking enabled")
  else
    health.info("lazy.nvim not detected - plugin update tracking disabled")
  end

  local progress_ok, Progress = pcall(require, "updater.progress")
  if progress_ok and Progress.is_fidget_available() then
    health.ok("fidget.nvim detected - progress indicators enabled")
  else
    health.info("fidget.nvim not detected - using notifications only")
  end

  if Status.state.debug_enabled then
    health.warn("Debug mode is enabled", {
      "Debug mode simulates updates and may not reflect real repository state",
      "Run :UpdaterDebugToggle to disable",
    })
  else
    health.ok("Debug mode disabled")
  end

  local git_ok, Git = pcall(require, "updater.git")
  local cfg = updater.get_config()

  if git_ok and cfg and cfg.repo_path then
    local validation_status = Git.get_validation_status(cfg.repo_path)
    if validation_status == true then
      health.ok("Repository validated: " .. cfg.repo_path)
    elseif validation_status == false then
      health.error("Repository validation failed: " .. cfg.repo_path, {
        "Check that the path exists and is a valid git repository",
        "Run :UpdaterCheck to see the full error",
      })
    else
      health.info("Repository not yet validated (validated lazily on first use): " .. cfg.repo_path)
      health.info("Run :UpdaterCheck to validate now")
    end
  elseif cfg and not cfg.repo_path then
    health.warn("No repository path configured", {
      "Call require('updater').setup({ repo_path = '/path/to/repo' })",
    })
  else
    health.info("Plugin not yet configured - call require('updater').setup() first")
  end
end

return M
