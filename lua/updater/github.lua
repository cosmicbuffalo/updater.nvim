-- GitHub API integration for fetching release data
local M = {}

local Health = require("updater.health")

-- Cache for GitHub releases
local releases_cache = {
  data = {}, -- map of tag -> release data
  last_fetch = 0,
  ttl = 300, -- 5 minutes cache
}

-- Parse GitHub owner/repo from a remote URL
-- Supports:
--   https://github.com/owner/repo
--   https://github.com/owner/repo.git
--   git@github.com:owner/repo.git
function M.parse_github_url(url)
  if not url then
    return nil, nil
  end

  -- HTTPS format
  local owner, repo = url:match("github%.com/([^/]+)/([^/%.]+)")
  if owner and repo then
    return owner, repo
  end

  -- SSH format
  owner, repo = url:match("github%.com:([^/]+)/([^/%.]+)")
  if owner and repo then
    return owner, repo
  end

  return nil, nil
end

-- Fetch all releases from GitHub API
-- callback(releases_map, error) where releases_map is tag -> release_data
function M.fetch_releases(callback)
  local now = os.time()

  -- Check cache
  if now - releases_cache.last_fetch < releases_cache.ttl and next(releases_cache.data) ~= nil then
    callback(releases_cache.data, nil)
    return
  end

  -- Get the remote URL to parse owner/repo
  local Git = require("updater.git")
  Git.get_remote_url(function(remote_url, err)
    if err or not remote_url then
      callback({}, "Failed to get remote URL: " .. (err or "unknown"))
      return
    end

    local owner, repo = M.parse_github_url(remote_url)
    if not owner or not repo then
      callback({}, "Not a GitHub repository or could not parse URL: " .. remote_url)
      return
    end

    -- Determine which API method to use
    local api_method = Health.get_github_api_method()

    if not api_method then
      -- No API method available, skip GitHub release fetching
      callback({}, "No GitHub API method available (install gh CLI or curl)")
      return
    end

    -- Build the command based on available method
    local cmd
    if api_method == "gh" then
      -- Use gh CLI (works with private repos)
      local api_path = string.format("repos/%s/%s/releases", owner, repo)
      cmd = string.format("gh api %s 2>/dev/null", vim.fn.shellescape(api_path))
    else
      -- Use curl (works with public repos only)
      local api_url = string.format("https://api.github.com/repos/%s/%s/releases", owner, repo)
      cmd =
        string.format("curl -s -H 'Accept: application/vnd.github.v3+json' %s 2>/dev/null", vim.fn.shellescape(api_url))
    end

    vim.system({ "bash", "-c", cmd }, {
      text = true,
      timeout = 10000, -- 10 second timeout
    }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          -- API call failed - silently fail, GitHub data is optional
          callback({}, "GitHub API request failed")
          return
        end

        local json_str = obj.stdout
        if not json_str or json_str == "" then
          callback({}, "Empty response from GitHub API")
          return
        end

        -- Parse JSON
        local ok, releases = pcall(vim.json.decode, json_str)
        if not ok or type(releases) ~= "table" then
          callback({}, "Failed to parse GitHub API response")
          return
        end

        -- Check for API error response (e.g., 404 for private repo with curl)
        if releases.message then
          -- This happens when using curl on a private repo - silently fail
          callback({}, "GitHub API error: " .. releases.message)
          return
        end

        -- Build map of tag -> release data
        local releases_map = {}
        for _, release in ipairs(releases) do
          if release.tag_name then
            releases_map[release.tag_name] = {
              tag = release.tag_name,
              name = release.name, -- Release title
              body = release.body, -- Release notes/description
              prerelease = release.prerelease or false,
              draft = release.draft or false,
              html_url = release.html_url,
              published_at = release.published_at,
              author = release.author and release.author.login or nil,
            }
          end
        end

        -- Update cache
        releases_cache.data = releases_map
        releases_cache.last_fetch = now

        callback(releases_map, nil)
      end)
    end)
  end)
end

-- Get cached release data for a specific tag
function M.get_release(tag)
  return releases_cache.data[tag]
end

-- Check if a tag has GitHub release data
function M.has_release(tag)
  return releases_cache.data[tag] ~= nil
end

-- Get all cached releases
function M.get_all_releases()
  return releases_cache.data
end

-- Clear the cache
function M.clear_cache()
  releases_cache.data = {}
  releases_cache.last_fetch = 0
end

return M
