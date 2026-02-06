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

  describe("clear_recent_updates", function()
    it("should clear recent update flags", function()
      Status.state.recently_updated_dotfiles = true
      Status.state.recently_updated_plugins = true

      Status.clear_recent_updates()

      assert.is_false(Status.state.recently_updated_dotfiles)
      assert.is_false(Status.state.recently_updated_plugins)
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

    it("should have version tracking state fields", function()
      assert.is_not_nil(Status.state.expanded_releases)
      assert.is_not_nil(Status.state.release_details_cache)
      assert.is_not_nil(Status.state.fetching_release_details)
      assert.is_not_nil(Status.state.github_releases)
    end)
  end)

  describe("version tracking helpers", function()
    before_each(function()
      Status.state.current_tag = nil
    end)

    describe("get_version_display", function()
      it("should return nil when no current tag", function()
        Status.state.current_tag = nil
        assert.is_nil(Status.get_version_display())
      end)

      it("should return current_tag when on a tag", function()
        Status.state.current_tag = "v1.2.0"
        assert.equals("v1.2.0", Status.get_version_display())
      end)
    end)
  end)

  describe("release expansion helpers", function()
    before_each(function()
      Status.state.expanded_releases = {}
      Status.state.release_details_cache = {}
      Status.state.fetching_release_details = {}
    end)

    describe("is_release_expanded", function()
      it("should return false for non-expanded release", function()
        assert.is_false(Status.is_release_expanded("v1.0.0"))
      end)

      it("should return true for expanded release", function()
        Status.state.expanded_releases["v1.0.0"] = true
        assert.is_true(Status.is_release_expanded("v1.0.0"))
      end)
    end)

    describe("toggle_release_expansion", function()
      it("should expand a collapsed release", function()
        Status.toggle_release_expansion("v1.0.0")
        assert.is_true(Status.is_release_expanded("v1.0.0"))
      end)

      it("should collapse an expanded release", function()
        Status.state.expanded_releases["v1.0.0"] = true
        Status.toggle_release_expansion("v1.0.0")
        assert.is_false(Status.is_release_expanded("v1.0.0"))
      end)
    end)

    describe("release_details_cache", function()
      it("should get and set release details", function()
        local details = { commit = "abc123", date = "2024-01-01" }
        Status.set_release_details("v1.0.0", details)

        local retrieved = Status.get_release_details("v1.0.0")
        assert.equals("abc123", retrieved.commit)
        assert.equals("2024-01-01", retrieved.date)
      end)

      it("should return nil for uncached release", function()
        assert.is_nil(Status.get_release_details("v2.0.0"))
      end)
    end)

    describe("fetching_release_details", function()
      it("should track fetching state", function()
        assert.is_false(Status.is_fetching_release_details("v1.0.0"))

        Status.set_fetching_release_details("v1.0.0", true)
        assert.is_true(Status.is_fetching_release_details("v1.0.0"))

        Status.set_fetching_release_details("v1.0.0", false)
        assert.is_false(Status.is_fetching_release_details("v1.0.0"))
      end)
    end)
  end)

  describe("GitHub release helpers", function()
    before_each(function()
      Status.state.github_releases = {}
    end)

    describe("get_github_release", function()
      it("should return nil for unknown tag", function()
        assert.is_nil(Status.get_github_release("v1.0.0"))
      end)

      it("should return release data for known tag", function()
        Status.state.github_releases["v1.0.0"] = {
          name = "Release 1.0.0",
          body = "Release notes",
          prerelease = false,
        }

        local release = Status.get_github_release("v1.0.0")
        assert.equals("Release 1.0.0", release.name)
        assert.equals("Release notes", release.body)
        assert.is_false(release.prerelease)
      end)
    end)

    describe("is_prerelease", function()
      it("should return falsy for unknown tag", function()
        assert.is_falsy(Status.is_prerelease("v1.0.0"))
      end)

      it("should return false for non-prerelease", function()
        Status.state.github_releases["v1.0.0"] = { prerelease = false }
        assert.is_false(Status.is_prerelease("v1.0.0"))
      end)

      it("should return true for prerelease", function()
        Status.state.github_releases["v1.0.0-pre"] = { prerelease = true }
        assert.is_true(Status.is_prerelease("v1.0.0-pre"))
      end)
    end)

    describe("get_release_title", function()
      it("should return nil for unknown tag", function()
        assert.is_nil(Status.get_release_title("v1.0.0"))
      end)

      it("should return release name", function()
        Status.state.github_releases["v1.0.0"] = { name = "Version 1.0.0" }
        assert.equals("Version 1.0.0", Status.get_release_title("v1.0.0"))
      end)
    end)

    describe("get_release_body", function()
      it("should return nil for unknown tag", function()
        assert.is_nil(Status.get_release_body("v1.0.0"))
      end)

      it("should return release body", function()
        Status.state.github_releases["v1.0.0"] = { body = "# Changelog\n- Feature 1" }
        assert.equals("# Changelog\n- Feature 1", Status.get_release_body("v1.0.0"))
      end)
    end)
  end)
end)
