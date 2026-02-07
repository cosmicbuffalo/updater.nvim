# updater.nvim

A Neovim plugin for managing your dotfiles repository with semantic versioning. Pin your configuration to stable releases, switch between versions, and keep your plugins in sync with your dotfiles.

## Features

- 🏷️ **Version Management** - Pin your dotfiles to specific release tags (e.g., `v1.0.0`)
- 🔄 **Automatic Plugin Sync** - Restore plugins from `lazy-lock.json` when switching versions
- 🛠️ **Mason Tool Sync** - Restore mason tools from `mason-lock.json` (if mason-lock.nvim is installed)
- 📋 **Release Notes** - View GitHub release titles and notes directly in Neovim
- 🎨 **Visual TUI** - Browse releases, view changelogs, and switch versions with a simple interface
- 🔔 **Update Notifications** - Get notified when a new release is available
- 🏥 **Health Checks** - Built-in diagnostics via `:checkhealth updater`

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "cosmicbuffalo/updater.nvim",
    opts = {
        versioned_releases_only = true,  -- Recommended: use release-based updates
    },
}
```

## Quick Start

1. **Create a release tag** in your dotfiles repository:
   ```bash
   cd ~/.config/nvim
   git add -A && git commit -m "Release v1.0.0"
   git tag v1.0.0
   git push origin main --tags
   ```

2. **Open the updater** with `<leader>e` or `:UpdaterOpen`

3. **Switch versions** using the TUI or `:DotfilesVersion v1.0.0`

## Version Management

### The `:DotfilesVersion` Command

```vim
:DotfilesVersion              " Open interactive version picker
:DotfilesVersion v1.2.0       " Switch to specific version
:DotfilesVersion latest       " Switch to the latest release
```

### What Happens When You Switch Versions

1. **Safety Check** - Verifies no uncommitted changes exist (ignoring lazy/mason lockfiles)
2. **Git Checkout** - Checks out the specified tag (detached HEAD)
3. **Plugin Restore** - Runs `lazy.restore()` to sync plugins with `lazy-lock.json`
4. **Mason Restore** - Runs `mason-lock.restore()` if mason-lock.nvim is installed
5. **State Update** - Updates the TUI to reflect the new version

> [!IMPORTANT]
> Switching your dotfiles version still requires you to close and reopen neovim to load all the updates!

## Configuration

```lua
require("updater").setup({
    -- Path to your dotfiles repository (optional, will use default config path)
    repo_path = vim.fn.stdpath("config"),

    -- RECOMMENDED: Enable release-based version management
    -- versioned_releases_only mode will become the only mode in a future release!
    versioned_releases_only = true,

    -- Pattern for version tags (default matches v1.0.0, v2.1.3, etc.)
    version_tag_pattern = "v*",

    -- Main branch name
    main_branch = "main",

    -- Window title
    title = "Neovim Dotfiles Updater",

    -- Keybindings -- DEPRECATED, will be removed in a future release
    keymap = {
        open = "<leader>e",       -- Open the updater TUI
        update = "u",             -- Update to selected version
        refresh = "r",            -- Refresh status
        close = "q",              -- Close the TUI
        install_plugins = "i",    -- Install plugin updates
        update_all = "U",         -- Update dotfiles + plugins
    },

    -- Automatic update checking
    check_updates_on_startup = {
        enabled = true,
    },

    -- Periodic background checks -- DEPRECATED, will be removed in a future release
    periodic_check = {
        enabled = true,
        frequency_minutes = 20,
    },

    -- Git options
    git = {
        rebase = true,
        autostash = true,
    },

    -- Operation timeouts (seconds)
    timeouts = {
        fetch = 30,
        pull = 30,
        merge = 30,
        log = 15,
        status = 10,
        default = 20,
    },

    -- Filetypes where update checks are skipped
    excluded_filetypes = { "gitcommit", "gitrebase" },
})
```

## TUI Keybindings

When `versioned_releases_only = true`:

| Key | Action |
|-----|--------|
| `s` | Switch to the release under cursor |
| `U` | Switch to the latest release |
| `Enter` | Expand/collapse release details |
| `r` | Refresh status |
| `q` / `Esc` | Close the TUI |
| `j` / `k` | Navigate between releases |
| `y` | Copy release URL to clipboard |

## Commands

| Command | Description |
|---------|-------------|
| `:UpdaterOpen` | Open the updater TUI |
| `:DotfilesVersion` | Open version picker or switch to a version |
| `:DotfilesVersion <tag>` | Switch to a specific version |
| `:DotfilesVersion latest` | Switch to the latest release |
| `:UpdaterCheck` | Check for updates (shows notification) |
| `:UpdaterStartChecking` | Start periodic update checking DEPRECATED|
| `:UpdaterStopChecking` | Stop periodic update checking DEPRECATED|
| `:checkhealth updater` | Run health diagnostics |

## GitHub Release Integration

If you have the [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated, updater.nvim will fetch release metadata from GitHub:

- **Release Titles** - Displayed alongside version tags
- **Release Notes** - Shown when expanding a release in the TUI
- **Prerelease Tags** - Marked in the version picker

For public repositories, `curl` can be used as a fallback (without authentication).

Run `:checkhealth updater` to verify your GitHub API access.

## Lualine Integration

> [!WARNING]
> The API for this lualine integration is deprecated and will be removed in a future release

Display update status in your statusline:

```lua
require('lualine').setup({
    sections = {
        lualine_x = {
            {
                function()
                    return require('updater').status.get_update_text('icon')
                end,
                cond = function()
                    return require('updater').status.has_updates()
                end,
                color = { fg = '#ff9e64' },
                on_click = function()
                    require('updater').open()
                end,
            },
        }
    }
})
```

### Format Options

- `"default"`: "2 dotfiles, 3 plugins updates"
- `"short"`: "2d 3p"
- `"icon"`: "󰚰 2 󰏖 3"

## Requirements

- Neovim >= 0.10.0 (for `vim.system()` async support)
- Git
- `timeout` command (Linux) or `gtimeout` (macOS via Homebrew) - recommended
- [lazy.nvim](https://github.com/folke/lazy.nvim) - for plugin management
- [gh CLI](https://cli.github.com/) - optional, for GitHub release metadata
- [mason-lock.nvim](https://github.com/zapling/mason-lock.nvim) - optional, for mason tool sync
- [fidget.nvim](https://github.com/j-hui/fidget.nvim) - optional, for progress indicators

## Creating Releases

To create a new release for your dotfiles:

```bash
cd ~/.config/nvim

