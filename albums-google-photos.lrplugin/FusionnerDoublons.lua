-- Fusionne les doublons du catalogue : une même photo importée plusieurs fois depuis des dossiers
-- différents, ou existant en plusieurs tailles.
--
-- 1. Candidats : photos de même nom d'origine (suffixes « -2 », « (2) », « -Modifier »,
--    « -Modifié-2026-08-02T22-37-43 », « _filtered », « -20260821-DxO_DeepPRIME XD3 » ignorés) et de
--    même date de prise de vue. Les fichiers dont le nom annonce une retouche sont traités à part :
--    jamais retirés au profit d'une copie sans marqueur, même si leur image est identique.
-- 2. Comparaison des images (empreinte, voir Empreintes.lua) : deux copies dont seules les
--    métadonnées intégrées diffèrent sont des copies du même fichier.
-- 3. Les images qui diffèrent sont comparées par une miniature (ImageMagick, voir Vignettes.lua et
--    Similitude.lua) : si elles montrent exactement la même vue (même forme, mêmes couleurs), l'une
--    est une copie réduite ou recompressée de l'autre et on garde la plus grande. Une version
--    retouchée (exposition, teinte, recadrage, éditeur externe, nom « -Modifier ») n'est jamais
--    prise pour une copie : elle est conservée avec l'original et listée dans le rapport.
--    Les retouches faites dans Lightroom ne changent pas le fichier : voir Doublons.lua.
-- 4. Pour chaque groupe, choix de la copie à garder (voir Doublons.lua).
-- 5. Après confirmation, la copie gardée prend la place des autres dans leurs collections (sauf
--    les collections dynamiques, qui se recalculent seules) et récupère ce qui lui manque :
--    mots-clés, note (la plus haute), drapeau « retenue », position GPS, et les champs de texte
--    listés dans CHAMPS_TEXTE quand elle n'a rien dans le champ. Les autres copies quittent leurs
--    collections et sont rassemblées dans la collection « Doublons à retirer ».
--    Ne sont pas recopiés : réglages de développement (une copie retouchée dans Lightroom est
--    toujours la gardée, sinon le groupe reste « à vérifier »), copies virtuelles, instantanés,
--    piles, collections publiées (groupe « à vérifier »), fichiers annexes sur le disque (.xmp, .on1).
-- Le SDK de Lightroom ne permet pas de retirer une photo du catalogue : il reste à ouvrir cette
-- collection, tout sélectionner et appuyer sur Suppr.
-- Le détail des décisions est écrit dans doublons.csv, dans le dossier du projet.

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrShell = import 'LrShell'
local LrTasks = import 'LrTasks'

local Csv = require 'Csv'
local Doublons = require 'Doublons'
local Empreintes = require 'Empreintes'
local Parallele = require 'Parallele'
local Similitude = require 'Similitude'
local Vignettes = require 'Vignettes'

local TAILLE_LOT = 1000
local LOT_ECRITURE = 100
local PARALLELE = 4   -- miniatures calculées en même temps
local COLLECTION_DOUBLONS = Doublons.COLLECTION
-- Champs de texte recopiés sur la copie gardée quand elle n'a rien dans le champ (clés de
-- getFormattedMetadata et de setRawMetadata) : libellé, titre, légende, titre court, auteur,
-- copyright, lieu, ville, région, pays, code du pays, personnes, événement.
local CHAMPS_TEXTE = { 'label', 'title', 'caption', 'headline', 'creator', 'copyright', 'location', 'city',
  'stateProvince', 'country', 'isoCountryCode', 'personShown', 'event' }
local RAPPORT = LrPathUtils.child(LrPathUtils.parent(_PLUGIN.path), 'doublons.csv')

local parLots = Parallele.parLots

local function nomFichier(chemin)
  return chemin:match('[^/\\]+$') or chemin
end

