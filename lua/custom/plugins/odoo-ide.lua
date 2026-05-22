local xpath_ns = vim.api.nvim_create_namespace 'odoo_xpath'
local function set_odoo_highlights()
  vim.api.nvim_set_hl(0, 'OdooCodeLens', { italic = true, fg = '#FF8F00' })
  vim.api.nvim_set_hl(0, 'OdooXpathBorder', { fg = '#FFAB40' })
end
set_odoo_highlights()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_odoo_highlights })
local xpath_script = vim.fn.expand '~/.local/share/odoo-ide/xpath_validate.py'
local xpath_timer = nil
local codelens_refreshers = {}

local _cached_version = nil

local function detect_version_from_dockerfile(start_path)
  local dir = start_path
  while dir and dir ~= '/' and dir ~= vim.fn.expand '~' do
    local dockerfile = dir .. '/Dockerfile'
    local f = io.open(dockerfile, 'r')
    if f then
      for line in f:lines() do
        local version = line:match 'FROM%s+odoo:(%d+)%.%d+'
        if version then
          f:close()
          return version
        end
      end
      f:close()
    end
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  return nil
end

local function get_odoo_version()
  if _cached_version then
    return _cached_version
  end
  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path ~= '' then
    _cached_version = detect_version_from_dockerfile(vim.fn.fnamemodify(buf_path, ':h'))
  end
  return _cached_version
end

local function get_search_dirs()
  local home = vim.fn.expand '~'
  local version = get_odoo_version()
  local dirs = {}
  if version then
    local p = home .. '/odoo' .. version .. '/addons'
    if vim.fn.isdirectory(p) == 1 then
      table.insert(dirs, p)
    end
    local e = home .. '/enterprise' .. version .. '.0'
    if vim.fn.isdirectory(e) == 1 then
      table.insert(dirs, e)
    end
  else
    for v = 14, 20 do
      local p = home .. '/odoo' .. v .. '/addons'
      if vim.fn.isdirectory(p) == 1 then
        table.insert(dirs, p)
      end
      local e = home .. '/enterprise' .. v .. '.0'
      if vim.fn.isdirectory(e) == 1 then
        table.insert(dirs, e)
      end
    end
  end
  return dirs
end

