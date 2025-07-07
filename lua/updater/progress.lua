local Constants = require("updater.constants")
local M = {}

function M.is_fidget_available()
	local ok, _ = pcall(require, "fidget")
	return ok
end

function M.create_fidget_progress(title, message)
	if not M.is_fidget_available() then
		return nil
	end

	local ok, fidget = pcall(require, "fidget")
	if not ok then
		return nil
	end

	return fidget.progress.handle.create({
		title = title,
		message = message,
		lsp_client = { name = "updater.nvim" },
	})
end

function M.handle_refresh_progress(progress_title, initial_message)
	local progress = nil

	progress = M.create_fidget_progress("Updater", progress_title)
	if progress then
		progress:report({ message = initial_message })
	end

	return {
		progress = progress,
		update_fetching = function()
			if progress then
				progress:report({ message = "Fetching remote changes..." })
			end
		end,
		finish = function(has_updates)
			if progress then
				if has_updates then
					progress:report({ message = "Updates available!" })
					vim.defer_fn(function()
						progress:finish()
					end, Constants.PROGRESS_SUCCESS_DURATION)
				else
					progress:report({ message = "Up to date" })
					vim.defer_fn(function()
						progress:finish()
					end, Constants.PROGRESS_FINISH_DURATION)
				end
			end
		end,
	}
end

return M

