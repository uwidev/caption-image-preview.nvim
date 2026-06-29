local M = {}

local config = require("caption-image-preview.config")
local state = {
	active = false,
	win = nil,
	buf = nil,
	image = nil,
	updating = false,
	update_timer = nil,
	last_file = nil,
}

local image_nvim = nil
local image_cache = {}

local function get_image()
	if image_nvim then
		return image_nvim
	end

	local ok, img = pcall(require, "image")
	if not ok then
		vim.notify("caption-image-preview: image.nvim not installed", vim.log.levels.ERROR)
		return nil
	end
	image_nvim = img
	return image_nvim
end

local function is_caption_file(filepath)
	if filepath == "" then
		return false
	end
	local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
	return ext == "txt"
end

local function find_image(caption_path)
	if caption_path == "" then
		return nil
	end

	-- Fast cache lookup
	local cached = image_cache[caption_path]
	if cached and vim.fn.filereadable(cached) == 1 then
		return cached
	end

	local dir = vim.fn.fnamemodify(caption_path, ":h")
	local basename = vim.fn.fnamemodify(caption_path, ":t:r")
	local opts = config.get()

	for _, ext in ipairs(opts.extensions) do
		local candidate = dir .. "/" .. basename .. ext
		if vim.fn.filereadable(candidate) == 1 then
			image_cache[caption_path] = candidate
			return candidate
		end
	end

	-- Cache the miss too
	image_cache[caption_path] = false
	return nil
end

local function clear_image()
	if state.image then
		pcall(function()
			state.image:clear()
		end)
		state.image = nil
	end
end

