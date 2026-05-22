local docker = require('purecraft.docker')
local config = require('purecraft.config')

local M = {}

local function notify(msg, level)
  vim.notify('[purecraft:todoo] ' .. msg, level or vim.log.levels.INFO)
end

local function get_todoo_url()
  local cfg = config.get().todoo
  return string.format('http://%s:%d', cfg.host, cfg.port)
end

local function http_get(path, callback)
  local url = get_todoo_url() .. path
  vim.system({ 'curl', '-s', '-f', url }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        callback(nil, 'request failed')
        return
      end
      local ok, data = pcall(vim.json.decode, obj.stdout)
      if ok then
        callback(data)
      else
        callback(nil, 'json parse error')
      end
    end)
  end)
end

function M.is_server_running(callback)
  http_get('/api/current-container', function(data, err)
    callback(data ~= nil)
  end)
end

function M.start_server()
  local cfg = config.get().todoo
  local cmd = { 'todoo', '--port', tostring(cfg.port), '--host', cfg.host }
  local job_id = vim.fn.jobstart(cmd, {
    detach = true,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then
          vim.schedule(function()
            notify(line)
          end)
        end
      end
    end,
  })
  if job_id > 0 then
    notify('Serveur todoo démarré sur ' .. cfg.host .. ':' .. cfg.port)
  else
    notify('Erreur au démarrage du serveur todoo', vim.log.levels.ERROR)
  end
  return job_id
end

function M.stop_server()
  vim.system({ 'pkill', '-f', 'todoo' }, {}, function()
    vim.schedule(function()
      notify('Serveur todoo arrêté')
    end)
  end)
end

function M.discover_tests()
  local cwd = vim.fn.getcwd()
  local test_files = vim.fn.glob(cwd .. '/**/tests/test_*.py', false, true)
  local modules = {}

  for _, path in ipairs(test_files) do
    local mod_dir = path:match('(.+)/tests/test_')
    if mod_dir then
      local mod_name = vim.fn.fnamemodify(mod_dir, ':t')
      if not modules[mod_name] then
        modules[mod_name] = { name = mod_name, files = {}, classes = {} }
      end
      local file_name = vim.fn.fnamemodify(path, ':t')
      table.insert(modules[mod_name].files, file_name)

      local f = io.open(path, 'r')
      if f then
        for line in f:lines() do
          local cls = line:match('^class%s+(Test%w+)')
          if cls then
            table.insert(modules[mod_name].classes, cls)
          end
        end
        f:close()
      end
    end
  end

  local result = {}
  for _, mod in pairs(modules) do
    table.insert(result, mod)
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

function M.run_tests(test_tags)
  local cfg = config.get().todoo

  M.is_server_running(function(running)
    if not running then
      notify('Démarrage du serveur todoo...')
      M.start_server()
      vim.defer_fn(function()
        M._execute_tests(test_tags, cfg)
      end, 2000)
    else
      M._execute_tests(test_tags, cfg)
    end
  end)
end

function M._execute_tests(test_tags, cfg)
  local payload = vim.json.encode({
    test_tags = test_tags,
    db_name = cfg.db_name,
    db_host = cfg.db_host,
    db_password = cfg.db_password,
    http_port = cfg.http_port,
    with_coverage = false,
  })

  local url = string.format('ws://%s:%d/ws/run-tests', cfg.host, cfg.port)
  local websocat = vim.fn.exepath('websocat')

  if websocat ~= '' then
    M._run_with_websocat(url, payload)
  else
    M._run_with_curl(cfg, test_tags)
  end
end

function M._run_with_websocat(url, payload)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, 'purecraft_todoo_tests')
  vim.api.nvim_set_option_value('filetype', 'purecraft_test', { buf = buf })
  vim.cmd('botright split')
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, 20)

  local lines = { '━━━ Todoo Test Runner ━━━', '' }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace('purecraft_todoo')

  vim.fn.jobstart(
    { 'sh', '-c', string.format("echo '%s' | websocat '%s'", payload:gsub("'", "'\\''"), url) },
    {
      stdout_buffered = false,
      on_stdout = function(_, data)
        for _, line in ipairs(data) do
          if line ~= '' then
            vim.schedule(function()
              if not vim.api.nvim_buf_is_valid(buf) then return end
              local ok, msg = pcall(vim.json.decode, line)
              if ok and msg then
                M._handle_ws_message(buf, ns, msg)
              end
            end)
          end
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            local count = vim.api.nvim_buf_line_count(buf)
            vim.api.nvim_buf_set_lines(buf, count, count, false, { '', '━━━ Terminé ━━━' })
          end
        end)
      end,
    }
  )
