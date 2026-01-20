local Spinner = require("updater.spinner")
local Status = require("updater.status")

describe("spinner module", function()
  before_each(function()
    -- Reset spinner state
    if Status.state.loading_spinner_timer then
      Status.state.loading_spinner_timer:stop()
      Status.state.loading_spinner_timer:close()
    end
    Status.state.loading_spinner_timer = nil
    Status.state.loading_spinner_frame = 1
    Status.state.is_open = false
    Status.state.is_initial_load = false
  end)

  after_each(function()
    -- Cleanup any running spinner
    Spinner.stop_loading_spinner()
  end)

  describe("start_loading_spinner", function()
    it("should create a timer", function()
      Spinner.start_loading_spinner(function() end)

      assert.is_not_nil(Status.state.loading_spinner_timer)

      Spinner.stop_loading_spinner()
    end)

    it("should not create multiple timers", function()
      Spinner.start_loading_spinner(function() end)
      local first_timer = Status.state.loading_spinner_timer

      Spinner.start_loading_spinner(function() end)
      local second_timer = Status.state.loading_spinner_timer

      assert.equals(first_timer, second_timer)

      Spinner.stop_loading_spinner()
    end)

    it("should reset spinner frame to 1", function()
      Status.state.loading_spinner_frame = 5
      Spinner.start_loading_spinner(function() end)

      assert.equals(1, Status.state.loading_spinner_frame)

      Spinner.stop_loading_spinner()
    end)
  end)

  describe("stop_loading_spinner", function()
    it("should stop and clear timer", function()
      Spinner.start_loading_spinner(function() end)
      assert.is_not_nil(Status.state.loading_spinner_timer)

      Spinner.stop_loading_spinner()

      assert.is_nil(Status.state.loading_spinner_timer)
    end)

    it("should handle nil timer gracefully", function()
      Status.state.loading_spinner_timer = nil

      -- Should not error
      Spinner.stop_loading_spinner()

      assert.is_nil(Status.state.loading_spinner_timer)
    end)

    it("should handle being called multiple times", function()
      Spinner.start_loading_spinner(function() end)

      Spinner.stop_loading_spinner()
      Spinner.stop_loading_spinner()
      Spinner.stop_loading_spinner()

      assert.is_nil(Status.state.loading_spinner_timer)
    end)
  end)
end)
