local M = {}

function M.create_render_callback(config)
  return function(mode)
    local Window = require("updater.window")
    if mode == "loading" then
      Window.render_loading_state(config)
    else
      Window.render(config)
    end
  end
end

function M.generate_outdated_message(config, status)
  if status.ahead > 0 then
    return "Your branch is ahead by "
      .. status.ahead
      .. " commit(s) and behind by "
      .. status.behind
      .. " commit(s). Press "
      .. config.keymap.open
      .. " to open the updater."
  else
    return config.notify.outdated.message
  end
end

function M.generate_up_to_date_message(config, status)
  if status.ahead > 0 then
    return "Your branch is up to date! (but ahead by " .. status.ahead .. " commits)."
  else
    return config.notify.up_to_date.message
  end
end

return M
