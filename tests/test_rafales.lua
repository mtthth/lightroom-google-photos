-- Tests de Rafales.lua (logique pure), puis simulation de ReduireRafales.lua avec un faux Lightroom.
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

-- Faux modules Lightroom minimaux, pour charger les modules purs (Catalogue, Parallele…).
local mocks = {}
function import(nom) return assert(mocks[nom], 'module inconnu : ' .. nom) end
mocks.LrTasks = { pcall = pcall, yield = function() end, sleep = function() end, startAsyncTask = function(f) f() end }

local Rafales = require 'Rafales'

-- Outils : fichiers et cadres ---------------------------------------------------------------------------
local T0 = 810000000
local function fichier(chemin, dt, extra)
  local f = { chemin = chemin, t = T0 + dt, taille = 1000 }
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end
local function frames(...)   -- cadres à partir de fichiers
  return Rafales.cadres({ ... })
end

-- numero -------------------------------------------------------------------------------------------------------
verifier('numéro Fuji', Rafales.numero('DSCF4348.JPG'), 4348)
verifier('numéro copie -2', Rafales.numero('DSCF4344-2.JPG'), 4344)
verifier('numéro retouche', Rafales.numero('DSCF4344-Modifier.JPG'), 4344)
verifier('numéro sans chiffres', Rafales.numero('photo.jpg'), -1)
verifier('numéro : moins de 3 chiffres', Rafales.numero('a12b.jpg'), -1)
verifier('numéro : dernière suite', Rafales.numero('IMG_20260802_123456.jpg'), 123456)
verifier('numéro téléphone Pixel', Rafales.numero('PXL_20260815_171001000.jpg'), 171001000)
verifier('numéro WhatsApp : le compteur', Rafales.numero('IMG-20260802-WA0003.jpg'), 3)
verifier('numéro WhatsApp retouché : le compteur', Rafales.numero('IMG-20260802-WA0003-Modifié-2026-08-02T22-37-43.jpg'), 3)
verifier('numéro DxO', Rafales.numero('DSCF5360-20260821-DxO_DeepPRIME XD3.jpg'), 5360)

-- cadres ---------------------------------------------------------------------------------------------------------
local D = 'C:/Photos/2026-08-15/'
local liste = frames(
  fichier(D .. 'DSCF1001.JPG', 0), fichier(D .. 'DSCF1000.RAF', 0), fichier(D .. 'DSCF1000.JPG', 0),
  fichier(D .. 'DSCF1000-2.JPG', 0), fichier(D .. 'DSCF1000-Modifier.JPG', 0), fichier('C:/Autre/DSCF1000.JPG', 0),
  fichier(D .. 'photo_a.jpg', 5), fichier(D .. 'photo_b.jpg', 5))
