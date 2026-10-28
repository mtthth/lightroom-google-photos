-- Fusionne les doublons des photos sélectionnées (ou, sans sélection, des photos affichées) : une même
-- photo importée plusieurs fois depuis des dossiers différents, ou existant en plusieurs tailles.
--
-- 0. Portée : les photos sélectionnées s'il y en a au moins deux, sinon toutes les photos affichées dans la
--    grille (dossier, collection…). Une copie n'est trouvée que si ses doublons sont dans cette portée.
-- 1. Empreinte exacte de chaque photo de la portée (voir Empreintes.lua) : deux contenus identiques
--    sont regroupés même si leurs noms ou leurs dates diffèrent.
--    Vidéos incluses : identité du fichier entier, vérifiée intégralement pour les gros candidats.
-- 2. Pour les photos dont l'empreinte diffère, recherche de variantes de même nom d'origine
--    (suffixes « -2 », « (2) », « -Modifier », « _filtered », DxO…) et de même date de prise de vue.
-- 3. Ces variantes sont comparées par une miniature 16 × 16 (ImageMagick, voir Vignettes.lua et
--    Similitude.lua) : si elles montrent la même vue, l'une est une copie réduite ou recompressée.
--    Les noms qui annoncent une retouche interdisent cette comparaison approximative, mais pas une
--    fusion lorsque l'empreinte exacte est identique. Les retouches Lightroom restent protégées
--    séparément par Doublons.lua.
-- 4. Pour chaque groupe, choix de la copie à garder (voir Doublons.lua) et plan de ce qui change
--    (Doublons.effets).
-- 5. Rapport HTML (rapport-doublons\index.html, voir RapportHtml.lua) : groupe par groupe, avec des
--    miniatures, la copie gardée et pourquoi, et ce qui change dans les collections et les métadonnées.
--    Il est construit à partir du même plan que celui qui est appliqué ensuite. Le détail est aussi écrit
--    dans doublons.csv.
-- 6. Après confirmation, la copie gardée prend la place des autres dans leurs collections (sauf
--    les collections dynamiques, qui se recalculent seules) et récupère ce qui lui manque :
--    mots-clés, note (la plus haute), drapeau, position GPS, et les champs de texte
--    listés dans Doublons.CHAMPS_TEXTE quand elle n'a rien dans le champ. Les autres copies quittent leurs
--    collections et sont rassemblées dans la collection « Doublons à retirer ».
--    Ne sont pas recopiés : réglages de développement (une copie retouchée dans Lightroom est
--    toujours la gardée, sinon le groupe reste « à vérifier »), copies virtuelles, instantanés,
--    piles, collections publiées (groupe « à vérifier »), fichiers annexes sur le disque (.xmp, .on1).
-- Le module laisse les copies écartées au catalogue. Leur retrait volontaire se termine en les
-- sélectionnant dans « Toutes les photos », puis Suppr → Retirer.

local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Catalogue = require 'Catalogue'
local Annulation = require 'Annulation'
local Csv = require 'Csv'
local Doublons = require 'Doublons'
local Epoques = require 'Epoques'
local Empreintes = require 'Empreintes'
local Historique = require 'Historique'
local Parallele = require 'Parallele'
local Rafales = require 'Rafales'
local RapportHtml = require 'RapportHtml'
local Similitude = require 'Similitude'
local Vignettes = require 'Vignettes'

local TAILLE_LOT = 1000
local LOT_ECRITURE = 100
local PARALLELE = 4   -- miniatures calculées en même temps
local GRANDE_PORTEE = 20000
local COLLECTION_DOUBLONS = Doublons.COLLECTION
-- Collections « à retirer » : la copie gardée ne les rejoint jamais.
local CORBEILLES = { [Doublons.COLLECTION] = true, [Rafales.COLLECTION] = true }
local DOSSIER_PROJET = LrPathUtils.parent(_PLUGIN.path)
local RAPPORT = LrPathUtils.child(DOSSIER_PROJET, 'doublons.csv')
local HISTORIQUE = LrPathUtils.child(DOSSIER_PROJET, 'photos-traitees.txt')
local DOSSIER_RAPPORT = LrPathUtils.child(DOSSIER_PROJET, 'rapport-doublons')
local RAPPORT_HTML = LrPathUtils.child(DOSSIER_RAPPORT, 'index.html')
local DOSSIER_APERCUS = LrPathUtils.child(DOSSIER_RAPPORT, 'vignettes')

