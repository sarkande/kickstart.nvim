local rpc = require('purecraft.rpc')
local config = require('purecraft.config')

local M = {}

local _projects = {}
local _tasks = {}
local _buf = nil
local _win = nil
local _tree_lines = {}
local ns = vim.api.nvim_create_namespace('purecraft_projects')

local function notify(msg, level)
  vim.notify('[purecraft:projects] ' .. msg, level or vim.log.levels.INFO)
end

local stage_colors = {
  { patterns = { 'fait', 'done', 'terminé', 'fusionner', 'validé', 'résolu', 'merge' }, hl = 'DiagnosticOk' },
  { patterns = { 'annulé', 'cancel', 'abandonné' }, hl = 'DiagnosticError' },
  { patterns = { "aujourd'hui", 'en cours', 'cette semaine' }, hl = 'DiagnosticWarn' },
  { patterns = { 'ce mois', 'en attente' }, hl = 'Special' },
  { patterns = { 'recetter', 'testing', 'analysis', 'design', 'development' }, hl = 'Function' },
  { patterns = { 'nouveau', 'backlog', 'open', 'inbox', 'a faire', 'todo' }, hl = 'DiagnosticInfo' },
  { patterns = { 'plus tard' }, hl = 'Comment' },
}

local function get_stage_hl(stage_name)
  if not stage_name then
    return 'Normal'
  end
  local lower = stage_name:lower()
  for _, group in ipairs(stage_colors) do
    for _, pat in ipairs(group.patterns) do
      if lower:find(pat, 1, true) then
        return group.hl
      end
    end
  end
  return 'Normal'
end

function M.connect()
  vim.ui.input({ prompt = 'Odoo Host: ', default = config.get().odoo.host }, function(host)
    if not host then return end
    vim.ui.input({ prompt = 'Port: ', default = tostring(config.get().odoo.port) }, function(port)
      if not port then return end
      vim.ui.input({ prompt = 'Base de données: ', default = config.get().odoo.db }, function(db)
        if not db then return end
        vim.ui.input({ prompt = 'Utilisateur: ', default = config.get().odoo.user }, function(user)
          if not user then return end
          vim.ui.input({ prompt = 'Mot de passe: ' }, function(pass)
            if not pass then return end
            config.update('odoo.host', host)
            config.update('odoo.port', tonumber(port) or 8235)
            config.update('odoo.db', db)
            config.update('odoo.user', user)
            config.update('odoo.pass', pass)
            rpc.logout()
            rpc.login(function(uid, err)
              if uid then
                notify('Connecté (uid=' .. uid .. ')')
                M.refresh()
              end
            end)
          end)
        end)
      end)
    end)
  end)
end

function M.refresh()
  rpc.ensure_login(function(uid, err)
    if err then return end
    M._load_projects(uid)
  end)
end

function M._load_projects(uid)
  local project_fields = { 'id', 'name' }
  local time_fields = { 'allocated_hours', 'all_hours_spend', 'all_hours_remain' }

  rpc.search_read('project.project', { { 'task_user_ids', 'in', uid } },
    vim.list_extend(vim.deepcopy(project_fields), time_fields),
    function(projects, err)
      if err then
        rpc.search_read('project.project', { { 'task_user_ids', 'in', uid } }, project_fields,
          function(p2, e2)
            if p2 then
              _projects = p2
              M._load_tasks()
            end
          end)
        return
      end
      _projects = projects or {}

      local cfg = config.get()
      local favorites = cfg.favorite_projects
      if favorites and #favorites > 0 then
        local existing_ids = {}
        for _, p in ipairs(_projects) do
          table.insert(existing_ids, p.id)
        end
        rpc.search_read('project.project',
          { { 'name', 'in', favorites }, { 'id', 'not in', existing_ids } },
          vim.list_extend(vim.deepcopy(project_fields), time_fields),
          function(extra)
            if extra then
              for _, p in ipairs(extra) do
                table.insert(_projects, p)
              end
            end
            M._load_tasks()
          end)
      else
        M._load_tasks()
      end
    end)
end

function M._load_tasks()
  if #_projects == 0 then
    M._render()
    return
  end

  local project_ids = {}
  for _, p in ipairs(_projects) do
    table.insert(project_ids, p.id)
  end

  rpc.search_read('project.task', { { 'project_id', 'in', project_ids } },
    { 'id', 'name', 'parent_id', 'project_id', 'write_date', 'stage_id',
      'effective_hours', 'allocated_hours', 'total_hours_spent', 'remaining_hours' },
    function(tasks, err)
      _tasks = tasks or {}
      table.sort(_tasks, function(a, b) return (a.write_date or '') > (b.write_date or '') end)
      M._load_today_hours()
    end)
end

function M._load_today_hours()
  local uid = rpc.get_uid()
  local today = os.date('%Y-%m-%d')
  rpc.search_read('account.analytic.line',
    { { 'user_id', '=', uid }, { 'date', '=', today } },
    { 'unit_amount' },
    function(lines)
      local total = 0
      if lines then
        for _, l in ipairs(lines) do
          total = total + (l.unit_amount or 0)
        end
      end
      M._render(total)
    end)
