-- Default configuration
local defaults = {
    split_ratio = 0.4,  -- 40% of screen width
    extensions = { '.jpg', '.jpeg', '.png', '.webp', '.gif' },
    caption_patterns = { '*.txt' },
    keymap_prefix = '<leader>',  -- Prefix for keymaps
    auto_update = true,          -- Auto-update on buffer switch
}

local M = {}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
    M.options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
end

return M
