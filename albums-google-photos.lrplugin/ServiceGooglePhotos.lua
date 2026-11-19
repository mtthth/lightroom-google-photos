-- Service d'export « Google Photos » : envoie les photos exportées dans un album Google Photos,
-- par l'API officielle (voir GooglePhotos.lua).
--
-- Usage courant : sélectionner les photos d'une collection, clic droit sur une vignette →
-- Exporter → « Google Photos 4K » (préréglage du dossier presets, auquel on peut ajouter des
-- actions LR/Mogrify : bordure, textes…).
--
-- À l'ouverture de la boîte d'export, le nom de l'album est prérempli avec celui de la collection
-- (ou du dossier) affichée dans Lightroom, et reste modifiable. S'il est laissé vide, ce nom est repris
-- à l'envoi, ou demandé. Si ce service a déjà créé un album de ce nom, il le complète :
-- les photos dont le nom de fichier y figure déjà ne sont ni rendues ni renvoyées.
-- Les actions de post-traitement (LR/Mogrify…) s'appliquent avant l'envoi.
--
-- Taille des photos : au choix dans la section « Google Photos » (grand côté limité), ou selon la
-- section « Dimensionnement de l'image » de Lightroom.
-- Vidéos : non envoyées, converties en 1080p léger par ffmpeg (voir Videos.lua), ou envoyées telles
-- que Lightroom les exporte (section « Vidéo »).
-- Les textes affichés suivent la langue choisie dans les réglages du module (voir Langue.lua).

local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local GooglePhotos = require 'GooglePhotos'
local Langue = require 'Langue'
local Videos = require 'Videos'
local T = Langue.t