end

function M._render(today_hours)
  _tree_lines = {}

  if today_hours then
    local h = math.floor(today_hours)
    local m = math.floor((today_hours - h) * 60)
    table.insert(_tree_lines, {
      text = string.format('  Today: %dh%02dmin', h, m),
      hl = 'DiagnosticInfo',
      action = nil,
    })
    table.insert(_tree_lines, { text = '', hl = nil, action = nil })
  end

  local cfg = config.get()
  if cfg.current_task.id then
    table.insert(_tree_lines, {
      text = string.format('  #%s · %s', cfg.current_task.id, cfg.current_task.name or ''),
      hl = 'DiagnosticOk',
      action = nil,
    })
    table.insert(_tree_lines, { text = '', hl = nil, action = nil })
  end

  local cwd_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')

  local sorted_projects = vim.deepcopy(_projects)
  table.sort(sorted_projects, function(a, b)
    local a_match = a.name:lower():find(cwd_name:lower(), 1, true) and 1 or 0
    local b_match = b.name:lower():find(cwd_name:lower(), 1, true) and 1 or 0
    if a_match ~= b_match then return a_match > b_match end
    return a.name < b.name
  end)

  for _, project in ipairs(sorted_projects) do
    local star = project.name:lower():find(cwd_name:lower(), 1, true) and '★ ' or '  '
    local hours_info = ''
    if project.all_hours_spend then
      hours_info = string.format(' [%.1fh/%.1fh]', project.all_hours_spend or 0, project.allocated_hours or 0)
    end
    table.insert(_tree_lines, {
      text = star .. project.name .. hours_info,
      hl = 'Title',
      action = nil,
      project_id = project.id,
      collapsed = false,
    })

    local project_tasks = {}
    for _, t in ipairs(_tasks) do
      if t.project_id and t.project_id[1] == project.id and (not t.parent_id or t.parent_id == false) then
        table.insert(project_tasks, t)
      end
    end

    for _, task in ipairs(project_tasks) do
      local stage = task.stage_id and task.stage_id[2] or ''
      local stage_hl = get_stage_hl(stage)
      local hours = task.effective_hours and string.format(' %.1fh', task.effective_hours) or ''
      table.insert(_tree_lines, {
        text = '  ├─ ' .. task.name .. hours .. (stage ~= '' and (' [' .. stage .. ']') or ''),
        hl = stage_hl,
        task = task,
      })

      local subtasks = {}
      for _, st in ipairs(_tasks) do
        if st.parent_id and type(st.parent_id) == 'table' and st.parent_id[1] == task.id then
          table.insert(subtasks, st)
        end
      end
      for _, sub in ipairs(subtasks) do
        local sub_stage = sub.stage_id and sub.stage_id[2] or ''
        table.insert(_tree_lines, {
          text = '  │  └─ ' .. sub.name .. (sub_stage ~= '' and (' [' .. sub_stage .. ']') or ''),
          hl = get_stage_hl(sub_stage),
          task = sub,
        })
      end
    end

    table.insert(_tree_lines, { text = '', hl = nil, action = nil })
  end

  M._draw()
end

function M._draw()
  if not _buf or not vim.api.nvim_buf_is_valid(_buf) then
    _buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(_buf, 'purecraft_projects')
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = _buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = _buf })
    vim.api.nvim_set_option_value('modifiable', false, { buf = _buf })
    vim.api.nvim_set_option_value('filetype', 'purecraft_projects', { buf = _buf })
    M._set_keymaps()
  end

  vim.api.nvim_set_option_value('modifiable', true, { buf = _buf })
  local lines = {}
  for _, tl in ipairs(_tree_lines) do
    table.insert(lines, tl.text)
  end
  vim.api.nvim_buf_set_lines(_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = _buf })

  vim.api.nvim_buf_clear_namespace(_buf, ns, 0, -1)
  for i, tl in ipairs(_tree_lines) do
    if tl.hl then
      vim.api.nvim_buf_set_extmark(_buf, ns, i - 1, 0, { line_hl_group = tl.hl })
    end
  end

  if not _win or not vim.api.nvim_win_is_valid(_win) then
    vim.cmd('topleft vsplit')
    _win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(_win, _buf)
    vim.api.nvim_win_set_width(_win, 50)
    vim.api.nvim_set_option_value('number', false, { win = _win })
    vim.api.nvim_set_option_value('relativenumber', false, { win = _win })
    vim.api.nvim_set_option_value('signcolumn', 'no', { win = _win })
    vim.api.nvim_set_option_value('winfixwidth', true, { win = _win })
  end
end

