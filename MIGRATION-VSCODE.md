# Migration VSCode → Neovim — checklist de travail

> Suivi des chantiers pour rendre la config nvim aussi confortable que l'ancien
> VSCode (mode Vim). Priorité explicite : **coller aux raccourcis VSCode** quand
> il y a un choix. On coche au fur et à mesure. Chaque chantier = problème →
> proposition → approche → statut.

Légende statut : `[ ]` à faire · `[~]` en cours · `[x]` fait · `[?]` à décider ensemble

---

## 0. Quick wins (validés, à appliquer)

- [x] **`have_nerd_font = true`** (init.lua:94). Kitty tourne en *DankMono Nerd Font*,
  donc on débloque les icônes partout (which-key, statusline, lazy, mini.icons,
  neo-tree, telescope). Aucun risque. ✅ testé OK.
- [x] **`relativenumber`** (init.lua:106). Activer en plus de `number` → numéros
  hybrides (ligne courante absolue, le reste relatif) pour les sauts `5j`/`12k`.
  ✅ testé OK. ⚠️ voir §11 : pas assez visibles.
- [x] **Virer `oil.nvim`**, garder neo-tree comme explorateur unique. ✅ Fait :
  `oil.lua` supprimé, branches `if filetype == 'oil'` retirées de `<D-e>` et
  neo-tree.lua, hijack netrw ajouté (`hijack_netrw_behavior = 'open_current'`),
  `:Lazy clean` pour désinstaller oil + mini.icons. Reste la branche `oil://`
  défensive dans `purecraft/docker.lua` (à nettoyer en §6).

---

## 1. 🔍 Recherche (LE gros morceau — priorité n°1)

**Problèmes signalés :**
- Trop compliqué à utiliser ; même `Cmd+Shift+F` ne satisfait pas.
- Des fichiers qu'on ne trouve pas (probable : respect du `.gitignore` / dossiers
  sources Odoo hors cwd / fichiers cachés ignorés).
- Spam de `.po`, `.pot`, tests, etc.
- Besoin de **toggle des types** (un coup Python, un coup XML, un coup JS).
- **Pas d'énième raccourci** : on veut du **visuel façon VSCode** — un input
  *include* (`*.js,*.xml`) et un *exclude* sur le même principe.
- **Persistance** : à la réouverture de nvim, on retrouve ses filtres.

**Proposition — un seul point d'entrée, des filtres persistants :**

Un module maison `lua/purecraft/search.lua` (ou `custom/plugins/search.lua`) qui :

1. Tient un état `{ include = {...globs}, exclude = {...globs} }`.
2. **Persiste sur disque** (`stdpath('state') .. '/odoo-search.json'`), chargé au
   démarrage → les filtres survivent au redémarrage.
3. **Exclude par défaut Odoo** : `*.po`, `*.pot`, `*/tests/*`, `*/test_*`,
   `*.min.js`, `*.min.css`.
4. Un **dashboard flottant unique** (un seul raccourci, ex. on réutilise
   `<D-S-f>` / `<leader>sg`) qui affiche les filtres courants et permet, sans
   quitter :
   - `i` → éditer l'include (input texte type VSCode : `*.py,*.xml`)
   - `e` → éditer l'exclude
   - `p` / `x` / `j` / `s` → toggle preset Python / XML / JS+TS / SCSS
   - `a` → mode « tout » (désactive include, ignore .gitignore : `--no-ignore`)
   - `<CR>` → lance le grep avec ces filtres
5. Moteur : **telescope + `live-grep-args`** (déjà installé) en passant les globs
   en `-g` à ripgrep, **scopé sur les sources Odoo détectées** (cwd + `odooXX` +
   `enterpriseXX.0`, logique déjà présente dans `<D-S-f>`).

