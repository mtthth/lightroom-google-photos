-- Rafales : détection et choix des cadres à retirer. Pur Lua, sans appel à Lightroom, pour pouvoir
-- être testé à part. L'interface est dans ReduireRafales.lua.
--
-- Un fichier est décrit par une table { chemin, t (secondes, heure de prise de vue), taille (octets),
-- raisons (protections trouvées par l'appelant : « note 3 », « collection « … » »…), photo }.
--
-- Cadre : les fichiers qui portent le même numéro à la même seconde dans le même dossier
-- (RAW + JPEG, copie « -2 », version retouchée) comptent pour un seul cadre.
-- Rafale : au moins MIN_CADRES cadres qui se suivent à ECART_SECONDES au plus, avec des numéros de
-- fichier voisins. Le catalogue ne garde que la seconde entière : l'ordre à l'intérieur d'une seconde
-- vient du numéro de fichier.
-- Blocs : une rafale de n cadres est découpée en ceil(n / ratio) blocs consécutifs de tailles presque
-- égales. Dans chaque bloc :
--   - les cadres protégés sont toujours gardés (« protégé ») ;
--   - parmi les autres, le plus net est gardé (« garder ») et les autres sont retirés (« retirer »).
-- Les protégés s'ajoutent donc au plus net : un cadre protégé ne tient pas lieu de gardé pour son bloc.
-- Un cadre est protégé s'il a au moins une raison (collection autre que les époques, note, drapeau,
-- libellé, retouches Lightroom, version retouchée dans un éditeur externe…).

local Doublons = require 'Doublons'
local Epoques = require 'Epoques'
local Noms = require 'Noms'
local Similitude = require 'Similitude'

local M = {}

-- Collection où « Réduire les rafales » rassemble les cadres à retirer. Elle sera vidée une fois les
-- cadres supprimés : elle ne peut donc pas servir de mémoire.
M.COLLECTION = 'Rafales à retirer'
-- Mot-clé (non exporté) posé sur toutes les photos des rafales traitées, gardées comme retirées : les
-- relances les ignorent, pour ne pas réduire une seconde fois des cadres déjà réduits. Pour retraiter
-- une rafale, il suffit d'ôter ce mot-clé de ses photos.
M.MOT_CLE = 'Rafale traitée'
M.RATIO = 4              -- un cadre gardé pour 4
M.ECART_SECONDES = 1     -- écart maximal entre deux cadres d'une rafale
M.ECART_NUMERO = 3       -- écart maximal entre deux numéros de fichier (des cadres ont pu être supprimés)
M.MIN_CADRES = 3

-- Ensembles ou collections de premier niveau qui ne protègent pas une photo : les époques sont
-- calculées automatiquement, les deux autres sont des corbeilles. Les albums Google, eux, protègent.
M.SANS_PROTECTION = { [Noms.ENSEMBLE_EPOQUES] = true, [Doublons.COLLECTION] = true, [M.COLLECTION] = true }

-- Formats que ImageMagick lit ; plus le rang est petit, plus on préfère le fichier (RAW + JPEG : le JPEG).
local FORMATS_MESURABLES = { jpg = 0, jpeg = 0, tif = 1, tiff = 1, png = 2, heic = 3 }

local function nomFichier(chemin)
  return chemin:match('[^/\\]+$') or chemin
end

local function dossierDe(chemin)
  return chemin:match('^(.*)[/\\][^/\\]*$') or ''
end

-- Numéro d'un nom de fichier : la dernière suite d'au moins 3 chiffres du nom débarrassé de ses
-- suffixes de copie et de retouche, ou -1. « DSCF4348-2.JPG » → 4348 ; « IMG-20260802-WA0003-Modifié-
-- 2026-08-02T22-37-43.jpg » → 3 (le compteur, pas la date) ; « PXL_20260815_171001000.jpg » → 171001000
-- (l'heure en millisecondes, qui distingue les cadres).
function M.numero(nom)
  local dernier = nil
  for suite in Doublons.nomDeBase(nom):gmatch('%d%d%d+') do dernier = suite end
  return tonumber(dernier) or -1
end

-- Regroupe les fichiers en cadres, dans l'ordre chronologique. Chaque cadre :
--   { t, numero, fichiers, nom (nom affiché), mesure (fichier à mesurer, ou nil) }.
function M.cadres(fichiers)
  local parCle, liste = {}, {}
  for _, f in ipairs(fichiers) do
    f.nom = nomFichier(f.chemin)
    f.derive = Similitude.nomRetouche(f.nom)
    local numero = M.numero(f.nom)
    local t = math.floor(f.t)
    -- Sans numéro, le nom sépare les cadres : des fichiers sans chiffres ne sont pas un même cadre.
    local cle = dossierDe(f.chemin):lower() .. '|' .. t .. '|' .. numero
      .. (numero < 0 and ('|' .. Doublons.nomDeBase(f.nom)) or '')
    local cadre = parCle[cle]
    if not cadre then
      cadre = { t = t, numero = numero, fichiers = {} }
      parCle[cle] = cadre
      liste[#liste + 1] = cadre
    end
    table.insert(cadre.fichiers, f)
  end

  for _, c in ipairs(liste) do
    -- Nom affiché : le fichier d'origine (ni retouche ni copie « -2 »), sans extension.
    local origine = nil
    for _, f in ipairs(c.fichiers) do
      if not f.derive and not f.nom:find('%-%d$') then origine = origine or f end
    end
    origine = origine or c.fichiers[1]
    c.nom = (origine.nom:gsub('%.[^%.]*$', ''))
    -- Fichier mesuré : un fichier ordinaire que ImageMagick sait lire, de préférence un JPEG.
    local meilleur, rang = nil, nil
    for _, f in ipairs(c.fichiers) do
      local r = FORMATS_MESURABLES[(f.nom:match('%.([^%.]*)$') or ''):lower()]
      if not f.derive and r and (not rang or r < rang or (r == rang and #f.nom < #meilleur.nom)) then
        meilleur, rang = f, r
      end
    end
    c.mesure = meilleur
  end

  table.sort(liste, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    if a.numero ~= b.numero then return a.numero < b.numero end
    return a.fichiers[1].chemin < b.fichiers[1].chemin
  end)
  return liste
end

-- Calcule les protections d'un cadre : cadre.raisons (liste sans doublon) et cadre.protege.
-- Un fichier à nom de retouche (« -Modifier », « DxO_… ») est une version voulue : il protège son cadre.
function M.proteger(cadre)
  local raisons, vues = {}, {}
  local function ajouter(raison)
    if not vues[raison] then
      vues[raison] = true
      raisons[#raisons + 1] = raison
    end
  end
  for _, f in ipairs(cadre.fichiers) do
    for _, raison in ipairs(f.raisons or {}) do ajouter(raison) end
    if f.derive then ajouter('version retouchée (éditeur externe)') end
  end
  cadre.raisons = raisons
  cadre.protege = #raisons > 0
end

local function adjacents(a, b)
  if b.t - a.t > M.ECART_SECONDES then return false end
  return a.numero < 0 or b.numero < 0 or a.numero >= 100000 or b.numero >= 100000
    or math.abs(b.numero - a.numero) <= M.ECART_NUMERO
end

-- Rafales d'une liste de cadres chronologique : listes d'au moins MIN_CADRES cadres.
function M.rafales(cadres)
  local resultat, courante = {}, {}
  for _, c in ipairs(cadres) do
    local precedent = courante[#courante]
    if precedent and adjacents(precedent, c) then
      courante[#courante + 1] = c
    else
      if #courante >= M.MIN_CADRES then resultat[#resultat + 1] = courante end
      courante = { c }
    end
  end
  if #courante >= M.MIN_CADRES then resultat[#resultat + 1] = courante end
  for i, r in ipairs(resultat) do r.numero = i end
  return resultat
end

-- Découpe une liste en n groupes contigus de tailles presque égales (n <= #liste).
function M.decouper(liste, n)
  local blocs, taille = {}, #liste
  for i = 1, n do
    local bloc = {}
    for j = math.floor((i - 1) * taille / n) + 1, math.floor(i * taille / n) do bloc[#bloc + 1] = liste[j] end
    blocs[i] = bloc
  end
  return blocs
end

-- Découpe chaque rafale en blocs (rafale.blocs). ratio : un cadre gardé pour `ratio` cadres.
function M.blocs(rafales, ratio)
  for _, rafale in ipairs(rafales) do
    rafale.blocs = M.decouper(rafale, math.max(1, math.ceil(#rafale / (ratio or M.RATIO))))
  end
end

-- Cadres dont il faut mesurer la netteté : les cadres non protégés des blocs qui en comptent au moins
-- deux (un cadre seul dans son bloc est gardé sans comparaison). À appeler après proteger et blocs.
function M.cadresAMesurer(rafales)
  local liste = {}
  for _, rafale in ipairs(rafales) do
    for _, bloc in ipairs(rafale.blocs) do
      local libres = {}
      for _, c in ipairs(bloc) do
        if not c.protege then libres[#libres + 1] = c end
      end
      if #libres >= 2 then
        for _, c in ipairs(libres) do
          if c.mesure then liste[#liste + 1] = c end
        end
      end
    end
  end
  return liste
end

-- Décide du sort de chaque cadre : cadre.decision = 'protégé', 'garder' ou 'retirer' (et cadre.pourquoi
-- pour les cadres retirés). À appeler après blocs, proteger et la mesure de netteté (cadre.nettete).
function M.decider(rafales)
  for _, rafale in ipairs(rafales) do
    for _, bloc in ipairs(rafale.blocs) do
      local libres, meilleur = {}, nil
      for _, c in ipairs(bloc) do
        if c.protege then
          c.decision = 'protégé'
        else
          libres[#libres + 1] = c
          -- Strictement plus net : à netteté égale (ou inconnue), le premier cadre du bloc l'emporte.
          if not meilleur or (c.nettete or -1) > (meilleur.nettete or -1) then meilleur = c end
        end
      end
      for _, c in ipairs(libres) do
        if c == meilleur then
          c.decision = 'garder'
        else
          c.decision = 'retirer'
          c.pourquoi = meilleur.nettete == nil and 'netteté non mesurée : le premier cadre du bloc est gardé'
            or ('moins net que ' .. meilleur.nom)
        end
      end
    end
  end
end

-- Comptes pour le bilan : rafales, cadres, protégés, gardés, retirés, fichiers et octets retirés.
function M.bilan(rafales)
  local b = { rafales = #rafales, cadres = 0, proteges = 0, gardes = 0, retires = 0, fichiersRetires = 0, octetsRetires = 0 }
  for _, rafale in ipairs(rafales) do
    for _, c in ipairs(rafale) do
      b.cadres = b.cadres + 1
      if c.decision == 'protégé' then
        b.proteges = b.proteges + 1
      elseif c.decision == 'garder' then
        b.gardes = b.gardes + 1
      elseif c.decision == 'retirer' then
        b.retires = b.retires + 1
        for _, f in ipairs(c.fichiers) do
          b.fichiersRetires = b.fichiersRetires + 1
          b.octetsRetires = b.octetsRetires + (f.taille or 0)
        end
      end
    end
  end
  return b
end

-- Photos (tous les fichiers) des cadres à retirer.
function M.photosARetirer(rafales)
  local photos = {}
  for _, rafale in ipairs(rafales) do
    for _, c in ipairs(rafale) do
      if c.decision == 'retirer' then
        for _, f in ipairs(c.fichiers) do
          if f.photo then photos[#photos + 1] = f.photo end
        end
      end
    end
  end
  return photos
end

-- Photos (tous les fichiers) de tous les cadres des rafales : celles qui reçoivent le mot-clé MOT_CLE.
function M.photosTraitees(rafales)
  local photos = {}
  for _, rafale in ipairs(rafales) do
    for _, c in ipairs(rafale) do
      for _, f in ipairs(c.fichiers) do
        if f.photo then photos[#photos + 1] = f.photo end
      end
    end
  end
  return photos
end

-- Lignes du rapport : une par cadre.
function M.lignesRapport(rafales)
  local lignes = { { 'rafale', 'bloc', 'cadre', 'heure', 'decision', 'nettete', 'raison', 'fichiers' } }
  for _, rafale in ipairs(rafales) do
    for b, bloc in ipairs(rafale.blocs) do
      for _, c in ipairs(bloc) do
        local chemins = {}
        for i, f in ipairs(c.fichiers) do chemins[i] = f.chemin end
        lignes[#lignes + 1] = {
          rafale.numero, b, c.nom, Epoques.texte(Epoques.depuisLightroom(c.t, 0)):sub(12),
          c.decision or '',
          -- Deux décimales : deux cadres voisins peuvent différer de moins d'un dixième.
          c.nettete and (string.format('%.2f', c.nettete):gsub('%.', ',')) or '',
          c.decision == 'protégé' and table.concat(c.raisons, ', ') or (c.pourquoi or ''),
          table.concat(chemins, ' | '),
        }
      end
    end
  end
  return lignes
end

return M
