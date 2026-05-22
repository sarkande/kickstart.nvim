local docker = require('purecraft.docker')
local config = require('purecraft.config')
local version = require('purecraft.version')

local M = {}

local function notify(msg, level)
  vim.notify('[purecraft] ' .. msg, level or vim.log.levels.INFO)
end

local function require_compose()
  local compose = docker.find_compose_file()
  if not compose then
    notify('docker-compose.yml introuvable', vim.log.levels.ERROR)
    return nil
  end
  return compose
end

local function pick_container(compose, callback)
  local containers = docker.get_containers_sync(compose)
  if #containers == 0 then
    notify('Aucun container trouvé', vim.log.levels.WARN)
    return
  end
  vim.ui.select(containers, {
    prompt = 'Container:',
    format_item = function(c)
      local icon = c.state == 'running' and '●' or '○'
      return icon .. ' ' .. c.name .. ' (' .. c.service .. ')'
    end,
  }, function(choice)
    if choice then
      callback(choice)
    end
  end)
end

local function pick_database(callback)
  local cfg = config.get()
  local items = {}
  for _, db in ipairs(cfg.db_history) do
    table.insert(items, db)
  end
  table.insert(items, '+ Nouvelle base de données')

  vim.ui.select(items, { prompt = 'Base de données:' }, function(choice)
    if not choice then
      return
    end
    if choice == '+ Nouvelle base de données' then
      vim.ui.input({ prompt = 'Nom de la base de données: ', default = 'odoo' }, function(name)
        if name and name ~= '' then
          config.add_db_history(name)
          callback(name)
        end
      end)
    else
      config.add_db_history(choice)
      callback(choice)
    end
  end)
end

local function get_workspace_modules()
  local cwd = vim.fn.getcwd()
  local modules = {}
  local manifests = vim.fn.glob(cwd .. '/*/__manifest__.py', false, true)
  for _, path in ipairs(manifests) do
    local mod = vim.fn.fnamemodify(path, ':h:t')
    table.insert(modules, mod)
  end
  table.sort(modules)
  return modules
end

local function pick_modules(callback)
  local modules = get_workspace_modules()
  if #modules == 0 then
    notify('Aucun module Odoo trouvé dans le workspace', vim.log.levels.WARN)
    return
  end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  pickers.new({}, {
    prompt_title = 'Modules Odoo (Tab pour sélectionner, Enter pour valider)',
    finder = finders.new_table({ results = modules }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local selections = picker:get_multi_selection()
        actions.close(prompt_bufnr)
        local selected = {}
        if #selections > 0 then
          for _, s in ipairs(selections) do
            table.insert(selected, s[1])
          end
        else
          local entry = action_state.get_selected_entry()
          if entry then
            table.insert(selected, entry[1])
          end
        end
        if #selected > 0 then
          callback(selected)
        end
      end)
      return true
    end,
  }):find()
end

local function get_port_flag()
  if version.is_legacy() then
    return '--xmlrpc-port=8070'
  end
  return '--http-port=8070'
end

-- ━━━ BASH ━━━

function M.bash()
  local compose = require_compose()
  if not compose then return end
  pick_container(compose, function(c)
    vim.ui.select({ 'Sans Sudo', 'Avec Sudo' }, { prompt = 'Mode:' }, function(mode)
      if not mode then return end
      local cmd = mode == 'Avec Sudo'
        and { 'docker', 'exec', '-it', '-u', '0', c.name, 'bash' }
        or { 'docker', 'exec', '-it', c.name, 'bash' }
      docker.open_terminal(cmd, 'bash-' .. c.name)
    end)
  end)
end

-- ━━━ LOGS ━━━

function M.logs()
  local compose = require_compose()
  if not compose then return end
  pick_container(compose, function(c)
    docker.open_terminal({ 'docker', 'logs', '-f', c.name }, 'logs-' .. c.name)
  end)
end

-- ━━━ ODOO SHELL ━━━

function M.shell()
  local compose = require_compose()
  if not compose then return end
  pick_container(compose, function(c)
    pick_database(function(db)
      docker.open_terminal(
        { 'docker', 'exec', '-it', c.name, 'odoo', 'shell', '--shell-interface', 'ipython', '-d', db, '--db_host', 'db', '--db_password', 'odoo' },
        'shell-' .. c.name
      )
    end)
  end)
end

-- ━━━ UPGRADE ━━━

