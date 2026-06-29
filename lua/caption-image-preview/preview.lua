local M = {}

local config = require("caption-image-preview.config")
local state = {
	active = false,
	win = nil,
	buf = nil,
	image = nil,
	updating = false,
}

local image_nvim = nil

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

	local dir = vim.fn.fnamemodify(caption_path, ":h")
	local basename = vim.fn.fnamemodify(caption_path, ":t:r")
	local opts = config.get()

	for _, ext in ipairs(opts.extensions) do
		local candidate = dir .. "/" .. basename .. ext
		if vim.fn.filereadable(candidate) == 1 then
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
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
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
		show_message(buf, {})

		if not image_path then
			local basename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t:r")
			show_message(buf, {
				"No image found",
				"Looking for: " .. basename .. ".[jpg,png,webp]",
				"",
				"Press q or <Esc> to close",
			})
			return
		end

		local image = get_image()
		if not image then
			return
		end

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
			vim.schedule(function()
				img:render()
				state.updating = false
			end)
			state.image = img
		end
	end, function(err)
		show_message(buf, {
			"Failed to render image",
			tostring(err),
			"",
			"Press q or <Esc> to close",
		})
	end)

	if not ok then
		cleanup()
	end
end

local function close_preview()
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

local function update_preview()
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

	clear_image()
	local image_path = find_image(current_file)
	render_preview(state.buf, state.win, image_path)
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

	local split_width = math.floor(vim.o.columns * opts.split_ratio)
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
	update_preview()
end

function M.get_state()
	return state
end

local function setup_autocmds()
	local group = vim.api.nvim_create_augroup("CaptionImagePreview", { clear = true })
	local opts = config.get()

	if opts.auto_update then
		vim.api.nvim_create_autocmd("BufEnter", {
			group = group,
			pattern = opts.caption_patterns,
			callback = function()
				if vim.api.nvim_get_current_buf() == state.buf then
					return
				end
				update_preview()
			end,
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
