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
mocks.LrPathUtils = {
  child = function(a, b) return a .. '/' .. b end, parent = parent, leafName = feuille,
  getStandardFilePath = function(nom) assert(nom == 'home'); return HOME end,
}
mocks.LrFileUtils = {
  exists = function(p) local f = io.open(p, 'rb'); if f then f:close(); return 'file' end; return false end,
  delete = function(p) os.remove(p); supprimes[#supprimes + 1] = p end,
  createAllDirectories = function() end,
}
mocks.LrTasks = {
  pcall = pcall,
  sleep = function(s) pauses[#pauses + 1] = s end,
  execute = function(commande)
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
  post = function(url, corps, entetes, methode) return routeur(methode or 'POST', url, corps, entetes) end,
  openUrlInBrowser = function(url) ouvertes[#ouvertes + 1] = url end,
}

function import(nom) return assert(mocks[nom], 'module inconnu : ' .. nom) end
Json = require 'Json'
local Service = require 'ServiceGooglePhotos'

-- Faux export --------------------------------------------------------------------------------
local function exporter(noms, album, avantRendu)
  local renditions = {}
  for i, nom in ipairs(noms) do
    local r = { destinationPath = TMP .. '/' .. nom, rendue = false }
    function r:skipRender() self.sautee = true end
    function r:waitForRender()
      assert(not self.sautee)
      if avantRendu then avantRendu(i) end
      if nom:find('echec%-rendu') then return false, 'Le filtre de post-traitement n’est pas parvenu à effectuer le rendu.' end
      self.rendue = true
      local f = io.open(self.destinationPath, 'wb'); f:write('JPEG-' .. nom); f:close()
      return true, self.destinationPath
    end
    function r:uploadFailed(m) self.echec = m end
    renditions[i] = r
  end
  local progression = setmetatable({}, { __index = function() return function() end end })
  local contexte = {
    propertyTable = { album = album or '' },
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

print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
