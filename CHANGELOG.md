# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
