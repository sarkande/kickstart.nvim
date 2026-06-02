return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gs', '<cmd>DiffviewOpen<CR>', desc = '[G]it [S]tatus (diff)' },
    { '<leader>gd', '<cmd>DiffviewOpen<CR>', desc = '[G]it [D]iff working tree' },
    { '<leader>gf', '<cmd>DiffviewFileHistory %<CR>', desc = '[G]it [F]ile history' },
  },
  config = function()
    local function git_commit(args, label)
      vim.system(args, { text = true }, function(obj)
        vim.schedule(function()
          if obj.code ~= 0 then
            vim.notify('Commit failed: ' .. (obj.stderr or ''), vim.log.levels.ERROR)
            return
          end
          vim.notify(label, vim.log.levels.INFO)
          vim.cmd 'DiffviewClose'
          vim.system({ 'git', 'status', '--porcelain' }, { text = true }, function(st)
            vim.schedule(function()
              if st.stdout and st.stdout ~= '' then
                vim.cmd 'DiffviewOpen'
              end
            end)
          end)
        end)
      end)
    end

    require('diffview').setup {
      view = {
        merge_tool = { layout = 'diff3_mixed' },
      },
      keymaps = {
        file_panel = {
          { 'n', 'cc', function()
            vim.ui.input({ prompt = 'Commit: ' }, function(msg)
              if msg and msg ~= '' then
                git_commit({ 'git', 'commit', '-m', msg }, 'Committed: ' .. msg)
              end
            end)
          end, { desc = 'Commit staged' } },

          { 'n', 'ca', function()
            vim.ui.input({ prompt = 'Amend (empty = keep message): ' }, function(msg)
              if msg == nil then
                return
              end
              if msg == '' then
                git_commit({ 'git', 'commit', '--amend', '--no-edit' }, 'Amended (same message)')
              else
                git_commit({ 'git', 'commit', '--amend', '-m', msg }, 'Amended: ' .. msg)
              end
            end)
          end, { desc = 'Amend commit' } },

          { 'n', 'cp', function()
            vim.ui.input({ prompt = 'Commit & push: ' }, function(msg)
              if msg and msg ~= '' then
                vim.system({ 'git', 'commit', '-m', msg }, { text = true }, function(obj)
                  vim.schedule(function()
                    if obj.code ~= 0 then
                      vim.notify('Commit failed: ' .. (obj.stderr or ''), vim.log.levels.ERROR)
                      return
                    end
                    vim.notify('Committed, pushing...', vim.log.levels.INFO)
                    vim.system({ 'git', 'push' }, { text = true }, function(push)
                      vim.schedule(function()
                        if push.code == 0 then
                          vim.notify('Pushed!', vim.log.levels.INFO)
                        else
                          vim.notify('Push failed: ' .. (push.stderr or ''), vim.log.levels.ERROR)
                        end
                        vim.cmd 'DiffviewClose'
                      end)
                    end)
                  end)
                end)
              end
            end)
          end, { desc = 'Commit & push' } },

          { 'n', 'q', '<cmd>DiffviewClose<CR>', { desc = 'Close' } },
        },
        view = {
          { 'n', 'q', '<cmd>DiffviewClose<CR>', { desc = 'Close' } },
        },
      },
    }
  end,
}
