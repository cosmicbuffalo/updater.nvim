local M = {}

local config = {
    repo_path = vim.fn.stdpath("config"),
    timeout_utility = "timeout",
    title = "Neovim Dotfiles Updater",
    log_count = 15,
    main_branch = "main",
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
    keys = {
        open = "<leader>e",
        update = "u",
        refresh = "r",
        close = "q",
    }
}

local state = {
    is_open = false,
    buffer = nil,
    window = nil,
    commits = {},
    current_commit = nil,
    is_updating = false,
    is_refreshing = false,
    needs_update = false,
    current_branch = "",
    ahead_count = 0,
    behind_count = 0,
    remote_commits = {},
    commits_in_branch = {},
}

local cd_repo_path = "cd " .. config.repo_path .. " && "

local function execute_command(cmd, timeout_key)
    timeout_key = timeout_key or "default"
    local timeout = config.timeouts[timeout_key] or config.timeouts.default

    local timeout_cmd = string.format(
        "%s %ds bash -c %s || (exit_code=$?; if [ $exit_code -eq 124 ]; then echo 'COMMAND_TIMED_OUT'; exit 124; else exit $exit_code; fi)",
        config.timeout_utility,
        timeout,
        vim.fn.shellescape(cmd .. " 2>&1")
    )

    local handle = io.popen(timeout_cmd)
    if not handle then
        return nil, "Failed to execute command"
    end

    local result = handle:read("*a")
    handle:close()

    if result and result:match("COMMAND_TIMED_OUT") then
        return nil, "timeout"
    end

    return result, nil
end

local function execute_git_command(git_cmd, timeout_key, operation_name)
    local full_cmd = cd_repo_path .. git_cmd
    local result, err = execute_command(full_cmd, timeout_key)

    if err then
        if err == "timeout" then
            vim.notify(
                (operation_name or "Git operation") .. " timed out",
                vim.log.levels.ERROR,
                { title = config.notify.timeout.title }
            )
        end
        return nil, err
    end

    return result and vim.trim(result), nil
end

local function notify_error(message, is_timeout)
    local notification = is_timeout and config.notify.timeout or config.notify.error
    vim.notify(message, vim.log.levels.ERROR, { title = notification.title })
end

local function parse_commit_line(line)
    local parts = vim.split(line, "|", { plain = true })
    if #parts < 4 then
        return nil
    end

    local hash = vim.trim(parts[1] or "")
    local message = vim.trim(parts[2] or "")
    local author = vim.trim(parts[3] or "")
    local date = vim.trim(parts[4] or "")

    message = message:gsub("\r", ""):gsub("\n.*", "")
    if #message > 80 then
        message = message:sub(1, 77) .. "..."
    end

    if hash ~= "" then
        return {
            hash = hash,
            message = message,
            author = author,
            date = date,
        }
    end

    return nil
end

local function parse_commits_from_output(result)
    local commits = {}
    if not result then
        return commits
    end

    for line in result:gmatch("[^\r\n]+") do
        local commit = parse_commit_line(line)
        if commit then
            table.insert(commits, commit)
        end
    end
    return commits
end

local function get_current_commit()
    local result, err = execute_git_command("git rev-parse HEAD", "status", "Git status check")
    return result
end

local function get_remote_commit()
    local _, err = execute_git_command("git fetch", "fetch", "Git fetch operation")
    if err then
        return nil
    end

    local result, fetch_err = execute_git_command("git rev-parse @{u}", "status", "Git status check")
    return result
end

local function get_current_branch()
    local result, err = execute_git_command("git rev-parse --abbrev-ref HEAD", "status", "Git branch check")
    return result or "unknown"
end

local function get_ahead_behind_count()
    local branch = get_current_branch()
    local main = config.main_branch
    local compare_with = "origin/" .. main

    local result, err = execute_git_command(
        "git rev-list --left-right --count " .. branch .. "..." .. compare_with,
        "status",
        "Git count operation"
    )

    if not result then
        return 0, 0
    end

    local ahead, behind = result:match("(%d+)%s+(%d+)")
    return tonumber(ahead) or 0, tonumber(behind) or 0
