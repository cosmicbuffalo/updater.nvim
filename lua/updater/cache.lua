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

-- Async read using vim.uv
function M.read(repo_path, callback)
  local cache_path = M.get_cache_path(repo_path)

  vim.uv.fs_open(cache_path, "r", 438, function(err, fd)
    if err or not fd then
      vim.schedule(function()
        callback(nil)
      end)
      return
    end

    vim.uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or not stat then
        vim.uv.fs_close(fd)
        vim.schedule(function()
          callback(nil)
        end)
        return
      end

      vim.uv.fs_read(fd, stat.size, 0, function(read_err, content)
        vim.uv.fs_close(fd)

        if read_err or not content or content == "" then
          vim.schedule(function()
            callback(nil)
          end)
          return
        end

        vim.schedule(function()
          local ok, data = pcall(vim.json.decode, content)
          if not ok or type(data) ~= "table" then
            callback(nil)
            return
          end

          if data.version ~= CACHE_VERSION then
            callback(nil)
            return
          end

          if data.repo_path ~= repo_path then
            callback(nil)
            return
          end

          callback(data)
        end)
      end)
    end)
  end)
end

-- Async write using vim.uv
function M.write(repo_path, data, callback)
  M.ensure_cache_dir()

  local cache_path = M.get_cache_path(repo_path)

  local cache_data = vim.tbl_extend("force", data, {
    version = CACHE_VERSION,
    repo_path = repo_path,
  })

  local ok, json_content = pcall(vim.json.encode, cache_data)
  if not ok then
    if callback then
      vim.schedule(function()
        callback(false)
      end)
    end
    return
  end

  vim.uv.fs_open(cache_path, "w", 438, function(err, fd)
    if err or not fd then
      if callback then
        vim.schedule(function()
          callback(false)
        end)
      end
      return
    end

    vim.uv.fs_write(fd, json_content, 0, function(write_err)
      vim.uv.fs_close(fd)
      if callback then
        vim.schedule(function()
          callback(not write_err)
        end)
      end
    end)
  end)
end

-- Async check if cache is fresh
function M.is_fresh(repo_path, frequency_minutes, callback)
  M.read(repo_path, function(cache_data)
    if not cache_data or not cache_data.last_check_time then
      callback(false, nil)
      return
    end

    local now = os.time()
    local age_seconds = now - cache_data.last_check_time
    local max_age_seconds = frequency_minutes * 60

    callback(age_seconds < max_age_seconds, cache_data)
  end)
end

-- Async update cache after check
function M.update_after_check(repo_path, state, callback)
  local cache_data = {
    last_check_time = os.time(),
    last_commit_hash = state.current_commit,
    branch = state.current_branch,
    behind_count = state.behind_count or 0,
    ahead_count = state.ahead_count or 0,
    needs_update = state.needs_update or false,
    has_plugin_updates = state.has_plugin_updates or false,
  }

  M.write(repo_path, cache_data, callback)
end

return M
