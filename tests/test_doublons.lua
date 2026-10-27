-- Tests de Doublons.lua et Empreintes.lua, puis simulation de FusionnerDoublons.lua et de
-- RecreerAlbums.lua avec un faux Lightroom.
local PLUGIN, SCRATCH = arg[1], arg[2]
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

local Doublons = require 'Doublons'
local Epoques = require 'Epoques'
local function dateLr(texte) return Epoques.secondes(texte) - 978307200 end

-- rangDossier -----------------------------------------------------------------------------
local A = 'D:\\Photographies src 2\\Archives\\'
local P = A .. '# Photos personnelles\\'
verifier('rang désordre', Doublons.rangDossier(A .. 'Désordre\\2018\\DSC02375.jpg'), 4)
verifier('rang daté', Doublons.rangDossier(P .. '201x\\2018\\2018-08-12\\DSC02375.jpg'), 2)
verifier('rang mois', Doublons.rangDossier(P .. '202x\\2024\\2024-09\\x.jpg'), 2)
verifier('rang nommé', Doublons.rangDossier(P .. '201x\\2015\\150425. Vacances au fréty\\IMG_7433.JPG'), 1)
verifier('rang année', Doublons.rangDossier(P .. '202x\\2021\\IMG.jpg'), 3)
verifier('rang décennie', Doublons.rangDossier(P .. '202x\\IMG.jpg'), 3)
verifier('rang manquantes', Doublons.rangDossier('D:\\Documents Phemios\\x\\photos-albums-tous-manquantes\\CIMG0638.JPG'), 5)
verifier('rang mal rangées', Doublons.rangDossier('C:\\DATA\\Photographies src\\Archives\\# Photos personnelles\\mal rangées\\x.jpg'), 4)
verifier('rang barres obliques', Doublons.rangDossier('D:/Photographies src 2/Archives/LNE/Labo/x.jpg'), 1)

-- ecartDossier ----------------------------------------------------------------------------
local prise = dateLr('2018-08-19 15:00:00')
verifier('écart AAMMJJ', Doublons.ecartDossier(P .. '201x\\2018\\180818. vacances à Andernos les Bains\\a.jpg', prise), 27 * 3600)
verifier('écart parent', Doublons.ecartDossier(P .. '202x\\2021\\211205. Quarante ans\\Google photos\\a.jpg', dateLr('2021-12-05 12:00:00')), 0)
verifier('écart sans date', Doublons.ecartDossier(P .. '202x\\Divers\\a.jpg', prise), math.huge)
verifier('écart date inconnue', Doublons.ecartDossier(P .. '2018-08-18\\a.jpg', nil), math.huge)

-- nomDeBase ---------------------------------------------------------------------------------
verifier('base simple', Doublons.nomDeBase('DSCF5219.JPG'), 'dscf5219')
verifier('base -2', Doublons.nomDeBase('IMG_6527-2.JPG'), 'img_6527')
verifier('base (2)', Doublons.nomDeBase('P1210938 (2).jpg'), 'p1210938')
verifier('base -2-Modifier', Doublons.nomDeBase('D:\\dossier\\DSCF5219-2-Modifier.JPG'), 'dscf5219')
verifier('base Modifier-2(1)', Doublons.nomDeBase('GF1_100623P1010190-Modifier-2(1).jpg'), 'gf1_100623p1010190')
verifier('base Modifier_stitch', Doublons.nomDeBase('P1040855-Modifier_stitch.jpg'), 'p1040855')
verifier('base - copie', Doublons.nomDeBase('photo - copie.jpg'), 'photo')
verifier('base sans extension', Doublons.nomDeBase('IMG_1'), 'img_1')
verifier('base nom tout en suffixe', Doublons.nomDeBase('-2.jpg'), '-2')
verifier('base -Modifié', Doublons.nomDeBase('DSCF5219-Modifié.JPG'), 'dscf5219')
verifier('base -MODIFIÉ', Doublons.nomDeBase('DSCF5219-MODIFIÉ.JPG'), 'dscf5219')
verifier('base -2-Modifié', Doublons.nomDeBase('DSCF5219-2-Modifié.jpg'), 'dscf5219')
verifier('base _filtered', Doublons.nomDeBase('IMG_6527_filtered.jpg'), 'img_6527')
verifier('base _filtered-2', Doublons.nomDeBase('IMG_6527_filtered-2.jpg'), 'img_6527')
verifier('base -filtered', Doublons.nomDeBase('IMG_6527-filtered.jpg'), 'img_6527')
verifier('base -Edited', Doublons.nomDeBase('IMG_6527-Edited.jpg'), 'img_6527')
verifier('base : un nom ordinaire n’est pas touché', Doublons.nomDeBase('IMG_6527_final.jpg'), 'img_6527_final')
local Similitude = require 'Similitude'
for _, nom in ipairs({ 'DSCF5219-Modifier.JPG', 'DSCF5219-Modifié.JPG', 'D:\\x\\DSCF5219-2-MODIFIÉ.jpg', 'IMG_1_filtered.jpg',
  'IMG_1-filtered.jpg', 'IMG_1-Edit.jpg', 'IMG_1-Retouche.jpg' }) do
  verifier('nom de retouche : ' .. nom, Similitude.nomRetouche(nom), true)
end
for _, nom in ipairs({ 'DSCF5219-2.JPG', 'IMG_1 (2).jpg', 'IMG_6527_final.jpg', 'filtre.jpg' }) do
  verifier('pas un nom de retouche : ' .. nom, Similitude.nomRetouche(nom), false)
