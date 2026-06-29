local M = {}

local config = require('caption-image-preview.config')
local state = {
    active = false,
    win = nil,
    buf = nil,
    image = nil,
}

-- Check if we have image.nvim
local function has_image_nvim()
    local ok, _ = pcall(require, 'image')
    return ok
end

-- Use user's existing image.nvim settings
local function get_image()
    if not has_image_nvim() then
        vim.notify("caption-image-preview: image.nvim not installed", vim.log.levels.ERROR)
        return nil
    end
    return require('image')
end

local function is_caption_file(filepath)
    if filepath == '' then
        return false
    end
    local ext = vim.fn.fnamemodify(filepath, ':e'):lower()
    return ext == 'txt'
end

local function find_image(caption_path)
    if caption_path == '' then
        return nil
    end
    local dir = vim.fn.fnamemodify(caption_path, ':h')
    local basename = vim.fn.fnamemodify(caption_path, ':t:r')

    for _, ext in ipairs(config.options.extensions) do
        local candidate = dir .. '/' .. basename .. ext
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

local function render_preview(buf, win, image_path)
    clear_image()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

    if not image_path then
        local basename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t:r')
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "No image found",
            "Looking for: " .. basename .. ".[jpg,png,webp]",
            "",
            "Press q or <Esc> to close"
        })
        return
    end

    local image = get_image()
    if not image then
        return
    end

    local ok, err = pcall(function()
        local img = image.from_file(image_path, {
            window = win,
            buffer = buf,
            x = 0,
            y = 0,
        })
        if img then
            img:render()
            state.image = img
        end
    end)

    if not ok then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Failed to render image",
            tostring(err),
            "",
            "Press q or <Esc> to close"
        })
    end
end

local function update_preview()
    if not state.active then
        return
    end

    if not vim.api.nvim_win_is_valid(state.win) or not vim.api.nvim_buf_is_valid(state.buf) then
        state.active = false
        state.image = nil
        state.win = nil
        state.buf = nil
        return
    end

    local current_file = vim.api.nvim_buf_get_name(0)
    if not is_caption_file(current_file) then
        return
    end

    local image_path = find_image(current_file)
    render_preview(state.buf, state.win, image_path)
end

function M.toggle()
    if not has_image_nvim() then
        vim.notify("caption-image-preview: Requires image.nvim", vim.log.levels.ERROR)
        return
    end

    if state.active then
        clear_image()
        if state.win and vim.api.nvim_win_is_valid(state.win) then
            vim.api.nvim_win_close(state.win, true)
        end
        state.active = false
        state.buf = nil
        state.win = nil
        return
    end

    local current_file = vim.api.nvim_buf_get_name(0)
    if not is_caption_file(current_file) then
        vim.notify("caption-image-preview: Not a caption file", vim.log.levels.WARN)
        return
    end

    local original_win = vim.api.nvim_get_current_win()

    local preview_buf = vim.api.nvim_create_buf(false, true)
    local preview_name = "[Preview] " .. vim.fn.fnamemodify(current_file, ':t:r')
    vim.api.nvim_buf_set_name(preview_buf, preview_name)
    vim.api.nvim_buf_set_option(preview_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(preview_buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(preview_buf, 'swapfile', false)

    local split_width = math.floor(vim.o.columns * config.options.split_ratio)
    vim.api.nvim_command('vsplit')
    vim.api.nvim_win_set_buf(0, preview_buf)
    vim.api.nvim_win_set_width(0, split_width)

    state.win = vim.api.nvim_get_current_win()
    state.buf = preview_buf
    state.active = true
    state.image = nil

    local image_path = find_image(current_file)
    render_preview(state.buf, state.win, image_path)

    vim.api.nvim_buf_set_keymap(state.buf, 'n', 'q', ':bd!<CR>', {
        silent = true,
        noremap = true
    })
    vim.api.nvim_buf_set_keymap(state.buf, 'n', '<Esc>', ':bd!<CR>', {
        silent = true,
        noremap = true
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
    local group = vim.api.nvim_create_augroup('CaptionImagePreview', { clear = true })

    if config.options.auto_update then
        vim.api.nvim_create_autocmd('BufEnter', {
            group = group,
            pattern = config.options.caption_patterns,
            callback = update_preview,
        })
    end

    vim.api.nvim_create_autocmd('WinClosed', {
        group = group,
        callback = function(args)
            if state.win and tonumber(args.match) == state.win then
                clear_image()
                state.active = false
                state.win = nil
                state.buf = nil
                state.image = nil
            end
        end,
    })
end

setup_autocmds()

return M
