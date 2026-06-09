-- Configuration NvChad (fusionnée avec les défauts de nvconfig par le plugin).
-- Pour l'instant : juste le thème de départ. On portera ayu en étape 2 et on
-- branchera le theme picker / colorify ensuite.
---@type ChadrcConfig
local M = {}

M.base46 = {
  -- ayu_light = exactement la palette ayu qu'on avait (fg #5C6166, tag cyan,
  -- keyword orange, string vert, etc.), thème base46 intégré.
  theme = 'ayu_light',
  -- <leader>tt (et le bouton en haut à droite) bascule entre ces deux :
  -- sombre = onedark (le défaut NvChad), clair = ayu_light.
  theme_toggle = { 'onedark', 'ayu_light' },
}

M.ui = {
  statusline = {
    -- Ordre par défaut NvChad (thème "default") + un module "odoo" inséré
    -- juste avant "cwd" (le dossier workspace).
    order = { 'mode', 'file', 'git', '%=', 'lsp_msg', '%=', 'diagnostics', 'lsp', 'odoo', 'cwd', 'cursor' },
    modules = {
      -- Version Odoo détectée par odoo-ide (vim.g.odoo_version), affichée dans
      -- la barre. Vide tant que le LSP odoo n'a pas attaché.
      odoo = function()
        local v = vim.g.odoo_version
        if v and v ~= '' then
          return '%#St_cwd_txt# Odoo ' .. v .. '.0 '
        end
        return ''
      end,
    },
  },
}

return M
