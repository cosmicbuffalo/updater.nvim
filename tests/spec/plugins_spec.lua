local Plugins = require("updater.plugins")
local Config = require("updater.config")

describe("plugins module", function()
  local test_dir

  before_each(function()
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
    Config._reset({
      repo_path = test_dir,
    })
  end)

  after_each(function()
    vim.fn.delete(test_dir, "rf")
    Config._reset(nil)
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
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level, opts = opts })
      end

      Config._reset(nil)
      Plugins.install_plugin_updates(nil)

      vim.notify = original_notify

      assert.equals(1, #notifications)
      assert.equals(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("should error when repo_path is empty", function()
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level, opts = opts })
      end

      Config._reset({ repo_path = "" })
      Plugins.install_plugin_updates(nil)

      vim.notify = original_notify

      assert.equals(1, #notifications)
      assert.equals(vim.log.levels.ERROR, notifications[1].level)
    end)
  end)

  describe("get_plugin_updates", function()
    it("should call callback with empty result when config is nil", function()
      local result
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level, opts = opts })
      end

      Config._reset(nil)
      Plugins.get_plugin_updates(function(r)
        result = r
      end)

      vim.notify = original_notify

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
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level, opts)
        table.insert(notifications, { msg = msg, level = level, opts = opts })
      end

      Config._reset({ repo_path = "" })
      Plugins.get_plugin_updates(function(r)
        result = r
      end)

      vim.notify = original_notify

      assert.is_table(result)
      assert.equals(0, #result.all_updates)
      assert.equals(0, #result.plugins_behind)
      assert.equals(0, #result.plugins_ahead)
    end)

    it("should call callback with empty result when lockfile does not exist", function()
      local result

      Plugins.get_plugin_updates(function(r)
        result = r
      end)

      assert.is_table(result)
      assert.equals(0, #result.all_updates)
      assert.equals(0, #result.plugins_behind)
      assert.equals(0, #result.plugins_ahead)
    end)

    it("should return result with proper structure", function()
      local result

      Plugins.get_plugin_updates(function(r)
        result = r
      end)

      assert.is_table(result)
      assert.is_not_nil(result.all_updates)
      assert.is_not_nil(result.plugins_behind)
      assert.is_not_nil(result.plugins_ahead)
    end)
  end)
end)
