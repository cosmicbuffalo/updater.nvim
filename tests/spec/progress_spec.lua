local Progress = require("updater.progress")

describe("progress module", function()
  describe("is_fidget_available", function()
    it("should return false when fidget is not installed", function()
      -- In test environment, fidget is not installed
      assert.is_false(Progress.is_fidget_available())
    end)
  end)

  describe("create_fidget_progress", function()
    it("should return nil when fidget is not available", function()
      local progress = Progress.create_fidget_progress("Test", "Testing...")
      assert.is_nil(progress)
    end)
  end)

  describe("handle_refresh_progress", function()
    it("should return a handler object", function()
      local handler = Progress.handle_refresh_progress("Checking...", "Initial message")

      assert.is_not_nil(handler)
      assert.is_table(handler)
    end)

    it("should have a finish function", function()
      local handler = Progress.handle_refresh_progress("Checking...", "Initial message")

      assert.is_function(handler.finish)
    end)

    it("should have a progress field (nil when fidget unavailable)", function()
      local handler = Progress.handle_refresh_progress("Checking...", "Initial message")

      -- Progress is nil when fidget is not available
      assert.is_nil(handler.progress)
    end)

    it("finish should not error when called with true", function()
      local handler = Progress.handle_refresh_progress("Checking...", "Initial message")

      -- Should not error even without fidget
      handler.finish(true)
    end)

    it("finish should not error when called with false", function()
      local handler = Progress.handle_refresh_progress("Checking...", "Initial message")

      -- Should not error even without fidget
      handler.finish(false)
    end)
  end)
end)
