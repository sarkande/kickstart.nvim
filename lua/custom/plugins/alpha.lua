return {
  'goolord/alpha-nvim',
  config = function()
    local alpha = require 'alpha'
    local dashboard = require 'alpha.themes.dashboard'
    local home = vim.fn.expand '~'
    local cwd = vim.fn.getcwd()
    local cwd_esc = vim.fn.shellescape(cwd)

    local function detect_odoo()
      local dir = cwd
      while dir and dir ~= '/' and dir ~= home do
        local f = io.open(dir .. '/Dockerfile', 'r')
        if f then
          for line in f:lines() do
            local v = line:match 'FROM%s+odoo:(%d+%.%d+)'
            if v then
              f:close()
              return v:match '^(%d+)', v, dir
            end
          end
          f:close()
        end
        dir = vim.fn.fnamemodify(dir, ':h')
      end
    end

    local function detect_ports(dir)
      local ports = {}
      local f = io.open(dir .. '/docker-compose.yml', 'r')
      if not f then
        return ports
      end
      local in_ports = false
      for line in f:lines() do
        if line:match '^%s+ports:' then
          in_ports = true
        elseif in_ports then
          local host, container = line:match '"(%d+):(%d+)"'
          if host then
            table.insert(ports, host .. ' → ' .. container)
          elseif not line:match '^%s+-' and not line:match '^%s*$' then
            in_ports = false
          end
        end
      end
      f:close()
      return ports
    end

    local function get_git()
      local branch = vim.fn.system('git -C ' .. cwd_esc .. ' branch --show-current 2>/dev/null'):gsub('\n', '')
      if branch == '' then
        return nil
      end
      local status_out = vim.fn.system('git -C ' .. cwd_esc .. ' status --porcelain 2>/dev/null')
      local modified, untracked, staged = 0, 0, 0
      for line in status_out:gmatch '[^\n]+' do
        local x, y = line:sub(1, 1), line:sub(2, 2)
        if x == '?' then
          untracked = untracked + 1
        elseif x ~= ' ' and y ~= ' ' then
          staged = staged + 1
          modified = modified + 1
        elseif x ~= ' ' then
          staged = staged + 1
        elseif y ~= ' ' then
          modified = modified + 1
        end
      end
      local log_out = vim.fn.system('git -C ' .. cwd_esc .. ' log --oneline -5 2>/dev/null')
      local commits = {}
      for line in log_out:gmatch '[^\n]+' do
        local hash, msg = line:match '^(%S+)%s+(.+)'
        if hash then
          if #msg > 48 then
            msg = msg:sub(1, 45) .. '...'
          end
          table.insert(commits, { hash = hash:sub(1, 7), msg = msg })
        end
      end
      return { branch = branch, modified = modified, untracked = untracked, staged = staged, commits = commits }
    end

    local function sep(title, width)
      local t = '── ' .. title .. ' '
      local remaining = width - vim.fn.strdisplaywidth(t)
      if remaining > 0 then
        return t .. string.rep('─', remaining)
      end
      return t
    end

    local function pad(lines, width)
      for i, l in ipairs(lines) do
        local n = width - vim.fn.strdisplaywidth(l)
        if n > 0 then
          lines[i] = l .. string.rep(' ', n)
        end
      end
    end

    -- Gather data
    local major, version_full, docker_dir = detect_odoo()
    local ports = docker_dir and detect_ports(docker_dir) or {}
    local git = get_git()

    -- Build content lines
    local project_lines = {}
    if major then
      table.insert(project_lines, '    Project      ' .. vim.fn.fnamemodify(cwd, ':~'))
      local odoo_path = home .. '/odoo' .. major
      if vim.fn.isdirectory(odoo_path) == 1 then
        table.insert(project_lines, '    Odoo         ' .. vim.fn.fnamemodify(odoo_path, ':~'))
      end
      local ent_path = home .. '/enterprise' .. major .. '.0'
      if vim.fn.isdirectory(ent_path) == 1 then
        table.insert(project_lines, '    Enterprise   ' .. vim.fn.fnamemodify(ent_path, ':~'))
      end
      if #ports > 0 then
        table.insert(project_lines, '')
        table.insert(project_lines, '    Ports        ' .. table.concat(ports, '   '))
      end
    else
      table.insert(project_lines, '    ' .. vim.fn.fnamemodify(cwd, ':~'))
    end

    local commit_lines = {}
    if git then
      for _, c in ipairs(git.commits) do
        table.insert(commit_lines, '    ' .. c.hash .. '  ' .. c.msg)
      end
    end

    -- Compute max width and pad all blocks
    local max_w = 50
    for _, lines in ipairs { project_lines, commit_lines } do
      for _, l in ipairs(lines) do
        max_w = math.max(max_w, vim.fn.strdisplaywidth(l))
      end
    end
    pad(project_lines, max_w)
    pad(commit_lines, max_w)

    -- Build layout
    local sections = {
      { type = 'padding', val = 2 },
      {
        type = 'text',
        val = {
          '  ███╗   ██╗██╗   ██╗██╗███╗   ███╗',
          '  ████╗  ██║██║   ██║██║████╗ ████║',
          '  ██╔██╗ ██║██║   ██║██║██╔████╔██║',
          '  ██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║',
          '  ██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║',
          '  ╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝',
        },
        opts = { position = 'center', hl = 'Type' },
      },
      { type = 'padding', val = 1 },
      {
        type = 'text',
        val = sep(major and ('Odoo ' .. version_full) or vim.fn.fnamemodify(cwd, ':t'), max_w),
        opts = { position = 'center', hl = 'Type' },
      },
      { type = 'padding', val = 1 },
      {
        type = 'text',
        val = project_lines,
        opts = { position = 'center', hl = 'Comment' },
      },
    }

    if git then
      local status_parts = {}
      if git.staged > 0 then
        table.insert(status_parts, git.staged .. ' staged')
      end
      if git.modified > 0 then
        table.insert(status_parts, git.modified .. ' modified')
      end
      if git.untracked > 0 then
        table.insert(status_parts, git.untracked .. ' untracked')
      end
      local git_title = 'Git (' .. git.branch .. ')'
      if #status_parts > 0 then
        git_title = git_title .. ' ─ ' .. table.concat(status_parts, ' · ')
      end

      table.insert(sections, { type = 'padding', val = 1 })
      table.insert(sections, {
        type = 'text',
        val = sep(git_title, max_w),
        opts = { position = 'center', hl = 'Type' },
      })
      if #commit_lines > 0 then
        table.insert(sections, { type = 'padding', val = 1 })
        table.insert(sections, {
          type = 'text',
          val = commit_lines,
          opts = { position = 'center', hl = 'Comment' },
        })
      end
    end

    table.insert(sections, { type = 'padding', val = 2 })
    table.insert(sections, {
      type = 'group',
      val = {
        dashboard.button('p', '→  Find file', '<cmd>Telescope find_files<CR>'),
        dashboard.button('g', '→  Grep text', '<cmd>Telescope live_grep<CR>'),
        dashboard.button('r', '→  Recent files', '<cmd>Telescope oldfiles<CR>'),
        dashboard.button('n', '→  New file', '<cmd>enew<CR>'),
        dashboard.button('q', '→  Quit', '<cmd>qa!<CR>'),
      },
    })

    alpha.setup { layout = sections }

    vim.api.nvim_create_autocmd('VimEnter', {
      callback = function()
        local should_dashboard = vim.fn.argc() == 0
          or (vim.fn.argc() == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1)
        if not should_dashboard then
          return
        end
        vim.defer_fn(function()
          local ok, err = pcall(alpha.start, false)
          if not ok then
            vim.notify('Dashboard: ' .. tostring(err), vim.log.levels.WARN)
          end
          pcall(vim.cmd, 'Neotree show')
        end, 150)
      end,
    })
  end,
}
