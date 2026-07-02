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
	current_image_path = nil,
}

local image_nvim = nil
local image_cache = {}
local caption_cache = {}
local basename_cache = {}
local path_cache = {}

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
	local sanitized = path:gsub("%z", ""):gsub("[%c]", "")
	return sanitized
end

local function is_caption_file(filepath)
	if not filepath or filepath == "" then
		return false
	end

	local sanitized = sanitize_path(filepath)
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

	local cached = image_cache[sanitized]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		if vim.fn.filereadable(cached) == 1 then
			return cached
		else
			image_cache[sanitized] = nil
		end
	end

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

	clear_image()
	update_buffer_name(buf, image_path)
	clear_buffer(buf)

	-- Store for later redraws
	state.current_image_path = image_path

	if not image_path then
		state.current_image_path = nil
		local basename = state.last_file
				and (basename_cache[state.last_file] or vim.fn.fnamemodify(state.last_file, ":t:r"))
			or "unknown"
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

	local opts = config.get()
	local height_percent = opts.render_height_percent or 95

	local ok, img = pcall(function()
		return image.from_file(image_path, {
			window = win,
			buffer = buf,
			x = 0,
			y = 0,
			max_width_window_percentage = 100,
			max_height_window_percentage = height_percent,
			with_virtual_padding = false,
			inline = false,
		})
	end)

	if not ok then
		vim.notify("caption-image-preview: Error creating image: " .. tostring(img), vim.log.levels.ERROR)
		cleanup()
		return
	end

	if not img then
		cleanup()
		return
	end

	state.image = img
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
		vim.notify("caption-image-preview: Error rendering image: " .. tostring(render_err), vim.log.levels.ERROR)
	end

	cleanup()
end

function M.redraw_preview()
	if not state.active then
		vim.notify("caption-image-preview: Preview not active", vim.log.levels.WARN)
		return
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.notify("caption-image-preview: Preview window is invalid", vim.log.levels.WARN)
		return
	end

	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		vim.notify("caption-image-preview: Preview buffer is invalid", vim.log.levels.WARN)
		return
	end

	if not state.current_image_path then
		vim.notify("caption-image-preview: No image to redraw", vim.log.levels.WARN)
		return
	end

	-- Clear the current image to force a fresh render
	clear_image()
	render_preview(state.buf, state.win, state.current_image_path)
end

local function close_preview()
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

	state.current_image_path = nil
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

function M.adjust_split()
	if not state.active then
		vim.notify("caption-image-preview: Preview not active", vim.log.levels.WARN)
		return
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.notify("caption-image-preview: Preview window is invalid", vim.log.levels.WARN)
		return
	end

	local left_win = nil
	local wins = vim.api.nvim_list_wins()
	for _, w in ipairs(wins) do
		if w ~= state.win then
			left_win = w
			break
		end
	end

	if not left_win then
		vim.notify("caption-image-preview: No other window found", vim.log.levels.WARN)
		return
	end

	local buf = vim.api.nvim_win_get_buf(left_win)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	local max_len = 0
	for _, line in ipairs(lines) do
		if not line:match("%.$") then
			local len = #line
			if len > max_len then
				max_len = len
			end
		end
	end

	local wininfo = vim.fn.getwininfo(left_win)[1]
	if not wininfo then
		vim.notify("caption-image-preview: Cannot get window info", vim.log.levels.WARN)
		return
	end
	local textoff = wininfo.textoff

	local opts = config.get()
	local padding = opts.split_padding or 2
	local total_cols = vim.o.columns

	local desired_split_col = textoff + max_len + padding

	local min_ratio = opts.split_ratio or 0.4
	local min_preview_width = math.floor(total_cols * min_ratio)
	if min_preview_width < 1 then
		min_preview_width = 1
	end

	local max_split_col = total_cols - min_preview_width
	if desired_split_col > max_split_col then
		desired_split_col = max_split_col
	end

	if desired_split_col < 1 then
		desired_split_col = 1
	end

	local new_preview_width = total_cols - desired_split_col
	vim.api.nvim_win_set_width(state.win, new_preview_width)

	vim.notify(
		string.format(
			"Preview adjusted: split at col %d (width %d, textoff %d, max_len %d)",
			desired_split_col,
			new_preview_width,
			textoff,
			max_len
		),
		vim.log.levels.INFO
	)
end

function M.reset_split()
	if not state.active then
		vim.notify("caption-image-preview: Preview not active", vim.log.levels.WARN)
		return
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.notify("caption-image-preview: Preview window is invalid", vim.log.levels.WARN)
		return
	end

	local opts = config.get()
	local total_cols = vim.o.columns
	local min_ratio = opts.split_ratio or 0.4

	local preview_width = math.floor(total_cols * min_ratio)
	if preview_width < 1 then
		preview_width = 1
	end
	if preview_width > total_cols - 1 then
		preview_width = total_cols - 1
	end

	vim.api.nvim_win_set_width(state.win, preview_width)

	vim.notify(
		string.format("Preview reset to ratio: width %d (%.1f%%)", preview_width, min_ratio * 100),
		vim.log.levels.INFO
	)
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

	vim.api.nvim_create_autocmd("WinResized", {
		group = group,
		callback = function(args)
			if state.active and state.win and tonumber(args.win) == state.win then
				M.refresh()
			end
		end,
	})
end

setup_autocmds()

return M
