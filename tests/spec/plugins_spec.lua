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

  describe("get_plugin_updates_async", function()
    it("should call callback with empty result when config is nil", function()
      local result
      local captured = _G.test_helpers.capture_notifications()

      Plugins.get_plugin_updates_async(nil, function(r)
        result = r
      end)

      captured.restore()

      assert.is_table(result)
      assert.is_table(result.all_updates)
      assert.is_table(result.plugins_behind)
      assert.is_table(result.plugins_ahead)
      assert.equals(0, #result.all_updates)
      assert.equals(0, #result.plugins_behind)
      assert.equals(0, #result.plugins_ahead)
    end)

    it("should call callback with empty result when repo_path is empty", function()
      local result
      local captured = _G.test_helpers.capture_notifications()

      Plugins.get_plugin_updates_async({ repo_path = "" }, function(r)
        result = r
      end)

      captured.restore()

      assert.is_table(result)
      assert.equals(0, #result.all_updates)
      assert.equals(0, #result.plugins_behind)
      assert.equals(0, #result.plugins_ahead)
    end)

    it("should call callback with empty result when lockfile does not exist", function()
      local result

      Plugins.get_plugin_updates_async(test_config, function(r)
        result = r
      end)

      assert.is_table(result)
      assert.equals(0, #result.all_updates)
      assert.equals(0, #result.plugins_behind)
      assert.equals(0, #result.plugins_ahead)
    end)

    it("should return result with proper structure", function()
      local result

      Plugins.get_plugin_updates_async(test_config, function(r)
        result = r
      end)

      assert.is_table(result)
      assert.is_not_nil(result.all_updates)
      assert.is_not_nil(result.plugins_behind)
      assert.is_not_nil(result.plugins_ahead)
    end)
  end)
end)