verifier('autre dossier : autre cadre', #liste, 5)
verifier('ordre : numéro dans la même seconde', liste[2].numero, 1000)
local cadre1000 = nil
for _, c in ipairs(liste) do if c.numero == 1000 and #c.fichiers == 4 then cadre1000 = c end end
verifier('RAW + JPEG + copie + retouche : un seul cadre', cadre1000 ~= nil, true)
verifier('nom affiché : le fichier d’origine', cadre1000 and cadre1000.nom, 'DSCF1000')
verifier('fichier mesuré : le JPEG d’origine', cadre1000 and cadre1000.mesure.nom, 'DSCF1000.JPG')
verifier('sans numéro : deux noms, deux cadres', #frames(fichier(D .. 'photo_a.jpg', 5), fichier(D .. 'photo_b.jpg', 5)), 2)
local seulRaw = frames(fichier(D .. 'DSCF1000.RAF', 0))
verifier('RAW seul : rien à mesurer', seulRaw[1].mesure, nil)
local seulRetouche = frames(fichier(D .. 'DSCF1000-Modifier.JPG', 0))
verifier('retouche seule : jamais mesurée', seulRetouche[1].mesure, nil)
verifier('dates à la seconde : fractions ignorées', #frames(fichier(D .. 'DSCF1000.JPG', 0.2), fichier(D .. 'DSCF1000.RAF', 0.7)), 1)

-- proteger -----------------------------------------------------------------------------------------------------
local c = frames(fichier(D .. 'DSCF1000.JPG', 0, { raisons = { 'note 3', 'drapeau' } }),
  fichier(D .. 'DSCF1000.RAF', 0, { raisons = { 'note 3' } }))[1]
Rafales.proteger(c)
verifier('protégé : raisons sans doublon', #c.raisons, 2)
verifier('protégé', c.protege, true)
c = frames(fichier(D .. 'DSCF1000.JPG', 0))[1]
Rafales.proteger(c)
verifier('non protégé', c.protege, false)
c = frames(fichier(D .. 'DSCF1000.JPG', 0), fichier(D .. 'DSCF1000-Modifier.JPG', 0))[1]
Rafales.proteger(c)
verifier('version retouchée : protégé', c.protege, true)
verifier('version retouchée : raison', c.raisons[1], 'version retouchée (éditeur externe)')

-- rafales ----------------------------------------------------------------------------------------------------------
local function serie(debut, n, dt, pas)
  local fs = {}
  for i = 0, n - 1 do fs[#fs + 1] = fichier(string.format('%sDSCF%04d.JPG', D, debut + i * (pas or 1)), dt) end
  return fs
end
local function cadresDe(...)
  local tous = {}
  for _, fs in ipairs({ ... }) do for _, f in ipairs(fs) do tous[#tous + 1] = f end end
  return Rafales.cadres(tous)
end
verifier('3 cadres à la même seconde : une rafale', #Rafales.rafales(cadresDe(serie(100, 3, 0))), 1)
verifier('2 cadres : pas une rafale', #Rafales.rafales(cadresDe(serie(100, 2, 0))), 0)
local deuxSecondes = {}
for i = 0, 4 do table.insert(deuxSecondes, fichier(string.format('%sDSCF%04d.JPG', D, 100 + i), i)) end   -- un cadre par seconde
verifier('un cadre par seconde : une rafale (écart de 1 s)', #Rafales.rafales(Rafales.cadres(deuxSecondes)), 1)
local espaces = {}
for i = 0, 4 do table.insert(espaces, fichier(string.format('%sDSCF%04d.JPG', D, 100 + i), i * 2)) end   -- écart de 2 s
verifier('écart de 2 s : pas une rafale', #Rafales.rafales(Rafales.cadres(espaces)), 0)
verifier('numéros espacés de 3 : une rafale', #Rafales.rafales(cadresDe(serie(100, 4, 0, 3))), 1)
verifier('numéros espacés de 4 : pas une rafale', #Rafales.rafales(cadresDe(serie(100, 4, 0, 4))), 0)
local deux = Rafales.rafales(cadresDe(serie(100, 4, 0), serie(200, 5, 0)))
verifier('deux rafales distinctes (numéros éloignés)', #deux, 2)
verifier('taille de la 2e rafale', #deux[2], 5)
verifier('numérotation des rafales', deux[2].numero, 2)
local telephone = {}
for i = 0, 3 do table.insert(telephone, fichier(string.format('%sPXL_20260815_17%07d.jpg', D, 1000 + i * 40), 0)) end
verifier('noms de téléphone : la proximité des numéros ne compte pas', #Rafales.rafales(Rafales.cadres(telephone)), 1)

-- blocs ---------------------------------------------------------------------------------------------------------------
local function tailles(n, ratio)
  local r = Rafales.rafales(cadresDe(serie(100, n, 0)))[1]
  Rafales.blocs({ r }, ratio)
  local t = {}
  for i, b in ipairs(r.blocs) do t[i] = #b end
  return table.concat(t, ',')
end
verifier('3 cadres : 1 bloc', tailles(3, 4), '3')
verifier('4 cadres : 1 bloc', tailles(4, 4), '4')
verifier('5 cadres : 2 blocs', tailles(5, 4), '2,3')
verifier('8 cadres : 2 blocs', tailles(8, 4), '4,4')
verifier('9 cadres : 3 blocs', tailles(9, 4), '3,3,3')
verifier('55 cadres : 14 blocs de 3 ou 4', tailles(55, 4), '3,4,4,4,4,4,4,4,4,4,4,4,4,4')
verifier('ratio 2 : 5 cadres en 3 blocs', tailles(5, 2), '1,2,2')

-- décision (règle A : les protégés s'ajoutent au plus net) -------------------------------------------------
local function bloc(valeurs, proteges)
  local fs = {}
  for i = 1, #valeurs do fs[i] = fichier(string.format('%sDSCF%04d.JPG', D, 100 + i - 1), 0) end
  local r = Rafales.rafales(Rafales.cadres(fs))[1]
  Rafales.blocs({ r }, 4)
  for i, cadre in ipairs(r) do
    cadre.nettete = valeurs[i]
    cadre.raisons = {}
    cadre.protege = proteges and proteges[i] or false
    if cadre.protege then cadre.raisons = { 'collection « Album »' } end
  end
  Rafales.decider({ r })
  local decisions = {}
  for i, cadre in ipairs(r) do decisions[i] = cadre.decision:sub(1, 1) end
  return table.concat(decisions), r
end
verifier('4 cadres, aucun protégé : le plus net', (bloc({ 10, 30, 20, 5 })), 'rgrr')
verifier('règle A : le protégé s’ajoute au plus net non protégé', (bloc({ 10, 30, 20, 5 }, { true })), 'pgrr')
verifier('règle A : protégé plus net que les autres', (bloc({ 99, 30, 20, 5 }, { true })), 'pgrr')
verifier('plusieurs protégés', (bloc({ 10, 30, 20, 5 }, { true, false, true })), 'pgpr')
verifier('tous protégés : rien à retirer', (bloc({ 10, 30, 20 }, { true, true, true })), 'ppp')
verifier('un seul non protégé : gardé', (bloc({ 10, 30, 20 }, { true, true, false })), 'ppg')
verifier('égalité : le premier du bloc', (bloc({ 20, 20, 20 })), 'grr')
local _, sansMesure = bloc({ 1, 2, 3 })
for _, cadre in ipairs(sansMesure) do cadre.nettete = nil; cadre.decision = nil end
Rafales.decider({ sansMesure })
verifier('sans mesure : premier gardé', sansMesure[1].decision, 'garder')
verifier('sans mesure : raison', sansMesure[2].pourquoi:find('non mesurée', 1, true) ~= nil, true)
local _, mixte = bloc({ 1, 2, 3 })
mixte[1].nettete, mixte[2].nettete, mixte[3].nettete = nil, 7, nil
Rafales.decider({ mixte })
verifier('mesuré contre non mesuré : le mesuré l’emporte', mixte[2].decision, 'garder')
verifier('raison : nom du cadre gardé', mixte[1].pourquoi, 'moins net que ' .. mixte[2].nom)

-- cadres à mesurer, bilan, photos, rapport -------------------------------------------------------------------
local fs = {}
for i = 0, 7 do fs[#fs + 1] = fichier(string.format('%sDSCF%04d.JPG', D, 100 + i), 0, { photo = { id = i }, taille = 2000 + i }) end
local rafale = Rafales.rafales(Rafales.cadres(fs))[1]
Rafales.blocs({ rafale }, 4)
rafale[1].raisons, rafale[1].protege = { 'note 3' }, true
for i = 2, 8 do rafale[i].raisons, rafale[i].protege = {}, false end
rafale[5].raisons, rafale[5].protege = { 'collection « A »' }, true
rafale[6].raisons, rafale[6].protege = { 'libellé red' }, true
rafale[7].raisons, rafale[7].protege = { 'drapeau' }, true
-- bloc 1 : 1 protégé + 3 libres ; bloc 2 : 3 protégés + 1 libre (8)
verifier('à mesurer : seulement les blocs à comparer', #Rafales.cadresAMesurer({ rafale }), 3)
for i, cadre in ipairs(rafale) do cadre.nettete = i end
Rafales.decider({ rafale })
local bilan = Rafales.bilan({ rafale })
verifier('bilan : rafales', bilan.rafales, 1)
verifier('bilan : cadres', bilan.cadres, 8)
verifier('bilan : protégés', bilan.proteges, 4)
verifier('bilan : gardés', bilan.gardes, 2)
verifier('bilan : retirés', bilan.retires, 2)
verifier('bilan : fichiers retirés', bilan.fichiersRetires, 2)
verifier('bilan : octets retirés', bilan.octetsRetires, 2001 + 2002)
verifier('photos à retirer', #Rafales.photosARetirer({ rafale }), 2)
local lignes = Rafales.lignesRapport({ rafale })
verifier('rapport : en-tête et une ligne par cadre', #lignes, 9)
verifier('rapport : protégé avec sa raison', lignes[2][5] .. '|' .. lignes[2][7], 'protégé|note 3')
verifier('rapport : nombre à virgule', lignes[4][6], '3,00')
verifier('rapport : heure', #lignes[2][4], 8)
verifier('rapport : numéro de bloc', lignes[6][2], 2)

-- ----------------------------------------------------------------------------------------------------------------------------
-- Simulation de la commande avec un faux Lightroom
-- ----------------------------------------------------------------------------------------------------------------------------
_PLUGIN = { path = PLUGIN }
local RAPPORT = PLUGIN:match('^(.*)[/\\]') .. '/rafales.csv'

local collections, ecritures, dialogues, reponses, journal, sousDossiersDemande, motsCles
local photosDuDossier, optionsTest, sources, magickDispo, nettetes
local ecriture = false

local function nouvelEnsemble(nom, parent)
  return { getName = function() return nom end, getParent = function() return parent end }
end
local function nouvelleCollection(nom, parent, intelligente)
  local c = { nom = nom, parent = parent, photos = {}, intelligente = intelligente }
  function c:getName() return self.nom end
  function c:getParent() return self.parent end
  function c:isSmartCollection() return self.intelligente or false end
  function c:getPhotos() local r = {} for _, p in ipairs(self.photos) do r[#r + 1] = p end return r end
  function c:addPhotos(liste)
    assert(ecriture, 'addPhotos hors accès en écriture')
    for _, p in ipairs(liste) do
      local deja = false
      for _, q in ipairs(self.photos) do if q == p then deja = true end end
      if not deja then
        table.insert(self.photos, p)
        table.insert(p.collectionsContenues, self)
      end
    end
  end
  collections[#collections + 1] = c
  return c
end
local function nouveauMotCle(nom, parent)
  local k = { nom = nom, parent = parent, photos = {}, enfants = {} }
  function k:getName() return self.nom end
  function k:getChildren() return self.enfants end
  function k:getPhotos() return self.photos end
  if parent then table.insert(parent.enfants, k) else motsCles[#motsCles + 1] = k end
  return k
end
local function nouvellePhoto(id, chemin, dt, champs)
  local p = { localIdentifier = id, chemin = chemin, t = T0 + dt, note = 0, drapeau = 0, label = 'none', virtuelle = false,
    nbVirtuelles = 0, taille = 1000000 + id, collectionsContenues = {}, publiees = {}, retouchee = false }
  for k, v in pairs(champs or {}) do p[k] = v end
  function p:getContainedCollections() return self.collectionsContenues end
  function p:getContainedPublishedCollections() return self.publiees end
  function p:addKeyword(k)
    assert(ecriture, 'addKeyword hors accès en écriture')
    table.insert(k.photos, self)
  end
  return p
end

mocks.LrApplication = { activeCatalog = function()
  local catalogue = {}
  function catalogue:getActiveSources() return sources end
  function catalogue:batchGetRawMetadata(lot)
    local r = {}
    for _, p in ipairs(lot) do
      r[p] = { path = p.chemin, fileSize = p.taille, dateTimeOriginal = p.t, isVirtualCopy = p.virtuelle,
        countVirtualCopies = p.nbVirtuelles, rating = p.note, pickStatus = p.drapeau, colorNameForLabel = p.label }
    end
    return r
  end
  function catalogue:findPhotos(args)
    assert(args.searchDesc.criteria == 'hasAdjustments' and args.searchDesc.operation == 'isTrue')
    local r = {}
    for _, p in ipairs(photosDuDossier) do if p.retouchee then r[#r + 1] = p end end
    return r
  end
  function catalogue:getChildCollections()
    local r = {}
    for _, c in ipairs(collections) do if not c.parent then r[#r + 1] = c end end
    return r
  end
  function catalogue:withWriteAccessDo(_, f)
    ecritures = ecritures + 1
    ecriture = true
    f()
    ecriture = false
  end
  function catalogue:createCollection(nom)
    assert(ecriture, 'createCollection hors accès en écriture')
    for _, c in ipairs(collections) do if c.nom == nom and not c.parent then return c end end
    return nouvelleCollection(nom, nil)
  end
  function catalogue:getKeywords() return motsCles end
  function catalogue:createKeyword(nom, synonymes, exporte, parent, retournerExistant)
    assert(ecriture, 'createKeyword hors accès en écriture')
    assert(exporte == false, 'le mot-clé des rafales ne doit pas être exporté')
    assert(parent == nil and retournerExistant == true)
    for _, k in ipairs(motsCles) do if k.nom == nom then return k end end
    local k = nouveauMotCle(nom, nil)
    k.exporte = exporte
    return k
  end
  function catalogue:setActiveSources(s) journal[#journal + 1] = 'source ' .. s[1].nom end
  return catalogue
end }
mocks.LrDialogs = {
  presentModalDialog = function(args)
    if optionsTest == 'annuler' then return 'cancel' end
    args.contents.bind_to_object.ratio = optionsTest.ratio or 4
    args.contents.bind_to_object.sousDossiers = optionsTest.sousDossiers or false
    return 'ok'
  end,
  confirm = function(titre, texte) dialogues[#dialogues + 1] = { titre = titre, texte = texte }; return table.remove(reponses, 1) or 'cancel' end,
  message = function(titre, texte) dialogues[#dialogues + 1] = { titre = titre, texte = texte } end,
}
mocks.LrBinding = { makePropertyTable = function() return {} end }
local fabrique = setmetatable({}, { __index = function() return function(_, t) return t end end })
mocks.LrView = { osFactory = function() return fabrique end, bind = function(t) return t end }
mocks.LrFunctionContext = { callWithContext = function(_, f) return f({}) end }
mocks.LrPathUtils = { parent = function(p) return p:match('^(.*)[/\\][^/\\]+$') end, child = function(a, b) return a .. '/' .. b end }
mocks.LrProgressScope = function() return setmetatable({}, { __index = function(_, k)
  if k == 'isCanceled' then return function() return false end end
  return function() end
end }) end
mocks.LrShell = { revealInShell = function(p) journal[#journal + 1] = 'révéler ' .. p end }
mocks.LrTasks = { pcall = pcall, yield = function() end, sleep = function() end, startAsyncTask = function(f) f() end }

-- Faux ImageMagick : la netteté vient d'une table.
package.loaded['Vignettes'] = {
  magick = function() return magickDispo and 'magick.exe' or nil end,
  nettete = function(chemin) return nettetes[chemin] end,
}

local function chemin(nom) return D .. nom end
local function monter()
  collections, ecritures, dialogues, journal, motsCles = {}, 0, {}, {}, {}
  magickDispo, sousDossiersDemande = true, nil
  nouveauMotCle('Enfants', nouveauMotCle('Famille', nil))   -- mots-clés sans rapport

  local albums = nouvelEnsemble('Google Photos - albums', nil)
  local albumJava = nouvelleCollection('2026-08-15 – La java', albums)
  local epoques = nouvelEnsemble('Google Photos - époques', nil)
  local epoques2026 = nouvelEnsemble('2026', epoques)
  local epoqueJour = nouvelleCollection('2026-08-15 – Goûter', epoques2026)
  local dynamique = nouvelleCollection('Collection dynamique', nil, true)
  local doublons = nouvelleCollection('Doublons à retirer', nil)

  local p = {}
  local function ajouter(id, nom, dt, champs)
    p[nom] = nouvellePhoto(id, chemin(nom), dt, champs)
    return p[nom]
  end
  -- Rafale A : 8 cadres DSCF1000..1007 à la même seconde.
  ajouter(10, 'DSCF1000.JPG', 0); ajouter(11, 'DSCF1000.RAF', 0)
  ajouter(12, 'DSCF1001.JPG', 0)
  ajouter(13, 'DSCF1002.JPG', 0)
  ajouter(14, 'DSCF1003.JPG', 0); ajouter(15, 'DSCF1003-2.JPG', 0)
  ajouter(16, 'DSCF1004.JPG', 0, { nbVirtuelles = 1 })
  ajouter(17, 'DSCF1004-virtuelle', 0, { virtuelle = true, chemin = chemin('DSCF1004.JPG') })   -- sa copie virtuelle
  ajouter(18, 'DSCF1005.JPG', 0)
  ajouter(19, 'DSCF1006.JPG', 0, { note = 3 })
  ajouter(20, 'DSCF1007.JPG', 0)
  -- Rafale B : 3 cadres 10 s plus tard.
  ajouter(30, 'DSCF2000.JPG', 10); ajouter(31, 'DSCF2000-Modifier.JPG', 10)
  ajouter(32, 'DSCF2001.JPG', 10, { retouchee = true })
  ajouter(33, 'DSCF2002.JPG', 10)
  -- Rafale C : 4 cadres 30 s plus tard.
  ajouter(40, 'DSCF2500.JPG', 30); ajouter(41, 'DSCF2501.JPG', 30); ajouter(42, 'DSCF2502.JPG', 30); ajouter(43, 'DSCF2503.JPG', 30)
  -- Pas des rafales : cadres isolés, ou à 2 s d'écart.
  ajouter(50, 'DSCF3000.JPG', 100); ajouter(51, 'DSCF3001.JPG', 130)
  ajouter(52, 'DSCF3002.JPG', 200); ajouter(53, 'DSCF3003.JPG', 202); ajouter(54, 'DSCF3004.JPG', 204)

  ecriture = true
  albumJava:addPhotos({ p['DSCF1001.JPG'] })
  epoqueJour:addPhotos({ p['DSCF1005.JPG'], p['DSCF1000.JPG'] })
  dynamique:addPhotos({ p['DSCF2002.JPG'] })
  doublons:addPhotos({ p['DSCF1003-2.JPG'] })
  ecriture = false

  photosDuDossier = {}
  for _, nom in ipairs({ 'DSCF1000.JPG', 'DSCF1000.RAF', 'DSCF1001.JPG', 'DSCF1002.JPG', 'DSCF1003.JPG', 'DSCF1003-2.JPG', 'DSCF1004.JPG',
    'DSCF1004-virtuelle', 'DSCF1005.JPG', 'DSCF1006.JPG', 'DSCF1007.JPG', 'DSCF2000.JPG', 'DSCF2000-Modifier.JPG', 'DSCF2001.JPG', 'DSCF2002.JPG', 'DSCF2500.JPG',
    'DSCF2501.JPG', 'DSCF2502.JPG', 'DSCF2503.JPG', 'DSCF3000.JPG', 'DSCF3001.JPG', 'DSCF3002.JPG', 'DSCF3003.JPG', 'DSCF3004.JPG' }) do
    photosDuDossier[#photosDuDossier + 1] = p[nom]
  end
  nettetes = {
    [chemin('DSCF1000.JPG')] = 50, [chemin('DSCF1001.JPG')] = 99, [chemin('DSCF1002.JPG')] = 70, [chemin('DSCF1003.JPG')] = 60,
    [chemin('DSCF1004.JPG')] = 40, [chemin('DSCF1005.JPG')] = 90, [chemin('DSCF1006.JPG')] = 10, [chemin('DSCF1007.JPG')] = 85,
    [chemin('DSCF2002.JPG')] = 55,
    [chemin('DSCF2500.JPG')] = 10, [chemin('DSCF2501.JPG')] = 40, [chemin('DSCF2502.JPG')] = 30, [chemin('DSCF2503.JPG')] = 20,
  }
  local dossier = { type = function() return 'LrFolder' end, getName = function() return '2026-08-15' end,
    getPhotos = function(_, sous) sousDossiersDemande = sous; return photosDuDossier end }
  sources = { dossier }
  optionsTest = { ratio = 4 }
  os.remove(RAPPORT)
  return p
end
local function lancer(reps)
  reponses = reps or {}
  dialogues = {}
  dofile(PLUGIN .. '/ReduireRafales.lua')
end
local function collectionRafales()
  for _, c in ipairs(collections) do if c.nom == 'Rafales à retirer' then return c end end
end
local function noms(c)
  local r = {}
  for _, photo in ipairs(c and c.photos or {}) do r[#r + 1] = photo.chemin:match('[^/]+$') end
  table.sort(r)
  return table.concat(r, ' ')
end
local function lire(chemin)
  local f = io.open(chemin, 'rb')
  local t = f and f:read('*a') or ''
  if f then f:close() end
  return t
end

-- 1. Cas normal : on met de côté.
local p = monter()
lancer({ 'ok' })
local texte = dialogues[1] and dialogues[1].texte or ''
verifier('confirmation : titre', dialogues[1] and dialogues[1].titre, 'Mettre de côté les cadres en trop ?')
verifier('confirmation : rafales', texte:match('(%d+) rafales'), '3')
verifier('confirmation : cadres en rafale', texte:match('(%d+) cadres en rafale'), '15')
verifier('confirmation : protégés', texte:match('• (%d+) cadres protégés'), '5')
verifier('confirmation : gardés', texte:match('• (%d+) cadres gardés'), '4')
verifier('confirmation : retirés', texte:match('• (%d+) cadres à retirer'), '6')
verifier('confirmation : fichiers', texte:match('%((%d+) fichiers'), '7')
verifier('confirmation : rien n’est supprimé', texte:find('Rien n’est supprimé', 1, true) ~= nil, true)
verifier('une copie des doublons est ignorée, et signalée', texte:match('(%d+) photos de cette source sont ignorées'), '1')
verifier('sous-dossiers non demandés', sousDossiersDemande, false)
verifier('collection créée', noms(collectionRafales()),
  'DSCF1000.JPG DSCF1000.RAF DSCF1003.JPG DSCF1007.JPG DSCF2500.JPG DSCF2502.JPG DSCF2503.JPG')
verifier('une seule écriture', ecritures, 1)
verifier('la copie en trop des doublons n’est pas touchée', collectionRafales() and #collectionRafales().photos, 7)
verifier('collection ouverte', journal[1], 'source Rafales à retirer')
local traite = nil
for _, k in ipairs(motsCles) do if k.nom == 'Rafale traitée' then traite = k end end
verifier('mot-clé créé', traite ~= nil, true)
verifier('mot-clé non exporté', traite and traite.exporte, false)
verifier('mot-clé posé sur toutes les photos des rafales (gardées comme retirées)', noms(traite),
  'DSCF1000.JPG DSCF1000.RAF DSCF1001.JPG DSCF1002.JPG DSCF1003.JPG DSCF1004.JPG DSCF1005.JPG DSCF1006.JPG DSCF1007.JPG '
  .. 'DSCF2000-Modifier.JPG DSCF2000.JPG DSCF2001.JPG DSCF2002.JPG DSCF2500.JPG DSCF2501.JPG DSCF2502.JPG DSCF2503.JPG')
verifier('mot-clé : pas sur les cadres isolés ni sur la copie des doublons', noms(traite):find('DSCF3', 1, true) == nil
  and noms(traite):find('1003%-2') == nil, true)
verifier('un seul mot-clé des rafales (pas de doublon)', #motsCles, 2)
verifier('message final : mot-clé', dialogues[#dialogues] and dialogues[#dialogues].texte:find('Rafale traitée', 1, true) ~= nil, true)
verifier('message final', dialogues[#dialogues] and dialogues[#dialogues].titre, 'Rafales mises de côté')
local csv = lire(RAPPORT)
verifier('rapport écrit', csv:find('rafale;bloc;cadre;heure;decision;nettete;raison;fichiers', 1, true) ~= nil, true)
verifier('rapport : album protège', csv:find('DSCF1001;protégé;', 1, true) == nil and csv:find(';DSCF1001;', 1, true) ~= nil, true)
verifier('rapport : raison album', csv:find('collection « Google Photos - albums / 2026-08-15 – La java »', 1, true) ~= nil, true)
verifier('rapport : note', csv:find('note 3', 1, true) ~= nil, true)
verifier('rapport : copies virtuelles', csv:find('copies virtuelles', 1, true) ~= nil, true)
verifier('rapport : retouches Lightroom', csv:find('retouches Lightroom', 1, true) ~= nil, true)
verifier('rapport : version retouchée externe', csv:find('version retouchée (éditeur externe)', 1, true) ~= nil, true)
verifier('rapport : époque ne protège pas', csv:find('Goûter', 1, true), nil)
verifier('rapport : collection dynamique ne protège pas', csv:find('dynamique', 1, true), nil)
verifier('rapport : netteté à virgule', csv:find('70,00', 1, true) ~= nil, true)
verifier('rapport : moins net que', csv:find('moins net que DSCF1002', 1, true) ~= nil, true)
verifier('le plus net d’un bloc est gardé', csv:find('DSCF1002;[0-9:]+;garder') ~= nil, true)

-- 2. Relance : toutes les photos des rafales traitées portent le mot-clé, elles sont ignorées.
lancer({})
verifier('relance : plus aucune rafale', dialogues[1] and dialogues[1].texte:find('Aucune rafale', 1, true) ~= nil, true)
verifier('relance : aucune nouvelle écriture', ecritures, 1)

-- 2b. Même quand la collection « Rafales à retirer » est vidée et les cadres supprimés du catalogue :
-- les cadres gardés (seuls à rester, voisins les uns des autres) ne sont pas réduits une seconde fois.
local aSupprimer = {}
for _, ph in ipairs(collectionRafales().photos) do aSupprimer[ph] = true end
collectionRafales().photos = {}
local restantes = {}
for _, ph in ipairs(photosDuDossier) do if not aSupprimer[ph] then restantes[#restantes + 1] = ph end end
photosDuDossier = restantes
lancer({})
verifier('relance après suppression : toujours aucune rafale', dialogues[1] and dialogues[1].texte:find('Aucune rafale', 1, true) ~= nil, true)
-- Contre-épreuve : sans le mot-clé, ces cadres voisins formeraient une nouvelle rafale.
for _, k in ipairs(motsCles) do if k.nom == 'Rafale traitée' then k.photos = {} end end
lancer({ 'cancel' })
verifier('sans le mot-clé, les cadres restants formeraient une rafale', (dialogues[1] and dialogues[1].texte or ''):match('(%d+) rafales') ~= nil, true)

-- 2c. Mot-clé déjà posé par une exécution précédente, rangé sous un autre mot-clé : retrouvé, et signalé.
p = monter()
local parentOutillage = nouveauMotCle('Outillage', nil)
local dejaTraite = nouveauMotCle('Rafale traitée', parentOutillage)
dejaTraite.photos = { p['DSCF2500.JPG'], p['DSCF2501.JPG'] }
lancer({ 'cancel' })
texte = dialogues[1] and dialogues[1].texte or ''
verifier('mot-clé sous un parent : rafales', texte:match('(%d+) rafales'), '2')
verifier('mot-clé sous un parent : cadres en rafale', texte:match('(%d+) cadres en rafale'), '11')
verifier('mot-clé sous un parent : photos ignorées', texte:match('(%d+) photos de cette source sont ignorées'), '3')

-- 3. Annuler à la confirmation : rien n'est écrit.
p = monter()
lancer({ 'cancel' })
verifier('annulation : aucune écriture', ecritures, 0)
verifier('annulation : pas de collection', collectionRafales(), nil)

-- 4. Voir le rapport puis annuler.
p = monter()
lancer({ 'other', 'cancel' })
verifier('voir le rapport', journal[1] and journal[1]:match('rafales%.csv$') ~= nil, true)
verifier('voir le rapport : toujours rien d’écrit', ecritures, 0)

-- 5. Annuler la boîte de choix.
p = monter()
optionsTest = 'annuler'
lancer({})
verifier('boîte annulée : aucune boîte de confirmation', #dialogues, 0)
verifier('boîte annulée : aucune écriture', ecritures, 0)

-- 6. Un cadre sur 2.
p = monter()
optionsTest = { ratio = 2 }
lancer({ 'ok' })
verifier('ratio 2 : cadres retirés', noms(collectionRafales()), 'DSCF1003.JPG DSCF2500.JPG DSCF2503.JPG')

-- 7. Ratio absurde (1) : ramené à 2.
p = monter()
optionsTest = { ratio = 1 }
lancer({ 'ok' })
verifier('ratio 1 : ramené à 2', noms(collectionRafales()), 'DSCF1003.JPG DSCF2500.JPG DSCF2503.JPG')

-- 8. Sous-dossiers.
p = monter()
optionsTest = { ratio = 4, sousDossiers = true }
lancer({ 'cancel' })
verifier('sous-dossiers demandés', sousDossiersDemande, true)

-- 9. Sans ImageMagick : le premier cadre non protégé de chaque bloc est gardé.
p = monter()
magickDispo = false
lancer({ 'ok' })
texte = dialogues[1] and dialogues[1].texte or ''
verifier('sans ImageMagick : avertissement', texte:find('ImageMagick est introuvable', 1, true) ~= nil, true)
verifier('sans ImageMagick : on garde le premier', noms(collectionRafales()),
  'DSCF1002.JPG DSCF1003.JPG DSCF1007.JPG DSCF2501.JPG DSCF2502.JPG DSCF2503.JPG')

-- 10. Plusieurs sources, ou source inadaptée.
p = monter()
sources = { sources[1], sources[1] }
lancer({})
verifier('deux sources : message', dialogues[1] and dialogues[1].texte:find('un seul dossier', 1, true) ~= nil, true)
sources = { 'kAllPhotos' }
lancer({})
verifier('source spéciale : message', dialogues[1] and dialogues[1].titre, 'Réduire les rafales')
sources = { { type = function() return 'LrCollectionSet' end, getName = function() return 'Ensemble' end } }
lancer({})
verifier('ensemble de collections : message', dialogues[1] and dialogues[1].texte:find('pas un ensemble', 1, true) ~= nil, true)

-- 11. Collection comme source.
p = monter()
local collectionSource = { type = function() return 'LrCollection' end, getName = function() return 'Ma collection' end,
  getPhotos = function() return photosDuDossier end }
sources = { collectionSource }
lancer({ 'cancel' })
verifier('collection comme source : analysée', (dialogues[1] and dialogues[1].texte or ''):match('(%d+) rafales'), '3')

-- 12. Aucune rafale.
p = monter()
local seuls = {}
for _, nom in ipairs({ 'DSCF3000.JPG', 'DSCF3001.JPG', 'DSCF3002.JPG', 'DSCF3003.JPG', 'DSCF3004.JPG' }) do seuls[#seuls + 1] = p[nom] end
photosDuDossier = seuls
lancer({})
verifier('aucune rafale : message', dialogues[1] and dialogues[1].texte:find('Aucune rafale', 1, true) ~= nil, true)
verifier('aucune rafale : aucune écriture', ecritures, 0)

-- 13. Tout est protégé : rien à retirer.
p = monter()
for _, ph in ipairs(photosDuDossier) do ph.note = 1 end
lancer({})
verifier('tout protégé : message', dialogues[1] and dialogues[1].texte:find('rien à retirer', 1, true) ~= nil, true)
verifier('tout protégé : aucune écriture', ecritures, 0)
os.remove(RAPPORT)

print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
