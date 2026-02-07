local Config = require("updater.config")

describe("config module", function()
  describe("setup_config", function()
    it("should return default config when no options provided", function()
      local config, err = Config.setup_config({})

      assert.is_not_nil(config)
      assert.is_nil(err)
      assert.is_not_nil(config.repo_path)
      assert.equals("main", config.main_branch)
      assert.equals(15, config.log_count)
    end)

    it("should merge user options with defaults", function()
      local config, _err = Config.setup_config({
        main_branch = "develop",
        log_count = 20,
      })

      assert.is_not_nil(config)
      assert.equals("develop", config.main_branch)
      assert.equals(20, config.log_count)
    end)

    it("should accept any repo_path without validation", function()
      -- repo_path is not validated at config time - errors will surface on first use
      local config, err = Config.setup_config({
        repo_path = "/nonexistent/path/that/does/not/exist",
      })

      assert.is_not_nil(config)
      assert.is_nil(err)
      assert.equals("/nonexistent/path/that/does/not/exist", config.repo_path)
    end)

    it("should have default timeouts configured", function()
      local config, _err = Config.setup_config({})

      assert.is_not_nil(config)
      assert.is_not_nil(config.timeouts)
      assert.is_not_nil(config.timeouts.fetch)
      assert.is_not_nil(config.timeouts.pull)
      assert.is_not_nil(config.timeouts.merge)
      assert.is_not_nil(config.timeouts.log)
      assert.is_not_nil(config.timeouts.status)
      assert.is_not_nil(config.timeouts.default)
    end)

    it("should have default keymaps configured", function()
      local config, _err = Config.setup_config({})

      assert.is_not_nil(config)
      assert.is_not_nil(config.keymap)
      assert.equals("<leader>e", config.keymap.open)
      assert.equals("u", config.keymap.update)
      assert.equals("r", config.keymap.refresh)
      assert.equals("q", config.keymap.close)
    end)

    it("should have default notification messages", function()
      local config, _err = Config.setup_config({})

      assert.is_not_nil(config)
      assert.is_not_nil(config.notify)
      assert.is_not_nil(config.notify.up_to_date)
      assert.is_not_nil(config.notify.outdated)
      assert.is_not_nil(config.notify.error)
      assert.is_not_nil(config.notify.timeout)
      assert.is_not_nil(config.notify.updated)
    end)

    it("should validate log_count is positive", function()
      local config, err = Config.setup_config({
        log_count = -5,
      })

      assert.is_nil(config)
      assert.is_not_nil(err)
      assert.is_truthy(err:match("log_count"))
    end)

    it("should validate log_count max limit", function()
      local config, err = Config.setup_config({
        log_count = 500,
      })

      assert.is_nil(config)
      assert.is_not_nil(err)
      assert.is_truthy(err:match("log_count"))
    end)

    it("should validate timeout values are positive", function()
      local config, err = Config.setup_config({
        timeouts = {
          fetch = -10,
        },
      })

      assert.is_nil(config)
      assert.is_not_nil(err)
      assert.is_truthy(err:match("timeouts"))
    end)

    it("should expand repo_path with vim functions", function()
      local config, _err = Config.setup_config({
        repo_path = vim.fn.stdpath("config"),
      })

      assert.is_not_nil(config)
      assert.is_not_nil(config.repo_path)
      -- Should be an absolute path
      assert.is_truthy(config.repo_path:match("^/"))
    end)

    it("should have git options configured", function()
      local config, _err = Config.setup_config({})

      assert.is_not_nil(config)
      assert.is_not_nil(config.git)
      assert.is_true(config.git.rebase)
      assert.is_true(config.git.autostash)
    end)

    it("should allow overriding git options", function()
      local config, _err = Config.setup_config({
        git = {
          rebase = false,
          autostash = false,
        },
      })

      assert.is_not_nil(config)
      assert.is_false(config.git.rebase)
      assert.is_false(config.git.autostash)
    end)
  end)
end)
