-- Main entry point
local config = require("caption-image-preview.config")
local preview = require("caption-image-preview.preview")

local M = {}

function M.setup(opts)
	config.setup(opts)

	-- Create user commands
	vim.api.nvim_create_user_command("CaptionImagePreviewToggle", preview.toggle, {})
	vim.api.nvim_create_user_command("CaptionImagePreviewRefresh", preview.refresh, {})
	vim.api.nvim_create_user_command("CaptionImagePreviewAdjust", preview.adjust_split, {})
	vim.api.nvim_create_user_command("CaptionImagePreviewReset", preview.reset_split, {})

	-- Create keymaps (if enabled)
	local opts_config = config.get()
	local keymaps = opts_config.keymaps or {}

	if keymaps.toggle then
		vim.api.nvim_set_keymap("n", keymaps.toggle, ":CaptionImagePreviewToggle<CR>", {
			silent = true,
			noremap = true,
			desc = "Toggle caption image preview",
		})
	end

	if keymaps.refresh then
		vim.api.nvim_set_keymap("n", keymaps.refresh, ":CaptionImagePreviewRefresh<CR>", {
			silent = true,
			noremap = true,
			desc = "Refresh caption image preview",
		})
	end

	if keymaps.adjust then
		vim.api.nvim_set_keymap("n", keymaps.adjust, ":CaptionImagePreviewAdjust<CR>", {
			silent = true,
			noremap = true,
			desc = "Adjust caption image preview split",
		})
	end

	if keymaps.reset then
		vim.api.nvim_set_keymap("n", keymaps.reset, ":CaptionImagePreviewReset<CR>", {
			silent = true,
			noremap = true,
			desc = "Reset caption image preview split to ratio",
		})
	end
end

-- Expose internal modules for advanced usage
M.config = config
M.preview = preview
M.redraw_preview = preview.redraw_preview

return M
