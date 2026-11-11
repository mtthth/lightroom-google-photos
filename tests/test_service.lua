-- Simulation d'exports avec un faux Lightroom et un faux Google Photos.
local PLUGIN, SCRATCH = arg[1], arg[2]
package.path = PLUGIN .. '/?.lua;' .. package.path

local HOME = SCRATCH .. '/home'
local LOCAL = HOME .. '/AppData/Local'
local TMP = SCRATCH .. '/rendus'
os.execute('mkdir "' .. (LOCAL .. '/lightroom-google-photos'):gsub('/', '\\') .. '" 2>nul')
os.execute('mkdir "' .. TMP:gsub('/', '\\') .. '" 2>nul')
local FICHIER_CONNEXION = LOCAL .. '/lightroom-google-photos/google-photos.json'
os.remove(FICHIER_CONNEXION)

-- Comme dans Lightroom : pas de variables d'environnement.
os.getenv = nil
_PLUGIN = { path = PLUGIN }

local Json -- chargé plus bas
local journal = {}
local function note(...) journal[#journal + 1] = table.concat({ ... }, ' ') end

local function feuille(p) return p:match('[^/\\]+$') end
local function parent(p) return p:match('^(.*)[/\\][^/\\]+$') end

local horloge = 1000
local reponses = {}  -- réponses des fausses boîtes de dialogue
local supprimes, pauses, ouvertes, messages, confirmations = {}, {}, {}, {}, {}
local commandeExecutee

local mocks = {}
mocks.LrDate = { currentTime = function() return horloge end }
local function lire(p) local f = io.open(p, 'rb'); if not f then return nil end; local c = f:read('*a'); f:close(); return c end
local function ecrire(p, c) local f = assert(io.open(p, 'wb')); f:write(c); f:close() end

-- Faux dossiers (pour la recherche de ffmpeg) : chemin → liste des chemins qu'il contient.
local dossiers = {}
local FFMPEG_WINGET = LOCAL .. '/Microsoft/WinGet/Packages/Gyan.FFmpeg_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin/ffmpeg.exe'
local function installerFfmpeg(present)
  dossiers = {}
  if not present then return end
  local packages = LOCAL .. '/Microsoft/WinGet/Packages'
  dossiers[packages] = { packages .. '/Autre.Paquet_1', packages .. '/Gyan.FFmpeg_8wekyb3d8bbwe' }
  dossiers[packages .. '/Autre.Paquet_1'] = {}
  dossiers[packages .. '/Gyan.FFmpeg_8wekyb3d8bbwe'] = { parent(parent(FFMPEG_WINGET)) }
end
local fichiersFfmpeg = { [FFMPEG_WINGET] = true }

mocks.LrPathUtils = {
  child = function(a, b) return a .. '/' .. b end, parent = parent, leafName = feuille,
  extension = function(p) return feuille(p):match('%.([^.]*)$') or '' end,
  removeExtension = function(p) return (p:gsub('%.[^./\\]*$', '')) end,
  getStandardFilePath = function(nom) assert(nom == 'home'); return HOME end,
}
mocks.LrFileUtils = {
  exists = function(p)
    if dossiers[p] then return 'directory' end
    if fichiersFfmpeg[p] and dossiers[parent(parent(parent(p)))] then return 'file' end
    local f = io.open(p, 'rb'); if f then f:close(); return 'file' end; return false
  end,
  delete = function(p) os.remove(p); supprimes[#supprimes + 1] = p end,
  move = function(a, b) assert(os.rename(a, b)) end,
  directoryEntries = function(p)
    local i, liste = 0, dossiers[p] or {}
    return function() i = i + 1; return liste[i] end
  end,
  createAllDirectories = function() end,
}

-- Faux ffmpeg et ffprobe : une vidéo dont le contenu mentionne HDR est en HLG, une vidéo CASSEE
-- ne se convertit pas.
local commandesFfmpeg = {}
local function fauxFfmpeg(commande)
  commandesFfmpeg[#commandesFfmpeg + 1] = commande
  local journal = commande:match('> "([^"]+)" 2>&1"$')
  if commande:find('-version', 1, true) then
    return dossiers[LOCAL .. '/Microsoft/WinGet/Packages'] and 0 or 1
  end
  local entree = commande:match(' "([^"]+)" > ') or commande:match('%-i "([^"]+)"')
  if commande:find('ffprobe.exe', 1, true) then
    entree = commande:match('nk=1 "([^"]+)"')
    ecrire(journal, (lire(entree) or ''):find('HDR') and 'arib-std-b67\r\n' or 'bt709\r\n')
    return 0
  end
  entree = commande:match('%-i "([^"]+)"')
  local sortie = commande:match('"([^"]+)" > "[^"]+" 2>&1"$')
  local contenu = lire(entree) or ''
  if contenu:find('CASSEE') then
    ecrire(journal, '[mov @ 0000] moov atom not found\r\n' .. entree .. ': Invalid data found when processing input\r\n')
    return 1
  end
  ecrire(journal, '')
  ecrire(sortie, 'MP4(' .. contenu .. ')')
  return 0
end

mocks.LrTasks = {
  pcall = pcall,
  sleep = function(s) pauses[#pauses + 1] = s end,
  execute = function(commande)
    if commande:find('ffmpeg', 1, true) or commande:find('ffprobe', 1, true) then return fauxFfmpeg(commande) end
    commandeExecutee = commande
    local f = io.open(FICHIER_CONNEXION, 'wb')
    f:write('{"client_id":"C","client_secret":"S","refresh_token":"R-OK"}')
    f:close()
    return 0
  end,
}
mocks.LrDialogs = {
  confirm = function(titre, texte, oui)
    confirmations[#confirmations + 1] = { titre = titre, texte = texte, oui = oui }
    return table.remove(reponses, 1) or 'cancel'
  end,
  message = function(titre, texte, genre) messages[#messages + 1] = { titre = titre, texte = texte, genre = genre } end,
  presentModalDialog = function(args)
    local r = table.remove(reponses, 1)
    if r then args.contents.bind_to_object.nom = r; return 'ok' end
    return 'cancel'
  end,
}
mocks.LrBinding = { makePropertyTable = function() return {} end }
local fabrique = setmetatable({}, { __index = function() return function(_, t) return t end end })
mocks.LrView = { osFactory = function() return fabrique end, bind = function(t) return t end, share = function(t) return t end }
local sources = {}
mocks.LrApplication = { activeCatalog = function() return { getActiveSources = function() return sources end } end }

-- Faux Google -----------------------------------------------------------------------------
local google
local function reinitialiserGoogle()
  google = { albums = {}, contenu = {}, envois = 0, lots = {}, jetons = 0, refreshValide = true, statutCreation = 200 }
end
reinitialiserGoogle()

local function entete(entetes, nom)
  for _, e in ipairs(entetes or {}) do if e.field == nom then return e.value end end
end
local function rep(statut, corps) return corps, { status = statut } end

local function routeur(methode, url, corps, entetes)
  if url == 'https://oauth2.googleapis.com/token' then
    assert(entete(entetes, 'Content-Type') == 'application/x-www-form-urlencoded')
    if corps:find('refresh_token=R%-OK') and google.refreshValide then
      google.jetons = google.jetons + 1
      return rep(200, '{"access_token":"AT' .. google.jetons .. '","expires_in":3599}')
    end
    return rep(400, '{"error":"invalid_grant","error_description":"Token has been expired or revoked."}')
  end
  assert(entete(entetes, 'Authorization') == 'Bearer AT' .. google.jetons, 'jeton périmé : ' .. tostring(entete(entetes, 'Authorization')))
  local chemin = url:gsub('^https://photoslibrary.googleapis.com/v1/', '')

  if methode == 'GET' and chemin:find('^albums%?') then
    assert(chemin:find('excludeNonAppCreatedData=true'))
    -- Pages de deux albums, pour vérifier le parcours des pages.
    local debut = tonumber(chemin:match('pageToken=(%d+)') or '1')
    local page = { albums = {} }
    for i = debut, math.min(debut + 1, #google.albums) do page.albums[#page.albums + 1] = google.albums[i] end
    if debut + 2 <= #google.albums then page.nextPageToken = tostring(debut + 2) end
    return rep(200, Json.encoder(page))
  elseif methode == 'POST' and chemin == 'albums' then
    if google.statutCreation ~= 200 then return rep(google.statutCreation, '{"error":{"code":403,"message":"Request had insufficient authentication scopes.","status":"PERMISSION_DENIED"}}') end
    local titre = Json.decoder(corps).album.title
    local album = { id = 'ALB' .. (#google.albums + 1), title = titre, productUrl = 'https://photos.google.com/lr/album/' .. (#google.albums + 1) }
    google.albums[#google.albums + 1] = album
    google.contenu[album.id] = {}
    return rep(200, Json.encoder(album))
  elseif methode == 'POST' and chemin == 'mediaItems:search' then
    local d = Json.decoder(corps)
    local liste = google.contenu[d.albumId]
    local debut = tonumber(d.pageToken or '1')
    local page = { mediaItems = {} }
    for i = debut, math.min(debut + 39, #liste) do page.mediaItems[#page.mediaItems + 1] = { id = 'm' .. i, filename = liste[i] } end
    if debut + 40 <= #liste then page.nextPageToken = tostring(debut + 40) end
    return rep(200, Json.encoder(page))
  elseif methode == 'POST' and chemin == 'uploads' then
    assert(entete(entetes, 'X-Goog-Upload-Protocol') == 'raw')
    assert(entete(entetes, 'Content-Type') == 'application/octet-stream')
    if corps:find('ECHEC%-ENVOI') then return rep(503, 'Service Unavailable') end
    google.envois = google.envois + 1
    google['jeton' .. google.envois] = corps
    google['type' .. google.envois] = entete(entetes, 'X-Goog-Upload-Content-Type')
    google['delai' .. google.envois] = google.dernierDelai
    return rep(200, 'UP' .. google.envois)
  elseif methode == 'POST' and chemin == 'mediaItems:batchCreate' then
    local d = Json.decoder(corps)
    assert(#d.newMediaItems <= 50, 'lot trop grand')
    google.lots[#google.lots + 1] = #d.newMediaItems
    local resultats, partiel = {}, false
    for _, n in ipairs(d.newMediaItems) do
      local item = n.simpleMediaItem
      local r = { uploadToken = item.uploadToken }
      if item.fileName:find('refus') then
        r.status = { code = 3, message = 'Failed: There was an error while trying to create this media item.' }
        partiel = true
      else
        r.status = { message = 'Success' }
        r.mediaItem = { id = 'M' .. item.uploadToken, filename = item.fileName }
        table.insert(google.contenu[d.albumId], item.fileName)
      end
      resultats[#resultats + 1] = r
    end
    return rep(partiel and 207 or 200, Json.encoder({ newMediaItemResults = resultats }))
  end
  error('requête inattendue : ' .. methode .. ' ' .. url)
end

mocks.LrHttp = {
  get = function(url, entetes) return routeur('GET', url, nil, entetes) end,
  post = function(url, corps, entetes, methode, delai)
    google.dernierDelai = delai
    return routeur(methode or 'POST', url, corps, entetes)
  end,
  openUrlInBrowser = function(url) ouvertes[#ouvertes + 1] = url end,
}

function import(nom) return assert(mocks[nom], 'module inconnu : ' .. nom) end
Json = require 'Json'
local Service = require 'ServiceGooglePhotos'

-- Faux export --------------------------------------------------------------------------------
local function exporter(noms, album, avantRendu, videos)
  local renditions = {}
  for i, nom in ipairs(noms) do
    local r = { destinationPath = TMP .. '/' .. nom, rendue = false }
    function r:skipRender() self.sautee = true end
    function r:waitForRender()
      assert(not self.sautee)
      if avantRendu then avantRendu(i) end
      if nom:find('echec%-rendu') then return false, 'Le filtre de post-traitement n’est pas parvenu à effectuer le rendu.' end
      self.rendue = true
      local jpeg = nom:lower():find('%.jpg$')
      local f = io.open(self.destinationPath, 'wb'); f:write((jpeg and 'JPEG-' or 'VIDEO-') .. nom); f:close()
      return true, self.destinationPath
    end
    function r:uploadFailed(m) self.echec = m end
    renditions[i] = r
  end
  local progression = setmetatable({}, { __index = function() return function() end end })
  local contexte = {
    propertyTable = { album = album or '', videos = videos },
    exportSession = { countRenditions = function() return #renditions end },
    configureProgress = function() return progression end,
    renditions = function()
      local i = 0
      return function() i = i + 1; if renditions[i] then return i, renditions[i] end end
    end,
  }
  supprimes, pauses, ouvertes, messages, confirmations = {}, {}, {}, {}, {}
  Service.processRenderedPhotos({}, contexte)
  return renditions
end

local function compter(renditions, champ)
  local n = 0
  for _, r in ipairs(renditions) do if r[champ] then n = n + 1 end end
  return n
end

local nb, echecs = 0, 0
local function verifier(nom, obtenu, attendu)
  nb = nb + 1
  if obtenu ~= attendu then
    echecs = echecs + 1
    print('ÉCHEC ' .. nom .. '\n  obtenu  : ' .. tostring(obtenu) .. '\n  attendu : ' .. tostring(attendu))
  end
end

local function noms(n, speciaux)
  local t = {}
  for i = 1, n do t[i] = speciaux[i] or string.format('20250724T1000%02d-IMG_%04d-4096 x 3072.jpg', i % 60, i) end
  return t
end

-- A. Première fois : pas de connexion, collection « Vacances Gien », 120 photos dont une que
-- Google ne reçoit pas et une qu'il refuse.
sources = { { getName = function() return 'Vacances Gien' end } }
google.albums = { { id = 'X1', title = 'Autre' }, { id = 'X2', title = 'Encore un autre' }, { id = 'X3', title = 'Troisième' } }
google.contenu.X1, google.contenu.X2, google.contenu.X3 = {}, {}, {}
reponses = { 'ok', 'ok' }   -- « Se connecter », puis « Ouvrir l'album »
local A = noms(120, { [7] = 'p007-ECHEC-ENVOI.jpg', [10] = 'p010-refus.jpg' })
local r = exporter(A)
verifier('A connexion proposée', confirmations[1] and confirmations[1].oui, 'Se connecter')
verifier('A commande', commandeExecutee, '"node "' .. parent(PLUGIN) .. '/connexion-google-photos.mjs" > "' .. LOCAL .. '/lightroom-google-photos/connexion.log" 2>&1"')
verifier('A album créé', google.albums[4] and google.albums[4].title, 'Vacances Gien')
verifier('A lots', table.concat(google.lots, ','), '50,50,19')
verifier('A dans l’album', #google.contenu.ALB4, 118)
verifier('A échecs signalés', compter(r, 'echec'), 2)
verifier('A échec envoi', r[7].echec, 'erreur 503 de Google Photos : Service Unavailable')
verifier('A échec refus', r[10].echec, 'refusée par Google Photos : Failed: There was an error while trying to create this media item.')
verifier('A reprises', table.concat(pauses, ','), '5,10')
verifier('A fichiers supprimés', #supprimes, 120)
verifier('A message', confirmations[2] and confirmations[2].texte,
  '118 photos envoyées dans l’album « Vacances Gien ».\n2 photos n’ont pas pu être envoyées (Lightroom en affiche la liste).')
verifier('A album ouvert', ouvertes[1], 'https://photos.google.com/lr/album/4')
verifier('A contenu envoyé', google.jeton1, 'JPEG-' .. A[1])

-- B. Deuxième envoi de la même collection, avec 5 photos de plus : seules les nouvelles et les
-- deux en échec partent.
google.lots = {}
reponses = { 'cancel' }
local B = noms(125, { [7] = 'p007-ECHEC-ENVOI.jpg', [10] = 'p010-refus.jpg' })
B[3] = B[3]:upper()   -- même nom à la casse près
r = exporter(B)
verifier('B pas de nouvel album', #google.albums, 4)
verifier('B sautées', compter(r, 'sautee'), 118)
verifier('B rendues', compter(r, 'rendue'), 7)
verifier('B lots', table.concat(google.lots, ','), '6')
verifier('B dans l’album', #google.contenu.ALB4, 123)
verifier('B message', confirmations[1] and confirmations[1].texte,
  '5 photos envoyées dans l’album « Vacances Gien ».\n118 photos y étaient déjà, elles n’ont pas été renvoyées.\n2 photos n’ont pas pu être envoyées (Lightroom en affiche la liste).')
verifier('B pas d’ouverture', #ouvertes, 0)

-- C. Album choisi dans la boîte d'export, plusieurs sources : pas de question.
google.lots = {}
sources = { 'kAllPhotos', { getName = function() return 'X' end } }
reponses = {}
r = exporter(noms(3, {}), '  Choisi  ')
verifier('C album', google.albums[5] and google.albums[5].title, 'Choisi')
verifier('C envoyées', #google.contenu.ALB5, 3)

-- D. Source spéciale sans album choisi : on demande le nom.
sources = { 'kAllPhotos' }
reponses = { '  Mon album  ', 'cancel' }
r = exporter(noms(2, {}))
verifier('D album demandé', google.albums[6] and google.albums[6].title, 'Mon album')

-- E. Nom demandé puis annulation : rien n'est rendu ni envoyé.
local avant = google.envois
reponses = {}
r = exporter(noms(4, {}))
verifier('E sautées', compter(r, 'sautee'), 4)
verifier('E aucun envoi', google.envois, avant)

-- F. Connexion révoquée et l'utilisateur renonce à se reconnecter.
google.refreshValide = false
sources = { { getName = function() return 'Vacances Gien' end } }
reponses = { 'cancel' }
r = exporter(noms(4, {}))
verifier('F proposée', confirmations[1] and confirmations[1].oui, 'Se connecter')
verifier('F sautées', compter(r, 'sautee'), 4)
verifier('F aucun message d’erreur', #messages, 0)
google.refreshValide = true

-- G. Envoi qui dure plus d'une heure : le jeton d'accès est renouvelé en route.
local jetonsAvant = google.jetons
reponses = { 'cancel' }
r = exporter(noms(130, {}), 'Long', function(i) if i == 60 then horloge = horloge + 3500 end end)
verifier('G jetons', google.jetons - jetonsAvant, 2)
verifier('G envoyées', #google.contenu.ALB7, 130)

-- H. Google refuse la création de l'album : message d'erreur clair.
google.statutCreation = 403
reponses = {}
r = exporter(noms(2, {}), 'Interdit')
verifier('H message', messages[1] and messages[1].texte, 'erreur 403 de Google Photos : Request had insufficient authentication scopes.')
verifier('H genre', messages[1] and messages[1].genre, 'critical')

-- I. Rendu refusé par un filtre (LR/Mogrify) : rien n'est envoyé pour cette photo, le message le dit.
google.statutCreation = 200
google.lots = {}
reponses = { 'cancel' }
r = exporter({ 'a.jpg', 'b-echec-rendu.jpg', 'c.jpg' }, 'Filtre')
verifier('I lots', table.concat(google.lots, ','), '2')
verifier('I message', confirmations[1] and confirmations[1].texte,
  '2 photos envoyées dans l’album « Filtre ».\n1 photos n’ont pas pu être préparées par Lightroom ou une action '
  .. 'de post-traitement (LR/Mogrify…) : elles n’ont pas été envoyées.')

-- J. Vidéos converties en 1080p : ffmpeg trouvé dans le dossier de winget, une vidéo HDR, une
-- vidéo illisible. Les photos partent comme avant.
local function existe(p) return lire(p) ~= nil end
local function contient(texte, morceau) return (texte or ''):find(morceau, 1, true) ~= nil end
installerFfmpeg(true)
google.lots, commandesFfmpeg = {}, {}
reponses = { 'cancel' }
local envoisAvant = google.envois
r = exporter({ 'a.jpg', '20240701T100000-IMG_0001.MOV', '20240702T100000-IMG_0002-HDR.mov', 'b.jpg', 'c-CASSEE.mov' },
  'Vidéos', nil, 'convertir')
verifier('J lots', table.concat(google.lots, ','), '4')
local albumJ = google.contenu[google.albums[#google.albums].id]
verifier('J noms dans l’album', table.concat(albumJ, ','),
  'a.jpg,20240701T100000-IMG_0001.mp4,20240702T100000-IMG_0002-HDR.mp4,b.jpg')
verifier('J contenu converti', google['jeton' .. (envoisAvant + 2)], 'MP4(VIDEO-20240701T100000-IMG_0001.MOV)')
verifier('J type photo', google['type' .. (envoisAvant + 1)], 'image/jpeg')
verifier('J type vidéo', google['type' .. (envoisAvant + 2)], 'video/mp4')
verifier('J délai photo', google['delai' .. (envoisAvant + 1)], 300)
verifier('J délai vidéo', google['delai' .. (envoisAvant + 2)], 3600)
-- ffmpeg est trouvé sans rien lancer ; ffprobe puis ffmpeg pour chaque vidéo.
verifier('J commandes', #commandesFfmpeg, 6)
local ffprobe = parent(FFMPEG_WINGET) .. '/ffprobe.exe'
verifier('J ffprobe', commandesFfmpeg[1], '""' .. ffprobe .. '" -v error -select_streams v:0 -show_entries '
  .. 'stream=color_transfer -of default=nw=1:nk=1 "' .. TMP .. '/google-photos-video-1.MOV" > "'
  .. TMP .. '/google-photos-video-1-1080p.mp4.txt" 2>&1"')
verifier('J ffmpeg SDR', commandesFfmpeg[2], '""' .. FFMPEG_WINGET .. '" -nostdin -y -loglevel error -i "'
  .. TMP .. '/google-photos-video-1.MOV" -map 0:v:0 -map 0:a:0? -map_metadata 0 '
  .. "-vf \"scale='if(gt(iw,ih),-2,trunc(min(iw,1080)/2)*2)':'if(gt(iw,ih),trunc(min(ih,1080)/2)*2,-2)'\" "
  .. '-fpsmax 30 -c:v libx264 -preset medium -crf 24 -maxrate 6M -bufsize 12M -pix_fmt yuv420p '
  .. '-c:a aac -b:a 128k -movflags +faststart "' .. TMP .. '/google-photos-video-1-1080p.mp4" > "'
  .. TMP .. '/google-photos-video-1-1080p.mp4.txt" 2>&1"')
verifier('J ffmpeg HDR ramené en SDR', contient(commandesFfmpeg[4], ',zscale=t=linear:npl=100,')
  and contient(commandesFfmpeg[4], 'tonemap=tonemap=hable') and contient(commandesFfmpeg[4], '-color_trc bt709 '), true)
verifier('J SDR sans tonemap', contient(commandesFfmpeg[2], 'tonemap'), false)
verifier('J échec conversion', r[5].echec, 'conversion de la vidéo impossible (ffmpeg : ' .. TMP
  .. '/google-photos-video-3.mov: Invalid data found when processing input).')
verifier('J message', confirmations[1] and confirmations[1].texte,
  '2 photos et 2 vidéos envoyées dans l’album « Vidéos ».\n1 photos n’ont pas pu être envoyées (Lightroom en affiche la liste).')
local restes = {}
for _, n in ipairs({ 'google-photos-video-1.MOV', 'google-photos-video-1-1080p.mp4', 'google-photos-video-1-1080p.mp4.txt',
  'google-photos-video-2.mov', 'google-photos-video-2-1080p.mp4', 'google-photos-video-3.mov',
  'google-photos-video-3-1080p.mp4', 'google-photos-video-3-1080p.mp4.txt', '20240701T100000-IMG_0001.MOV', 'a.jpg' }) do
  if existe(TMP .. '/' .. n) then restes[#restes + 1] = n end
end
verifier('J fichiers de travail supprimés', table.concat(restes, ','), '')

-- K. Nouvel envoi dans le même album : les vidéos déjà converties et envoyées ne sont ni
-- rendues ni reconverties.
google.lots, commandesFfmpeg = {}, {}
reponses = { 'cancel' }
r = exporter({ 'a.jpg', '20240701T100000-IMG_0001.MOV', '20240703T100000-IMG_0003.mov' }, 'Vidéos', nil, 'convertir')
verifier('K sautées', compter(r, 'sautee'), 2)
verifier('K une conversion', #commandesFfmpeg, 2)
verifier('K message', confirmations[1] and confirmations[1].texte,
  '0 photos et 1 vidéos envoyées dans l’album « Vidéos ».\n2 photos y étaient déjà, elles n’ont pas été renvoyées.')

-- L. ffmpeg absent (ni winget ni PATH) : les vidéos échouent avec un message clair, les photos partent.
installerFfmpeg(false)
google.lots, commandesFfmpeg = {}, {}
reponses = { 'cancel' }
r = exporter({ 'd.jpg', 'v1.mov', 'v2.mov' }, 'Sans ffmpeg', nil, 'convertir')
verifier('L recherche une fois', #commandesFfmpeg, 1)
verifier('L échec', r[2].echec, 'ffmpeg introuvable : installe-le (winget install Gyan.FFmpeg) ou choisis '
  .. 'd’envoyer les vidéos telles que Lightroom les exporte.')
verifier('L échecs', compter(r, 'echec'), 2)
verifier('L photo envoyée', table.concat(google.lots, ','), '1')
verifier('L vidéo gardée sur le disque ? non', existe(TMP .. '/v1.mov'), false)

-- M. Vidéos envoyées telles que Lightroom les exporte : pas de ffmpeg, nom et type d'origine.
google.lots, commandesFfmpeg = {}, {}
reponses = { 'cancel' }
envoisAvant = google.envois
r = exporter({ 'e.jpg', 'clip.MOV' }, 'Telles', nil, 'telles')
verifier('M pas de ffmpeg', #commandesFfmpeg, 0)
verifier('M noms', table.concat(google.contenu[google.albums[#google.albums].id], ','), 'e.jpg,clip.MOV')
verifier('M type', google['type' .. (envoisAvant + 2)], 'video/quicktime')
verifier('M contenu', google['jeton' .. (envoisAvant + 2)], 'VIDEO-clip.MOV')

-- N. Réglages imposés à Lightroom par les choix de la section « Google Photos ».
local p = { taille = '2048', videos = 'convertir', LR_size_maxWidth = 4096, LR_size_resizeType = 'wh', LR_size_doConstrain = false }
Service.updateExportSettings(p)
verifier('N taille', string.format('%s %s %s %s %s %s', tostring(p.LR_size_doConstrain), p.LR_size_resizeType,
  p.LR_size_maxWidth, p.LR_size_maxHeight, p.LR_size_units, tostring(p.LR_size_doNotEnlarge)),
  'true longEdge 2048 2048 pixels true')
verifier('N vidéos converties', string.format('%s %s %s %s', tostring(p.LR_includeVideoFiles),
  p.LR_export_videoFileHandling, p.LR_export_videoFormat, p.LR_export_videoPreset), 'true include original original')
p = { taille = 'originale', videos = 'non', LR_size_doConstrain = true, LR_size_maxWidth = 4096 }
Service.updateExportSettings(p)
verifier('N originale', tostring(p.LR_size_doConstrain) .. ' ' .. p.LR_size_maxWidth, 'false 4096')
verifier('N sans vidéos', tostring(p.LR_includeVideoFiles) .. ' ' .. p.LR_export_videoFileHandling, 'false exclude')
p = { LR_size_doConstrain = true, LR_size_maxWidth = 1500, LR_size_resizeType = 'wh', LR_export_videoFormat = 'h264' }
Service.updateExportSettings(p)   -- préréglage antérieur : champs absents
verifier('N réglages Lightroom gardés', tostring(p.LR_size_doConstrain) .. ' ' .. p.LR_size_maxWidth .. ' '
  .. p.LR_size_resizeType .. ' ' .. p.LR_export_videoFileHandling, 'true 1500 wh exclude')
p = { videos = 'telles', LR_export_videoFormat = 'h264' }
Service.updateExportSettings(p)
verifier('N vidéos telles', p.LR_export_videoFileHandling .. ' ' .. p.LR_export_videoFormat, 'include h264')
-- Les choix faits dans la boîte d'export se reportent tout de suite dans les sections de Lightroom.
local observateurs = {}
p = { addObserver = function(self, cle, f) observateurs[cle] = f end }
Service.startDialog(p)
p.taille = '1600'; observateurs.taille(p, 'taille', '1600')
verifier('N observateur taille', p.LR_size_maxWidth, 1600)
p.videos = 'convertir'; observateurs.videos(p, 'videos', 'convertir')
verifier('N observateur vidéos', p.LR_export_videoFormat, 'original')

print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