end

local function get_latest_remote_commit()
    local fetch_result, err = execute_git_command("git fetch", "fetch", "Git fetch operation")
    if err then
        return nil
    end

    local hash, hash_err = execute_git_command("git rev-parse origin/" .. config.main_branch, "status")
    if not hash then
        return nil
    end

    local details, details_err = execute_git_command(
        'git show -s --format="%h|%s|%an|%ar" ' .. hash,
        "log",
        "Git log operation"
    )
    if not details then
        return nil
    end

    local commit = parse_commit_line(details)
    if commit then
        commit.full_hash = hash
    end
    return commit
end

local function is_commit_in_branch(commit_hash, branch)
    local result, err = execute_git_command(
        "git branch --contains " .. commit_hash .. " | grep -q " .. branch .. " && echo yes || echo no",
        "status",
        "Git branch check"
    )
    return result == "yes"
end

local function get_commit_log()
    local branch = get_current_branch()
    local main = config.main_branch
    local log_format = string.format('--format=format:"%%h|%%s|%%an|%%ar" -n %d', config.log_count)
    local git_cmd
    local log_type

    if branch == main then
        if state.behind_count > 0 then
            git_cmd = string.format("git log %s origin/%s ^HEAD", log_format, main)
            log_type = "remote"
        else
            git_cmd = string.format("git log %s HEAD", log_format)
            log_type = "local"
        end
    else
        if state.ahead_count > 0 then
            git_cmd = string.format("git log %s %s ^%s", log_format, branch, main)
            log_type = "local"
        else
            git_cmd = string.format("git log %s %s ^%s", log_format, main, branch)
            log_type = "remote"
        end
    end

    local result, err = execute_git_command(git_cmd, "log", "Git log operation")
    if not result then
        return {}, log_type
    end

    return parse_commits_from_output(result), log_type
end

local function get_remote_commits_not_in_local()
    local branch = get_current_branch()
    local main = config.main_branch
    local compare_with = "origin/" .. main

    local git_cmd = string.format(
        'git log -n %d --format=format:"%%h|%%s|%%an|%%ar" %s ^%s',
        config.log_count,
        compare_with,
        branch
    )

    local result, err = execute_git_command(git_cmd, "log", "Git log operation")
    if not result then
        return {}
    end

    return parse_commits_from_output(result)
end

local function are_commits_in_branch(commits, branch)
    local result = {}
    for _, commit in ipairs(commits) do
        result[commit.hash] = is_commit_in_branch(commit.hash, branch)
    end
    return result
end

local function get_repo_status()
    local _, fetch_err = execute_git_command("git fetch", "fetch", "Git fetch operation")
    if fetch_err then
        return { error = true }
    end

    local branch = get_current_branch()
    local ahead, behind = get_ahead_behind_count()

    return {
        branch = branch,
        ahead = ahead,
        behind = behind,
        is_main = branch == config.main_branch,
        error = false,
        up_to_date = behind == 0,
        has_local_changes = ahead > 0,
    }
end

