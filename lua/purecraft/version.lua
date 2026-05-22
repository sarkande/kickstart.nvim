local M = {}

local _cached = nil

local dockerfiles = { 'Dockerfile', 'Dockerfile.dev', 'Dockerfile.odoo' }

local function detect_from_file(path, patterns)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local content = f:read('*a')
  f:close()
  for _, pattern in ipairs(patterns) do
    local major, minor = content:match(pattern)
    if major then
      return tonumber(major), tonumber(minor or 0)
    end
  end
  return nil
end

function M.detect(start_dir)
  if _cached then
    return _cached
  end
  start_dir = start_dir or vim.fn.getcwd()
  local dir = start_dir
  for _ = 1, 6 do
    for _, df in ipairs(dockerfiles) do
      local major, minor = detect_from_file(dir .. '/' .. df, {
        'FROM%s+odoo:(%d+)%.?(%d*)',
      })
      if major then
        _cached = { major = major, minor = minor, raw = major .. '.' .. minor, is_legacy = major < 19 }
        return _cached
      end
    end

    local docker = require('purecraft.docker')
    local compose = docker.find_compose_file(dir)
    if compose then
      local major, minor = detect_from_file(compose, {
        'image:%s*odoo:(%d+)%.?(%d*)',
        'enterprise(%d+)%.?(%d*):',
        'dockerfile:.*odoo[:%-%.]?(%d+)%.?(%d*)',
      })
      if major then
        _cached = { major = major, minor = minor, raw = major .. '.' .. minor, is_legacy = major < 19 }
        return _cached
      end
    end

    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then
      break
    end
    dir = parent
  end
  return nil
end

function M.is_legacy()
  local v = M.detect()
  if not v then
    return true
  end
  return v.is_legacy
end

function M.clear_cache()
  _cached = nil
end

return M