local function parse_xml_context(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local inherit_ref = nil
  local xpaths = {}
  local inherits = {}
  local records = {}
  for i, line in ipairs(lines) do
    local rec_id = line:match '<record[^>]+id="([^"]+)"[^>]+model="ir%.ui%.view"'
      or line:match '<record[^>]+model="ir%.ui%.view"[^>]+id="([^"]+)"'
    if rec_id then
      table.insert(records, { lnum = i - 1, id = rec_id, line = line })
    end
    local ref = line:match 'inherit_id[^/]*ref="([^"]+)"'
    if ref then
      inherit_ref = ref
      table.insert(inherits, { lnum = i - 1, ref = ref, line = line })
    end
    local expr = line:match '<xpath%s+expr="([^"]+)"'
    if expr and inherit_ref then
      table.insert(xpaths, { lnum = i - 1, expr = expr, ref = inherit_ref, line = line })
    end
  end
  return xpaths, inherit_ref, inherits, records
end

local function get_xpath_at_cursor(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local cur_line = lines[row]
  local expr = cur_line and cur_line:match '<xpath%s+expr="([^"]+)"'
  if not expr then
    return nil, nil
  end
  local inherit_ref = nil
  for i = row, 1, -1 do
    local ref = lines[i]:match 'inherit_id[^/]*ref="([^"]+)"'
    if ref then
      inherit_ref = ref
      break
    end
  end
  return expr, inherit_ref
end

local function validate_xpaths_in_buffer(bufnr)
  if vim.bo[bufnr].filetype ~= 'xml' then
    return
  end
  local xpaths, _, inherits, records = parse_xml_context(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, xpath_ns, 0, -1)
  vim.diagnostic.set(xpath_ns, bufnr, {})

  for _, inh in ipairs(inherits) do
    local indent = inh.line:match '^(%s*)' or ''
    vim.api.nvim_buf_set_extmark(bufnr, xpath_ns, inh.lnum, 0, {
      virt_lines_above = true,
      virt_lines = {
        { { indent .. 'Inherited view → ' .. inh.ref, 'OdooCodeLens' } },
      },
    })
  end

  if #records > 0 then
    local dirs_json = vim.json.encode(get_search_dirs())
    local buf_path = vim.api.nvim_buf_get_name(bufnr)
    local addon_dir = buf_path:match '(.-)/' and vim.fn.fnamemodify(buf_path, ':h')
    while addon_dir and addon_dir ~= '/' do
      if vim.fn.filereadable(addon_dir .. '/__manifest__.py') == 1 then
        break
      end
      addon_dir = vim.fn.fnamemodify(addon_dir, ':h')
    end
    local module_name = addon_dir and vim.fn.fnamemodify(addon_dir, ':t') or ''

    for _, rec in ipairs(records) do
      vim.system({ 'python3', xpath_script, 'count', dirs_json, rec.id, module_name }, { text = true }, function(obj)
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end
          if obj.code == 0 and obj.stdout and obj.stdout ~= '' then
            local ok, result = pcall(vim.json.decode, obj.stdout)
            if ok and result and result.count and result.count > 0 then
              local indent = rec.line:match '^(%s*)' or ''
              vim.api.nvim_buf_set_extmark(bufnr, xpath_ns, rec.lnum, 0, {
                virt_lines_above = true,
                virt_lines = {
                  { { indent .. result.count .. ' inheriting view(s)', 'OdooCodeLens' } },
                },
              })
            end
          end
        end)
      end)
    end
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local depth = 0
  for i, line in ipairs(lines) do
    if line:match '<xpath%s' then
      depth = depth + 1
    end
    if depth > 0 then
      vim.api.nvim_buf_set_extmark(bufnr, xpath_ns, i - 1, 0, {
        sign_text = '│',
        sign_hl_group = 'OdooXpathBorder',
      })
    end
    if line:match '</xpath>' then
      depth = depth - 1
    end
  end

  if #xpaths == 0 then
    return
  end

  local dirs_json = vim.json.encode(get_search_dirs())
  local diagnostics = {}
  local pending = #xpaths

  for _, xp in ipairs(xpaths) do
    vim.system({ 'python3', xpath_script, 'validate', dirs_json, xp.ref, xp.expr }, { text = true }, function(obj)
      vim.schedule(function()
        pending = pending - 1
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        if obj.code == 0 and obj.stdout and obj.stdout ~= '' then
          local ok, result = pcall(vim.json.decode, obj.stdout)
          if ok and result and result.error_segment and result.error_segment ~= vim.NIL then
            local expr_start = xp.line:find(xp.expr, 1, true)
            if expr_start then
              local err_col = expr_start - 1 + result.valid_end
              local err_end = expr_start - 1 + result.total
              vim.api.nvim_buf_set_extmark(bufnr, xpath_ns, xp.lnum, err_col, {
                end_col = err_end,
                hl_group = 'DiagnosticUnderlineError',
              })
              table.insert(diagnostics, {
                lnum = xp.lnum,
                col = err_col,
                end_col = err_end,
                message = 'XPath not found: ' .. result.error_segment,
                severity = vim.diagnostic.severity.ERROR,
                source = 'odoo-xpath',
              })
            end
          end
        end
        if pending == 0 then
          vim.diagnostic.set(xpath_ns, bufnr, diagnostics)
        end
      end)
    end)
  end
end

local function debounced_validate(bufnr)
  if xpath_timer then
    xpath_timer:stop()
  end
  xpath_timer = vim.defer_fn(function()
    validate_xpaths_in_buffer(bufnr)
  end, 500)
end

local function get_module_name(bufnr)
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  local dir = vim.fn.fnamemodify(buf_path, ':h')
  while dir and dir ~= '/' do
    if vim.fn.filereadable(dir .. '/__manifest__.py') == 1 then
      return vim.fn.fnamemodify(dir, ':t')
    end
    dir = vim.fn.fnamemodify(dir, ':h')
  end
  return ''
end

local function goto_xpath_target(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local cur_line = lines[row] or ''

  local rec_id = cur_line:match '<record[^>]+id="([^"]+)"[^>]+model="ir%.ui%.view"'
    or cur_line:match '<record[^>]+model="ir%.ui%.view"[^>]+id="([^"]+)"'
  if rec_id then
    local dirs_json = vim.json.encode(get_search_dirs())
    local module_name = get_module_name(bufnr)
    vim.system({ 'python3', xpath_script, 'count', dirs_json, rec_id, module_name }, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 or not obj.stdout or obj.stdout == '' then
          vim.notify('[odoo-ide] No inheriting views found', vim.log.levels.INFO)
          return
        end
        local ok, result = pcall(vim.json.decode, obj.stdout)
        if not ok or not result.locations or #result.locations == 0 then
          vim.notify('[odoo-ide] No inheriting views found', vim.log.levels.INFO)
          return
        end
        local items = {}
        for _, loc in ipairs(result.locations) do
          table.insert(items, { filename = loc.file, lnum = loc.line, col = 1 })
        end
        vim.fn.setqflist(items, 'r')
        require('telescope.builtin').quickfix { jump_type = 'never' }
      end)
    end)
    return
  end

  local expr, ref = get_xpath_at_cursor(bufnr)
  if not expr or not ref then
    require('telescope.builtin').lsp_definitions { jump_type = 'never' }
    return
  end

  local dirs_json = vim.json.encode(get_search_dirs())
  vim.system({ 'python3', xpath_script, 'locate', dirs_json, ref, expr }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 or not obj.stdout or obj.stdout == '' then
        vim.notify('[odoo-ide] Could not locate xpath target', vim.log.levels.WARN)
        return
      end
      local ok, result = pcall(vim.json.decode, obj.stdout)
      if not ok or result.error then
        vim.notify('[odoo-ide] ' .. (result and result.error or 'parse error'), vim.log.levels.WARN)
        return
      end
      vim.fn.setqflist({ { filename = result.file, lnum = result.line, col = 1 } }, 'r')
      require('telescope.builtin').quickfix { jump_type = 'never' }
    end)
  end)
