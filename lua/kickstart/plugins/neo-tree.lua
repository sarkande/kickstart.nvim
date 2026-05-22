return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons',
    'MunifTanjim/nui.nvim',
  },
  cmd = 'Neotree',
  keys = {
    { '\\', ':Neotree reveal<CR>', desc = 'NeoTree reveal', silent = true },
    { '<leader>e', ':Neotree reveal<CR>', desc = 'File [E]xplorer', silent = true },
  },
  opts = {
    enable_diagnostics = true,
    use_popups_for_input = false,
    filesystem = {
      filtered_items = {
        hide_dotfiles = false,
        hide_by_name = { '__pycache__', '.git' },
      },
      follow_current_file = { enabled = true },
      use_libuv_file_watcher = true,
      window = {
        position = 'right',
        width = 45,
        mappings = {
          ['\\'] = 'close_window',
          ['<leader>e'] = 'close_window',
          ['/'] = 'fuzzy_finder',
          ['f'] = 'filter_on_submit',
          ['v'] = 'open_vsplit',
          ['s'] = 'open_split',
        },
      },
    },
  },
}
