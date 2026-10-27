-- Recrée les albums Google Photos sous forme de collections dans le catalogue ouvert.
--
-- Lit le fichier photos-albums-<année>.csv (album ; fichier ; date_prise_de_vue ; id_photo)
-- et retrouve chaque photo dans le catalogue (voir Correspondance.lua).
--
-- Deux ensembles de collections sont créés :
--   « Google Photos - albums » : une collection par album Google Photos ;
--   « Google Photos - époques » : pour chaque album, une collection avec les photos de l'album
--     et toutes les photos du catalogue prises entre sa première et sa dernière photo, plus une
--     collection « intercalaire » dans chaque trou entre deux périodes couvertes par des albums
--     (voir Epoques.lua).
-- Relancer le module ne crée pas de doublons : il complète les collections existantes.
-- Les photos introuvables sont listées dans un fichier « …-non-trouvees.csv » à côté du CSV.

local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'

local Correspondance = require 'Correspondance'
local Catalogue = require 'Catalogue'
local Doublons = require 'Doublons'
local Empreintes = require 'Empreintes'
local Epoques = require 'Epoques'
local Historique = require 'Historique'
local Noms = require 'Noms'
local Rafales = require 'Rafales'

local TAILLE_LOT = 1000
local ENSEMBLE_ALBUMS = Noms.ENSEMBLE_ALBUMS
local ENSEMBLE_EPOQUES = Noms.ENSEMBLE_EPOQUES
-- Un album plus long que cela n'est pas une époque (album annuel, album de plusieurs années…) :
-- il reste une collection d'album mais ne définit ni époque ni période intercalaire.
-- nil : aucune limite, tous les albums définissent une époque.
local DUREE_MAX_EPOQUE_JOURS = 45
-- Titre sous lequel export-albums.mjs range les photos qui ne sont dans aucun album.
local TITRE_HORS_ALBUM = '(hors album)'
local HISTORIQUE = LrPathUtils.child(LrPathUtils.parent(_PLUGIN.path), 'photos-traitees.txt')