function M.upgrade()
  local compose = require_compose()
  if not compose then return end

  pick_modules(function(modules)
    vim.ui.input({ prompt = 'Modules supplémentaires (comma-separated): ' }, function(extra)
      if extra and extra ~= '' then
        for mod in extra:gmatch('[^,%s]+') do
          table.insert(modules, mod)
        end
      end
      pick_database(function(db)
        local containers = docker.get_containers_sync(compose)
        local web = nil
        for _, c in ipairs(containers) do
          if c.state == 'running' and (c.service == 'web' or c.service == 'odoo') then
            web = c
            break
          end
        end
        if not web then
          pick_container(compose, function(c)
            M._run_upgrade(c, modules, db)
          end)
        else
          M._run_upgrade(web, modules, db)
        end
      end)
    end)
  end)
end

function M._run_upgrade(container, modules, db)
  local mods = table.concat(modules, ',')
  config.update('last_upgrade_modules', modules)
  local cmd = {
    'docker', 'exec', '-it', container.name,
    'odoo', '-d', db, '--db_host', 'db', '--db_password', 'odoo',
    '-u', mods, '--stop-after-init', get_port_flag(),
  }
  docker.open_terminal(cmd, 'upgrade-' .. mods)
end

-- ━━━ RE-UPGRADE ━━━

function M.reupgrade()
  local cfg = config.get()
  local modules = cfg.last_upgrade_modules
  if not modules or #modules == 0 then
    notify('Pas de modules précédents à re-upgrade', vim.log.levels.WARN)
    return
  end

  local compose = require_compose()
  if not compose then return end

  pick_database(function(db)
    local containers = docker.get_containers_sync(compose)
    local web = nil
    for _, c in ipairs(containers) do
      if c.state == 'running' and (c.service == 'web' or c.service == 'odoo') then
        web = c
        break
      end
    end
    if not web then
      pick_container(compose, function(c)
        M._run_upgrade(c, modules, db)
      end)
    else
      M._run_upgrade(web, modules, db)
    end
  end)
end

-- ━━━ TEST ━━━

function M.test()
  local compose = require_compose()
  if not compose then return end

  pick_modules(function(modules)
    pick_database(function(db)
      local containers = docker.get_containers_sync(compose)
      local web = nil
      for _, c in ipairs(containers) do
        if c.state == 'running' and (c.service == 'web' or c.service == 'odoo') then
          web = c
          break
        end
      end
      if not web then
        pick_container(compose, function(c)
          M._run_test(c, modules, db)
        end)
      else
        M._run_test(web, modules, db)
      end
    end)
  end)
end

function M._run_test(container, modules, db)
  local mods = table.concat(modules, ',')
  local cmd = {
    'docker', 'exec', '-it', container.name,
    'odoo', '-d', db, '--db_host', 'db', '--db_password', 'odoo',
    '-i', mods, '--test-enable', '--log-level=test', '--stop-after-init', get_port_flag(),
  }
  docker.open_terminal(cmd, 'test-' .. mods)
end

-- ━━━ RESET CONTAINER ━━━

function M.reset()
  local compose = require_compose()
  if not compose then return end

  vim.ui.select({ 'Oui', 'Non' }, {
    prompt = '⚠ Réinitialiser le container ? (down -v + up --build)',
  }, function(choice)
    if choice ~= 'Oui' then return end
    docker.open_terminal(
      { 'sh', '-c', 'docker compose -f ' .. compose .. ' down -v && docker compose -f ' .. compose .. ' up --build -d' },
      'reset'
    )
  end)
end

-- ━━━ RESET BASE URL ━━━

function M.reset_base_url()
  local compose = require_compose()
  if not compose then return end

  pick_database(function(db)
    local db_container = nil
    local containers = docker.get_containers_sync(compose)
    for _, c in ipairs(containers) do
      if c.service == 'db' and c.state == 'running' then
        db_container = c
        break
      end
    end
    if not db_container then
      notify('Container DB introuvable ou arrêté', vim.log.levels.ERROR)
      return
    end
    vim.system(
      { 'docker', 'exec', db_container.name, 'psql', '-U', 'odoo', '-d', db, '-c',
        "UPDATE ir_config_parameter SET value = 'http://localhost:8069' WHERE key = 'web.base.url';" },
      { text = true },
      function(obj)
        vim.schedule(function()
          if obj.code == 0 then
            notify('Base URL réinitialisée à http://localhost:8069')
          else
            notify('Erreur: ' .. (obj.stderr or ''), vim.log.levels.ERROR)
          end
        end)
      end
    )
  end)
