-- Service d'export « Google Photos » : envoie les photos exportées dans un album Google Photos,
-- par l'API officielle (voir GooglePhotos.lua).
--
-- Usage courant : sélectionner les photos d'une collection, clic droit sur une vignette →
-- Exporter → « Google Photos 4K » (préréglage du dossier presets, auquel on peut ajouter des
-- actions LR/Mogrify : bordure, textes…).
--
-- L'album porte le nom choisi dans la boîte d'export ou, à défaut, celui de la collection (ou du
-- dossier) affichée dans Lightroom. Si ce service a déjà créé un album de ce nom, il le complète :
-- les photos dont le nom de fichier y figure déjà ne sont ni rendues ni renvoyées.
-- Les actions de post-traitement (LR/Mogrify…) s'appliquent avant l'envoi.

local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local GooglePhotos = require 'GooglePhotos'

local function trim(texte)
  return (texte:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Nom de la collection ou du dossier affiché, si une seule source est sélectionnée.
-- Les sources spéciales (« Toutes les photos »…) n'ont pas de nom utilisable.
local function nomSourceActive()
  local sources = LrApplication.activeCatalog():getActiveSources()
  if #sources ~= 1 then return nil end
  local ok, nom = LrTasks.pcall(function() return sources[1]:getName() end)
  if ok and type(nom) == 'string' and trim(nom) ~= '' then return trim(nom) end
  return nil
end

local function demanderNomAlbum(contexte)
  local f = LrView.osFactory()
  local proprietes = LrBinding.makePropertyTable(contexte)
  proprietes.nom = ''
  local reponse = LrDialogs.presentModalDialog {
    title = 'Album Google Photos',
    contents = f:column {
      bind_to_object = proprietes,
      spacing = f:control_spacing(),
      f:static_text { title = 'Dans quel album Google Photos envoyer les photos ?' },
      f:edit_field { value = LrView.bind('nom'), width_in_chars = 40, immediate = true },
    },
    actionVerb = 'Envoyer',
  }
  local nom = trim(proprietes.nom or '')
  if reponse ~= 'ok' or nom == '' then return nil end
  return nom
end

-- Client connecté à Google Photos ; propose au besoin de lancer la connexion.
-- Renvoie nil si l'utilisateur y renonce.
local function connecter()
  local client = GooglePhotos.ouvrir()
  if client then return client end
  local choix = LrDialogs.confirm('Connexion à Google Photos',
    'Lightroom n’est pas encore connecté à ton compte Google Photos, ou la connexion a expiré.\n\n'
    .. 'Ton navigateur va s’ouvrir sur la page de Google. Si Google prévient que l’application '
    .. 'n’est pas validée : « Paramètres avancés », puis « Accéder à … ». Laisse cochées les deux '
    .. 'autorisations demandées.\n\nLightroom attend la fin de la connexion (10 minutes au plus).',
    'Se connecter', 'Annuler')
  if choix ~= 'ok' then return nil end
  GooglePhotos.lancerConnexion()
  client = GooglePhotos.ouvrir()
  if not client then error('la connexion semble faite, mais Google la refuse. Réessaie l’export.', 0) end
  return client
end

local function sectionsForTopOfDialog(f, proprietes)
  local etiquette = LrView.share('etiquette_google_photos')
  return {
    {
      title = 'Google Photos',
      synopsis = LrView.bind {
        key = 'album',
        transform = function(album)
          return (album and album ~= '') and ('Album « ' .. album .. ' »') or 'Album : nom de la collection'
        end,
      },
      f:row {
        f:static_text { title = 'Album :', alignment = 'right', width = etiquette },
        f:edit_field { value = LrView.bind('album'), width_in_chars = 40, immediate = true },
      },
      f:row {
        f:static_text { title = '', width = etiquette },
        f:static_text {
          title = 'Laisser vide pour prendre le nom de la collection ou du dossier affiché.\n'
            .. 'Un album déjà créé par ce service est complété, sans renvoyer les photos qu’il contient.',
          height_in_lines = 2,
        },
      },
      f:row {
        f:static_text { title = '', width = etiquette },
        f:static_text {
          title = GooglePhotos.connexionEnregistree() and 'Connecté à Google Photos.'
            or 'Pas encore connecté : la connexion se fera au premier envoi.',
        },
      },
    },
  }
end

local function envoyer(contexte, exportContext)
  local nbPhotos = exportContext.exportSession:countRenditions()
  local progression = exportContext:configureProgress {
    title = string.format('Envoi de %d photos vers Google Photos', nbPhotos),
  }

  local titre = trim(exportContext.propertyTable.album or '')
  if titre == '' then titre = nomSourceActive() or demanderNomAlbum(contexte) end
  local client = titre and connecter()
  if not client then
    for _, rendition in exportContext:renditions() do rendition:skipRender() end
    return
  end

  -- Album : celui que ce service a déjà créé sous ce nom, sinon un nouveau.
  progression:setCaption('Recherche de l’album « ' .. titre .. ' »…')
  local album = client:trouverAlbum(titre)
  local deja = {}
  if album then
    deja = client:nomsDansAlbum(album.id)
  else
    album = client:creerAlbum(titre)
  end

  -- Les photos envoyées sont ajoutées à l'album par lots.
  local enAttente = {}
  local nbEnvoyees, nbDeja, nbEchecs, nbNonPreparees = 0, 0, 0, 0
  local function ajouterEnAttente()
    if #enAttente == 0 then return end
    progression:setCaption('Ajout des photos à l’album…')
    local erreurs = client:ajouterAAlbum(album.id, enAttente)
    for i, e in ipairs(enAttente) do
      if erreurs[i] then
        e.rendition:uploadFailed(erreurs[i])
        nbEchecs = nbEchecs + 1
      else
        nbEnvoyees = nbEnvoyees + 1
      end
    end
    enAttente = {}
  end

  for i, rendition in exportContext:renditions { stopIfCanceled = true } do
    progression:setPortionComplete(i - 1, nbPhotos)
    if deja[LrPathUtils.leafName(rendition.destinationPath):lower()] then
      rendition:skipRender()
      nbDeja = nbDeja + 1
    else
      local rendue, chemin = rendition:waitForRender()
      if rendue then
        local nom = LrPathUtils.leafName(chemin)
        progression:setCaption(string.format('Envoi de %s (%d / %d)', nom, i, nbPhotos))
        local envoye, resultat = LrTasks.pcall(function() return client:envoyer(chemin) end)
        LrFileUtils.delete(chemin)
        if envoye then
          table.insert(enAttente, { jeton = resultat, nom = nom, rendition = rendition })
          if #enAttente >= GooglePhotos.TAILLE_LOT then ajouterEnAttente() end
        else
          rendition:uploadFailed(tostring(resultat))
          nbEchecs = nbEchecs + 1
        end
      else
        -- Lightroom signale lui-même l'erreur dans sa liste de fin d'export.
        nbNonPreparees = nbNonPreparees + 1
      end
    end
  end
  -- Même après une annulation : les photos déjà envoyées vont dans l'album.
  ajouterEnAttente()
  progression:done()

  local message = string.format('%d photos envoyées dans l’album « %s ».', nbEnvoyees, titre)
  if nbDeja > 0 then
    message = message .. string.format('\n%d photos y étaient déjà, elles n’ont pas été renvoyées.', nbDeja)
  end
  if nbNonPreparees > 0 then
    message = message .. string.format('\n%d photos n’ont pas pu être préparées par Lightroom ou une action '
      .. 'de post-traitement (LR/Mogrify…) : elles n’ont pas été envoyées.', nbNonPreparees)
  end
  if nbEchecs > 0 then
    message = message .. string.format('\n%d photos n’ont pas pu être envoyées (Lightroom en affiche la liste).', nbEchecs)
  end
  if LrDialogs.confirm('Google Photos', message, 'Ouvrir l’album', 'Fermer') == 'ok' and album.productUrl then
    LrHttp.openUrlInBrowser(album.productUrl)
  end
end

local function processRenderedPhotos(contexte, exportContext)
  local ok, erreur = LrTasks.pcall(envoyer, contexte, exportContext)
  if not ok then
    LrDialogs.message('Envoi vers Google Photos impossible', tostring(erreur), 'critical')
  end
end

return {
  hideSections = { 'exportLocation' },
  allowFileFormats = { 'JPEG' },
  -- La résolution d'impression reste affichée : sans elle, les textes de LR/Mogrify échouent.
  canExportVideo = false,
  exportPresetFields = {
    { key = 'album', default = '' },
  },
  sectionsForTopOfDialog = sectionsForTopOfDialog,
  processRenderedPhotos = processRenderedPhotos,
}