local function update_repo()
    state.is_updating = true
    M.render()

    local branch = get_current_branch()
    local cmd = ""

    local fetch_result, fetch_err =
        execute_command(cd_repo_path .. "git fetch origin " .. config.main_branch, "fetch")
    if fetch_err then
        state.is_updating = false
        local error_msg
        if fetch_err == "timeout" then
            error_msg = "Git fetch operation timed out"
            vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.timeout.title })
        else
            error_msg = "Failed to fetch updates: " .. (fetch_result or fetch_err or "Unknown error")
            vim.notify(error_msg, vim.log.levels.ERROR, { title = config.notify.error.title })
        end
        M.refresh()
        return
    end

    if branch == config.main_branch then
        cmd = "git pull origin " .. config.main_branch
    else
        cmd = "git merge origin/" .. config.main_branch .. " --no-edit"
    end

    local timeout_key = branch == config.main_branch and "pull" or "merge"
    local result, err = execute_command(cd_repo_path .. cmd, timeout_key)

    state.is_updating = false

    if err then
        if err == "timeout" then
            vim.notify(
                "Git " .. timeout_key .. " operation timed out",
                vim.log.levels.ERROR,
                { title = config.notify.timeout.title }
            )
        else
            vim.notify(
                "Failed to update: " .. (result or err or "Unknown error"),
                vim.log.levels.ERROR,
                { title = config.notify.error.title }
            )
        end
    elseif not result or result:match("error") or result:match("Error") or result:match("conflict") then
        vim.notify(
            "Failed to update: " .. (result or "Unknown error"),
            vim.log.levels.ERROR,
            { title = config.notify.error.title }
        )
    else
        if result:match("Already up to date") then
            vim.notify(
                "Already up to date with origin/" .. config.main_branch,
                vim.log.levels.INFO,
                { title = config.notify.updated.title }
            )
        else
            if branch == config.main_branch then
                vim.notify(
                    "Successfully pulled changes from origin/" .. config.main_branch,
                    vim.log.levels.INFO,
                    { title = config.notify.updated.title }
                )
            else
                vim.notify(
                    "Successfully merged origin/" .. config.main_branch .. " into " .. branch,
                    vim.log.levels.INFO,
                    { title = config.notify.updated.title }
                )
            end
        end
        state.needs_update = false
    end

    M.refresh()
end

function M.create_window()
    local width = math.min(math.floor(vim.o.columns * 0.9), 150)
    local height = math.min(math.floor(vim.o.lines * 0.8), 40)
    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - height) / 2)

    state.buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(state.buffer, "bufhidden", "wipe")

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

    state.window = vim.api.nvim_open_win(state.buffer, true, buf_opts)

    vim.api.nvim_win_set_option(state.window, "winblend", 10)
    vim.api.nvim_win_set_option(state.window, "cursorline", true)

    local opts = { buffer = state.buffer, noremap = true, silent = true }
    vim.keymap.set("n", config.keys.close, M.close, opts)
    vim.keymap.set("n", "<Esc>", M.close, opts)
    vim.keymap.set("n", config.keys.update, update_repo, opts)
    vim.keymap.set("n", config.keys.refresh, M.refresh, opts)

    vim.api.nvim_buf_set_option(state.buffer, "modifiable", false)
    vim.api.nvim_buf_set_option(state.buffer, "filetype", "dotfiles-updater")

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = state.buffer,
        callback = function()
            M.close()
        end,
        once = true,
    })

    state.is_open = true
end

local function generate_header()
    local header = { "" }

    table.insert(header, "  Branch: " .. state.current_branch)

    if state.current_branch == config.main_branch then
        if state.ahead_count > 0 then
            table.insert(header, string.format(
                "  Your %s branch is ahead of origin/%s by %d commits",
                config.main_branch, config.main_branch, state.ahead_count
            ))
        elseif state.behind_count > 0 then
            table.insert(header, string.format(
                "  Your %s branch is behind origin/%s by %d commits",
                config.main_branch, config.main_branch, state.behind_count
            ))
        else
            table.insert(header, string.format(
                "  Your %s branch is in sync with origin/%s",
                config.main_branch, config.main_branch
            ))
        end
    else
        if state.ahead_count > 0 then
            table.insert(header, string.format(
                "  Your branch is ahead of origin/%s by %d commits",
                config.main_branch, state.ahead_count
            ))
        end
        if state.behind_count > 0 then
            table.insert(header, string.format(
                "  Your branch is behind origin/%s by %d commits",
                config.main_branch, state.behind_count
            ))
        end
    end
    table.insert(header, "")

    if state.is_updating then
        table.insert(header, "  Updating dotfiles... Please wait.")
    elseif state.is_refreshing then
        table.insert(header, "  Checking for updates... Please wait.")
    elseif state.behind_count > 0 then
        table.insert(header, "  Updates available! Press 'u' to update.")
    else
        table.insert(header, "  Your dotfiles are up to date with origin/" .. config.main_branch .. "!")
    end
    table.insert(header, "")

    return header
