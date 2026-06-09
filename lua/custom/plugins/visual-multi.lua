-- Multi-curseur façon VSCode, avec édition EN TEMPS RÉEL sur tous les curseurs.
-- mg979/vim-visual-multi.
return {
  'mg979/vim-visual-multi',
  branch = 'master',
  -- `init` : les variables g:VM_* doivent être posées AVANT que le plugin se
  -- charge (il lit ses globales au source). lazy garantit que init() tourne
  -- avant le chargement du plugin.
  init = function()
    -- Remappe les actions VM sur <leader> (priorité raccourcis VSCode).
    --  <leader>n : sélectionne le mot sous le curseur et démarre le multi-curseur
    --              (= Cmd+D). Réappuyer ajoute l'occurrence suivante.
    --  En visuel, <leader>n part de la sélection courante (« Find Subword »).
    vim.g.VM_maps = {
      ['Find Under'] = '<leader>n', -- normal : mot sous le curseur + occurrence suivante
      ['Find Subword Under'] = '<leader>n', -- visuel : idem sur la sélection
      ['Select All'] = '<leader>A', -- toutes les occurrences d'un coup
      ['Skip Region'] = '<leader>q', -- sauter l'occurrence courante (passe à la suivante)
      ['Remove Region'] = '<leader>Q', -- retirer le curseur courant
    }

    -- Confort.
    vim.g.VM_silent_exit = 1 -- pas de message quand on quitte le mode VM
    vim.g.VM_show_warnings = 0
    vim.g.VM_set_statusline = 0 -- on garde la statusline mini.nvim intacte
  end,
}