function M._set_keymaps()
  local opts = { buffer = _buf, silent = true }

  vim.keymap.set('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local tl = _tree_lines[row]
    if tl and tl.task then
      M.select_task(tl.task)
    end
  end, opts)

  vim.keymap.set('n', 'o', function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local tl = _tree_lines[row]
    if tl and tl.task then
      M.open_task_in_browser(tl.task)
    end
  end, opts)

  vim.keymap.set('n', 't', function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local tl = _tree_lines[row]
    if tl and tl.task then
      M.log_timesheet(tl.task)
    end
  end, opts)

  vim.keymap.set('n', 'a', function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local tl = _tree_lines[row]
    if tl and tl.task then
      M.create_subtask(tl.task)
    elseif tl and tl.project_id then
      M.create_task(tl.project_id)
    end
  end, opts)

  vim.keymap.set('n', 'r', function()
    M.refresh()
  end, opts)

  vim.keymap.set('n', 'q', function()
    M.close()
  end, opts)

  vim.keymap.set('n', '?', function()
    notify('Enter=sélectionner | o=ouvrir navigateur | t=timesheet | a=créer | r=rafraîchir | q=fermer')
  end, opts)
end

function M.select_task(task)
  config.update('current_task.id', tostring(task.id))
  config.update('current_task.name', task.name)
  local project = task.project_id and task.project_id[2] or ''
  config.update('current_task.project', project)
  notify(string.format('Tâche sélectionnée: #%d · %s', task.id, task.name))
  M.refresh()
end

function M.open_task_in_browser(task)
  local cfg = config.get().odoo
  local scheme = cfg.port == 443 and 'https' or 'http'
  local url = string.format('%s://%s:%d/odoo/project/%d/tasks/%d',
    scheme, cfg.host, cfg.port, task.project_id[1], task.id)
  vim.ui.open(url)
end

function M.log_timesheet(task)
  vim.ui.input({ prompt = 'Temps (ex: 1h30, 45min, 2): ' }, function(input)
    if not input or input == '' then return end
    local hours = M._parse_time(input)
    if not hours then
      notify('Format invalide', vim.log.levels.ERROR)
      return
    end
    local today = os.date('%Y-%m-%d')
    rpc.call('account.analytic.line', 'add_timesheet_from_vscode',
      { task.id, hours, today }, nil,
      function(result, err)
        if err then
          notify('Erreur: ' .. err, vim.log.levels.ERROR)
          return
        end
        local h = math.floor(hours)
        local m = math.floor((hours - h) * 60)
        notify(string.format('%dh%02dmin loggé sur #%d · %s', h, m, task.id, task.name))
        M.refresh()
      end)
  end)
end

function M._parse_time(input)
  local h, m = input:match('^(%d+)h(%d+)$')
  if h then return tonumber(h) + tonumber(m) / 60 end
  h = input:match('^(%d+)h$')
  if h then return tonumber(h) end
  m = input:match('^(%d+)min$') or input:match('^(%d+)m$')
  if m then return tonumber(m) / 60 end
  local n = tonumber(input)
  if n then return n end
  return nil
end

function M.create_task(project_id)
  vim.ui.input({ prompt = 'Nom de la tâche: ' }, function(name)
    if not name or name == '' then return end
    local uid = rpc.get_uid()
    rpc.create('project.task', {
      name = name,
      project_id = project_id,
      user_ids = { uid },
    }, function(result, err)
      if err then
        notify('Erreur: ' .. err, vim.log.levels.ERROR)
        return
      end
      notify('Tâche créée: ' .. name)
      M.refresh()
    end)
  end)
end

function M.create_subtask(parent_task)
  vim.ui.input({ prompt = 'Nom de la sous-tâche: ' }, function(name)
    if not name or name == '' then return end
    local uid = rpc.get_uid()
    rpc.create('project.task', {
      name = name,
      project_id = parent_task.project_id[1],
      parent_id = parent_task.id,
      user_ids = { uid },
    }, function(result, err)
      if err then
        notify('Erreur: ' .. err, vim.log.levels.ERROR)
        return
      end
      notify('Sous-tâche créée: ' .. name)
      M.refresh()
    end)
  end)
end

function M.search_tasks()
  vim.ui.input({ prompt = 'Rechercher une tâche: ' }, function(query)
    if not query or query == '' then return end
    rpc.search_read('project.task',
      { { 'name', 'ilike', query } },
      { 'id', 'name', 'project_id', 'stage_id' },
      function(tasks, err)
        if err or not tasks or #tasks == 0 then
          notify('Aucune tâche trouvée')
          return
        end

        local pickers = require('telescope.pickers')
        local finders = require('telescope.finders')
        local conf = require('telescope.config').values
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')

        pickers.new({}, {
          prompt_title = 'Tâches Odoo',
          finder = finders.new_table({
            results = tasks,
            entry_maker = function(task)
              local project = task.project_id and task.project_id[2] or ''
              local display = string.format('#%d · %s (%s)', task.id, task.name, project)
              return { value = task, display = display, ordinal = display }
            end,
          }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              local entry = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if entry then
                M.select_task(entry.value)
              end
            end)
            return true
          end,
        }):find()
      end)
  end)
end

function M.toggle()
  if _win and vim.api.nvim_win_is_valid(_win) then
    M.close()
  else
    M.refresh()
  end
end

function M.close()
  if _win and vim.api.nvim_win_is_valid(_win) then
    vim.api.nvim_win_close(_win, true)
    _win = nil
  end
end

return M