end

-- ━━━ CHANGE PASSWORD ━━━

function M.change_password()
  local compose = require_compose()
  if not compose then return end

  pick_database(function(db)
    local db_container = nil
    local containers = docker.get_containers_sync(compose)
    for _, c in ipairs(containers) do
      if c.service == 'db' and c.state == 'running' then
        db_container = c
        break
      end
    end
    if not db_container then
      notify('Container DB introuvable ou arrêté', vim.log.levels.ERROR)
      return
    end
    vim.system(
      { 'docker', 'exec', db_container.name, 'psql', '-U', 'odoo', '-d', db, '-c',
        "UPDATE res_users SET login = 'odoo', password = 'odoo' WHERE id = 2;" },
      { text = true },
      function(obj)
        vim.schedule(function()
          if obj.code == 0 then
            notify('Password changé → login: odoo / password: odoo')
          else
            notify('Erreur: ' .. (obj.stderr or ''), vim.log.levels.ERROR)
          end
        end)
      end
    )
  end)
end

-- ━━━ DELETE IR.ASSET ━━━

function M.delete_ir_asset()
  local compose = require_compose()
  if not compose then return end

  pick_database(function(db)
    local db_container = nil
    local containers = docker.get_containers_sync(compose)
    for _, c in ipairs(containers) do
      if c.service == 'db' and c.state == 'running' then
        db_container = c
        break
      end
    end
    if not db_container then
      notify('Container DB introuvable ou arrêté', vim.log.levels.ERROR)
      return
    end
    vim.system(
      { 'docker', 'exec', db_container.name, 'psql', '-U', 'odoo', '-d', db, '-c',
        'DELETE FROM ir_asset;' },
      { text = true },
      function(obj)
        vim.schedule(function()
          if obj.code == 0 then
            notify('ir_asset supprimés')
          else
            notify('Erreur: ' .. (obj.stderr or ''), vim.log.levels.ERROR)
          end
        end)
      end
    )
  end)
end

-- ━━━ LOAD FILESTORE ━━━

function M.load_filestore()
  local compose = require_compose()
  if not compose then return end
  local compose_dir = docker.get_compose_dir(compose)

  vim.ui.input({ prompt = 'SSH (user@host): ' }, function(ssh)
    if not ssh or ssh == '' then return end
    vim.ui.input({ prompt = 'Base de données distante: ' }, function(remote_db)
      if not remote_db or remote_db == '' then return end
      pick_database(function(local_db)
        local cmd = string.format(
          'rsync -avz --ignore-times --progress %s:/home/odoo/data/filestore/%s/ %s/data/.local/share/Odoo/filestore/%s/',
          ssh, remote_db, compose_dir, local_db
        )
        docker.open_terminal({ 'sh', '-c', cmd }, 'filestore-sync')
      end)
    end)
  end)
end

-- ━━━ SCAFFOLD ━━━

function M.scaffold()
  vim.ui.input({ prompt = 'Nom du module (snake_case): ' }, function(name)
    if not name or name == '' then return end
    if not name:match('^[a-z][a-z0-9_]*$') then
      notify('Le nom doit être en snake_case', vim.log.levels.ERROR)
      return
    end

    vim.ui.input({ prompt = 'Description: ', default = name }, function(description)
      if not description then return end

      vim.ui.input({ prompt = 'Auteur: ', default = 'Pure Illusion' }, function(author)
        if not author then return end

        local folder_opts = { 'models', 'views', 'security', 'controllers', 'wizards', 'data', 'reports', 'static', 'i18n', 'tests' }

        local pickers = require('telescope.pickers')
        local finders = require('telescope.finders')
        local conf = require('telescope.config').values
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')

        pickers.new({}, {
          prompt_title = 'Dossiers (Tab pour sélectionner)',
          finder = finders.new_table({ results = folder_opts }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              local picker = action_state.get_current_picker(prompt_bufnr)
              local selections = picker:get_multi_selection()
              actions.close(prompt_bufnr)
              local folders = {}
              if #selections > 0 then
                for _, s in ipairs(selections) do
                  table.insert(folders, s[1])
                end
              else
                folders = { 'models', 'views', 'security' }
              end
              M._create_module(name, description, author, folders)
            end)
            return true
          end,
        }):find()
      end)
    end)
  end)
end

