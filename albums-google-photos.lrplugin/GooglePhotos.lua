-- Accès à Google Photos par l'API officielle (« Library API »), pour le service d'export.
--
-- Depuis mars 2025, l'API ne donne plus accès à toute la photothèque : elle permet d'envoyer des
-- photos et de créer des albums, mais ne relit que les albums et les photos créés par
-- l'application elle-même. Un album fait à la main dans Google Photos ne peut donc pas être
-- complété : le service crée ses propres albums.
--
-- La connexion (identifiants du client OAuth et jeton de renouvellement) est enregistrée par
-- connexion-google-photos.mjs, dans le dossier du projet, que ce module lance au besoin.

local LrDate = import 'LrDate'
local LrFileUtils = import 'LrFileUtils'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Json = require 'Json'

local M = {}

local API = 'https://photoslibrary.googleapis.com/v1/'
local ADRESSE_JETON = 'https://oauth2.googleapis.com/token'
-- %LOCALAPPDATA%, où connexion-google-photos.mjs enregistre la connexion. Lightroom ne donne pas
-- accès aux variables d'environnement (os.getenv) : on part du dossier personnel.
local DOSSIER_CONNEXION = LrPathUtils.child(
  LrPathUtils.child(LrPathUtils.child(LrPathUtils.getStandardFilePath('home'), 'AppData'), 'Local'),
  'lightroom-google-photos')
local FICHIER_CONNEXION = LrPathUtils.child(DOSSIER_CONNEXION, 'google-photos.json')
-- Le module est dans le dossier du projet, à côté des scripts Node.
local SCRIPT_CONNEXION = LrPathUtils.child(LrPathUtils.parent(_PLUGIN.path), 'connexion-google-photos.mjs')

local function encoderUrl(texte)
  return (texte:gsub('[^%w%-%._~]', function(c) return string.format('%%%02X', c:byte()) end))
end

local function lireFichier(chemin)
  local f = io.open(chemin, 'rb')
  if not f then return nil end
  local contenu = f:read('*a')
  f:close()
  return contenu
end

-- Requête HTTP, avec deux nouvelles tentatives si Google ne répond pas, est indisponible ou
-- demande de ralentir. Renvoie le corps de la réponse et le statut HTTP. delai : en secondes.
local function requete(methode, adresse, corps, entetes, delai)
  for essai = 1, 3 do
    local reponse, infos
    if methode == 'GET' then
      reponse, infos = LrHttp.get(adresse, entetes, 120)
    else
      reponse, infos = LrHttp.post(adresse, corps, entetes, methode, delai or 300)
    end
    local statut = infos and infos.status
    local panne = not infos or infos.error
    if essai == 3 or not (panne or statut == 429 or (statut and statut >= 500)) then
      if panne then
        local detail = infos and infos.error and (infos.error.name or infos.error.errorCode)
        error('Google Photos ne répond pas (' .. tostring(detail or 'erreur réseau') .. ').', 0)
      end
      return reponse, statut
    end
    LrTasks.sleep(5 * essai)
  end
end

-- Message d'erreur lisible à partir d'une réponse de Google.
local function messageErreur(reponse, statut)
  local ok, json = LrTasks.pcall(Json.decoder, reponse)
  local detail = nil
  if ok and type(json) == 'table' then
    detail = json.error_description or (type(json.error) == 'table' and json.error.message) or json.error
  elseif type(reponse) == 'string' and reponse ~= '' then
    detail = reponse:sub(1, 300)
  end
  return string.format('erreur %s de Google Photos%s', tostring(statut), detail and (' : ' .. tostring(detail)) or '')
end

-- Connexion -----------------------------------------------------------------------------

function M.connexionEnregistree()
  return LrFileUtils.exists(FICHIER_CONNEXION) == 'file'
end

-- Lance connexion-google-photos.mjs, qui ouvre le navigateur sur la page de Google, et attend
-- qu'il ait fini (10 minutes au plus). Lève une erreur avec ce qu'a écrit le script s'il échoue.
function M.lancerConnexion()
  if not LrFileUtils.exists(SCRIPT_CONNEXION) then
    error('script de connexion introuvable : ' .. SCRIPT_CONNEXION, 0)
  end
  LrFileUtils.createAllDirectories(DOSSIER_CONNEXION)
  local journal = LrPathUtils.child(DOSSIER_CONNEXION, 'connexion.log')
  -- Guillemets autour de toute la commande : cmd.exe retire la première et la dernière.
  local commande = string.format('"node "%s" > "%s" 2>&1"', SCRIPT_CONNEXION, journal)
  if LrTasks.execute(commande) ~= 0 then
    error('la connexion à Google Photos a échoué.\n\n' .. (lireFichier(journal) or ''), 0)
  end
end

-- Client ---------------------------------------------------------------------------------

local Client = {}
Client.__index = Client

-- Nouveau jeton d'accès (valable une heure). Renvoie false si Google a révoqué la connexion ou
-- l'a laissée expirer : il faut alors la refaire.
function Client:renouveler()
  local c = self.connexion
  local corps = table.concat({
    'client_id=' .. encoderUrl(c.client_id),
    'client_secret=' .. encoderUrl(c.client_secret),
    'refresh_token=' .. encoderUrl(c.refresh_token),
    'grant_type=refresh_token',
  }, '&')
  local reponse, statut = requete('POST', ADRESSE_JETON, corps,
    { { field = 'Content-Type', value = 'application/x-www-form-urlencoded' } })
  local ok, json = LrTasks.pcall(Json.decoder, reponse)
  if statut == 400 and ok and json.error == 'invalid_grant' then return false end
  if statut ~= 200 or not ok or not json.access_token then error(messageErreur(reponse, statut), 0) end
  self.jetonAcces = json.access_token
  self.expiration = LrDate.currentTime() + (json.expires_in or 3600)
  return true
