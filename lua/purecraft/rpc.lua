local config = require('purecraft.config')

local M = {}

local _uid = nil

local function notify(msg, level)
  vim.notify('[purecraft:rpc] ' .. msg, level or vim.log.levels.INFO)
end

local function build_url(cfg)
  local scheme = cfg.port == 443 and 'https' or 'http'
  return string.format('%s://%s:%d/jsonrpc', scheme, cfg.host, cfg.port)
end

local function jsonrpc_call(url, service, method, args, callback)
  local payload = vim.json.encode({
    jsonrpc = '2.0',
    method = 'call',
    params = {
      service = service,
      method = method,
      args = args,
    },
    id = os.time(),
  })

  vim.system(
    { 'curl', '-s', '-X', 'POST', url, '-H', 'Content-Type: application/json', '-d', payload },
    { text = true },
    function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          callback(nil, 'HTTP request failed')
          return
        end
        local ok, resp = pcall(vim.json.decode, obj.stdout)
        if not ok then
          callback(nil, 'JSON parse error')
          return
        end
        if resp.error then
          callback(nil, resp.error.message or 'RPC error')
          return
        end
        callback(resp.result)
      end)
    end
  )
end

function M.login(callback)
  local cfg = config.get().odoo
  if not cfg.host or cfg.host == '' or not cfg.db or cfg.db == '' then
    notify('Configuration Odoo incomplète — :PureCraftSettings', vim.log.levels.ERROR)
    callback(nil, 'missing config')
    return
  end

  local url = build_url(cfg)
  jsonrpc_call(url, 'common', 'login', { cfg.db, cfg.user, cfg.pass }, function(uid, err)
    if err then
      notify('Connexion échouée: ' .. err, vim.log.levels.ERROR)
      callback(nil, err)
      return
    end
    if not uid or uid == false then
      notify('Login/mot de passe incorrect', vim.log.levels.ERROR)
      callback(nil, 'invalid credentials')
      return
    end
    _uid = uid
    callback(uid)
  end)
end

function M.ensure_login(callback)
  if _uid then
    callback(_uid)
    return
  end
  M.login(callback)
end

function M.call(model, method, args, kwargs, callback)
  M.ensure_login(function(uid, err)
    if err then
      if callback then callback(nil, err) end
      return
    end
    local cfg = config.get().odoo
    local url = build_url(cfg)
    local rpc_args = { cfg.db, uid, cfg.pass, model, method, args or {} }
    if kwargs then
      table.insert(rpc_args, kwargs)
    end
    jsonrpc_call(url, 'object', 'execute_kw', rpc_args, function(result, call_err)
      if callback then
        callback(result, call_err)
      end
    end)
  end)
end

function M.search_read(model, domain, fields, callback, kwargs)
  local kw = kwargs or {}
  kw.fields = fields
  M.call(model, 'search_read', { domain }, kw, callback)
end

function M.create(model, vals, callback)
  M.call(model, 'create', { vals }, nil, callback)
end

function M.get_uid()
  return _uid
end

function M.logout()
  _uid = nil
end

return M
