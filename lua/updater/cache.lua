local M = {}

local CACHE_VERSION = 1
local CACHE_DIR_NAME = "updater.nvim"
local CACHE_KEY_LENGTH = 16

function M.get_cache_dir()
  return vim.fn.stdpath("cache") .. "/" .. CACHE_DIR_NAME
end

function M.get_cache_key(repo_path)
  local hash = vim.fn.sha256(repo_path)
  return hash:sub(1, CACHE_KEY_LENGTH)
end

function M.get_cache_path(repo_path)
  local cache_dir = M.get_cache_dir()
  local cache_key = M.get_cache_key(repo_path)
  return cache_dir .. "/" .. cache_key .. ".json"
end

function M.ensure_cache_dir()
  local cache_dir = M.get_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 0 then
    vim.fn.mkdir(cache_dir, "p")
  end
  return cache_dir
end

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

  if data.version ~= CACHE_VERSION then
    return nil
  end

  if data.repo_path ~= repo_path then
    return nil
  end

  return data
end

function M.write(repo_path, data)
  M.ensure_cache_dir()

  local cache_path = M.get_cache_path(repo_path)

  local cache_data = vim.tbl_extend("force", data, {
    version = CACHE_VERSION,
    repo_path = repo_path,
  })

  local ok, json_content = pcall(vim.json.encode, cache_data)
  if not ok then
    return false
  end

  local file = io.open(cache_path, "w")
  if not file then
    return false
  end

  file:write(json_content)
  file:close()

  return true
end

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