end

return {
  'neovim/nvim-lspconfig',
  opts = function(_, opts)
    local lspconfig = require 'lspconfig'
    local configs = require 'lspconfig.configs'

    local server_path = vim.fn.expand '~/.local/share/odoo-ide/server.js'
    local data_path = vim.fn.expand '~/.local/share/odoo-ide/data'
    local home = vim.fn.expand '~'

    local function detect_odoo_version(project_root)
      local version = detect_version_from_dockerfile(project_root)
      if version then
        _cached_version = version
      end
      return version
    end

    local function build_odoo_folders(version, project_root)
      local folders = {
        { uri = vim.uri_from_fname(project_root), name = vim.fn.fnamemodify(project_root, ':t') },
      }
      local odoo_path = home .. '/odoo' .. version
      if vim.fn.isdirectory(odoo_path) == 1 then
        table.insert(folders, { uri = vim.uri_from_fname(odoo_path), name = 'odoo' .. version })
      end
      local enterprise_path = home .. '/enterprise' .. version .. '.0'
      if vim.fn.isdirectory(enterprise_path) == 1 then
        table.insert(folders, { uri = vim.uri_from_fname(enterprise_path), name = 'enterprise' .. version .. '.0' })
      end
      return folders
    end

    local function root_dir(fname)
      local util = require 'lspconfig.util'
      local manifest = util.root_pattern '__manifest__.py'(fname)
      if manifest then
        return vim.fn.fnamemodify(manifest, ':h')
      end
      return util.root_pattern('.git', 'pyrightconfig.json')(fname)
    end

    if not configs.odoo_ide then
      configs.odoo_ide = {
        default_config = {
          cmd = {
            'node',
            '--max-old-space-size=3072',
            '--disable-warning=ExperimentalWarning',
            server_path,
            '--stdio',
            '--dataStoragePath=' .. data_path,
          },
          filetypes = { 'python', 'xml' },
          root_dir = root_dir,
          single_file_support = false,
        },
      }
    end

    lspconfig.odoo_ide.setup {
      before_init = function(params, config)
        local project_root = config.root_dir
        if not project_root then
          return
        end
        local version = detect_odoo_version(project_root)
        if not version then
          return
        end
        local folders = build_odoo_folders(version, project_root)
        params.workspaceFolders = folders
        config._odoo_version = version
      end,

      on_init = function(client, _)
        local version = client.config._odoo_version
        if version then
          local folders = client.workspace_folders or {}
          vim.notify('[odoo-ide] Odoo ' .. version .. '.0 | ' .. #folders .. ' workspace folders', vim.log.levels.INFO)
        end
        return false
      end,

      on_new_config = function(new_config, project_root)
        local version = detect_odoo_version(project_root)
        if not version then
          return
        end
        local folders = build_odoo_folders(version, project_root)
        local extra_paths = vim.tbl_map(function(wf)
          return vim.uri_to_fname(wf.uri)
        end, folders)

        new_config.settings = {
          python = {
            pythonPath = vim.fn.exepath 'python3',
            analysis = {
              autoSearchPaths = true,
              extraPaths = extra_paths,
              typeCheckingMode = 'standard',
              diagnosticMode = 'openFilesOnly',
            },
          },
        }
      end,

      on_attach = function(client, bufnr)
        local codelens_ns = vim.api.nvim_create_namespace 'odoo_codelens'
        local codelens_data = {}

        local function render_codelens(lenses)
          vim.api.nvim_buf_clear_namespace(bufnr, codelens_ns, 0, -1)
          codelens_data = {}
          if not lenses then
            return
          end
          local by_line = {}
          for _, lens in ipairs(lenses) do
            if lens.command then
              local line = lens.range.start.line
              by_line[line] = by_line[line] or {}
              table.insert(by_line[line], lens)
            end
          end
          for line, line_lenses in pairs(by_line) do
            local code_line = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ''
            local indent = code_line:match '^(%s*)' or ''
            local texts = { { indent, '' } }
            for i, lens in ipairs(line_lenses) do
              if i > 1 then
                table.insert(texts, { ' | ', 'OdooCodeLens' })
              end
              table.insert(texts, { lens.command.title, 'OdooCodeLens' })
            end
            if #texts > 1 and line < vim.api.nvim_buf_line_count(bufnr) then
              vim.api.nvim_buf_set_extmark(bufnr, codelens_ns, line, 0, {
                virt_lines_above = true,
                virt_lines = { texts },
              })
              codelens_data[line] = line_lenses
            end
          end
        end

        local codelens_timer = nil
        local function refresh_codelens()
          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end
          local params = { textDocument = { uri = vim.uri_from_bufnr(bufnr) } }
          client:request('textDocument/codeLens', params, function(err, result)
            if err or not result or #result == 0 then
              return
            end
            local pending = 0
            for _, lens in ipairs(result) do
              if not lens.command then
                pending = pending + 1
                client:request('codeLens/resolve', lens, function(_, resolved)
                  if resolved and resolved.command then
                    lens.command = resolved.command
                  end
                  pending = pending - 1
                  if pending == 0 then
                    render_codelens(result)
                  end
                end, bufnr)
              end
            end
            if pending == 0 then
              render_codelens(result)
            end
          end, bufnr)
        end

        local function debounced_codelens()
          if codelens_timer then
            codelens_timer:stop()
          end
          codelens_timer = vim.defer_fn(refresh_codelens, 1000)
        end

        codelens_refreshers[bufnr] = refresh_codelens
        vim.api.nvim_create_autocmd('BufDelete', {
          buffer = bufnr,
          once = true,
          callback = function()
            codelens_refreshers[bufnr] = nil
          end,
        })

        vim.defer_fn(refresh_codelens, 3000)
        vim.api.nvim_create_autocmd('BufEnter', {
          buffer = bufnr,
          callback = refresh_codelens,
        })
        vim.api.nvim_create_autocmd({ 'InsertLeave', 'TextChanged' }, {
          buffer = bufnr,
          callback = debounced_codelens,
        })
        vim.keymap.set('n', '<leader>cl', function()
          local row = vim.api.nvim_win_get_cursor(0)[1] - 1
          local lenses = codelens_data[row]
          if not lenses then
            for line, l in pairs(codelens_data) do
              if line == row or line == row - 1 or line == row + 1 then
                lenses = l
                break
              end
            end
          end
          if lenses and #lenses > 0 and lenses[1].command then
            local cmd = lenses[1].command
            if vim.lsp.commands[cmd.command] then
              vim.lsp.commands[cmd.command]({ arguments = cmd.arguments })
            else
              vim.notify('[odoo-ide] Unknown command: ' .. cmd.command, vim.log.levels.WARN)
            end
          else
            vim.notify('[odoo-ide] No CodeLens here', vim.log.levels.INFO)
          end
        end, { buffer = bufnr, desc = '[C]ode [L]ens run' })

        -- Register custom peek command for CodeLens
        vim.lsp.commands['odoo-ide.action.peekLocations'] = function(cmd)
          local args = cmd.arguments or {}
          local locations = args[3]
          if not locations or #locations == 0 then
            vim.notify('[odoo-ide] No locations', vim.log.levels.WARN)
            return
          end
          local items = {}
          for _, loc in ipairs(locations) do
            table.insert(items, {
              filename = loc.path,
              lnum = (loc.range.start.line or 0) + 1,
              col = (loc.range.start.character or 0) + 1,
            })
          end
          vim.fn.setqflist(items, 'r')
          require('telescope.builtin').quickfix { jump_type = 'never' }
        end

        -- <leader>g / double-click : LSP definition or xpath target
        local function smart_goto()
          local row = vim.api.nvim_win_get_cursor(0)[1] - 1
          local lenses = codelens_data[row]
          if not lenses then
            for line, l in pairs(codelens_data) do
              if line == row or line == row - 1 then
                lenses = l
                break
              end
            end
          end
          if lenses and #lenses > 0 and lenses[1].command then
            local cmd = lenses[1].command
            if vim.lsp.commands[cmd.command] then
              vim.lsp.commands[cmd.command]({ arguments = cmd.arguments })
              return
            end
          end
          goto_xpath_target(bufnr)
        end
        vim.keymap.set('n', '<leader>g', smart_goto, { buffer = bufnr, desc = '[G]oto Definition / XPath target' })
        vim.keymap.set('n', '<2-LeftMouse>', smart_goto, { buffer = bufnr })

        -- Workspace-wide search (Ctrl+P / Ctrl+G)
        local workspace_dirs = {}
        local folders = client.workspace_folders or {}
        for _, wf in ipairs(folders) do
          table.insert(workspace_dirs, vim.uri_to_fname(wf.uri))
        end
        if #workspace_dirs > 0 then
          vim.keymap.set('n', '<C-p>', function()
            require('telescope.builtin').find_files { search_dirs = workspace_dirs }
          end, { buffer = bufnr, desc = 'Find files (Odoo workspace)' })
          vim.keymap.set('n', '<C-g>', function()
            require('telescope.builtin').live_grep { search_dirs = workspace_dirs }
          end, { buffer = bufnr, desc = 'Search in files (Odoo workspace)' })
        end

        -- XPath validation
        validate_xpaths_in_buffer(bufnr)
        vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
          buffer = bufnr,
          callback = function()
            debounced_validate(bufnr)
          end,
        })
        vim.api.nvim_create_autocmd('BufWritePost', {
          buffer = bufnr,
          callback = function()
            validate_xpaths_in_buffer(bufnr)
          end,
        })
      end,

      handlers = {
        ['workspace/diagnostic/refresh'] = function()
          return vim.NIL
        end,
        ['workspace/codeLens/refresh'] = function()
          for _, fn in pairs(codelens_refreshers) do
            vim.schedule(fn)
          end
          return vim.NIL
        end,
      },

      capabilities = vim.lsp.protocol.make_client_capabilities(),
    }
  end,
}
