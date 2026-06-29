# caption-image-preview.nvim

Preview images associated with caption files (.txt) in Neovim.

## Requirements

- Neovim 0.9+
- [image.nvim](https://github.com/3rd/image.nvim) with Sixel/Kitty support

## Installation

### Lazy.nvim

```lua
{
    "uwidev/caption-image-preview.nvim",
    config = function()
        require('caption-image-preview').setup({
            split_ratio = 0.4,
            extensions = { '.jpg', '.png', '.webp' },
        })
    end
}
````
