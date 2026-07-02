# caption-image-preview.nvim

Preview images associated with caption files (.txt) in Neovim.

## Requirements

- Neovim 0.9+
- [image.nvim](https://github.com/3rd/image.nvim) with Sixel/Kitty support

## Installation

### vim.pack

```lua
vim.pack.add { gh 'uwidev/caption-image-preview.nvim' }

require('caption-image-preview').setup {
    split_ratio = 0.4,
    extensions = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
    caption_patterns = { "*.txt" },
    auto_update = true,
    split_padding = 2,
    render_height_percent = 95,
    keymaps = {
        toggle = "<leader>cip",
        refresh = "<leader>cir",
        adjust = "<leader>cia",
        reset = "<leader>civ"
    },
}
```

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
```

## Configuration

|Option                 |Type   |Default                               |Description                                                                                         |
|-----------------------|-------|--------------------------------------|----------------------------------------------------------------------------------------------------|
|`split_ratio`          |number |0.4                                   |Fraction of screen width for the preview window (0–1).                                            |
|`extensions`           |table  |{".jpg",".jpeg",".png",".webp",".gif"}|Image file extensions to look for.                                                                  |
|`caption_patterns`     |table  |{"*.txt"}                             |File patterns for caption files.                                                                    |
|`auto_update`          |boolean|true                                  |Automatically update preview on buffer enter and text changes.                                      |
|`split_padding`        |number |2                                     |Extra columns to add after the longest line when using `:CaptionImagePreviewAdjust`.                |
|`render_height_percent`|number |95                                    |Maximum height percentage for the rendered image (1–100).                                         |
|`keymaps`              |table  |See below                             |Keymap overrides. Disable with `false`.                                                             |
|`auto_adjust_split`    |boolean|false                                 |Automatically adjust split position on toggle and buffer change (uses `:CaptionImagePreviewAdjust`).|

### On `auto_adjust_split`
Enable this if you frequently navigate between caption files and want the preview window to automatically reposition itself to the longest line. Default is `false` to avoid unexpected layout changes.

### Keymaps

Default keymaps (all in normal mode):

| Action | Default |
|--------|---------|
| Toggle preview | `<leader>cip` |
| Refresh preview | `<leader>cir` |
| Adjust split position | `<leader>cia` |
| Reset split to ratio | `<leader>civ` |

### Important note on `render_height_percent`

When the quickfix window (or other horizontal splits) is open, the bottom of the image may be clipped if `render_height_percent` is set to 100. This appears to be a quirk of how `image.nvim` calculates the available height with respect to Neovim's window layout and terminal graphics protocols (Sixel, Kitty, etc.). The default value of 95% avoids this issue in most environments.

If you still experience bottom clipping after opening quickfix, try lowering the value (e.g., 94, 93, 92) until the image fits perfectly within the preview window. Conversely, if you have extra vertical space and want to maximize the image size, you can increase the value, but be aware that values above 95% may cause clipping depending on your specific setup. The optimal value often lies between 90 and 97.

## Commands

| Command | Description |
|---------|-------------|
| `:CaptionImagePreviewToggle` | Toggle the preview window. |
| `:CaptionImagePreviewRefresh` | Refresh the current preview. |
| `:CaptionImagePreviewAdjust` | Adjust the split column to the longest line (excluding lines ending with a period). |
| `:CaptionImagePreviewReset` | Reset the split to the configured `split_ratio`. |
| `:CaptionImagePreviewDebug` | Write debug information to `caption-image-preview-debug.log` in the current working directory. |

## API

External plugins can call `require('caption-image-preview').redraw_preview()` to force a fresh render of the current image – useful after a floating window has been closed and may have left a visual artifact.

---

*This plugin was developed with the assistance of AI. Use at your own risk.*
