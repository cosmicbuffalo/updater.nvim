# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v2.0.0-pre] - 2026-02-06

### Added
- **Versioned Releases Mode** (`versioned_releases_only = true`): New release-based version management
  - Pin dotfiles to specific semantic version tags (e.g., `v1.0.0`)
  - Automatic plugin restoration via `lazy.restore()` when switching versions
  - Automatic mason tool restoration via `mason-lock.restore()` (if mason-lock.nvim is installed)
  - Version switching runs plugin/tool restoration in a headless Neovim instance to avoid UI conflicts
- **`:DotfilesVersion` Command**: Interactive version management
  - No arguments: opens version picker with release titles and prerelease indicators
  - With tag argument: switches to specific version (e.g., `:DotfilesVersion v1.2.0`)
  - `latest` argument: switches to the newest release tag
  - Tab completion for available version tags
- **Release-Focused TUI**: New interface for versioned releases mode
  - Browse all release tags with expand/collapse for details
  - Cursor constraining to navigate only between release/commit lines
  - `s` keybind to switch to release under cursor
  - `U` keybind to switch to latest release
  - `Enter` to expand/collapse release details
  - `y` keybind to copy release URL to clipboard
- **GitHub Release Integration**: Fetch release metadata from GitHub API
  - Show release notes when expanding releases
  - Supports `gh` CLI (private repos) with `curl` fallback (public repos only)
- **New Test Coverage**: 75+ new tests for versioned releases features

### Changed
- **README Rewritten**: Focus on versioned releases as the primary use case
  - Quick start guide for creating releases
  - Comprehensive documentation of `:DotfilesVersion` command
  - Updated configuration examples
  - Migration guide from legacy mode
- **Neovim Version Requirement**: Increased to 0.10.0+ (for `vim.system()` support)
- **Config Validation**: Removed `repo_path` validation - errors surface on first use instead
- **Health Check**: Removed `repo_path` health check, added GitHub API method detection

### Deprecated
- **Legacy Mode** (`versioned_releases_only = false`): Deprecated, will be removed in a future release
  - Commit-based updates without version pinning
  - Direct pull from main branch
  - Users should migrate to versioned releases mode
- **Periodic checks**: Deprecated, will be removed in a future release
- **Lualine integration support**: Deprecated, will be removed in a future release
  - With the switch to semantic versioning, a new integration will be built eventually

## [v1.0.0] - 2026-01-20

Major refactor to async architecture with smart plugin update detection and comprehensive test coverage.

### Added
- **Async Architecture**: All git and plugin operations now use non-blocking async patterns via `vim.system()`
  - Git operations (fetch, pull, merge, status) are fully async with callbacks
  - Plugin update checking runs in parallel for better performance
- **Smart Plugin Direction Detection**: Compares git commit timestamps to determine if installed plugins are newer or older than lockfile
- **Multi-line Status Messages**: Status area now supports multiple lines with independent highlighting
  - Green message for actual updates available
  - Yellow message for plugins that can be downgraded
- **Test Suite**: Comprehensive test coverage using plenary.nvim
  - 134 unit tests across all modules
  - Test helpers for git repo setup, async waiting, and notification capture
  - CI workflow for automated testing via GitHub Actions
- **Linting**: Added selene linter configuration and Makefile targets

### Changed
- **`Git.update_repo()` API simplified**: No longer requires `current_branch` argument - fetches branch internally
- **`get_current_branch()` made private**: Now a local function in `git.lua` since it's only used internally
- **`get_plugin_updates()` made async**: Returns `{ all_updates, plugins_behind, plugins_ahead }` via callback
- **Operations module refactored**: Extracted refresh steps into named functions for better readability
- **Health check moved to `:checkhealth`**: Streamlined validation logic and removed redundant checks
