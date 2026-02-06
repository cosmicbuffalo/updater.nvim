local M = {}

-- Timing constants
M.SPINNER_INTERVAL = 100 -- Spinner animation interval (ms)
M.PROGRESS_SUCCESS_DURATION = 1500 -- How long to show "Updates available!" (ms)
M.PROGRESS_FINISH_DURATION = 1000 -- How long to show "Up to date" (ms)
M.STARTUP_CHECK_DELAY = 200 -- Delay for startup check (ms)
M.TIMEOUT_EXIT_CODE = 124 -- Exit code for command timeout

-- UI layout constants
M.WINDOW_WIDTH_RATIO = 0.9 -- Window width as ratio of screen width
M.WINDOW_HEIGHT_RATIO = 0.8 -- Window height as ratio of screen height
M.MAX_WINDOW_WIDTH = 150 -- Maximum window width in columns
M.MAX_WINDOW_HEIGHT = 40 -- Maximum window height in lines
M.WINDOW_BLEND = 10 -- Window transparency blend value
M.MAX_WINDOW_HEIGHT_LINES = 60 -- Maximum window height in lines for content

-- Text formatting constants
M.MAX_COMMIT_MESSAGE_LENGTH = 80

-- Animation constants
M.SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- Version switching constants
M.VERSION_CACHE_TTL = 60 -- seconds to cache tag list
M.MAX_SECTION_ITEMS = 10 -- max items to show in release/commit sections

return M