local function trim(texte)
  return (texte:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Nom de la collection ou du dossier affiché, si une seule source est sélectionnée.
-- Les sources spéciales (« Toutes les photos »…) n'ont pas de nom utilisable. pcall plutôt que
-- LrTasks.pcall : la boîte d'export l'appelle hors d'une tâche, et getName ne cède pas la main.
local function nomSourceActive()
  local okSources, sources = pcall(function() return LrApplication.activeCatalog():getActiveSources() end)
  if not okSources or type(sources) ~= 'table' or #sources ~= 1 then return nil end
  local ok, nom = pcall(function() return sources[1]:getName() end)
  if ok and type(nom) == 'string' and trim(nom) ~= '' then return trim(nom) end
  return nil
end

local function demanderNomAlbum(contexte)
  local f = LrView.osFactory()
  local proprietes = LrBinding.makePropertyTable(contexte)
  proprietes.nom = ''
  local reponse = LrDialogs.presentModalDialog {
    title = T('Album Google Photos', 'Google Photos album'),
    contents = f:column {
      bind_to_object = proprietes,
      spacing = f:control_spacing(),
      f:static_text { title = T('Dans quel album Google Photos envoyer les photos ?',
        'Which Google Photos album should the photos go to?') },
      f:edit_field { value = LrView.bind('nom'), width_in_chars = 40, immediate = true },
    },
    actionVerb = T('Envoyer', 'Upload'),
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
  local choix = LrDialogs.confirm(T('Connexion à Google Photos', 'Connecting to Google Photos'),
    T('Lightroom n’est pas encore connecté à ton compte Google Photos, ou la connexion a expiré.\n\n'
    .. 'Ton navigateur va s’ouvrir sur la page de Google. Si Google prévient que l’application '
    .. 'n’est pas validée : « Paramètres avancés », puis « Accéder à … ». Laisse cochées les deux '
    .. 'autorisations demandées.\n\nLightroom attend la fin de la connexion (10 minutes au plus).',
    'Lightroom is not connected to your Google Photos account yet, or the connection has expired.\n\n'
    .. 'Your browser will open on Google’s page. If Google warns that the app has not been verified: '
    .. '“Advanced”, then “Go to …”. Leave both requested permissions ticked.\n\n'
    .. 'Lightroom waits for the connection to finish (10 minutes at most).'),
    T('Se connecter', 'Connect'), T('Annuler', 'Cancel'))
  if choix ~= 'ok' then return nil end
  GooglePhotos.lancerConnexion()
  client = GooglePhotos.ouvrir()
  if not client then
    error(T('la connexion semble faite, mais Google la refuse. Réessaie l’export.',
      'the connection seems complete, but Google refuses it. Try the export again.'), 0)
  end
  return client
end

-- Fonctions : les titres sont traduits à l'ouverture de la boîte d'export.
local function tailles()
  return {
    { title = T('Selon « Dimensionnement de l’image »', 'As in “Image Sizing”'), value = 'lightroom' },
    { title = T('Taille d’origine', 'Original size'), value = 'originale' },
    { title = '4096 pixels (4K)', value = '4096' },
    { title = '2048 pixels', value = '2048' },
    { title = T('1600 pixels (léger)', '1600 pixels (light)'), value = '1600' },
  }
end

local function videos()
  return {
    { title = T('Ne pas les envoyer', 'Do not upload them'), value = 'non' },
    { title = T('Converties en 1080p léger (ffmpeg)', 'Converted to light 1080p (ffmpeg)'), value = 'convertir' },
    { title = T('Telles que Lightroom les exporte (section « Vidéo »)', 'As exported by Lightroom (“Video” section)'),
      value = 'telles' },
  }
end

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

-- Le nom de l'album est prérempli avec celui de la collection ou du dossier affiché, pour qu'il
-- suffise de le modifier au besoin. Sans source nommée (« Toutes les photos »…), le champ garde sa
-- valeur. Les sections de Lightroom suivent les choix faits dans la section « Google Photos ».
local function startDialog(p)
  local nom = nomSourceActive()
  if nom then p.album = nom end
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
          return (album and album ~= '') and (T('Album « ', 'Album “') .. album .. T(' »', '”'))
            or T('Album : nom de la collection', 'Album: collection name')
        end,
      },
      f:row {
        f:static_text { title = T('Album :', 'Album:'), alignment = 'right', width = etiquette },
        f:edit_field { value = LrView.bind('album'), width_in_chars = 40, immediate = true },
      },
      f:row {
        f:static_text { title = '', width = etiquette },
        f:static_text {
          title = T('Prérempli avec le nom de la collection ou du dossier affiché : modifiez-le au besoin.\n'
            .. 'Un album déjà créé par ce service est complété, sans renvoyer les photos qu’il contient.',
            'Prefilled with the name of the collection or folder shown: change it if needed.\n'
            .. 'An album already created by this service is completed, without re-uploading the photos it contains.'),
          height_in_lines = 2,
        },
      },
      f:row {
        f:static_text { title = T('Photos :', 'Photos:'), alignment = 'right', width = etiquette },
        f:popup_menu { value = LrView.bind('taille'), items = tailles() },
        f:static_text { title = T('grand côté au plus, sans agrandir', 'long edge at most, never enlarged') },
      },
      f:row {
        f:static_text { title = T('Vidéos :', 'Videos:'), alignment = 'right', width = etiquette },
        f:popup_menu { value = LrView.bind('videos'), items = videos() },
      },
      f:row {
        f:static_text { title = '', width = etiquette },
        f:static_text {
          title = T('Conversion : MP4 H.264, petit côté 1080 pixels, 30 images/s, 6 Mbit/s au plus ; '
            .. 'HDR ramené en SDR.\nDemande ffmpeg (winget install Gyan.FFmpeg). Les découpes faites '
            .. 'dans Lightroom ne sont pas appliquées.',
            'Conversion: MP4 H.264, short edge 1080 pixels, 30 fps, 6 Mbit/s at most; HDR mapped to SDR.\n'
            .. 'Requires ffmpeg (winget install Gyan.FFmpeg). Trims made in Lightroom are not applied.'),
          height_in_lines = 2,
        },
      },
      f:row {
        f:static_text { title = '', width = etiquette },
        f:static_text {
          title = GooglePhotos.connexionEnregistree() and T('Connecté à Google Photos.', 'Connected to Google Photos.')
            or T('Pas encore connecté : la connexion se fera au premier envoi.',
              'Not connected yet: you will connect on the first upload.'),
        },
      },
    },
  }
