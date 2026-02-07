local Health = require("updater.health")

describe("health module", function()
  describe("get_github_api_method", function()
    -- Note: These tests check the function exists and returns expected types.
    -- The actual result depends on the system's gh/curl availability.

    it("should return a string or nil", function()
      local method = Health.get_github_api_method()

      if method ~= nil then
        assert.is_string(method)
        assert.is_true(method == "gh" or method == "curl")
      else
        assert.is_nil(method)
      end
    end)

    it("should return consistent results (cached)", function()
      local method1 = Health.get_github_api_method()
      local method2 = Health.get_github_api_method()

      assert.equals(method1, method2)
    end)
  end)

  describe("check function", function()
    it("should exist and be callable", function()
      assert.is_function(Health.check)
    end)
  end)
end)
