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
--
-- Taille des photos : au choix dans la section « Google Photos » (grand côté limité), ou selon la
-- section « Dimensionnement de l'image » de Lightroom.
-- Vidéos : non envoyées, converties en 1080p léger par ffmpeg (voir Videos.lua), ou envoyées telles
-- que Lightroom les exporte (section « Vidéo »).

local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local GooglePhotos = require 'GooglePhotos'
local Videos = require 'Videos'

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

local TAILLES = {
  { title = 'Selon « Dimensionnement de l’image »', value = 'lightroom' },
  { title = 'Taille d’origine', value = 'originale' },
  { title = '4096 pixels (4K)', value = '4096' },
  { title = '2048 pixels', value = '2048' },
  { title = '1600 pixels (léger)', value = '1600' },
}

local VIDEOS = {
  { title = 'Ne pas les envoyer', value = 'non' },
  { title = 'Converties en 1080p léger (ffmpeg)', value = 'convertir' },
  { title = 'Telles que Lightroom les exporte (section « Vidéo »)', value = 'telles' },
}

-- Réglages intégrés de Lightroom (préfixe LR_) imposés par le choix de taille des photos.
local function reglerDimensions(p)
  local taille = p.taille or 'lightroom'
  if taille == 'originale' then
    p.LR_size_doConstrain = false
    p.LR_size_userWantsConstrain = false
  elseif tonumber(taille) then
    p.LR_size_doConstrain = true
    p.LR_size_userWantsConstrain = true
    p.LR_size_resizeType = 'longEdge'
    p.LR_size_units = 'pixels'
    p.LR_size_maxWidth = tonumber(taille)
    p.LR_size_maxHeight = tonumber(taille)
    p.LR_size_doNotEnlarge = true
  end
end

-- Pour la conversion, Lightroom fournit le fichier d'origine : ffmpeg ne fait qu'un réencodage et
-- garde la date de prise de vue. Les découpes faites dans Lightroom ne sont alors pas appliquées.
local function reglerVideos(p)
  local videos = p.videos or 'non'
  p.LR_includeVideoFiles = videos ~= 'non'
  p.LR_export_videoFileHandling = videos ~= 'non' and 'include' or 'exclude'
  if videos == 'convertir' then
    p.LR_export_videoFormat = 'original'
    p.LR_export_videoPreset = 'original'
  end
end

local function updateExportSettings(p)
  reglerDimensions(p)
  reglerVideos(p)
end

