return {
  'mbbill/undotree',
  keys = {
    { '<leader>u', '<cmd>UndotreeToggle<CR>', desc = '[U]ndo history' },
  },
  config = function()
    vim.g.undotree_SetFocusWhenToggle = 1
    vim.g.undotree_WindowLayout = 3
    vim.g.undotree_DiffpanelHeight = 15
  end,
}