end

local function generate_keybindings()
    return {
        "  Keybindings:",
        "    " .. config.keys.update .." - Update dotfiles",
        "    " .. config.keys.refresh .. " - Refresh status",
        "    " .. config.keys.close .. " - Close window",
        "",
    }
end

local function generate_remote_commits_section()
    local remote_commit_info = {}
    if #state.remote_commits > 0 then
        table.insert(remote_commit_info, "  Commits on origin/" .. config.main_branch .. " not in your branch:")
        table.insert(remote_commit_info, "  " .. string.rep("─", 70))

        for _, commit in ipairs(state.remote_commits) do
            local status_indicator = state.commits_in_branch[commit.hash] and "✓" or "✗"
            local line = string.format("  %s %s - %s (%s, %s)",
                status_indicator, commit.hash, commit.message, commit.author, commit.date)
            table.insert(remote_commit_info, line)
        end
        table.insert(remote_commit_info, "  ")
    end
    return remote_commit_info
end

local function generate_commit_log()
    local log_title = state.log_type == "remote"
            and "  Commits from origin/" .. config.main_branch .. " not in your branch:"
        or "  Local commits on " .. state.current_branch .. ":"

    local log_lines = {
        log_title,
        "  " .. string.rep("─", 70),
    }

    local current_hash = state.current_commit
    for _, commit in ipairs(state.commits) do
        local indicator = "  "
        if commit.hash == current_hash:sub(1, #commit.hash) then
            indicator = "→ "
        end

        local line = "  " .. indicator .. commit.hash .. " - " .. commit.message .. " (" .. commit.author .. ", " .. commit.date .. ")"
        table.insert(log_lines, line)
    end

    return log_lines
end

local function apply_highlighting(lines, status_line, keybindings_start, remote_commit_line)
    local ns_id = vim.api.nvim_create_namespace("DotfilesUpdater")
    vim.api.nvim_buf_clear_namespace(state.buffer, ns_id, 0, -1)

    vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Directory", 1, 2, -1)

    if state.is_updating or state.is_refreshing then
        vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "WarningMsg", status_line, 2, -1)
    else
        vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "String", status_line, 2, -1)
    end

    local keys = { config.keys.update, config.keys.refresh, config.keys.close }
    for i = 0, 2 do
        local line_num = keybindings_start + i
        vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Statement", line_num, 4, 4 + #keys[i + 1])
    end

    if #state.remote_commits > 0 then
        vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Title", remote_commit_line, 2, -1)

        for i = 1, #state.remote_commits do
            local line_num = remote_commit_line + i
            vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Statement", line_num, 2, 3)
            vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Directory", line_num, 4, 13)
            vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Special", line_num, state.remote_commits[i].message:len() + 17, -1)
        end
        remote_commit_line = remote_commit_line + #state.remote_commits + 1
    end

    vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Special", remote_commit_line, 2, -1)

    local log_start = remote_commit_line + 3
    for i, commit in ipairs(state.commits) do
        local line_num = log_start + i - 1
        local line = vim.api.nvim_buf_get_lines(state.buffer, line_num, line_num + 1, false)
        local indicator = vim.fn.strcharpart(line[1], 2, 1)
        if indicator == "→" then
            vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "String", line_num, 2, 3)
            vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Special", line_num, 4, 13)
            vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Special", line_num, commit.message:len() + 17, -1)
        else
            vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Special", line_num, 4, 11)
            vim.api.nvim_buf_add_highlight(state.buffer, ns_id, "Special", line_num, commit.message:len() + 15, -1)
        end
    end
end

