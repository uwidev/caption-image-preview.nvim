-- Main entry point
local config = require('caption-image-preview.config')
local preview = require('caption-image-preview.preview')

local M = {}

function M.setup(opts)
    config.setup(opts)

    -- Create user commands
    vim.api.nvim_create_user_command('CaptionImagePreviewToggle', preview.toggle, {})
    vim.api.nvim_create_user_command('CaptionImagePreviewRefresh', preview.refresh, {})

    -- Create keymaps
    local prefix = config.options.keymap_prefix or '<leader>'
    vim.api.nvim_set_keymap('n', prefix .. 'cip', ':CaptionImagePreviewToggle<CR>', {
        silent = true,
        noremap = true,
        desc = "Toggle caption image preview"
    })
    vim.api.nvim_set_keymap('n', prefix .. 'cir', ':CaptionImagePreviewRefresh<CR>', {
        silent = true,
        noremap = true,
        desc = "Refresh caption image preview"
    })
end

-- Expose internal modules for advanced usage
M.config = config
M.preview = preview

return M
