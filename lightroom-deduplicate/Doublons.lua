-- Doublons du catalogue : regroupement des copies et choix de celle à garder.
-- Pur Lua, sans appel à Lightroom, pour pouvoir être testé à part.
--
-- Une copie est décrite par une table :
--   { id, chemin, date (secondes Lightroom, ou nil), retouchee, virtuelles (nombre de copies
--     virtuelles), publiee, annotee (note, drapeau, libellé, mots-clés, titre ou légende),
--     empreinte (image, voir Empreintes.lua), pixels et octets (taille de l'image et du fichier,
--     quand on les connaît) }
--
-- Copie gardée, chaque critère ne servant qu'à départager les ex aequo du précédent :
--   1. la plus grande image (pixels), puis, à dimensions égales, le fichier le plus lourd
--      (copie réduite ou recompressée : on garde la meilleure) ;
--   2. celle qui a des retouches (deux séries de retouches ne se fusionnent pas) ;
--   3. celle qui a des copies virtuelles (elles disparaîtraient avec elle) ;
--   4. le dossier le mieux rangé (voir rangDossier) ;
--   5. le dossier dont la date est la plus proche de la prise de vue ;
--   6. le dossier le plus profond (« 2024-10/2024-10-13 » plutôt que « 2024-10-13 ») ;
--   7. le nom sans suffixe de copie (« DSCF5219 » plutôt que « DSCF5219-2 ») ;
--   8. celle qui a déjà des notes, mots-clés… ;
--   9. la première importée (identifiant le plus petit).
-- Un groupe est laissé tel quel (« à vérifier ») quand plusieurs copies sont retouchées, quand
-- plusieurs ont des copies virtuelles, quand une copie à retirer est publiée, ou quand une copie
-- à retirer est retouchée ou a des copies virtuelles (c'est la copie réduite qui porte le travail).

local Epoques = require 'Epoques'
local Similitude = require 'Similitude'

local M = {}

-- Collection où la fusion rassemble les copies en trop, en attendant que tu les retires du catalogue.
M.COLLECTION = 'Doublons à retirer'

-- Champs de texte recopiés sur la copie gardée quand elle n'a rien dans le champ (clés de
-- getFormattedMetadata et de setRawMetadata), avec leur nom affiché.
M.CHAMPS_TEXTE = { 'label', 'title', 'caption', 'headline', 'creator', 'copyright', 'location', 'city',
  'stateProvince', 'country', 'isoCountryCode', 'personShown', 'event' }
M.NOMS_CHAMPS = {
  label = 'Libellé de couleur', title = 'Titre', caption = 'Légende', headline = 'Titre court', creator = 'Auteur',
  copyright = 'Copyright', location = 'Lieu', city = 'Ville', stateProvince = 'Région', country = 'Pays',
  isoCountryCode = 'Code du pays', personShown = 'Personnes', event = 'Événement',
}

local INCONNU = math.huge

