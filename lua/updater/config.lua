local M = {}

local function validate_timeout_utility(cfg)
  local errors = {}
  if cfg.timeout_utility and type(cfg.timeout_utility) ~= "string" then
    table.insert(errors, "timeout_utility must be a string")
  end
  return errors
end

local function validate_periodic_check(cfg)
  local errors = {}
  if cfg.periodic_check and cfg.periodic_check.frequency_minutes then
    local freq = cfg.periodic_check.frequency_minutes
    if type(freq) ~= "number" or freq <= 0 then
      table.insert(errors, "periodic_check.frequency_minutes must be a positive number")
    elseif freq < 1 then
      table.insert(errors, "periodic_check.frequency_minutes must be at least 1 minute")
    end
  end
  return errors
end

local function validate_timeouts(cfg)
  local errors = {}
  if cfg.timeouts then
    for key, value in pairs(cfg.timeouts) do
      if type(value) ~= "number" or value <= 0 then
        table.insert(errors, "timeouts." .. key .. " must be a positive number")
      elseif value > 300 then
        table.insert(errors, "timeouts." .. key .. " is too large (max 300 seconds)")
      end
    end
  end
  return errors
end

local function validate_log_count(cfg)
  local errors = {}
  if cfg.log_count then
    if type(cfg.log_count) ~= "number" or cfg.log_count <= 0 or cfg.log_count > 100 then
      table.insert(errors, "log_count must be a number between 1 and 100")
    end
  end
  return errors
end

local function validate_main_branch(cfg)
  local errors = {}
  if cfg.main_branch and (type(cfg.main_branch) ~= "string" or cfg.main_branch == "") then
    table.insert(errors, "main_branch must be a non-empty string")
  end
  return errors
end

local function validate_git_options(cfg)
  local errors = {}
  if cfg.git then
    if cfg.git.rebase ~= nil and type(cfg.git.rebase) ~= "boolean" then
      table.insert(errors, "git.rebase must be a boolean")
    end
    if cfg.git.autostash ~= nil and type(cfg.git.autostash) ~= "boolean" then
      table.insert(errors, "git.autostash must be a boolean")
    end
  end
  return errors
end

local function validate_excluded_filetypes(cfg)
  local errors = {}
  if cfg.excluded_filetypes then
    if type(cfg.excluded_filetypes) ~= "table" then
      table.insert(errors, "excluded_filetypes must be a table")
    else
      for i, ft in ipairs(cfg.excluded_filetypes) do
        if type(ft) ~= "string" then
          table.insert(errors, "excluded_filetypes[" .. i .. "] must be a string")
        end
      end
    end
  end
  return errors
end

local function validate_versioned_releases_only(cfg)
  local errors = {}
  if cfg.versioned_releases_only ~= nil and type(cfg.versioned_releases_only) ~= "boolean" then
    table.insert(errors, "versioned_releases_only must be a boolean")
  end
  return errors
end

local function validate_version_tag_pattern(cfg)
  local errors = {}
  if cfg.version_tag_pattern ~= nil then
    if type(cfg.version_tag_pattern) ~= "string" then
      table.insert(errors, "version_tag_pattern must be a string")
    elseif cfg.version_tag_pattern == "" then
      table.insert(errors, "version_tag_pattern cannot be empty")
    end
  end
  return errors
end

local function validate_config(cfg)
  local errors = {}

  local validators = {
    validate_timeout_utility,
    validate_periodic_check,
    validate_timeouts,
    validate_log_count,
    validate_main_branch,
    validate_git_options,
    validate_excluded_filetypes,
    validate_versioned_releases_only,
    validate_version_tag_pattern,
  }

  for _, validator in ipairs(validators) do
    local validator_errors = validator(cfg)
    for _, error in ipairs(validator_errors) do
      table.insert(errors, error)
    end
  end

  return errors
end

local function expand_repo_path(path)
  if type(path) ~= "string" then
    return path
  end
  local expanded = vim.fn.expand(path)
  local resolved = vim.fn.resolve(expanded)
  return resolved
end

function M.setup_config(opts)
  local default_config = {
    repo_path = vim.fn.stdpath("config"),
    timeout_utility = "timeout",
    title = "Neovim Dotfiles Updater",
    log_count = 15,
    main_branch = "main",
    git = {
      rebase = true,
      autostash = true,
    },
    timeouts = {
      fetch = 30,
      pull = 30,
      merge = 30,
      log = 15,
      status = 10,
      default = 20,
    },
    notify = {
      up_to_date = {
        title = "Neovim Dotfiles",
        message = "Your dotfiles are up to date!",
        level = "info",
      },
      outdated = {
        title = "Neovim Dotfiles",
        message = "Updates available! Press <leader>e to open the updater.",
        level = "warn",
      },
      error = {
        title = "Neovim Dotfiles",
        message = "Error checking for updates",
        level = "error",
      },
      timeout = {
        title = "Neovim Dotfiles",
        message = "Git operation timed out",
        level = "error",
      },
      updated = {
        title = "Neovim Dotfiles",
        message = "Successfully updated dotfiles!",
        level = "info",
      },
    },
    keymap = {
      open = "<leader>e",
      update = "u",
      refresh = "r",
      close = "q",
      install_plugins = "i",
      update_all = "U",
    },
    check_updates_on_startup = {
      enabled = true,
    },
    periodic_check = {
      enabled = true,
      frequency_minutes = 20,
    },
    excluded_filetypes = { "gitcommit", "gitrebase" },
    versioned_releases_only = false, -- When true, only show updates when new release tags are available
    version_tag_pattern = "v*", -- Glob pattern for version tags (e.g., "v*", "release-*")
  }

  local merged_config = vim.tbl_deep_extend("force", default_config, opts or {})

  local config_errors = validate_config(merged_config)
  if #config_errors > 0 then
    local error_msg = "updater.nvim configuration errors:\n" .. table.concat(config_errors, "\n")
    return nil, error_msg
  end

  merged_config.repo_path = expand_repo_path(merged_config.repo_path)

  return merged_config
end

return M
