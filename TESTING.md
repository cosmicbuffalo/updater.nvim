# Testing updater.nvim

This guide provides several methods to test the updater plugin locally, even when your repository is up to date.

## Method 1: Debug Mode (Recommended)

The plugin includes a built-in debug mode that simulates updates without requiring actual git changes.

### Enable Debug Mode

```vim
" Toggle debug mode (enables with defaults: 2 dotfile updates, 3 plugin updates)
:UpdaterDebugToggle

" Enable with custom counts
:UpdaterDebugSimulate 5 2

" Or using Lua (after debug module is loaded)
:lua require('updater.debug').simulate_updates(5, 2)
```

### Test Features in Debug Mode

1. **Test Lualine Integration**: With debug mode enabled, your lualine should show the update indicator
2. **Test UI**: Run `:UpdaterOpen` to see the simulated updates in the TUI
3. **Test API Functions**: 
   ```lua
   :lua print(require('updater').status.has_updates())  -- Should return true
   :lua print(require('updater').status.get_update_count())  -- Should return total count
   :lua print(require('updater').status.get_update_text('icon'))  -- Should show formatted text
   ```

### Disable Debug Mode

```vim
:UpdaterDebugDisable
" Or using Lua (after debug module is loaded)
:lua require('updater.debug').disable_debug_mode()
```

## Method 2: Test Branch Approach

Create a test scenario with real git history:

### Setup Test Branch

```bash
# 1. Create and switch to a test branch
git checkout -b test-updater

# 2. Reset to a few commits behind main
git reset --hard HEAD~3

# 3. Now your test branch is "behind" main by 3 commits
```

### Test with Test Branch

1. Open Neovim from the test branch
2. The updater should detect you're behind by 3 commits
3. Test all functionality:
   - `:UpdaterOpen` - See the commits you're behind
   - `:UpdaterCheck` - Get update notification
   - Test lualine integration
   - Try the update functionality (press `u` in the TUI)

### Cleanup

```bash
# Switch back to main and delete test branch
git checkout main
git branch -D test-updater
```

## Method 3: Test Repository

Create a dedicated test repository:

### Setup

```bash
# 1. Create a test repository
mkdir ~/test-updater-repo
cd ~/test-updater-repo
git init
echo "# Test Repo" > README.md
git add README.md
git commit -m "Initial commit"

# 2. Create a remote (simulate with another local repo)
cd ..
git clone --bare test-updater-repo test-updater-remote.git
cd test-updater-repo
git remote add origin ../test-updater-remote.git

# 3. Create some commits in the "remote"
cd ../test-updater-remote.git
git worktree add ../remote-work main
cd ../remote-work
echo "Remote change 1" >> README.md
git add README.md
git commit -m "Remote update 1"
echo "Remote change 2" >> README.md  
git add README.md
git commit -m "Remote update 2"
git push origin main
```

### Test with Test Repository

1. Configure updater to use the test repository:
   ```lua
   require('updater').setup({
     repo_path = vim.fn.expand("~/test-updater-repo")
   })
   ```

2. The updater should detect you're behind by 2 commits
3. Test all functionality

## Method 4: Temporary Configuration

Test different scenarios by temporarily modifying the plugin configuration:

```lua
-- Test with different notification settings
require('updater').setup({
  debug = {
    enabled = true,
    simulate_updates = {
      dotfiles = 1,
      plugins = 5,
    },
  },
  periodic_check = {
    enabled = true,
    frequency_minutes = 1, -- Very frequent for testing
    use_fidget = true,
  }
})
```

## Testing Checklist

### Basic Functionality
- [ ] `:UpdaterOpen` shows the TUI
- [ ] `:UpdaterCheck` shows notifications
- [ ] `:UpdaterHealth` runs successfully
- [ ] Keybindings work in TUI (`u`, `r`, `q`, etc.)

### Lualine Integration
- [ ] `require('updater').has_updates()` returns correct boolean
- [ ] `require('updater').get_update_text()` returns formatted string
- [ ] `require('updater').get_update_count()` returns correct number
- [ ] Lualine shows/hides indicator correctly
- [ ] Click handler opens updater TUI

### Debug Mode
- [ ] `:UpdaterDebugEnable` enables simulation
- [ ] `:UpdaterDebugDisable` disables simulation
- [ ] Different counts work correctly
- [ ] Debug mode affects all API functions

### Edge Cases
- [ ] No updates available (empty state)
- [ ] Only dotfile updates
- [ ] Only plugin updates  
- [ ] Both types of updates
- [ ] Error conditions (network issues, invalid repo, etc.)

## Common Test Scenarios

### Scenario 1: Fresh User
Test how the plugin behaves for a new user:
```lua
-- Simulate no lazy.nvim
-- Simulate no fidget.nvim
-- Test basic functionality
```

### Scenario 2: Power User
Test advanced features:
```lua
-- Enable all features
-- Test periodic checking
-- Test fidget integration
-- Test lualine integration
```

### Scenario 3: Different Update Types
```lua
-- Test dotfiles only: enable_debug_mode(3, 0)
-- Test plugins only: enable_debug_mode(0, 5)  
-- Test mixed: enable_debug_mode(2, 3)
```

## Cleanup After Testing

Remember to clean up after testing:

1. Disable debug mode: `:UpdaterDebugDisable`
2. Delete test branches: `git branch -D test-updater`
3. Remove test repositories: `rm -rf ~/test-updater-*`
4. Reset configuration to normal values

## Troubleshooting Tests

If tests aren't working as expected:

1. Run `:UpdaterHealth` to check system status
2. Check that debug mode is properly enabled/disabled
3. Verify git repository state with `git status` and `git log`
4. Check Neovim messages with `:messages`
5. Try restarting Neovim to reset state