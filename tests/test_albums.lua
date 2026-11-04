-- Recréation des albums et lecture de l'historique partagé, sans plugin Deduplicate.
local PLUGIN, SCRATCH = assert(arg[1]), assert(arg[2])
package.path = PLUGIN .. '/?.lua;' .. package.path
os.getenv = nil
local nb, echecs = 0, 0
local function verifier(nom, obtenu, attendu)
  nb = nb + 1
  if obtenu ~= attendu then
    echecs = echecs + 1
    print('ÉCHEC ' .. nom .. '\n  obtenu  : ' .. tostring(obtenu) .. '\n  attendu : ' .. tostring(attendu))
  end
end
local Epoques = require 'Epoques'
local function dateLr(texte) return Epoques.secondes(texte) - 978307200 end
-- Faux Lightroom ----------------------------------------------------------------------------
-- Le module écrit ses rapports à côté de son dossier : on le place dans le dossier temporaire du test.
local PROJET = SCRATCH .. '/projet-albums'
os.execute('mkdir "' .. PROJET:gsub('/', '\\') .. '" 2>nul')
_PLUGIN = { path = PROJET .. '/albums-google-photos.lrplugin' }
local DOSSIER = SCRATCH .. '/albums'
os.execute('mkdir "' .. DOSSIER:gsub('/', '\\') .. '" 2>nul')
local function ecrire(nom, contenu)
  local sous = nom:match('^(.*)/[^/]+$')
  if sous then os.execute('mkdir "' .. (DOSSIER .. '/' .. sous):gsub('/', '\\') .. '" 2>nul') end
  local chemin = DOSSIER .. '/' .. nom
  local f = io.open(chemin, 'wb'); f:write(contenu); f:close()
  return chemin
end

