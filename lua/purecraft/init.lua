local M = {}

function M.setup()
  local tools = require('purecraft.tools')
  local todoo = require('purecraft.todoo')
  local projects = require('purecraft.projects')

  local subcommands = {
    bash              = { fn = tools.bash,              desc = 'Bash dans un container' },
    logs              = { fn = tools.logs,              desc = 'Logs container' },
    shell             = { fn = tools.shell,             desc = 'Odoo Shell (ipython)' },
    upgrade           = { fn = tools.upgrade,           desc = 'Upgrade modules' },
    reupgrade         = { fn = tools.reupgrade,         desc = 'Re-upgrade derniers modules' },
    test              = { fn = tools.test,              desc = 'Lancer tests Odoo' },
    reset             = { fn = tools.reset,             desc = 'Reset container (down -v + up)' },
    reset_base_url    = { fn = tools.reset_base_url,    desc = 'Reset web.base.url à localhost' },
    change_password   = { fn = tools.change_password,   desc = 'Reset login/password à odoo/odoo' },
    delete_ir_asset   = { fn = tools.delete_ir_asset,   desc = 'DELETE FROM ir_asset' },
    load_filestore    = { fn = tools.load_filestore,    desc = 'Rsync filestore depuis SSH' },
    scaffold          = { fn = tools.scaffold,          desc = 'Créer un module Odoo' },
    restart           = { fn = tools.restart_container, desc = 'Restart container' },
    stop              = { fn = tools.stop_container,    desc = 'Stop container' },
    start             = { fn = tools.start_container,   desc = 'Start container' },
    todoo             = { fn = todoo.pick_and_run,      desc = 'Tests (Todoo picker)' },
    todoo_start       = { fn = todoo.start_server,      desc = 'Démarrer serveur Todoo' },
    todoo_stop        = { fn = todoo.stop_server,       desc = 'Arrêter serveur Todoo' },
    projects          = { fn = projects.toggle,         desc = 'Toggle vue projets/tâches' },
    connect           = { fn = projects.connect,        desc = 'Connexion Odoo' },
    refresh           = { fn = projects.refresh,        desc = 'Rafraîchir projets' },
    search            = { fn = projects.search_tasks,   desc = 'Rechercher une tâche' },
    timesheet         = { fn = function()
      local config = require('purecraft.config')
      local cfg = config.get()
      if not cfg.current_task.id then
        vim.notify('[purecraft] Aucune tâche sélectionnée', vim.log.levels.WARN)
        return
      end
      projects.log_timesheet({
        id = tonumber(cfg.current_task.id),
        name = cfg.current_task.name,
        project_id = { 0, cfg.current_task.project },
      })
    end, desc = 'Logger du temps sur la tâche courante' },
    settings          = { fn = function()
      local config = require('purecraft.config')
      local cfg = config.get()
      local lines = {
        'PureCraft Settings',
        string.rep('═', 40),
        '',
        'Odoo Connection:',
        '  host: ' .. cfg.odoo.host,
        '  port: ' .. cfg.odoo.port,
        '  db:   ' .. cfg.odoo.db,
        '  user: ' .. cfg.odoo.user,
        '  pass: ' .. string.rep('*', #cfg.odoo.pass),
        '',
        'Todoo:',
        '  host: ' .. cfg.todoo.host,
        '  port: ' .. cfg.todoo.port,
        '  db:   ' .. cfg.todoo.db_name,
        '',
        'Task: ' .. (cfg.current_task.id and ('#' .. cfg.current_task.id .. ' · ' .. (cfg.current_task.name or '')) or 'none'),
        'DB history: ' .. table.concat(cfg.db_history, ', '),
        'Last upgrade: ' .. table.concat(cfg.last_upgrade_modules, ', '),
        '',
        ':PureCraft connect  — changer la connexion Odoo',
      }
      vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
    end, desc = 'Afficher la configuration' },
  }

  local sorted_names = {}
  for name in pairs(subcommands) do
    table.insert(sorted_names, name)
  end
  table.sort(sorted_names)

  vim.api.nvim_create_user_command('PureCraft', function(opts)
    local arg = vim.trim(opts.args)
    if arg == '' then
      local pickers = require('telescope.pickers')
      local finders = require('telescope.finders')
      local conf = require('telescope.config').values
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')

      local items = {}
      for _, name in ipairs(sorted_names) do
        table.insert(items, { name = name, desc = subcommands[name].desc })
      end

      pickers.new({}, {
        prompt_title = 'PureCraft',
        finder = finders.new_table({
          results = items,
          entry_maker = function(item)
            local display = item.name .. '  —  ' .. item.desc
            return { value = item, display = display, ordinal = item.name .. ' ' .. item.desc }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            local entry = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if entry then
              subcommands[entry.value.name].fn()
            end
          end)
          return true
        end,
      }):find()
      return
    end
    local cmd = subcommands[arg]
    if cmd then
      cmd.fn()
    else
      vim.notify('[purecraft] Commande inconnue: ' .. arg, vim.log.levels.ERROR)
    end
  end, {
    nargs = '?',
    complete = function(lead)
      local matches = {}
      for _, name in ipairs(sorted_names) do
        if name:find(lead, 1, true) == 1 then
          table.insert(matches, name)
        end
      end
      return matches
    end,
  })
end

return M
