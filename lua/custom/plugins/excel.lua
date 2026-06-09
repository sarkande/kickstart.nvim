return {
  'mechatroner/rainbow_csv',
  ft = { 'csv', 'tsv' },
  config = function()
    -- Ouvrir un .xlsx : convertir en CSV temporaire et afficher
    vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile' }, {
      pattern = { '*.xlsx', '*.xls' },
      callback = function(ev)
        local src = ev.match
        local tmp = vim.fn.tempname() .. '.csv'

        local ok = vim.fn.system {
          'python3', '-c', string.format([[
import openpyxl, csv, sys
try:
    wb = openpyxl.load_workbook('%s', read_only=True, data_only=True)
    ws = wb.active
    with open('%s', 'w', newline='') as f:
        w = csv.writer(f)
        for row in ws.iter_rows(values_only=True):
            w.writerow(['' if v is None else str(v) for v in row])
    print('ok')
except Exception as e:
    print('ERR:' + str(e), file=sys.stderr)
]], src, tmp),
        }

        if vim.v.shell_error ~= 0 then
          vim.notify('Impossible de lire le fichier Excel', vim.log.levels.ERROR)
          return
        end

        -- Remplacer le buffer par le CSV temporaire (lecture seule)
        vim.schedule(function()
          vim.cmd('edit ' .. tmp)
          vim.bo.readonly = true
          vim.bo.modifiable = false
          vim.notify('Excel → CSV (lecture seule)', vim.log.levels.INFO)
        end)
      end,
    })
  end,
}
