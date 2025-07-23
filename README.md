# updater.nvim

A Neovim plugin for managing and updating your dotfiles repository directly from within Neovim.

## Features

- 🔄 Check for updates from your dotfiles repository
- 🚀 Update your dotfiles with a single keystroke
- 📊 Visual diff of local vs remote commits
- 🎨 Simple TUI interface similar to Lazy.nvim
- ⚡ Configurable timeouts for git operations
- 🔔 Periodic update checking with configurable frequency
- 📦 Plugin update integration with lazy.nvim
- 🛡️ Robust configuration validation and error handling
- 🏥 Built-in health checking for troubleshooting
- 🔒 Security features to prevent shell injection

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "cosmicbuffalo/updater.nvim",
    opts = {
        -- Configuration options (see below)
    },
}
```

## Configuration

The plugin comes with sensible defaults, but you can customize it:

```lua
require("updater").setup({
    -- Path to the dotfiles repository (default: current Neovim config directory)
    repo_path = vim.fn.stdpath("config"),
    
    -- Utility to run commands with timeout (switch to gtimeout on macOS)
    timeout_utility = "timeout",
    
    -- Title for the updater window
    title = "Neovim Dotfiles Updater",
    
    -- How many commits to show in the log
    log_count = 15,
    
    -- Main branch name
    main_branch = "main",
    
    -- Git operation timeouts (in seconds)
    timeouts = {
        fetch = 30,
        pull = 30,
        merge = 30,
        log = 15,
        status = 10,
        default = 20,
    },
    
    -- Keybindings 
    keymap = {
        -- normal mode keymaps
        open = "<leader>e",       -- Opens the updater TUI
        
        -- TUI buffer-local keymaps
        update = "u",             -- Updates dotfiles only
        refresh = "r",            -- Refreshes status
        close = "q",              -- Close the updater TUI
        install_plugins = "i",    -- Install plugin updates via lazy restore
        update_all = "U",         -- Update dotfiles + install plugin updates
    },
    
    -- Startup check configuration
    check_updates_on_startup = {
        enabled = true,           -- Check for updates when Neovim starts
    },
    
    -- Periodic update checking
    periodic_check = {
        enabled = true,           -- Enable periodic checking
        frequency_minutes = 20,   -- Check every 20 minutes (default)
    },
})
```

## Usage

### Opening the Updater

- Press `<leader>e` (default) or run `:UpdaterOpen`
- The updater will automatically check for updates when opened

### Within the Updater Window

- `U` - Update dotfiles + install plugin updates (recommended)
- `u` - Update dotfiles only
- `i` - Install plugin updates only (via lazy restore)
- `r` - Refresh the status
- `q` or `<Esc>` - Close the updater

### Commands

- `:UpdaterOpen` - Open the updater interface
- `:UpdaterCheck` - Check for updates and show notification
- `:UpdaterStartChecking` - Start periodic update checking
- `:UpdaterStopChecking` - Stop periodic update checking
- `:UpdaterHealth` - Run health check for troubleshooting

### Automatic Update Checking

The plugin supports two types of automatic checking:

#### Startup Checking
Check for updates when Neovim starts:
```lua
require("updater").setup({
    check_updates_on_startup = { enabled = false }  -- Disable startup check
})
```

#### Periodic Checking
Automatically check for updates every few minutes (only notifies when updates are available):
```lua
require("updater").setup({
    periodic_check = {
        enabled = true,
        frequency_minutes = 60,  -- Check every hour
    }
})
```

## Integrations

### Lualine Integration

Display update status in your lualine statusbar by adding this to your lualine config:

```lua
-- Basic integration
require('lualine').setup({
  sections = {
    lualine_x = {
      {
        function()
          return require('updater').status.get_update_text()
        end,
        cond = function()
          return require('updater').status.has_updates()
        end,
        color = { fg = '#ff9e64' }, -- Orange color for updates
        on_click = function()
          require('updater').open()
        end,
      },
      -- ... your other lualine_x components
    }
  }
})
```

#### Advanced Lualine Configuration

```lua
-- With custom formatting and icons
{
  function()
    return require('updater').status.get_update_text('icon') -- Use icon format
  end,
  cond = function()
    return require('updater').status.has_updates()
  end,
  color = function()
    local status = require('updater').status.get()
    -- Different colors based on update type
    if status.needs_update and status.has_plugin_updates then
      return { fg = '#f7768e' } -- Red for both types
    elseif status.needs_update then
      return { fg = '#ff9e64' } -- Orange for dotfiles
    else
      return { fg = '#9ece6a' } -- Green for plugins only
    end
  end,
  on_click = function()
    require('updater').open()
  end,
}
```

#### Format Options

The `get_update_text()` function supports different formats:

- `"default"`: "2 dotfiles, 3 plugins updates"
- `"short"`: "2d 3p" 
- `"icon"`: "󰚰 2 󰏖 3"

See [examples/lualine.lua](examples/lualine.lua) for more complete integration examples.

#### Available API Functions

```lua
local updater = require('updater')

