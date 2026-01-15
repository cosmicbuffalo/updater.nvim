-- Minimal init.lua for running tests with plenary

local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
local updater_dir = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":p:h:h")

-- Add plenary and updater to runtime path
vim.opt.rtp:append(plenary_dir)
vim.opt.rtp:append(updater_dir)

-- Load plenary
vim.cmd("runtime! plugin/plenary.vim")

-- Set up minimal mocks for optional dependencies

-- Mock fidget.nvim (optional dependency)
package.loaded["fidget"] = nil
package.loaded["fidget.progress"] = nil

-- Mock lazy.nvim (optional dependency for plugin updates)
package.loaded["lazy.core.config"] = {
  options = { lockfile = "/tmp/lazy-lock.json" },
  plugins = {},
  spec = { disabled = {}, plugins = {} },
}

package.loaded["lazy.manage.git"] = {
  info = function(dir)
    return nil
  end,
}

-- Seed random number generator for unique directory names
math.randomseed(os.time() + vim.loop.hrtime())

-- Counter for unique directory names
local temp_dir_counter = 0

-- Helper function available to all tests
_G.test_helpers = {
  -- Create a temporary directory for testing
  create_temp_dir = function()
    temp_dir_counter = temp_dir_counter + 1
    local dir = "/tmp/updater_test_" .. os.time() .. "_" .. temp_dir_counter .. "_" .. math.random(100000, 999999)
    vim.fn.mkdir(dir, "p")
    return dir
  end,

  -- Clean up a temporary directory
  cleanup_temp_dir = function(dir)
    if dir and dir:match("^/tmp/updater_test_") then
      vim.fn.delete(dir, "rf")
    end
  end,

  -- Initialize a git repo for testing
  init_git_repo = function(dir)
    -- Use -b main to ensure consistent branch name across git versions
    vim.fn.system(
      "cd "
        .. vim.fn.shellescape(dir)
        .. " && git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'"
    )
    vim.fn.system(
      "cd " .. vim.fn.shellescape(dir) .. " && touch README.md && git add . && git commit -m 'Initial commit'"
    )
    return dir
  end,

  -- Wait for async operation to complete
  wait_for = function(condition, timeout_ms)
    timeout_ms = timeout_ms or 5000
    local ok = vim.wait(timeout_ms, condition, 10)
    return ok
  end,

  -- Capture vim.notify calls
  capture_notifications = function()
    local notifications = {}
    local original_notify = vim.notify

    vim.notify = function(msg, level, opts)
      table.insert(notifications, {
        msg = msg,
        level = level,
        opts = opts,
      })
    end

    return {
      notifications = notifications,
      restore = function()
        vim.notify = original_notify
      end,
    }
  end,
}
