local Git = require("updater.git")
local Config = require("updater.config")

describe("git module", function()
  local test_config

  before_each(function()
    test_config = {
      repo_path = "/tmp/test-repo-" .. os.time(),
      main_branch = "main",
      log_count = 15,
      timeouts = {
        fetch = 30,
        pull = 30,
        merge = 30,
        log = 15,
        status = 10,
        checkout = 10,
        tag = 10,
        diff = 10,
        remote = 10,
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

    -- Create test directory and init git repo
    vim.fn.mkdir(test_config.repo_path, "p")
    vim.fn.system(
      "cd "
        .. test_config.repo_path
        .. " && git init && git config user.email 'test@test.com' && git config user.name 'Test'"
    )

    -- Create initial commit
    local test_file = test_config.repo_path .. "/test.txt"
    local file = io.open(test_file, "w")
    if file then
      file:write("test content")
      file:close()
    end
    vim.fn.system("cd " .. test_config.repo_path .. " && git add . && git commit -m 'initial commit'")

    -- Set config for the module
    Config._reset(test_config)

    -- Clear validation cache before each test
    Git.clear_validation_cache()
  end)

  after_each(function()
    vim.fn.system("rm -rf " .. test_config.repo_path)
    Git.clear_validation_cache()
    Config._reset(nil)
  end)

  describe("validate_git_repository", function()
    it("should validate a valid git repository", function()
      local done = false
      local is_valid = nil

      Git.validate_git_repository(function(valid, _err)
        is_valid = valid
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 50)

      assert.is_true(is_valid)
    end)

    it("should return false for non-git directory", function()
      local non_git_dir = "/tmp/non-git-" .. os.time()
      vim.fn.mkdir(non_git_dir, "p")

      -- Temporarily change repo_path to non-git directory
      local original_path = test_config.repo_path
      test_config.repo_path = non_git_dir
      Config._reset(test_config)

      local done = false
      local is_valid = nil
      local error_msg = nil

      Git.validate_git_repository(function(valid, err)
        is_valid = valid
        error_msg = err
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 50)

      assert.is_false(is_valid)
      assert.is_not_nil(error_msg)

      -- Cleanup
      test_config.repo_path = original_path
      Config._reset(test_config)
      vim.fn.system("rm -rf " .. non_git_dir)
    end)

    it("should return false for nil config", function()
      Config._reset(nil)

      local done = false
      local is_valid = nil

      Git.validate_git_repository(function(valid, _err)
        is_valid = valid
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 50)

      assert.is_false(is_valid)
    end)

    it("should cache validation results", function()
      local done1 = false

      Git.validate_git_repository(function(_valid, _err)
        done1 = true
      end)

      vim.wait(2000, function()
        return done1
      end, 50)

      -- Second call should use cache
      local status = Git.get_validation_status(test_config.repo_path)
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

      Git.validate_git_repository(function()
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 50)

      local status = Git.get_validation_status(test_config.repo_path)
      assert.is_true(status)
    end)
  end)

  describe("clear_validation_cache", function()
    it("should clear the validation cache", function()
      local done = false

      Git.validate_git_repository(function()
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 50)

      assert.is_true(Git.get_validation_status(test_config.repo_path))

      Git.clear_validation_cache()

      assert.is_nil(Git.get_validation_status(test_config.repo_path))
    end)
  end)

  describe("rollback_to_commit", function()
    it("should rollback to a specific commit", function()
      -- Get current commit
      local done = false
      local original_commit = nil

      Git.get_current_commit(function(result, _err)
        original_commit = result
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 50)

      assert.is_not_nil(original_commit)

      -- Create a new commit
      local test_file = test_config.repo_path .. "/new_file.txt"
      local file = io.open(test_file, "w")
      if file then
        file:write("new content")
        file:close()
      end

      vim.fn.system("cd " .. test_config.repo_path .. " && git add . && git commit -m 'new commit'")

      -- Verify we're on a different commit
      done = false
      local new_commit = nil
      Git.get_current_commit(function(result, _err)
        new_commit = result
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 50)

      assert.are_not.equals(original_commit, new_commit)

      -- Rollback
      done = false
      local rollback_success = nil

      Git.rollback_to_commit(original_commit, function(success, _err)
        rollback_success = success
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 50)

      assert.is_true(rollback_success)

      -- Verify we're back to original commit
      done = false
      local current_commit = nil
      Git.get_current_commit(function(result, _err)
        current_commit = result
        done = true
      end)

      vim.wait(2000, function()
        return done
      end, 50)

      assert.equals(original_commit, current_commit)
    end)
  end)
end)