function M._create_module(name, description, author, folders)
  local cwd = vim.fn.getcwd()
  local base = cwd .. '/' .. name

  if vim.fn.isdirectory(base) == 1 then
    notify('Le dossier ' .. name .. ' existe déjà', vim.log.levels.ERROR)
    return
  end

  vim.fn.mkdir(base, 'p')

  local v = version.detect()
  local ver_prefix = v and (v.major .. '.0.') or ''

  local data_files = {}
  local has = {}
  for _, f in ipairs(folders) do
    has[f] = true
    vim.fn.mkdir(base .. '/' .. f, 'p')
  end

  if has.security then
    local f = io.open(base .. '/security/ir.model.access.csv', 'w')
    if f then
      f:write('id,name,model_id/id,group_id/id,perm_read,perm_write,perm_create,perm_unlink\n')
      f:close()
    end
    table.insert(data_files, '"security/ir.model.access.csv"')
  end

  if has.views then
    local f = io.open(base .. '/views/.gitkeep', 'w')
    if f then f:close() end
  end

  if has.data then
    local f = io.open(base .. '/data/.gitkeep', 'w')
    if f then f:close() end
  end

  if has.models then
    local f = io.open(base .. '/models/__init__.py', 'w')
    if f then f:close() end
    f = io.open(base .. '/__init__.py', 'w')
    if f then
      f:write('from . import models\n')
      if has.controllers then f:write('from . import controllers\n') end
      if has.wizards then f:write('from . import wizards\n') end
      if has.reports then f:write('from . import reports\n') end
      f:close()
    end
  else
    local f = io.open(base .. '/__init__.py', 'w')
    if f then f:close() end
  end

  if has.controllers then
    local f = io.open(base .. '/controllers/__init__.py', 'w')
    if f then f:close() end
  end

  if has.wizards then
    local f = io.open(base .. '/wizards/__init__.py', 'w')
    if f then f:close() end
  end

  if has.reports then
    local f = io.open(base .. '/reports/__init__.py', 'w')
    if f then f:close() end
  end

  if has.static then
    vim.fn.mkdir(base .. '/static/description', 'p')
    vim.fn.mkdir(base .. '/static/src/scss', 'p')
    vim.fn.mkdir(base .. '/static/src/js', 'p')
    vim.fn.mkdir(base .. '/static/src/xml', 'p')
  end

  if has.tests then
    local f = io.open(base .. '/tests/__init__.py', 'w')
    if f then f:close() end
  end

  if has.i18n then
    vim.fn.mkdir(base .. '/i18n', 'p')
  end

  local data_str = ''
  if #data_files > 0 then
    data_str = '\n        ' .. table.concat(data_files, ',\n        ') .. ',\n    '
  end

  local manifest = string.format([[{
    "name": "%s",
    "summary": "%s",
    "version": "%s1.0.0",
    "category": "Uncategorized",
    "author": "%s",
    "license": "LGPL-3",
    "depends": ["base"],
    "data": [%s],
    "assets": {},
    "installable": True,
    "application": False,
    "auto_install": False,
}
]], name, description, ver_prefix, author, data_str)

  local f = io.open(base .. '/__manifest__.py', 'w')
  if f then
    f:write(manifest)
    f:close()
  end

  notify('Module ' .. name .. ' créé')
  vim.cmd('edit ' .. base .. '/__manifest__.py')
end

-- ━━━ CONTAINER ACTIONS ━━━

function M.restart_container()
  local compose = require_compose()
  if not compose then return end
  pick_container(compose, function(c)
    notify('Redémarrage de ' .. c.name .. '...')
    vim.system({ 'docker', 'restart', c.name }, {}, function(obj)
      vim.schedule(function()
        if obj.code == 0 then
          notify(c.name .. ' redémarré')
        else
          notify('Erreur au redémarrage', vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

function M.stop_container()
  local compose = require_compose()
  if not compose then return end
  pick_container(compose, function(c)
    vim.system({ 'docker', 'stop', c.name }, {}, function(obj)
      vim.schedule(function()
        if obj.code == 0 then
          notify(c.name .. ' arrêté')
        else
          notify('Erreur', vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

function M.start_container()
  local compose = require_compose()
  if not compose then return end
  pick_container(compose, function(c)
    vim.system(
      { 'docker', 'compose', '-f', compose, 'up', '-d', c.service },
      {},
      function(obj)
        vim.schedule(function()
          if obj.code == 0 then
            notify(c.service .. ' démarré')
          else
            notify('Erreur', vim.log.levels.ERROR)
          end
        end)
      end
    )
  end)
end

return M