-- Les sections de Lightroom suivent les choix faits dans la section « Google Photos ».
local function startDialog(p)
  p:addObserver('taille', function() pcall(reglerDimensions, p) end)
  p:addObserver('videos', function() pcall(reglerVideos, p) end)
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
        f:static_text { title = 'Photos :', alignment = 'right', width = etiquette },
        f:popup_menu { value = LrView.bind('taille'), items = TAILLES },
        f:static_text { title = 'grand côté au plus, sans agrandir' },
      },
      f:row {
        f:static_text { title = 'Vidéos :', alignment = 'right', width = etiquette },
        f:popup_menu { value = LrView.bind('videos'), items = VIDEOS },
      },
      f:row {
        f:static_text { title = '', width = etiquette },
        f:static_text {
          title = 'Conversion : MP4 H.264, petit côté 1080 pixels, 30 images/s, 6 Mbit/s au plus ; '
            .. 'HDR ramené en SDR.\nDemande ffmpeg (winget install Gyan.FFmpeg). Les découpes faites '
            .. 'dans Lightroom ne sont pas appliquées.',
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

  local modeVideos = exportContext.propertyTable.videos or 'non'
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

  -- Le format d'export est JPEG : tout autre fichier rendu est une vidéo.
  local function estVideo(chemin)
    local extension = (LrPathUtils.extension(chemin) or ''):lower()
    return extension ~= 'jpg' and extension ~= 'jpeg'
  end
  local function aConvertir(chemin) return modeVideos == 'convertir' and estVideo(chemin) end
  -- Nom du fichier dans Google Photos.
  local function nomEnvoye(chemin)
    local nom = LrPathUtils.leafName(chemin)
    if aConvertir(chemin) then nom = LrPathUtils.removeExtension(nom) .. '.mp4' end
    return nom
  end

  -- Vidéo convertie, à envoyer puis supprimer ; nil et l'erreur en cas d'échec. Les fichiers de
  -- travail ont des noms en ASCII, que la ligne de commande de ffmpeg ne peut pas abîmer.
  local ffmpeg, nbConversions = nil, 0
  local function convertirVideo(chemin)
    if ffmpeg == nil then ffmpeg = Videos.trouverFfmpeg() or false end
    if not ffmpeg then
      return nil, 'ffmpeg introuvable : installe-le (winget install Gyan.FFmpeg) ou choisis d’envoyer '
        .. 'les vidéos telles que Lightroom les exporte.'
    end
    nbConversions = nbConversions + 1
    local dossier = LrPathUtils.parent(chemin)
    local extension = (LrPathUtils.extension(chemin) or ''):gsub('[^%w]', '')
    local source = LrPathUtils.child(dossier, string.format('google-photos-video-%d.%s', nbConversions,
      extension ~= '' and extension or 'video'))
    local sortie = LrPathUtils.child(dossier, string.format('google-photos-video-%d-1080p.mp4', nbConversions))
    LrFileUtils.delete(source)
    LrTasks.pcall(LrFileUtils.move, chemin, source)
    if LrFileUtils.exists(source) ~= 'file' then return nil, 'vidéo exportée introuvable : ' .. chemin end
    local ok, erreur = Videos.convertir(ffmpeg, source, sortie)
    LrFileUtils.delete(source)
    if not ok then return nil, erreur end
    return sortie
  end

  -- Les photos envoyées sont ajoutées à l'album par lots.
  local enAttente = {}
  local nbEnvoyees, nbVideos, nbDeja, nbEchecs, nbNonPreparees = 0, 0, 0, 0, 0
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
        if e.video then nbVideos = nbVideos + 1 end
      end
    end
    enAttente = {}
  end

  for i, rendition in exportContext:renditions { stopIfCanceled = true } do
    progression:setPortionComplete(i - 1, nbPhotos)
    if deja[nomEnvoye(rendition.destinationPath):lower()] then
      rendition:skipRender()
      nbDeja = nbDeja + 1
    else
      local rendue, chemin = rendition:waitForRender()
      if rendue then
        local nom, fichier, erreur = nomEnvoye(chemin), chemin, nil
        if aConvertir(chemin) then
          progression:setCaption(string.format('Conversion de %s en 1080p (%d / %d)', nom, i, nbPhotos))
          local ok, resultat, message = LrTasks.pcall(convertirVideo, chemin)
          if ok then fichier, erreur = resultat, message else fichier, erreur = nil, tostring(resultat) end
        end
        if fichier then
          progression:setCaption(string.format('Envoi de %s (%d / %d)', nom, i, nbPhotos))
          local envoye, resultat = LrTasks.pcall(function() return client:envoyer(fichier) end)
          if envoye then
            table.insert(enAttente, { jeton = resultat, nom = nom, rendition = rendition, video = estVideo(chemin) })
          else
            erreur = tostring(resultat)
          end
        end
        LrFileUtils.delete(chemin)
        if fichier and fichier ~= chemin then LrFileUtils.delete(fichier) end
        if erreur then
          rendition:uploadFailed(erreur)
          nbEchecs = nbEchecs + 1
        elseif #enAttente >= GooglePhotos.TAILLE_LOT then
          ajouterEnAttente()
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
  if nbVideos > 0 then
    message = string.format('%d photos et %d vidéos envoyées dans l’album « %s ».', nbEnvoyees - nbVideos, nbVideos, titre)
  end
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
  canExportVideo = true,
  exportPresetFields = {
    { key = 'album', default = '' },
    { key = 'taille', default = 'lightroom' },
    { key = 'videos', default = 'non' },
  },
  startDialog = startDialog,
  updateExportSettings = updateExportSettings,
  sectionsForTopOfDialog = sectionsForTopOfDialog,
  processRenderedPhotos = processRenderedPhotos,
}
