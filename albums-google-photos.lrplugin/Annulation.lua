-- L'historique texte est le miroir d'un état du catalogue inclus dans la même action Undo/Redo
-- que les collections, mots-clés et métadonnées. Aucun changement privé n'ajoute d'étape Ctrl+Z.
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local Historique = require 'Historique'

local M = {}
local ETAT = 'historiquePhotosV1'
local MIROIR = 'historiquePhotosMiroirV1'
local verrou, generation = false, 0

local function avecVerrou(f)
  while verrou do LrTasks.sleep(0.05) end
  verrou = true
  local ok, a, b = LrTasks.pcall(f)
  verrou = false
  if not ok then error(a, 0) end
  return a, b
end

local function prive(catalogue, attendu, miroirAttendu, etat, miroir, chemin)
  local actualise = false
  local statut = catalogue:withPrivateWriteAccessDo(function()
    -- Ctrl+Z peut avoir changé l'état pendant l'attente de l'accès au catalogue.
    if catalogue:getPropertyForPlugin(_PLUGIN, ETAT) ~= attendu
      or catalogue:getPropertyForPlugin(_PLUGIN, MIROIR) ~= miroirAttendu then return end
    -- L'écriture du fichier et son marqueur restent sous le même accès catalogue : un Ctrl+Z
    -- pendant l'attente ne peut pas faire passer notre ancienne écriture pour une édition externe.
    if chemin then Historique.ecrire(chemin, miroir) end
    if etat ~= nil then catalogue:setPropertyForPlugin(_PLUGIN, ETAT, etat) end
    catalogue:setPropertyForPlugin(_PLUGIN, MIROIR, miroir)
    actualise = true
  end, { timeout = 30 })
  if statut ~= 'executed' then error('Lightroom n’a pas accordé l’accès à la synchronisation de l’historique.', 0) end
  return actualise
end

local function synchroniser(catalogue, chemin)
  while true do
    local etat = catalogue:getPropertyForPlugin(_PLUGIN, ETAT)
    local miroir = catalogue:getPropertyForPlugin(_PLUGIN, MIROIR)
    local fichier = Historique.contenu(chemin)
    if etat == nil then
      if prive(catalogue, etat, miroir, fichier, fichier) then return fichier end
    elseif etat ~= miroir then
      -- Annulation, rétablissement, ou écriture interrompue après validation du catalogue.
      if prive(catalogue, etat, miroir, nil, etat, chemin) then return etat end
    elseif fichier ~= miroir then
      -- Modification volontaire du fichier texte : elle devient la base des actions suivantes.
      if prive(catalogue, etat, miroir, fichier, fichier) then return fichier end
    else
      return etat
    end
    -- Le snapshot a changé pendant l'attente : suivre la nouvelle valeur plutôt que l'écraser.
  end
end

function M.synchroniser(catalogue, chemin)
  return avecVerrou(function() return synchroniser(catalogue, chemin) end)
end

-- Un seul accès normal en écriture : un Ctrl+Z annule toute l'opération, quelle que soit sa taille.
-- Le résultat indique seulement si le miroir disque a pu être actualisé après la validation.
function M.action(catalogue, chemin, titre, options, modifier)
  return avecVerrou(function()
    Historique.preparer(chemin)
    synchroniser(catalogue, chemin)
    local statut = catalogue:withWriteAccessDo(titre, function(contexte)
      local apres = Historique.modifier(catalogue:getPropertyForPlugin(_PLUGIN, ETAT), options)
      modifier(contexte)
      catalogue:setPropertyForPlugin(_PLUGIN, ETAT, apres)
    end, { timeout = 120 })
    if statut ~= 'executed' then error('Lightroom n’a pas accordé l’accès à l’opération « ' .. titre .. ' ».', 0) end
    local ok, erreur = LrTasks.pcall(synchroniser, catalogue, chemin)
    if ok then return true end
    return false, erreur
  end)
end

-- Le SDK n'expose pas de notification Undo. Une lecture légère du champ suit Ctrl+Z et Rétablir ;
-- chaque commande synchronise aussi avant de lire l'historique, sans attendre ce passage périodique.
function M.demarrer(chemin)
  generation = generation + 1
  local courante = generation
  LrTasks.startAsyncTask(function()
    local derniereErreur
    while courante == generation do
      local ok, erreur = LrTasks.pcall(function()
        M.synchroniser(LrApplication.activeCatalog(), chemin)
      end)
      if not ok and tostring(erreur) ~= derniereErreur then
        derniereErreur = tostring(erreur)
        LrDialogs.message('Historique non synchronisé', derniereErreur
          .. '\nLe catalogue conserve l’état annulable. Le module réessaiera la synchronisation.', 'warning')
      elseif ok then
        derniereErreur = nil
      end
      LrTasks.sleep(0.5)
    end
  end)
end

function M.arreter()
  generation = generation + 1
end

return M