-- Fast buffer clear - no modifiable toggling needed if we set it once
local function clear_buffer(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	-- Buffer is already modifiable from setup
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

-- Set message without unnecessary clearing
local function set_message(buf, lines)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	-- Buffer is already modifiable from setup
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local function update_buffer_name(buf, image_path)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local name

	if image_path then
		name = "[Preview] " .. vim.fn.fnamemodify(image_path, ":t:r")
	else
		if state.last_file then
			name = "[Preview] " .. vim.fn.fnamemodify(state.last_file, ":t:r")
		else
			local current_name = vim.api.nvim_buf_get_name(buf)
			if current_name and current_name ~= "" then
				name = current_name
			else
				name = "[Preview]"
			end
		end
	end

	pcall(function()
		vim.api.nvim_buf_set_name(buf, name)
	end)
end

local function render_preview(buf, win, image_path)
	if state.updating then
		return
	end
	state.updating = true

	local function cleanup()
		state.updating = false
	end

	update_buffer_name(buf, image_path)
	-- Fast path: clear buffer and show message/ image
	clear_buffer(buf)

	if not image_path then
		local basename
		if state.last_file then
			basename = vim.fn.fnamemodify(state.last_file, ":t:r")
		else
			basename = "unknown"
		end
		set_message(buf, {
			"No image found",
			"Looking for: " .. basename .. ".[jpg,png,webp]",
		})
		cleanup()
		return
	end

	local image = get_image()
	if not image then
		cleanup()
		return
	end

	-- Quick validation
	if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
		cleanup()
		return
	end

	-- Create image (buffer is already modifiable)
	local img = image.from_file(image_path, {
		window = win,
		buffer = buf,
		x = 0,
		y = 0,
		max_width_window_percentage = 100,
		max_height_window_percentage = 100,
		with_virtual_padding = true,
		inline = true,
	})

	if img then
		state.image = img
		vim.schedule(function()
			if
				state.active
				and state.win == win
				and state.buf == buf
				and vim.api.nvim_win_is_valid(win)
				and vim.api.nvim_buf_is_valid(buf)
			then
				pcall(function()
					img:render()
				end)
			else
				pcall(function()
					img:clear()
				end)
				if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
					clear_buffer(state.buf)
				end
			end
			state.updating = false
		end)
	else
		cleanup()
	end
end

local function close_preview()
	-- Cancel pending update
	if state.update_timer then
		state.update_timer:stop()
		state.update_timer:close()
		state.update_timer = nil
	end

	clear_image()

	if state.win and vim.api.nvim_win_is_valid(state.win) then
		local wins = vim.api.nvim_list_wins()
		if #wins > 1 then
			pcall(function()
				vim.api.nvim_win_close(state.win, true)
			end)
		end
	end

	state.active = false
	state.win = nil
	state.buf = nil
	state.image = nil
	state.last_file = nil
end

-- Fast debounced update
local function schedule_update()
	-- Cancel pending
	if state.update_timer then
		state.update_timer:stop()
		state.update_timer:close()
		state.update_timer = nil
	end

	state.update_timer = vim.defer_fn(function()
		state.update_timer = nil

		-- Quick validity checks
		if not state.active or state.updating then
			return
		end

		if not state.win or not vim.api.nvim_win_is_valid(state.win) then
			close_preview()
			return
		end

		if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
			close_preview()
			return
		end

		local current_file = vim.api.nvim_buf_get_name(0)
		if not is_caption_file(current_file) then
			return
		end

		-- Skip if we're in the preview buffer
		if vim.api.nvim_get_current_buf() == state.buf then
			return
		end

		-- Skip if same file (no need to re-render)
		if current_file == state.last_file then
			return
		end
		state.last_file = current_file

		-- Only clear cache if file changed
		-- (cache is already keyed by file path, so no need to clear)
		clear_image()
		local image_path = find_image(current_file)
		render_preview(state.buf, state.win, image_path)
	end, 50)
end

function M.toggle()
	if not get_image() then
		return
	end

	if state.active then
		close_preview()
		return
	end

	local current_file = vim.api.nvim_buf_get_name(0)
	if not is_caption_file(current_file) then
		vim.notify("caption-image-preview: Not a caption file", vim.log.levels.WARN)
		return
	end

	local original_win = vim.api.nvim_get_current_win()
	local opts = config.get()

	-- Create buffer
	local preview_buf = vim.api.nvim_create_buf(false, true)

	-- Set buffer options once
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = preview_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = preview_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = preview_buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = preview_buf })

	-- Calculate split width
	local split_width = math.floor(vim.o.columns * opts.split_ratio)
	if split_width < 1 then
		split_width = math.floor(vim.o.columns * 0.3)
	end
	if split_width > vim.o.columns - 1 then
		split_width = vim.o.columns - 1
	end

	-- Create split
	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, preview_buf)
	vim.api.nvim_win_set_width(0, split_width)

	-- Update state
	state.win = vim.api.nvim_get_current_win()
	state.buf = preview_buf
	state.active = true
	state.image = nil
	state.last_file = current_file

	-- Render image
	local image_path = find_image(current_file)
	render_preview(state.buf, state.win, image_path)

	vim.api.nvim_set_current_win(original_win)
end

function M.refresh()
	-- Force refresh by clearing last_file
	state.last_file = nil
	schedule_update()
end

function M.get_state()
	return state
end

local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("CaptionImagePreview", { clear = true })
	local opts = config.get()

	if opts.auto_update then
		local function handle_update()
			-- Quick preview buffer check
			if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
				if vim.api.nvim_get_current_buf() == state.buf then
					return
				end
			end

			-- Only proceed if it's a caption file
			local current_file = vim.api.nvim_buf_get_name(0)
			if current_file ~= "" and is_caption_file(current_file) then
				schedule_update()
			end
		end

		-- Consolidated autocommands
		vim.api.nvim_create_autocmd({
			"BufEnter",
			"TextChanged",
			"TextChangedI",
		}, {
			group = group,
			pattern = opts.caption_patterns,
			callback = handle_update,
		})
	end

	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			if state.win and tonumber(args.match) == state.win then
				close_preview()
			end
		end,
	})
end

setup_autocmds()

return M
