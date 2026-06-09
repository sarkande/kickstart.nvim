return {
  '3rd/image.nvim',
  ft = { 'markdown' },
  opts = {
    backend = 'kitty',
    processor = 'magick_cli',
    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = false,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        floating_windows = false,
      },
    },
    max_width = 80,
    max_height = 20,
    max_width_window_percentage = 50,
    max_height_window_percentage = 40,
    kitty_method = 'normal',
  },
}
