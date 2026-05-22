local session_dir = vim.fn.stdpath 'data' .. '/sessions/'
vim.fn.mkdir(session_dir, 'p')

local function session_file()
  local cwd = vim.fn.getcwd():gsub('/', '%%')
  return session_dir .. cwd .. '.vim'
end

vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    -- Close neo-tree before saving so it doesn't pollute the session
    pcall(vim.cmd, 'Neotree close')
    vim.cmd('mksession! ' .. vim.fn.fnameescape(session_file()))
  end,
})

vim.api.nvim_create_autocmd('VimEnter', {
  nested = true,
  callback = function()
    local arg = vim.fn.argv(0)
    if (vim.fn.argc() == 0 or arg == '.') and vim.fn.filereadable(session_file()) == 1 then
      vim.schedule(function()
        vim.cmd('silent! source ' .. vim.fn.fnameescape(session_file()))
      end)
    end
  end,
})

return {}
