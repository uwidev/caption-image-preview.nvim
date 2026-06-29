-- Main entry point
local config = require("caption-image-preview.config")
local preview = require("caption-image-preview.preview")

local M = {}

function M.setup(opts)
	config.setup(opts)

	-- Create user commands
	vim.api.nvim_create_user_command("CaptionImagePreviewToggle", preview.toggle, {})
	vim.api.nvim_create_user_command("CaptionImagePreviewRefresh", preview.refresh, {})

	-- Create keymaps (if enabled)
	local keymaps = config.options.keymaps or {}

	-- Toggle keymap
	if keymaps.toggle then
		vim.api.nvim_set_keymap("n", keymaps.toggle, ":CaptionImagePreviewToggle<CR>", {
			silent = true,
			noremap = true,
			desc = "Toggle caption image preview",
		})
	end

	-- Refresh keymap
	if keymaps.refresh then
		vim.api.nvim_set_keymap("n", keymaps.refresh, ":CaptionImagePreviewRefresh<CR>", {
			silent = true,
			noremap = true,
			desc = "Refresh caption image preview",
		})
	end
end

-- Expose internal modules for advanced usage
M.config = config
M.preview = preview

-- Auto-setup so users can just require the plugin
M.setup({})

return M
