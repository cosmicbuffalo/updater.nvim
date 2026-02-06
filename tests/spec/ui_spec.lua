local UI = require("updater.ui")
local Constants = require("updater.constants")
local Status = require("updater.status")

describe("ui module", function()
  local test_state
  local test_config

  before_each(function()
    test_state = {
      current_branch = "main",
      ahead_count = 0,
      behind_count = 0,
      is_updating = false,
      is_refreshing = false,
      is_installing_plugins = false,
      has_plugin_updates = false,
      has_plugins_behind = false,
      has_plugins_ahead = false,
      plugin_updates = {},
      plugins_behind = {},
      plugins_ahead = {},
      remote_commits = {},
      commits = {},
      commits_in_branch = {},
      log_type = "local",
      recently_updated_dotfiles = false,
      recently_updated_plugins = false,
      loading_spinner_frame = 1,
      current_commit = "abc1234",
      -- Versioned releases mode state
      current_release = nil,
      latest_remote_release = nil,
      has_new_release = false,
      commits_since_release = 0,
      commits_since_release_list = {},
      releases_since_current = {},
      releases_before_current = {},
      is_detached_head = false,
      current_tag = nil,
      is_switching_version = false,
      switching_to_version = nil,
      recently_switched_to = nil,
      switched_from_version = nil,
      window_width = 80,
      expanded_releases = {},
      github_releases = {},
    }

    test_config = {
      main_branch = "main",
      keymap = {
        update_all = "U",
        update = "u",
        install_plugins = "i",
        refresh = "r",
        close = "q",
      },
      versioned_releases_only = false,
    }

    -- Reset Status module state for release expansion checks
    Status.state.expanded_releases = {}
    Status.state.github_releases = {}
  end)

  describe("get_loading_spinner", function()
    it("should return a spinner frame", function()
      test_state.loading_spinner_frame = 1
      local frame = UI.get_loading_spinner(test_state)

      assert.is_string(frame)
      assert.equals(Constants.SPINNER_FRAMES[1], frame)
    end)

    it("should return correct frame for different indices", function()
      test_state.loading_spinner_frame = 5
      local frame = UI.get_loading_spinner(test_state)

      assert.equals(Constants.SPINNER_FRAMES[5], frame)
    end)

    it("should default to first frame for invalid index", function()
      test_state.loading_spinner_frame = 999
      local frame = UI.get_loading_spinner(test_state)

      assert.equals(Constants.SPINNER_FRAMES[1], frame)
    end)
  end)

  describe("generate_header", function()
    it("should return a table of lines", function()
      local header = UI.generate_header(test_state, test_config)

      assert.is_table(header)
      assert.is_true(#header > 0)
    end)

    it("should include branch name", function()
      test_state.current_branch = "feature-branch"
      local header = UI.generate_header(test_state, test_config)

      local found = false
      for _, line in ipairs(header) do
        if line:match("feature%-branch") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("should show up to date message when no updates", function()
      test_state.behind_count = 0
      test_state.has_plugin_updates = false
      local header = UI.generate_header(test_state, test_config)

      local found = false
      for _, line in ipairs(header) do
        if line:match("up to date") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("should show updates available when behind", function()
      test_state.behind_count = 5
      local header = UI.generate_header(test_state, test_config)

      local found = false
      for _, line in ipairs(header) do
        if line:match("available") or line:match("behind") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("should show updating message when is_updating", function()
      test_state.is_updating = true
      local header = UI.generate_header(test_state, test_config)

      local found = false
      for _, line in ipairs(header) do
        if line:match("Updating") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("should show refreshing message when is_refreshing", function()
      test_state.is_refreshing = true
      local header = UI.generate_header(test_state, test_config)

      local found = false
      for _, line in ipairs(header) do
        if line:match("Checking") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("should show 'Seeing what's new on main' on non-main branch when refreshing", function()
      test_state.current_branch = "feature-branch"
      test_state.is_refreshing = true
      test_state.is_initial_load = true
      local header = UI.generate_header(test_state, test_config)

      local found = false
      for _, line in ipairs(header) do
        if line:match("Seeing what's new on main") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("should show different up-to-date message on non-main branch", function()
      test_state.current_branch = "feature-branch"
      test_state.behind_count = 0
      test_state.has_plugin_updates = false
      local header = UI.generate_header(test_state, test_config)

      local found = false
      for _, line in ipairs(header) do
        if line:match("up to date with the latest commits on main") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("generate_keybindings", function()
    it("should return keybinding lines and keybind_data", function()
      -- On main branch with updates available
      test_state.current_branch = "main"
      test_state.behind_count = 1
      test_state.has_plugins_behind = true
      test_state.plugins_behind = { { name = "test" } }

      local keybindings, keybind_data = UI.generate_keybindings(test_state, test_config)

      assert.is_table(keybindings)
      assert.is_true(#keybindings > 0)
      assert.is_table(keybind_data)
      assert.is_true(#keybind_data > 0)
    end)

    it("should include all keymaps on main branch with updates", function()
      test_state.current_branch = "main"
      test_state.behind_count = 1
      test_state.has_plugins_behind = true
      test_state.plugins_behind = { { name = "test" } }

      local keybindings, _ = UI.generate_keybindings(test_state, test_config)
      local text = table.concat(keybindings, "\n")

      assert.is_truthy(text:match("U"))
      assert.is_truthy(text:match("u"))
      assert.is_truthy(text:match("i"))
      assert.is_truthy(text:match("r"))
      assert.is_truthy(text:match("q"))
    end)

    it("should hide U keybind on non-main branch", function()
      test_state.current_branch = "feature-branch"
      test_state.behind_count = 1
      test_state.has_plugins_behind = true
      test_state.plugins_behind = { { name = "test" } }

      local keybindings, _ = UI.generate_keybindings(test_state, test_config)
      local text = table.concat(keybindings, "\n")

      assert.is_falsy(text:match("Update dotfiles %+ install plugin updates"))
      assert.is_truthy(text:match("Pull latest main into branch"))
    end)

    it("should hide u keybind when behind_count is 0", function()
      test_state.current_branch = "main"
      test_state.behind_count = 0
      test_state.has_plugins_behind = false
      test_state.has_plugins_ahead = false

      local keybindings, keybind_data = UI.generate_keybindings(test_state, test_config)
      local text = table.concat(keybindings, "\n")

      -- Only r and q should be present (no U, u, or i)
      -- Use a more specific pattern - "u - Update" to match the u keybind line specifically
      assert.is_falsy(text:match("u %- Update dotfiles$"))
      assert.is_truthy(text:match("Refresh"))
      assert.is_truthy(text:match("Close"))
      assert.equals(2, #keybind_data) -- Only r and q
    end)

    it("should hide i keybind when no plugin differences", function()
      test_state.current_branch = "main"
      test_state.behind_count = 1
      test_state.has_plugins_behind = false
      test_state.has_plugins_ahead = false

      local keybindings, _ = UI.generate_keybindings(test_state, test_config)
      local text = table.concat(keybindings, "\n")

      assert.is_falsy(text:match("Install plugin updates"))
      assert.is_falsy(text:match("Update/Downgrade plugins"))
    end)

    it("should always show r and q keybinds", function()
      test_state.current_branch = "feature-branch"
      test_state.behind_count = 0
      test_state.has_plugins_behind = false
      test_state.has_plugins_ahead = false

      local keybindings, keybind_data = UI.generate_keybindings(test_state, test_config)
      local text = table.concat(keybindings, "\n")

      assert.is_truthy(text:match("r"))
      assert.is_truthy(text:match("q"))
      assert.equals(2, #keybind_data)
    end)

    it("should show 'Update/Downgrade plugins' when plugins are ahead", function()
      test_state.current_branch = "main"
      test_state.behind_count = 0
      test_state.has_plugins_behind = false
      test_state.has_plugins_ahead = true
      test_state.plugins_ahead = { { name = "test-ahead" } }

      local keybindings, _ = UI.generate_keybindings(test_state, test_config)
      local text = table.concat(keybindings, "\n")

      assert.is_truthy(text:match("Update/Downgrade plugins"))
    end)

    it("should show 'Install plugin updates' when only plugins behind", function()
      test_state.current_branch = "main"
      test_state.behind_count = 0
      test_state.has_plugins_behind = true
      test_state.has_plugins_ahead = false
      test_state.plugins_behind = { { name = "test-behind" } }

      local keybindings, _ = UI.generate_keybindings(test_state, test_config)
      local text = table.concat(keybindings, "\n")

      assert.is_truthy(text:match("Install plugin updates"))
      assert.is_falsy(text:match("Update/Downgrade"))
    end)

    it("should show i keybind on non-main branch when plugins have differences", function()
      test_state.current_branch = "feature-branch"
      test_state.behind_count = 0
      test_state.has_plugins_behind = true
      test_state.plugins_behind = { { name = "test" } }

      local keybindings, keybind_data = UI.generate_keybindings(test_state, test_config)
      local text = table.concat(keybindings, "\n")

      -- Should show i keybind even on non-main branch
      assert.is_truthy(text:match("i %- Install plugin updates"))
      -- Should have i, r, q in keybind_data (no U or u since behind_count is 0)
      assert.equals(3, #keybind_data)
    end)
  end)

  describe("generate_remote_commits_section", function()
    it("should return empty table when no remote commits", function()
      test_state.remote_commits = {}
      local section = UI.generate_remote_commits_section(test_state, test_config)

      assert.is_table(section)
      assert.equals(0, #section)
    end)

    it("should include commits when available", function()
      test_state.remote_commits = {
        { hash = "abc1234", message = "Test commit", author = "Test", date = "today" },
      }
      test_state.commits_in_branch = {}
      local section = UI.generate_remote_commits_section(test_state, test_config)

      assert.is_table(section)
      assert.is_true(#section > 0)

      local text = table.concat(section, "\n")
      assert.is_truthy(text:match("abc1234"))
      assert.is_truthy(text:match("Test commit"))
    end)
  end)

  describe("generate_plugin_updates_section", function()
    it("should return empty table when no plugins behind", function()
      test_state.plugins_behind = {}
      local section = UI.generate_plugin_updates_section(test_state)

      assert.is_table(section)
      assert.equals(0, #section)
    end)

    it("should include plugin info when plugins are behind", function()
      test_state.plugins_behind = {
        { name = "test-plugin", installed_commit = "old123", lockfile_commit = "new456", branch = "main" },
      }
      local section = UI.generate_plugin_updates_section(test_state)

      assert.is_table(section)
      assert.is_true(#section > 0)

      local text = table.concat(section, "\n")
      assert.is_truthy(text:match("test%-plugin"))
      assert.is_truthy(text:match("old123"))
      assert.is_truthy(text:match("new456"))
    end)
  end)

  describe("generate_plugins_ahead_section", function()
    it("should return empty table when no plugins ahead", function()
      test_state.plugins_ahead = {}
      local section = UI.generate_plugins_ahead_section(test_state)

      assert.is_table(section)
      assert.equals(0, #section)
    end)

    it("should include plugin info when plugins are ahead of lockfile", function()
      test_state.plugins_ahead = {
        { name = "telescope.nvim", installed_commit = "new789", lockfile_commit = "old456", branch = "main" },
      }
      local section = UI.generate_plugins_ahead_section(test_state)

      assert.is_table(section)
      assert.is_true(#section > 0)

      local text = table.concat(section, "\n")
      assert.is_truthy(text:match("telescope%.nvim"))
      assert.is_truthy(text:match("old456"))
      assert.is_truthy(text:match("new789"))
      assert.is_truthy(text:match("Plugins ahead of lockfile"))
    end)

    it("should show reversed arrow for ahead plugins", function()
      test_state.plugins_ahead = {
        { name = "plugin", installed_commit = "new123", lockfile_commit = "old456", branch = "main" },
      }
      local section = UI.generate_plugins_ahead_section(test_state)
      local text = table.concat(section, "\n")

      -- The format should be: lockfile <- installed (reversed arrow)
      assert.is_truthy(text:match("old456 ← new123"))
    end)
  end)

  describe("generate_restart_reminder_section", function()
    it("should return empty table when no recent updates", function()
      test_state.recently_updated_dotfiles = false
      test_state.recently_updated_plugins = false
      local section = UI.generate_restart_reminder_section(test_state)

      assert.is_table(section)
      assert.equals(0, #section)
    end)

    it("should show reminder when dotfiles recently updated", function()
      test_state.recently_updated_dotfiles = true
      local section = UI.generate_restart_reminder_section(test_state)

      assert.is_table(section)
      assert.is_true(#section > 0)

      local text = table.concat(section, "\n")
      assert.is_truthy(text:match("Restart Recommended"))
      assert.is_truthy(text:match("Dotfiles have been updated"))
    end)

    it("should show reminder when plugins recently updated", function()
      test_state.recently_updated_plugins = true
      local section = UI.generate_restart_reminder_section(test_state)

      assert.is_table(section)
      assert.is_true(#section > 0)

      local text = table.concat(section, "\n")
      assert.is_truthy(text:match("Restart Recommended"))
      assert.is_truthy(text:match("Plugins have been updated"))
    end)
  end)

  describe("generate_commit_log", function()
    it("should return commit log lines", function()
      test_state.commits = {
        { hash = "abc1234", message = "First commit", author = "Dev", date = "yesterday" },
        { hash = "def5678", message = "Second commit", author = "Dev", date = "today" },
      }
      local log = UI.generate_commit_log(test_state, test_config)

      assert.is_table(log)
      assert.is_true(#log > 0)

      local text = table.concat(log, "\n")
      assert.is_truthy(text:match("abc1234"))
      assert.is_truthy(text:match("def5678"))
    end)

    it("should show local commits title for local log_type", function()
      test_state.log_type = "local"
      test_state.commits = {
        { hash = "abc1234", message = "Commit", author = "Dev", date = "today" },
      }
      local log = UI.generate_commit_log(test_state, test_config)

      local text = table.concat(log, "\n")
      assert.is_truthy(text:match("Local commits"))
    end)

    it("should show remote commits title for remote log_type", function()
      test_state.log_type = "remote"
      test_state.commits = {
        { hash = "abc1234", message = "Commit", author = "Dev", date = "today" },
      }
      local log = UI.generate_commit_log(test_state, test_config)

      local text = table.concat(log, "\n")
      assert.is_truthy(text:match("origin/main"))
    end)
  end)

  describe("generate_loading_state", function()
    it("should return loading state lines", function()
      local lines = UI.generate_loading_state(test_state, test_config)

      assert.is_table(lines)
      assert.is_true(#lines > 0)
    end)

    it("should include loading message", function()
      local lines = UI.generate_loading_state(test_state, test_config)

      local text = table.concat(lines, "\n")
      assert.is_truthy(text:match("Checking") or text:match("Loading"))
    end)

    it("should include keybindings", function()
      local lines = UI.generate_loading_state(test_state, test_config)

      local text = table.concat(lines, "\n")
      assert.is_truthy(text:match("Keybindings"))
    end)

    it("should show 'Seeing what's new on main' on non-main branch", function()
      test_state.current_branch = "feature-branch"
      local lines = UI.generate_loading_state(test_state, test_config)

      local text = table.concat(lines, "\n")
      assert.is_truthy(text:match("Seeing what's new on main"))
    end)

    it("should only show close keybind during loading", function()
      local lines = UI.generate_loading_state(test_state, test_config)

      local text = table.concat(lines, "\n")
      assert.is_truthy(text:match("Close window"))
      -- Should not show other keybinds during loading
      assert.is_falsy(text:match("Update dotfiles"))
      assert.is_falsy(text:match("Refresh status"))
    end)
  end)

  describe("versioned_releases_only mode", function()
    before_each(function()
      test_config.versioned_releases_only = true
      test_state.current_release = "v1.0.0"
      test_state.latest_remote_release = "v1.1.0"
      test_state.has_new_release = true
      test_state.releases_since_current = {
        { tag = "v1.1.0", hash = "abc1234" },
      }
      test_state.releases_before_current = {
        { tag = "v0.9.0", hash = "def5678" },
      }
      test_state.release_commit = { hash = "ghi9012", message = "Release v1.0.0", author = "dev" }
    end)

    describe("generate_release_header", function()
      it("should return header lines", function()
        local header, status_messages, status_lines_start = UI.generate_release_header(test_state, test_config)

        assert.is_table(header)
        assert.is_true(#header > 0)
        assert.is_table(status_messages)
        assert.is_number(status_lines_start)
      end)

      it("should include branch info", function()
        local header = UI.generate_release_header(test_state, test_config)
        local text = table.concat(header, "\n")

        assert.is_truthy(text:match("Branch"))
      end)

      it("should show detached HEAD when on tag", function()
        test_state.is_detached_head = true
        test_state.current_tag = "v1.0.0"
        local header = UI.generate_release_header(test_state, test_config)
        local text = table.concat(header, "\n")

        assert.is_truthy(text:match("detached HEAD"))
        assert.is_truthy(text:match("v1%.0%.0"))
      end)
    end)

    describe("generate_release_keybindings", function()
      it("should return keybinding lines", function()
        local keybindings, keybind_data = UI.generate_release_keybindings(test_state, test_config)

        assert.is_table(keybindings)
        assert.is_true(#keybindings > 0)
        assert.is_table(keybind_data)
      end)

      it("should include release-specific keybinds", function()
        local keybindings = UI.generate_release_keybindings(test_state, test_config)
        local text = table.concat(keybindings, "\n")

        assert.is_truthy(text:match("Toggle release details"))
        assert.is_truthy(text:match("Switch to release"))
        assert.is_truthy(text:match("Copy"))
      end)

      it("should include close and refresh keybinds", function()
        local keybindings = UI.generate_release_keybindings(test_state, test_config)
        local text = table.concat(keybindings, "\n")

        assert.is_truthy(text:match("Close"))
        assert.is_truthy(text:match("Check for new releases"))
      end)
    end)

    describe("generate_current_release_section", function()
      it("should return lines and release_lines mapping", function()
        local lines, release_lines = UI.generate_current_release_section(test_state, test_config)

        assert.is_table(lines)
        assert.is_table(release_lines)
      end)

      it("should include current release section when release exists", function()
        local lines = UI.generate_current_release_section(test_state, test_config)
        local text = table.concat(lines, "\n")

        assert.is_truthy(text:match("Current release"))
        assert.is_truthy(text:match("v1%.0%.0"))
      end)

      it("should return empty when no current release", function()
        test_state.current_release = nil
        local lines = UI.generate_current_release_section(test_state, test_config)

        assert.equals(0, #lines)
      end)
    end)

    describe("generate_releases_since_section", function()
      it("should include releases since current", function()
        local lines = UI.generate_releases_since_section(test_state, test_config)
        local text = table.concat(lines, "\n")

        assert.is_truthy(text:match("v1%.1%.0"))
      end)

      it("should show section title with current release", function()
        local lines = UI.generate_releases_since_section(test_state, test_config)
        local text = table.concat(lines, "\n")

        assert.is_truthy(text:match("Releases since v1%.0%.0"))
      end)
    end)

    describe("generate_previous_releases_section", function()
      it("should include previous releases", function()
        local lines = UI.generate_previous_releases_section(test_state, test_config)
        local text = table.concat(lines, "\n")

        assert.is_truthy(text:match("v0%.9%.0"))
      end)

      it("should show section title", function()
        local lines = UI.generate_previous_releases_section(test_state, test_config)
        local text = table.concat(lines, "\n")

        assert.is_truthy(text:match("Previous releases"))
      end)
    end)

    describe("generate_commits_since_release_section", function()
      it("should return empty when no commits since release", function()
        test_state.commits_since_release_list = {}
        local lines = UI.generate_commits_since_release_section(test_state, test_config)

        assert.equals(0, #lines)
      end)

      it("should show commits when on a non-tag commit", function()
        test_state.current_tag = nil
        test_state.commits_since_release_list = {
          { hash = "abc1234", message = "Fix bug", author = "dev" },
          { hash = "def5678", message = "Add feature", author = "dev2" },
        }
        local lines, commit_lines = UI.generate_commits_since_release_section(test_state, test_config)
        local text = table.concat(lines, "\n")

        assert.is_truthy(text:match("Commits since"))
        assert.is_truthy(text:match("abc1234"))
        assert.is_truthy(text:match("Fix bug"))
      end)

      it("should include author in commit lines", function()
        test_state.current_tag = nil
        test_state.commits_since_release_list = {
          { hash = "abc1234", message = "Fix bug", author = "testdev" },
        }
        local lines = UI.generate_commits_since_release_section(test_state, test_config)
        local text = table.concat(lines, "\n")

        assert.is_truthy(text:match("by testdev"))
      end)
    end)
  end)
end)
