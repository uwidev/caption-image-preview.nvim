-- config.lua - Configuration management with validation and safety

local defaults = {
	split_ratio = 0.4, -- 0-1, percentage of screen width
	extensions = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
	caption_patterns = { "*.txt" },
	auto_update = true,
	keymaps = {
		toggle = "<leader>cip",
		refresh = "<leader>cir",
	},
}

local M = {}
M._setup_called = false
M.options = vim.deepcopy(defaults)

-- Deep copy function that preserves metatables
local function deepcopy(orig)
	local copy
	if type(orig) == "table" then
		copy = {}
		for k, v in pairs(orig) do
			copy[k] = deepcopy(v)
		end
		setmetatable(copy, getmetatable(orig))
	else
		copy = orig
	end
	return copy
end

-- Validate user configuration
local function validate_config(opts)
	if opts.split_ratio then
		if type(opts.split_ratio) ~= "number" or opts.split_ratio < 0 or opts.split_ratio > 1 then
			vim.notify(
				"caption-image-preview: split_ratio must be between 0 and 1, using default",
				vim.log.levels.ERROR
			)
			opts.split_ratio = defaults.split_ratio
		end
	end

	if opts.extensions and type(opts.extensions) ~= "table" then
		vim.notify("caption-image-preview: extensions must be a table, using default", vim.log.levels.ERROR)
		opts.extensions = defaults.extensions
	end

	if opts.auto_update and type(opts.auto_update) ~= "boolean" then
		vim.notify("caption-image-preview: auto_update must be a boolean, using default", vim.log.levels.ERROR)
		opts.auto_update = defaults.auto_update
	end

	if opts.keymaps then
		if opts.keymaps.toggle and type(opts.keymaps.toggle) ~= "string" and opts.keymaps.toggle ~= false then
			vim.notify(
				"caption-image-preview: keymaps.toggle must be a string or false, using default",
				vim.log.levels.ERROR
			)
			opts.keymaps.toggle = defaults.keymaps.toggle
		end
		if opts.keymaps.refresh and type(opts.keymaps.refresh) ~= "string" and opts.keymaps.refresh ~= false then
			vim.notify(
				"caption-image-preview: keymaps.refresh must be a string or false, using default",
				vim.log.levels.ERROR
			)
			opts.keymaps.refresh = defaults.keymaps.refresh
		end
	end

	return opts
end

-- Setup configuration
function M.setup(opts)
	if M._setup_called then
		vim.notify("caption-image-preview: setup already called, ignoring", vim.log.levels.WARN)
		return
	end
	M._setup_called = true

	local user_opts = validate_config(opts or {})
	M.options = vim.tbl_deep_extend("force", deepcopy(defaults), user_opts)
end

-- Get configuration (read-only copy)
function M.get()
	return deepcopy(M.options)
end

-- Get defaults
function M.get_defaults()
	return deepcopy(defaults)
end

-- Get a specific value
function M.get_value(key)
	return M.options[key]
end

-- Reload to defaults (useful for testing)
function M.reload()
	M.options = deepcopy(defaults)
	M._setup_called = false
end

-- Auto-initialize so users don't need to call setup
M.setup({})

return M