local parLots = Parallele.parLots

local function nomFichier(chemin)
  return chemin:match('[^/\\]+$') or chemin
end

local function nombre(n)
  return (tostring(n):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', ''))
end

-- Boîte de départ : confirme la portée de la recherche. Renvoie { miniatures } ou nil si l'utilisateur
-- renonce.
local function demanderPortee(contexte, portee, magickDispo)
  local nb = #portee.photos
  if nb < 2 then
    LrDialogs.message('Fusionner les doublons',
      'Il faut au moins deux photos : sélectionne-en plusieurs, ou affiche un dossier ou une collection.', 'info')
    return nil
  end
  local f = LrView.osFactory()
  local proprietes = LrBinding.makePropertyTable(contexte)
  proprietes.miniatures = magickDispo
  local description
  if portee.genre == 'selection' then
    description = string.format('Chercher les doublons parmi les %s photos sélectionnées.', nombre(nb))
  else
    description = string.format('Aucune sélection (ou une seule photo) : chercher les doublons parmi les %s photos '
      .. 'affichées%s.', nombre(nb), portee.nom and (' (« ' .. portee.nom .. ' »)') or '')
  end
  local texte = description .. '\n\nUne copie n’est trouvée que si ses doublons sont aussi dans ces photos. '
    .. 'Les vidéos sont incluses : seules les copies de fichiers identiques sont fusionnées automatiquement. '
    .. 'Pour une version convertie ou recompressée, utilise la fusion de force. '
    .. 'Rien n’est modifié avant que tu aies vu le rapport et confirmé.'
  if nb > GRANDE_PORTEE then
    texte = texte .. '\n\nC’est beaucoup de photos : l’analyse peut durer plusieurs minutes.'
  end
  local colonne = { bind_to_object = proprietes, spacing = f:control_spacing() }
  colonne[#colonne + 1] = f:static_text { title = texte, width = 480, height_in_lines = nb > GRANDE_PORTEE and 9 or 7 }
  colonne[#colonne + 1] = f:checkbox {
    title = magickDispo and 'Miniatures dans le rapport HTML (un peu plus long)'
      or 'Miniatures dans le rapport HTML (ImageMagick est introuvable)',
    value = LrView.bind('miniatures'), enabled = magickDispo,
  }
  local reponse = LrDialogs.presentModalDialog {
    title = 'Fusionner les doublons', contents = f:column(colonne), actionVerb = 'Analyser',
  }
  if reponse ~= 'ok' then return nil end
  return { miniatures = proprietes.miniatures and true or false }
end

-- Les photos de la portée (hors copies virtuelles), avec taille, date et chemin.
-- Renvoie nil si l'utilisateur annule.
local function lireCopies(catalogue, photos, progression, historique)
  local copies = {}
  local complet = parLots(photos, TAILLE_LOT, function(lot, _, fin)
    if progression:isCanceled() then return false end
    progression:setCaption(string.format('Lecture des photos : %d / %d', fin, #photos))
    local brutes = catalogue:batchGetRawMetadata(lot,
      { 'path', 'fileSize', 'dateTimeOriginal', 'isVirtualCopy', 'countVirtualCopies', 'isVideo', 'fileFormat' })
    for _, photo in ipairs(lot) do
      local b = brutes[photo] or {}
      if not b.isVirtualCopy and b.path and b.fileSize and not Historique.contient(historique, b.path) then
        copies[#copies + 1] = {
          photo = photo, id = photo.localIdentifier, chemin = b.path, taille = b.fileSize,
          date = b.dateTimeOriginal, virtuelles = b.countVirtualCopies or 0,
          video = b.isVideo or b.fileFormat == 'VIDEO' or Empreintes.estVideo(b.path),
        }
      end
    end
    progression:setPortionComplete(fin, #photos)
  end)
  return complet and copies or nil
end

-- Images distinctes d'un groupe de candidats : une classe par empreinte, avec ses copies. Une
-- classe est « retouchée » quand tous ses fichiers portent un nom de retouche (« -Modifier »).
local function classesDuGroupe(groupe)
  local classes, parEmpreinte = {}, {}
  for _, c in ipairs(groupe) do
    if c.empreinte then
      local classe = parEmpreinte[c.empreinte]
      if not classe then
        classe = { copies = {}, octets = 0, retouchee = true }
        parEmpreinte[c.empreinte] = classe
        classes[#classes + 1] = classe
      end
      table.insert(classe.copies, c)
      classe.octets = math.max(classe.octets, c.taille or 0)
      if not Similitude.nomRetouche(nomFichier(c.chemin)) then classe.retouchee = false end
    end
  end
  return classes
end

local function calculerMiniature(classe)
  local vignette = Vignettes.signature(classe.copies[1].chemin)
  if vignette then
    classe.signature, classe.largeur, classe.hauteur = vignette.signature, vignette.largeur, vignette.hauteur
    classe.pixels = vignette.largeur * vignette.hauteur
  end
end

-- Cherche les groupes de copies d'une même photo. Renvoie nil si l'utilisateur annule, sinon
--   groupes : listes de copies à départager (même image, ou même vue en plus petit) ;
--   differents : candidats qui restent à part (images différentes : versions retouchées…) ;
--   illisibles : fichiers qui n'ont pas pu être lus ;
--   sansMiniature : images dont ImageMagick n'a pas pu faire de miniature (conservées) ;
--   magickAbsent : vrai si des comparaisons de vues étaient utiles mais ImageMagick est introuvable.
local function chercherGroupes(copies, progression)
  -- L'empreinte exacte est indépendante du nom et de la date : on la calcule pour toute la portée.
  -- Le cache évite de relire deux entrées Lightroom qui pointent vers le même chemin.
  local empreintesParChemin = {}
  local illisibles = 0
  for fait, c in ipairs(copies) do
    if progression:isCanceled() then return nil end
    progression:setCaption(string.format('Empreinte des photos : %d / %d', fait, #copies))
    progression:setPortionComplete(fait, #copies)
    c.octets = c.taille
    local cleChemin = c.chemin:gsub('/', '\\'):lower()
    local empreinte = empreintesParChemin[cleChemin]
    if empreinte == nil then
      local ok, resultat = LrTasks.pcall(Empreintes.empreinte, c.chemin, c.video)
      empreinte = ok and resultat or false
      empreintesParChemin[cleChemin] = empreinte
    end
    c.empreinte = empreinte ~= false and empreinte or nil
    if not c.empreinte then illisibles = illisibles + 1 end
    LrTasks.yield()
  end

  -- Le début et la fin servent seulement de préfiltre pour les gros fichiers. Deux vidéos peuvent
  -- partager ces morceaux et différer au milieu : lire tous les octets des seuls candidats.
  local gros = Doublons.grouper(copies, function(c)
    return c.empreinte and c.empreinte:match('^gros:') and c.empreinte or nil
  end)
  local completes, total, fait = {}, 0, 0
  for _, groupe in ipairs(gros) do total = total + #groupe end
  for _, groupe in ipairs(gros) do
    for _, c in ipairs(groupe) do
      if progression:isCanceled() then return nil end
      fait = fait + 1
      progression:setCaption(string.format('Vérification complète des gros fichiers : %d / %d', fait, total))
      progression:setPortionComplete(fait, total)
      local cleChemin = c.chemin:gsub('/', '\\'):lower()
      if completes[cleChemin] == nil then
        local ok, resultat = LrTasks.pcall(Empreintes.empreinteComplete, c.chemin,
          function() return progression:isCanceled() end)
        completes[cleChemin] = ok and resultat or false
      end
      if progression:isCanceled() then return nil end
      c.empreinte = completes[cleChemin] or nil
      if not c.empreinte then illisibles = illisibles + 1 end
    end
  end
  -- Un préfiltre resté seul n'est jamais une preuve d'identité entre deux chemins.
  for _, c in ipairs(copies) do
    if c.empreinte and c.empreinte:match('^gros:') then
      c.empreinte = c.empreinte .. '|' .. c.chemin:gsub('/', '\\'):lower()
    end
  end

  local candidats = Doublons.grouper(copies, function(c)
    -- Une image du clip ne suffit pas à comparer sa durée, ses autres images et sa bande-son.
    if c.video then return nil end
    local extension = (c.chemin:match('%.([^%./\\]*)$') or ''):lower()
    return Doublons.nomDeBase(c.chemin) .. '.' .. extension .. '|'
      .. (c.date and string.format('%d', math.floor(c.date)) or '')
  end)
  local analyses = {}
  for _, groupe in ipairs(candidats) do
    -- Un fichier dont le nom annonce une retouche (« -Modifier », « _filtered », « DxO_… ») ne sera
    -- jamais fusionné par simple ressemblance visuelle. Les empreintes exactes identiques ont déjà
    -- été regroupées sans tenir compte de ces marqueurs.
    local marques, ordinaires = {}, {}
    for _, c in ipairs(groupe) do
      if Similitude.nomRetouche(nomFichier(c.chemin)) then marques[#marques + 1] = c else ordinaires[#ordinaires + 1] = c end
    end
    local melange = #marques > 0 and #ordinaires > 0
    for _, partie in ipairs(melange and { ordinaires, marques } or { groupe }) do
      analyses[#analyses + 1] = { copies = partie, classes = classesDuGroupe(partie), origine = groupe, melange = melange }
    end
  end

  -- Miniature de chaque image quand un groupe en compte plusieurs.
  local aComparer, nbMultiples = {}, 0
  for _, a in ipairs(analyses) do
    if #a.classes >= 2 then
      nbMultiples = nbMultiples + 1
      for _, classe in ipairs(a.classes) do aComparer[#aComparer + 1] = classe end
    end
  end
  local magickDispo = Vignettes.magick() ~= nil
  if magickDispo and #aComparer > 0 then
    if not Parallele.pourChaque(aComparer, PARALLELE, calculerMiniature, progression,
      'Comparaison des versions de taille différente : %d / %d') then return nil end
  end

  local groupes, differents, sansMiniature = {}, {}, 0
  local signales = {}   -- groupes de candidats déjà inscrits dans `differents`
  for _, a in ipairs(analyses) do
    local ensembles = {}
    if #a.classes >= 2 and magickDispo then
      ensembles = Similitude.regrouper(a.classes)
      for _, classe in ipairs(a.classes) do
        if not classe.signature then sansMiniature = sansMiniature + 1 end
      end
    else
      for i, classe in ipairs(a.classes) do ensembles[i] = { classe } end
    end
    for _, ensemble in ipairs(ensembles) do
      local liste = {}
      for _, classe in ipairs(ensemble) do
        for _, c in ipairs(classe.copies) do
          c.octets = c.taille
          if classe.pixels then
            c.pixels = classe.pixels
            c.dimensions = string.format('%dx%d', classe.largeur, classe.hauteur)
          end
          liste[#liste + 1] = c
        end
      end
      if #liste > 1 then groupes[#groupes + 1] = liste end
    end
    -- Versions qui restent à part : images différentes, ou version à nom de retouche à côté d'une
    -- copie sans marqueur. Le groupe de candidats est listé une seule fois, en entier.
    if (#ensembles > 1 or a.melange) and not signales[a.origine] then
      signales[a.origine] = true
      local entier = {}
      for _, c in ipairs(a.origine) do
        if c.empreinte then
          c.octets = c.taille
          entier[#entier + 1] = c
        end
      end
      differents[#differents + 1] = entier
    end
  end

  -- Les similarités de miniature restent limitées aux candidats de même nom/date. Les empreintes
  -- complètes, elles, regroupent les mêmes contenus partout dans la portée, quel que soit leur nom.
  local parent = {}
  for _, c in ipairs(copies) do parent[c] = c end
  local function racine(c)
    if parent[c] ~= c then parent[c] = racine(parent[c]) end
    return parent[c]
  end
  local function unir(groupe)
    local premier
    for _, c in ipairs(groupe) do
      if not premier then
        premier = c
      else
        local a, b = racine(premier), racine(c)
        if a ~= b then parent[b] = a end
      end
    end
  end
  for _, groupe in ipairs(groupes) do unir(groupe) end

  local parEmpreinte = {}
  for _, c in ipairs(copies) do
    if c.empreinte and not c.empreinte:match('^gros:') then
      parEmpreinte[c.empreinte] = parEmpreinte[c.empreinte] or {}
      table.insert(parEmpreinte[c.empreinte], c)
    end
  end
  for _, groupe in pairs(parEmpreinte) do
    if #groupe > 1 then unir(groupe) end
  end

  local composantes, ordreComposantes = {}, {}
  for _, c in ipairs(copies) do
    local r = racine(c)
    if not composantes[r] then
      composantes[r] = {}
      ordreComposantes[#ordreComposantes + 1] = r
    end
    table.insert(composantes[r], c)
  end
  local groupesFinaux = {}
  for _, r in ipairs(ordreComposantes) do
    if #composantes[r] > 1 then groupesFinaux[#groupesFinaux + 1] = composantes[r] end
  end

  local differentsFinaux = {}
  for _, groupe in ipairs(differents) do
    local racines, nombre = {}, 0
    for _, c in ipairs(groupe) do
      local r = racine(c)
      if not racines[r] then racines[r] = true; nombre = nombre + 1 end
    end
    if nombre > 1 then differentsFinaux[#differentsFinaux + 1] = groupe end
  end
  return {
    groupes = groupesFinaux, differents = differentsFinaux, illisibles = illisibles, sansMiniature = sansMiniature,
    magickAbsent = not magickDispo and nbMultiples > 0,
  }
end

-- Collections d'une photo : { id, nom (affichable), dynamique, exclue (une corbeille), objet }.
local function lireCollections(photo)
  local r = {}
  for _, collection in ipairs(photo:getContainedCollections()) do
    r[#r + 1] = {
      objet = collection, id = collection.localIdentifier, nom = Catalogue.etiquetteCollection(collection),
      dynamique = collection:isSmartCollection(), exclue = CORBEILLES[collection:getName()] or false,
    }
  end
  return r
end

-- Complète les copies des groupes : retouches, notes, mots-clés, collections… et publication.
local function details(catalogue, groupes, progression)
  progression:setCaption('Lecture des retouches et des métadonnées…')
  local ok, retouchees = LrTasks.pcall(function()
    return catalogue:findPhotos { searchDesc = { criteria = 'hasAdjustments', operation = 'isTrue', value = true } }
  end)
  if not ok then error('impossible de savoir quelles photos sont retouchées : ' .. tostring(retouchees), 0) end
  local estRetouchee = {}
  for _, p in ipairs(retouchees) do estRetouchee[p.localIdentifier] = true end

  local copies, photos = {}, {}
  for _, g in ipairs(groupes) do
    for _, c in ipairs(g) do
      copies[#copies + 1] = c
      photos[#photos + 1] = c.photo
    end
  end
  local parPhoto = {}
  for _, c in ipairs(copies) do parPhoto[c.photo] = c end
  local fait = 0
  parLots(photos, TAILLE_LOT, function(lot)
    local brutes = catalogue:batchGetRawMetadata(lot, { 'rating', 'pickStatus', 'keywords', 'gps' })
    local formatees = catalogue:batchGetFormattedMetadata(lot, Doublons.CHAMPS_TEXTE)
    for _, photo in ipairs(lot) do
      local c, b, f = parPhoto[photo], brutes[photo] or {}, formatees[photo] or {}
      c.retouchee = estRetouchee[c.id] or false
      c.note, c.drapeau, c.gps = b.rating or 0, b.pickStatus or 0, b.gps
      c.motsCles = {}
      for _, mot in ipairs(b.keywords or {}) do c.motsCles[#c.motsCles + 1] = { objet = mot, nom = mot:getName() } end
      c.textes = {}
      c.annotee = c.note > 0 or c.drapeau ~= 0 or #c.motsCles > 0
      for _, cle in ipairs(Doublons.CHAMPS_TEXTE) do
        c.textes[cle] = f[cle] or ''
        if c.textes[cle] ~= '' then c.annotee = true end
      end
      c.publiee = #photo:getContainedPublishedCollections() > 0
      c.collections = lireCollections(photo)
      fait = fait + 1
      if fait % 200 == 0 then
        progression:setCaption(string.format('Lecture des métadonnées : %d / %d', fait, #photos))
        LrTasks.yield()
      end
    end
  end)
end

-- La copie gardée prend la place de chaque copie retirée, selon le plan (Doublons.effets) montré dans le
-- rapport. À appeler dans un accès en écriture.
local function fusionnerGroupe(decision, corbeille)
  local e, p = decision.effets, decision.garde.photo
  for _, col in ipairs(e.corbeillesGardee) do col.objet:removePhotos({ p }) end
  for _, col in ipairs(e.collections) do col.objet:addPhotos({ p }) end
  for _, q in ipairs(e.quittees) do q.collection.objet:removePhotos({ q.copie.photo }) end
  for _, mot in ipairs(e.motsCles) do p:addKeyword(mot.objet) end
  if e.note then p:setRawMetadata('rating', e.note) end
  if e.drapeau then p:setRawMetadata('pickStatus', e.drapeau) end
  for _, t in ipairs(e.textes) do p:setRawMetadata(t.cle, t.valeur) end
  if e.gps then p:setRawMetadata('gps', e.gps) end
  local retirees = {}
  for i, c in ipairs(decision.retirees) do retirees[i] = c.photo end
  corbeille:addPhotos(retirees)
  corbeille:removePhotos({ p })
end

local function fusionner(catalogue, decisions, progression)
  local photos, gardees, cheminsGardes = {}, {}, {}
  for _, d in ipairs(decisions) do
    gardees[#gardees + 1] = d.garde.chemin
    cheminsGardes[d.garde.chemin:gsub('/', '\\'):lower()] = true
  end
  for _, d in ipairs(decisions) do
    for _, c in ipairs(d.retirees) do
      if not cheminsGardes[c.chemin:gsub('/', '\\'):lower()] then
        photos[#photos + 1] = {
          chemin = c.chemin, fichier = nomFichier(c.chemin),
          date = c.date and Epoques.texte(Epoques.depuisLightroom(c.date, 0)) or '',
        }
      end
    end
  end
  local corbeille
  local historiqueOk, erreurHistorique = Annulation.action(catalogue, HISTORIQUE, 'Fusionner les doublons',
    { retablir = gardees, type = 'doublon', photos = photos }, function()
    corbeille = catalogue:createCollection(COLLECTION_DOUBLONS, nil, true)
    for i, d in ipairs(decisions) do
      if progression:isCanceled() then error('Fusion annulée : aucune modification du catalogue n’a été conservée.', 0) end
      fusionnerGroupe(d, corbeille)
      progression:setPortionComplete(i, #decisions)
      if i % LOT_ECRITURE == 0 then
        progression:setCaption(string.format('Fusion des doublons : %d / %d groupes', i, #decisions))
        LrTasks.yield()
      end
    end
  end)
  for _, d in ipairs(decisions) do
    for _, col in ipairs(d.garde.photo:getContainedCollections()) do
      if CORBEILLES[col:getName()] then
        error('La photo gardée est encore dans « ' .. col:getName() .. ' ». Ne retire aucune photo du catalogue.', 0)
      end
    end
  end
  if historiqueOk then
    local historique = Historique.lire(HISTORIQUE)
    for _, chemin in ipairs(gardees) do
      if Historique.contient(historique, chemin) then error('Une photo gardée reste exclue dans l’historique.', 0) end
    end
  end
  return corbeille, #decisions, erreurHistorique
end

local function ko(octets)
  return string.format('%d Ko', math.floor((octets or 0) / 1024 + 0.5))
end

-- Pourquoi une copie est retirée : même image, ou copie réduite / recompressée de la gardée.
local function motifRetrait(c, garde)
  if c.empreinte ~= garde.empreinte then
    return string.format('copie réduite ou recompressée (%s, %s contre %s, %s)',
      c.dimensions or '?', ko(c.octets), garde.dimensions or '?', ko(garde.octets))
  end
  return c.retouchee and 'retouchée' or ''
end

local function ecrireRapportCsv(decisions, differents)
  local lignes = { { 'groupe', 'decision', 'fichier', 'detail' } }
  for i, groupe in ipairs(differents) do
    for _, c in ipairs(groupe) do
      table.insert(lignes, { 'D' .. i, 'non fusionné', c.chemin,
        (c.dimensions and (c.dimensions .. ' : ') or '')
          .. (Similitude.nomRetouche(nomFichier(c.chemin))
            and 'version retouchée d’après son nom : conservée'
            or 'même nom d’origine et même date, image différente (version retouchée, copie recompressée…)') })
    end
  end
  for i, d in ipairs(decisions) do
    local motif = d.aVerifier and ('à vérifier : ' .. d.aVerifier) or ''
    table.insert(lignes, { i, d.aVerifier and 'à vérifier' or 'garder', d.garde.chemin,
      motif ~= '' and motif or (d.garde.retouchee and 'retouchée' or '') })
    for _, c in ipairs(d.retirees) do
      table.insert(lignes, { i, d.aVerifier and 'à vérifier' or 'retirer', c.chemin, motifRetrait(c, d.garde) })
    end
  end
  Csv.ecrire(RAPPORT, lignes)
end

-- Aperçus du rapport : un petit JPEG par photo montrée, dans rapport-doublons\vignettes (réutilisé d'un
-- rapport à l'autre). Renvoie false si l'utilisateur annule.
local function genererApercus(decisions, differents, progression)
  local copies, vus = {}, {}
  local function voir(c)
    if not vus[c.id] then
      vus[c.id] = true
      copies[#copies + 1] = c
    end
  end
  for _, d in ipairs(decisions) do
    voir(d.garde)
    for _, c in ipairs(d.retirees) do voir(c) end
  end
  for _, groupe in ipairs(differents) do
    for _, c in ipairs(groupe) do voir(c) end
  end

  LrFileUtils.createAllDirectories(DOSSIER_APERCUS)
  local aFaire = {}
  for _, c in ipairs(copies) do
    c.fichierApercu = string.format('%s-%d.jpg', tostring(c.id), c.taille or 0)
    c.cheminApercu = LrPathUtils.child(DOSSIER_APERCUS, c.fichierApercu)
    if LrFileUtils.exists(c.cheminApercu) ~= 'file' then aFaire[#aFaire + 1] = c end
  end
  local complet = true
  if #aFaire > 0 then
    complet = Parallele.pourChaque(aFaire, PARALLELE, function(c) Vignettes.apercu(c.chemin, c.cheminApercu) end,
      progression, 'Miniatures du rapport : %d / %d')
  end
  for _, c in ipairs(copies) do c.avecApercu = LrFileUtils.exists(c.cheminApercu) == 'file' end
  return complet
end

local function dateDuRapport()
  local ok, texte = LrTasks.pcall(function() return LrDate.timeToUserFormat(LrDate.currentTime(), '%Y-%m-%d %H:%M') end)
  return ok and texte or ''
end

local function ecrireRapportHtml(modele)
  LrFileUtils.createAllDirectories(DOSSIER_RAPPORT)
  local f = io.open(RAPPORT_HTML, 'wb')
  if not f then error('Impossible d’écrire ' .. RAPPORT_HTML .. ' (page ouverte dans un autre programme ?)', 0) end
  f:write(RapportHtml.page(modele))
  f:close()
end

local function decrirePortee(portee)
  if portee.genre == 'selection' then return string.format('les %s photos sélectionnées', nombre(#portee.photos)) end
  return string.format('les %s photos affichées%s', nombre(#portee.photos), portee.nom and (' (« ' .. portee.nom .. ' »)') or '')
end

LrTasks.startAsyncTask(function()
  LrFunctionContext.callWithContext('fusionnerDoublons', function(contexte)
    local etape = 'choix de la portée'
    local ok, erreur = LrTasks.pcall(function()
      local catalogue = LrApplication.activeCatalog()
      local portee = Catalogue.portee(catalogue)
      local options = demanderPortee(contexte, portee, Vignettes.magick() ~= nil)
      if not options then return end
      local progression = LrProgressScope { title = 'Recherche des doublons', functionContext = contexte }

      etape = 'lecture des photos'
      Annulation.synchroniser(catalogue, HISTORIQUE)
      local historique = Historique.lire(HISTORIQUE)
      local copies = lireCopies(catalogue, portee.photos, progression, historique)
      if not copies then return end
      etape = 'comparaison des fichiers'
      local trouves = chercherGroupes(copies, progression)
      if not trouves then return end
      local groupes, differents = trouves.groupes, trouves.differents
      if #groupes == 0 then
        progression:done()
        LrDialogs.message('Doublons', string.format('Aucun fichier en double parmi %s.', decrirePortee(portee))
          .. (#differents > 0 and string.format('\n%d groupes de photos de même nom d’origine et même date ont '
            .. 'des versions distinctes (retouchées, recadrées…) : elles sont toutes conservées.', #differents) or ''), 'info')
        return
      end
      etape = 'lecture des métadonnées'
      details(catalogue, groupes, progression)

      local decisions, aFusionner = {}, {}
      local nbRetirees, nbReduites, nbAVerifier = 0, 0, 0
      for i, g in ipairs(groupes) do
        local d = Doublons.decider(g)
        decisions[i] = d
        if d.aVerifier then
          nbAVerifier = nbAVerifier + 1
        else
          d.effets = Doublons.effets(d)
          aFusionner[#aFusionner + 1] = d
          nbRetirees = nbRetirees + #d.retirees
          for _, c in ipairs(d.retirees) do
            if c.empreinte ~= d.garde.empreinte then nbReduites = nbReduites + 1 end
          end
        end
      end

      etape = 'miniatures du rapport'
      if options.miniatures and not genererApercus(decisions, differents, progression) then return end

      -- Remarques du rapport et du bilan.
      local remarques = {}
      if trouves.magickAbsent then
        remarques[#remarques + 1] = 'ImageMagick est introuvable : les copies réduites ou recompressées n’ont pas '
          .. 'été cherchées (seuls les fichiers de même image sont fusionnés).'
      end
      if trouves.sansMiniature > 0 then
        remarques[#remarques + 1] = string.format('%d images n’ont pas pu être comparées par ImageMagick '
          .. '(format non lu) : elles sont conservées.', trouves.sansMiniature)
      end
      if trouves.illisibles > 0 then
        remarques[#remarques + 1] = string.format('%d fichiers illisibles (absents ou hors ligne) n’ont pas pu être comparés.',
          trouves.illisibles)
      end
      if not options.miniatures then remarques[#remarques + 1] = 'Rapport sans miniatures.' end

      etape = 'écriture du rapport'
      ecrireRapportCsv(decisions, differents)
      ecrireRapportHtml({
        portee = decrirePortee(portee), date = dateDuRapport(), collection = COLLECTION_DOUBLONS,
        decisions = decisions, differents = differents, notes = remarques,
        vignette = function(c) return c.avecApercu and ('vignettes/' .. c.fichierApercu) or nil end,
      })
      progression:done()

      local message = string.format(
        '%s : %d groupes de copies d’une même photo, %d copies en trop%s.\n\n'
        .. 'Pour chaque groupe, le rapport montre la copie gardée (la plus grande image ; à image identique, la '
        .. 'retouchée, puis la mieux rangée), ce qui est retiré, et ce qui change dans les collections et les '
        .. 'métadonnées. Clique sur « Voir le rapport » (il s’ouvre dans ton navigateur) : rien n’est modifié '
        .. 'tant que tu ne cliques pas sur « Fusionner ». Les copies en trop sont rassemblées dans la collection '
        .. '« %s », à retirer ensuite du catalogue. Leurs chemins et dates sont mémorisés dans %s pour que '
        .. '« Recréer les albums » continue de les ignorer après vidage de la collection.',
        decrirePortee(portee):gsub('^les', 'Parmi les'), #aFusionner, nbRetirees,
        nbReduites > 0 and string.format(' (dont %d copies réduites ou recompressées)', nbReduites) or '',
        COLLECTION_DOUBLONS, HISTORIQUE)
      if nbAVerifier > 0 then
        message = message .. string.format('\n\n%d groupes à vérifier (plusieurs copies retouchées, copie '
          .. 'réduite retouchée…) restent tels quels.', nbAVerifier)
      end
      if #differents > 0 then
        message = message .. string.format('\n%d groupes de photos de même nom d’origine et même date ont des '
          .. 'versions distinctes (image différente, ou nom de retouche : « -Modifier », « -Modifié », « _filtered », '
          .. '« DxO_… »). Elles sont toutes conservées.', #differents)
      end
      for _, r in ipairs(remarques) do
        if r ~= 'Rapport sans miniatures.' then message = message .. '\n' .. r end
      end
      message = message .. '\n\nRapport : ' .. RAPPORT_HTML

      local choix
      repeat
        choix = LrDialogs.confirm('Fusionner les doublons ?', message, 'Fusionner', 'Annuler', 'Voir le rapport')
        if choix == 'other' then LrHttp.openUrlInBrowser(RapportHtml.urlFichier(RAPPORT_HTML)) end
      until choix ~= 'other'
      if choix ~= 'ok' or #aFusionner == 0 then return end

      etape = 'fusion des doublons'
      local fusion = LrProgressScope { title = 'Fusion des doublons', functionContext = contexte }
      local _, nbFusionnes, erreurHistorique = fusionner(catalogue, aFusionner, fusion)
      fusion:done()
      local bilan = string.format(
        '%d groupes fusionnés sur %d. Les copies en trop sont dans la collection « %s ». '
        .. '\n\nElles restent visibles dans les dossiers tant qu’elles sont au catalogue. Pour terminer le retrait, '
        .. 'sélectionne uniquement les copies écartées dans « Catalogue → Toutes les photos », puis Suppr → « Retirer ».',
        nbFusionnes, #aFusionner, COLLECTION_DOUBLONS)
        .. '\n\nCtrl+Z annule cette fusion complète, y compris l’historique des exclusions.'
      if erreurHistorique then bilan = bilan .. '\nHistorique texte à synchroniser : ' .. tostring(erreurHistorique) end
      LrDialogs.message('Doublons fusionnés', bilan, erreurHistorique and 'warning' or 'info')
    end)
    if not ok then
      LrDialogs.message('Erreur pendant la fusion des doublons',
        string.format('Étape : %s\n%s', etape, tostring(erreur)), 'critical')
    end
  end)
end)