-- Nom de fichier sans extension ni suffixes de copie ou de retouche, en minuscules :
-- « IMG_6527-2.JPG », « P1210938 (2).jpg », « DSCF5219-2-Modifier.JPG » → « img_6527 »,
-- « p1210938 », « dscf5219 ». Sert à retrouver les copies d'un même fichier : seule l'image
-- (voir Empreintes.lua) dit ensuite si ce sont bien les mêmes.
local SUFFIXES = { '%s*%(%d+%)$', '%-%d%d?$', '%-copie$', '%s%-%scopie$' }
-- Les marqueurs de retouche (voir Similitude.lua) et tout ce qui les suit : « -modifié », « -modifier-2(1) »,
-- « -modifié-2026-08-02t22-37-43 », « _filtered2 », « -20260821-dxo_deepprime xd3 »…
for _, marqueur in ipairs(Similitude.MARQUEURS_RETOUCHE) do
  SUFFIXES[#SUFFIXES + 1] = marqueur .. '.*$'
end

function M.nomDeBase(nom)
  local fichier = nom:match('[^/\\]+$') or nom
  local base = fichier:lower():gsub('%.[^%.]*$', '')
  for _ = 1, 6 do
    local avant = base
    for _, motif in ipairs(SUFFIXES) do
      local sans = base:gsub(motif, '')
      if sans ~= '' then base = sans end
    end
    if base == avant then break end
  end
  return base
end

-- Nombre de caractères de suffixe (copie, retouche) du nom : 0 pour le fichier d'origine.
function M.longueurSuffixe(nom)
  local fichier = (nom:match('[^/\\]+$') or nom):lower():gsub('%.[^%.]*$', '')
  return #fichier - #M.nomDeBase(nom)
end

local function separer(chemin)
  local parties = {}
  for partie in chemin:gmatch('[^/\\]+') do parties[#parties + 1] = partie end
  return parties
end

-- Rang du dossier d'une copie : plus il est petit, mieux la copie est rangée.
--   1 dossier nommé (« 180818. Vacances à Andernos », « LNE »…) ;
--   2 dossier daté (« 2024-10-13 », « 2024-10 ») ;
--   3 dossier d'année ou de décennie (« 2021 », « 202x ») ;
--   4 « Désordre », « mal rangées » ;
--   5 photos téléchargées depuis Google Photos (dossiers « …-manquantes »).
function M.rangDossier(chemin)
  local bas = chemin:lower()
  if bas:find('manquantes', 1, true) then return 5 end
  if bas:find('désordre', 1, true) or bas:find('mal rang', 1, true) then return 4 end
  local parties = separer(bas)
  local dossier = parties[#parties - 1] or ''
  if dossier:match('^%d%d%d%d$') or dossier:match('^%d%d%dx$') or #parties < 3 then return 3 end
  if dossier:match('^%d%d%d%d%-%d%d$') or dossier:match('^%d%d%d%d%-%d%d%-%d%d$') then return 2 end
  return 1
end

-- Date d'un nom de dossier (« 180818. Vacances », « 2024-10-13 », « 2024-10 »), en secondes
-- depuis 1970, ou nil.
local function dateNom(nom)
  local a, m, j = nom:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
  if not a then
    a, m = nom:match('^(%d%d%d%d)%-(%d%d)$')
    j = a and '01'
  end
  if not a then
    local aa
    aa, m, j = nom:match('^(%d%d)(%d%d)(%d%d)[%.%s]')
    if aa then a = tostring(tonumber(aa) <= 30 and 2000 + tonumber(aa) or 1900 + tonumber(aa)) end
  end
  if not a or tonumber(m) < 1 or tonumber(m) > 12 or tonumber(j) < 1 or tonumber(j) > 31 then return nil end
  return Epoques.secondes(string.format('%s-%s-%s 12:00:00', a, m, j))
end

-- Écart en secondes entre la prise de vue et la date du dossier daté le plus proche de la
-- photo (le dossier lui-même, sinon ses parents).
function M.ecartDossier(chemin, date)
  if not date then return INCONNU end
  local prise = Epoques.depuisLightroom(date, 0)
  local parties = separer(chemin)
  for i = #parties - 1, 1, -1 do
    local d = dateNom(parties[i])
    if d then return math.abs(prise - d) end
  end
  return INCONNU
end

local function meilleure(a, b)
  if a.pixels ~= b.pixels then return a.pixels > b.pixels end
  if a.octetsImage ~= b.octetsImage then return a.octetsImage > b.octetsImage end
  if a.retouchee ~= b.retouchee then return a.retouchee end
  if a.avecVirtuelles ~= b.avecVirtuelles then return a.avecVirtuelles end
  if a.rang ~= b.rang then return a.rang < b.rang end
  if a.ecart ~= b.ecart then return a.ecart < b.ecart end
  if a.profondeur ~= b.profondeur then return a.profondeur > b.profondeur end
  if a.suffixe ~= b.suffixe then return a.suffixe < b.suffixe end
  if a.annotee ~= b.annotee then return a.annotee end
  return a.copie.id < b.copie.id
end

-- Premier critère (dans l'ordre de `meilleure`) qui place a, la copie gardée, devant b, la suivante.
local function raisonDuChoix(a, b)
  if a.pixels ~= b.pixels then return 'la plus grande image' end
  if a.octetsImage ~= b.octetsImage then return 'le fichier le plus lourd (mêmes dimensions)' end
  if a.retouchee ~= b.retouchee then return 'retouchée dans Lightroom' end
  if a.avecVirtuelles ~= b.avecVirtuelles then return 'a des copies virtuelles' end
  if a.rang ~= b.rang then return 'dossier mieux rangé' end
  if a.ecart ~= b.ecart then return 'dossier dont la date correspond le mieux à la prise de vue' end
  if a.profondeur ~= b.profondeur then return 'dossier plus détaillé' end
  if a.suffixe ~= b.suffixe then return 'nom sans suffixe de copie' end
  if a.annotee ~= b.annotee then return 'déjà annotée (note, mots-clés, textes…)' end
  return 'importée la première'
end

-- copies : les copies d'un même fichier (deux au moins).
-- Renvoie { garde = copie, retirees = { copies… }, aVerifier = raison ou nil, pourquoi = raison du choix
-- de la copie gardée, memeImage = vrai si toutes les copies ont la même image }.
function M.decider(copies)
  -- Taille du fichier le plus lourd de chaque image : des copies de la même image (métadonnées
  -- intégrées différentes) ne se départagent pas par leur poids.
  local octetsParImage = {}
  for _, c in ipairs(copies) do
    local cle = c.empreinte or c
    octetsParImage[cle] = math.max(octetsParImage[cle] or 0, c.octets or 0)
  end
  local liste = {}
  for i, c in ipairs(copies) do
    liste[i] = {
      copie = c,
      pixels = c.pixels or 0,
      octetsImage = octetsParImage[c.empreinte or c],
      retouchee = c.retouchee and true or false,
      avecVirtuelles = (c.virtuelles or 0) > 0,
      rang = M.rangDossier(c.chemin),
      ecart = M.ecartDossier(c.chemin, c.date),
      profondeur = #separer(c.chemin),
      suffixe = M.longueurSuffixe(c.chemin),
      annotee = c.annotee and true or false,
    }
  end
  table.sort(liste, meilleure)

  local nbRetouchees, nbVirtuelles, publiee, travailPerdu = 0, 0, false, false
  local retirees = {}
  for i, e in ipairs(liste) do
    if e.retouchee then nbRetouchees = nbRetouchees + 1 end
    if e.avecVirtuelles then nbVirtuelles = nbVirtuelles + 1 end
    if i > 1 then
      retirees[#retirees + 1] = e.copie
      if e.copie.publiee then publiee = true end
      if e.retouchee or e.avecVirtuelles then travailPerdu = true end
    end
  end
  local raison = nil
  if nbRetouchees > 1 then
    raison = 'plusieurs copies retouchées'
  elseif nbVirtuelles > 1 then
    raison = 'plusieurs copies ont des copies virtuelles'
  elseif publiee then
    raison = 'une copie à retirer est publiée'
  elseif travailPerdu then
    raison = 'une copie à retirer est retouchée ou a des copies virtuelles'
  end
  local memeImage = true
  for _, c in ipairs(copies) do
    if c.empreinte ~= copies[1].empreinte then memeImage = false end
  end
  return {
    garde = liste[1].copie, retirees = retirees, aVerifier = raison, memeImage = memeImage,
    pourquoi = raisonDuChoix(liste[1], liste[2]),
  }
end

-- Proposition de la fusion manuelle : résolution, note, simplicité du nom. Le poids ne sert qu'à
-- départager les égalités : il peut varier à cause des métadonnées sans améliorer l'image.
-- Trie les copies sur place et renvoie vrai si toutes les résolutions sont connues.
function M.classerManuellement(copies)
  local parResolution = true
  for _, c in ipairs(copies) do
    if not c.pixels or c.pixels <= 0 then parResolution = false end
  end
  table.sort(copies, function(a, b)
    if parResolution and a.pixels ~= b.pixels then return a.pixels > b.pixels end
    if (a.note or 0) ~= (b.note or 0) then return (a.note or 0) > (b.note or 0) end
    local suffixeA, suffixeB = M.longueurSuffixe(a.chemin), M.longueurSuffixe(b.chemin)
    if suffixeA ~= suffixeB then return suffixeA < suffixeB end
    local nomA = (a.chemin:match('[^/\\]+$') or a.chemin):gsub('%.[^%.]*$', '')
    local nomB = (b.chemin:match('[^/\\]+$') or b.chemin):gsub('%.[^%.]*$', '')
    if #nomA ~= #nomB then return #nomA < #nomB end
    if (a.octets or 0) ~= (b.octets or 0) then return (a.octets or 0) > (b.octets or 0) end
    local rangA, rangB = M.rangDossier(a.chemin), M.rangDossier(b.chemin)
    if rangA ~= rangB then return rangA < rangB end
    return a.id < b.id
  end)
  return parResolution
end

-- Ce que la fusion d'un groupe change, calculé une fois pour le rapport et pour l'application : la copie
-- gardée prend la place des copies retirées dans leurs collections, et récupère ce qui lui manque.
-- decision : résultat de decider ; chaque copie porte, quand elle est lue dans Lightroom :
--   collections = { { id, nom, dynamique, exclue, objet }… }   (exclue : une corbeille, jamais recopiée)
--   motsCles = { { nom, objet }… }, note, drapeau (-1 = rejetée, 1 = retenue), gps, textes = { clé = texte }.
-- Les collections dynamiques se recalculent seules : elles ne sont pas touchées.
-- Renvoie { collections (que la gardée rejoint), collectionsFinales (toutes ses collections ordinaires après fusion),
--           corbeillesGardee (collections de retrait dont la gardée doit sortir),
--           quittees = { { collection, copie }… } (les retirées en sortent),
--           motsCles (à ajouter), note, drapeau, gps (à poser, ou nil), textes = { { cle, valeur }… } }.
function M.effets(decision)
  local garde = decision.garde
  local e = { collections = {}, collectionsFinales = {}, corbeillesGardee = {}, quittees = {}, motsCles = {}, textes = {} }

  local dedans = {}
  for _, col in ipairs(garde.collections or {}) do
    if not dedans[col.id] and col.exclue and not col.dynamique then
      e.corbeillesGardee[#e.corbeillesGardee + 1] = col
    end
    if not dedans[col.id] and not col.dynamique and not col.exclue then
      e.collectionsFinales[#e.collectionsFinales + 1] = col
    end
    dedans[col.id] = true
  end
  local motsCles = {}
  for _, mot in ipairs(garde.motsCles or {}) do motsCles[mot.nom] = true end
  local note, drapeau, gps = garde.note or 0, garde.drapeau or 0, garde.gps
  local textes = {}
  for cle, valeur in pairs(garde.textes or {}) do textes[cle] = valeur end

  for _, c in ipairs(decision.retirees) do
    for _, col in ipairs(c.collections or {}) do
      if not col.dynamique and not col.exclue then
        e.quittees[#e.quittees + 1] = { collection = col, copie = c }
        if not dedans[col.id] then
          dedans[col.id] = true
          e.collections[#e.collections + 1] = col
          e.collectionsFinales[#e.collectionsFinales + 1] = col
        end
      end
    end
    for _, mot in ipairs(c.motsCles or {}) do
      if not motsCles[mot.nom] then
        motsCles[mot.nom] = true
        e.motsCles[#e.motsCles + 1] = mot
      end
    end
    if (c.note or 0) > note then
      note = c.note
      e.note = note
    end
    -- Conserve un choix explicite : une retenue prévaut sur un rejet, qui prévaut sur l'absence de drapeau.
    local drapeauCopie = c.drapeau or 0
    if (drapeauCopie == 1 and drapeau ~= 1) or (drapeauCopie == -1 and drapeau == 0) then
      drapeau = drapeauCopie
      e.drapeau = drapeauCopie
    end
    for _, cle in ipairs(M.CHAMPS_TEXTE) do
      local valeur = (c.textes or {})[cle] or ''
      if (textes[cle] or '') == '' and valeur ~= '' then
        textes[cle] = valeur
        e.textes[#e.textes + 1] = { cle = cle, valeur = valeur }
      end
    end
    if not gps and c.gps then
      gps = c.gps
      e.gps = c.gps
    end
  end
  return e
end

-- Regroupe les éléments de même clé ; renvoie les groupes d'au moins deux éléments, dans
-- l'ordre de première apparition. cle(element) peut renvoyer nil : l'élément est ignoré.
function M.grouper(elements, cle)
  local groupes, ordre = {}, {}
  for _, e in ipairs(elements) do
    local k = cle(e)
    if k ~= nil then
      if not groupes[k] then
        groupes[k] = {}
        ordre[#ordre + 1] = k
      end
      table.insert(groupes[k], e)
    end
  end
  local resultat = {}
  for _, k in ipairs(ordre) do
    if #groupes[k] > 1 then resultat[#resultat + 1] = groupes[k] end
  end
  return resultat
end

return M