-- Lit un CSV séparé par « ; », avec guillemets éventuels et BOM UTF-8.
local function lireCsv(chemin)
  local f = io.open(chemin, 'rb')
  if not f then error('Impossible de lire ' .. chemin) end
  local texte = f:read('*a'):gsub('^\239\187\191', '')
  f:close()

  local lignes, ligne, champ = {}, {}, {}
  local entreGuillemets = false
  local i, n = 1, #texte
  while i <= n do
    local c = texte:sub(i, i)
    if entreGuillemets then
      if c == '"' and texte:sub(i + 1, i + 1) == '"' then
        champ[#champ + 1] = '"'
        i = i + 1
      elseif c == '"' then
        entreGuillemets = false
      else
        champ[#champ + 1] = c
      end
    elseif c == '"' then
      entreGuillemets = true
    elseif c == ';' then
      ligne[#ligne + 1] = table.concat(champ)
      champ = {}
    elseif c == '\n' then
      ligne[#ligne + 1] = table.concat(champ)
      champ = {}
      lignes[#lignes + 1] = ligne
      ligne = {}
    elseif c ~= '\r' then
      champ[#champ + 1] = c
    end
    i = i + 1
  end
  if #champ > 0 or #ligne > 0 then
    ligne[#ligne + 1] = table.concat(champ)
    lignes[#lignes + 1] = ligne
  end
  return lignes
end

local function ecrireCsv(chemin, lignes)
  local f = io.open(chemin, 'wb')
  if not f then error('Impossible d’écrire ' .. chemin) end
  f:write('\239\187\191')
  for _, ligne in ipairs(lignes) do
    local cellules = {}
    for j, valeur in ipairs(ligne) do
      valeur = tostring(valeur)
      if valeur:find('[;"\r\n]') then valeur = '"' .. valeur:gsub('"', '""') .. '"' end
      cellules[j] = valeur
    end
    f:write(table.concat(cellules, ';'), '\r\n')
  end
  f:close()
end

local function trim(texte)
  return (texte:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Photo du catalogue prise à la même seconde que la photo Google (nom différent : version
-- redimensionnée par le téléphone, par exemple). L'heure de Lightroom est décalée de
-- `decalage` secondes par rapport à Google, à une heure près selon l'heure d'été.
-- On ne retient que s'il n'y a qu'une seule prise de vue possible (une paire RAW + JPEG
-- compte pour une : on préfère alors l'extension du fichier Google).
local function retrouverParHeure(index, decalage, date, fichier)
  local secondes = Epoques.secondes(date)
  if not secondes then return nil end
  local candidats, vus = {}, {}
  for _, ecart in ipairs({ 0, 3600, -3600 }) do
    local brut = secondes - Epoques.depuisLightroom(0, 0) + decalage + ecart
    for _, photo in ipairs(index.parTemps[brut] or {}) do
      if not vus[photo] then
        vus[photo] = true
        table.insert(candidats, photo)
      end
    end
  end
  if #candidats == 0 then return nil end
  if #candidats == 1 then return candidats[1] end
  local base = Correspondance.nomOrigine(index.noms[candidats[1]] or '')
  for _, photo in ipairs(candidats) do
    if Correspondance.nomOrigine(index.noms[photo] or '') ~= base then return nil end
  end
  local extension = (string.lower(fichier or '')):match('%.([^%.]*)$')
  for _, photo in ipairs(candidats) do
    if (index.noms[photo] or ''):match('%.([^%.]*)$') == extension then return photo end
  end
  return candidats[1]
end

-- Photo du catalogue dont l'image est identique à celle d'un fichier téléchargé (voir
-- Empreintes.lua), cherchée parmi les fichiers de même nom ou de même taille : on la reprend
-- plutôt que d'importer un doublon. Utile quand la date ne correspond pas (date corrigée dans
-- Google Photos, par exemple), ou après une fusion des doublons.
local function photoIdentique(index, chemin)
  local attributs = LrFileUtils.fileAttributes(chemin)
  local candidats = {}
  for _, liste in ipairs({ index.parNom[LrPathUtils.leafName(chemin):lower()] or {},
                           attributs and index.parTaille[attributs.fileSize] or {} }) do
    for _, c in ipairs(liste) do candidats[#candidats + 1] = c end
  end
  if #candidats == 0 then return nil end
  local empreinte = Empreintes.empreinte(chemin)
  if not empreinte then return nil end
  for _, c in ipairs(candidats) do
    if c.chemin ~= chemin and Empreintes.empreinte(c.chemin) == empreinte then return c.photo end
  end
  return nil
end

-- Ensemble « AAAA » rangé dans l'ensemble racine (créé une seule fois par année).
local function ensembleAnnee(catalogue, racine, cache, annee)
  if not cache[annee] then
    cache[annee] = catalogue:createCollectionSet(annee, racine, true) or racine
  end
  return cache[annee]
end

-- Nom unique dans une année : Lightroom ne distingue pas majuscules et minuscules, et deux
-- albums de même titre le même jour porteraient le même nom.
local function nomUnique(pris, annee, nom)
  local candidat, n = nom, 1
  while pris[annee .. '|' .. candidat:lower()] do
    n = n + 1
    candidat = nom .. ' (' .. n .. ')'
  end
  pris[annee .. '|' .. candidat:lower()] = true
  return candidat
end

-- Crée (ou retrouve) une collection. Lightroom peut refuser certains titres (caractères comme
-- « / » ou « : ») en renvoyant nil : on réessaie alors sans ces caractères. Renvoie la collection,
-- ou nil après avoir signalé le problème.
local function creerCollection(catalogue, nom, ensemble, problemes)
  local contreOblique = string.char(92)
  local variantes = {
    nom,
    (nom:gsub('[/' .. contreOblique .. ']', '-')),
    (nom:gsub('[/' .. contreOblique .. ':]', '-')),
  }
  local dernier
  for _, variante in ipairs(variantes) do
    local ok, resultat = LrTasks.pcall(function() return catalogue:createCollection(variante, ensemble, true) end)
    if ok and resultat then return resultat end
    dernier = ok and 'refusé par Lightroom' or tostring(resultat)
  end
  problemes.nb = problemes.nb + 1
  if #problemes.exemples < 5 then
    table.insert(problemes.exemples, 'collection « ' .. nom .. ' » : ' .. dernier)
  end
  return nil
end

-- Photos téléchargées par telecharger-manquantes.mjs : dossier « …-manquantes » à côté du CSV,
-- avec un telechargements.csv (album ; fichier ; date ; id_photo ; chemin du fichier).
-- Renvoie une table clé « album/fichier/date » → liste de chemins (vide si le dossier n'existe pas).
local function cleManifeste(album, fichier, date)
  return trim(album or '') .. '|' .. (fichier or '') .. '|' .. (date or '')
end

local function lireManifeste(cheminCsv)
  local chemin = LrPathUtils.child(LrPathUtils.removeExtension(cheminCsv) .. '-manquantes', 'telechargements.csv')
  local manifeste = {}
  if not LrFileUtils.exists(chemin) then return manifeste end
  local lignes = lireCsv(chemin)
  for i = 2, #lignes do
    local l = lignes[i]
    local k = cleManifeste(l[1], l[2], l[3])
    manifeste[k] = manifeste[k] or { suivant = 0 }
    table.insert(manifeste[k], l[5])
  end
  return manifeste
end

-- Identifiants des photos des collections « Doublons à retirer » (copies en trop trouvées par
-- « Fusionner les doublons ») et « Rafales à retirer » (cadres en trop de « Réduire les rafales »),
-- pas encore retirées du catalogue, et leur nombre. Elles sont ignorées : sinon elles reviendraient
-- dans les albums et les époques, à la place de la copie ou du cadre gardé.
local function copiesEnTrop(catalogue)
  return Catalogue.photosDesCollections(catalogue, { Doublons.COLLECTION, Rafales.COLLECTION })
end

-- Indexe les photos du catalogue par lots, en affichant l'avancement.
-- Renvoie nil si l'utilisateur annule.
local function indexerCatalogue(catalogue, progression, problemes)
  progression:setCaption('Lecture du catalogue : liste des photos…')
  local photos = catalogue:getAllPhotos()
  local ignorees, nbIgnorees = copiesEnTrop(catalogue)
  local historique = Historique.lire(HISTORIQUE)
  local index = Correspondance.nouvelIndex()
  index.traitees = Correspondance.nouvelIndex()
  index.nbHistoriqueIgnorees = 0
  for _, entree in ipairs(historique.entrees) do
    if entree.fichier and entree.fichier ~= '' then
      Correspondance.ajouterPhoto(index.traitees, entree.chemin, entree.fichier, entree.date)
    end
  end
  index.nbIgnorees = nbIgnorees
  index.temps = {}    -- photo → date de prise de vue (secondes Lightroom)
  index.datees = {}   -- { t = secondes Lightroom, photo }, pour les époques
  index.parTemps = {} -- seconde Lightroom → photos prises à cet instant
  index.noms = {}     -- photo → nom de fichier en minuscules
  -- Pour reconnaître un fichier déjà importé : taille, ou nom en minuscules → { { photo, chemin } }.
  index.parTaille, index.parNom = {}, {}

  for debut = 1, #photos, TAILLE_LOT do
    if progression:isCanceled() then return nil end
    local fin = math.min(debut + TAILLE_LOT - 1, #photos)
    progression:setCaption(string.format('Lecture du catalogue : %d / %d photos', fin, #photos))

    local lot = {}
    for i = debut, fin do lot[#lot + 1] = photos[i] end
    local formatees = catalogue:batchGetFormattedMetadata(lot, { 'fileName' })
    local brutes = catalogue:batchGetRawMetadata(lot, { 'dateTimeOriginal', 'isVirtualCopy', 'fileSize', 'path' })
    for _, photo in ipairs(lot) do
      -- Une photo au comportement inattendu est ignorée et signalée, sans tout arrêter.
      local ok, erreur = LrTasks.pcall(function()
        local brut = brutes[photo] or {}
        local dejaIgnoree = ignorees[photo.localIdentifier]
        if not dejaIgnoree and Historique.contient(historique, brut.path) then
          dejaIgnoree = true
          index.nbHistoriqueIgnorees = index.nbHistoriqueIgnorees + 1
        end
        if not brut.isVirtualCopy and not dejaIgnoree then
          if brut.path then
            local copie = { photo = photo, chemin = brut.path }
            local nom = LrPathUtils.leafName(brut.path):lower()
            index.parNom[nom] = index.parNom[nom] or {}
            table.insert(index.parNom[nom], copie)
            if brut.fileSize then
              index.parTaille[brut.fileSize] = index.parTaille[brut.fileSize] or {}
              table.insert(index.parTaille[brut.fileSize], copie)
            end
          end
          -- Formatage sans fuseau horaire : l'heure de prise de vue telle qu'enregistrée.
          local date = brut.dateTimeOriginal and Epoques.texte(Epoques.depuisLightroom(brut.dateTimeOriginal, 0))
          Correspondance.ajouterPhoto(index, photo, (formatees[photo] or {}).fileName, date)
          if brut.dateTimeOriginal then
            index.temps[photo] = brut.dateTimeOriginal
            table.insert(index.datees, { t = brut.dateTimeOriginal, photo = photo })
            local seconde = math.floor(brut.dateTimeOriginal)
            index.parTemps[seconde] = index.parTemps[seconde] or {}
            table.insert(index.parTemps[seconde], photo)
            index.noms[photo] = string.lower((formatees[photo] or {}).fileName or '')
          end
        end
      end)
      if not ok then
        problemes.nb = problemes.nb + 1
        if #problemes.exemples < 5 then
          table.insert(problemes.exemples, 'catalogue : ' .. tostring(erreur))
        end
      end
    end
    progression:setPortionComplete(fin, #photos)
  end
  return index, #photos
end

LrTasks.startAsyncTask(function()
  LrFunctionContext.callWithContext('recreerAlbums', function(contexte)
    -- Les erreurs internes de Lightroom n'indiquent pas d'où elles viennent :
    -- on retient l'étape en cours pour l'afficher.
    local etape = 'choix du fichier'
    local ok, erreur = LrTasks.pcall(function()

    local choix = LrDialogs.runOpenPanel {
      title = 'Choisir le fichier photos-albums-<année>.csv',
      canChooseFiles = true,
      canChooseDirectories = false,
      allowsMultipleSelection = false,
      fileTypes = 'csv',
    }
    if not choix then return end
    local cheminCsv = choix[1]

    etape = 'lecture du CSV'
    local lignes = lireCsv(cheminCsv)
    local entete = lignes[1] or {}
    if entete[1] ~= 'album' or entete[2] ~= 'fichier' then
      LrDialogs.message('Fichier inattendu', 'Choisis le fichier photos-albums-<année>.csv produit par export-albums.mjs.', 'critical')
      return
    end

    -- Avec photos-albums-tous.csv, les photos qui ne sont dans aucun album (photos-hors-album.csv,
    -- à côté) sont traitées dans la foulée, par année, sous le titre « (hors album) ».
    if LrPathUtils.leafName(cheminCsv) == 'photos-albums-tous.csv' then
      local cheminHorsAlbum = LrPathUtils.child(LrPathUtils.parent(cheminCsv), 'photos-hors-album.csv')
      if LrFileUtils.exists(cheminHorsAlbum) then
        local horsAlbum = lireCsv(cheminHorsAlbum)
        for i = 2, #horsAlbum do table.insert(lignes, horsAlbum[i]) end
      end
    end

    etape = 'barre de progression'
    local progression = LrProgressScope { title = 'Recréation des albums Google Photos', functionContext = contexte }
    etape = 'lecture du catalogue'
    local catalogue = LrApplication.activeCatalog()
    local problemes = { nb = 0, exemples = {} }
    local index, nbCatalogue = indexerCatalogue(catalogue, progression, problemes)
    if not index then return end

    -- Regroupe les photos retrouvées par album, dans l'ordre du fichier.
    etape = 'recherche des photos des albums'
    progression:setCaption('Recherche des photos des albums…')
    local albums, ordre = {}, {}
    local nonTrouvees = { { 'album', 'fichier', 'date_prise_de_vue' } }
    local manquantes = {}
    local paires = {}   -- { temps Lightroom, temps Google } de photos reconnues, pour le décalage horaire
    local nbTrouvees, nbHistorique = 0, 0
    for i = 2, #lignes do
      local ligne = lignes[i]
      local titreCsv = trim(ligne[1] or '')
      local titre = titreCsv
      local horsAlbum = titreCsv == TITRE_HORS_ALBUM
      if horsAlbum then
        -- Un « album » par année : (hors album) 2019, (hors album) 2020…
        local annee = (ligne[3] or ''):match('^(%d%d%d%d)')
        titre = TITRE_HORS_ALBUM .. ' ' .. (annee or 'Sans date')
      end
      if titre ~= '' then
        if not albums[titre] then
          albums[titre] = { photos = {}, dejaVues = {}, titre = titre, horsAlbum = horsAlbum }
          table.insert(ordre, titre)
        end
        local album = albums[titre]
        local secondes = Epoques.secondes(ligne[3])
        if secondes then
          if not album.debut or secondes < album.debut then album.debut = secondes end
          if not album.fin or secondes > album.fin then album.fin = secondes end
        end
        local ok, photo = LrTasks.pcall(Correspondance.retrouver, index, ligne[2], ligne[3])
        if not ok then
          problemes.nb = problemes.nb + 1
          if #problemes.exemples < 5 then
            table.insert(problemes.exemples, tostring(ligne[2]) .. ' : ' .. tostring(photo))
          end
          photo = nil
        end
        if photo then
          if not album.dejaVues[photo] then
            album.dejaVues[photo] = true
            table.insert(album.photos, photo)
          end
          nbTrouvees = nbTrouvees + 1
          if secondes and index.temps[photo] then
            table.insert(paires, { index.temps[photo], secondes })
          end
        else
          -- titreCsv : le titre tel qu'il est dans le CSV, pour le manifeste et le rapport.
          local okHistorique, photoTraitee = LrTasks.pcall(Correspondance.retrouver, index.traitees, ligne[2], ligne[3])
          table.insert(manquantes, {
            titre = titre, titreCsv = titreCsv, fichier = ligne[2] or '', date = ligne[3] or '',
            historique = okHistorique and photoTraitee ~= nil,
          })
        end
      end
      progression:setPortionComplete(i, #lignes)
    end
    local manifeste = lireManifeste(cheminCsv)

    -- Décalage horaire Lightroom / Google, déduit des photos reconnues par leur nom, puis
    -- seconde chance par l'heure de prise de vue pour celles dont le nom a changé.
    etape = 'recherche par l’heure de prise de vue'
    local decalage = Epoques.decalage(paires)
    local nbParHeure = 0
    local encore = {}
    for _, m in ipairs(manquantes) do
      local ok, photo = LrTasks.pcall(retrouverParHeure, index, decalage, m.date, m.fichier)
      local album = albums[m.titre]
      if ok and photo then
        if not album.dejaVues[photo] then
          album.dejaVues[photo] = true
          table.insert(album.photos, photo)
        end
        nbTrouvees = nbTrouvees + 1
        nbParHeure = nbParHeure + 1
      else
        if m.historique then nbHistorique = nbHistorique + 1 else table.insert(encore, m) end
      end
    end
    manquantes = encore

    -- Fichiers téléchargés correspondant aux photos manquantes (une même photo peut servir
    -- à plusieurs albums : on ne l'importe qu'une fois).
    etape = 'recherche des fichiers téléchargés'
    local fichiersParLigne, aImporter, dejaPrevus = {}, {}, {}
    for i, m in ipairs(manquantes) do
      local entree = manifeste[cleManifeste(m.titreCsv, m.fichier, m.date)]
      local chemin = entree and entree[entree.suivant + 1]
      if chemin then entree.suivant = entree.suivant + 1 end
      if chemin and LrFileUtils.exists(chemin) then
        fichiersParLigne[i] = chemin
        if not dejaPrevus[chemin] then
          dejaPrevus[chemin] = true
          table.insert(aImporter, chemin)
        end
      end
    end

    -- Un accès en écriture par photo : la barre de progression avance et on voit où ça en est.
    etape = 'import des photos téléchargées'
    local importees = {}
    local nbImportees, nbDejaPresentes = 0, 0
    local debutImport = LrDate.currentTime()
    for i, chemin in ipairs(aImporter) do
      if progression:isCanceled() then break end
      progression:setCaption(string.format('Import des photos téléchargées : %d / %d', i, #aImporter))
      progression:setPortionComplete(i - 1, #aImporter)
      local ok, resultat = LrTasks.pcall(function()
        local photo = catalogue:findPhotoByPath(chemin)
        if not photo then
          photo = photoIdentique(index, chemin)
          if photo then nbDejaPresentes = nbDejaPresentes + 1 end
        end
        if not photo then
          catalogue:withWriteAccessDo('Importer une photo Google Photos', function()
            photo = catalogue:addPhoto(chemin)
          end, { timeout = 60 })
        end
        return photo
      end)
      if ok and resultat then
        importees[chemin] = resultat
        nbImportees = nbImportees + 1
      else
        problemes.nb = problemes.nb + 1
        if #problemes.exemples < 5 then
          table.insert(problemes.exemples, 'import de ' .. chemin .. ' : ' .. tostring(resultat))
        end
      end
    end
    local dureeImport = LrDate.currentTime() - debutImport

    for i, m in ipairs(manquantes) do
      local photo = fichiersParLigne[i] and importees[fichiersParLigne[i]]
      local album = albums[m.titre]
      if photo then
        if not album.dejaVues[photo] then
          album.dejaVues[photo] = true
          table.insert(album.photos, photo)
        end
        nbTrouvees = nbTrouvees + 1
      else
        table.insert(nonTrouvees, { m.titreCsv, m.fichier, m.date })
      end
    end

    etape = 'création des collections'
    progression:setCaption('Création des collections…')
    -- Nom de chaque album : « AAAA-MM-JJ – titre » dans l'ensemble de son année.
    for _, titre in ipairs(ordre) do
      local album = albums[titre]
      if album.horsAlbum then
        -- Collection « (hors album) » dans l'ensemble de l'année.
        album.nom, album.annee = TITRE_HORS_ALBUM, titre:sub(#TITRE_HORS_ALBUM + 2)
      else
        local nom = Noms.analyser(titre, album.debut and Epoques.dateTexte(album.debut))
        album.nom, album.annee = nom.nom, nom.annee
      end
    end
    catalogue:withWriteAccessDo('Recréer les albums Google Photos', function()
      local racine = catalogue:createCollectionSet(ENSEMBLE_ALBUMS, nil, true)
      local ensembles, nomsPris = {}, {}
      for _, titre in ipairs(ordre) do
        local album = albums[titre]
        -- Pas de collection « (hors album) » vide (année dont aucune photo n'est au catalogue).
        if not (album.horsAlbum and #album.photos == 0) then
          local parent = ensembleAnnee(catalogue, racine, ensembles, album.annee)
          local nom = nomUnique(nomsPris, album.annee, album.nom)
          local collection = creerCollection(catalogue, nom, parent, problemes)
          if collection and #album.photos > 0 then collection:addPhotos(album.photos) end
        end
      end
    end, { timeout = 30 })

    -- Époques : décalage entre les heures de Lightroom et celles de Google Photos (fuseau),
    -- déduit des photos reconnues, puis calcul des périodes.
    etape = 'calcul des époques'
    progression:setCaption('Calcul des époques…')
    local datees = {}
    for _, d in ipairs(index.datees) do
      table.insert(datees, { t = Epoques.depuisLightroom(d.t, decalage), photo = d.photo })
    end
    -- Les photos qu'on vient d'importer ne figuraient pas dans l'index.
    local nouvelles = {}
    for _, photo in pairs(importees) do table.insert(nouvelles, photo) end
    if #nouvelles > 0 then
      local temps = catalogue:batchGetRawMetadata(nouvelles, { 'dateTimeOriginal' })
      for _, photo in ipairs(nouvelles) do
        local t = temps[photo] and temps[photo].dateTimeOriginal
        if t then table.insert(datees, { t = Epoques.depuisLightroom(t, decalage), photo = photo }) end
      end
    end
    -- Les photos hors album ne définissent pas d'époque : elles tombent dans celle qui couvre leur
    -- date (toutes les photos du catalogue prises pendant une époque en font partie).
    local listeAlbums = {}
    for _, titre in ipairs(ordre) do
      if not albums[titre].horsAlbum then table.insert(listeAlbums, albums[titre]) end
    end
    local dureeMax = DUREE_MAX_EPOQUE_JOURS and DUREE_MAX_EPOQUE_JOURS * 24 * 3600 or nil
    local epoques = Epoques.calculer(listeAlbums, datees, dureeMax)

    etape = 'création des collections d’époques'
    progression:setCaption('Création des collections d’époques…')
    catalogue:withWriteAccessDo('Créer les époques Google Photos', function()
      local racine = catalogue:createCollectionSet(ENSEMBLE_EPOQUES, nil, true)
      local ensembles = {}
      for i, epoque in ipairs(epoques) do
        progression:setPortionComplete(i, #epoques)
        local parent = ensembleAnnee(catalogue, racine, ensembles, epoque.annee)
        local collection = creerCollection(catalogue, epoque.nom, parent, problemes)
        if collection and #epoque.photos > 0 then collection:addPhotos(epoque.photos) end
      end
    end, { timeout = 30 })
    progression:done()

    etape = 'écriture du rapport'
    local nbNonTrouvees = #nonTrouvees - 1
    local message = string.format(
      '%d collections créées ou complétées dans « %s ».\n%d photos retrouvées sur %d (catalogue : %d photos).',
      #ordre, ENSEMBLE_ALBUMS, nbTrouvees, nbTrouvees + nbNonTrouvees + nbHistorique, nbCatalogue)
    if nbHistorique > 0 then
      message = message .. string.format('\n%d lignes ignorées selon l’historique des traitements.', nbHistorique)
    end
    local nbHorsAlbum = 0
    for _, titre in ipairs(ordre) do
      if albums[titre].horsAlbum then nbHorsAlbum = nbHorsAlbum + #albums[titre].photos end
    end
    if nbHorsAlbum > 0 then
      message = message .. string.format('\n%d photos hors album rangées dans les collections « (hors album) » de chaque année.', nbHorsAlbum)
    end
    local nbIntercalaires = 0
    for _, epoque in ipairs(epoques) do
      if epoque.intercalaire then nbIntercalaires = nbIntercalaires + 1 end
    end
    message = message .. string.format('\n%d époques (dont %d intercalaires) dans « %s » ; décalage horaire détecté : %+.2f h.',
      #epoques, nbIntercalaires, ENSEMBLE_EPOQUES, decalage / 3600)
    if nbParHeure > 0 then
      message = message .. string.format('\n%d photos reconnues par l’heure de prise de vue (nom de fichier différent).', nbParHeure)
    end
    if nbImportees > nbDejaPresentes then
      message = message .. string.format('\n%d photos importées depuis le dossier des photos téléchargées (%d s).',
        nbImportees - nbDejaPresentes, math.floor(dureeImport + 0.5))
    end
    if nbDejaPresentes > 0 then
      message = message .. string.format('\n%d photos téléchargées étaient déjà au catalogue sous un autre chemin (même fichier) : '
        .. 'pas de nouvel import.', nbDejaPresentes)
    end
    if (index.nbIgnorees or 0) > 0 then
      message = message .. string.format('\n%d photos en trop des collections « %s » et « %s » ignorées (à retirer du catalogue).',
        index.nbIgnorees, Doublons.COLLECTION, Rafales.COLLECTION)
    end
    if (index.nbHistoriqueIgnorees or 0) > 0 then
      message = message .. string.format('\n%d photos ignorées d’après l’historique persistant.', index.nbHistoriqueIgnorees)
    end
    local cheminRapport = LrPathUtils.removeExtension(cheminCsv) .. '-non-trouvees.csv'
    if nbNonTrouvees > 0 then
      ecrireCsv(cheminRapport, nonTrouvees)
      message = message .. string.format('\n\n%d photos introuvables, listées dans :\n%s', nbNonTrouvees, cheminRapport)
    elseif LrFileUtils.exists(cheminRapport) then
      LrFileUtils.delete(cheminRapport)
    end
    if problemes.nb > 0 then
      message = message .. string.format('\n\n%d erreurs internes, par exemple :\n%s',
        problemes.nb, table.concat(problemes.exemples, '\n'))
    end
    LrDialogs.message('Albums Google Photos', message, 'info')
    end)
    if not ok then
      LrDialogs.message('Erreur du module Albums Google Photos',
        string.format('Étape : %s\n%s', etape, tostring(erreur)), 'critical')
    end
  end)
end)