local catalogue, collections, journal, dialogues, reponses
local reponsePortee, miniaturesVoulues, boitesPortee = 'ok', nil, {}
local function motCle(nom) return { nom = nom, getName = function() return nom end } end
local function nouvelleCollection(nom, intelligente)
  local c = { nom = nom, photos = {}, localIdentifier = #collections + 1000, intelligente = intelligente }
  function c:addPhotos(liste) for _, p in ipairs(liste) do self.photos[p] = true end end
  function c:removePhotos(liste) for _, p in ipairs(liste) do self.photos[p] = nil end end
  function c:isSmartCollection() return self.intelligente or false end
  function c:getName() return self.nom end
  function c:getParent() return nil end
  function c:getPhotos() local r = {} for p in pairs(self.photos) do r[#r + 1] = p end table.sort(r, function(a, b) return a.localIdentifier < b.localIdentifier end) return r end
  collections[#collections + 1] = c
  return c
end
local ecriture = false
local function nouvellePhoto(id, chemin, champs)
  local p = { localIdentifier = id, chemin = chemin, motsCles = {}, note = 0, drapeau = 0, libelle = '', titre = '', legende = '' }
  for k, v in pairs(champs or {}) do p[k] = v end
  -- Champs de texte, par clé de Lightroom ; ville, pays, createur sont les raccourcis du test.
  p.textes = { label = p.libelle, title = p.titre, caption = p.legende, city = p.ville, country = p.pays, creator = p.createur }
  function p:getContainedCollections()
    local r = {}
    for _, c in ipairs(collections) do if c.photos[self] then r[#r + 1] = c end end
    return r
  end
  function p:getContainedPublishedCollections() return self.publiee and { {} } or {} end
  function p:addKeyword(k) assert(ecriture, 'addKeyword hors écriture'); self.motsCles[#self.motsCles + 1] = k end
  function p:setRawMetadata(cle, valeur)
    assert(ecriture, 'setRawMetadata hors écriture')
    local champ = ({ rating = 'note', pickStatus = 'drapeau', gps = 'gps' })[cle]
    if champ then self[champ] = valeur else self.textes[cle] = valeur end
  end
  return p
end

local mocks = {
  LrApplication = { activeCatalog = function() return catalogue end },
  LrDialogs = {
    confirm = function(titre, texte, action) dialogues[#dialogues + 1] = { titre = titre, texte = texte, action = action }; return table.remove(reponses, 1) or 'cancel' end,
    message = function(titre, texte) dialogues[#dialogues + 1] = { titre = titre, texte = texte } end,
    runOpenPanel = function() return { DOSSIER .. '/photos-albums-test.csv' } end,
    -- Boîte de portée de « Fusionner les doublons » : on garde ses paramètres et on répond comme l'utilisateur.
    presentModalDialog = function(args)
      boitesPortee[#boitesPortee + 1] = args
      if miniaturesVoulues ~= nil then args.contents.bind_to_object.miniatures = miniaturesVoulues end
      return reponsePortee
    end,
  },
  LrBinding = { makePropertyTable = function() return {} end },
  LrView = {
    osFactory = function() return setmetatable({}, { __index = function() return function(_, t) return t end end }) end,
    bind = function(cle) return cle end,
  },
  LrHttp = { openUrlInBrowser = function(url) journal[#journal + 1] = 'navigateur ' .. url end },
  LrFunctionContext = { callWithContext = function(_, f) return f({}) end },
  LrPathUtils = {
    child = function(a, b) return a .. '/' .. b end,
    parent = function(p) return p:match('^(.*)[/\\][^/\\]+$') end,
    removeExtension = function(p) return (p:gsub('%.[^%./\\]*$', '')) end,
    leafName = function(p) return p:match('[^/\\]+$') end,
  },
  LrProgressScope = function() return setmetatable({}, { __index = function(_, k)
    if k == 'isCanceled' then return function() return false end end
    return function() end
  end }) end,
  LrShell = { revealInShell = function(p) journal[#journal + 1] = 'révéler ' .. p end },
  LrTasks = { pcall = pcall, yield = function() end, startAsyncTask = function(f) f() end, sleep = function() end },
  LrMD5 = { digest = function(s) return 'md5[' .. s .. ']' end },
  LrDate = { currentTime = function() return 0 end, timeToUserFormat = function() return '2026-10-27 14:05' end },
  LrFileUtils = {
    exists = function(p) local f = io.open(p, 'rb'); if f then f:close(); return 'file' end return false end,
    fileAttributes = function(p) local f = io.open(p, 'rb'); if not f then return nil end local t = f:seek('end'); f:close(); return { fileSize = t } end,
    readFile = function(p) local fh = assert(io.open(p, 'rb'), 'Could not open file for reading: ' .. p); local o = fh:read('*a'); fh:close(); return o end,
    chooseUniqueFileName = function(p)
      local candidat, i = p, 1
      while true do
        local f = io.open(candidat, 'rb')
        if not f then return candidat end
        f:close(); i = i + 1; candidat = p .. '-' .. i
      end
    end,
    move = function(src, dest)
      local f = io.open(dest, 'rb')
      if f then f:close(); return false, 'destination existante' end
      return os.rename(src, dest)
    end,
    delete = function(p) os.remove(p) end,
    createAllDirectories = function(p) os.execute('mkdir "' .. p:gsub('/', '\\') .. '" 2>nul') end,
  },
}
function import(nom) return assert(mocks[nom], 'module inconnu : ' .. nom) end

-- Empreintes ------------------------------------------------------------------------------
local Empreintes = require 'Empreintes'
local function segment(marqueur, donnees)
  local n = #donnees + 2
  return '\255' .. string.char(marqueur) .. string.char(math.floor(n / 256), n % 256) .. donnees
end
local function jpeg(xmp, image)
  return '\255\216' .. segment(0xE0, 'JFIF\0') .. segment(0xE1, 'http://ns.adobe.com/xap/1.0/\0' .. xmp)
    .. segment(0xDA, 'SOS') .. image .. '\255\217'
end
local function boiteIso(genre, donnees)
  local n = #donnees + 8
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) .. genre .. donnees
end
local function heic(meta, image) return boiteIso('ftyp', 'heicmif1') .. boiteIso('meta', meta) .. boiteIso('mdat', image) end

local J1 = jpeg('<xmp note="2"/>', 'PIXELS-A')
local J2 = jpeg('<xmp note="5" plus="long"/>', 'PIXELS-A')
local J3 = jpeg('<xmp note="2"/>', 'PIXELS-B')
verifier('jpeg : XMP différent, même image', Empreintes.empreinteContenu(J1) == Empreintes.empreinteContenu(J2), true)
verifier('jpeg : image différente', Empreintes.empreinteContenu(J1) == Empreintes.empreinteContenu(J3), false)
verifier('heic : meta différent, même mdat', Empreintes.empreinteContenu(heic('EXIF-1', 'IMG')) == Empreintes.empreinteContenu(heic('EXIF-2-plus-long', 'IMG')), true)
verifier('heic : mdat différent', Empreintes.empreinteContenu(heic('EXIF', 'IMG-1')) == Empreintes.empreinteContenu(heic('EXIF', 'IMG-2')), false)
verifier('autre format : tout le fichier', Empreintes.empreinteContenu('RIFF....AVI1'), 'brut:md5[RIFF....AVI1]')
verifier('jpeg tronqué', Empreintes.empreinteContenu('\255\216\255\225\0'):sub(1, 5), 'brut:')

local function photoTaille(chemin)
  local fh = io.open(chemin, 'rb')
  local n = fh and fh:seek('end') or 0
  if fh then fh:close() end
  return n
end
local function nouveauCatalogue(photos)
  collections = {}
  journal, dialogues = {}, {}
  catalogue = { photos = photos }
  function catalogue:getAllPhotos() return self.photos end
  -- Sélection : liste de photos (nil = rien de sélectionné). Comme dans Lightroom, getTargetPhotos renvoie
  -- toute la grille quand rien n'est sélectionné, et getMultipleSelectedOrAllPhotos toute la grille tant
  -- qu'il y a moins de deux photos sélectionnées.
  function catalogue:getTargetPhoto() return self.selection and self.selection[1] or nil end
  function catalogue:getTargetPhotos() return self.selection or self.photos end
  function catalogue:getMultipleSelectedOrAllPhotos()
    if self.selection and #self.selection > 1 then return self.selection end
    return self.photos
  end
  function catalogue:getActiveSources() return { { getName = function() return 'Dossier test' end } } end
  function catalogue:batchGetRawMetadata(lot)
    local r = {}
    for _, p in ipairs(lot) do
      local f = io.open(p.chemin, 'rb'); local taille = f and f:seek('end'); if f then f:close() end
      if p.poidsAbsent then taille = nil end
      r[p] = { path = p.chemin, fileSize = taille, dateTimeOriginal = p.date, isVirtualCopy = p.virtuelle or false,
        countVirtualCopies = p.nbVirtuelles or 0, rating = p.note, pickStatus = p.drapeau, keywords = p.motsCles, gps = p.gps,
        width = p.largeur, height = p.hauteur, dimensions = p.dimensions, masterPhoto = p.maitre,
        isVideo = p.video, fileFormat = p.format, durationInSeconds = p.duree }
    end
    return r
  end
  function catalogue:batchGetFormattedMetadata(lot)
    local r = {}
    for _, p in ipairs(lot) do
      r[p] = { fileName = p.chemin:match('[^/\\]+$') }
      for k, v in pairs(p.textes) do r[p][k] = v end
    end
    return r
  end
  function catalogue:findPhotos(args)
    assert(args.searchDesc.criteria == 'hasAdjustments' and args.searchDesc.operation == 'isTrue')
    local r = {}
    for _, p in ipairs(self.photos) do if p.retouchee then r[#r + 1] = p end end
    return r
  end
  function catalogue:withWriteAccessDo(_, f)
    ecriture = true; local ok, erreur = pcall(f); ecriture = false
    if not ok then error(erreur, 0) end
  end
  function catalogue:createCollection(nom)
    assert(ecriture, 'createCollection hors écriture')
    for _, c in ipairs(collections) do if c.nom == nom then return c end end
    return nouvelleCollection(nom)
  end
  function catalogue:createCollectionSet(nom) return { nom = nom } end
  function catalogue:getChildCollections()
    local r = {}
    for _, c in ipairs(collections) do r[#r + 1] = c end
    return r
  end
  function catalogue:setActiveSources(s) journal[#journal + 1] = 'source ' .. s[1].nom end
  function catalogue:findPhotoByPath(chemin) for _, p in ipairs(self.photos) do if p.chemin == chemin then return p end end end
  function catalogue:addPhoto(chemin)
    assert(ecriture, 'addPhoto hors écriture')
    local p = nouvellePhoto(#self.photos + 1, chemin)
    self.photos[#self.photos + 1] = p
    journal[#journal + 1] = 'import ' .. chemin
    return p
  end
  return catalogue
end


local MARQUEUR = '# historique-commun-deduplicate-google-v1\r\n'
local HISTORIQUE = PROJET .. '/photos-traitees.txt'
local function historique(texte)
  local f = assert(io.open(HISTORIQUE, 'wb')); assert(f:write(texte)); assert(f:close())
end
local function contenuHistorique()
  return mocks.LrFileUtils.readFile(HISTORIQUE)
end
historique(MARQUEUR)
-- Recréation des albums : un fichier téléchargé dont l'image est déjà au catalogue (XMP
-- différent) n'est pas réimporté.
local csv = DOSSIER .. '/photos-albums-test.csv'
local fc = io.open(csv, 'wb')
fc:write('\239\187\191album;fichier;date_prise_de_vue;id_photo\r\n')
fc:write('2005.12.24 Noël;CIMG0638.JPG;2005-12-24 19:15:34;ID1\r\n')   -- date corrigée dans Google : pas de correspondance
fc:write('2005.12.24 Noël;NOUVELLE.JPG;2005-12-24 20:00:00;ID2\r\n')
fc:close()
local telechargee = ecrire('photos-albums-test-manquantes/CIMG0638.JPG', jpeg('<google/>', 'PIXELS-CIMG0638'))
local nouvelle = ecrire('photos-albums-test-manquantes/NOUVELLE.JPG', jpeg('<google/>', 'PIXELS-NOUVELLE'))
local fm = io.open(DOSSIER .. '/photos-albums-test-manquantes/telechargements.csv', 'wb')
fm:write('album;fichier;date_prise_de_vue;id_photo;fichier_telecharge\r\n')
fm:write('2005.12.24 Noël;CIMG0638.JPG;2005-12-24 19:15:34;ID1;' .. telechargee .. '\r\n')
fm:write('2005.12.24 Noël;NOUVELLE.JPG;2005-12-24 20:00:00;ID2;' .. nouvelle .. '\r\n')
fm:close()
local original = ecrire('archives/051224. Noël 2005/CIMG0638.JPG', jpeg('<lightroom note="3" long="oui"/>', 'PIXELS-CIMG0638'))
local photoOriginale = nouvellePhoto(100, original, { date = dateLr('2005-01-07 19:15:34') })
nouveauCatalogue({ photoOriginale })
dofile(PLUGIN .. '/RecreerAlbums.lua')
local imports = {}
for _, l in ipairs(journal) do if l:find('^import ') then imports[#imports + 1] = l end end
verifier('un seul import', #imports, 1)
verifier('import de la nouvelle', imports[1], 'import ' .. nouvelle)
local albumNoel
for _, c in ipairs(collections) do if c.nom and c.nom:find('Noël') and c.photos[photoOriginale] then albumNoel = c end end
verifier('album avec la photo d’origine', albumNoel ~= nil, true)
local bilan = dialogues[#dialogues] and dialogues[#dialogues].texte or ''
verifier('bilan déjà présentes', bilan:match('(%d+) photos téléchargées étaient déjà au catalogue'), '1')
verifier('bilan importées', bilan:match('(%d+) photos importées'), '1')
verifier('pas d’erreur interne', bilan:match('erreurs internes'), nil)

-- Albums et copies retirées : la copie en trop (dans « Doublons à retirer ») est placée la première
-- dans le catalogue, donc c'est elle que la correspondance prendrait ; elle doit être ignorée, et
-- l'époque ne doit pas la reprendre non plus.
local fc2 = io.open(csv, 'wb')
fc2:write('\239\187\191album;fichier;date_prise_de_vue;id_photo\r\n')
fc2:write('2006.01.02 Gien;DUP.JPG;2006-01-02 10:00:00;ID3\r\n')
fc2:close()
local dupA = ecrire('archives/desordre/DUP.JPG', jpeg('<a/>', 'PIXELS-DUP'))
local dupB = ecrire('archives/060102. Gien/DUP.JPG', jpeg('<b/>', 'PIXELS-DUP'))
local d2006 = dateLr('2006-01-02 10:00:00')
local photoA = nouvellePhoto(200, dupA, { date = d2006 })
local photoB = nouvellePhoto(201, dupB, { date = d2006 })
nouveauCatalogue({ photoA, photoB })
local enTrop = nouvelleCollection('Doublons à retirer')
enTrop.photos[photoA] = true
dofile(PLUGIN .. '/RecreerAlbums.lua')
local albumGien, epoqueGien
for _, c in ipairs(collections) do
  if c.nom and c.nom:find('Gien') and c.nom:find('2006%-01%-02') then
    if c.photos[photoB] then albumGien = albumGien or c end
  end
end
verifier('album : la copie gardée est dans l’album', albumGien ~= nil, true)
verifier('album : la copie en trop n’y est pas', albumGien and albumGien.photos[photoA], nil)
local retourDansUneCollection = false
for _, c in ipairs(collections) do
  if c ~= enTrop and c.photos[photoA] then retourDansUneCollection = true end
end
verifier('la copie en trop n’est dans aucune collection (albums, époques)', retourDansUneCollection, false)
local bilan2 = dialogues[#dialogues] and dialogues[#dialogues].texte or ''
verifier('bilan : copies en trop ignorées', bilan2:match('(%d+) photos en trop des collections'), '1')


-- L'historique reste la seule source d'exclusion après le retrait des collections Deduplicate.
local exclusion = 'doublon\t' .. dupA .. '\tDUP.JPG\t2006-01-02 10:00:00\r\n'
historique(MARQUEUR .. exclusion)
nouveauCatalogue({ photoA, photoB })
dofile(PLUGIN .. '/RecreerAlbums.lua')
for _, c in ipairs(collections) do
  verifier('historique : copie écartée absente des albums et époques', c.photos[photoA], nil)
end
verifier('historique : aucune écriture par Google Photos', contenuHistorique(), MARQUEUR .. exclusion)

-- Une photo écartée et retirée du catalogue ne doit pas revenir par un téléchargement.
nouveauCatalogue({})
dofile(PLUGIN .. '/RecreerAlbums.lua')
verifier('historique : aucun réimport', #catalogue.photos, 0)
verifier('historique : exclusion signalée', dialogues[#dialogues].texte:find('1 lignes ignorées selon', 1, true) ~= nil, true)
verifier('historique : miroir conservé après réimport évité', contenuHistorique(), MARQUEUR .. exclusion)

-- Les collections Rafales à retirer sont également exclues.
historique(MARQUEUR)
nouveauCatalogue({ photoA, photoB })
local rafales = nouvelleCollection('Rafales à retirer')
rafales.photos[photoA] = true
dofile(PLUGIN .. '/RecreerAlbums.lua')
for _, c in ipairs(collections) do
  if c ~= rafales then verifier('rafales : copie écartée absente des albums et époques', c.photos[photoA], nil) end
end

-- Sans migration de l'historique par Deduplicate, aucune modification du catalogue.
for _, texte in ipairs({ '', '# ancien historique\r\n' }) do
  historique(texte)
  nouveauCatalogue({ photoB })
  dofile(PLUGIN .. '/RecreerAlbums.lua')
  verifier('historique non initialisé : pas de collections créées', #collections, 0)
  verifier('historique non initialisé : message explicite',
    dialogues[#dialogues].texte:find('Historique partagé non initialisé', 1, true) ~= nil, true)
  verifier('historique non initialisé : fichier conservé', contenuHistorique(), texte)
end
assert(os.remove(HISTORIQUE))
nouveauCatalogue({ photoB })
dofile(PLUGIN .. '/RecreerAlbums.lua')
verifier('historique absent : pas de collections créées', #collections, 0)
verifier('historique absent : message explicite',
  dialogues[#dialogues].texte:find('Historique partagé non initialisé', 1, true) ~= nil, true)
verifier('historique absent : fichier non créé par Google Photos', mocks.LrFileUtils.exists(HISTORIQUE), false)

print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
