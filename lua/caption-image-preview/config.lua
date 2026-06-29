-- Default configuration
local defaults = {
	split_ratio = 0.4,
	extensions = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
	caption_patterns = { "*.txt" },
	auto_update = true,
	keymaps = {
		toggle = "<leader>cip",
		refresh = "<leader>cir",
	},
}

local M = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("keep", vim.deepcopy(defaults), opts or {})
end

-- Provide a way to get config without side effects
function M.get()
	return M.options
end

-- Initialize on load so users don't have to call setup
M.setup({})

return M
