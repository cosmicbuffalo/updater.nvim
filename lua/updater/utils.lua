-- Simple utils module for updater plugin
local M = {}

M.lazy = {}

function M.lazy.read_lockfile(path)
	if vim.fn.filereadable(path) == 0 then
		return {}
	end

	local content = vim.fn.readfile(path)
	local json_str = table.concat(content, "\n")

	local ok, decoded = pcall(vim.json.decode, json_str)
	if not ok then
		return {}
	end

	return decoded
end

return M