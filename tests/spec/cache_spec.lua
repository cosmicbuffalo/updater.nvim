local Cache = require("updater.cache")

describe("cache module", function()
  local test_dir

  before_each(function()
    test_dir = _G.test_helpers.create_temp_dir()
  end)

  after_each(function()
    _G.test_helpers.cleanup_temp_dir(test_dir)
  end)

  describe("write and read", function()
    it("should write and read cache data asynchronously", function()
      local write_done = false
      local read_data = nil

      Cache.write(test_dir, { test_key = "test_value" }, function(success)
        assert.is_true(success)
        write_done = true
      end)

      _G.test_helpers.wait_for(function()
        return write_done
      end)

      Cache.read(test_dir, function(data)
        read_data = data
      end)

      _G.test_helpers.wait_for(function()
        return read_data ~= nil
      end)

      assert.is_not_nil(read_data)
      assert.equals("test_value", read_data.test_key)
    end)

    it("should return nil for non-existent cache", function()
      local read_done = false
      local read_data = "not_nil"

      Cache.read("/nonexistent/path", function(data)
        read_data = data
        read_done = true
      end)

      _G.test_helpers.wait_for(function()
        return read_done
      end)

      assert.is_nil(read_data)
    end)
  end)

  describe("is_fresh", function()
    it("should return false for non-existent cache", function()
      local check_done = false
      local is_fresh = nil

      Cache.is_fresh("/nonexistent/path", 60, function(fresh, data)
        is_fresh = fresh
        check_done = true
      end)

      _G.test_helpers.wait_for(function()
        return check_done
      end)

      assert.is_false(is_fresh)
    end)

    it("should return true for fresh cache", function()
      local write_done = false
      local is_fresh = nil

      -- Write cache with current time
      Cache.update_after_check(test_dir, {
        current_commit = "abc123",
        current_branch = "main",
      }, function()
        write_done = true
      end)

      _G.test_helpers.wait_for(function()
        return write_done
      end)

      local check_done = false
      Cache.is_fresh(test_dir, 60, function(fresh, data)
        is_fresh = fresh
        check_done = true
      end)

      _G.test_helpers.wait_for(function()
        return check_done
      end)

      assert.is_true(is_fresh)
    end)
  end)

  describe("update_after_check", function()
    it("should store state data in cache", function()
      local write_done = false
      local read_data = nil

      local state = {
        current_commit = "abc123",
        current_branch = "main",
        behind_count = 5,
        ahead_count = 2,
        needs_update = true,
        has_plugin_updates = false,
      }

      Cache.update_after_check(test_dir, state, function()
        write_done = true
      end)

      _G.test_helpers.wait_for(function()
        return write_done
      end)

      Cache.read(test_dir, function(data)
        read_data = data
      end)

      _G.test_helpers.wait_for(function()
        return read_data ~= nil
      end)

      assert.equals("main", read_data.branch)
      assert.equals(5, read_data.behind_count)
      assert.equals(2, read_data.ahead_count)
      assert.is_true(read_data.needs_update)
      assert.is_false(read_data.has_plugin_updates)
      assert.is_not_nil(read_data.last_check_time)
    end)
  end)
end)
