return {
  'stevearc/oil.nvim',
  lazy = false, -- On charge immédiatement (ne pas lazy-load pour qu'il remplace netrw)
  dependencies = {
    { 'nvim-mini/mini.icons', opts = {} }, -- icônes modernes
  },
  config = function()
    require('oil').setup {
      default_file_explorer = true,
      columns = { 'icon' },
      buf_options = { buflisted = false, bufhidden = 'hide' },
      win_options = {
        wrap = false,
        signcolumn = 'no',
        cursorcolumn = false,
        foldcolumn = '0',
        spell = false,
        list = false,
        conceallevel = 3,
        concealcursor = 'nvic',
      },
      delete_to_trash = false,
      skip_confirm_for_simple_edits = false,
      prompt_save_on_select_new_entry = true,
      cleanup_delay_ms = 2000,
      lsp_file_methods = {
        enabled = true,
        timeout_ms = 1000,
        autosave_changes = false,
      },
      constrain_cursor = 'editable',
      watch_for_changes = false,
      keymaps = {
        ['g?'] = { 'actions.show_help', mode = 'n' },
        ['<CR>'] = 'actions.select',
        ['<C-s>'] = { 'actions.select', opts = { vertical = true } },
        ['<C-h>'] = { 'actions.select', opts = { horizontal = true } },
        ['<C-t>'] = { 'actions.select', opts = { tab = true } },
        ['<C-p>'] = 'actions.preview',
        ['<C-c>'] = { 'actions.close', mode = 'n' },
        ['<C-l>'] = 'actions.refresh',
        ['-'] = { 'actions.parent', mode = 'n' },
        ['_'] = { 'actions.open_cwd', mode = 'n' },
        ['`'] = { 'actions.cd', mode = 'n' },
        ['~'] = { 'actions.cd', opts = { scope = 'tab' }, mode = 'n' },
        ['gs'] = { 'actions.change_sort', mode = 'n' },
        ['gx'] = 'actions.open_external',
        ['g.'] = { 'actions.toggle_hidden', mode = 'n' },
        ['g\\'] = { 'actions.toggle_trash', mode = 'n' },
      },
      use_default_keymaps = true,
      view_options = {
        show_hidden = false,
        is_hidden_file = function(name, bufnr)
          return name:match '^%.' ~= nil
        end,
        is_always_hidden = function(name, bufnr)
          return false
        end,
        natural_order = 'fast',
        case_insensitive = false,
        sort = {
          { 'type', 'asc' },
          { 'name', 'asc' },
        },
        highlight_filename = function(entry, is_hidden, is_link_target, is_link_orphan)
          return nil
        end,
      },
      extra_scp_args = {},
      git = {
        add = function()
          return false
        end,
        mv = function()
          return false
        end,
        rm = function()
          return false
        end,
      },
      float = {
        padding = 2,
        max_width = 0,
        max_height = 0,
        border = 'rounded',
        win_options = { winblend = 0 },
        preview_split = 'auto',
        override = function(conf)
          return conf
        end,
      },
      preview_win = {
        update_on_cursor_moved = true,
        preview_method = 'scratch',
        disable_preview = function(filepath)
          -- skip binaries
          local binary_exts = {
            'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'ico', 'bmp',
            'pdf', 'zip', 'tar', 'gz', 'rar', '7z',
            'exe', 'bin', 'so', 'dylib', 'o', 'a',
            'pyc', 'pyo', 'class',
            'mp3', 'mp4', 'mov', 'avi', 'mkv', 'wav', 'flac',
            'ttf', 'otf', 'woff', 'woff2',
          }
          local ext = filepath:match '%.([^.]+)$'
          if ext and vim.tbl_contains(binary_exts, ext:lower()) then
            return true
          end
          -- skip files > 500KB
          local ok, stat = pcall(vim.loop.fs_stat, filepath)
          if ok and stat and stat.size > 500 * 1024 then
            return true
          end
          return false
        end,
        win_options = {},
      },
      confirmation = {
        max_width = 0.9,
        min_width = { 40, 0.4 },
        max_height = 0.9,
        min_height = { 5, 0.1 },
        border = 'rounded',
        win_options = { winblend = 0 },
      },
      progress = {
        max_width = 0.9,
        min_width = { 40, 0.4 },
        max_height = { 10, 0.9 },
        min_height = { 5, 0.1 },
        border = 'rounded',
        minimized_border = 'none',
        win_options = { winblend = 0 },
      },
      ssh = { border = 'rounded' },
      keymaps_help = { border = 'rounded' },
    }

    -- At startup with directory arg or no arg, close Oil so alpha dashboard can take over
    if vim.fn.argc() == 0 or (vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1) then
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'oil',
        once = true,
        callback = function(ev)
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(ev.buf) then
              vim.cmd 'enew'
              pcall(vim.api.nvim_buf_delete, ev.buf, { force = true })
            end
          end)
        end,
      })
    end

    -- Auto-ouvrir la preview quand on entre dans Oil
    -- Mapping global : "-" pour ouvrir Oil partout
    vim.keymap.set('n', '-', '<CMD>Oil<CR>', { desc = 'Ouvrir Oil (explorateur)' })
  end,
}
