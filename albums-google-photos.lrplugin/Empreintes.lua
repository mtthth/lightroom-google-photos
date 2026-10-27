-- Empreinte (MD5) de l'image contenue dans un fichier, pour reconnaître deux copies du même
-- fichier, même quand leurs métadonnées intégrées diffèrent (XMP écrit par Lightroom, par
-- exemple : le fichier change, pas l'image).
--   JPEG : données d'image seules, à partir du premier segment SOS (les segments qui précèdent
--     portent l'EXIF, le XMP, l'IPTC, la vignette…) ;
--   HEIC, MP4… (format ISO à boîtes « ftyp ») : contenu des boîtes « mdat » ;
--   autres formats : tout le fichier.
-- Lecture par LrFileUtils.readFile, la seule qui gère les chemins accentués (« Désordre »…).
-- Au-delà de 64 Mo (vidéos), seuls le début et la fin du fichier sont lus, avec sa taille.

local LrFileUtils = import 'LrFileUtils'
local LrMD5 = import 'LrMD5'

local M = {}

local GROS = 64 * 1024 * 1024
local MORCEAU = 8 * 1024 * 1024

-- Position (à partir de 1) du segment SOS d'un JPEG, ou nil.
local function debutImageJpeg(octets)
  if octets:byte(1) ~= 0xFF or octets:byte(2) ~= 0xD8 then return nil end
  local i = 3
  while i + 3 <= #octets do
    local ff, marqueur = octets:byte(i, i + 1)
    if ff ~= 0xFF then return nil end
    if marqueur == 0xDA then return i end
    if marqueur == 0xFF then
      i = i + 1
    else
      local fort, faible = octets:byte(i + 2, i + 3)
      i = i + 2 + fort * 256 + faible
    end
  end
  return nil
end

local function entier32(octets, i)
  local a, b, c, d = octets:byte(i, i + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- Contenu des boîtes « mdat » d'un fichier au format ISO (HEIC, MP4…), ou nil.
local function donneesMdat(octets)
  if octets:sub(5, 8) ~= 'ftyp' then return nil end
  local morceaux, i = {}, 1
  while i + 7 <= #octets do
    local taille, entete = entier32(octets, i), 8
    local genre = octets:sub(i + 4, i + 7)
    if taille == 1 and i + 15 <= #octets then
      taille, entete = entier32(octets, i + 8) * 4294967296 + entier32(octets, i + 12), 16
    elseif taille == 0 then
      taille = #octets - i + 1
    end
    if taille < entete then break end
    if genre == 'mdat' then morceaux[#morceaux + 1] = octets:sub(i + entete, i + taille - 1) end
    i = i + taille
  end
  return #morceaux > 0 and table.concat(morceaux) or nil
end

-- Empreinte d'un contenu de fichier déjà lu.
function M.empreinteContenu(octets)
  local sos = debutImageJpeg(octets)
  if sos then return 'jpeg:' .. LrMD5.digest(octets:sub(sos)) end
  local mdat = donneesMdat(octets)
  if mdat then return 'mdat:' .. LrMD5.digest(mdat) end
  return 'brut:' .. LrMD5.digest(octets)
end

-- Gros fichier : début et fin seulement (io.open, qui ne gère pas les accents : au pire, nil).
local function empreinteGros(chemin, taille)
  local f = io.open(chemin, 'rb')
  if not f then return nil end
  local debut = f:read(MORCEAU)
  f:seek('set', taille - MORCEAU)
  local fin = f:read(MORCEAU)
  f:close()
  return 'gros:' .. taille .. ':' .. LrMD5.digest(debut or '') .. LrMD5.digest(fin or '')
end

-- Renvoie l'empreinte du fichier, ou nil s'il est illisible (absent, hors ligne…).
function M.empreinte(chemin)
  local attributs = LrFileUtils.fileAttributes(chemin)
  if not attributs or not attributs.fileSize then return nil end
  if attributs.fileSize > GROS then return empreinteGros(chemin, attributs.fileSize) end
  local octets = LrFileUtils.readFile(chemin)
  if not octets then return nil end
  return M.empreinteContenu(octets)
end

return M