end

function Client:jeton()
  -- Un envoi peut durer plus d'une heure.
  if LrDate.currentTime() > self.expiration - 300 and not self:renouveler() then
    error('Google a coupé la connexion pendant l’envoi.', 0)
  end
  return self.jetonAcces
end

-- Appel de l'API ; donnees (table) est envoyé en JSON. Renvoie la réponse décodée.
function Client:appeler(methode, chemin, donnees)
  local entetes = { { field = 'Authorization', value = 'Bearer ' .. self:jeton() } }
  local corps = nil
  if donnees then
    corps = Json.encoder(donnees)
    table.insert(entetes, { field = 'Content-Type', value = 'application/json; charset=utf-8' })
  end
  local reponse, statut = requete(methode, API .. chemin, corps, entetes)
  if not statut or statut < 200 or statut >= 300 then error(messageErreur(reponse, statut), 0) end
  return Json.decoder(reponse)
end

-- Premier album créé par l'application qui porte ce titre, ou nil.
function Client:trouverAlbum(titre)
  local page = nil
  repeat
    local reponse = self:appeler('GET', 'albums?pageSize=50&excludeNonAppCreatedData=true'
      .. (page and ('&pageToken=' .. encoderUrl(page)) or ''))
    for _, album in ipairs(reponse.albums or {}) do
      if album.title == titre then return album end
    end
    page = reponse.nextPageToken
  until not page
  return nil
end

-- Renvoie l'album créé (id, title, productUrl…).
function Client:creerAlbum(titre)
  return self:appeler('POST', 'albums', { album = { title = titre } })
end

-- Noms de fichier (en minuscules) des photos de l'album, pour ne pas les envoyer deux fois.
function Client:nomsDansAlbum(idAlbum)
  local noms, page = {}, nil
  repeat
    local reponse = self:appeler('POST', 'mediaItems:search', { albumId = idAlbum, pageSize = 100, pageToken = page })
    for _, element in ipairs(reponse.mediaItems or {}) do
      if element.filename then noms[element.filename:lower()] = true end
    end
    page = reponse.nextPageToken
  until not page
  return noms
end

-- Type MIME annoncé à Google, d'après l'extension du fichier.
local TYPES = {
  jpg = 'image/jpeg', jpeg = 'image/jpeg',
  mp4 = 'video/mp4', m4v = 'video/x-m4v', mov = 'video/quicktime', avi = 'video/x-msvideo',
  mts = 'video/mp2t', m2ts = 'video/mp2t', ['3gp'] = 'video/3gpp', mpg = 'video/mpeg', mpeg = 'video/mpeg',
}

function M.typeMime(nom)
  return TYPES[(nom:match('%.([^.]+)$') or ''):lower()]
end

-- Envoie un fichier (photo JPEG ou vidéo). Renvoie le jeton d'envoi à passer ensuite à ajouterAAlbum.
function Client:envoyer(chemin)
  local octets = lireFichier(chemin)
  if not octets then error('fichier illisible : ' .. chemin, 0) end
  local entetes = {
    { field = 'Authorization', value = 'Bearer ' .. self:jeton() },
    { field = 'Content-Type', value = 'application/octet-stream' },
    { field = 'X-Goog-Upload-Protocol', value = 'raw' },
  }
  local typeMime = M.typeMime(chemin)
  if typeMime then table.insert(entetes, { field = 'X-Goog-Upload-Content-Type', value = typeMime }) end
  -- Une vidéo peut peser plusieurs centaines de mégaoctets.
  local delai = (typeMime or ''):find('^image/') and 300 or 3600
  local reponse, statut = requete('POST', API .. 'uploads', octets, entetes, delai)
  if statut ~= 200 or not reponse or reponse == '' then error(messageErreur(reponse, statut), 0) end
  return reponse
end

M.TAILLE_LOT = 50   -- maximum accepté par mediaItems:batchCreate

-- Crée les photos envoyées dans l'album. elements : { { jeton, nom }… } (TAILLE_LOT au plus).
-- Renvoie une table indice → message d'erreur, pour les éléments que Google a refusés.
function Client:ajouterAAlbum(idAlbum, elements)
  local nouveaux = {}
  for i, e in ipairs(elements) do
    nouveaux[i] = { simpleMediaItem = { uploadToken = e.jeton, fileName = e.nom } }
  end
  local reponse = self:appeler('POST', 'mediaItems:batchCreate', { albumId = idAlbum, newMediaItems = nouveaux })
  local parJeton = {}
  for _, r in ipairs(reponse.newMediaItemResults or {}) do
    if r.uploadToken then parJeton[r.uploadToken] = r end
  end
  local erreurs = {}
  for i, e in ipairs(elements) do
    local r = parJeton[e.jeton]
    if not r then
      erreurs[i] = 'absente de la réponse de Google Photos'
    elseif not r.mediaItem then
      erreurs[i] = 'refusée par Google Photos' .. (r.status and r.status.message and (' : ' .. r.status.message) or '')
    end
  end
  return erreurs
end

-- Client prêt à l'emploi, ou nil s'il faut (re)faire la connexion (voir lancerConnexion).
function M.ouvrir()
  local contenu = lireFichier(FICHIER_CONNEXION)
  if not contenu then return nil end
  local ok, connexion = LrTasks.pcall(Json.decoder, contenu)
  if not ok or type(connexion) ~= 'table' or not connexion.refresh_token then return nil end
  local client = setmetatable({ connexion = connexion }, Client)
  if not client:renouveler() then return nil end
  return client
end

return M