end
verifier('base DxO avec date', Doublons.nomDeBase('DSCF5360-20260821-DxO_DeepPRIME XD3.jpg'), 'dscf5360')
verifier('base DxO dng', Doublons.nomDeBase('DSCF5360-20260821-DxO_DeepPRIME 3.dng'), 'dscf5360')
verifier('base DxO sans date', Doublons.nomDeBase('DSCF5360-DxO_DeepPRIME XD3.jpg'), 'dscf5360')
verifier('base DxO souligné', Doublons.nomDeBase('DSCF5360_DxO_Standard.jpg'), 'dscf5360')
verifier('base WhatsApp -Modifié horodaté', Doublons.nomDeBase('IMG-20260802-WA0003-Modifié-2026-08-02T22-37-43.jpg'), 'img-20260802-wa0003')
verifier('base WhatsApp d’origine', Doublons.nomDeBase('IMG-20260802-WA0003.jpg'), 'img-20260802-wa0003')
verifier('base -Modifier-2(1)', Doublons.nomDeBase('GF1_100623P1010190-Modifier-2(1).jpg'), 'gf1_100623p1010190')
for _, nom in ipairs({ 'DSCF5360-20260821-DxO_DeepPRIME XD3.jpg', 'DSCF5360-20260821-DxO_DeepPRIME 3.dng',
  'IMG-20260802-WA0003-Modifié-2026-08-02T22-37-43.jpg', 'DSCF5219-2-Modifier.JPG', 'DSCF5360_DxO_Standard.jpg' }) do
  verifier('retouche d’après le nom : ' .. nom, require('Similitude').nomRetouche(nom), true)
end
verifier('un nom contenant « dxo » sans marqueur n’est pas une retouche', require('Similitude').nomRetouche('dxo.jpg'), false)
verifier('suffixe 0', Doublons.longueurSuffixe('DSCF5219.JPG'), 0)
verifier('suffixe -2-Modifier', Doublons.longueurSuffixe('DSCF5219-2-Modifier.JPG'), 11)

-- decider ---------------------------------------------------------------------------------
local function copie(id, chemin, extra)
  local c = { id = id, chemin = chemin, date = prise }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end
