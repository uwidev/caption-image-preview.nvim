# caption-image-preview.nvim

Preview images associated with caption files (.txt) in Neovim.

## Requirements

- Neovim 0.9+
- image.nvim with Sixel/Kitty support

## Installation

### vim.pack

```lua
vim.pack.add { gh 'uwidev/caption-image-preview.nvim' }
require('caption-image-preview').setup {}
```


### packer.nvim

```lua
use {
    "uwidev/caption-image-preview.nvim",
    config = function()
        require('caption-image-preview').setup()
    end
}
```

### lazy.nvim

```lua
{
    "uwidev/caption-image-preview.nvim",
    config = function()
        require('caption-image-preview').setup()
    end
}
```

### vim-plug

```vim
Plug 'uwidev/caption-image-preview.nvim'
```

### paq.nvim

```lua
"uwidev/caption-image-preview.nvim"
```

### Manual

Clone into your Neovim packages directory:

```bash
git clone https://github.com/uwidev/caption-image-preview.nvim ~/.local/share/nvim/site/pack/plugins/start/caption-image-preview.nvim
```

## Configuration (Optional)

The plugin works without configuration. To customize:

```lua
require('caption-image-preview').setup({
    split_ratio = 0.4,                    -- Preview window width (40%)
    extensions = { '.jpg', '.jpeg', '.png', '.webp', '.gif' },
    caption_patterns = { '*.txt' },
    auto_update = true,
    keymaps = {
        toggle = '<leader>cip',
        refresh = '<leader>cir',
    },
})
```

## Usage

- `<leader>cip` or `:CaptionImagePreviewToggle` - Toggle preview
- `<leader>cir` or `:CaptionImagePreviewRefresh` - Refresh preview
