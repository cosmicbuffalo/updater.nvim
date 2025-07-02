local Constants = require("updater.constants")
local Status = require("updater.status")
local M = {}


function M.start_loading_spinner(render_callback)
	if Status.state.loading_spinner_timer then
		return
	end

	Status.state.loading_spinner_frame = 1
	Status.state.loading_spinner_timer = vim.uv.new_timer()
	Status.state.loading_spinner_timer:start(
		Constants.SPINNER_INTERVAL,
		Constants.SPINNER_INTERVAL,
		vim.schedule_wrap(function()
			Status.state.loading_spinner_frame = (Status.state.loading_spinner_frame % #Constants.SPINNER_FRAMES) + 1
			if Status.state.is_open and render_callback then
				if Status.state.is_initial_load then
					render_callback("loading")
				else
					render_callback("normal")
				end
			end
		end)
	)
end

function M.stop_loading_spinner()
	if Status.state.loading_spinner_timer then
		Status.state.loading_spinner_timer:stop()
		Status.state.loading_spinner_timer:close()
		Status.state.loading_spinner_timer = nil
	end
end

return M