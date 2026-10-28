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
local Annulation = require 'Annulation'
local Doublons = require 'Doublons'
local Epoques = require 'Epoques'
local Historique = require 'Historique'
local Noms = require 'Noms'

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
    { 'path', 'fileSize', 'dateTimeOriginal', 'isVirtualCopy', 'masterPhoto', 'countVirtualCopies', 'width', 'height', 'dimensions' })
  local copies = {}
  for _, photo in ipairs(photos) do
    local b = brutes[photo] or {}
    if not b.path then
      return nil, 'Au moins une photo sélectionnée n’a pas de chemin de fichier lisible dans le catalogue.'
    end
    local dimensions = type(b.dimensions) == 'table' and b.dimensions or {}
    local largeur, hauteur = tonumber(b.width or dimensions.width), tonumber(b.height or dimensions.height)
    copies[#copies + 1] = {
      photo = photo, id = photo.localIdentifier, chemin = b.path, taille = b.fileSize or 0,
      octets = b.fileSize or 0, date = b.dateTimeOriginal, virtuelles = b.countVirtualCopies or 0,
      virtuelle = b.isVirtualCopy or false, maitre = b.masterPhoto,
      collections = {}, motsCles = {}, textes = {}, note = 0, drapeau = 0,
      largeur = largeur, hauteur = hauteur,
      pixels = largeur and hauteur and largeur > 0 and hauteur > 0 and largeur * hauteur or nil,
    }
  end
  return copies
end