-- Check if any updates are available
updater.status.has_updates() -- returns boolean

-- Get total count of available updates
updater.status.get_update_count() -- returns number

-- Get formatted update text
updater.status.get_update_text('icon') -- returns string or empty string

-- Get detailed status information
updater.status.get() -- returns table with all status info

-- Open the updater TUI
updater.open()
```

## How It Works

1. **Fetching**: The plugin fetches the latest changes from your remote repository
2. **Comparison**: It compares your local branch with the remote main branch
3. **Display**: Shows you what commits are available and what's different
4. **Plugin Updates**: If lazy.nvim is available, it also checks for plugin updates
5. **Update**: 
   - `U` - Updates dotfiles + installs plugin updates
   - `u` - Updates dotfiles only (pulls changes on main branch, merges on feature branches)
   - `i` - Installs plugin updates only (via lazy restore)

## Requirements

- Neovim >= 0.7.0
- Git
- `timeout` command (Linux) or `gtimeout` (macOS via Homebrew) - optional but recommended
- lazy.nvim - optional, enables plugin update features
- fidget.nvim - optional, enables unobtrusive progress indicators

## Testing

For local testing and development, see [TESTING.md](TESTING.md) for comprehensive testing methods including:

- **Debug Mode**: Simulate updates without git changes 
- **Test Branch**: Create git scenarios with real update states  
- **Test Repository**: Set up dedicated test environments

### Debug Mode

Debug functionality is loaded on-demand to keep the main plugin lightweight:

```vim
:UpdaterDebugToggle        " Toggle debug mode (lazily loads)
:UpdaterDebugSimulate 2 3  " Simulate 2 dotfile + 3 plugin updates  
:UpdaterOpen               " Open TUI to see simulated updates
:UpdaterDebugDisable       " Turn off debug mode
```

**Debug Commands**:
- `:UpdaterDebugToggle` - Toggle debug mode on/off 
- `:UpdaterDebugSimulate <dotfiles> <plugins>` - Enable debug mode and simulate specific update counts (both arguments required)
- `:UpdaterDebugDisable` - Turn off debug mode

**Behavior**:
- Debug module loads only when `:UpdaterDebugToggle` is first used
- `:UpdaterDebugToggle` sets default simulation values (2 dotfiles, 3 plugins)
- Debug simulation affects both periodic checks and the updater TUI when enabled

**Note**: Debug mode simulates updates without making actual git changes, useful for testing UI and workflows.

## Troubleshooting

If you encounter issues, run `:UpdaterHealth` to diagnose common problems:

- Git repository validation
- Git command availability  
- Timeout utility check
- Lazy.nvim integration status
- Fidget.nvim integration status
- Remote connectivity test

## Security

The plugin includes several security features:

- Input validation to prevent shell injection
- Path sanitization for repository locations
- Timeout protection for all git operations
- Safe command execution with proper escaping

## License

MIT License