-- Toutes les photos du catalogue (hors copies virtuelles), avec taille, date et chemin.
-- Renvoie nil si l'utilisateur annule.
local function lireCatalogue(catalogue, progression)
  local photos = catalogue:getAllPhotos()
  local copies = {}
  local complet = parLots(photos, TAILLE_LOT, function(lot, _, fin)
    if progression:isCanceled() then return false end
    progression:setCaption(string.format('Lecture du catalogue : %d / %d photos', fin, #photos))
    local brutes = catalogue:batchGetRawMetadata(lot,
      { 'path', 'fileSize', 'dateTimeOriginal', 'isVirtualCopy', 'countVirtualCopies' })
    for _, photo in ipairs(lot) do
      local b = brutes[photo] or {}
      if not b.isVirtualCopy and b.path and b.fileSize then
        copies[#copies + 1] = {
          photo = photo, id = photo.localIdentifier, chemin = b.path, taille = b.fileSize,
          date = b.dateTimeOriginal, virtuelles = b.countVirtualCopies or 0,
        }
      end
    end
    progression:setPortionComplete(fin, #photos)
  end)
  return complet and copies or nil, #photos
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
  local candidats = Doublons.grouper(copies, function(c)
    local extension = (c.chemin:match('%.([^%./\\]*)$') or ''):lower()
    return Doublons.nomDeBase(c.chemin) .. '.' .. extension .. '|'
      .. (c.date and string.format('%d', math.floor(c.date)) or '')
  end)
  local total = 0
  for _, g in ipairs(candidats) do total = total + #g end

  -- Empreinte de l'image de chaque candidat.
  local fait, illisibles = 0, 0
  local analyses = {}
  for _, groupe in ipairs(candidats) do
    for _, c in ipairs(groupe) do
      if progression:isCanceled() then return nil end
      fait = fait + 1
      progression:setCaption(string.format('Comparaison des fichiers : %d / %d', fait, total))
      progression:setPortionComplete(fait, total)
      local ok, empreinte = LrTasks.pcall(Empreintes.empreinte, c.chemin)
      c.empreinte = ok and empreinte or nil
      if not c.empreinte then illisibles = illisibles + 1 end
      LrTasks.yield()
    end
    -- Un fichier dont le nom annonce une retouche (« -Modifier », « _filtered », « DxO_… ») est une
    -- version voulue : jamais retiré au profit d'une copie sans marqueur, même si son image est
    -- (encore) identique. Marqués et non marqués sont donc traités à part ; deux fichiers marqués
    -- identiques restent des doublons l'un de l'autre.
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
    local tous = {}
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
          tous[#tous + 1] = c
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
  return {
    groupes = groupes, differents = differents, illisibles = illisibles, sansMiniature = sansMiniature,
    magickAbsent = not magickDispo and nbMultiples > 0,
  }
end

-- Complète les copies des groupes : retouches, notes, mots-clés… et publication.
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
  parLots(photos, TAILLE_LOT, function(lot)
    local brutes = catalogue:batchGetRawMetadata(lot, { 'rating', 'pickStatus', 'keywords', 'gps' })
    local formatees = catalogue:batchGetFormattedMetadata(lot, CHAMPS_TEXTE)
    for _, photo in ipairs(lot) do
      local c, b, f = parPhoto[photo], brutes[photo] or {}, formatees[photo] or {}
      c.retouchee = estRetouchee[c.id] or false
      c.note, c.drapeau, c.motsCles, c.gps = b.rating or 0, b.pickStatus or 0, b.keywords or {}, b.gps
      c.textes = {}
      c.annotee = c.note > 0 or c.drapeau ~= 0 or #c.motsCles > 0
      for _, cle in ipairs(CHAMPS_TEXTE) do
        c.textes[cle] = f[cle] or ''
        if c.textes[cle] ~= '' then c.annotee = true end
      end
      c.publiee = #photo:getContainedPublishedCollections() > 0
    end
  end)
end

-- La copie gardée prend la place de chaque copie retirée. À appeler dans un accès en écriture,
-- après avoir lu les collections des copies retirées (champ collections).
local function fusionnerGroupe(decision, corbeille)
  local garde = decision.garde
  local p = garde.photo
  local retirees = {}
  for _, c in ipairs(decision.retirees) do
    retirees[#retirees + 1] = c.photo
    for _, collection in ipairs(c.collections or {}) do
      if collection.localIdentifier ~= corbeille.localIdentifier and not collection:isSmartCollection() then
        collection:addPhotos({ p })
        collection:removePhotos({ c.photo })
      end
    end
    for _, motCle in ipairs(c.motsCles) do p:addKeyword(motCle) end
    if c.note > garde.note then
      p:setRawMetadata('rating', c.note)
      garde.note = c.note
    end
    if c.drapeau == 1 and garde.drapeau ~= 1 then
      p:setRawMetadata('pickStatus', 1)
      garde.drapeau = 1
    end
    for _, cle in ipairs(CHAMPS_TEXTE) do
      if garde.textes[cle] == '' and c.textes[cle] ~= '' then
        p:setRawMetadata(cle, c.textes[cle])
        garde.textes[cle] = c.textes[cle]
      end
    end
    if not garde.gps and c.gps then
      p:setRawMetadata('gps', c.gps)
      garde.gps = c.gps
    end
  end
  corbeille:addPhotos(retirees)
end

local function fusionner(catalogue, decisions, progression)
  local corbeille
  catalogue:withWriteAccessDo('Créer la collection des doublons', function()
    corbeille = catalogue:createCollection(COLLECTION_DOUBLONS, nil, true)
  end, { timeout = 30 })
  local nbFusionnes = 0
  parLots(decisions, LOT_ECRITURE, function(lot, _, fin)
    if progression:isCanceled() then return false end
    progression:setCaption(string.format('Fusion des doublons : %d / %d groupes', fin, #decisions))
    -- Lectures en dehors de l'accès en écriture.
    for _, d in ipairs(lot) do
      for _, c in ipairs(d.retirees) do c.collections = c.photo:getContainedCollections() end
    end
    catalogue:withWriteAccessDo('Fusionner des doublons', function()
      for _, d in ipairs(lot) do fusionnerGroupe(d, corbeille) end
    end, { timeout = 120 })
    nbFusionnes = fin
    progression:setPortionComplete(fin, #decisions)
  end)
  return corbeille, nbFusionnes
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

local function ecrireRapport(decisions, differents)
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

LrTasks.startAsyncTask(function()
  LrFunctionContext.callWithContext('fusionnerDoublons', function(contexte)
    local etape = 'lecture du catalogue'
    local ok, erreur = LrTasks.pcall(function()
      local catalogue = LrApplication.activeCatalog()
      local progression = LrProgressScope { title = 'Recherche des doublons', functionContext = contexte }

      local copies, nbCatalogue = lireCatalogue(catalogue, progression)
      if not copies then return end
      etape = 'comparaison des fichiers'
      local trouves = chercherGroupes(copies, progression)
      if not trouves then return end
      local groupes, differents = trouves.groupes, trouves.differents
      if #groupes == 0 then
        progression:done()
        LrDialogs.message('Doublons', string.format('Aucun fichier en double parmi les %d photos du catalogue.', nbCatalogue)
          .. (#differents > 0 and string.format('\n%d groupes de photos de même nom d’origine et même date ont '
            .. 'des versions distinctes (retouchées, recadrées…) : elles sont toutes conservées.', #differents) or ''), 'info')
        return
      end
      etape = 'lecture des métadonnées'
      details(catalogue, groupes, progression)

      local decisions, aFusionner = {}, {}
      local nbRetirees, nbReduites, nbAVerifier = 0, 0, 0
      for i, g in ipairs(groupes) do
        decisions[i] = Doublons.decider(g)
        if decisions[i].aVerifier then
          nbAVerifier = nbAVerifier + 1
        else
          aFusionner[#aFusionner + 1] = decisions[i]
          nbRetirees = nbRetirees + #decisions[i].retirees
          for _, c in ipairs(decisions[i].retirees) do
            if c.empreinte ~= decisions[i].garde.empreinte then nbReduites = nbReduites + 1 end
          end
        end
      end
      etape = 'écriture du rapport'
      ecrireRapport(decisions, differents)
      progression:done()

      local message = string.format(
        '%d groupes de copies d’une même photo : %d copies en trop%s.\n\n'
        .. 'Dans chaque groupe, la copie gardée est la plus grande image ; à image identique, la copie '
        .. 'retouchée s’il y en a une, sinon la mieux rangée (pas dans « Désordre » ni dans un dossier '
        .. '« …-manquantes », dossier nommé plutôt que daté). Elle prend la place des autres dans leurs '
        .. 'collections et récupère leurs mots-clés, note, drapeau, position GPS et textes (libellé, titre, '
        .. 'légende, auteur, lieu, ville, pays…) quand elle n’en a pas. '
        .. 'Les autres copies sont rassemblées dans la collection « %s », à retirer ensuite du catalogue.',
        #aFusionner, nbRetirees,
        nbReduites > 0 and string.format(' (dont %d copies réduites ou recompressées)', nbReduites) or '',
        COLLECTION_DOUBLONS)
      if nbAVerifier > 0 then
        message = message .. string.format('\n\n%d groupes à vérifier (plusieurs copies retouchées, copie '
          .. 'réduite retouchée…) restent tels quels.', nbAVerifier)
      end
      if #differents > 0 then
        message = message .. string.format('\n%d groupes de photos de même nom d’origine et même date ont des '
          .. 'versions distinctes : image différente (retouche dans un éditeur externe, recadrage…) ou nom '
          .. 'de retouche (« -Modifier », « -Modifié », « _filtered », « DxO_… »). Elles sont toutes conservées.',
          #differents)
      end
      if trouves.magickAbsent then
        message = message .. '\nImageMagick est introuvable : les copies réduites ou recompressées n’ont pas '
          .. 'été cherchées (seuls les fichiers de même image sont fusionnés).'
      end
      if trouves.sansMiniature > 0 then
        message = message .. string.format('\n%d images n’ont pas pu être comparées par ImageMagick '
          .. '(format non lu) : elles sont conservées.', trouves.sansMiniature)
      end
      if trouves.illisibles > 0 then
        message = message .. string.format('\n%d fichiers illisibles (absents ou hors ligne) n’ont pas pu être comparés.', trouves.illisibles)
      end
      message = message .. '\n\nDétail des décisions : ' .. RAPPORT

      local choix
      repeat
        choix = LrDialogs.confirm('Fusionner les doublons ?', message, 'Fusionner', 'Annuler', 'Voir le rapport')
        if choix == 'other' then LrShell.revealInShell(RAPPORT) end
      until choix ~= 'other'
      if choix ~= 'ok' or #aFusionner == 0 then return end

      etape = 'fusion des doublons'
      local fusion = LrProgressScope { title = 'Fusion des doublons', functionContext = contexte }
      local corbeille, nbFusionnes = fusionner(catalogue, aFusionner, fusion)
      fusion:done()
      LrTasks.pcall(function() catalogue:setActiveSources({ corbeille }) end)
      LrDialogs.message('Doublons fusionnés', string.format(
        '%d groupes fusionnés sur %d. Les copies en trop sont dans la collection « %s », '
        .. 'qui vient d’être ouverte.\n\nPour les retirer du catalogue : Ctrl+A, puis Suppr, puis '
        .. '« Retirer » (ou « Supprimer du disque » pour libérer aussi la place sur le disque).',
        nbFusionnes, #aFusionner, COLLECTION_DOUBLONS), 'info')
    end)
    if not ok then
      LrDialogs.message('Erreur pendant la fusion des doublons',
        string.format('Étape : %s\n%s', etape, tostring(erreur)), 'critical')
    end
  end)
end)
