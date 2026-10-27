-- Mesures sur une image, calculées par ImageMagick (Lightroom ne sait pas décoder une image lui-même) :
--   - une miniature de 16 × 16 pixels, pour reconnaître une copie réduite ou recompressée
--     (voir Similitude.lua) ;
--   - la netteté, pour choisir le meilleur cadre d'une rafale (voir Rafales.lua).
--
-- Chemins : LrTasks.execute passe par cmd.exe, qui ne sait pas lire les accents de façon fiable
-- (« Désordre », « Numérisations »…). Un fichier dont le chemin n'est pas en ASCII simple est donc
-- d'abord copié (LrFileUtils.copy, sans souci d'accents) sous un nom simple dans le dossier
-- temporaire, puis supprimé.

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local M = {}

local COTE = 16
local OCTETS = COTE * COTE * 3
local COTE_APERCU = 220   -- aperçus du rapport HTML
local DOSSIERS_IMAGEMAGICK = { 'C:\\Program Files', 'C:\\Program Files (x86)' }
local EXTENSIONS_ABANDONNEES = { mp4 = true, mov = true, avi = true, mts = true, m2ts = true, mkv = true, wmv = true, ['3gp'] = true }

-- Orientations EXIF qui échangent la largeur et la hauteur (photo prise en portrait).
local ORIENTATIONS_PIVOTEES = { LeftTop = true, RightTop = true, RightBottom = true, LeftBottom = true }

local magick, magickCherche = nil, false

-- Chemin de magick.exe (ImageMagick 7), ou nil.
function M.magick()
  if magickCherche then return magick end
  magickCherche = true
  for _, dossier in ipairs(DOSSIERS_IMAGEMAGICK) do
    local ok = LrTasks.pcall(function()
      for entree in LrFileUtils.directoryEntries(dossier) do
        if not magick and entree:lower():find('imagemagick', 1, true) then
          local candidat = LrPathUtils.child(entree, 'magick.exe')
          if LrFileUtils.exists(candidat) == 'file' then magick = candidat end
        end
      end
    end)
    if ok and magick then break end
  end
  return magick
end

local compteur = 0

-- Chemin sûr à passer à cmd.exe tel quel : ASCII, sans caractère spécial pour l'interpréteur.
local function cheminSimple(chemin)
  return chemin:find('^[%w %.%_%-#,;@%(%)\\/:~%+=]+$') ~= nil
end

