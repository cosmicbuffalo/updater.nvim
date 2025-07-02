local M = {}

-- Simple error notification with consistent formatting
function M.notify_error(message, config, operation_name)
	operation_name = operation_name or "Operation"
	
	local title = "Updater Error"
	if config and config.notify and config.notify.error and config.notify.error.title then
		title = config.notify.error.title
	end
	
	local full_message = string.format("%s failed: %s", operation_name, message)
	vim.notify(full_message, vim.log.levels.ERROR, { title = title })
end

-- Simple timeout error string
function M.timeout_error(operation_name, timeout_seconds)
	return string.format("%s timed out after %d seconds", operation_name, timeout_seconds)
end

return M