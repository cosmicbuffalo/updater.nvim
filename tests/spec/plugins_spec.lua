local Plugins = require("updater.plugins")

describe("plugins module", function()
  local test_dir
  local test_config

  before_each(function()
    test_dir = _G.test_helpers.create_temp_dir()
    test_config = {
      repo_path = test_dir,
    }
  end)

  after_each(function()
    _G.test_helpers.cleanup_temp_dir(test_dir)
  end)

  describe("is_lazy_available", function()
    it("should return true when lazy.core.config is mocked", function()
      -- Our test setup mocks lazy.core.config
      assert.is_true(Plugins.is_lazy_available())
    end)
  end)

  describe("get_plugin_updates", function()
    it("should return empty table when config is nil", function()
      local captured = _G.test_helpers.capture_notifications()
      local updates = Plugins.get_plugin_updates(nil)
      captured.restore()

      assert.is_table(updates)
      assert.equals(0, #updates)
    end)

    it("should return empty table when repo_path is empty", function()
      local captured = _G.test_helpers.capture_notifications()
      local updates = Plugins.get_plugin_updates({ repo_path = "" })
      captured.restore()

      assert.is_table(updates)
      assert.equals(0, #updates)
    end)

    it("should return empty table when lockfile does not exist", function()
      local updates = Plugins.get_plugin_updates(test_config)

      assert.is_table(updates)
      assert.equals(0, #updates)
    end)

    it("should return empty table for empty lockfile", function()
      -- Create empty lockfile
      local lockfile_path = test_dir .. "/lazy-lock.json"
      local file = io.open(lockfile_path, "w")
      file:write("")
      file:close()

      local updates = Plugins.get_plugin_updates(test_config)

      assert.is_table(updates)
      assert.equals(0, #updates)
    end)

    it("should handle malformed JSON gracefully", function()
      local lockfile_path = test_dir .. "/lazy-lock.json"
      local file = io.open(lockfile_path, "w")
      file:write("this is not valid json")
      file:close()

      local captured = _G.test_helpers.capture_notifications()
      local updates = Plugins.get_plugin_updates(test_config)
      captured.restore()

      assert.is_table(updates)
      assert.equals(0, #updates)
      -- Should have warned about malformed JSON
      assert.is_true(#captured.notifications >= 1)
    end)

    it("should handle valid lockfile with no updates needed", function()
      local lockfile_path = test_dir .. "/lazy-lock.json"
      local file = io.open(lockfile_path, "w")
      file:write(vim.json.encode({
        ["test-plugin"] = {
          branch = "main",
          commit = "abc123def456789",
        },
      }))
      file:close()

      local updates = Plugins.get_plugin_updates(test_config)

      -- Since the mock doesn't return installed commits, no updates detected
      assert.is_table(updates)
    end)
  end)

  describe("get_installed_plugin_commit", function()
    it("should return nil for non-existent plugin", function()
      local commit = Plugins.get_installed_plugin_commit("non-existent-plugin")
      assert.is_nil(commit)
    end)
  end)

  describe("install_plugin_updates", function()
    it("should error when config is nil", function()
      local captured = _G.test_helpers.capture_notifications()

      Plugins.install_plugin_updates(nil, nil)

      captured.restore()

      assert.equals(1, #captured.notifications)
      assert.equals(vim.log.levels.ERROR, captured.notifications[1].level)
    end)

    it("should error when repo_path is empty", function()
      local captured = _G.test_helpers.capture_notifications()

      Plugins.install_plugin_updates({ repo_path = "" }, nil)

      captured.restore()

      assert.equals(1, #captured.notifications)
      assert.equals(vim.log.levels.ERROR, captured.notifications[1].level)
    end)
  end)
end)