- [?] **Décision moteur** : on reste sur telescope (cohérent avec le thème et
  l'existant) **ou** on bascule sur `fzf-lua` si la fiabilité « fichier pas
  trouvé » ne s'améliore pas. → trancher après un premier essai telescope.
- [ ] Diagnostiquer le « fichier pas trouvé » : vérifier `.gitignore` / `--hidden`
  / `follow` symlinks sur les pickers `find_files` et `live_grep`.
- [ ] Module `search.lua` : état + persistance JSON + presets + exclude Odoo.
- [ ] Dashboard flottant include/exclude + toggles.
- [ ] Brancher sur `<D-S-f>` (Cmd+Shift+F) et `<leader>sg`.

---

## 2. 🗂️ Explorateur & navigation « retour »

- [x] **`<leader>e` neo-tree** — ✅ la vraie cause des « 2-3 essais » était le
  `<space>` mappé sur `toggle_node` par neo-tree, qui se déclenchait quand la
  séquence leader expirait. Neutralisé (`['<space>'] = 'none'`). Le pseudo-toggle
  fonctionne (reveal depuis l'extérieur, close_window depuis l'arbre).
  Numéros de ligne retirés de neo-tree au passage (statuscolumn → fonction Lua).
  [?] Reste optionnel : un vrai toggle ouvre↔ferme strict sur une seule touche si
  le pseudo-toggle ne suffit pas à l'usage.
- [ ] **Retour après ouverture d'un fichier des sources Odoo** : `<C-o>` (jumplist)
  est mal vécu. Propositions :
  - `<leader>bb` = buffer précédent (`:b#`) — retour immédiat au fichier d'avant.
  - Clarifier jumplist : `<C-o>`/`<C-i>` reculer/avancer, le documenter dans le
    cheatsheet.
  - **harpoon** (voir §8) pour épingler model.py / views.xml / __manifest__ et
    sauter entre eux sans réfléchir.

---

## 3. 🔗 Références (pas clean)

- [ ] Aujourd'hui `grr` → telescope `lsp_references`. Proposition :
  - Mapper sur **`<leader>gr`** (= `space g r` de VSCode, priorité VSCode).
  - Passer à **`trouble.nvim`** pour références/diagnostics/quickfix : panneau
    bas persistant, navigable, bien plus lisible qu'une popup telescope.

---

## 4. ✳️ Multi-curseur (`space n`) — FAIT

- [x] ~~multicursor.nvim~~ → **abandonné** : il réplique les éditions à la SORTIE
  d'insertion (`InsertLeave`), pas en temps réel. Rédhibitoire (besoin du feeling
  VSCode live).
- [x] **`mg979/vim-visual-multi`** installé → édition LIVE sur tous les curseurs.
  Mappings (priorité VSCode) : `<leader>n` = mot sous curseur + occurrence
  suivante (Cmd+D), `<leader>A` = toutes, `<leader>q` = sauter, `<leader>Q` =
  retirer un curseur. Édition : `a`/`i`/`c`/`A`/`I` en temps réel, `<Esc>` sort.
  Spec : `custom/plugins/visual-multi.lua`. `:Lazy sync` pour désinstaller l'ancien.
  Édition après sélection : **`a`** = après le mot (le cas courant), `i` = avant,
  `c` = remplacer le mot. ⚠️ `A`/`I` = fin/début de LIGNE (Vim standard), pas le mot.

---

## 5. ⌨️ Harmonisation raccourcis (priorité VSCode)

On ajoute les bindings VSCode **en plus** des défauts kickstart (`gr*`), pour
coller à la mémoire musculaire. Source : `keybindings.json`.