function M.render()
    if not state.buffer or not state.is_open then
        return
    end

    vim.api.nvim_buf_set_option(state.buffer, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, {})

    local header = generate_header()
    local keybindings = generate_keybindings()
    local remote_commit_info = generate_remote_commits_section()
    local commit_log = generate_commit_log()

    local lines = {}

    for _, line in ipairs(header) do
        table.insert(lines, line)
    end
    local status_line = #lines - 2
    local keybindings_start = #lines + 1

    for _, line in ipairs(keybindings) do
        table.insert(lines, line)
    end

    local remote_commit_line = #lines + 1
    for _, line in ipairs(remote_commit_info) do
        table.insert(lines, line)
    end
    if #remote_commit_info == 0 then
        remote_commit_line = #lines - 1
    end

    for _, line in ipairs(commit_log) do
        table.insert(lines, line)
    end

    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
    apply_highlighting(lines, status_line, keybindings_start, remote_commit_line)

    vim.api.nvim_buf_set_option(state.buffer, "modifiable", false)
    vim.api.nvim_win_set_height(state.window, math.min(#lines + 1, 60))
    vim.cmd("redraw")
end

function M.refresh()
    state.is_refreshing = true
    if state.is_open then
        M.render()
    end

    state.current_commit = get_current_commit()
    local status = get_repo_status()

    if not status.error then
        state.current_branch = status.branch
        state.ahead_count = status.ahead
        state.behind_count = status.behind
        state.remote_commits = get_remote_commits_not_in_local()
        state.commits_in_branch = are_commits_in_branch(state.remote_commits, state.current_branch)
        state.needs_update = #state.remote_commits > 0
    else
        state.needs_update = false
    end

    state.commits, state.log_type = get_commit_log()
    state.is_refreshing = false
    M.render()
end

function M.open()
    if state.is_open then
        if vim.api.nvim_win_is_valid(state.window) then
            vim.api.nvim_set_current_win(state.window)
            return
        else
            state.is_open = false
        end
    end

    M.create_window()
    M.refresh()
end

function M.close()
    if state.is_open and state.window and vim.api.nvim_win_is_valid(state.window) then
        vim.api.nvim_win_close(state.window, true)
    end
    state.is_open = false
    state.window = nil
end

function M.check_updates()
    if vim.g.disable_neovim_dotfiles_check_updates then
        return
    end
    local status = get_repo_status()

    if status.error then
        vim.notify(config.notify.error.message, vim.log.levels.ERROR, { title = config.notify.error.title })
        return
    end

    state.current_branch = status.branch
    state.ahead_count = status.ahead
    state.behind_count = status.behind

    if status.behind > 0 then
        local message = config.notify.outdated.message
        if status.ahead > 0 then
            message = "Your branch is ahead by "
                .. status.ahead
                .. " commit(s) and behind by "
                .. status.behind
                .. " commit(s). Press <leader>e to open the updater."
        end

        vim.notify(message, vim.log.levels.WARN, { title = config.notify.outdated.title })
        state.needs_update = true
    else
        local message = config.notify.up_to_date.message
        if status.ahead > 0 then
            message = "Your branch is up to date with origin but ahead by " .. status.ahead .. " commits."
        end

        vim.notify(message, vim.log.levels.INFO, { title = config.notify.up_to_date.title })
        state.needs_update = false
    end
end

function M.setup(opts)
	opts = opts or {}

	config = vim.tbl_deep_extend("force", config, opts)
	cd_repo_path = "cd " .. config.repo_path .. " && "

	vim.keymap.set(
		"n",
		config.keys.open,
		M.open,
		{ noremap = true, silent = true, desc = "Open Neovim Dotfiles Updater" }
	)

	vim.api.nvim_create_user_command("UpdaterOpen", M.open, { desc = "Open the dotfiles updater" })
	vim.api.nvim_create_user_command("UpdaterCheck", M.check_updates, { desc = "Check for dotfiles updates" })
end

return M