-- Prépare le fichier pour ImageMagick (copié sous un nom simple si son chemin ne l'est pas), appelle
-- travail(exe, source, base, temporaires) et supprime ensuite les fichiers temporaires : travail y
-- inscrit ceux qu'il crée. Renvoie ce que renvoie travail, ou nil si le fichier est inutilisable.
local function avecSource(chemin, travail)
  local exe = M.magick()
  if not exe then return nil end
  local extension = (chemin:match('%.([%w]+)$') or ''):lower()
  if EXTENSIONS_ABANDONNEES[extension] then return nil end

  compteur = compteur + 1
  local base = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), 'lrgp-vignette-' .. compteur)
  local temporaires = {}
  local function nettoyer()
    -- Chaque fichier est supprimé à part : une erreur sur l'un n'empêche pas les autres.
    for _, fichier in ipairs(temporaires) do LrTasks.pcall(LrFileUtils.delete, fichier) end
  end

  local source = chemin
  if not cheminSimple(chemin) then
    source = base .. '-source' .. (extension:find('^%w+$') and ('.' .. extension) or '')
    temporaires[#temporaires + 1] = source
    if not LrFileUtils.copy(chemin, source) then
      nettoyer()
      return nil
    end
  end
  local ok, resultat = LrTasks.pcall(travail, exe, source, base, temporaires)
  nettoyer()
  if ok then return resultat end
  return nil
end

-- Renvoie { signature (miniature RVB de 16 × 16), largeur, hauteur } (dimensions après rotation
-- EXIF), ou nil si ImageMagick ne sait pas lire le fichier.
function M.signature(chemin)
  return avecSource(chemin, function(exe, source, base, temporaires)
    local infos, rvb = base .. '.txt', base .. '.rvb'
    temporaires[#temporaires + 1] = infos
    temporaires[#temporaires + 1] = rvb

    -- Dimensions et orientation (en-tête seul), puis miniature. Le décodeur JPEG peut réduire l'image
    -- d'emblée (jpeg:size) : 0,26 s au lieu de 1,2 s pour 40 millions de pixels. L'image décodée reste
    -- plus grande que 1024 pixels : une réduction plus forte (64, 256…) décale l'image d'une fraction
    -- de pixel quand ses dimensions ne sont pas multiples de 8, et la même photo à deux tailles
    -- donnerait alors des miniatures un peu différentes.
    local commande = string.format(
      '"%s" identify -format "%%w %%h %%[orientation]" "%s[0]" > "%s" 2>nul && '
      .. '"%s" -define jpeg:size=1024x1024 "%s[0]" -auto-orient -resize %dx%d! -colorspace sRGB -depth 8 rgb:"%s" 2>nul',
      exe, source, infos, exe, source, COTE, COTE, rvb)
    LrTasks.execute('"' .. commande .. '"')

    local ok, texte = LrTasks.pcall(function() return LrFileUtils.readFile(infos) end)
    local largeur, hauteur, orientation = nil, nil, nil
    if ok and texte then largeur, hauteur, orientation = texte:match('(%d+) (%d+)%s*(%a*)') end
    local okRvb, miniature = LrTasks.pcall(function() return LrFileUtils.readFile(rvb) end)
    if largeur and okRvb and miniature and #miniature == OCTETS then
      largeur, hauteur = tonumber(largeur), tonumber(hauteur)
      if ORIENTATIONS_PIVOTEES[orientation] then largeur, hauteur = hauteur, largeur end
      return { signature = miniature, largeur = largeur, hauteur = hauteur }
    end
    return nil
  end)
end

-- Netteté d'une image : écart-type du laplacien de l'image réduite à 1200 pixels, en niveaux de
-- gris, multiplié par 1000. Plus le nombre est grand, plus l'image est nette ; il ne se compare
-- qu'entre des vues d'une même scène (une rafale). Renvoie nil si ImageMagick ne sait pas lire le
-- fichier. 0,3 s environ par photo de 24 millions de pixels.
function M.nettete(chemin)
  return avecSource(chemin, function(exe, source, base, temporaires)
    local sortie = base .. '-nettete.txt'
    temporaires[#temporaires + 1] = sortie
    local commande = string.format(
      '"%s" -define jpeg:size=1600x1600 "%s[0]" -auto-orient -resize 1200x1200 -colorspace Gray '
      .. '-morphology Convolve Laplacian:0 -format "%%[fx:standard_deviation*1000]" info: > "%s" 2>nul',
      exe, source, sortie)
    LrTasks.execute('"' .. commande .. '"')
    local ok, texte = LrTasks.pcall(function() return LrFileUtils.readFile(sortie) end)
    if not ok or not texte then return nil end
    return tonumber(texte:match('^%s*(%-?[%d%.]+[eE]?[%-+]?%d*)'))
  end)
end

-- Écrit dans `destination` un aperçu JPEG du fichier (220 pixels au plus sur le grand côté), pour le
-- rapport HTML. L'aperçu est d'abord écrit sous un nom simple dans le dossier temporaire, puis déplacé :
-- la destination peut avoir des accents. Renvoie true si l'aperçu est écrit, nil si ImageMagick ne sait
-- pas lire le fichier (RAW sans décodeur…). 0,2 s environ par photo de 24 millions de pixels.
function M.apercu(chemin, destination)
  return avecSource(chemin, function(exe, source, base, temporaires)
    local sortie = base .. '-apercu.jpg'
    temporaires[#temporaires + 1] = sortie
    -- Le décodeur JPEG réduit l'image d'emblée, sans descendre sous le double de l'aperçu.
    local commande = string.format(
      '"%s" -define jpeg:size=%dx%d "%s[0]" -auto-orient -thumbnail %dx%d -strip -quality 72 "%s" 2>nul',
      exe, 2 * COTE_APERCU, 2 * COTE_APERCU, source, COTE_APERCU, COTE_APERCU, sortie)
    LrTasks.execute('"' .. commande .. '"')
    if LrFileUtils.exists(sortie) ~= 'file' then return nil end
    if LrFileUtils.exists(destination) then LrFileUtils.delete(destination) end
    if not LrFileUtils.move(sortie, destination) then return nil end
    return true
  end)
end

return M
