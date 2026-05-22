local M = {}

local data_dir = vim.fn.stdpath('data') .. '/purecraft'
local config_file = data_dir .. '/config.json'

local defaults = {
  odoo = {
    host = 'localhost',
    port = 8235,
    db = '',
    user = '',
    pass = '',
  },
  todoo = {
    host = '127.0.0.1',
    port = 8080,
    db_name = 'odoo',
    db_host = 'db',
    db_password = 'odoo',
    http_port = 8070,
    preferred_service = 'web',
  },
  db_history = {},
  last_upgrade_modules = {},
  favorite_projects = {},
  current_task = { id = nil, name = nil, project = nil },
}

local _state = nil

local function ensure_dir()
  vim.fn.mkdir(data_dir, 'p')
end

function M.load()
  if _state then
    return _state
  end
  ensure_dir()
  local f = io.open(config_file, 'r')
  if f then
    local content = f:read('*a')
    f:close()
    local ok, data = pcall(vim.json.decode, content)
    if ok and data then
      _state = vim.tbl_deep_extend('force', vim.deepcopy(defaults), data)
      return _state
    end
  end
  _state = vim.deepcopy(defaults)
  return _state
end

function M.save()
  ensure_dir()
  local f = io.open(config_file, 'w')
  if f then
    f:write(vim.json.encode(_state or defaults))
    f:close()
  end
end

function M.get()
  return M.load()
end

function M.update(key, value)
  local cfg = M.load()
  local keys = vim.split(key, '.', { plain = true })
  local tbl = cfg
  for i = 1, #keys - 1 do
    tbl[keys[i]] = tbl[keys[i]] or {}
    tbl = tbl[keys[i]]
  end
  tbl[keys[#keys]] = value
  M.save()
end

function M.add_db_history(db_name)
  local cfg = M.load()
  local history = cfg.db_history
  for i, v in ipairs(history) do
    if v == db_name then
      table.remove(history, i)
      break
    end
  end
  table.insert(history, 1, db_name)
  while #history > 10 do
    table.remove(history)
  end
  M.save()
end

return M
