local Operations = require("updater.operations")
local Status = require("updater.status")
local Config = require("updater.config")
local Git = require("updater.git")

describe("operations module", function()
  local test_dir

  before_each(function()
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    -- Initialize a git repo
    vim.fn.system(
      "cd "
        .. vim.fn.shellescape(test_dir)
        .. " && git init && git config user.email 'test@test.com' && git config user.name 'Test' && touch test.txt && git add . && git commit -m 'Initial commit'"
    )

    Config._reset({
      repo_path = test_dir,
      main_branch = "main",
      log_count = 15,
      timeouts = {
        fetch = 30,
        pull = 30,
        merge = 30,
        log = 15,
        status = 10,
        default = 20,
      },
      notify = {
        timeout = { title = "Timeout" },
        error = { title = "Error" },
        updated = { title = "Updated" },
        outdated = { title = "Outdated" },
      },
      git = {
        rebase = true,
        autostash = true,
      },
    })

    -- Reset status state
    Status.state.is_refreshing = false
    Status.state.is_updating = false
    Status.state.is_installing_plugins = false
    Status.state.needs_update = false
    Status.state.has_plugin_updates = false
    Status.state.current_branch = "Loading..."
    Status.state.ahead_count = 0
    Status.state.behind_count = 0
    Status.state.last_check_time = nil
    Status.state.debug_enabled = false
    Status.state.is_open = false

    Git.clear_validation_cache()
  end)

  after_each(function()
    vim.fn.delete(test_dir, "rf")
    Config._reset(nil)
    Git.clear_validation_cache()
  end)

  describe("check_updates_silent", function()
    it("should update status state after checking", function()
      local done = false

      Operations.check_updates_silent(function(_)
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 10)

      -- Should have updated the state
      assert.is_not_nil(Status.state.last_check_time)
      assert.is_not_nil(Status.state.current_branch)
    end)

    it("should call callback with result", function()
      local done = false
      local result = nil

      Operations.check_updates_silent(function(has_updates)
        result = has_updates
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 10)

      -- Result should be a boolean
      assert.is_boolean(result)
    end)

    it("should work without callback", function()
      -- Should not error when callback is nil
      Operations.check_updates_silent(nil)

      -- Wait a bit for async operation
      vim.wait(500, function()
        return Status.state.last_check_time ~= nil
      end, 10)
    end)

    it("should use debug mode when enabled", function()
      Status.state.debug_enabled = true
      Status.state.debug_simulate_dotfiles = 2
      Status.state.debug_simulate_plugins = 1

      local done = false
      local result = nil

      Operations.check_updates_silent(function(has_updates)
        result = has_updates
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 10)

      -- Debug mode should simulate updates
      assert.is_true(result)
      assert.equals(2, Status.state.behind_count)
    end)
  end)

  describe("refresh", function()
    it("should set is_refreshing during operation", function()
      local refresh_started = false

      -- Check state after a small delay
      vim.defer_fn(function()
        refresh_started = Status.state.is_refreshing
      end, 150)

      Operations.refresh(function() end)

      vim.wait(2000, function()
        return refresh_started or not Status.state.is_refreshing
      end, 10)
    end)

    it("should call render callback", function()
      local callback_called = false

      local render_callback = function(_)
        callback_called = true
      end

      -- Render callback only fires when is_open is true
      Status.state.is_open = true

      Operations.refresh(render_callback)

      -- Wait for operation to complete
      vim.wait(5000, function()
        return not Status.state.is_refreshing
      end, 10)

      -- Give a bit more time for callbacks
      vim.wait(200, function()
        return callback_called
      end, 10)

      assert.is_true(callback_called)
    end)
  end)
end)
