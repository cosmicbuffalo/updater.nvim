local Git = require("updater.git")

describe("git module", function()
  local test_dir
  local test_config

  before_each(function()
    test_dir = _G.test_helpers.create_temp_dir()
    _G.test_helpers.init_git_repo(test_dir)

    test_config = {
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
      },
      git = {
        rebase = true,
        autostash = true,
      },
    }

    -- Clear validation cache before each test
    Git.clear_validation_cache()
  end)

  after_each(function()
    _G.test_helpers.cleanup_temp_dir(test_dir)
    Git.clear_validation_cache()
  end)

  describe("validate_git_repository", function()
    it("should validate a valid git repository", function()
      local done = false
      local is_valid = nil

      Git.validate_git_repository(test_dir, function(valid, err)
        is_valid = valid
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      assert.is_true(is_valid)
    end)

    it("should return false for non-git directory", function()
      local non_git_dir = _G.test_helpers.create_temp_dir()
      local done = false
      local is_valid = nil
      local error_msg = nil

      Git.validate_git_repository(non_git_dir, function(valid, err)
        is_valid = valid
        error_msg = err
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      assert.is_false(is_valid)
      assert.is_not_nil(error_msg)

      _G.test_helpers.cleanup_temp_dir(non_git_dir)
    end)

    it("should return false for nil path", function()
      local done = false
      local is_valid = nil

      Git.validate_git_repository(nil, function(valid, err)
        is_valid = valid
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      assert.is_false(is_valid)
    end)

    it("should cache validation results", function()
      local done1 = false
      local done2 = false

      Git.validate_git_repository(test_dir, function(valid, err)
        done1 = true
      end)

      _G.test_helpers.wait_for(function()
        return done1
      end)

      -- Second call should use cache
      local status = Git.get_validation_status(test_dir)
      assert.is_true(status)
    end)
  end)

  describe("get_validation_status", function()
    it("should return nil for unchecked path", function()
      local status = Git.get_validation_status("/some/random/path")
      assert.is_nil(status)
    end)

    it("should return true after successful validation", function()
      local done = false

      Git.validate_git_repository(test_dir, function()
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      local status = Git.get_validation_status(test_dir)
      assert.is_true(status)
    end)
  end)

  describe("clear_validation_cache", function()
    it("should clear the validation cache", function()
      local done = false

      Git.validate_git_repository(test_dir, function()
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      assert.is_true(Git.get_validation_status(test_dir))

      Git.clear_validation_cache()

      assert.is_nil(Git.get_validation_status(test_dir))
    end)
  end)

  describe("rollback_to_commit", function()
    it("should rollback to a specific commit", function()
      -- Get current commit
      local done = false
      local original_commit = nil

      Git.get_current_commit(test_config, test_dir, function(result, err)
        original_commit = result
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      -- Create a new commit
      local test_file = test_dir .. "/new_file.txt"
      local file = io.open(test_file, "w")
      file:write("new content")
      file:close()

      vim.fn.system("cd " .. test_dir .. " && git add . && git commit -m 'new commit'")

      -- Verify we're on a different commit
      done = false
      local new_commit = nil
      Git.get_current_commit(test_config, test_dir, function(result, err)
        new_commit = result
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      assert.are_not.equals(original_commit, new_commit)

      -- Rollback
      done = false
      local rollback_success = nil

      Git.rollback_to_commit(test_config, test_dir, original_commit, function(success, err)
        rollback_success = success
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      assert.is_true(rollback_success)

      -- Verify we're back to original commit
      done = false
      local current_commit = nil
      Git.get_current_commit(test_config, test_dir, function(result, err)
        current_commit = result
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      assert.equals(original_commit, current_commit)
    end)
  end)
end)
