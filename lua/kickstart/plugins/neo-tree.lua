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
    { '\\', '<cmd>lua NeoTreeToggle()<cr>', desc = 'NeoTree toggle', silent = true },
    { '<leader>e', '<cmd>lua NeoTreeToggle()<cr>', desc = 'File [E]xplorer (toggle)', silent = true },
  },
  opts = {
    enable_diagnostics = true,
    use_popups_for_input = false,
    filesystem = {
      -- Ouvrir un dossier (`nvim .`, ouverture d'un répertoire) → neo-tree
      -- prend la main à la place de netrw (l'explorateur par défaut de vim).
      hijack_netrw_behavior = 'open_current',
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
          -- neo-tree mappe <space> sur toggle_node par défaut ; comme <space>
          -- est notre leader, ça se déclenchait quand la séquence leader expirait
          -- (timeoutlen) → ouverture intempestive du nœud. On le neutralise pour
          -- que l'espace ne soit QUE la leader. (Enter / o ouvrent toujours.)
          ['<space>'] = 'none',
          ['\\'] = 'close_window',
          ['<leader>e'] = 'close_window',
          ['/'] = 'fuzzy_finder',
          ['f'] = 'filter_on_submit',
          ['v'] = 'open_vsplit',
          ['s'] = 'open_split',
          ['P'] = { 'toggle_preview', config = { use_float = false, use_image_nvim = true } },
        },
      },
    },
    preview = {
      use_float = false,
      use_image_nvim = true,
    },
  },
  config = function(_, opts)
    require('neo-tree').setup(opts)

    -- Auto-preview on cursor move in neo-tree
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'neo-tree',
      callback = function(ev)
        -- Ouvrir la preview automatiquement
        vim.defer_fn(function()
          vim.cmd 'Neotree action=focus'
          local ok = pcall(function()
            require('neo-tree.command').execute { action = 'show', source = 'filesystem' }
          end)
        end, 50)

        -- Mettre à jour la preview au mouvement du curseur
        vim.api.nvim_create_autocmd('CursorMoved', {
          buffer = ev.buf,
          callback = function()
            local state = require('neo-tree.sources.manager').get_state 'filesystem'
            if state and state.preview_mode then
              require('neo-tree.sources.common.preview').hide()
              require('neo-tree.sources.common.preview').show(state)
            end
          end,
        })
      end,
    })
  end,
}
