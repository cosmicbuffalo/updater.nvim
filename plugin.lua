return {
  "cosmicbuffalo/updater.nvim",
  opts = {
    -- Example configuration - customize as needed
    -- repo_path = vim.fn.stdpath("config"), -- default
    -- periodic_check = { frequency_minutes = 240 }, -- default is 20 minutes
  },
  keys = {
    {
      "<leader>e",
      function()
        require("updater").open()
      end,
      desc = "Open Dotfiles Updater",
    },
  },
  cmd = {
    "UpdaterOpen",
    "UpdaterCheck",
    "UpdaterStartChecking", -- DEPRECATED
    "UpdaterStopChecking", -- DEPRECATED
    "UpdaterHealth",
  },
  config = function(_, opts)
    require("updater").setup(opts)
  end,
}
