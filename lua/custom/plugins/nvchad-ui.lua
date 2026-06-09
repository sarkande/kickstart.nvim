-- NvChad UI en mode STANDALONE (sans importer tout le stack NvChad).
-- Apporte : moteur de thème base46 (+ theme picker), colorify, statusline,
-- tabufline, NvCheatsheet. On cohabite avec kickstart (telescope/blink/etc.).
-- Config pilotée par lua/chadrc.lua.
return {
  {
    'nvchad/ui',
    config = function()
      require 'nvchad'

      local map = vim.keymap.set
      -- <leader>tt : bascule clair ⇆ sombre (paire définie dans chadrc.theme_toggle)
      map('n', '<leader>tt', function()
        require('base46').toggle_theme()
      end, { desc = '[T]oggle thème clair/sombre' })
      -- <leader>ts : sélecteur de thème (picker, parcourt les 68 + tes customs)
      map('n', '<leader>ts', function()
        require('nvchad.themes').open()
      end, { desc = '[T]hème : [S]électeur' })
    end,
  },
  {
    'nvchad/base46',
    lazy = true,
    build = function()
      -- Compile les thèmes en cache de bytecode (vim.g.base46_cache).
      require('base46').load_all_highlights()
    end,
  },
  -- Lib UI (theme picker, cheatsheet, colorify s'appuient dessus).
  { 'nvzone/volt', lazy = true },
}
