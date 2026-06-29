" show_caption_image - Preview images for caption files

if exists('g:loaded_caption_image_preview')
    finish
endif
let g:loaded_caption_image_preview = 1

lua require('caption-image-preview')
