local Config = require("updater.config")
local M = {}

function M.notify_error(message, operation_name)
  operation_name = operation_name or "Operation"
  local config = Config.get()

  local title = "Updater Error"
  if config and config.notify and config.notify.error and config.notify.error.title then
    title = config.notify.error.title
  end

  local full_message = string.format("%s failed: %s", operation_name, message)
  vim.notify(full_message, vim.log.levels.ERROR, { title = title })
end

return M
