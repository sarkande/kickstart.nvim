local M = {}

local compose_names = {
  'docker-compose.yml',
  'docker-compose.yaml',
  'compose.yml',
  'compose.yaml',
}

local function resolve_buf_dir()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname:find('^oil://') then
    return bufname:gsub('^oil://', ''):gsub('/$', '')
  end
  if bufname ~= '' then
    return vim.fn.fnamemodify(bufname, ':h')
  end
  return nil
end

function M.find_compose_file(start_dir)
  local candidates = {}
  if start_dir then
    table.insert(candidates, start_dir)
  end
  local buf_dir = resolve_buf_dir()
  if buf_dir then
    table.insert(candidates, buf_dir)
  end
  table.insert(candidates, vim.fn.getcwd())

  for _, base in ipairs(candidates) do
    local dir = base
    for _ = 1, 8 do
      for _, name in ipairs(compose_names) do
        local path = dir .. '/' .. name
        if vim.fn.filereadable(path) == 1 then
          return path
        end
      end
      local parent = vim.fn.fnamemodify(dir, ':h')
      if parent == dir then
        break
      end
      dir = parent
    end
  end
  return nil
end

function M.get_compose_dir(compose_file)
  return vim.fn.fnamemodify(compose_file, ':h')
end

function M.get_containers(compose_file, callback)
  vim.system(
    { 'docker', 'compose', '-f', compose_file, 'ps', '--format', 'json' },
    { text = true },
    function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          callback({})
          return
        end
        local containers = {}
        for line in obj.stdout:gmatch('[^\n]+') do
          local ok, c = pcall(vim.json.decode, line)
          if ok and c then
            table.insert(containers, {
              id = c.ID,
              name = c.Name,
              service = c.Service,
              state = c.State,
            })
          end
        end
        callback(containers)
      end)
    end
  )
end

function M.get_containers_sync(compose_file)
  local obj = vim.system(
    { 'docker', 'compose', '-f', compose_file, 'ps', '--format', 'json' },
    { text = true }
  ):wait()
  if obj.code ~= 0 then
    return {}
  end
  local containers = {}
  for line in obj.stdout:gmatch('[^\n]+') do
    local ok, c = pcall(vim.json.decode, line)
    if ok and c then
      table.insert(containers, {
        id = c.ID,
        name = c.Name,
        service = c.Service,
        state = c.State,
      })
    end
  end
  return containers
end

function M.get_services(compose_file)
  local f = io.open(compose_file, 'r')
  if not f then
    return {}
  end
  local content = f:read('*a')
  f:close()
  local services = {}
  local in_services = false
  for line in content:gmatch('[^\n]+') do
    if line:match('^services:') then
      in_services = true
    elseif in_services then
      local svc = line:match('^  ([%w_-]+):')
      if svc then
        table.insert(services, svc)
      elseif not line:match('^%s') and line ~= '' then
        break
      end
    end
  end
  return services
end

function M.get_container_name(compose_file, service)
  local f = io.open(compose_file, 'r')
  if not f then
    return nil
  end
  local content = f:read('*a')
  f:close()
  local in_service = false
  local indent_level = nil
  for line in content:gmatch('[^\n]+') do
    if line:match('^  ' .. service .. ':') then
      in_service = true
      indent_level = 2
    elseif in_service then
      local cn = line:match('^%s+container_name:%s*(.+)')
      if cn then
        return vim.trim(cn)
      end
      if not line:match('^%s') or (line:match('^  [%w]') and not line:match('^%s%s%s')) then
        break
      end
    end
  end
  return nil
end

function M.open_terminal(cmd, name)
  vim.cmd('tabnew')
  vim.fn.termopen(cmd)
  if name then
    pcall(vim.api.nvim_buf_set_name, 0, 'purecraft_' .. name:gsub('[^%w_-]', '_'))
  end
  vim.cmd('startinsert')
end

return M
