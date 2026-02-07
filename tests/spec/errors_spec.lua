local Errors = require("updater.errors")
local Config = require("updater.config")

describe("errors module", function()
  local original_notify

  before_each(function()
    original_notify = vim.notify
  end)

  after_each(function()
    vim.notify = original_notify
    Config._reset(nil)
  end)

  describe("notify_error", function()
    it("should call vim.notify with formatted message", function()
      local captured = {}
      vim.notify = function(msg, level, opts)
        table.insert(captured, { msg = msg, level = level, opts = opts })
      end

      Errors.notify_error("Connection failed", "Network check")

      assert.equals(1, #captured)
      assert.is_truthy(captured[1].msg:match("Network check failed"))
      assert.is_truthy(captured[1].msg:match("Connection failed"))
      assert.equals(vim.log.levels.ERROR, captured[1].level)
    end)

    it("should use default operation name when not provided", function()
      local captured = {}
      vim.notify = function(msg, level, opts)
        table.insert(captured, { msg = msg, level = level, opts = opts })
      end

      Errors.notify_error("Something went wrong", nil)

      assert.equals(1, #captured)
      assert.is_truthy(captured[1].msg:match("Operation failed"))
    end)

    it("should use config title when set", function()
      local captured = {}
      vim.notify = function(msg, level, opts)
        table.insert(captured, { msg = msg, level = level, opts = opts })
      end

      Config._reset({
        notify = {
          error = {
            title = "Custom Error Title",
          },
        },
      })

      Errors.notify_error("Test error", "Test op")

      assert.equals(1, #captured)
      assert.equals("Custom Error Title", captured[1].opts.title)
    end)

    it("should use default title when config not set", function()
      local captured = {}
      vim.notify = function(msg, level, opts)
        table.insert(captured, { msg = msg, level = level, opts = opts })
      end

      Errors.notify_error("Test error", "Test op")

      assert.equals(1, #captured)
      assert.equals("Updater Error", captured[1].opts.title)
    end)
  end)
end)