end

function M._run_with_curl(cfg, test_tags)
  notify('websocat non trouvé — exécution directe via docker', vim.log.levels.WARN)

  local compose = docker.find_compose_file()
  if not compose then
    notify('docker-compose.yml introuvable', vim.log.levels.ERROR)
    return
  end

  local containers = docker.get_containers_sync(compose)
  local web = nil
  for _, c in ipairs(containers) do
    if c.state == 'running' and (c.service == 'web' or c.service == 'odoo') then
      web = c
      break
    end
  end
  if not web then
    notify('Aucun container web/odoo en cours', vim.log.levels.ERROR)
    return
  end

  local version = require('purecraft.version')
  local port_flag = version.is_legacy() and '--xmlrpc-port=8070' or '--http-port=8070'

  docker.open_terminal({
    'docker', 'exec', '-it', web.name,
    'odoo', '-d', cfg.db_name, '--db_host', cfg.db_host, '--db_password', cfg.db_password,
    '--test-tags', test_tags, '--stop-after-init', '--log-level=test', port_flag,
  }, 'test-' .. test_tags)
end

function M._handle_ws_message(buf, ns, msg)
  local count = vim.api.nvim_buf_line_count(buf)

  if msg.type == 'log' then
    vim.api.nvim_buf_set_lines(buf, count, count, false, { msg.line or '' })

  elseif msg.type == 'test_result' then
    local r = msg.result or {}
    local icon = '?'
    local hl = 'Normal'
    if r.status == 'passed' then
      icon = '✓'
      hl = 'DiagnosticOk'
    elseif r.status == 'failed' then
      icon = '✗'
      hl = 'DiagnosticError'
    elseif r.status == 'error' then
      icon = '!'
      hl = 'DiagnosticError'
    end

    local duration = r.duration_ms and string.format(' (%.1fs)', r.duration_ms / 1000) or ''
    local text = string.format('  %s %s.%s%s', icon, r.test_class or '', r.test_method or '', duration)
    vim.api.nvim_buf_set_lines(buf, count, count, false, { text })
    vim.api.nvim_buf_set_extmark(buf, ns, count, 0, { line_hl_group = hl })

    if r.error_message then
      local err_lines = vim.split(r.error_message, '\n')
      for _, el in ipairs(err_lines) do
        count = count + 1
        vim.api.nvim_buf_set_lines(buf, count, count, false, { '    ' .. el })
      end
    end

  elseif msg.type == 'complete' then
    local s = msg.summary or {}
    local status_icon = msg.status == 'passed' and '✓' or '✗'
    local summary = string.format(
      '%s Total: %d | Passed: %d | Failed: %d | Errors: %d',
      status_icon, s.total or 0, s.passed or 0, s.failed or 0, s.errors or 0
    )
    vim.api.nvim_buf_set_lines(buf, count, count, false, { '', '━━━ ' .. summary .. ' ━━━' })

  elseif msg.type == 'error' then
    vim.api.nvim_buf_set_lines(buf, count, count, false, { 'ERROR: ' .. (msg.message or 'unknown') })
  end

  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
end

-- Telescope picker for test selection
function M.pick_and_run()
  local modules = M.discover_tests()
  if #modules == 0 then
    notify('Aucun test trouvé', vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, mod in ipairs(modules) do
    table.insert(items, { display = '/' .. mod.name .. ' (' .. #mod.files .. ' files)', tag = '/' .. mod.name })
    for _, cls in ipairs(mod.classes) do
      table.insert(items, { display = '  ' .. cls, tag = '/' .. mod.name .. ':' .. cls })
    end
  end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  pickers.new({}, {
    prompt_title = 'Todoo — Sélectionner les tests',
    finder = finders.new_table({
      results = items,
      entry_maker = function(item)
        return { value = item.tag, display = item.display, ordinal = item.display }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local selections = picker:get_multi_selection()
        actions.close(prompt_bufnr)

        local tags = {}
        if #selections > 0 then
          for _, s in ipairs(selections) do
            table.insert(tags, s.value)
          end
        else
          local entry = action_state.get_selected_entry()
          if entry then
            table.insert(tags, entry.value)
          end
        end

        if #tags > 0 then
          M.run_tests(table.concat(tags, ','))
        end
      end)
      return true
    end,
  }):find()
end

return M
