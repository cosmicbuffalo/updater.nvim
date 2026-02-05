local Status = require("updater.status")

describe("status module", function()
  before_each(function()
    -- Reset state before each test
    Status.state.is_open = false
    Status.state.buffer = nil
    Status.state.window = nil
    Status.state.is_initial_load = false
    Status.state.is_updating = false
    Status.state.is_refreshing = false
    Status.state.is_installing_plugins = false
    Status.state.current_branch = "Loading..."
    Status.state.current_commit = nil
    Status.state.ahead_count = 0
    Status.state.behind_count = 0
    Status.state.needs_update = false
    Status.state.last_check_time = nil
    Status.state.commits = {}
    Status.state.remote_commits = {}
    Status.state.commits_in_branch = {}
    Status.state.log_type = "local"
    Status.state.plugin_updates = {}
    Status.state.plugins_behind = {}
    Status.state.plugins_ahead = {}
    Status.state.has_plugin_updates = false
    Status.state.has_plugins_behind = false
    Status.state.has_plugins_ahead = false
    Status.state.recently_updated_dotfiles = false
    Status.state.recently_updated_plugins = false
    Status.state.loading_spinner_timer = nil
    Status.state.loading_spinner_frame = 1
    Status.state.periodic_timer = nil
    Status.state.debug_enabled = false
    Status.state.debug_simulate_dotfiles = 0
    Status.state.debug_simulate_plugins = 0
  end)

  describe("has_cached_data", function()
    it("should return false when last_check_time is nil", function()
      Status.state.last_check_time = nil
      assert.is_false(Status.has_cached_data())
    end)

    it("should return true when last_check_time is set", function()
      Status.state.last_check_time = os.time()
      assert.is_true(Status.has_cached_data())
    end)
  end)

  describe("has_updates", function()
    it("should return false when no updates available", function()
      Status.state.needs_update = false
      Status.state.has_plugin_updates = false
      assert.is_false(Status.has_updates())
    end)

    it("should return true when dotfile updates available", function()
      Status.state.needs_update = true
      Status.state.has_plugin_updates = false
      assert.is_true(Status.has_updates())
    end)

    it("should return true when plugin updates available", function()
      Status.state.needs_update = false
      Status.state.has_plugin_updates = true
      assert.is_true(Status.has_updates())
    end)

    it("should return true when both updates available", function()
      Status.state.needs_update = true
      Status.state.has_plugin_updates = true
      assert.is_true(Status.has_updates())
    end)
  end)

  describe("has_recent_updates", function()
    it("should return false when no recent updates", function()
      Status.state.recently_updated_dotfiles = false
      Status.state.recently_updated_plugins = false
      assert.is_false(Status.has_recent_updates())
    end)

    it("should return true when dotfiles recently updated", function()
      Status.state.recently_updated_dotfiles = true
      Status.state.recently_updated_plugins = false
      assert.is_true(Status.has_recent_updates())
    end)

    it("should return true when plugins recently updated", function()
      Status.state.recently_updated_dotfiles = false
      Status.state.recently_updated_plugins = true
      assert.is_true(Status.has_recent_updates())
    end)

    it("should return true when both recently updated", function()
      Status.state.recently_updated_dotfiles = true
      Status.state.recently_updated_plugins = true
      assert.is_true(Status.has_recent_updates())
    end)
  end)

  describe("clear_recent_updates", function()
    it("should clear recent update flags", function()
      Status.state.recently_updated_dotfiles = true
      Status.state.recently_updated_plugins = true

      Status.clear_recent_updates()

      assert.is_false(Status.state.recently_updated_dotfiles)
      assert.is_false(Status.state.recently_updated_plugins)
    end)
  end)

  describe("get", function()
    it("should return current status", function()
      Status.state.needs_update = true
      Status.state.behind_count = 5
      Status.state.ahead_count = 2
      Status.state.has_plugin_updates = true
      Status.state.plugin_updates = { { name = "test" }, { name = "test2" } }
      Status.state.current_branch = "main"
      Status.state.last_check_time = 12345
      Status.state.is_updating = false
      Status.state.is_installing_plugins = false
      Status.state.is_refreshing = true

      local status = Status.get()

      assert.equals(true, status.needs_update)
      assert.equals(5, status.behind_count)
      assert.equals(2, status.ahead_count)
      assert.equals(true, status.has_plugin_updates)
      assert.equals(2, status.plugin_update_count)
      assert.equals("main", status.current_branch)
      assert.equals(12345, status.last_check_time)
      assert.equals(false, status.is_updating)
      assert.equals(false, status.is_installing_plugins)
      assert.equals(true, status.is_refreshing)
    end)
  end)

  describe("get_update_count", function()
    it("should return 0 when no updates", function()
      Status.state.needs_update = false
      Status.state.has_plugins_behind = false
      assert.equals(0, Status.get_update_count())
    end)

    it("should return behind_count when dotfile updates available", function()
      Status.state.needs_update = true
      Status.state.behind_count = 3
      Status.state.has_plugins_behind = false
      assert.equals(3, Status.get_update_count())
    end)

    it("should return plugin count when plugins are behind", function()
      Status.state.needs_update = false
      Status.state.has_plugins_behind = true
      Status.state.plugins_behind = { { name = "a" }, { name = "b" } }
      assert.equals(2, Status.get_update_count())
    end)

    it("should return combined count when both updates available", function()
      Status.state.needs_update = true
      Status.state.behind_count = 3
      Status.state.has_plugins_behind = true
      Status.state.plugins_behind = { { name = "a" }, { name = "b" } }
      assert.equals(5, Status.get_update_count())
    end)

    it("should not count plugins ahead in update count", function()
      Status.state.needs_update = false
      Status.state.has_plugins_behind = false
      Status.state.has_plugins_ahead = true
      Status.state.plugins_ahead = { { name = "a" } }
      assert.equals(0, Status.get_update_count())
    end)
  end)

  describe("get_update_text", function()
    it("should return empty string when no updates", function()
      Status.state.needs_update = false
      Status.state.has_plugins_behind = false
      assert.equals("", Status.get_update_text())
    end)

    it("should return dotfile text in default format", function()
      Status.state.needs_update = true
      Status.state.behind_count = 1
      Status.state.has_plugins_behind = false
      assert.equals("1 dotfile update", Status.get_update_text())
    end)

    it("should pluralize dotfiles correctly", function()
      Status.state.needs_update = true
      Status.state.behind_count = 3
      Status.state.has_plugins_behind = false
      assert.equals("3 dotfiles updates", Status.get_update_text())
    end)

    it("should return plugin text in default format", function()
      Status.state.needs_update = false
      Status.state.has_plugins_behind = true
      Status.state.plugins_behind = { { name = "test" } }
      assert.equals("1 plugin update", Status.get_update_text())
    end)

    it("should pluralize plugins correctly", function()
      Status.state.needs_update = false
      Status.state.has_plugins_behind = true
      Status.state.plugins_behind = { { name = "a" }, { name = "b" } }
      assert.equals("2 plugins updates", Status.get_update_text())
    end)

    it("should combine dotfiles and plugins", function()
      Status.state.needs_update = true
      Status.state.behind_count = 2
      Status.state.has_plugins_behind = true
      Status.state.plugins_behind = { { name = "a" } }
      assert.equals("2 dotfiles, 1 plugin updates", Status.get_update_text())
    end)

    it("should return short format", function()
      Status.state.needs_update = true
      Status.state.behind_count = 2
      Status.state.has_plugins_behind = true
      Status.state.plugins_behind = { { name = "a" } }
      assert.equals("2d 1p", Status.get_update_text("short"))
    end)

    it("should return icon format", function()
      Status.state.needs_update = true
      Status.state.behind_count = 2
      Status.state.has_plugins_behind = true
      Status.state.plugins_behind = { { name = "a" } }
      local text = Status.get_update_text("icon")
      assert.is_truthy(text:match("2"))
      assert.is_truthy(text:match("1"))
    end)
  end)

  describe("stop_periodic_timer", function()
    it("should handle nil timer gracefully", function()
      Status.state.periodic_timer = nil
      -- Should not error
      Status.stop_periodic_timer()
      assert.is_nil(Status.state.periodic_timer)
    end)

    it("should stop and close timer", function()
      local timer = vim.uv.new_timer()
      Status.state.periodic_timer = timer

      Status.stop_periodic_timer()

      assert.is_nil(Status.state.periodic_timer)
    end)
  end)

  describe("state", function()
    it("should expose state object", function()
      assert.is_not_nil(Status.state)
      assert.is_table(Status.state)
    end)

    it("should have all expected state fields", function()
      assert.is_not_nil(Status.state.is_open)
      assert.is_not_nil(Status.state.current_branch)
      assert.is_not_nil(Status.state.needs_update)
      assert.is_not_nil(Status.state.plugin_updates)
    end)
  end)
end)
