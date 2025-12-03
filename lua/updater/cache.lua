local M = {}

-- Constants
local CACHE_VERSION = 1
local CACHE_DIR_NAME = "updater"
local CACHE_KEY_LENGTH = 16

-- Get the cache directory path (XDG-compliant)
function M.get_cache_dir()
  return vim.fn.stdpath("cache") .. "/" .. CACHE_DIR_NAME
end

-- Generate a stable cache key from repo path
function M.get_cache_key(repo_path)
  local hash = vim.fn.sha256(repo_path)
  return hash:sub(1, CACHE_KEY_LENGTH)
end

-- Get the full path to the cache file for a repo
function M.get_cache_path(repo_path)
  local cache_dir = M.get_cache_dir()
  local cache_key = M.get_cache_key(repo_path)
  return cache_dir .. "/" .. cache_key .. ".json"
end

-- Ensure cache directory exists
function M.ensure_cache_dir()
  local cache_dir = M.get_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 0 then
    vim.fn.mkdir(cache_dir, "p")
  end
  return cache_dir
end

-- Read cache data for a repo (fail-open: returns nil on any error)
function M.read(repo_path)
  local cache_path = M.get_cache_path(repo_path)

  local file = io.open(cache_path, "r")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()

  if not content or content == "" then
    return nil
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return nil
  end

  -- Validate cache version
  if data.version ~= CACHE_VERSION then
    return nil
  end

  -- Validate repo path matches (security check)
  if data.repo_path ~= repo_path then
    return nil
  end

  return data
end

-- Write cache data for a repo (atomic write via temp file + rename)
function M.write(repo_path, data)
  M.ensure_cache_dir()

  local cache_path = M.get_cache_path(repo_path)
  local temp_path = cache_path .. ".tmp." .. os.time()

  -- Prepare data with version and repo path
  local cache_data = vim.tbl_extend("force", data, {
    version = CACHE_VERSION,
    repo_path = repo_path,
  })

  local ok, json_content = pcall(vim.json.encode, cache_data)
  if not ok then
    return false
  end

  -- Write to temp file
  local file = io.open(temp_path, "w")
  if not file then
    return false
  end

  file:write(json_content)
  file:close()

  -- Atomic rename
  local rename_ok = os.rename(temp_path, cache_path)
  if not rename_ok then
    -- Clean up temp file on failure
    os.remove(temp_path)
    return false
  end

  return true
end

-- Check if cache is fresh (within frequency_minutes)
function M.is_fresh(repo_path, frequency_minutes)
  local cache_data = M.read(repo_path)
  if not cache_data or not cache_data.last_check_time then
    return false
  end

  local now = os.time()
  local age_seconds = now - cache_data.last_check_time
  local max_age_seconds = frequency_minutes * 60

  return age_seconds < max_age_seconds
end

-- Update cache after a successful check
function M.update_after_check(repo_path, status_data)
  local cache_data = {
    last_check_time = os.time(),
    last_commit_hash = status_data.current_commit,
    branch = status_data.branch,
    behind_count = status_data.behind_count or 0,
    ahead_count = status_data.ahead_count or 0,
    needs_update = status_data.needs_update or false,
    has_plugin_updates = status_data.has_plugin_updates or false,
  }

  return M.write(repo_path, cache_data)
end

return M
