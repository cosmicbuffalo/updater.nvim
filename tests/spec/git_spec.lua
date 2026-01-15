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

  describe("get_current_branch", function()
    it("should return the current branch name", function()
      local done = false
      local branch = nil

      Git.get_current_branch(test_config, test_dir, function(result, err)
        branch = result
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      -- Git init creates 'master' or 'main' depending on config
      assert.is_truthy(branch == "main" or branch == "master")
    end)

    it("should return 'unknown' for nil config", function()
      local done = false
      local branch = nil

      Git.get_current_branch(nil, test_dir, function(result, err)
        branch = result
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      assert.equals("unknown", branch)
    end)
  end)

  describe("get_current_commit", function()
    it("should return a commit hash", function()
      local done = false
      local commit = nil

      Git.get_current_commit(test_config, test_dir, function(result, err)
        commit = result
        done = true
      end)

      _G.test_helpers.wait_for(function()
        return done
      end)

      assert.is_not_nil(commit)
      -- Git commit hashes are 40 characters
      assert.equals(40, #commit)
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
end)
