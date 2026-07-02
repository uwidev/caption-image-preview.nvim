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
local caption_cache = {} -- cache for is_caption_file results (boolean)
local basename_cache = {} -- cache for fnamemodify results (string)
local path_cache = {} -- cache for directory/file paths

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

local function sanitize_path(path)
	if not path or path == "" then
		return ""
	end
	-- Remove null bytes and control characters
	local sanitized = path:gsub("%z", ""):gsub("[%c]", "")
	return sanitized
end

local function is_caption_file(filepath)
	if not filepath or filepath == "" then
		return false
	end

	local sanitized = sanitize_path(filepath)

	-- Check caption cache
	if caption_cache[sanitized] ~= nil then
		return caption_cache[sanitized]
	end

	local ext = vim.fn.fnamemodify(sanitized, ":e"):lower()
	local result = ext == "txt"
	caption_cache[sanitized] = result
	return result
end

local function find_image(caption_path)
	if not caption_path or caption_path == "" then
		return nil
	end

	local sanitized = sanitize_path(caption_path)

	-- Fast cache lookup
	local cached = image_cache[sanitized]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		if vim.fn.filereadable(cached) == 1 then
			return cached
		else
			-- File was deleted, clear cache
			image_cache[sanitized] = nil
		end
	end

	-- Cache path components
	local cache_key = sanitized
	if path_cache[cache_key] == nil then
		local dir = vim.fn.fnamemodify(sanitized, ":h")
		local basename = vim.fn.fnamemodify(sanitized, ":t:r")
		path_cache[cache_key] = { dir = dir, basename = basename }
	end

	local paths = path_cache[cache_key]
	local dir = paths.dir
	local basename = paths.basename

	local opts = config.get()

	local found_path = nil
	for _, ext in ipairs(opts.extensions) do
		local candidate = dir .. "/" .. basename .. ext
		if vim.fn.filereadable(candidate) == 1 then
			found_path = candidate
			break
		end
	end

	if found_path then
		image_cache[sanitized] = found_path
		return found_path
	end

	-- Cache the miss too
	image_cache[sanitized] = false
	return nil
end

local function clear_image()
	if state.image then
		local success, err = pcall(function()
			state.image:clear()
		end)
		if not success then
			vim.notify("caption-image-preview: Error clearing image: " .. tostring(err), vim.log.levels.WARN)
		end
		state.image = nil
	end
end

