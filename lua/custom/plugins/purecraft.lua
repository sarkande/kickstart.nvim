return {
  dir = vim.fn.stdpath('config') .. '/lua/purecraft',
  name = 'purecraft',
  config = function()
    require('purecraft').setup()
  end,
}
