-- Lectures dans le catalogue partagées par les commandes du module.

local LrTasks = import 'LrTasks'

local M = {}

-- Identifiants (localIdentifier) des photos des collections de premier niveau portant l'un des
-- noms de `noms` (par exemple « Doublons à retirer » et « Rafales à retirer », où les commandes
-- mettent les photos en trop en attendant que tu les retires du catalogue), et leur nombre.
-- Une erreur de lecture donne une liste vide : la commande continue sans ignorer ces photos.
function M.photosDesCollections(catalogue, noms)
  local voulus = {}
  for _, nom in ipairs(noms) do voulus[nom] = true end
  local ids, nb = {}, 0
  LrTasks.pcall(function()
    for _, collection in ipairs(catalogue:getChildCollections()) do
      if voulus[collection:getName()] then
        for _, photo in ipairs(collection:getPhotos()) do
          if not ids[photo.localIdentifier] then nb = nb + 1 end
          ids[photo.localIdentifier] = true
        end
      end
    end
  end)
  return ids, nb
end

-- Identifiants des photos qui portent le mot-clé `nom` (à n'importe quel niveau de la hiérarchie des
-- mots-clés), et leur nombre. Une erreur de lecture, ou un mot-clé absent, donne une liste vide.
function M.photosAvecMotCle(catalogue, nom)
  local ids, nb = {}, 0
  LrTasks.pcall(function()
    local visites = 0
    local function chercher(motsCles)
      for _, motCle in ipairs(motsCles) do
        visites = visites + 1
        if motCle:getName() == nom then
          for _, photo in ipairs(motCle:getPhotos()) do
            if not ids[photo.localIdentifier] then nb = nb + 1 end
            ids[photo.localIdentifier] = true
          end
        end
        -- Garde-fou : une hiérarchie démesurée ne doit pas bloquer la commande.
        if visites < 50000 then chercher(motCle:getChildren()) end
      end
    end
    chercher(catalogue:getKeywords())
  end)
  return ids, nb
end

local NOMS_SOURCES = {
  kAllPhotos = 'Toutes les photos du catalogue', kPreviousImport = 'Dernier import',
  kQuickCollection = 'Collection rapide', kTargetCollection = 'Collection cible',
}

-- Nom de la source affichée dans la grille (dossier, collection…), ou nil.
local function nomSources(catalogue)
  local noms = {}
  LrTasks.pcall(function()
    for _, source in ipairs(catalogue:getActiveSources()) do
      noms[#noms + 1] = type(source) == 'table' and source:getName() or NOMS_SOURCES[source] or tostring(source)
    end
  end)
  return #noms > 0 and table.concat(noms, ' + ') or nil
end

-- Photos sur lesquelles travaille une commande de recherche : les photos sélectionnées s'il y en a au
-- moins deux, sinon toutes les photos affichées dans la grille (dossier, collection, tout le catalogue…).
-- Renvoie { photos, genre = 'selection' ou 'affichees', nom = nom de la source affichée (ou nil) }.
function M.portee(catalogue)
  local nom = nomSources(catalogue)
  -- getTargetPhoto vaut nil quand rien n'est sélectionné ; getTargetPhotos renverrait alors toute la grille.
  if catalogue:getTargetPhoto() then
    local selection = catalogue:getTargetPhotos()
    if #selection >= 2 then return { photos = selection, genre = 'selection', nom = nom } end
  end
  -- Une seule photo sélectionnée, ou aucune : getMultipleSelectedOrAllPhotos renvoie toute la grille.
  return { photos = catalogue:getMultipleSelectedOrAllPhotos(), genre = 'affichees', nom = nom }
end

-- Étiquette d'une collection pour l'affichage : « Ensemble / Collection » (ensemble de premier niveau
-- et collection elle-même ; les niveaux intermédiaires sont omis).
function M.etiquetteCollection(collection)
  local noms = { collection:getName() }
  local parent = collection:getParent()
  while parent do
    table.insert(noms, 1, parent:getName())
    parent = parent:getParent()
  end
  return #noms == 1 and noms[1] or (noms[1] .. ' / ' .. noms[#noms])
end

return M
