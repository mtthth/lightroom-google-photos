-- Calcul des « époques » : pour chaque album Google Photos, la période qu'il couvre dans le
-- catalogue Lightroom, et les périodes intercalaires entre deux albums.
-- Pur Lua, sans appel à Lightroom, pour pouvoir être testé à part.
--
-- Toutes les heures sont des secondes depuis 1970, en heure locale de prise de vue comptée
-- comme si c'était de l'UTC (c'est ce que donne Google Photos une fois le fuseau appliqué).
--
-- Une époque = les photos de l'album + toutes les photos du catalogue prises entre la première
-- et la dernière photo de l'album.
-- Une époque intercalaire = les photos du catalogue prises entre la fin d'une période couverte
-- par des albums et le début de la suivante.

local Noms = require 'Noms'

local M = {}

local SECONDES_COCOA = 978307200  -- 1970-01-01 → 2001-01-01, origine des dates de Lightroom
local JOUR = 24 * 3600

-- Nombre de jours depuis 1970-01-01 pour une date du calendrier grégorien.
local function joursDepuis1970(annee, mois, jour)
  if mois <= 2 then annee = annee - 1 end
  local ere = math.floor(annee / 400)
  local an = annee - ere * 400
  local jourAn = math.floor((153 * ((mois + 9) % 12) + 2) / 5) + jour - 1
  local jourEre = an * 365 + math.floor(an / 4) - math.floor(an / 100) + jourAn
  return ere * 146097 + jourEre - 719468
end

local function dateDepuisJours(jours)
  jours = jours + 719468
  local ere = math.floor(jours / 146097)
  local jourEre = jours - ere * 146097
  local an = math.floor((jourEre - math.floor(jourEre / 1460) + math.floor(jourEre / 36524) - math.floor(jourEre / 146096)) / 365)
  local annee = an + ere * 400
  local jourAn = jourEre - (365 * an + math.floor(an / 4) - math.floor(an / 100))
  local mp = math.floor((5 * jourAn + 2) / 153)
  local jour = jourAn - math.floor((153 * mp + 2) / 5) + 1
  local mois = mp < 10 and mp + 3 or mp - 9
  if mois <= 2 then annee = annee + 1 end
  return annee, mois, jour
end

-- « 2025-07-27 14:17:35 » → secondes depuis 1970 ; nil si le texte n'a pas ce format.
function M.secondes(texte)
  local a, mo, j, h, mi, s = (texte or ''):match('^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)$')
  if not a then return nil end
  return joursDepuis1970(tonumber(a), tonumber(mo), tonumber(j)) * JOUR
    + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
end

-- Secondes depuis 1970 → « 2025-07-27 14:17:35 », sans aucun fuseau horaire.
function M.texte(secondes)
  local reste = secondes - math.floor(secondes / JOUR) * JOUR
  return string.format('%s %02d:%02d:%02d', M.dateTexte(secondes),
    math.floor(reste / 3600), math.floor(reste % 3600 / 60), reste % 60)
end

-- Secondes depuis 1970 → « 2025-07-27 ».
function M.dateTexte(secondes)
  local a, mo, j = dateDepuisJours(math.floor(secondes / JOUR))
  return string.format('%04d-%02d-%02d', a, mo, j)
end

-- Heure de Lightroom (secondes depuis 2001) → échelle commune, une fois le décalage retiré.
function M.depuisLightroom(temps, decalage)
  return temps + SECONDES_COCOA - (decalage or 0)
end

-- Décalage entre les dates de Lightroom et celles de Google Photos, déduit de photos
-- reconnues. Chaque paire : { temps Lightroom, secondes Google }. Médiane arrondie au quart d'heure.
function M.decalage(paires)
  if #paires == 0 then return 0 end
  local ecarts = {}
  for i, p in ipairs(paires) do ecarts[i] = p[1] + SECONDES_COCOA - p[2] end
  table.sort(ecarts)
  local mediane = ecarts[math.floor((#ecarts + 1) / 2)]
  return math.floor(mediane / 900 + 0.5) * 900
end

-- Premier indice de `liste` (triée par t) dont t >= valeur.
local function premierIndice(liste, valeur)
  local bas, haut = 1, #liste + 1
  while bas < haut do
    local milieu = math.floor((bas + haut) / 2)
    if liste[milieu].t < valeur then bas = milieu + 1 else haut = milieu end
  end
  return bas
end

-- Photos de `liste` dont t est dans [debut, fin] (bornes incluses ou non).
local function photosEntre(liste, debut, fin, inclure)
  local resultat = {}
  local i = premierIndice(liste, debut)
  while liste[i] and (inclure and liste[i].t <= fin or (not inclure and liste[i].t < fin)) do
    if inclure or liste[i].t > debut then resultat[#resultat + 1] = liste[i].photo end
    i = i + 1
  end
  return resultat
end

-- albums : { { titre, nom, annee, debut, fin, photos = { LrPhoto… } }… }  (debut et fin en secondes ;
--   nom et annee viennent de Noms.analyser)
-- catalogue : { { t = secondes, photo = LrPhoto }… }  (toutes les photos datées du catalogue)
-- dureeMax : durée maximale d'un album pour compter comme époque, en secondes (nil : aucune limite)
-- Renvoie { { nom, annee, photos, debut, fin, intercalaire }… } dans l'ordre chronologique.
function M.calculer(albums, catalogue, dureeMax)
  table.sort(catalogue, function(a, b) return a.t < b.t end)

  local retenus = {}
  for _, album in ipairs(albums) do
    if album.debut and album.fin and (not dureeMax or album.fin - album.debut <= dureeMax) then
      retenus[#retenus + 1] = album
    end
  end
  table.sort(retenus, function(a, b)
    if a.debut ~= b.debut then return a.debut < b.debut end
    return a.titre < b.titre
  end)

  local epoques = {}
  local nomsPris = {}
  local function ajouter(epoque)
    local nom, n = epoque.nom, 1
    -- Lightroom ne distingue pas majuscules et minuscules dans les noms de collection.
    -- Les noms doivent être uniques dans un ensemble (ici, l'année).
    while nomsPris[epoque.annee .. '|' .. nom:lower()] do n = n + 1; nom = epoque.nom .. ' (' .. n .. ')' end
    nomsPris[epoque.annee .. '|' .. nom:lower()] = true
    epoque.nom = nom
    epoques[#epoques + 1] = epoque
  end

  -- Une époque par album.
  for _, album in ipairs(retenus) do
    local photos, vues = {}, {}
    for _, photo in ipairs(album.photos) do
      if not vues[photo] then vues[photo] = true; photos[#photos + 1] = photo end
    end
    for _, photo in ipairs(photosEntre(catalogue, album.debut, album.fin, true)) do
      if not vues[photo] then vues[photo] = true; photos[#photos + 1] = photo end
    end
    ajouter({
      nom = album.nom or album.titre, annee = album.annee or 'Sans date',
      photos = photos, debut = album.debut, fin = album.fin,
    })
  end

  -- Une époque intercalaire dans chaque trou entre deux périodes couvertes par des albums.
  local fin = nil
  for _, album in ipairs(retenus) do
    if fin and album.debut > fin then
      local photos = photosEntre(catalogue, fin, album.debut, false)
      if #photos > 0 then
        local nom = Noms.intercalaire(M.dateTexte(fin), M.dateTexte(album.debut))
        ajouter({ nom = nom.nom, annee = nom.annee, photos = photos, debut = fin, fin = album.debut, intercalaire = true })
      end
    end
    if not fin or album.fin > fin then fin = album.fin end
  end

  table.sort(epoques, function(a, b)
    if a.debut ~= b.debut then return a.debut < b.debut end
    return a.nom < b.nom
  end)
  return epoques
end

return M
