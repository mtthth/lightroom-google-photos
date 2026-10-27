-- Fusionne en un seul groupe les photos explicitement sélectionnées par l'utilisateur.
-- Contrairement à « Fusionner les doublons », cette commande ne cherche pas à reconnaître les images :
-- la sélection elle-même désigne le groupe à fusionner.

local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Catalogue = require 'Catalogue'
local Doublons = require 'Doublons'
local Epoques = require 'Epoques'
local Historique = require 'Historique'

local COLLECTION_DOUBLONS = Doublons.COLLECTION
local CORBEILLES = { [Doublons.COLLECTION] = true, ['Rafales à retirer'] = true }
local DOSSIER_PROJET = LrPathUtils.parent(_PLUGIN.path)
local HISTORIQUE = LrPathUtils.child(DOSSIER_PROJET, 'photos-traitees.txt')

local function nomFichier(chemin)
  return chemin:match('[^/\\]+$') or chemin
end

local function cleChemin(chemin)
  return (chemin or ''):gsub('/', '\\'):lower()
end

local function selection(catalogue)
  if not catalogue:getTargetPhoto() then return {} end
  local vus, photos = {}, {}
  for _, photo in ipairs(catalogue:getTargetPhotos()) do
    if not vus[photo.localIdentifier] then
      vus[photo.localIdentifier] = true
      photos[#photos + 1] = photo
    end
  end
  return photos
end

local function lireCopies(catalogue, photos)
  local brutes = catalogue:batchGetRawMetadata(photos,
    { 'path', 'fileSize', 'dateTimeOriginal', 'isVirtualCopy', 'countVirtualCopies' })
  local copies = {}
  for _, photo in ipairs(photos) do
    local b = brutes[photo] or {}
    if b.isVirtualCopy then
      return nil, 'La sélection contient une copie virtuelle Lightroom. Elle doit rester rattachée à sa photo d’origine.'
    end
    if not b.path then
      return nil, 'Au moins une photo sélectionnée n’a pas de chemin de fichier lisible dans le catalogue.'
    end
    copies[#copies + 1] = {
      photo = photo, id = photo.localIdentifier, chemin = b.path, taille = b.fileSize or 0,
      octets = b.fileSize or 0, date = b.dateTimeOriginal, virtuelles = b.countVirtualCopies or 0,
      collections = {}, motsCles = {}, textes = {}, note = 0, drapeau = 0,
    }
  end
  return copies
end

local function lireCollections(photo)
  local r = {}
  for _, collection in ipairs(photo:getContainedCollections()) do
    r[#r + 1] = {
      objet = collection, id = collection.localIdentifier, nom = Catalogue.etiquetteCollection(collection),
      dynamique = collection:isSmartCollection(), exclue = CORBEILLES[collection:getName()] or false,
    }
  end
  return r
end

local function completerDetails(catalogue, copies, progression)
  progression:setCaption('Lecture des retouches et des métadonnées…')
  local ok, retouchees = LrTasks.pcall(function()
    return catalogue:findPhotos { searchDesc = { criteria = 'hasAdjustments', operation = 'isTrue', value = true } }
  end)
  if not ok then error('impossible de savoir quelles photos sont retouchées : ' .. tostring(retouchees), 0) end
  local estRetouchee = {}
  for _, photo in ipairs(retouchees) do estRetouchee[photo.localIdentifier] = true end

  local photos, parPhoto = {}, {}
  for _, c in ipairs(copies) do
    photos[#photos + 1] = c.photo
    parPhoto[c.photo] = c
  end
  local brutes = catalogue:batchGetRawMetadata(photos, { 'rating', 'pickStatus', 'keywords', 'gps' })
  local formatees = catalogue:batchGetFormattedMetadata(photos, Doublons.CHAMPS_TEXTE)
  for _, photo in ipairs(photos) do
    local c, b, f = parPhoto[photo], brutes[photo] or {}, formatees[photo] or {}
    c.retouchee = estRetouchee[c.id] or false
    c.note, c.drapeau, c.gps = b.rating or 0, b.pickStatus or 0, b.gps
    for _, mot in ipairs(b.keywords or {}) do c.motsCles[#c.motsCles + 1] = { objet = mot, nom = mot:getName() } end
    c.textes = {}
    for _, cle in ipairs(Doublons.CHAMPS_TEXTE) do c.textes[cle] = f[cle] or '' end
    c.publiee = #photo:getContainedPublishedCollections() > 0
    c.collections = lireCollections(photo)
  end
end

local function choisirGardee(contexte, copies)
  local f = LrView.osFactory()
  local proprietes = LrBinding.makePropertyTable(contexte)
  local choix = {}
  for _, c in ipairs(copies) do choix[#choix + 1] = { title = c.chemin, value = c.id } end
  proprietes.gardee = choix[1].value
  local reponse = LrDialogs.presentModalDialog {
    title = 'Fusion manuelle',
    contents = f:column {
      bind_to_object = proprietes,
      spacing = f:control_spacing(),
      f:static_text {
        title = string.format('%d photos sélectionnées seront considérées comme une seule photo, sans comparaison '
          .. 'de leur contenu. Choisis celle qui restera au catalogue. Les autres quitteront leurs collections '
          .. 'ordinaires et seront placées dans « %s » ; les collections dynamiques restent calculées par Lightroom.',
          #copies, COLLECTION_DOUBLONS),
        width = 560, height_in_lines = 4,
      },
      f:static_text { title = 'Photo à garder :' },
      f:popup_menu { value = LrView.bind('gardee'), items = choix, width_in_chars = 72 },
    },
    actionVerb = 'Continuer',
  }
  if reponse ~= 'ok' then return nil end
  for _, c in ipairs(copies) do if c.id == proprietes.gardee then return c end end
  return nil
end

local function validerRetirees(decision)
  local problemes = {}
  for _, c in ipairs(decision.retirees) do
    if c.retouchee then problemes[#problemes + 1] = nomFichier(c.chemin) .. ' est retouchée dans Lightroom' end
    if c.virtuelles > 0 then problemes[#problemes + 1] = nomFichier(c.chemin) .. ' a des copies virtuelles' end
    if c.publiee then problemes[#problemes + 1] = nomFichier(c.chemin) .. ' est dans une collection publiée' end
  end
  return problemes
end

local function appliquer(catalogue, decision)
  local corbeille
  catalogue:withWriteAccessDo('Créer la collection des doublons', function()
    corbeille = catalogue:createCollection(COLLECTION_DOUBLONS, nil, true)
  end, { timeout = 30 })
  catalogue:withWriteAccessDo('Fusion manuelle de photos', function()
    local e, garde = decision.effets, decision.garde.photo
    for _, col in ipairs(e.collections) do col.objet:addPhotos({ garde }) end
    for _, q in ipairs(e.quittees) do q.collection.objet:removePhotos({ q.copie.photo }) end
    for _, mot in ipairs(e.motsCles) do garde:addKeyword(mot.objet) end
    if e.note then garde:setRawMetadata('rating', e.note) end
    if e.drapeau then garde:setRawMetadata('pickStatus', e.drapeau) end
    for _, t in ipairs(e.textes) do garde:setRawMetadata(t.cle, t.valeur) end
    if e.gps then garde:setRawMetadata('gps', e.gps) end
    local retirees = {}
    for i, c in ipairs(decision.retirees) do retirees[i] = c.photo end
    corbeille:addPhotos(retirees)
  end, { timeout = 120 })

  local photos = {}
  for _, c in ipairs(decision.retirees) do
    -- L'historique porte sur les fichiers, pas les entrées du catalogue. Si Lightroom a deux fiches
    -- pour le même chemin, ne pas marquer le fichier gardé comme retiré.
    if cleChemin(c.chemin) ~= cleChemin(decision.garde.chemin) then
      photos[#photos + 1] = {
        chemin = c.chemin, fichier = nomFichier(c.chemin),
        date = c.date and Epoques.texte(Epoques.depuisLightroom(c.date, 0)) or '',
      }
    end
  end
  Historique.ajouter(HISTORIQUE, 'doublon', photos)
  return corbeille
end

LrTasks.startAsyncTask(function()
  LrFunctionContext.callWithContext('fusionManuelle', function(contexte)
    local etape = 'lecture de la sélection'
    local ok, erreur = LrTasks.pcall(function()
      local catalogue = LrApplication.activeCatalog()
      local photos = selection(catalogue)
      if #photos < 2 then
        LrDialogs.message('Fusion manuelle', 'Sélectionne au moins deux photos dans la grille ou la pellicule.', 'info')
        return
      end

      local progression = LrProgressScope { title = 'Fusion manuelle', functionContext = contexte }
      local copies, message = lireCopies(catalogue, photos)
      if not copies then progression:done(); LrDialogs.message('Fusion manuelle impossible', message, 'critical'); return end
      etape = 'lecture des métadonnées'
      completerDetails(catalogue, copies, progression)
      progression:done()

      local garde = choisirGardee(contexte, copies)
      if not garde then return end
      local retirees = {}
      for _, c in ipairs(copies) do if c ~= garde then retirees[#retirees + 1] = c end end
      local decision = { garde = garde, retirees = retirees }
      local problemes = validerRetirees(decision)
      if #problemes > 0 then
        LrDialogs.message('Fusion manuelle impossible', 'Pour éviter de perdre des données, la fusion est bloquée :\n\n'
          .. table.concat(problemes, '\n') .. '\n\nChoisis comme photo à garder une photo retouchée ou avec des copies virtuelles, '
          .. 'ou retire-la de la sélection. Les photos publiées doivent être retirées de leurs collections publiées avant la fusion.',
          'warning')
        return
      end
      decision.effets = Doublons.effets(decision)

      local lignes, destination = {}, {}
      for _, c in ipairs(retirees) do lignes[#lignes + 1] = '• ' .. c.chemin end
      for _, col in ipairs(decision.effets.collections) do destination[#destination + 1] = col.nom end
      local texteDestination = #destination > 0 and ('La photo gardée rejoindra les collections : '
        .. table.concat(destination, ', ') .. '.') or 'Aucune nouvelle collection ne sera ajoutée à la photo gardée.'
      local messageConfirmation = 'Photo gardée :\n' .. garde.chemin .. '\n\nPhotos qui seront mises dans « '
        .. COLLECTION_DOUBLONS .. ' » :\n' .. table.concat(lignes, '\n') .. '\n\n' .. texteDestination
        .. '\nLes albums et collections ordinaires seront réunis sur la photo gardée. Les métadonnées manquantes '
        .. 'seront fusionnées et les fichiers retirés mémorisés dans photos-traitees.txt.'
      if LrDialogs.confirm('Confirmer la fusion manuelle ?', messageConfirmation, 'Fusionner', 'Annuler') ~= 'ok' then return end

      etape = 'application de la fusion'
      local corbeille = appliquer(catalogue, decision)
      LrTasks.pcall(function() catalogue:setActiveSources({ corbeille }) end)
      LrDialogs.message('Fusion manuelle terminée', string.format(
        '%d photos fusionnées. La photo gardée est dans « %s » ; les %d autres sont dans « %s » et dans photos-traitees.txt.',
        #copies, nomFichier(garde.chemin), #retirees, COLLECTION_DOUBLONS), 'info')
    end)
    if not ok then
      LrDialogs.message('Erreur pendant la fusion manuelle', string.format('Étape : %s\n%s', etape, tostring(erreur)), 'critical')
    end
  end)
end)
