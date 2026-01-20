local Errors = require("updater.errors")

describe("errors module", function()
  describe("timeout_error", function()
    it("should format timeout error message", function()
      local msg = Errors.timeout_error("Git fetch", 30)
      assert.equals("Git fetch timed out after 30 seconds", msg)
    end)

    it("should handle different operation names", function()
      local msg = Errors.timeout_error("Pull operation", 60)
      assert.equals("Pull operation timed out after 60 seconds", msg)
    end)
  end)

  describe("notify_error", function()
    it("should call vim.notify with formatted message", function()
      local captured = _G.test_helpers.capture_notifications()

      Errors.notify_error("Connection failed", nil, "Network check")

      captured.restore()

      assert.equals(1, #captured.notifications)
      assert.is_truthy(captured.notifications[1].msg:match("Network check failed"))
      assert.is_truthy(captured.notifications[1].msg:match("Connection failed"))
      assert.equals(vim.log.levels.ERROR, captured.notifications[1].level)
    end)

    it("should use default operation name when not provided", function()
      local captured = _G.test_helpers.capture_notifications()

      Errors.notify_error("Something went wrong", nil, nil)

      captured.restore()

      assert.equals(1, #captured.notifications)
      assert.is_truthy(captured.notifications[1].msg:match("Operation failed"))
    end)

    it("should use config title when provided", function()
      local captured = _G.test_helpers.capture_notifications()

      local config = {
        notify = {
          error = {
            title = "Custom Error Title",
          },
        },
      }

      Errors.notify_error("Test error", config, "Test op")

      captured.restore()

      assert.equals(1, #captured.notifications)
      assert.equals("Custom Error Title", captured.notifications[1].opts.title)
    end)

    it("should use default title when config not provided", function()
      local captured = _G.test_helpers.capture_notifications()

      Errors.notify_error("Test error", nil, "Test op")

      captured.restore()

      assert.equals(1, #captured.notifications)
      assert.equals("Updater Error", captured.notifications[1].opts.title)
    end)
  end)
end)
