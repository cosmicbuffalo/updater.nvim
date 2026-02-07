local M = {}

local health = vim.health

-- Check if gh CLI is available and authenticated
local function check_gh_auth()
  if vim.fn.executable("gh") ~= 1 then
    return false, "not installed"
  end

  -- Check if gh is authenticated (synchronous check for health)
  local result = vim.fn.system("gh auth status 2>&1")
  if vim.v.shell_error ~= 0 then
    if result:match("not logged in") or result:match("not logged into") then
      return false, "not authenticated"
    end
    return false, "auth check failed"
  end

  return true, "authenticated"
end

-- Cache for API method detection
local api_method_cache = {
  method = nil, -- "gh" | "curl" | "none" | nil (nil = not checked yet)
  checked_at = 0,
  ttl = 300, -- 5 minutes
}

-- Get the best available GitHub API method
-- Returns: "gh" | "curl" | nil
function M.get_github_api_method()
  local now = os.time()

  -- Return cached result if still valid
  if api_method_cache.method ~= nil and (now - api_method_cache.checked_at) < api_method_cache.ttl then
    -- Translate "none" sentinel back to nil
    if api_method_cache.method == "none" then
      return nil
    end
    return api_method_cache.method
  end

  -- Check gh CLI first (works with private repos)
  local gh_ok, _ = check_gh_auth()
  if gh_ok then
    api_method_cache.method = "gh"
    api_method_cache.checked_at = now
    return "gh"
  end

  -- Fall back to curl (works with public repos only)
  if vim.fn.executable("curl") == 1 then
    api_method_cache.method = "curl"
    api_method_cache.checked_at = now
    return "curl"
  end

  -- No API method available - use "none" sentinel to cache this result
  api_method_cache.method = "none"
  api_method_cache.checked_at = now
  return nil
end

-- Clear the API method cache (useful after auth changes)
function M.clear_api_cache()
  api_method_cache.method = nil
  api_method_cache.checked_at = 0
end

function M.check()
  health.start("updater.nvim")

  if vim.fn.executable("git") == 1 then
    health.ok("git command available")
  else
    health.error("git command not found in PATH", { "Install git and ensure it's in your PATH" })
  end

  -- Check GitHub API availability (for release metadata)
  local gh_ok, gh_status = check_gh_auth()
  if gh_ok then
    health.ok("gh CLI authenticated - GitHub release metadata enabled (private repos supported)")
  else
    if gh_status == "not installed" then
      if vim.fn.executable("curl") == 1 then
        health.warn("gh CLI not installed - using curl for GitHub API (public repos only)", {
          "Install gh CLI for private repository support: https://cli.github.com/",
          "Release titles and notes from GitHub will only work for public repos",
        })
      else
        health.warn("gh CLI not installed and curl not available", {
          "Install gh CLI for GitHub release metadata: https://cli.github.com/",
          "Or install curl for public repo support",
          "Plugin will use git tag data only (no GitHub release titles/notes)",
        })
      end
    elseif gh_status == "not authenticated" then
      if vim.fn.executable("curl") == 1 then
        health.warn("gh CLI not authenticated - using curl for GitHub API (public repos only)", {
          "Run 'gh auth login' for private repository support",
          "Release titles and notes from GitHub will only work for public repos",
        })
      else
        health.warn("gh CLI not authenticated and curl not available", {
          "Run 'gh auth login' for GitHub release metadata",
          "Or install curl for public repo support",
          "Plugin will use git tag data only (no GitHub release titles/notes)",
        })
      end
    else
      health.warn("gh CLI auth check failed: " .. gh_status, {
        "Try running 'gh auth status' to diagnose",
      })
    end
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

  local ok, _ = pcall(require, "updater")
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
end

return M
