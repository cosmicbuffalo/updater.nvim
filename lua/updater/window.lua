local UI = require("updater.ui")
local Status = require("updater.status")
local Constants = require("updater.constants")
local M = {}

function M.create_window(config)
  local width = math.min(math.floor(vim.o.columns * Constants.WINDOW_WIDTH_RATIO), Constants.MAX_WINDOW_WIDTH)
  local height = math.min(math.floor(vim.o.lines * Constants.WINDOW_HEIGHT_RATIO), Constants.MAX_WINDOW_HEIGHT)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  Status.state.buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(Status.state.buffer, "bufhidden", "wipe")

  local buf_opts = {
    style = "minimal",
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    title = config.title,
    title_pos = "center",
  }

  Status.state.window = vim.api.nvim_open_win(Status.state.buffer, true, buf_opts)

  vim.api.nvim_win_set_option(Status.state.window, "winblend", Constants.WINDOW_BLEND)
  vim.api.nvim_win_set_option(Status.state.window, "cursorline", true)

  vim.api.nvim_buf_set_option(Status.state.buffer, "modifiable", false)
  vim.api.nvim_buf_set_option(Status.state.buffer, "filetype", "dotfiles-updater")

  Status.state.is_open = true
end

function M.setup_keymaps(config, callbacks)
  local opts = { buffer = Status.state.buffer, noremap = true, silent = true }
  vim.keymap.set("n", config.keymap.close, callbacks.close, opts)
  vim.keymap.set("n", "<Esc>", callbacks.close, opts)
  vim.keymap.set("n", config.keymap.update, callbacks.update, opts)
  vim.keymap.set("n", config.keymap.refresh, callbacks.refresh, opts)
  vim.keymap.set("n", config.keymap.install_plugins, callbacks.install_plugins, opts)
  vim.keymap.set("n", config.keymap.update_all, callbacks.update_all, opts)
end

function M.setup_autocmds(close_callback)
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = Status.state.buffer,
    callback = function()
      close_callback()
    end,
    once = true,
  })
end

function M.render(config)
  if not Status.state.buffer or not Status.state.is_open then
    return
  end

  vim.api.nvim_buf_set_option(Status.state.buffer, "modifiable", true)
  vim.api.nvim_buf_set_lines(Status.state.buffer, 0, -1, false, {})

  local header, status_messages, status_lines_start = UI.generate_header(Status.state, config)
  local keybindings, keybind_data = UI.generate_keybindings(Status.state, config)
  local remote_commit_info = UI.generate_remote_commits_section(Status.state, config)
  local plugin_update_info = UI.generate_plugin_updates_section(Status.state)
  local plugins_ahead_info = UI.generate_plugins_ahead_section(Status.state)
  local restart_reminder = UI.generate_restart_reminder_section(Status.state)

  -- Only show commit log if it's not redundant with remote commits section
  -- When both would show remote commits, prefer the remote commits section
  local show_commit_log = not (#Status.state.remote_commits > 0 and Status.state.log_type == "remote")
    and #Status.state.commits > 0
  local commit_log = show_commit_log and UI.generate_commit_log(Status.state, config) or {}

  local lines = {}

  for _, line in ipairs(header) do
    table.insert(lines, line)
  end

  local keybindings_start = #lines + 1
  for _, line in ipairs(keybindings) do
    table.insert(lines, line)
  end

  local restart_reminder_line = #lines + 1
  for _, line in ipairs(restart_reminder) do
    table.insert(lines, line)
  end
  if #restart_reminder == 0 then
    restart_reminder_line = #lines - 1
  end

  for _, line in ipairs(remote_commit_info) do
    table.insert(lines, line)
  end

  for _, line in ipairs(plugin_update_info) do
    table.insert(lines, line)
  end

  for _, line in ipairs(plugins_ahead_info) do
    table.insert(lines, line)
  end

  for _, line in ipairs(commit_log) do
    table.insert(lines, line)
  end

  vim.api.nvim_buf_set_lines(Status.state.buffer, 0, -1, false, lines)
  UI.apply_highlighting(
    Status.state,
    config,
    status_messages,
    status_lines_start,
    keybindings_start,
    keybind_data,
    restart_reminder_line
  )

  vim.api.nvim_buf_set_option(Status.state.buffer, "modifiable", false)
  vim.api.nvim_win_set_height(Status.state.window, math.min(#lines + 1, Constants.MAX_WINDOW_HEIGHT_LINES))
end

function M.render_loading_state(config)
  if not Status.state.buffer or not Status.state.is_open then
    return
  end

  vim.api.nvim_buf_set_option(Status.state.buffer, "modifiable", true)
  vim.api.nvim_buf_set_lines(Status.state.buffer, 0, -1, false, {})

  local lines = UI.generate_loading_state(Status.state, config)
  vim.api.nvim_buf_set_lines(Status.state.buffer, 0, -1, false, lines)

  UI.apply_loading_state_highlighting(Status.state, config)

  vim.api.nvim_buf_set_option(Status.state.buffer, "modifiable", false)
  vim.api.nvim_win_set_height(Status.state.window, math.min(#lines + 1, Constants.MAX_WINDOW_HEIGHT_LINES))
end

function M.close()
  if Status.state.is_open and Status.state.window and vim.api.nvim_win_is_valid(Status.state.window) then
    vim.api.nvim_win_close(Status.state.window, true)
  end
  Status.state.is_open = false
  Status.state.is_initial_load = false
  Status.clear_recent_updates()
  Status.state.window = nil
end

return M
