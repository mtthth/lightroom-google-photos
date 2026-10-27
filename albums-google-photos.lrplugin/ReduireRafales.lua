-- Réduit les rafales du dossier (ou de la collection) affiché dans Lightroom.
--
-- 1. Détecte les rafales : au moins 3 cadres qui se suivent à une seconde au plus, avec des numéros de
--    fichier voisins (voir Rafales.lua).
-- 2. Découpe chaque rafale en blocs de 4 cadres consécutifs (réglable) et, dans chaque bloc, garde le
--    cadre le plus net (netteté mesurée par ImageMagick, voir Vignettes.lua).
-- 3. Les cadres protégés sont toujours gardés, en plus du plus net de leur bloc : ceux qui sont dans une
--    collection autre que « Google Photos - époques » (les albums Google comptent), notés, marqués d'un
--    drapeau ou d'un libellé de couleur, retouchés dans Lightroom ou avec des copies virtuelles,
--    publiés, ou qui ont une version retouchée dans un éditeur externe (-Modifier, DxO_…).
-- 4. Après confirmation, les autres cadres (tous leurs fichiers : RAW + JPEG, copies…) sont mis dans la
--    collection « Rafales à retirer ». Rien n'est supprimé : le SDK de Lightroom ne le permet pas. Il
--    reste à ouvrir la collection, tout sélectionner et appuyer sur Suppr.
-- 5. Toutes les photos des rafales traitées (gardées comme retirées) reçoivent le mot-clé « Rafale
--    traitée », non exporté. La collection « Rafales à retirer » sera vidée une fois les cadres
--    supprimés : le mot-clé est la mémoire qui empêche une relance de réduire une seconde fois les cadres
--    déjà réduits.
-- Le détail est écrit dans rafales.csv, dans le dossier du projet.
-- Sont ignorées les photos des collections « Doublons à retirer » et « Rafales à retirer », et celles qui
-- portent déjà le mot-clé « Rafale traitée ».

local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrShell = import 'LrShell'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Catalogue = require 'Catalogue'
local Csv = require 'Csv'
local Doublons = require 'Doublons'
local Epoques = require 'Epoques'
local Historique = require 'Historique'
local Parallele = require 'Parallele'
local Rafales = require 'Rafales'
local Vignettes = require 'Vignettes'

local TAILLE_LOT = 1000
local PARALLELE = 4   -- mesures de netteté en même temps
local RAPPORT = LrPathUtils.child(LrPathUtils.parent(_PLUGIN.path), 'rafales.csv')
local HISTORIQUE = LrPathUtils.child(LrPathUtils.parent(_PLUGIN.path), 'photos-traitees.txt')

-- Source affichée dans Lightroom : un dossier ou une collection. Renvoie
-- { nom, dossier (vrai pour un dossier), photos = function(sousDossiers) }, ou nil et un message.
local function lireSource(catalogue)
  local sources = catalogue:getActiveSources()
  if #sources ~= 1 or type(sources[1]) ~= 'table' then
    return nil, 'Affiche un seul dossier ou une seule collection (panneau Dossiers ou Collections), puis relance la commande.'
  end
  local source = sources[1]
  local genre = source:type()
  if genre == 'LrFolder' then
    return { nom = source:getName(), dossier = true, photos = function(sous) return source:getPhotos(sous) end }
  elseif genre == 'LrCollection' or genre == 'LrPublishedCollection' then
    return { nom = source:getName(), dossier = false, photos = function() return source:getPhotos() end }
  end
  return nil, 'Affiche un dossier ou une collection (pas un ensemble de collections), puis relance la commande.'
end