# Ensure lazy-lock.json is up to date
nvim -c "Lazy sync" -c "qa"

# If using mason-lock.nvim, update the lockfile
nvim -c "MasonLock" -c "qa"

# Commit and tag
git add -A
git commit -m "Release v1.0.0: Description of changes"
git tag v1.0.0
git push origin main --tags
```

Users of your dotfiles can then switch to this version:
```vim
:DotfilesVersion v1.0.0
```

## Troubleshooting

Run `:checkhealth updater` to diagnose common issues:

- Git command availability
- GitHub CLI authentication status
- Timeout utility availability
- Neovim version compatibility
- lazy.nvim integration
- fidget.nvim integration

## Debug Mode -- DEPRECATED

For testing without making git changes:

```vim
:UpdaterDebugToggle           " Toggle debug mode
:UpdaterDebugSimulate 2 3     " Simulate 2 dotfile + 3 plugin updates
:UpdaterDebugDisable          " Disable debug mode
```

---

## DEPRECATED: Legacy Mode

> **Deprecation Notice:** The legacy update mode (`versioned_releases_only = false`) is deprecated and will be removed in a future release. Please migrate to versioned releases mode.

<details>
<summary>Legacy Mode Documentation (Deprecated)</summary>

### Legacy Configuration

```lua
require("updater").setup({
    versioned_releases_only = false,  -- DEPRECATED
    -- ... other options
})
```

### Legacy TUI Keybindings

| Key | Action |
|-----|--------|
| `U` | Update dotfiles + install plugin updates |
| `u` | Update dotfiles only |
| `i` | Install plugin updates only |
| `r` | Refresh status |
| `q` | Close |

### Legacy Behavior

In legacy mode, the plugin:
- Compares local commits with the remote main branch
- Pulls changes directly without version pinning
- Shows commit logs instead of release information

### Migration Guide

1. Create release tags in your dotfiles repository
2. Set `versioned_releases_only = true` in your config
3. Disable lazy.nvim's checker: `checker = { enabled = false }`
4. Use `:DotfilesVersion` to manage versions

</details>

---

## License

MIT License