end

local function envoyer(contexte, exportContext)
  local nbPhotos = exportContext.exportSession:countRenditions()
  local progression = exportContext:configureProgress {
    title = string.format(T('Envoi de %d photos vers Google Photos', 'Uploading %d photos to Google Photos'), nbPhotos),
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
  progression:setCaption(T('Recherche de l’album « ', 'Looking for the album “') .. titre .. T(' »…', '”…'))
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
      return nil, T('ffmpeg introuvable : installe-le (winget install Gyan.FFmpeg) ou choisis d’envoyer '
        .. 'les vidéos telles que Lightroom les exporte.', 'ffmpeg not found: install it (winget install Gyan.FFmpeg) '
        .. 'or choose to upload videos as exported by Lightroom.')
    end
    nbConversions = nbConversions + 1
    local dossier = LrPathUtils.parent(chemin)
    local extension = (LrPathUtils.extension(chemin) or ''):gsub('[^%w]', '')
    local source = LrPathUtils.child(dossier, string.format('google-photos-video-%d.%s', nbConversions,
      extension ~= '' and extension or 'video'))
    local sortie = LrPathUtils.child(dossier, string.format('google-photos-video-%d-1080p.mp4', nbConversions))
    LrFileUtils.delete(source)
    LrTasks.pcall(LrFileUtils.move, chemin, source)
    if LrFileUtils.exists(source) ~= 'file' then return nil, T('vidéo exportée introuvable : ', 'exported video not found: ') .. chemin end
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
    progression:setCaption(T('Ajout des photos à l’album…', 'Adding the photos to the album…'))
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
          progression:setCaption(string.format(T('Conversion de %s en 1080p (%d / %d)', 'Converting %s to 1080p (%d / %d)'), nom, i, nbPhotos))
          local ok, resultat, message = LrTasks.pcall(convertirVideo, chemin)
          if ok then fichier, erreur = resultat, message else fichier, erreur = nil, tostring(resultat) end
        end
        if fichier then
          progression:setCaption(string.format(T('Envoi de %s (%d / %d)', 'Uploading %s (%d / %d)'), nom, i, nbPhotos))
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

  local message = string.format(T('%d photos envoyées dans l’album « %s ».', '%d photos uploaded to the album “%s”.'),
    nbEnvoyees, titre)
  if nbVideos > 0 then
    message = string.format(T('%d photos et %d vidéos envoyées dans l’album « %s ».',
      '%d photos and %d videos uploaded to the album “%s”.'), nbEnvoyees - nbVideos, nbVideos, titre)
  end
  if nbDeja > 0 then
    message = message .. string.format(T('\n%d photos y étaient déjà, elles n’ont pas été renvoyées.',
      '\n%d photos were already there and were not uploaded again.'), nbDeja)
  end
  if nbNonPreparees > 0 then
    message = message .. string.format(T('\n%d photos n’ont pas pu être préparées par Lightroom ou une action '
      .. 'de post-traitement (LR/Mogrify…) : elles n’ont pas été envoyées.', '\n%d photos could not be rendered by '
      .. 'Lightroom or a post-processing action (LR/Mogrify…): they were not uploaded.'), nbNonPreparees)
  end
  if nbEchecs > 0 then
    message = message .. string.format(T('\n%d photos n’ont pas pu être envoyées (Lightroom en affiche la liste).',
      '\n%d photos could not be uploaded (Lightroom lists them).'), nbEchecs)
  end
  if LrDialogs.confirm('Google Photos', message, T('Ouvrir l’album', 'Open the album'), T('Fermer', 'Close')) == 'ok'
    and album.productUrl then
    LrHttp.openUrlInBrowser(album.productUrl)
  end
end

local function processRenderedPhotos(contexte, exportContext)
  local ok, erreur = LrTasks.pcall(envoyer, contexte, exportContext)
  if not ok then
    LrDialogs.message(T('Envoi vers Google Photos impossible', 'Upload to Google Photos failed'), tostring(erreur), 'critical')
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
