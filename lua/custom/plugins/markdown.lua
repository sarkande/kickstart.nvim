return {
  'MeanderingProgrammer/render-markdown.nvim',
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
  ft = { 'markdown' },
  opts = {
    render_modes = { 'n', 'c' },
    anti_conceal = { enabled = true },
    heading = {
      sign = false,
      icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
    },
    code = {
      sign = false,
      width = 'block',
      right_pad = 1,
    },
    dash = { width = 60 },
    bullet = { icons = { '●', '○', '◆', '◇' } },
    checkbox = {
      unchecked = { icon = '󰄱 ' },
      checked = { icon = '󰱒 ' },
    },
    quote = { repeat_linebreak = true },
    pipe_table = { preset = 'round' },
  },
}
