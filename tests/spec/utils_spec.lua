local Utils = require("updater.utils")

describe("utils module", function()
  local test_config

  before_each(function()
    test_config = {
      keymap = {
        open = "<leader>e",
      },
      notify = {
        outdated = {
          message = "Updates available!",
        },
        up_to_date = {
          message = "You are up to date!",
        },
      },
    }
  end)

  describe("generate_outdated_message", function()
    it("should return default message when not ahead", function()
      local status = { ahead = 0, behind = 5 }
      local message = Utils.generate_outdated_message(test_config, status)
      assert.equals("Updates available!", message)
    end)

    it("should return custom message when ahead", function()
      local status = { ahead = 2, behind = 5 }
      local message = Utils.generate_outdated_message(test_config, status)
      assert.is_truthy(message:match("ahead by 2"))
      assert.is_truthy(message:match("behind by 5"))
      assert.is_truthy(message:match("<leader>e"))
    end)
  end)

  describe("generate_up_to_date_message", function()
    it("should return default message when not ahead", function()
      local status = { ahead = 0, behind = 0 }
      local message = Utils.generate_up_to_date_message(test_config, status)
      assert.equals("You are up to date!", message)
    end)

    it("should return custom message when ahead", function()
      local status = { ahead = 3, behind = 0 }
      local message = Utils.generate_up_to_date_message(test_config, status)
      assert.is_truthy(message:match("up to date"))
      assert.is_truthy(message:match("ahead by 3"))
    end)
  end)
end)