- [ ] `<leader>gd` → définition (déjà `<leader>g`, on confirme/aligne)
- [ ] `<leader>gr` → références (cf §3)
- [ ] `<leader>gi` → implémentation
- [ ] `<leader>gh` → hover (⚠️ collision : `<leader>gh` = git file history
  aujourd'hui → arbitrer, p.ex. hover sur `<leader>k`)
- [ ] `<leader>ca` → code action
- [ ] `<leader>cr` → rename
- [ ] `<leader>cs` → symboles document
- [ ] `<leader>bd` → fermer le buffer
- [ ] `<leader>,` → éditeurs récents (telescope oldfiles/buffers)
- [x] **`<leader><leader>`** : DÉCIDÉ → on **garde buffers** (option B). Le file
  finder reste sur `Cmd+P`/`<C-p>` (seul utilisé en pratique), pas de doublon.
- [ ] **`shift+j` / `shift+k` en Visual** = déplacer les lignes (tu l'avais en
  VSCode, absent ici). Idiome vim `:m '>+1`/`:m '<-2` + reindent.

---

## 6. 🐳 Intégration Odoo (docker-compose + URL)

⚠️ **Le module `purecraft` ne fonctionne pas** — c'est un portage encore non
fonctionnel de l'extension VSCode. On ne capitalise donc PAS dessus tel quel : à
décider si on le **répare**, on le **réécrit en petit**, ou on repart d'un module
minimal pour juste ce dont on a besoin ici.

- [?] **Décision purecraft** : réparer / réécrire minimal / abandonner ?
  Le code source reste une **référence d'algorithme** réutilisable
  (`docker.lua::find_compose_file`, parsing services/ports, `projects.lua` URL
  via host/port + `vim.ui.open`) même si le module ne tourne pas.
- [ ] **`<leader>oc`** (Odoo Compose) → ouvrir le `docker-compose.yml` détecté
  (logique de détection à extraire/réimplémenter proprement).
- [ ] **`<leader>oo`** (Odoo Open) → ouvrir l'URL Odoo dans le navigateur, port
  **auto-détecté** depuis le compose (ex. `localhost:8092`).
- [?] Bonus : afficher version Odoo + port détectés dans la **statusline**.
- [?] Bonus : `<leader>ol` → logs du container Odoo (docker compose logs -f).

---

## 7. 🤖 Claude — sélection → prompt

Déjà : split Claude OK, `<leader>cc` toggle ClaudeCode, `<leader>y` copie
code+chemin+diagnostics dans le presse-papier.

- [ ] **Sélection visuelle + une touche → ouvre Claude avec le code déjà collé
  dans des ``` ``` ```** (chemin + n° de lignes en en-tête, façon `<leader>y`
  mais envoyé directement dans le buffer ClaudeCode au lieu du presse-papier).
  Mapping proposé : `<leader>cs` (mais collision §5 symboles → arbitrer, p.ex.
  `<leader>ai` ou `<leader>cy`).

---

## 8. 🎯 Curseur dynamique & confort visuel (force de proposition)

- [ ] **Curseur « trail » / non téléporté** : `sphamba/smear-cursor.nvim` (traînée
  du curseur) **ou** `karb94/neoscroll.nvim` (scroll fluide) **ou**
  `echasnovski/mini.animate` (anime curseur + scroll, déjà dans l'écosystème
  mini que tu utilises → mon préféré ici).
- [ ] **`flash.nvim`** : saut éclair (`s` + 2 lettres) n'importe où à l'écran.
  Game-changer pour remplacer les `10j`/`fx` à répétition.
- [ ] **`nvim-treesitter-context`** : en-tête sticky de la fonction/classe en haut
  d'écran — précieux sur les longues méthodes Odoo / gros XML.
- [ ] **harpoon** (`ThePrimeagen/harpoon`) : épingler 4-5 fichiers et sauter
  instantanément (`<leader>1..4`) — taillé pour le combo model/view/manifest.
- [ ] **`vim-illuminate`** : surligne les autres occurrences du symbole sous le
  curseur (comme VSCode).
- [?] Vérifier que `custom/plugins/sessions.lua` **auto-restaure** la session à
  l'ouverture (lié à la persistance demandée pour la recherche).

---

## 9. ⇥ Indentation Tab / Shift-Tab (« un truc cloche »)

État actuel (init.lua:222-225) : `<S-Tab>` = `<<` (normal), `<C-d>` (insert),
`<gv` (visual). Pas de `Tab` symétrique pour indenter, et `Tab` en normal = saut
jumplist (`<C-i>`), donc le remapper est destructeur.

- [ ] **Diagnostiquer ensemble** le comportement exact qui gêne (insert ? visual ?).
- [ ] Rendre au minimum le **Visual symétrique** : `Tab` = `>gv`, `<S-Tab>` = `<gv`
  (indente/désindente en gardant la sélection). Laisser normal/insert sains.
- [ ] Vérifier l'interaction avec `vim-sleuth` (détection auto tabstop/shiftwidth)
  qui peut donner une sensation incohérente selon le fichier.

---

## 10. 💡 Idées bonus / à discuter

- [?] **which-key** : déclarer les groupes `<leader>o` (Odoo), `<leader>c` (code),
  `<leader>g` (goto/git) pour que les menus soient lisibles.
- [?] **Statusline** : afficher branche git + version Odoo + container actif.
- [?] **`gitsigns` blame** déjà mappé (`<leader>tb`/`<leader>hb`) — OK.
- [?] **Format on save** (conform) actif mais peu de formatters configurés
  (`python` commenté) → ajouter black/isort/ruff pour Odoo ?
- [?] Cheatsheet `<leader>?` : la régénérer une fois tous les nouveaux mappings posés.

---

## ✅ Acquis à NE PAS casser

- Thème **ayu-light** — rendu XML jugé excellent. On garde.
- Pont Kitty→Neovim CSI u (`<D-*>`) — cohérent et complet.
- Auto-save sur FocusLost/BufLeave.
- `<leader>id` (insère noqa/pylint/type:ignore selon la source).
- `<leader>y` (copie code+chemin+diagnostics).
- `<D-S-f>` détection version Odoo via Dockerfile (base de la recherche §1).

> ⚠️ Le module `purecraft` (docker / projects / todoo / rpc) **ne fonctionne
> pas** (portage VSCode incomplet) — ce n'est PAS un acquis. À traiter en §6.

---

## 11. 🎨 Réglages visuels divers (retours en cours d'usage)

- [x] **Numéros de ligne** : ✅ `LineNr` = `#8A9199`, `CursorLineNr` = orange ayu
  `#FA8D3E` + gras, alignement à droite via statuscolumn (plus de « retrait » sur
  la ligne courante), et colonne vide dans les buffers spéciaux.

---

## Ordre d'attaque proposé

1. **§0 quick wins** (5 min, sans risque) — nerd font, relativenumber, retrait oil.
2. **§2 fix neo-tree** + **§9 diag indentation** (irritants quotidiens rapides).
3. **§4 multi-curseur** (demande explicite, isolé).
4. **§1 recherche** (le gros chantier, on prend le temps).
5. **§6 Odoo URL/compose**, **§3 références**, **§5 harmonisation**, **§7 Claude**.
6. **§8 confort visuel** en finition.
