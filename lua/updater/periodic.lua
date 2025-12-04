local Progress = require("updater.progress")
local Operations = require("updater.operations")
local Status = require("updater.status")
local Spinner = require("updater.spinner")
local Constants = require("updater.constants")
local Cache = require("updater.cache")
local M = {}

local function periodic_check(config)
  if Cache.is_fresh(config.repo_path, config.periodic_check.frequency_minutes) then
    return
  end

  local progress_handler = Progress.handle_refresh_progress("Checking for updates...", "Fetching remote changes...")

  local has_updates = Operations.check_updates_silent(config)

  if progress_handler then
    progress_handler.finish(has_updates)
  end

  if has_updates then
    local message = config.notify.outdated.message
    if Status.state.ahead_count > 0 then
      message = "Your branch is ahead by "
        .. Status.state.ahead_count
        .. " commit(s) and behind by "
        .. Status.state.behind_count
        .. " commit(s). Press "
        .. config.keymap.open
        .. " to open the updater."
    end
    vim.notify(message, vim.log.levels.WARN, { title = config.notify.outdated.title })
  end
end

function M.stop_periodic_check()
  Status.stop_periodic_timer()
  Spinner.stop_loading_spinner()
end

function M.setup_periodic_check(config)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("updater_cleanup", { clear = true }),
    callback = M.stop_periodic_check,
  })

  if not config.periodic_check.enabled then
    return
  end

  local frequency_ms = config.periodic_check.frequency_minutes * 60 * 1000

  local timer = vim.uv.new_timer()
  Status.state.periodic_timer = timer
  timer:start(
    frequency_ms,
    frequency_ms,
    vim.schedule_wrap(function()
      -- Skip check if current filetype is excluded
      local ft = vim.bo.filetype
      for _, excluded_ft in ipairs(config.excluded_filetypes or {}) do
        if ft == excluded_ft then
          return
        end
      end
      periodic_check(config)
    end)
  )
end

function M.setup_startup_check(config, check_updates_callback)
  if not config.check_updates_on_startup.enabled then
    return
  end

  vim.api.nvim_create_autocmd("UIEnter", {
    group = vim.api.nvim_create_augroup("updater_check_updates", { clear = true }),
    callback = function()
      vim.defer_fn(function()
        -- Skip check if current filetype is excluded
        local ft = vim.bo.filetype
        for _, excluded_ft in ipairs(config.excluded_filetypes or {}) do
          if ft == excluded_ft then
            return
          end
        end

        if Cache.is_fresh(config.repo_path, config.periodic_check.frequency_minutes) then
          local cached = Cache.read(config.repo_path)
          if cached and cached.needs_update then
            vim.notify(config.notify.outdated.message, vim.log.levels.WARN, { title = config.notify.outdated.title })
          end
          return
        end

        check_updates_callback()
      end, Constants.STARTUP_CHECK_DELAY)
    end,
  })
end

return M