local d = Doublons.decider({ copie(1, A .. 'Désordre\\2018\\a.jpg'), copie(2, P .. '201x\\2018\\180818. Andernos\\a.jpg') })
verifier('nommé plutôt que désordre', d.garde.id, 2)
verifier('une retirée', #d.retirees, 1)
verifier('pas à vérifier', d.aVerifier, nil)
d = Doublons.decider({ copie(1, P .. '202x\\2024\\2024-10-13\\a.jpg'), copie(2, P .. '202x\\2024\\2024-10\\2024-10-13\\a.jpg') })
verifier('le plus profond', d.garde.id, 2)
d = Doublons.decider({ copie(5, P .. '201x\\2018\\180703. juillet\\a.jpg'), copie(9, P .. '201x\\2018\\180818. vacances à Andernos\\a.jpg') })
verifier('date de dossier la plus proche', d.garde.id, 9)
d = Doublons.decider({ copie(1, P .. '201x\\2018\\180818. Andernos\\a.jpg'), copie(2, A .. 'Désordre\\2018\\a.jpg', { retouchee = true }) })
verifier('la retouchée d’abord', d.garde.id, 2)
d = Doublons.decider({ copie(1, P .. 'a\\a.jpg', { retouchee = true }), copie(2, P .. 'b\\a.jpg', { retouchee = true }) })
verifier('deux retouchées : à vérifier', d.aVerifier, 'plusieurs copies retouchées')
d = Doublons.decider({ copie(1, P .. '201x\\2018\\180818. Andernos\\a.jpg'), copie(2, A .. 'Désordre\\2018\\a.jpg', { virtuelles = 2 }) })
verifier('copies virtuelles gardées', d.garde.id, 2)
d = Doublons.decider({ copie(1, P .. '201x\\2018\\180818. Andernos\\a.jpg'), copie(2, A .. 'Désordre\\2018\\a.jpg', { publiee = true }) })
verifier('copie publiée : à vérifier', d.aVerifier, 'une copie à retirer est publiée')
d = Doublons.decider({ copie(7, P .. 'x\\a.jpg'), copie(3, P .. 'y\\a.jpg'), copie(4, P .. 'z\\a.jpg', { annotee = true }) })
verifier('annotée à égalité de dossier', d.garde.id, 4)
verifier('deux retirées', #d.retirees, 2)
d = Doublons.decider({ copie(7, P .. 'x\\a.jpg'), copie(3, P .. 'y\\a.jpg') })
verifier('sinon la première importée', d.garde.id, 3)

-- pourquoi : le premier critère qui départage la copie gardée de la suivante
d = Doublons.decider({ copie(1, P .. 'a\\a.jpg', { pixels = 1000 }), copie(2, P .. 'b\\a.jpg', { pixels = 4000 }) })
verifier('pourquoi : la plus grande image', d.pourquoi, 'la plus grande image')
d = Doublons.decider({ copie(1, P .. 'a\\a.jpg', { pixels = 4000, octets = 100 }), copie(2, P .. 'b\\a.jpg', { pixels = 4000, octets = 900, empreinte = 'x' }) })
verifier('pourquoi : le plus lourd à dimensions égales', d.pourquoi, 'le fichier le plus lourd (mêmes dimensions)')
d = Doublons.decider({ copie(1, P .. 'a\\a.jpg'), copie(2, P .. 'b\\a.jpg', { retouchee = true }) })
verifier('pourquoi : retouchée', d.pourquoi, 'retouchée dans Lightroom')
d = Doublons.decider({ copie(1, A .. 'Désordre\\2018\\a.jpg'), copie(2, P .. '201x\\2018\\180818. Andernos\\a.jpg') })
verifier('pourquoi : dossier mieux rangé', d.pourquoi, 'dossier mieux rangé')
d = Doublons.decider({ copie(1, P .. 'x\\a.jpg'), copie(2, P .. 'y\\a-2.jpg') })
verifier('pourquoi : nom sans suffixe', d.pourquoi, 'nom sans suffixe de copie')
d = Doublons.decider({ copie(9, P .. 'x\\a.jpg'), copie(3, P .. 'y\\a.jpg') })
verifier('pourquoi : la première importée', d.pourquoi, 'importée la première')
verifier('même image', d.memeImage, true)
d = Doublons.decider({ copie(1, P .. 'a\\a.jpg', { pixels = 1000, empreinte = 'a' }), copie(2, P .. 'b\\a.jpg', { pixels = 4000, empreinte = 'b' }) })
verifier('copie réduite : pas la même image', d.memeImage, false)

-- effets : ce que la fusion change
local function col(id, nom, extra) local c = { id = id, nom = nom, dynamique = false, exclue = false }; for k, v in pairs(extra or {}) do c[k] = v end; return c end
local function mot(nom) return { nom = nom, objet = 'objet:' .. nom } end
local gardee = copie(1, P .. 'a\\a.jpg', { collections = { col(1, 'Album A') }, motsCles = { mot('x') }, note = 2, drapeau = 0,
  textes = { city = '', creator = 'Moi' } })
local r1 = copie(2, A .. 'Désordre\\a.jpg', { collections = { col(1, 'Album A'), col(2, 'Album B'), col(3, 'Dynamique', { dynamique = true }),
  col(4, 'Doublons à retirer', { exclue = true }) }, motsCles = { mot('x'), mot('y') }, note = 4, drapeau = 1,
  textes = { city = 'Gien', creator = 'Autre' }, gps = { latitude = 1 } })
local r2 = copie(3, A .. 'Désordre\\b.jpg', { collections = { col(2, 'Album B'), col(5, 'Album C') }, motsCles = { mot('y'), mot('z') },
  note = 3, textes = { city = 'Orléans' }, gps = { latitude = 2 } })
local e = Doublons.effets({ garde = gardee, retirees = { r1, r2 } })
verifier('effets : collections rejointes', #e.collections, 2)
verifier('effets : Album B', e.collections[1].nom, 'Album B')
verifier('effets : Album C', e.collections[2].nom, 'Album C')
verifier('effets : collections quittées (statiques, hors corbeille)', #e.quittees, 4)
verifier('effets : mots-clés ajoutés une fois', #e.motsCles, 2)
verifier('effets : y puis z', e.motsCles[1].nom .. e.motsCles[2].nom, 'yz')
verifier('effets : note la plus haute', e.note, 4)
verifier('effets : drapeau', e.drapeau, 1)
verifier('effets : un seul texte recopié (le premier)', #e.textes, 1)
verifier('effets : ville', e.textes[1].cle .. '=' .. e.textes[1].valeur, 'city=Gien')
verifier('effets : gps de la première copie qui en a', e.gps.latitude, 1)
e = Doublons.effets({ garde = copie(1, P .. 'a\\a.jpg', { collections = {}, motsCles = {}, note = 5, drapeau = 1, textes = {}, gps = { latitude = 9 } }),
  retirees = { copie(2, P .. 'b\\a.jpg', { collections = {}, motsCles = {}, note = 3, drapeau = 1, textes = {}, gps = { latitude = 1 } }) } })
verifier('effets : rien à changer (note)', e.note, nil)
verifier('effets : rien à changer (drapeau)', e.drapeau, nil)
verifier('effets : rien à changer (gps)', e.gps, nil)

local g = Doublons.grouper({ { k = 'a' }, { k = 'b' }, { k = 'a' }, { k = nil }, { k = 'c' }, { k = 'c' } }, function(e) return e.k end)
verifier('grouper', #g, 2)
verifier('grouper ordre', g[1][1].k, 'a')

-- Faux Lightroom ----------------------------------------------------------------------------
-- Le module écrit ses rapports à côté de son dossier : on le place dans le dossier temporaire du test.
local PROJET = SCRATCH .. '/projet-doublons'
os.execute('rmdir /s /q "' .. PROJET:gsub('/', '\\') .. '" 2>nul')
os.execute('mkdir "' .. PROJET:gsub('/', '\\') .. '" 2>nul')
_PLUGIN = { path = PROJET .. '/albums-google-photos.lrplugin' }
local DOSSIER = SCRATCH .. '/doublons'
os.execute('rmdir /s /q "' .. DOSSIER:gsub('/', '\\') .. '" 2>nul')
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
    confirm = function(titre, texte) dialogues[#dialogues + 1] = { titre = titre, texte = texte }; return table.remove(reponses, 1) or 'cancel' end,
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
    readFile = function(p) local fh = io.open(p, 'rb'); if not fh then return nil end local o = fh:read('*a'); fh:close(); return o end,
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
local function boite(genre, donnees)
  local n = #donnees + 8
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) .. genre .. donnees
end
local function heic(meta, image) return boite('ftyp', 'heicmif1') .. boite('meta', meta) .. boite('mdat', image) end

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
      r[p] = { path = p.chemin, fileSize = taille, dateTimeOriginal = p.date, isVirtualCopy = p.virtuelle or false,
        countVirtualCopies = p.nbVirtuelles or 0, rating = p.note, pickStatus = p.drapeau, keywords = p.motsCles, gps = p.gps }
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
  function catalogue:withWriteAccessDo(_, f) ecriture = true; f(); ecriture = false end
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

-- Fusion ----------------------------------------------------------------------------------
-- IMG_1 : trois copies de la même image (XMP différents, nom en majuscules pour l'une) ;
-- IMG_3 : même nom et même date, mais image recompressée : pas fusionnée ;
-- R : deux copies retouchées : à vérifier ; absente : fichier introuvable.
local d1 = dateLr('2018-08-19 15:00:00')
local orig = ecrire('perso/180818. Andernos/IMG_1.jpg', jpeg('<a/>', 'PIXELS-1'))
local desordre = ecrire('desordre/2018/IMG_1.jpg', jpeg('<xmp note="4" bien="plus long"/>', 'PIXELS-1'))
local manquante = ecrire('x-manquantes/IMG_1.JPG', jpeg('<b/>', 'PIXELS-1'))
local recompressee1 = ecrire('perso/a/IMG_3.jpg', jpeg('<a/>', 'PIXELS-3-original'))
local recompressee2 = ecrire('perso/b/IMG_3.jpg', jpeg('<a/>', 'PIXELS-3-google'))
local r1 = ecrire('perso/a/R.jpg', 'RETOUCHE')
local r2 = ecrire('perso/b/R.jpg', 'RETOUCHE')
local absent = DOSSIER .. '/perso/c/IMG_1.jpg'
-- Famille DSCF_1 : l'original, une copie « -2 » (même image, XMP différent), un « -2-Modifier »
-- rendu sans changement (même image) et un « -Modifier » réellement retouché (autre image).
local dscf2 = ecrire('perso/d/DSCF_1-2.jpg', jpeg('<xmp copie="2" long="oui"/>', 'PIXELS-DSCF'))
local dscf1 = ecrire('perso/d/DSCF_1.jpg', jpeg('<a/>', 'PIXELS-DSCF'))
local dscf2m = ecrire('perso/d/DSCF_1-2-Modifier.jpg', jpeg('<m/>', 'PIXELS-DSCF'))
local dscfm = ecrire('perso/d/DSCF_1-Modifier.jpg', jpeg('<m/>', 'PIXELS-DSCF-RETOUCHES'))

-- Versions de tailles différentes. Les miniatures sont simulées ici (le vrai ImageMagick est
-- testé dans test_vignettes.lua).
local function uniforme(v) return string.rep(string.char(v), 768) end
local function decale(sig, d, n)
  local r = {}
  for i = 1, #sig do r[i] = string.char(math.min(255, sig:byte(i) + (i <= n and d or 0))) end
  return table.concat(r)
end
local miniatures = {}
local function vignette(chemin, sig, l, h) miniatures[chemin] = { signature = sig, largeur = l, hauteur = h } end
local apercusDemandes, apercusEchec = {}, {}
package.loaded['Vignettes'] = {
  magick = function() return 'magick.exe' end,
  signature = function(chemin) return miniatures[chemin] end,
  apercu = function(chemin, destination)
    apercusDemandes[#apercusDemandes + 1] = chemin
    if apercusEchec[chemin] then return nil end
    local fh = io.open(destination, 'wb')
    if not fh then return nil end
    fh:write('JPEG-APERCU')
    fh:close()
    return true
  end,
}

-- PHOTO_9 : la grande dans « desordre », une copie réduite dans un dossier nommé : on garde la grande.
local g9 = ecrire('desordre/2018/PHOTO_9.jpg', jpeg('<a/>', 'PIXELS-9-GRAND'))
local p9 = ecrire('perso/180818. Andernos/PHOTO_9-2.jpg', jpeg('<a/>', 'PIXELS-9-PETIT'))
vignette(g9, uniforme(90), 4000, 3000); vignette(p9, decale(uniforme(90), 1, 768), 1000, 750)
-- PHOTO_8 : version réduite et éclaircie : c'est une retouche, les deux sont gardées.
local g8 = ecrire('perso/f/PHOTO_8.jpg', jpeg('<a/>', 'PIXELS-8-GRAND'))
local p8 = ecrire('perso/f/PHOTO_8-2.jpg', jpeg('<a/>', 'PIXELS-8-ECLAIRCI'))
vignette(g8, uniforme(90), 4000, 3000); vignette(p8, decale(uniforme(90), 12, 768), 1000, 750)
-- PHOTO_7 : « -Modifier » à la miniature identique : le nom annonce une retouche, jamais fusionné.
local g7 = ecrire('perso/g/PHOTO_7.jpg', jpeg('<a/>', 'PIXELS-7-A'))
local p7 = ecrire('perso/g/PHOTO_7-Modifier.jpg', jpeg('<a/>', 'PIXELS-7-B'))
vignette(g7, uniforme(90), 4000, 3000); vignette(p7, uniforme(90), 4000, 3000)
-- PHOTO_6 : copie réduite retouchée dans Lightroom : le travail serait perdu, le groupe reste à vérifier.
local g6 = ecrire('perso/h/PHOTO_6.jpg', jpeg('<a/>', 'PIXELS-6-GRAND'))
local p6 = ecrire('perso/h/PHOTO_6-2.jpg', jpeg('<a/>', 'PIXELS-6-PETIT'))
vignette(g6, uniforme(90), 4000, 3000); vignette(p6, uniforme(90), 1000, 750)
-- PHOTO_5 : deux copies de la grande image (XMP différent) et une copie réduite.
local g5a = ecrire('perso/i/PHOTO_5.jpg', jpeg('<a/>', 'PIXELS-5-GRAND'))
local g5b = ecrire('desordre/2018/PHOTO_5.jpg', jpeg('<b long="oui"/>', 'PIXELS-5-GRAND'))
local p5 = ecrire('perso/i/PHOTO_5-2.jpg', jpeg('<a/>', 'PIXELS-5-PETIT'))
vignette(g5a, uniforme(90), 4000, 3000); vignette(g5b, uniforme(90), 4000, 3000); vignette(p5, uniforme(90), 1000, 750)

-- PHOTO_4 : « -Modifié » ; PHOTO_3 : « _filtered » : mêmes dimensions et miniatures identiques, mais le
-- nom annonce une retouche : jamais fusionnés.
local g4 = ecrire('perso/j/PHOTO_4.jpg', jpeg('<a/>', 'PIXELS-4-A'))
local p4 = ecrire('perso/j/PHOTO_4-Modifié.jpg', jpeg('<a/>', 'PIXELS-4-B'))
local g3 = ecrire('perso/j/PHOTO_3.jpg', jpeg('<a/>', 'PIXELS-3-A'))
local p3 = ecrire('perso/j/PHOTO_3_filtered.jpg', jpeg('<a/>', 'PIXELS-3-B'))
for _, c in ipairs({ g4, p4, g3, p3 }) do vignette(c, uniforme(90), 4000, 3000) end

-- PHOTO_2 : sortie DxO PureRAW (nom « -20260821-DxO_DeepPRIME XD3 »), miniature identique : conservée.
local g2 = ecrire('perso/k/PHOTO_2.jpg', jpeg('<a/>', 'PIXELS-2-A'))
local p2 = ecrire('perso/k/PHOTO_2-20260821-DxO_DeepPRIME XD3.jpg', jpeg('<a/>', 'PIXELS-2-DXO'))
-- IMG-…-WA0003 : retouche WhatsApp « -Modifié-<horodatage> » : conservée.
local gw = ecrire('perso/l/IMG-20260802-WA0003.jpg', jpeg('<a/>', 'PIXELS-W-A'))
local pw = ecrire('perso/l/IMG-20260802-WA0003-Modifié-2026-08-02T22-37-43.jpg', jpeg('<a/>', 'PIXELS-W-B'))
for _, c in ipairs({ g2, p2, gw, pw }) do vignette(c, uniforme(90), 4000, 3000) end
-- PHOTO_1 : deux fichiers « -Modifier » identiques dans deux dossiers : ce sont des doublons l'un de l'autre.
local m1a = ecrire('perso/m/PHOTO_1-Modifier.jpg', jpeg('<a/>', 'PIXELS-1-M'))
local m1b = ecrire('perso/n/PHOTO_1-Modifier.jpg', jpeg('<b long="oui"/>', 'PIXELS-1-M'))

apercusEchec[g7] = true   -- pas d'aperçu pour celle-là : le rapport l'indique

local photos = {
  nouvellePhoto(10, orig, { date = d1, note = 2, createur = 'Matthieu', pays = '' }),
  nouvellePhoto(11, desordre, { date = d1, note = 4, drapeau = 1, libelle = 'Rouge', titre = 'Plage', ville = 'Andernos-les-Bains', pays = 'France', createur = 'Un autre', motsCles = { motCle('Andernos') }, gps = { latitude = 44.7, longitude = -1.1 } }),
  nouvellePhoto(12, manquante, { date = d1, drapeau = -1 }),
  nouvellePhoto(13, recompressee1, { date = d1 }),
  nouvellePhoto(14, recompressee2, { date = d1 }),
  nouvellePhoto(20, r1, { date = d1 - 100, retouchee = true }),
  nouvellePhoto(21, r2, { date = d1 - 100, retouchee = true }),
  nouvellePhoto(30, absent, { date = d1 }),
  nouvellePhoto(40, dscf2, { date = d1 }),
  nouvellePhoto(41, dscf1, { date = d1 }),
  nouvellePhoto(42, dscf2m, { date = d1 }),
  nouvellePhoto(43, dscfm, { date = d1 }),
  nouvellePhoto(50, g9, { date = d1 }),
  nouvellePhoto(51, p9, { date = d1 }),
  nouvellePhoto(52, g8, { date = d1 }),
  nouvellePhoto(53, p8, { date = d1 }),
  nouvellePhoto(54, g7, { date = d1 }),
  nouvellePhoto(55, p7, { date = d1 }),
  nouvellePhoto(56, g6, { date = d1 }),
  nouvellePhoto(57, p6, { date = d1, retouchee = true }),
  nouvellePhoto(58, g5a, { date = d1 }),
  nouvellePhoto(59, g5b, { date = d1 }),
  nouvellePhoto(60, p5, { date = d1 }),
  nouvellePhoto(61, g4, { date = d1 }),
  nouvellePhoto(62, p4, { date = d1 }),
  nouvellePhoto(63, g3, { date = d1 }),
  nouvellePhoto(64, p3, { date = d1 }),
  nouvellePhoto(70, g2, { date = d1 }),
  nouvellePhoto(71, p2, { date = d1 }),
  nouvellePhoto(72, gw, { date = d1 }),
  nouvellePhoto(73, pw, { date = d1 }),
  nouvellePhoto(74, m1a, { date = d1 }),
  nouvellePhoto(75, m1b, { date = d1 }),
}
local PH = { g9 = photos[13], p9 = photos[14], g8 = photos[15], p8 = photos[16], g7 = photos[17], p7 = photos[18],
  g6 = photos[19], p6 = photos[20], g5a = photos[21], g5b = photos[22], p5 = photos[23],
  g4 = photos[24], p4 = photos[25], g3 = photos[26], p3 = photos[27],
  g2 = photos[28], p2 = photos[29], gw = photos[30], pw = photos[31], m1a = photos[32], m1b = photos[33] }
local rangReel = Doublons.rangDossier
Doublons.rangDossier = function(chemin)   -- « desordre » sans accent dans les chemins du test
  if chemin:find('desordre') then return 4 end
  return rangReel(chemin)
end
nouveauCatalogue(photos)
local album = nouvelleCollection('Google Photos - albums / Andernos')
album:addPhotos({ photos[2], photos[3] })
local epoque = nouvelleCollection('Époque Andernos')
epoque:addPhotos({ photos[1], photos[2], photos[3] })
local intelligente = nouvelleCollection('Collection dynamique', true)
intelligente:addPhotos({ photos[2] })

-- Portée : rien n'est sélectionné, le module prend toutes les photos affichées.
reponses = { 'other', 'ok' }   -- « Voir le rapport », puis « Fusionner »
dofile(PLUGIN .. '/FusionnerDoublons.lua')

verifier('une boîte de portée', #boitesPortee, 1)
local boite = boitesPortee[1] and boitesPortee[1].contents[1].title or ''
verifier('portée : aucune sélection', boite:find('Aucune sélection', 1, true) ~= nil, true)
verifier('portée : nombre de photos', boite:find('parmi les ' .. #photos .. ' photos affichées', 1, true) ~= nil, true)
verifier('portée : nom de la source', boite:find('« Dossier test »', 1, true) ~= nil, true)
verifier('portée : rien n’est modifié avant confirmation', boite:find('Rien n’est modifié', 1, true) ~= nil, true)

local texte = dialogues[1] and dialogues[1].texte or ''
verifier('dialogue de confirmation', dialogues[1] and dialogues[1].titre, 'Fusionner les doublons ?')
verifier('compte', texte:match('(%d+) groupes de copies d’une même photo'), '5')
verifier('le bilan nomme la portée', texte:match('^Parmi les %d+ photos affichées'), 'Parmi les ' .. #photos .. ' photos affichées')
verifier('copies en trop', texte:match(', (%d+) copies en trop'), '7')
verifier('dont réduites', texte:match('%(dont (%d+) copies réduites ou recompressées%)'), '2')
verifier('à vérifier', texte:match('(%d+) groupes à vérifier'), '2')
verifier('images différentes', texte:match('(%d+) groupes de photos de même nom d’origine et même date ont des versions distinctes'), '8')
verifier('images sans miniature', texte:match('(%d+) images n’ont pas pu être comparées'), '4')
verifier('ImageMagick présent', texte:match('ImageMagick est introuvable'), nil)
verifier('illisibles', texte:match('(%d+) fichiers illisibles'), nil)
verifier('« Voir le rapport » ouvre la page HTML dans le navigateur',
  journal[1] and journal[1]:match('^navigateur file:///.*/projet%-doublons/rapport%-doublons/index%.html$') ~= nil, true)
local garde = photos[1]
verifier('album repris par la gardée', album.photos[garde], true)
verifier('album quitté par la désordre', album.photos[photos[2]], nil)
verifier('album quitté par la manquante', album.photos[photos[3]], nil)
verifier('époque sans doublon', epoque.photos[photos[2]] or epoque.photos[photos[3]], nil)
verifier('époque garde', epoque.photos[garde], true)
verifier('collection dynamique intacte', intelligente.photos[photos[2]], true)
verifier('note max', garde.note, 4)
verifier('drapeau retenu', garde.drapeau, 1)
verifier('libellé', garde.textes.label, 'Rouge')
verifier('titre', garde.textes.title, 'Plage')
verifier('ville recopiée', garde.textes.city, 'Andernos-les-Bains')
verifier('pays recopié', garde.textes.country, 'France')
verifier('auteur déjà renseigné : conservé', garde.textes.creator, 'Matthieu')
verifier('mot-clé', garde.motsCles[1] and garde.motsCles[1]:getName(), 'Andernos')
verifier('gps', garde.gps and garde.gps.latitude, 44.7)
local corbeille
for _, c in ipairs(collections) do if c.nom == 'Doublons à retirer' then corbeille = c end end
verifier('corbeille créée', corbeille ~= nil, true)
verifier('corbeille contient désordre', corbeille and corbeille.photos[photos[2]], true)
verifier('corbeille contient manquante', corbeille and corbeille.photos[photos[3]], true)
verifier('recompressées non touchées', corbeille and (corbeille.photos[photos[4]] or corbeille.photos[photos[5]]), nil)
verifier('retouchées non touchées', corbeille and (corbeille.photos[photos[6]] or corbeille.photos[photos[7]]), nil)
verifier('corbeille ouverte', journal[2], 'source Doublons à retirer')
verifier('message final', dialogues[#dialogues] and dialogues[#dialogues].texte:match('^5 groupes fusionnés sur 5') ~= nil, true)
verifier('PHOTO_9 : la grande est gardée', corbeille and corbeille.photos[PH.g9], nil)
verifier('PHOTO_9 : la copie réduite est retirée', corbeille and corbeille.photos[PH.p9], true)
verifier('PHOTO_8 : réduite éclaircie conservée', corbeille and (corbeille.photos[PH.g8] or corbeille.photos[PH.p8]), nil)
verifier('PHOTO_7 : -Modifier conservé', corbeille and (corbeille.photos[PH.g7] or corbeille.photos[PH.p7]), nil)
verifier('PHOTO_6 : copie réduite retouchée conservée', corbeille and (corbeille.photos[PH.g6] or corbeille.photos[PH.p6]), nil)
verifier('PHOTO_5 : la grande rangée est gardée', corbeille and corbeille.photos[PH.g5a], nil)
verifier('PHOTO_5 : l’autre grande est retirée', corbeille and corbeille.photos[PH.g5b], true)
verifier('PHOTO_5 : la réduite est retirée', corbeille and corbeille.photos[PH.p5], true)
verifier('PHOTO_4 : -Modifié conservé', corbeille and (corbeille.photos[PH.g4] or corbeille.photos[PH.p4]), nil)
verifier('PHOTO_3 : _filtered conservé', corbeille and (corbeille.photos[PH.g3] or corbeille.photos[PH.p3]), nil)
verifier('PHOTO_2 : DxO conservé', corbeille and (corbeille.photos[PH.g2] or corbeille.photos[PH.p2]), nil)
verifier('WhatsApp : -Modifié horodaté conservé', corbeille and (corbeille.photos[PH.gw] or corbeille.photos[PH.pw]), nil)
verifier('PHOTO_1 : deux « -Modifier » identiques : un seul gardé', corbeille and corbeille.photos[PH.m1a], nil)
verifier('PHOTO_1 : l’autre est retiré', corbeille and corbeille.photos[PH.m1b], true)
verifier('DSCF : la copie au nom propre est gardée', photos[10].motsCles ~= nil and corbeille and corbeille.photos[photos[10]], nil)
verifier('DSCF : -2 retirée', corbeille and corbeille.photos[photos[9]], true)
verifier('DSCF : -2-Modifier (image identique, nom de retouche) conservé', corbeille and corbeille.photos[photos[11]], nil)
verifier('DSCF : -Modifier retouchée conservée', corbeille and corbeille.photos[photos[12]], nil)

local RAPPORT = PROJET .. '/doublons.csv'
local f = io.open(RAPPORT, 'rb')
local rapport = f and f:read('*a') or ''
if f then f:close() end
verifier('rapport garder', rapport:find('1;garder;' .. orig, 1, true) ~= nil, true)
verifier('rapport retirer', rapport:find('1;retirer;' .. desordre, 1, true) ~= nil, true)
verifier('rapport à vérifier', rapport:find('à vérifier : plusieurs copies retouchées', 1, true) ~= nil, true)
verifier('rapport non fusionné', rapport:find('D1;non fusionné;' .. recompressee1 .. ';même nom d’origine et même date, image différente', 1, true) ~= nil, true)
verifier('rapport : la version retouchée est listée', rapport:find('non fusionné;' .. dscfm, 1, true) ~= nil, true)
verifier('rapport : la copie gardée est le nom propre', rapport:find(';garder;' .. dscf1, 1, true) ~= nil, true)
verifier('rapport : réduite retirée avec ses dimensions',
  rapport:find(';retirer;' .. p9 .. ';copie réduite ou recompressée (1000x750, ', 1, true) ~= nil, true)
verifier('rapport : contre la grande', rapport:find(' contre 4000x3000, ', 1, true) ~= nil, true)
verifier('rapport : réduite éclaircie listée',
  rapport:find('non fusionné;' .. p8 .. ';1000x750 : même nom d’origine et même date, image différente', 1, true) ~= nil, true)
verifier('rapport : -Modifier listé', rapport:find('non fusionné;' .. p7 .. ';', 1, true) ~= nil, true)
verifier('rapport : -Modifié listé', rapport:find('non fusionné;' .. p4 .. ';', 1, true) ~= nil, true)
verifier('rapport : _filtered listé', rapport:find('non fusionné;' .. p3 .. ';', 1, true) ~= nil, true)
verifier('rapport : DxO listé', rapport:find('non fusionné;' .. p2 .. ';', 1, true) ~= nil, true)
verifier('rapport : WhatsApp listé', rapport:find('non fusionné;' .. pw .. ';', 1, true) ~= nil, true)
verifier('rapport : -2-Modifier à l’image identique listé comme version retouchée',
  rapport:find('non fusionné;' .. dscf2m .. ';version retouchée d’après son nom : conservée', 1, true) ~= nil, true)
verifier('rapport : l’original sans marqueur est listé aussi', rapport:find('non fusionné;' .. g2 .. ';', 1, true) ~= nil, true)
verifier('rapport : réduite retouchée à vérifier',
  rapport:find('à vérifier : une copie à retirer est retouchée ou a des copies virtuelles', 1, true) ~= nil, true)
os.remove(RAPPORT)

-- Rapport HTML : même plan que celui qui a été appliqué.
local HTML = PROJET .. '/rapport-doublons/index.html'
local fh = io.open(HTML, 'rb')
local html = fh and fh:read('*a') or ''
if fh then fh:close() end
local function compter(motif)
  local n = 0
  for _ in html:gmatch(motif) do n = n + 1 end
  return n
end
verifier('rapport HTML écrit', #html > 1000, true)
verifier('HTML : groupes à fusionner', compter('<article class="carte fusion"'), 5)
verifier('HTML : groupes à vérifier', compter('<article class="carte verifier"'), 2)
verifier('HTML : versions conservées à part', compter('<article class="carte apart"'), 8)
verifier('HTML : rien n’a été modifié', html:find('Rien n’a été modifié dans Lightroom', 1, true) ~= nil, true)
verifier('HTML : la portée', html:find('les ' .. #photos .. ' photos affichées (« Dossier test »)', 1, true) ~= nil, true)
verifier('HTML : date', html:find('2026-10-27 14:05', 1, true) ~= nil, true)
verifier('HTML : la collection où vont les copies', html:find('collection « Doublons à retirer » : rien n’est supprimé', 1, true) ~= nil, true)
verifier('HTML : pourquoi la grande est gardée', html:find('Copie gardée : la plus grande image.', 1, true) ~= nil, true)
verifier('HTML : pourquoi le nom propre est gardé', html:find('Copie gardée : nom sans suffixe de copie.', 1, true) ~= nil, true)
verifier('HTML : collection rejointe', html:find('La copie gardée rejoint 1 collection : « Google Photos - albums / Andernos »', 1, true) ~= nil, true)
verifier('HTML : collections quittées',
  html:find('Les copies retirées sortent de : « Google Photos - albums / Andernos », « Époque Andernos »', 1, true) ~= nil, true)
verifier('HTML : la collection dynamique n’est pas touchée', html:find('Collection dynamique', 1, true), nil)
verifier('HTML : mots-clés ajoutés', html:find('Mots-clés ajoutés : « Andernos »', 1, true) ~= nil, true)
verifier('HTML : note relevée', html:find('Note relevée à ★★★★', 1, true) ~= nil, true)
verifier('HTML : drapeau', html:find('Drapeau « retenue » recopié', 1, true) ~= nil, true)
verifier('HTML : ville recopiée', html:find('Ville recopié(e) : Andernos-les-Bains', 1, true) ~= nil, true)
verifier('HTML : l’auteur déjà renseigné n’est pas recopié', html:find('Auteur recopié', 1, true), nil)
verifier('HTML : position GPS', html:find('Position GPS recopiée', 1, true) ~= nil, true)
verifier('HTML : copie réduite annoncée', html:find('copie réduite ou recompressée', 1, true) ~= nil, true)
verifier('HTML : groupe à vérifier', html:find('À vérifier : plusieurs copies retouchées. <b>Rien ne sera fait pour ce groupe.</b>', 1, true) ~= nil, true)
verifier('HTML : version conservée d’après son nom', html:find('Un fichier dont le nom annonce une retouche', 1, true) ~= nil, true)
verifier('HTML : aperçu d’une photo montrée', html:find('<img src="vignettes/50-', 1, true) ~= nil, true)
verifier('HTML : photo sans aperçu', html:find('pas d’aperçu', 1, true) ~= nil, true)
verifier('HTML : l’aperçu est écrit sur le disque', io.open(PROJET .. '/rapport-doublons/vignettes/50-' .. photoTaille(g9) .. '.jpg', 'rb') ~= nil, true)
verifier('HTML : rien d’exécutable', html:find('<script>', 1, true) ~= nil and html:find('</script>', 1, true) ~= nil, true)
local nbApercus = #apercusDemandes
verifier('aperçus demandés pour chaque photo montrée', nbApercus > 20, true)

-- Relance : même proposition, rien n'est cassé.
reponses = { 'cancel' }
dialogues = {}
dofile(PLUGIN .. '/FusionnerDoublons.lua')
verifier('relance : même proposition', dialogues[1] and dialogues[1].texte:match('(%d+) groupes de copies d’une même photo'), '5')
verifier('relance : les aperçus déjà écrits ne sont pas refaits', #apercusDemandes, nbApercus + 1)   -- seule g7, sans aperçu, est retentée
-- Les copies retirées sont maintenant dans « Doublons à retirer » : la page ne doit pas croire que la copie
-- gardée doive rejoindre cette collection, ni que les copies en sortent.
fh = io.open(HTML, 'rb'); html = fh and fh:read('*a') or ''; if fh then fh:close() end
verifier('relance : la gardée ne rejoint pas la corbeille', html:find('rejoint [^<]*« Doublons à retirer »'), nil)
verifier('relance : les copies ne « sortent » pas de la corbeille', html:find('sortent de : [^<]*« Doublons à retirer »'), nil)
os.remove(RAPPORT)

-- Portée : une sélection. Seules les photos sélectionnées sont examinées, même si d'autres ont des doublons.
catalogue.selection = { PH.g9, PH.p9 }
reponses = { 'cancel' }
boitesPortee, dialogues = {}, {}
dofile(PLUGIN .. '/FusionnerDoublons.lua')
local boiteSelection = boitesPortee[1] and boitesPortee[1].contents[1].title or ''
verifier('sélection : la boîte nomme la sélection', boiteSelection:find('parmi les 2 photos sélectionnées', 1, true) ~= nil, true)
verifier('sélection : un seul groupe trouvé', dialogues[1] and dialogues[1].texte:match('(%d+) groupes de copies d’une même photo'), '1')
verifier('sélection : le bilan nomme la sélection', dialogues[1] and dialogues[1].texte:match('^Parmi les 2 photos sélectionnées') ~= nil, true)

-- Une seule photo sélectionnée : on prend toute la grille.
catalogue.selection = { PH.g9 }
boitesPortee, dialogues = {}, {}
dofile(PLUGIN .. '/FusionnerDoublons.lua')
verifier('une seule photo sélectionnée : toute la grille',
  (boitesPortee[1] and boitesPortee[1].contents[1].title or ''):find('parmi les ' .. #photos .. ' photos affichées', 1, true) ~= nil, true)
catalogue.selection = nil

-- Renoncer dans la boîte de portée : rien n'est analysé.
reponsePortee = 'cancel'
boitesPortee, dialogues = {}, {}
dofile(PLUGIN .. '/FusionnerDoublons.lua')
verifier('annulation : aucun bilan', #dialogues, 0)
reponsePortee = 'ok'

-- Sans miniatures : la page n'a pas d'image et ne demande aucun aperçu.
local avant = #apercusDemandes
miniaturesVoulues = false
reponses = { 'cancel' }
dialogues = {}
dofile(PLUGIN .. '/FusionnerDoublons.lua')
miniaturesVoulues = nil
verifier('sans miniatures : aucun aperçu demandé', #apercusDemandes, avant)
fh = io.open(HTML, 'rb'); html = fh and fh:read('*a') or ''; if fh then fh:close() end
verifier('sans miniatures : pas d’image', html:find('<img ', 1, true), nil)
verifier('sans miniatures : la page le dit', html:find('Rapport sans miniatures.', 1, true) ~= nil, true)
os.remove(RAPPORT)

-- Moins de deux photos : message.
local seule = nouvellePhoto(300, ecrire('seule/A.jpg', jpeg('<a/>', 'PIXELS-SEULE')), { date = d1 })
local sauvegarde = catalogue
nouveauCatalogue({ seule })
dofile(PLUGIN .. '/FusionnerDoublons.lua')
verifier('une seule photo : message', dialogues[1] and dialogues[1].texte:find('au moins deux photos', 1, true) ~= nil, true)
Doublons.rangDossier = rangReel

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
local enTrop = nouvelleCollection(Doublons.COLLECTION)
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

print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