local function clear_buffer(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local success, err = pcall(function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	end)
	if not success then
		vim.notify("caption-image-preview: Error clearing buffer: " .. tostring(err), vim.log.levels.WARN)
	end
end

local function set_message(buf, lines)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local success, err = pcall(function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end)
	if not success then
		vim.notify("caption-image-preview: Error setting message: " .. tostring(err), vim.log.levels.WARN)
	end
end

local function update_buffer_name(buf, image_path)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local name
	local sanitized = sanitize_path(image_path or "")

	if sanitized and sanitized ~= "" then
		local cache_key = sanitized
		if basename_cache[cache_key] == nil then
			basename_cache[cache_key] = vim.fn.fnamemodify(sanitized, ":t:r")
		end
		name = "[Preview] " .. basename_cache[cache_key]
	else
		if state.last_file then
			local cache_key = state.last_file
			if basename_cache[cache_key] == nil then
				basename_cache[cache_key] = vim.fn.fnamemodify(state.last_file, ":t:r")
			end
			name = "[Preview] " .. basename_cache[cache_key]
		else
			local ok, current_name = pcall(vim.api.nvim_buf_get_name, buf)
			if ok and current_name and current_name ~= "" then
				name = current_name
			else
				name = "[Preview]"
			end
		end
	end

	local success, err = pcall(function()
		vim.api.nvim_buf_set_name(buf, name)
	end)
	if not success then
		vim.notify("caption-image-preview: Error setting buffer name: " .. tostring(err), vim.log.levels.DEBUG)
	end
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
	clear_buffer(buf)

	if not image_path then
		local basename
		if state.last_file then
			local cache_key = state.last_file
			if basename_cache[cache_key] == nil then
				basename_cache[cache_key] = vim.fn.fnamemodify(state.last_file, ":t:r")
			end
			basename = basename_cache[cache_key]
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

	if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
		cleanup()
		return
	end

	-- Use pcall for image creation
	local ok, img = pcall(function()
		return image.from_file(image_path, {
			window = win,
			buffer = buf,
			x = 0,
			y = 0,
			max_width_window_percentage = 100,
			max_height_window_percentage = 100,
			with_virtual_padding = true,
			inline = true,
		})
	end)

	if not ok then
		vim.notify("caption-image-preview: Error creating image: " .. tostring(img), vim.log.levels.ERROR)
		cleanup()
		return
	end

	if img then
		state.image = img
		-- Use vim.schedule to avoid blocking
		vim.schedule(function()
			local render_ok, render_err = pcall(function()
				if
					state.active
					and state.win == win
					and state.buf == buf
					and vim.api.nvim_win_is_valid(win)
					and vim.api.nvim_buf_is_valid(buf)
				then
					img:render()
				else
					img:clear()
					if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
						clear_buffer(state.buf)
					end
				end
			end)
			if not render_ok then
				vim.notify(
					"caption-image-preview: Error rendering image: " .. tostring(render_err),
					vim.log.levels.ERROR
				)
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
		local success, err = pcall(function()
			state.update_timer:stop()
			state.update_timer:close()
		end)
		if not success then
			vim.notify("caption-image-preview: Error closing timer: " .. tostring(err), vim.log.levels.DEBUG)
		end
		state.update_timer = nil
	end

	clear_image()

	if state.win and vim.api.nvim_win_is_valid(state.win) then
		local success, err = pcall(function()
			vim.api.nvim_win_close(state.win, true)
		end)
		if not success then
			vim.notify("caption-image-preview: Error closing window: " .. tostring(err), vim.log.levels.WARN)
		end
	end

	state.active = false
	state.win = nil
	state.buf = nil
	state.image = nil
	state.last_file = nil
end

local function schedule_update()
	-- Cancel pending
	if state.update_timer then
		local success, err = pcall(function()
			state.update_timer:stop()
			state.update_timer:close()
		end)
		if not success then
			vim.notify("caption-image-preview: Error stopping timer: " .. tostring(err), vim.log.levels.DEBUG)
		end
		state.update_timer = nil
	end

	state.update_timer = vim.defer_fn(function()
		state.update_timer = nil

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

		if vim.api.nvim_get_current_buf() == state.buf then
			return
		end

		if current_file == state.last_file then
			return
		end
		state.last_file = current_file

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

	local preview_buf = vim.api.nvim_create_buf(false, true)

	-- Set buffer options with error handling
	local function set_buffer_options(buf)
		local options = {
			buftype = "nofile",
			bufhidden = "wipe",
			swapfile = false,
			modifiable = true,
		}

		for opt, value in pairs(options) do
			local success, err = pcall(function()
				vim.api.nvim_set_option_value(opt, value, { buf = buf })
			end)
			if not success then
				vim.notify(
					"caption-image-preview: Error setting buffer option " .. opt .. ": " .. tostring(err),
					vim.log.levels.WARN
				)
			end
		end
	end

	set_buffer_options(preview_buf)

	local split_width = math.floor(vim.o.columns * opts.split_ratio)
	if split_width < 1 then
		split_width = math.floor(vim.o.columns * 0.3)
	end
	if split_width > vim.o.columns - 1 then
		split_width = vim.o.columns - 1
	end

	local success, err = pcall(function()
		vim.cmd("vsplit")
		vim.api.nvim_win_set_buf(0, preview_buf)
		vim.api.nvim_win_set_width(0, split_width)
	end)

	if not success then
		vim.notify("caption-image-preview: Error creating split: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	state.win = vim.api.nvim_get_current_win()
	state.buf = preview_buf
	state.active = true
	state.image = nil
	state.last_file = current_file

	local image_path = find_image(current_file)
	render_preview(state.buf, state.win, image_path)

	vim.api.nvim_set_current_win(original_win)
end

function M.refresh()
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
			if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
				if vim.api.nvim_get_current_buf() == state.buf then
					return
				end
			end

			local current_file = vim.api.nvim_buf_get_name(0)
			if current_file ~= "" and is_caption_file(current_file) then
				schedule_update()
			end
		end

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
