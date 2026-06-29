local M = {}

local config = require("caption-image-preview.config")
local state = {
	active = false,
	win = nil,
	buf = nil,
	image = nil,
	updating = false,
	update_timer = nil, -- For debouncing
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

	-- Check cache
	if image_cache[caption_path] and vim.fn.filereadable(image_cache[caption_path]) == 1 then
		return image_cache[caption_path]
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

local function show_message(buf, lines)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local was_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", was_modifiable, { buf = buf })
end

local function render_preview(buf, win, image_path)
	if state.updating then
		return
	end
	state.updating = true

	local function cleanup()
		state.updating = false
	end

	local ok, err = xpcall(function()
		-- Clear buffer
		show_message(buf, {})

		if not image_path then
			local basename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t:r")
			show_message(buf, {
				"No image found",
				"Looking for: " .. basename .. ".[jpg,png,webp]",
				"",
				"Press q or <Esc> to close",
			})
			cleanup()
			return
		end

		local image = get_image()
		if not image then
			cleanup()
			return
		end

		-- Validate window and buffer
		if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
			cleanup()
			return
		end

		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

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
				end
				state.updating = false
			end)
		else
			cleanup()
		end
	end, function(err)
		show_message(buf, {
			"Failed to render image",
			tostring(err),
			"",
			"Press q or <Esc> to close",
		})
		cleanup()
	end)

	if not ok then
		cleanup()
	end
end

local function close_preview()
	-- Cancel any pending update
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
end

-- Single debounced update function
local function schedule_update()
	-- Cancel any pending update
	if state.update_timer then
		state.update_timer:stop()
		state.update_timer:close()
		state.update_timer = nil
	end

	-- Schedule update after a short delay
	state.update_timer = vim.defer_fn(function()
		state.update_timer = nil

		if not state.active or state.updating then
			return
		end

		if state.win and not vim.api.nvim_win_is_valid(state.win) then
			close_preview()
			return
		end

		if not state.win or not state.buf then
			close_preview()
			return
		end

		if not vim.api.nvim_buf_is_valid(state.buf) then
			close_preview()
			return
		end

		local current_file = vim.api.nvim_buf_get_name(0)
		if not is_caption_file(current_file) then
			return
		end

		-- Don't update if we're in the preview buffer
		if vim.api.nvim_get_current_buf() == state.buf then
			return
		end

		-- Clear cache for this file
		image_cache[current_file] = nil

		clear_image()
		local image_path = find_image(current_file)
		render_preview(state.buf, state.win, image_path)
	end, 50) -- 50ms debounce delay
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
	local preview_name = "[Preview] " .. vim.fn.fnamemodify(current_file, ":t:r")
	vim.api.nvim_buf_set_name(preview_buf, preview_name)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = preview_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = preview_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = preview_buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = preview_buf })

	local split_width = math.floor(vim.o.columns * opts.split_ratio)
	if split_width < 1 then
		split_width = math.floor(vim.o.columns * 0.3)
	end
	if split_width > vim.o.columns - 1 then
		split_width = vim.o.columns - 1
	end

	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, preview_buf)
	vim.api.nvim_win_set_width(0, split_width)

	state.win = vim.api.nvim_get_current_win()
	state.buf = preview_buf
	state.active = true
	state.image = nil

	local image_path = find_image(current_file)
	render_preview(state.buf, state.win, image_path)

	vim.api.nvim_buf_set_keymap(state.buf, "n", "q", ':lua require("caption-image-preview.preview").toggle()<CR>', {
		silent = true,
		noremap = true,
	})
	vim.api.nvim_buf_set_keymap(state.buf, "n", "<Esc>", ':lua require("caption-image-preview.preview").toggle()<CR>', {
		silent = true,
		noremap = true,
	})

	vim.api.nvim_set_current_win(original_win)
end

function M.refresh()
	schedule_update()
end

function M.get_state()
	return state
end

local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("CaptionImagePreview", { clear = true })
	local opts = config.get()

	if opts.auto_update then
		-- Single handler for all events
		local function handle_update()
			-- Don't update if we're in the preview buffer
			if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
				if vim.api.nvim_get_current_buf() == state.buf then
					return
				end
			end

			-- Clear cache for current file if it's a caption file
			local current_file = vim.api.nvim_buf_get_name(0)
			if current_file and current_file ~= "" and is_caption_file(current_file) then
				image_cache[current_file] = nil
			end

			schedule_update()
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
