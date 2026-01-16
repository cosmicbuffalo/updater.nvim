local UI = require("updater.ui")
local Constants = require("updater.constants")

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
      plugin_updates = {},
      remote_commits = {},
      commits = {},
      commits_in_branch = {},
      log_type = "local",
      recently_updated_dotfiles = false,
      recently_updated_plugins = false,
      loading_spinner_frame = 1,
      current_commit = "abc1234",
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
    }
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
  end)

  describe("generate_keybindings", function()
    it("should return keybinding lines", function()
      local keybindings = UI.generate_keybindings(test_config)

      assert.is_table(keybindings)
      assert.is_true(#keybindings > 0)
    end)

    it("should include all keymaps", function()
      local keybindings = UI.generate_keybindings(test_config)
      local text = table.concat(keybindings, "\n")

      assert.is_truthy(text:match("U"))
      assert.is_truthy(text:match("u"))
      assert.is_truthy(text:match("i"))
      assert.is_truthy(text:match("r"))
      assert.is_truthy(text:match("q"))
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
    it("should return empty table when no plugin updates", function()
      test_state.plugin_updates = {}
      local section = UI.generate_plugin_updates_section(test_state)

      assert.is_table(section)
      assert.equals(0, #section)
    end)

    it("should include plugin info when updates available", function()
      test_state.plugin_updates = {
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
  end)
end)
