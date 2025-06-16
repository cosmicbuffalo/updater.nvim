return {
    "cosmicbuffalo/updater.nvim",
    opts = {
        -- Path to the dotfiles repository (default: current Neovim config directory)
        repo_path = vim.fn.stdpath("config"),
        -- Utility to run commands with timeout (switch to gtimeout on macOS)
        timeout_utility = "timeout",
        -- Title for the updater window
        title = "Neovim Dotfiles Updater",
        -- How many commits to show in the log
        log_count = 15,
        -- Main branch name
        main_branch = "main",
        -- Git operation timeouts (in seconds)
        timeouts = {
            fetch = 30,
            pull = 30,
            merge = 30,
            log = 15,
            status = 10,
            default = 20,
        },
        -- Keybindings
        keys = {
            open = "<leader>e",  -- Key to open the updater
            update = "u",        -- Key to trigger update
            refresh = "r",       -- Key to refresh status
            close = "q",         -- Key to close the updater
        }
    },
    keys = {
        { "<leader>e", function() require("updater").open() end, desc = "Open Dotfiles Updater" },
    },
    cmd = { "UpdaterOpen", "UpdaterCheck" },
    config = function(_, opts)
        require("updater").setup(opts)
    end,
}