local function lireCollections(photo)
  local r = {}
  for _, collection in ipairs(photo:getContainedCollections()) do
    r[#r + 1] = {
      objet = collection, id = collection.localIdentifier, nom = Catalogue.etiquetteCollection(collection, true),
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
  local champs = { 'copyName' }
  for _, cle in ipairs(Doublons.CHAMPS_TEXTE) do champs[#champs + 1] = cle end
  local formatees = catalogue:batchGetFormattedMetadata(photos, champs)
  for _, photo in ipairs(photos) do
    local c, b, f = parPhoto[photo], brutes[photo] or {}, formatees[photo] or {}
    c.retouchee = estRetouchee[c.id] or false
    c.note, c.drapeau, c.gps = b.rating or 0, b.pickStatus or 0, b.gps
    c.nomCopie = f.copyName or ''
    for _, mot in ipairs(b.keywords or {}) do c.motsCles[#c.motsCles + 1] = { objet = mot, nom = mot:getName() } end
    c.textes = {}
    for _, cle in ipairs(Doublons.CHAMPS_TEXTE) do c.textes[cle] = f[cle] or '' end
    c.publiee = #photo:getContainedPublishedCollections() > 0
    c.collections = lireCollections(photo)
  end
end

local function decrireCopie(c)
  return (c.pixels and string.format('%d × %d px', c.largeur, c.hauteur) or 'résolution inconnue')
    .. string.format(' · %d étoile(s) · %.2f Mo', c.note or 0, c.taille / 1024 / 1024)
    .. (c.virtuelle and (' · copie virtuelle' .. (c.nomCopie ~= '' and (' « ' .. c.nomCopie .. ' »') or '')) or '')
end

local function choisirGardee(contexte, copies, parResolution)
  local f = LrView.osFactory()
  local proprietes = LrBinding.makePropertyTable(contexte)
  local choix = {}
  local originaux = {}
  for _, c in ipairs(copies) do if not c.virtuelle then originaux[cleChemin(c.chemin)] = true end end
  local avecOriginalSelectionne = false
  local avecOriginalEcarte = false
  for _, c in ipairs(copies) do
    local originalEcarte = false
    if c.virtuelle and c.maitre then
      for _, collection in ipairs(c.maitre:getContainedCollections()) do
        if CORBEILLES[collection:getName()] then originalEcarte = true; break end
      end
    end
    -- Retirer l'original du catalogue retirerait aussi sa copie virtuelle : elle ne peut pas être
    -- la gardée quand cet original est sélectionné ou déjà mis à retirer hors de la sélection.
    if c.virtuelle and originaux[cleChemin(c.chemin)] then
      avecOriginalSelectionne = true
    elseif originalEcarte then
      avecOriginalEcarte = true
    else
      choix[#choix + 1] = {
        title = (#choix == 0 and 'Conseillée — ' or '') .. decrireCopie(c) .. ' — ' .. c.chemin, value = c.id,
      }
    end
  end
  if #choix == 0 then
    LrDialogs.message('Fusion manuelle impossible', 'Aucune photo de la sélection ne peut être gardée : '
      .. 'les originaux de ces copies virtuelles sont dans une collection « à retirer ». '
      .. 'Rétablis d’abord leurs originaux avant de relancer la fusion.', 'warning')
    return nil
  end
  proprietes.gardee = choix[1].value
  local reponse = LrDialogs.presentModalDialog {
    title = 'Fusion manuelle',
    contents = f:column {
      bind_to_object = proprietes,
      spacing = f:control_spacing(),
      f:static_text {
        title = string.format('%d photos sélectionnées seront traitées comme un seul groupe, sans comparaison '
          .. 'de leur contenu. Choisis celle qui récupère les albums et métadonnées. Les autres quitteront leurs '
          .. 'collections ordinaires et seront placées dans « %s ». Elles restent dans le catalogue jusqu’à leur retrait manuel.',
          #copies, COLLECTION_DOUBLONS),
        width = 560, height_in_lines = 5,
      },
      f:static_text {
        title = parResolution
          and 'Proposition : plus grande résolution, puis meilleure note, puis nom le plus simple.'
          or 'Résolution incomplète : proposition selon la note puis le nom ; le poids départage les égalités.',
        width = 560, height_in_lines = 2,
      },
      f:static_text { title = 'Photo à garder (la proposition est présélectionnée) :' },
      f:popup_menu { value = LrView.bind('gardee'), items = choix, width_in_chars = 72 },
      f:static_text {
        title = avecOriginalSelectionne
          and 'Une copie virtuelle et son original sont sélectionnés : garde un original pour conserver le fichier support.' or '',
        visible = avecOriginalSelectionne, width = 560, height_in_lines = 2,
      },
      f:static_text {
        title = avecOriginalEcarte
          and 'Les copies virtuelles dont l’original est dans une collection « à retirer » ne peuvent pas être gardées. '
            .. 'Rétablis d’abord leur original si tu veux les conserver.' or '',
        visible = avecOriginalEcarte, width = 560, height_in_lines = 3,
      },
    },
    actionVerb = 'Continuer',
  }
  if reponse ~= 'ok' then return nil end
  for _, c in ipairs(copies) do if c.id == proprietes.gardee then return c end end
  return nil
end

local function decrireCollections(decision)
  local albums, autres = {}, {}
  local prefixe = Noms.ENSEMBLE_ALBUMS .. ' / '
  for _, col in ipairs(decision.effets.collectionsFinales) do
    local liste = col.nom:sub(1, #prefixe) == prefixe and albums or autres
    liste[#liste + 1] = col.nom
  end
  table.sort(albums)
  table.sort(autres)
  local texte = #albums > 0 and ('Albums après fusion (' .. #albums .. ') :\n• ' .. table.concat(albums, '\n• '))
    or 'Albums après fusion : aucun album Google Photos dans les appartenances actuelles de la sélection.'
  if #autres > 0 then
    texte = texte .. '\n\nAutres collections après fusion :\n• ' .. table.concat(autres, '\n• ')
  end
  return texte
end

local function avertissementsRetirees(decision)
  local avertissements = {}
  for _, c in ipairs(decision.retirees) do
    if c.retouchee then avertissements[#avertissements + 1] = nomFichier(c.chemin) .. ' est retouchée dans Lightroom' end
    if c.virtuelle then avertissements[#avertissements + 1] = nomFichier(c.chemin) .. ' est une copie virtuelle' end
    if c.virtuelles > 0 then avertissements[#avertissements + 1] = nomFichier(c.chemin) .. ' a des copies virtuelles' end
    if c.publiee then avertissements[#avertissements + 1] = nomFichier(c.chemin) .. ' est dans une collection publiée' end
  end
  return avertissements
end

local function appliquer(catalogue, decision)
  local photos = {}
  for _, c in ipairs(decision.retirees) do
    if not c.virtuelle and cleChemin(c.chemin) ~= cleChemin(decision.garde.chemin) then
      photos[#photos + 1] = {
        chemin = c.chemin, fichier = nomFichier(c.chemin),
        date = c.date and Epoques.texte(Epoques.depuisLightroom(c.date, 0)) or '',
      }
    end
  end
  local corbeille
  local historiqueOk, erreurHistorique = Annulation.action(catalogue, HISTORIQUE, 'Fusion manuelle de photos',
    { retablir = { decision.garde.chemin }, type = 'doublon', photos = photos }, function()
    corbeille = catalogue:createCollection(COLLECTION_DOUBLONS, nil, true)
    local e, garde = decision.effets, decision.garde.photo
    for _, col in ipairs(e.corbeillesGardee) do col.objet:removePhotos({ garde }) end
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
    corbeille:removePhotos({ garde })
  end)
  for _, col in ipairs(decision.garde.photo:getContainedCollections()) do
    if CORBEILLES[col:getName()] then
      error('La photo gardée est encore dans « ' .. col:getName() .. ' ». Ne retire aucune photo du catalogue.', 0)
    end
  end
  if historiqueOk and Historique.contient(Historique.lire(HISTORIQUE), decision.garde.chemin) then
    error('La photo gardée reste exclue dans l’historique. Ne retire aucune photo du catalogue.', 0)
  end
  return historiqueOk, erreurHistorique
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
      local parResolution = Doublons.classerManuellement(copies)
      progression:done()

      local garde = choisirGardee(contexte, copies, parResolution)
      if not garde then return end
      local retirees = {}
      for _, c in ipairs(copies) do if c ~= garde then retirees[#retirees + 1] = c end end
      local decision = { garde = garde, retirees = retirees }
      local avertissements = avertissementsRetirees(decision)
      decision.effets = Doublons.effets(decision)

      local lignes = {}
      for _, c in ipairs(retirees) do
        lignes[#lignes + 1] = '• ' .. c.chemin
          .. (c.virtuelle and (' (copie virtuelle' .. (c.nomCopie ~= '' and (' « ' .. c.nomCopie .. ' »') or '') .. ')') or '')
      end
      local texteDestination = decrireCollections(decision)
      if #decision.effets.corbeillesGardee > 0 then
        texteDestination = texteDestination .. '\n\nLa photo gardée sera sortie des collections « à retirer » où elle se trouve déjà.'
      end
      local messageConfirmation = 'Photo gardée :\n' .. garde.chemin .. '\n' .. decrireCopie(garde)
        .. '\n\n' .. texteDestination .. '\n\nPhotos qui seront mises dans « '
        .. COLLECTION_DOUBLONS .. ' » :\n' .. table.concat(lignes, '\n')
        .. '\n\nMétadonnées : note la plus haute, mots-clés réunis, drapeau retenu prioritaire sur rejeté ; '
        .. 'textes et GPS de la photo gardée conservés, champs vides complétés avec les autres copies.'
        .. '\nLes fichiers retirés seront mémorisés dans photos-traitees.txt.'
      if #avertissements > 0 then
        messageConfirmation = messageConfirmation .. '\n\nÉléments non transférés :\n• '
          .. table.concat(avertissements, '\n• ')
          .. '\nLes réglages de développement, les copies virtuelles et les appartenances publiées restent sur les '
          .. 'copies écartées tant qu’elles sont au catalogue. Leur retrait ultérieur fera perdre ces éléments.'
      end
      if LrDialogs.confirm('Confirmer la fusion manuelle ?', messageConfirmation, 'Fusionner de force', 'Annuler') ~= 'ok' then return end

      etape = 'préparation de l’historique et fusion annulable'
      local historiqueOk, erreurHistorique = appliquer(catalogue, decision)
      local bilan = string.format('%d photos fusionnées. Photo gardée :\n%s\n\n%s\n\nLes %d autres sont dans « %s ».',
        #copies, garde.chemin, texteDestination, #retirees, COLLECTION_DOUBLONS)
        .. '\nLa photo gardée a été vérifiée hors des collections de retrait. Les copies écartées restent visibles '
        .. 'dans les dossiers tant qu’elles ne sont pas retirées du catalogue.'
        .. '\nCtrl+Z annule cette fusion complète, y compris l’historique des exclusions.'
      if historiqueOk then
        LrDialogs.message('Fusion manuelle terminée', bilan .. '\nHistorique enregistré dans photos-traitees.txt.', 'info')
      else
        LrDialogs.message('Fusion effectuée, historique non enregistré', bilan
          .. '\n\nLa fusion a bien été appliquée. Garde les copies dans cette collection tant que l’historique '
          .. 'n’est pas enregistré.\n' .. tostring(erreurHistorique), 'warning')
      end
    end)
    if not ok then
      LrDialogs.message('Erreur pendant la fusion manuelle', string.format('Étape : %s\n%s', etape, tostring(erreur)), 'critical')
    end
  end)
end)
