-- Tests de Doublons.lua et Empreintes.lua, puis simulation de FusionnerDoublons.lua et de
-- RecreerAlbums.lua avec un faux Lightroom.
local PLUGIN, SCRATCH, GOOGLE_PLUGIN = arg[1], arg[2], arg[3]
local UndoSimule = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/annulation_simulee.lua')
package.path = PLUGIN .. '/?.lua;' .. (GOOGLE_PLUGIN and (GOOGLE_PLUGIN .. '/?.lua;') or '') .. package.path
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

-- Proposition manuelle : un poids gonflé par les métadonnées ne prime pas sur la résolution, la note ou le nom.
local manuel = {
  copie(1, P .. 'a\\CIMG0631-001.JPG', { pixels = 12000000, octets = 9000000, note = 2 }),
  copie(2, P .. 'a\\CIMG0631.JPG', { pixels = 12000000, octets = 2000000, note = 2 }),
  copie(3, P .. 'a\\CIMG0631-2.JPG', { pixels = 3000000, octets = 12000000, note = 5 }),
}
verifier('manuel : résolutions disponibles', Doublons.classerManuellement(manuel), true)
verifier('manuel : nom simple avant poids, résolution avant note', manuel[1].id, 2)
manuel[2].note = 4
Doublons.classerManuellement(manuel)
verifier('manuel : note avant simplicité du nom', manuel[1].id, 1)
manuel[1].pixels = nil
verifier('manuel : résolution inconnue signalée', Doublons.classerManuellement(manuel), false)
verifier('manuel : sans résolution, note prioritaire au poids', manuel[1].id, 3)

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
verifier('effets : total après fusion, avec l’album déjà présent', #e.collectionsFinales, 3)
verifier('effets : l’album existant reste visible', e.collectionsFinales[1].nom, 'Album A')
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

-- Le vrai SDK lève une erreur sur un fichier absent, contrairement à l'ancien faux Lightroom.
local Historique = require 'Historique'
local cheminHistorique = PROJET .. '/historique-test.txt'
local lu, historiqueVide = pcall(Historique.lire, cheminHistorique)
verifier('historique absent : lecture sans erreur', lu, true)
verifier('historique absent : aucune entrée', lu and #historiqueVide.entrees, 0)
Historique.preparer(cheminHistorique)
Historique.ajouter(cheminHistorique, 'doublon', { { chemin = 'D:\\Photos\\copie.jpg', fichier = 'copie.jpg' } })
verifier('historique créé : copie mémorisée', Historique.contient(Historique.lire(cheminHistorique), 'D:\\Photos\\copie.jpg'), true)
Historique.preparer(cheminHistorique)
verifier('historique préparé deux fois : données conservées', #Historique.lire(cheminHistorique).entrees, 1)
Historique.ajouter(cheminHistorique, 'doublon', { { chemin = 'D:\\Photos\\autre.jpg', fichier = 'autre.jpg' } })
local avantRetablissement = mocks.LrFileUtils.readFile(cheminHistorique)
verifier('historique : rétablissement indépendant de la casse et des séparateurs',
  Historique.retablir(cheminHistorique, { 'd:/PHOTOS/COPIE.jpg' }), 1)
verifier('historique : gardée rétablie', Historique.contient(Historique.lire(cheminHistorique), 'D:\\Photos\\copie.jpg'), false)
verifier('historique : autres exclusions conservées', Historique.contient(Historique.lire(cheminHistorique), 'D:\\Photos\\autre.jpg'), true)
verifier('historique : sauvegarde avant rétablissement', mocks.LrFileUtils.readFile(cheminHistorique .. '.bak'), avantRetablissement)
verifier('historique : rétablissement répétable', Historique.retablir(cheminHistorique, { 'D:\\Photos\\copie.jpg' }), 0)
local deplacementOriginal = mocks.LrFileUtils.move
mocks.LrFileUtils.move = function(src, dest)
  if src:find('.tmp', 1, true) then return false, 'remplacement interrompu' end
  return deplacementOriginal(src, dest)
end
local avantEchec = mocks.LrFileUtils.readFile(cheminHistorique)
local retabli = pcall(Historique.retablir, cheminHistorique, { 'D:\\Photos\\autre.jpg' })
verifier('historique : échec de remplacement signalé', retabli, false)
verifier('historique : original restauré après échec', mocks.LrFileUtils.readFile(cheminHistorique), avantEchec)
mocks.LrFileUtils.move = deplacementOriginal

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
  UndoSimule.brancher(catalogue, function() return { photos, collections } end)
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
verifier('copies en trop', texte:match(', (%d+) copies en trop'), '8')
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
verifier('fusion auto : vue courante conservée', journal[2], nil)
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
verifier('DSCF : -2-Modifier retiré quand l’image est exactement identique', corbeille and corbeille.photos[photos[11]], true)
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

local Annulation = require 'Annulation'
verifier('auto : toute la fusion dans une seule étape Ctrl+Z', catalogue:nombreActions(), 1)
verifier('auto : nom de l’action Ctrl+Z', catalogue:derniereAction(), 'Fusionner les doublons')
catalogue:annuler()
Annulation.synchroniser(catalogue, PROJET .. '/photos-traitees.txt')
verifier('auto Ctrl+Z : note restaurée', garde.note, 2)
verifier('auto Ctrl+Z : ancienne copie de nouveau dans son album', album.photos[photos[2]], true)
verifier('auto Ctrl+Z : historique restauré', #Historique.lire(PROJET .. '/photos-traitees.txt').entrees, 0)
catalogue:retablir()
Annulation.synchroniser(catalogue, PROJET .. '/photos-traitees.txt')
verifier('auto Rétablir : note fusionnée', garde.note, 4)
verifier('auto Rétablir : copie remise à retirer', corbeille.photos[photos[2]], true)
verifier('auto Rétablir : historique rétabli', Historique.contient(Historique.lire(PROJET .. '/photos-traitees.txt'), desordre), true)

-- Relance : les copies mémorisées ne sont plus proposées, les groupes à vérifier restent visibles.
reponses = { 'cancel' }
dialogues = {}
dofile(PLUGIN .. '/FusionnerDoublons.lua')
verifier('relance : aucun groupe déjà fusionné proposé de nouveau', dialogues[1] and dialogues[1].texte:match('(%d+) groupes de copies d’une même photo'), '0')
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
verifier('sélection : copie déjà fusionnée ignorée', dialogues[1] and dialogues[1].texte:find('Aucun fichier en double', 1, true) ~= nil, true)
verifier('sélection : le bilan nomme la sélection', dialogues[1] and dialogues[1].texte:find('parmi les 2 photos sélectionnées', 1, true) ~= nil, true)

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
dofile(GOOGLE_PLUGIN .. '/RecreerAlbums.lua')
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
dofile(GOOGLE_PLUGIN .. '/RecreerAlbums.lua')
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

-- Fusion manuelle : historique neuf dans un projet temporaire distinct, sans toucher à l'historique réel.
local PROJET_MANUEL = SCRATCH .. '/projet-manuel'
os.execute('mkdir "' .. PROJET_MANUEL:gsub('/', '\\') .. '" 2>nul')
_PLUGIN = { path = PROJET_MANUEL .. '/albums-google-photos.lrplugin' }
local simple = ecrire('manuel/CIMG0631.JPG', 'image')
local scan = ecrire('manuel/CIMG0631-001.JPG', string.rep('metadata', 100))
local reduite = ecrire('manuel/CIMG0631-2.JPG', string.rep('metadata', 200))
local originale = nouvellePhoto(300, simple, { largeur = 4000, hauteur = 3000, note = 2, titre = 'Titre gardé' })
local numerisee = nouvellePhoto(301, scan, { largeur = 4000, hauteur = 3000, note = 2, drapeau = 1,
  ville = 'Gien', titre = 'Autre titre', motsCles = { motCle('Noël') }, gps = { latitude = 1, longitude = 2 } })
local petite = nouvellePhoto(302, reduite, { largeur = 2000, hauteur = 1500, note = 5 })
nouveauCatalogue({ numerisee, petite, originale })
catalogue.selection = { numerisee, petite, originale }
local noel = nouvelleCollection('Google Photos - albums / 2005 / Noël 2005')
local horsAlbum = nouvelleCollection('Google Photos - albums / 2005 / (hors album)')
noel.photos[originale], noel.photos[petite], horsAlbum.photos[numerisee] = true, true, true
reponses, reponsePortee, miniaturesVoulues, boitesPortee = { 'ok' }, 'ok', nil, {}
dofile(PLUGIN .. '/FusionManuelle.lua')
verifier('manuel : proposition selon dimensions, note et nom', boitesPortee[1].contents.bind_to_object.gardee, originale.localIdentifier)
verifier('manuel : les deux albums annoncés explicitement', dialogues[1].texte:find('Albums après fusion (2)', 1, true) ~= nil, true)
verifier('manuel : Noël déjà présent est annoncé', dialogues[1].texte:find(noel.nom, 1, true) ~= nil, true)
verifier('manuel : hors album ajouté est annoncé', dialogues[1].texte:find(horsAlbum.nom, 1, true) ~= nil, true)
verifier('manuel : la gardée reste dans Noël', noel.photos[originale], true)
verifier('manuel : la gardée rejoint hors album', horsAlbum.photos[originale], true)
verifier('manuel : copies retirées des albums', noel.photos[petite] or horsAlbum.photos[numerisee], nil)
verifier('manuel : note maximale fusionnée', originale.note, 5)
verifier('manuel : mot-clé fusionné', originale.motsCles[1].nom, 'Noël')
verifier('manuel : drapeau fusionné', originale.drapeau, 1)
verifier('manuel : titre déjà renseigné conservé', originale.textes.title, 'Titre gardé')
verifier('manuel : ville manquante complétée', originale.textes.city, 'Gien')
verifier('manuel : GPS manquant complété', originale.gps.latitude, 1)
local historiqueManuel = Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt')
verifier('manuel : historique absent créé', #historiqueManuel.entrees, 2)
verifier('manuel : copie retirée mémorisée', Historique.contient(historiqueManuel, scan), true)
verifier('manuel : gardée non exclue de recréer les albums', Historique.contient(historiqueManuel, simple), false)
verifier('manuel : bilan sans fausse erreur', dialogues[#dialogues].titre, 'Fusion manuelle terminée')
verifier('manuel : bilan contient aussi les deux albums', dialogues[#dialogues].texte:find('Albums après fusion (2)', 1, true) ~= nil, true)
verifier('manuel : vue courante conservée', #journal, 0)
verifier('manuel : une seule étape Ctrl+Z', catalogue:nombreActions(), 1)

-- Le suivi périodique suit réellement les changements du champ Undo sans écriture normale supplémentaire.
local demarrerTache, dormir = mocks.LrTasks.startAsyncTask, mocks.LrTasks.sleep
local suivi
mocks.LrTasks.startAsyncTask = function(f) suivi = coroutine.create(f); assert(coroutine.resume(suivi)) end
mocks.LrTasks.sleep = function() coroutine.yield() end
Annulation.demarrer(PROJET_MANUEL .. '/photos-traitees.txt')
catalogue:annuler()
assert(coroutine.resume(suivi))
verifier('manuel Ctrl+Z : note restaurée', originale.note, 2)
verifier('manuel Ctrl+Z : mot-clé ajouté retiré', #originale.motsCles, 0)
verifier('manuel Ctrl+Z : GPS restauré', originale.gps, nil)
verifier('manuel Ctrl+Z : ville restaurée', originale.textes.city, nil)
verifier('manuel Ctrl+Z : titre conservé', originale.textes.title, 'Titre gardé')
verifier('manuel Ctrl+Z : album de la copie restauré', horsAlbum.photos[numerisee], true)
verifier('manuel Ctrl+Z : ajout à l’album annulé', horsAlbum.photos[originale], nil)
verifier('manuel Ctrl+Z : collection de retrait créée supprimée', #collections, 2)
verifier('manuel Ctrl+Z : historique synchronisé automatiquement', #Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt').entrees, 0)
catalogue:retablir()
assert(coroutine.resume(suivi))
verifier('manuel Rétablir : note fusionnée', originale.note, 5)
verifier('manuel Rétablir : albums réunis', noel.photos[originale] and horsAlbum.photos[originale], true)
verifier('manuel Rétablir : historique synchronisé automatiquement', #Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt').entrees, 2)
verifier('manuel : la synchronisation ne rajoute aucune étape Undo', catalogue:nombreActions(), 1)
Annulation.arreter()
assert(coroutine.resume(suivi))
verifier('arrêt du suivi à la désactivation du module', coroutine.status(suivi), 'dead')
mocks.LrTasks.startAsyncTask, mocks.LrTasks.sleep = demarrerTache, dormir

-- Cas demandé : trois _filtered de résolutions différentes, dont des versions Lightroom retouchées.
local f1 = ecrire('force/CIMG1569_filtered-2(1).jpg', 'version retouchée 4,3 MP')
local f2 = ecrire('force/CIMG1569_filtered-2.jpg', 'copie réduite 2,8 MP')
local f3 = ecrire('force/CIMG1569_filtered.jpg', 'version simple 4,3 MP')
local versionRetouchee = nouvellePhoto(400, f1, { largeur = 2400, hauteur = 1800, note = 3, retouchee = true, nbVirtuelles = 1 })
local versionReduite = nouvellePhoto(401, f2, { largeur = 1920, hauteur = 1440, note = 3, retouchee = true, publiee = true })
local versionSimple = nouvellePhoto(402, f3, { largeur = 2400, hauteur = 1800, note = 3 })
nouveauCatalogue({ versionRetouchee, versionReduite, versionSimple })
catalogue.selection = { versionRetouchee, versionReduite, versionSimple }
local albumPraha = nouvelleCollection('Google Photos - albums / 2006 / Welcome back to Praha')
local albumEtoiles = nouvelleCollection('Google Photos - albums / Sans date / Trois étoiles')
albumPraha.photos[versionRetouchee], albumEtoiles.photos[versionReduite] = true, true
reponses, boitesPortee = { 'ok' }, {}
dofile(PLUGIN .. '/FusionManuelle.lua')
verifier('forcée : garde le nom simple parmi les 4,3 MP', boitesPortee[1].contents.bind_to_object.gardee, versionSimple.localIdentifier)
verifier('forcée : action explicitement nommée', dialogues[1].action, 'Fusionner de force')
verifier('forcée : retouches non transférées annoncées', dialogues[1].texte:find('est retouchée dans Lightroom', 1, true) ~= nil, true)
verifier('forcée : copies virtuelles non transférées annoncées', dialogues[1].texte:find('a des copies virtuelles', 1, true) ~= nil, true)
verifier('forcée : publication non transférée annoncée', dialogues[1].texte:find('collection publiée', 1, true) ~= nil, true)
verifier('forcée : fusion malgré les protections automatiques', dialogues[#dialogues].titre, 'Fusion manuelle terminée')
verifier('forcée : les deux albums sont réunis', albumPraha.photos[versionSimple] and albumEtoiles.photos[versionSimple], true)
local retraiteForcee
for _, collection in ipairs(collections) do if collection.nom == Doublons.COLLECTION then retraiteForcee = collection end end
verifier('forcée : copies retouchées mises de côté', retraiteForcee.photos[versionRetouchee] and retraiteForcee.photos[versionReduite], true)
verifier('forcée : retouches restent sur les copies au catalogue', versionRetouchee.retouchee and versionReduite.retouchee, true)
verifier('forcée : vue courante conservée', #journal, 0)

-- Régression : la gardée a déjà été écartée lors d'une opération précédente. Elle doit être rétablie.
retraiteForcee.photos[versionSimple] = true
local retraitRafales = nouvelleCollection('Rafales à retirer')
retraitRafales.photos[versionSimple] = true
Historique.ajouter(PROJET_MANUEL .. '/photos-traitees.txt', 'doublon', { { chemin = f3, fichier = 'CIMG1569_filtered.jpg' } })
reponses, dialogues = { 'ok' }, {}
dofile(PLUGIN .. '/FusionManuelle.lua')
verifier('gardée déjà écartée : sortie des doublons à retirer', retraiteForcee.photos[versionSimple], nil)
verifier('gardée déjà écartée : sortie des rafales à retirer', retraitRafales.photos[versionSimple], nil)
verifier('gardée déjà écartée : les deux autres restent à retirer',
  retraiteForcee.photos[versionRetouchee] and retraiteForcee.photos[versionReduite], true)
local nbEcartees = 0
for _ in pairs(retraiteForcee.photos) do nbEcartees = nbEcartees + 1 end
verifier('gardée déjà écartée : exactement deux copies dans la corbeille', nbEcartees, 2)
local historiqueRetabli = Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt')
verifier('gardée déjà écartée : rétablie dans l’historique', Historique.contient(historiqueRetabli, f3), false)
verifier('gardée déjà écartée : exclusions des copies préservées',
  Historique.contient(historiqueRetabli, f1) and Historique.contient(historiqueRetabli, f2), true)
verifier('gardée déjà écartée : ses albums sont préservés', albumPraha.photos[versionSimple] and albumEtoiles.photos[versionSimple], true)
verifier('gardée déjà écartée : rétablissement annoncé avant confirmation',
  dialogues[1].texte:find('sortie des collections', 1, true) ~= nil, true)
verifier('gardée déjà écartée : vérification annoncée au bilan',
  dialogues[#dialogues].texte:find('vérifiée hors des collections de retrait', 1, true) ~= nil, true)
catalogue:annuler()
Annulation.synchroniser(catalogue, PROJET_MANUEL .. '/photos-traitees.txt')
verifier('Ctrl+Z du rétablissement : appartenance initiale restaurée', retraiteForcee.photos[versionSimple], true)
verifier('Ctrl+Z du rétablissement : ancienne exclusion restaurée',
  Historique.contient(Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt'), f3), true)
catalogue:retablir()
Annulation.synchroniser(catalogue, PROJET_MANUEL .. '/photos-traitees.txt')
verifier('Rétablir la fusion : gardée de nouveau hors de la corbeille', retraiteForcee.photos[versionSimple], nil)
verifier('Rétablir la fusion : gardée de nouveau hors de l’historique',
  Historique.contient(Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt'), f3), false)

-- Les avertissements ne déclenchent aucune modification tant que la confirmation est annulée.
nouveauCatalogue({ versionRetouchee, versionReduite, versionSimple })
catalogue.selection = { versionRetouchee, versionReduite, versionSimple }
reponses = { 'cancel' }
dofile(PLUGIN .. '/FusionManuelle.lua')
verifier('forcée annulée : aucune collection créée', #collections, 0)

-- Une copie virtuelle peut être écartée ; son fichier source doit rester utilisable par les albums.
do
local maitre = nouvellePhoto(410, ecrire('force/MAITRE.JPG', 'original'), { largeur = 2400, hauteur = 1800, nbVirtuelles = 1 })
local virtuelle = nouvellePhoto(411, maitre.chemin, { largeur = 2400, hauteur = 1800, virtuelle = true, maitre = maitre, note = 5, retouchee = true })
nouveauCatalogue({ virtuelle, maitre })
catalogue.selection = { virtuelle, maitre }
reponses, boitesPortee = { 'ok' }, {}
dofile(PLUGIN .. '/FusionManuelle.lua')
verifier('forcée : original conservé avec sa copie virtuelle', boitesPortee[1].contents.bind_to_object.gardee, maitre.localIdentifier)
verifier('forcée : note de la copie virtuelle réunie sur l’original', maitre.note, 5)
verifier('forcée : copie virtuelle acceptée', dialogues[#dialogues].titre, 'Fusion manuelle terminée')
verifier('forcée : original non exclu par la copie virtuelle', Historique.contient(Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt'), maitre.chemin), false)

-- Écarter une copie virtuelle d'un autre original ne doit pas marquer son fichier comme supprimé.
local autreMaitre = nouvellePhoto(413, ecrire('force/AUTRE-ORIGINAL.JPG', 'source conservée hors sélection'),
  { largeur = 1200, hauteur = 900, nbVirtuelles = 1 })
local autreVirtuelle = nouvellePhoto(412, autreMaitre.chemin,
  { largeur = 1200, hauteur = 900, virtuelle = true, maitre = autreMaitre })
nouveauCatalogue({ maitre, autreVirtuelle, autreMaitre })
catalogue.selection = { maitre, autreVirtuelle }
reponses = { 'ok' }
dofile(PLUGIN .. '/FusionManuelle.lua')
verifier('forcée : source hors sélection non exclue par sa copie virtuelle',
  Historique.contient(Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt'), autreVirtuelle.chemin), false)

-- Garder une virtuelle ne doit pas la condamner au retrait ultérieur de son maître hors sélection.
for _, nomCorbeille in ipairs({ Doublons.COLLECTION, 'Rafales à retirer' }) do
  local originalEcarte = nouvellePhoto(420, ecrire('force/MAITRE-ECARTE.JPG', 'original hors sélection'),
    { largeur = 4000, hauteur = 3000, nbVirtuelles = 1, note = 1 })
  local virtuelleFragile = nouvellePhoto(421, originalEcarte.chemin,
    { largeur = 4000, hauteur = 3000, virtuelle = true, maitre = originalEcarte, note = 5 })
  local autreOriginal = nouvellePhoto(422, ecrire('force/AUTRE-CHOIX.JPG', 'autre original'),
    { largeur = 2000, hauteur = 1500 })
  nouveauCatalogue({ originalEcarte, virtuelleFragile, autreOriginal })
  catalogue.selection = { virtuelleFragile, autreOriginal }
  local corbeilleMaitre = nouvelleCollection(nomCorbeille)
  corbeilleMaitre.photos[originalEcarte] = true
  reponses, boitesPortee = { 'ok' }, {}
  dofile(PLUGIN .. '/FusionManuelle.lua')
  verifier(nomCorbeille .. ' : virtuelle exclue des gardées', boitesPortee[1].contents.bind_to_object.gardee,
    autreOriginal.localIdentifier)
  verifier(nomCorbeille .. ' : un seul choix sûr', #boitesPortee[1].contents[4].items, 1)
  verifier(nomCorbeille .. ' : exclusion expliquée', boitesPortee[1].contents[6].title:find('original est dans', 1, true) ~= nil, true)
  verifier(nomCorbeille .. ' : maître hors sélection laissé dans sa collection', corbeilleMaitre.photos[originalEcarte], true)
  verifier(nomCorbeille .. ' : métadonnées du maître hors sélection intactes', originalEcarte.note, 1)
  verifier(nomCorbeille .. ' : fusion sûre effectuée', dialogues[#dialogues].titre, 'Fusion manuelle terminée')

  -- Une fois son maître rétabli, la virtuelle redevient un choix valide sans modifier le maître.
  nouveauCatalogue({ originalEcarte, virtuelleFragile, autreOriginal })
  catalogue.selection = { virtuelleFragile, autreOriginal }
  reponses, boitesPortee = { 'ok' }, {}
  dofile(PLUGIN .. '/FusionManuelle.lua')
  verifier(nomCorbeille .. ' : virtuelle avec maître sain peut être gardée', boitesPortee[1].contents.bind_to_object.gardee,
    virtuelleFragile.localIdentifier)
  verifier(nomCorbeille .. ' : maître sain hors sélection intact', originalEcarte.note, 1)
end

-- Si chaque choix dépend d'un maître écarté, aucune boîte de choix vide ni écriture n'est lancée.
local premierMaitre = nouvellePhoto(430, ecrire('force/MAITRE-1.JPG', 'premier original'), { nbVirtuelles = 1 })
local secondMaitre = nouvellePhoto(431, ecrire('force/MAITRE-2.JPG', 'second original'), { nbVirtuelles = 1 })
local premiereVirtuelle = nouvellePhoto(432, premierMaitre.chemin, { virtuelle = true, maitre = premierMaitre })
local secondeVirtuelle = nouvellePhoto(433, secondMaitre.chemin, { virtuelle = true, maitre = secondMaitre })
nouveauCatalogue({ premierMaitre, secondMaitre, premiereVirtuelle, secondeVirtuelle })
catalogue.selection = { premiereVirtuelle, secondeVirtuelle }
local corbeilleDesMaitres = nouvelleCollection(Doublons.COLLECTION)
corbeilleDesMaitres.photos[premierMaitre], corbeilleDesMaitres.photos[secondMaitre] = true, true
reponses, boitesPortee = { 'ok' }, {}
dofile(PLUGIN .. '/FusionManuelle.lua')
verifier('virtuelles sans choix sûr : message clair', dialogues[#dialogues].titre, 'Fusion manuelle impossible')
verifier('virtuelles sans choix sûr : rétablissement conseillé', dialogues[#dialogues].texte:find('Rétablis', 1, true) ~= nil, true)
verifier('virtuelles sans choix sûr : pas de boîte de choix vide', #boitesPortee, 0)
verifier('virtuelles sans choix sûr : aucune action catalogue', catalogue:nombreActions(), 0)
verifier('virtuelles sans choix sûr : maîtres toujours dans leur collection',
  corbeilleDesMaitres.photos[premierMaitre] and corbeilleDesMaitres.photos[secondMaitre], true)
end

-- Une panne d'historique après écriture ne doit pas faire croire que la fusion du catalogue a échoué.
local ajoutOriginal = Historique.ecrire
Historique.ecrire = function() error('disque devenu indisponible') end
local panneGardee = nouvellePhoto(480, ecrire('panne/PANNE.JPG', 'original'))
local panneRetiree = nouvellePhoto(481, ecrire('panne/PANNE-2.JPG', 'copie'))
nouveauCatalogue({ panneGardee, panneRetiree })
catalogue.selection = { panneGardee, panneRetiree }
reponses = { 'ok' }
dofile(PLUGIN .. '/FusionManuelle.lua')
verifier('manuel : erreur tardive annoncée comme fusion effectuée', dialogues[#dialogues].titre, 'Fusion effectuée, historique non enregistré')
Historique.ecrire = ajoutOriginal
Annulation.synchroniser(catalogue, PROJET_MANUEL .. '/photos-traitees.txt')
verifier('historique indisponible : nouvelle tentative depuis l’état du catalogue',
  Historique.contient(Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt'), panneRetiree.chemin), true)

-- Une panne déjà présente doit être détectée avant la moindre modification du catalogue.
local preparationOriginale = Historique.preparer
Historique.preparer = function() error('historique non accessible') end
nouveauCatalogue({ originale, numerisee })
catalogue.selection = { numerisee, originale }
reponses = { 'ok' }
dofile(PLUGIN .. '/FusionManuelle.lua')
verifier('manuel : précontrôle avant création de collection', #collections, 0)
verifier('manuel : étape de précontrôle explicite', dialogues[#dialogues].texte:find('préparation de l’historique', 1, true) ~= nil, true)
Historique.preparer = preparationOriginale

-- Même garantie en fusion automatique, y compris deux fiches Lightroom pour un même fichier.
local cheminPartage = ecrire('retablissement-auto/PARTAGE.JPG', jpeg('<a/>', 'IMAGE-PARTAGEE'))
local ficheGardee = nouvellePhoto(500, cheminPartage)
local ficheRetiree = nouvellePhoto(501, cheminPartage)
nouveauCatalogue({ ficheGardee, ficheRetiree })
catalogue.selection = { ficheGardee, ficheRetiree }
local corbeilleAuto = nouvelleCollection(Doublons.COLLECTION)
corbeilleAuto.photos[ficheGardee] = true
reponses, miniaturesVoulues = { 'ok' }, false
dofile(PLUGIN .. '/FusionnerDoublons.lua')
verifier('auto : la fiche gardée sort de la corbeille', corbeilleAuto.photos[ficheGardee], nil)
verifier('auto : seule la fiche retirée reste en corbeille', corbeilleAuto.photos[ficheRetiree], true)
verifier('auto : le chemin du fichier gardé reste utilisable',
  Historique.contient(Historique.lire(PROJET_MANUEL .. '/photos-traitees.txt'), cheminPartage), false)

-- Une opération interrompue revient intégralement à l'état précédent, sans modifier le fichier externe.
local cheminUndo = PROJET_MANUEL .. '/photos-traitees.txt'
local historiqueAvantErreur = Historique.contenu(cheminUndo)
local actionsAvantErreur, collectionsAvantErreur = catalogue:nombreActions(), #collections
local noteAvantErreur = ficheGardee.note
local actionOk = pcall(Annulation.action, catalogue, cheminUndo, 'Opération interrompue',
  { photos = { { chemin = 'D:\\Photos\\interrompue.jpg' } } }, function()
    catalogue:createCollection('Collection interrompue', nil, true)
    ficheGardee:setRawMetadata('rating', 5)
    error('interruption volontaire')
  end)
verifier('transaction interrompue : erreur signalée', actionOk, false)
verifier('transaction interrompue : collection annulée', #collections, collectionsAvantErreur)
verifier('transaction interrompue : métadonnée annulée', ficheGardee.note, noteAvantErreur)
verifier('transaction interrompue : aucune nouvelle étape Undo', catalogue:nombreActions(), actionsAvantErreur)
verifier('transaction interrompue : fichier historique intact', Historique.contenu(cheminUndo), historiqueAvantErreur)

-- Les modifications manuelles du texte restent la base du Ctrl+Z de l'opération suivante.
Historique.ajouter(cheminUndo, 'doublon', { { chemin = 'D:\\Photos\\ajout-externe.jpg' } })
local baseExterne = Historique.contenu(cheminUndo)
local miroirOk = Annulation.action(catalogue, cheminUndo, 'Après édition du texte',
  { photos = { { chemin = 'D:\\Photos\\action-suivante.jpg' } } }, function() ficheGardee:setRawMetadata('rating', 4) end)
verifier('édition externe : action suivante synchronisée', miroirOk, true)
catalogue:annuler()
Annulation.synchroniser(catalogue, cheminUndo)
verifier('édition externe : Ctrl+Z conserve exactement l’édition externe', Historique.contenu(cheminUndo), baseExterne)

-- La fusion forcée réunit aussi des vidéos de contenus et formats différents, sans lecture Develop.
do
  local contexteAvant = { plugin = _PLUGIN, catalogue = catalogue, collections = collections, journal = journal,
    dialogues = dialogues, reponses = reponses, boitesPortee = boitesPortee }
  local projetVideos = SCRATCH .. '/projet-videos-manuelles'
  os.execute('mkdir "' .. projetVideos:gsub('/', '\\') .. '" 2>nul')
  _PLUGIN = { path = projetVideos .. '/albums-google-photos.lrplugin' }
  local videoOriginale = nouvellePhoto(600, ecrire('videos/CLIP.MOV', 'contenu original vidéo'),
    { video = true, format = 'VIDEO', duree = 12.5, largeur = 3840, hauteur = 2160, note = 5,
      titre = 'Titre du clip', ville = 'Gien', motsCles = { motCle('Voyage') }, gps = { latitude = 1, longitude = 2 } })
  local videoConvertie = nouvellePhoto(601, ecrire('videos/CLIP.mp4', 'vidéo convertie : contenu différent'),
    { video = true, format = 'VIDEO', duree = 12.5, largeur = 1920, hauteur = 1080, note = 1, legende = 'Légende conservée' })
  function videoOriginale:getDevelopSettings() error('Develop indisponible pour les vidéos') end
  function videoConvertie:getDevelopSettings() error('Develop indisponible pour les vidéos') end
  nouveauCatalogue({ videoOriginale, videoConvertie })
  catalogue.selection = { videoOriginale, videoConvertie }
  local albumOriginal = nouvelleCollection('Google Photos - albums / 2020 / Original')
  local albumConverti = nouvelleCollection('Google Photos - albums / 2020 / Converti')
  albumOriginal.photos[videoOriginale], albumConverti.photos[videoConvertie] = true, true
  local boiteOriginale = mocks.LrDialogs.presentModalDialog
  mocks.LrDialogs.presentModalDialog = function(args)
    args.contents.bind_to_object.gardee = videoConvertie.localIdentifier
    return boiteOriginale(args)
  end
  reponses, boitesPortee = { 'ok' }, {}
  dofile(PLUGIN .. '/FusionManuelle.lua')
  mocks.LrDialogs.presentModalDialog = boiteOriginale
  verifier('vidéos manuelles : fusion MOV + MP4 effectuée', dialogues[#dialogues].titre, 'Fusion manuelle terminée')
  verifier('vidéos manuelles : choix de la version convertie respecté', albumOriginal.photos[videoConvertie], true)
  verifier('vidéos manuelles : album existant conservé', albumConverti.photos[videoConvertie], true)
  verifier('vidéos manuelles : copie retirée de son album', albumOriginal.photos[videoOriginale], nil)
  verifier('vidéos manuelles : type vidéo affiché', boitesPortee[1].contents[4].items[1].title:find('vidéo', 1, true) ~= nil, true)
  verifier('vidéos manuelles : durée affichée', boitesPortee[1].contents[4].items[1].title:find('12.5 s', 1, true) ~= nil, true)
  verifier('vidéos manuelles : coupes non transférées annoncées', dialogues[1].texte:find('coupes et réglages vidéo ne seront pas transférés', 1, true) ~= nil, true)
  verifier('vidéos manuelles : note maximale réunie', videoConvertie.note, 5)
  verifier('vidéos manuelles : mots-clés réunis', videoConvertie.motsCles[1].nom, 'Voyage')
  verifier('vidéos manuelles : titre complété', videoConvertie.textes.title, 'Titre du clip')
  verifier('vidéos manuelles : légende conservée', videoConvertie.textes.caption, 'Légende conservée')
  verifier('vidéos manuelles : GPS complété', videoConvertie.gps.latitude, 1)
  verifier('vidéos manuelles : une seule étape Undo', catalogue:nombreActions(), 1)
  verifier('vidéos manuelles : original écarté mémorisé',
    Historique.contient(Historique.lire(projetVideos .. '/photos-traitees.txt'), videoOriginale.chemin), true)
  catalogue:annuler()
  Annulation.synchroniser(catalogue, projetVideos .. '/photos-traitees.txt')
  verifier('vidéos Ctrl+Z : note restaurée', videoConvertie.note, 1)
  verifier('vidéos Ctrl+Z : mot-clé retiré', #videoConvertie.motsCles, 0)
  verifier('vidéos Ctrl+Z : titre restauré', videoConvertie.textes.title, '')
  verifier('vidéos Ctrl+Z : album de l’original restauré', albumOriginal.photos[videoOriginale], true)
  verifier('vidéos Ctrl+Z : historique restauré', #Historique.lire(projetVideos .. '/photos-traitees.txt').entrees, 0)
  catalogue:retablir()
  Annulation.synchroniser(catalogue, projetVideos .. '/photos-traitees.txt')
  verifier('vidéos Rétablir : note fusionnée', videoConvertie.note, 5)
  verifier('vidéos Rétablir : albums réunis', albumOriginal.photos[videoConvertie] and albumConverti.photos[videoConvertie], true)
  verifier('vidéos Rétablir : exclusion rétablie',
    Historique.contient(Historique.lire(projetVideos .. '/photos-traitees.txt'), videoOriginale.chemin), true)

  -- Les champs vidéo facultatifs et le poids peuvent manquer, même pour un fichier présent.
  local videoSansDetails = nouvellePhoto(610, ecrire('videos/INCONNUE.MOV', 'vidéo sans métadonnées'), { poidsAbsent = true, note = 3 })
  local autreVideo = nouvellePhoto(611, ecrire('videos/INCONNUE-2.mp4', 'autre contenu sans dimensions'), { poidsAbsent = true })
  nouveauCatalogue({ videoSansDetails, autreVideo })
  catalogue.selection = { videoSansDetails, autreVideo }
  reponses, boitesPortee = { 'ok' }, {}
  dofile(PLUGIN .. '/FusionManuelle.lua')
  verifier('vidéos sans détails : fusion possible', dialogues[#dialogues].titre, 'Fusion manuelle terminée')
  verifier('vidéos sans détails : extension reconnue sans isVideo SDK', boitesPortee[1].contents[4].items[1].title:find('vidéo', 1, true) ~= nil, true)
  verifier('vidéos sans détails : résolution inconnue annoncée', boitesPortee[1].contents[4].items[1].title:find('résolution inconnue', 1, true) ~= nil, true)
  verifier('vidéos sans détails : poids inconnu annoncé', boitesPortee[1].contents[4].items[1].title:find('poids inconnu', 1, true) ~= nil, true)
  verifier('vidéos sans détails : chemins exclus mémorisés malgré date absente',
    Historique.contient(Historique.lire(projetVideos .. '/photos-traitees.txt'), autreVideo.chemin), true)
  _PLUGIN, catalogue, collections, journal = contexteAvant.plugin, contexteAvant.catalogue, contexteAvant.collections, contexteAvant.journal
  dialogues, reponses, boitesPortee = contexteAvant.dialogues, contexteAvant.reponses, contexteAvant.boitesPortee
end

-- Les gates du SDK peuvent abandonner l'accès sans lever d'erreur ni appeler le callback.
local function testerAccesCatalogue()
local ecrireCatalogue = catalogue.withWriteAccessDo
local avantRefus = Historique.contenu(cheminUndo)
local actionsAvantRefus = catalogue:nombreActions()
local callbackExecute = false
catalogue.withWriteAccessDo = function() return 'aborted' end
local refusOk = pcall(Annulation.action, catalogue, cheminUndo, 'Accès refusé',
  { photos = { { chemin = 'D:\\Photos\\non-fusionnee.jpg' } } }, function() callbackExecute = true end)
verifier('accès refusé : échec signalé', refusOk, false)
verifier('accès refusé : callback non exécuté', callbackExecute, false)
verifier('accès refusé : historique intact', Historique.contenu(cheminUndo), avantRefus)
verifier('accès refusé : aucune action Undo ajoutée', catalogue:nombreActions(), actionsAvantRefus)
catalogue.withWriteAccessDo = ecrireCatalogue

nouveauCatalogue({ ficheGardee, ficheRetiree })
local cheminRefus = PROJET_MANUEL .. '/historique-refus.txt'
Historique.preparer(cheminRefus)
local ecrirePrive = catalogue.withPrivateWriteAccessDo
catalogue.withPrivateWriteAccessDo = function() return 'aborted' end
local synchronise = pcall(Annulation.synchroniser, catalogue, cheminRefus)
verifier('accès privé refusé : échec de synchronisation signalé', synchronise, false)
verifier('accès privé refusé : état non initialisé', catalogue:getPropertyForPlugin(_PLUGIN, 'historiquePhotosV1'), nil)
catalogue.withPrivateWriteAccessDo = ecrirePrive
Annulation.synchroniser(catalogue, cheminRefus)
local syncAvant = Historique.contenu(cheminRefus)
catalogue.withPrivateWriteAccessDo = function() return 'aborted' end
local miroirRefuse = Annulation.action(catalogue, cheminRefus, 'Miroir refusé',
  { photos = { { chemin = 'D:\\Photos\\fusionnee.jpg' } } }, function() end)
verifier('miroir refusé après fusion : échec signalé', miroirRefuse, false)
verifier('miroir refusé après fusion : action conservée', catalogue:nombreActions(), 1)
catalogue.withPrivateWriteAccessDo = ecrirePrive
Annulation.synchroniser(catalogue, cheminRefus)
verifier('miroir refusé après fusion : synchronisation reprise',
  Historique.contient(Historique.lire(cheminRefus), 'D:\\Photos\\fusionnee.jpg'), true)
catalogue:annuler()
Annulation.synchroniser(catalogue, cheminRefus)
verifier('miroir refusé après fusion : Ctrl+Z reste effectif', Historique.contenu(cheminRefus), syncAvant)

-- Un Ctrl+Z peut survenir pendant l'attente de l'accès en écriture : la base doit être relue dans la gate.
local avantAttente = Historique.contenu(cheminRefus)
Annulation.action(catalogue, cheminRefus, 'Avant attente',
  { photos = { { chemin = 'D:\\Photos\\annulee-pendant-attente.jpg' } } }, function() end)
local ecrireApresAttente = catalogue.withWriteAccessDo
catalogue.withWriteAccessDo = function(self, titre, f, options)
  self:annuler()
  return ecrireApresAttente(self, titre, f, options)
end
local suivante = { photos = { { chemin = 'D:\\Photos\\apres-attente.jpg' } } }
Annulation.action(catalogue, cheminRefus, 'Après attente', suivante, function() end)
catalogue.withWriteAccessDo = ecrireApresAttente
verifier('Ctrl+Z pendant attente : exclusions annulées non réintroduites',
  Historique.contenu(cheminRefus), Historique.modifier(avantAttente, suivante))
catalogue:annuler()
Annulation.synchroniser(catalogue, cheminRefus)
verifier('Ctrl+Z pendant attente : base de la nouvelle action cohérente', Historique.contenu(cheminRefus), avantAttente)

-- Même course pendant l'import d'une édition externe par l'accès privé.
local avantAttentePrivee = Historique.contenu(cheminRefus)
Annulation.action(catalogue, cheminRefus, 'Avant attente privée',
  { photos = { { chemin = 'D:\\Photos\\annulee-pendant-attente-privee.jpg' } } }, function() end)
Historique.ajouter(cheminRefus, 'doublon', { { chemin = 'D:\\Photos\\edition-externe-pendant-attente.jpg' } })
catalogue.withPrivateWriteAccessDo = function(self, f, options)
  self.withPrivateWriteAccessDo = ecrirePrive
  self:annuler()
  return ecrirePrive(self, f, options)
end
local etatApresAttentePrivee = Annulation.synchroniser(catalogue, cheminRefus)
verifier('Ctrl+Z pendant attente privée : état annulé conservé', etatApresAttentePrivee, avantAttentePrivee)
verifier('Ctrl+Z pendant attente privée : fichier suit le catalogue', Historique.contenu(cheminRefus), avantAttentePrivee)
catalogue:retablir()
Annulation.synchroniser(catalogue, cheminRefus)
verifier('Ctrl+Z pendant attente privée : Rétablir reste effectif',
  Historique.contient(Historique.lire(cheminRefus), 'D:\\Photos\\annulee-pendant-attente-privee.jpg'), true)

-- Le fichier attend encore la première synchronisation d'une action ; Ctrl+Z précède la gate privée.
-- Une écriture faite AVANT la gate serait alors prise à tort pour une modification externe.
local avantMiroirEnRetard = Historique.contenu(cheminRefus)
local ecrireHistorique = Historique.ecrire
Historique.ecrire = function() error('disque momentanément indisponible') end
local miroirEnRetard = Annulation.action(catalogue, cheminRefus, 'Miroir en retard',
  { photos = { { chemin = 'D:\\Photos\\annulee-avant-miroir.jpg' } } }, function() end)
Historique.ecrire = ecrireHistorique
verifier('miroir en retard : panne initiale simulée', miroirEnRetard, false)
catalogue.withPrivateWriteAccessDo = function(self, f, options)
  self.withPrivateWriteAccessDo = ecrirePrive
  self:annuler()
  return ecrirePrive(self, f, options)
end
verifier('Ctrl+Z avant miroir : état annulé conservé', Annulation.synchroniser(catalogue, cheminRefus), avantMiroirEnRetard)
verifier('Ctrl+Z avant miroir : fichier annulé conservé', Historique.contenu(cheminRefus), avantMiroirEnRetard)
catalogue:retablir()
Annulation.synchroniser(catalogue, cheminRefus)
verifier('Ctrl+Z avant miroir : Rétablir reste effectif',
  Historique.contient(Historique.lire(cheminRefus), 'D:\\Photos\\annulee-avant-miroir.jpg'), true)
end
testerAccesCatalogue()

local function testerDetectionVideos()
  -- Identité de tout le fichier : noms et dates peuvent différer, les albums et notes sont réunis.
  local contenu = boiteIso('ftyp', 'isom') .. boiteIso('moov', 'temps et pistes') .. boiteIso('mdat', 'VIDEO-IDENTIQUE')
  local a = nouvellePhoto(600, ecrire('videos/rangee/VIDEO-A.mp4', contenu), { note = 1 })
  local b = nouvellePhoto(601, ecrire('videos/desordre/RENOMMEE.mov', contenu), { note = 4, date = d1 + 20 })
  nouveauCatalogue({ a, b })
  catalogue.selection = { a, b }
  local album = nouvelleCollection('Album vidéo')
  album.photos[b] = true
  reponses, miniaturesVoulues = { 'ok' }, false
  dofile(PLUGIN .. '/FusionnerDoublons.lua')
  local corbeille = collections[#collections]
  verifier('vidéos identiques renommées : fusion effectuée', dialogues[#dialogues].titre, 'Doublons fusionnés')
  verifier('vidéos identiques renommées : une seule copie écartée', corbeille.photos[a] ~= corbeille.photos[b], true)
  local gardee, retiree = corbeille.photos[a] and b or a, corbeille.photos[a] and a or b
  verifier('vidéos : note réunie', gardee.note, 4)
  verifier('vidéos : album réuni', album.photos[gardee], true)
  verifier('vidéos : exclusion mémorisée', Historique.contient(Historique.lire(cheminUndo), retiree.chemin), true)
  catalogue:annuler()
  Annulation.synchroniser(catalogue, cheminUndo)
  verifier('vidéos Ctrl+Z : album original restauré', album.photos[b], true)
  verifier('vidéos Ctrl+Z : exclusion annulée', Historique.contient(Historique.lire(cheminUndo), retiree.chemin), false)

  -- Même mdat et une éventuelle première image identique ne prouvent pas l'identité du montage.
  local x = nouvellePhoto(610, ecrire('videos/distinctes/CLIP.mov', boiteIso('ftyp', 'qt  ')
    .. boiteIso('moov', 'montage A') .. boiteIso('mdat', 'MEMES-IMAGES')))
  local y = nouvellePhoto(611, ecrire('videos/distinctes/CLIP-2.mov', boiteIso('ftyp', 'qt  ')
    .. boiteIso('moov', 'montage B') .. boiteIso('mdat', 'MEMES-IMAGES')))
  vignette(x.chemin, uniforme(100), 1920, 1080)
  vignette(y.chemin, uniforme(100), 1920, 1080)
  nouveauCatalogue({ x, y })
  catalogue.selection = { x, y }
  reponses, miniaturesVoulues = { 'ok' }, false
  dofile(PLUGIN .. '/FusionnerDoublons.lua')
  verifier('vidéos : montages différents non fusionnés', catalogue:nombreActions(), 0)

  -- Préfiltre identique : seule l'empreinte intégrale décide, y compris avec des noms différents.
  local empreinte, complete = Empreintes.empreinte, Empreintes.empreinteComplete
  local v1 = nouvellePhoto(620, ecrire('videos/grosses/ORIGINAL.mp4', 'A'))
  local v2 = nouvellePhoto(621, ecrire('videos/grosses/COPIE.mov', 'A'))
  local v3 = nouvellePhoto(622, ecrire('videos/grosses/AUTRE.mp4', 'B'))
  local unique = nouvellePhoto(623, ecrire('videos/grosses/UNIQUE.mp4', 'C'))
  local lectures = {}
  Empreintes.empreinte = function(chemin)
    return chemin == unique.chemin and 'gros:unique' or 'gros:debut-et-fin-identiques'
  end
  Empreintes.empreinteComplete = function(chemin)
    lectures[chemin] = (lectures[chemin] or 0) + 1
    return chemin == v3.chemin and 'complet:B' or 'complet:A'
  end
  nouveauCatalogue({ v1, v2, v3, unique })
  catalogue.selection = { v1, v2, v3, unique }
  reponses = { 'ok' }
  dofile(PLUGIN .. '/FusionnerDoublons.lua')
  Empreintes.empreinte, Empreintes.empreinteComplete = empreinte, complete
  corbeille = collections[#collections]
  verifier('grosses vidéos : candidats vérifiés intégralement', lectures[v1.chemin] == 1 and lectures[v2.chemin] == 1
    and lectures[v3.chemin] == 1, true)
  verifier('grosses vidéos : fichier sans candidat non relu', lectures[unique.chemin], nil)
  verifier('grosses vidéos : seule une copie identique écartée', corbeille.photos[v1] ~= corbeille.photos[v2], true)
  verifier('grosses vidéos : milieu différent conservé', corbeille.photos[v3], nil)
  verifier('grosses vidéos : fichier unique conservé', corbeille.photos[unique], nil)
end
testerDetectionVideos()

print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
