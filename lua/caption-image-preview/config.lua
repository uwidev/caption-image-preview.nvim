-- Default configuration
local defaults = {
	split_ratio = 0.4, -- 40% of screen width
	extensions = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
	caption_patterns = { "*.txt" },
	auto_update = true, -- Auto-update on buffer switch
	-- Keymaps: set to false to disable, or provide a string for custom keymap
	keymaps = {
		toggle = "<leader>cip", -- Toggle preview
		refresh = "<leader>cir", -- Refresh preview
	},
}

local M = {}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
