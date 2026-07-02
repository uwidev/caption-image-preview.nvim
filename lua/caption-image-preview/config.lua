-- config.lua - Configuration management

local defaults = {
	split_ratio = 0.4,
	extensions = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
	caption_patterns = { "*.txt" },
	auto_update = true,
	split_padding = 2,
	render_height_percent = 96, -- percentage of window height to use (avoid bottom clipping)
	keymaps = {
		toggle = "<leader>cip",
		refresh = "<leader>cir",
		adjust = "<leader>cia",
		reset = "<leader>civ",
	},
}

local M = {}
M.options = vim.deepcopy(defaults)

local function validate_config(opts)
	local valid = vim.deepcopy(opts)

	if valid.split_ratio then
		if type(valid.split_ratio) ~= "number" or valid.split_ratio < 0 or valid.split_ratio > 1 then
			vim.notify("caption-image-preview: split_ratio must be between 0 and 1, using default", vim.log.levels.WARN)
			valid.split_ratio = defaults.split_ratio
		end
	end

	if valid.extensions and type(valid.extensions) ~= "table" then
		vim.notify("caption-image-preview: extensions must be a table, using default", vim.log.levels.WARN)
		valid.extensions = defaults.extensions
	end

	if valid.auto_update and type(valid.auto_update) ~= "boolean" then
		vim.notify("caption-image-preview: auto_update must be a boolean, using default", vim.log.levels.WARN)
		valid.auto_update = defaults.auto_update
	end

	if valid.split_padding and type(valid.split_padding) ~= "number" then
		vim.notify("caption-image-preview: split_padding must be a number, using default", vim.log.levels.WARN)
		valid.split_padding = defaults.split_padding
	end

	if valid.render_height_percent and type(valid.render_height_percent) ~= "number" then
		vim.notify("caption-image-preview: render_height_percent must be a number, using default", vim.log.levels.WARN)
		valid.render_height_percent = defaults.render_height_percent
	end

	if valid.keymaps then
		if valid.keymaps.toggle and type(valid.keymaps.toggle) ~= "string" and valid.keymaps.toggle ~= false then
			vim.notify(
				"caption-image-preview: keymaps.toggle must be a string or false, using default",
				vim.log.levels.WARN
			)
			valid.keymaps.toggle = defaults.keymaps.toggle
		end
		if valid.keymaps.refresh and type(valid.keymaps.refresh) ~= "string" and valid.keymaps.refresh ~= false then
			vim.notify(
				"caption-image-preview: keymaps.refresh must be a string or false, using default",
				vim.log.levels.WARN
			)
			valid.keymaps.refresh = defaults.keymaps.refresh
		end
		if valid.keymaps.adjust and type(valid.keymaps.adjust) ~= "string" and valid.keymaps.adjust ~= false then
			vim.notify(
				"caption-image-preview: keymaps.adjust must be a string or false, using default",
				vim.log.levels.WARN
			)
			valid.keymaps.adjust = defaults.keymaps.adjust
		end
		if valid.keymaps.reset and type(valid.keymaps.reset) ~= "string" and valid.keymaps.reset ~= false then
			vim.notify(
				"caption-image-preview: keymaps.reset must be a string or false, using default",
				vim.log.levels.WARN
			)
			valid.keymaps.reset = defaults.keymaps.reset
		end
	end

	return valid
end

function M.setup(opts)
	local user_opts = validate_config(opts or {})
	M.options = vim.tbl_deep_extend("force", defaults, user_opts)
end

function M.get()
	return vim.deepcopy(M.options)
end

function M.get_defaults()
	return vim.deepcopy(defaults)
end

function M.get_value(key)
	return M.options[key]
end

function M.reload()
	M.options = vim.deepcopy(defaults)
end

return M