-- Boîte de choix : un cadre gardé pour combien, sous-dossiers. Renvoie { ratio, sousDossiers } ou nil.
local function demanderOptions(contexte, source)
  local f = LrView.osFactory()
  local proprietes = LrBinding.makePropertyTable(contexte)
  proprietes.ratio = Rafales.RATIO
  proprietes.sousDossiers = false

  local colonne = { bind_to_object = proprietes, spacing = f:control_spacing() }
  colonne[#colonne + 1] = f:static_text {
    title = 'Réduire les rafales de « ' .. source.nom .. ' ». Rien n’est supprimé : les cadres en trop sont mis '
      .. 'dans la collection « ' .. Rafales.COLLECTION .. ' », que tu vérifies avant de les retirer.',
    width = 480, height_in_lines = 3,
  }
  colonne[#colonne + 1] = f:row {
    spacing = f:label_spacing(),
    f:static_text { title = 'Garder 1 cadre sur' },
    f:edit_field { value = LrView.bind('ratio'), width_in_digits = 3, min = 2, max = 20, precision = 0, immediate = true },
    f:static_text { title = '(le plus net de chaque bloc ; les cadres protégés sont gardés en plus)' },
  }
  if source.dossier then
    colonne[#colonne + 1] = f:checkbox { title = 'Inclure les sous-dossiers', value = LrView.bind('sousDossiers') }
  end
  local reponse = LrDialogs.presentModalDialog {
    title = 'Réduire les rafales', contents = f:column(colonne), actionVerb = 'Analyser',
  }
  if reponse ~= 'ok' then return nil end
  local ratio = math.floor(tonumber(proprietes.ratio) or Rafales.RATIO)
  return { ratio = math.max(2, ratio), sousDossiers = proprietes.sousDossiers and true or false }
end

-- Fichiers des photos : chemin, heure de prise de vue, taille, et les protections qui se lisent dans
-- les métadonnées. Renvoie nil si l'utilisateur annule, sinon les fichiers et le nombre de photos de
-- la source ignorées car elles sont déjà traitées ou dans une collection « à retirer ».
local function lireFichiers(catalogue, photos, ignorees, historique, progression)
  local fichiers, nbIgnorees = {}, 0
  local complet = Parallele.parLots(photos, TAILLE_LOT, function(lot, _, fin)
    if progression:isCanceled() then return false end
    progression:setCaption(string.format('Lecture des photos : %d / %d', fin, #photos))
    local brutes = catalogue:batchGetRawMetadata(lot, { 'path', 'fileSize', 'dateTimeOriginal', 'isVirtualCopy',
      'countVirtualCopies', 'rating', 'pickStatus', 'colorNameForLabel' })
    for _, photo in ipairs(lot) do
      local b = brutes[photo] or {}
      if ignorees[photo.localIdentifier] or Historique.contient(historique, b.path) then
        nbIgnorees = nbIgnorees + 1
      elseif not b.isVirtualCopy and b.path and b.dateTimeOriginal then
        local raisons = {}
        if (b.rating or 0) > 0 then raisons[#raisons + 1] = 'note ' .. b.rating end
        if (b.pickStatus or 0) ~= 0 then raisons[#raisons + 1] = 'drapeau' end
        if b.colorNameForLabel and b.colorNameForLabel ~= '' and b.colorNameForLabel ~= 'none' then
          raisons[#raisons + 1] = 'libellé ' .. b.colorNameForLabel
        end
        if (b.countVirtualCopies or 0) > 0 then raisons[#raisons + 1] = 'copies virtuelles' end
        fichiers[#fichiers + 1] = {
          photo = photo, id = photo.localIdentifier, chemin = b.path, t = b.dateTimeOriginal,
          taille = b.fileSize, raisons = raisons,
        }
      end
    end
    progression:setPortionComplete(fin, #photos)
  end)
  if not complet then return nil end
  return fichiers, nbIgnorees
end

-- Nom de l'ensemble de premier niveau d'une collection et libellé à afficher.
local function historiqueARetirer(rafales)
  local photos = {}
  for _, rafale in ipairs(rafales) do
    for _, cadre in ipairs(rafale) do
      if cadre.decision == 'retirer' then
        for _, f in ipairs(cadre.fichiers) do
          photos[#photos + 1] = {
            chemin = f.chemin, fichier = f.nom,
            date = Epoques.texte(Epoques.depuisLightroom(f.t, 0)),
          }
        end
      end
    end
  end
  return photos
end

local function infoCollection(collection)
  local noms = { collection:getName() }
  local parent = collection:getParent()
  while parent do
    table.insert(noms, 1, parent:getName())
    parent = parent:getParent()
  end
  return noms[1], #noms == 1 and noms[1] or (noms[1] .. ' / ' .. noms[#noms])
end

-- Ajoute aux fichiers des cadres en rafale les protections qui demandent un appel par photo :
-- collections (hors époques), collections publiées et retouches Lightroom.
local function ajouterProtections(catalogue, rafales, progression)
  local ok, retouchees = LrTasks.pcall(function()
    return catalogue:findPhotos { searchDesc = { criteria = 'hasAdjustments', operation = 'isTrue', value = true } }
  end)
  if not ok then error('impossible de savoir quelles photos sont retouchées : ' .. tostring(retouchees), 0) end
  local estRetouchee = {}
  for _, p in ipairs(retouchees) do estRetouchee[p.localIdentifier] = true end

  local total, fait = 0, 0
  for _, rafale in ipairs(rafales) do total = total + #rafale end
  for _, rafale in ipairs(rafales) do
    for _, cadre in ipairs(rafale) do
      if progression:isCanceled() then return false end
      fait = fait + 1
      progression:setCaption(string.format('Protections des cadres : %d / %d', fait, total))
      progression:setPortionComplete(fait, total)
      for _, f in ipairs(cadre.fichiers) do
        if estRetouchee[f.id] then table.insert(f.raisons, 'retouches Lightroom') end
        for _, collection in ipairs(f.photo:getContainedCollections()) do
          if not collection:isSmartCollection() then
            local racine, etiquette = infoCollection(collection)
            if not Rafales.SANS_PROTECTION[racine] then table.insert(f.raisons, 'collection « ' .. etiquette .. ' »') end
          end
        end
        if #f.photo:getContainedPublishedCollections() > 0 then table.insert(f.raisons, 'collection publiée') end
      end
      Rafales.proteger(cadre)
      LrTasks.yield()
    end
  end
  return true
end

local function taille(octets)
  return (string.format('%.2f Go', octets / 1024 ^ 3):gsub('%.', ','))
end

-- Mesure la netteté des cadres à comparer. Renvoie false si l'utilisateur annule.
local function mesurerNettete(rafales, progression)
  local aMesurer = Rafales.cadresAMesurer(rafales)
  if #aMesurer == 0 then return true end
  return Parallele.pourChaque(aMesurer, PARALLELE, function(cadre)
    cadre.nettete = Vignettes.nettete(cadre.mesure.chemin)
  end, progression, 'Mesure de la netteté : %d / %d')
end

LrTasks.startAsyncTask(function()
  LrFunctionContext.callWithContext('reduireRafales', function(contexte)
    local etape = 'lecture de la source'
    local ok, erreur = LrTasks.pcall(function()
      local catalogue = LrApplication.activeCatalog()
      local source, probleme = lireSource(catalogue)
      if not source then
        LrDialogs.message('Réduire les rafales', probleme, 'info')
        return
      end
      local options = demanderOptions(contexte, source)
      if not options then return end

      local progression = LrProgressScope { title = 'Réduction des rafales', functionContext = contexte }
      etape = 'lecture des photos'
      -- Ignorées : les photos des collections « à retirer » et celles qui portent le mot-clé des rafales
      -- déjà traitées (la collection sera vidée une fois les cadres supprimés, le mot-clé reste).
      local ignorees = Catalogue.photosDesCollections(catalogue, { Doublons.COLLECTION, Rafales.COLLECTION })
      for id in pairs((Catalogue.photosAvecMotCle(catalogue, Rafales.MOT_CLE))) do ignorees[id] = true end
      local historique = Historique.lire(HISTORIQUE)
      local photos = source.photos(options.sousDossiers)
      local fichiers, nbIgnorees = lireFichiers(catalogue, photos, ignorees, historique, progression)
      if not fichiers then return end

      etape = 'détection des rafales'
      local cadres = Rafales.cadres(fichiers)
      local rafales = Rafales.rafales(cadres)
      if #rafales == 0 then
        progression:done()
        LrDialogs.message('Réduire les rafales', string.format(
          'Aucune rafale dans « %s » (%d cadres) : il faut au moins %d cadres à une seconde d’écart au plus, '
          .. 'avec des numéros de fichier voisins.', source.nom, #cadres, Rafales.MIN_CADRES), 'info')
        return
      end
      Rafales.blocs(rafales, options.ratio)

      etape = 'protections'
      if not ajouterProtections(catalogue, rafales, progression) then return end

      etape = 'mesure de la netteté'
      local magickAbsent = Vignettes.magick() == nil
      if not magickAbsent and not mesurerNettete(rafales, progression) then return end
      Rafales.decider(rafales)

      etape = 'écriture du rapport'
      Csv.ecrire(RAPPORT, Rafales.lignesRapport(rafales))
      progression:done()

      local bilan = Rafales.bilan(rafales)
      local sansMesure = 0
      for _, rafale in ipairs(rafales) do
        for _, c in ipairs(rafale) do
          if c.decision == 'retirer' and c.nettete == nil and c.pourquoi and c.pourquoi:find('non mesurée', 1, true) then
            sansMesure = sansMesure + 1
          end
        end
      end
      if bilan.retires == 0 then
        LrDialogs.message('Réduire les rafales', string.format(
          '%d rafales (%d cadres) dans « %s » : rien à retirer, tous les cadres sont protégés ou seuls dans leur bloc.\n\n'
          .. 'Détail : %s', bilan.rafales, bilan.cadres, source.nom, RAPPORT), 'info')
        return
      end

      local message = string.format(
        '« %s » : %d rafales, %d cadres en rafale.\n\n'
        .. '• %d cadres protégés, toujours gardés (collection autre que les époques, note, drapeau, libellé, retouche…)\n'
        .. '• %d cadres gardés : le plus net de chaque bloc de %d\n'
        .. '• %d cadres à retirer (%d fichiers, %s), mis dans la collection « %s »\n\n'
        .. 'Rien n’est supprimé. Les photos de ces rafales (gardées comme retirées) reçoivent le mot-clé « %s » '
        .. '(non exporté) : une relance les ignore. Détail : %s',
        source.nom, bilan.rafales, bilan.cadres, bilan.proteges, bilan.gardes, options.ratio,
        bilan.retires, bilan.fichiersRetires, taille(bilan.octetsRetires), Rafales.COLLECTION, Rafales.MOT_CLE, RAPPORT)
      if nbIgnorees > 0 then
        message = message .. string.format('\n\n%d photos de cette source sont ignorées : déjà traitées (mot-clé « %s » ou historique) '
          .. 'ou dans les collections « à retirer ».', nbIgnorees, Rafales.MOT_CLE)
      end
      if magickAbsent then
        message = message .. '\n\nImageMagick est introuvable : la netteté n’a pas été mesurée, le premier cadre non protégé '
          .. 'de chaque bloc est gardé.'
      elseif sansMesure > 0 then
        message = message .. string.format('\n\n%d cadres n’ont pas pu être mesurés (format non lu par ImageMagick, '
          .. 'RAW sans JPEG…) : le premier cadre de leur bloc est gardé.', sansMesure)
      end

      local choix
      repeat
        choix = LrDialogs.confirm('Mettre de côté les cadres en trop ?', message, 'Mettre de côté', 'Annuler', 'Voir le rapport')
        if choix == 'other' then LrShell.revealInShell(RAPPORT) end
      until choix ~= 'other'
      if choix ~= 'ok' then return end

      etape = 'création de la collection et du mot-clé'
      local aRetirer = Rafales.photosARetirer(rafales)
      local traitees = Rafales.photosTraitees(rafales)
      local collection
      catalogue:withWriteAccessDo('Mettre de côté les rafales en trop', function()
        collection = catalogue:createCollection(Rafales.COLLECTION, nil, true)
        if collection then collection:addPhotos(aRetirer) end
        -- Mot-clé non exporté, posé sur toutes les photos des rafales traitées.
        local motCle = catalogue:createKeyword(Rafales.MOT_CLE, {}, false, nil, true)
        if motCle then
          for _, photo in ipairs(traitees) do photo:addKeyword(motCle) end
        end
      end, { timeout = 120 })
      if not collection then error('Lightroom a refusé de créer la collection « ' .. Rafales.COLLECTION .. ' ».', 0) end
      Historique.ajouter(HISTORIQUE, 'rafale', historiqueARetirer(rafales))
      LrTasks.pcall(function() catalogue:setActiveSources({ collection }) end)
      LrDialogs.message('Rafales mises de côté', string.format(
        '%d cadres (%d fichiers) sont dans la collection « %s », qui vient d’être ouverte.\n\n'
        .. 'Vérifie-les dans la grille, puis pour les retirer du catalogue : Ctrl+A, Suppr, puis « Retirer » '
        .. '(ou « Supprimer du disque » pour libérer %s).\n\n'
        .. 'Les photos de ces rafales ont reçu le mot-clé « %s » : les prochaines réductions les ignorent, même une '
        .. 'fois la collection vidée. Les fichiers retirés sont mémorisés dans %s. Pour les retraiter, supprime '
        .. 'leurs lignes de cet historique et ôte le mot-clé de toutes les photos de la rafale.',
        bilan.retires, bilan.fichiersRetires, Rafales.COLLECTION, taille(bilan.octetsRetires), Rafales.MOT_CLE, HISTORIQUE), 'info')
    end)
    if not ok then
      LrDialogs.message('Erreur pendant la réduction des rafales',
        string.format('Étape : %s\n%s', etape, tostring(erreur)), 'critical')
    end
  end)
end)
