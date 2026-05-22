return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gf', '<cmd>DiffviewFileHistory %<CR>', desc = '[G]it [F]ile history (diff)' },
    { '<leader>gd', '<cmd>DiffviewOpen<CR>', desc = '[G]it [D]iff working tree' },
  },
  opts = {
    view = {
      merge_tool = { layout = 'diff3_mixed' },
    },
  },
}
