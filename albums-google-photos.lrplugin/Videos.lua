-- Conversion des vidéos en 1080p « léger » avant l'envoi vers Google Photos, avec ffmpeg
-- (winget install Gyan.FFmpeg).
--
-- H.264 / AAC en MP4 : le plus petit côté passe à 1080 pixels au plus (sans agrandir), la cadence à
-- 30 images/s au plus, le débit vidéo reste sous 6 Mbit/s. La rotation et la date de prise de vue
-- (métadonnées du conteneur) sont conservées. Les vidéos HDR (iPhone : HLG ou Dolby Vision, PQ)
-- sont ramenées en SDR, sinon leurs couleurs paraissent délavées une fois en 8 bits.

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local M = {}

M.COTE_MAX = 1080

-- Plus petit côté ramené à COTE_MAX au plus, dimensions paires (exigées par le H.264 4:2:0).
-- Les guillemets simples protègent les virgules des expressions dans la chaîne de filtres.
local ECHELLE = string.format(
  "scale='if(gt(iw,ih),-2,trunc(min(iw,%d)/2)*2)':'if(gt(iw,ih),trunc(min(ih,%d)/2)*2,-2)'",
  M.COTE_MAX, M.COTE_MAX)
local VERS_SDR = 'zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,'
  .. 'tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p'

local function lireFichier(chemin)
  local f = io.open(chemin, 'rb')
  if not f then return nil end
  local contenu = f:read('*a')
  f:close()
  return contenu
end

-- cmd.exe retire la première et la dernière guillemet de la commande.
local function executer(commande)
  return LrTasks.execute('"' .. commande .. '"')
end

-- Chemin de ffmpeg.exe : dans le dossier où winget l'installe, sinon dans le PATH. nil s'il manque.
function M.trouverFfmpeg()
  -- Lightroom ne donne pas accès à %LOCALAPPDATA% (os.getenv) : on part du dossier personnel.
  local packages = LrPathUtils.getStandardFilePath('home')
  for _, dossier in ipairs({ 'AppData', 'Local', 'Microsoft', 'WinGet', 'Packages' }) do
    packages = LrPathUtils.child(packages, dossier)
  end
  if LrFileUtils.exists(packages) == 'directory' then
    for paquet in LrFileUtils.directoryEntries(packages) do
      if LrPathUtils.leafName(paquet):lower():find('ffmpeg', 1, true) then
        for sous in LrFileUtils.directoryEntries(paquet) do
          local exe = LrPathUtils.child(LrPathUtils.child(sous, 'bin'), 'ffmpeg.exe')
          if LrFileUtils.exists(exe) == 'file' then return exe end
        end
      end
    end
  end
  if executer('ffmpeg -version > nul 2>&1') == 0 then return 'ffmpeg' end
  return nil
end

-- ffprobe est installé à côté de ffmpeg.
local function ffprobe(ffmpeg)
  if ffmpeg == 'ffmpeg' then return 'ffprobe' end
  return LrPathUtils.child(LrPathUtils.parent(ffmpeg), 'ffprobe.exe')
end

-- Vrai si la vidéo est en HDR (PQ ou HLG). Dans le doute (ffprobe absent ou muet) : SDR.
function M.estHdr(ffmpeg, entree, journal)
  executer(string.format('"%s" -v error -select_streams v:0 -show_entries stream=color_transfer '
    .. '-of default=nw=1:nk=1 "%s" > "%s" 2>&1', ffprobe(ffmpeg), entree, journal))
  local transfert = lireFichier(journal) or ''
  LrFileUtils.delete(journal)
  return transfert:find('smpte2084', 1, true) ~= nil or transfert:find('arib-std-b67', 1, true) ~= nil
end

function M.commande(ffmpeg, entree, sortie, hdr, journal)
  local filtres, couleurs = ECHELLE, ''
  if hdr then
    filtres = filtres .. ',' .. VERS_SDR
    couleurs = '-color_primaries bt709 -color_trc bt709 -colorspace bt709 '
  end
  return string.format('"%s" -nostdin -y -loglevel error -i "%s" -map 0:v:0 -map 0:a:0? -map_metadata 0 '
    .. '-vf "%s" -fpsmax 30 -c:v libx264 -preset medium -crf 24 -maxrate 6M -bufsize 12M -pix_fmt yuv420p %s'
    .. '-c:a aac -b:a 128k -movflags +faststart "%s" > "%s" 2>&1',
    ffmpeg, entree, filtres, couleurs, sortie, journal)
end

-- Convertit entree en sortie (MP4). Les chemins doivent être en ASCII : la ligne de commande de
-- Windows abîme les autres caractères. Renvoie true, ou false et le message de ffmpeg.
function M.convertir(ffmpeg, entree, sortie)
  local journal = sortie .. '.txt'
  local hdr = M.estHdr(ffmpeg, entree, journal)
  LrFileUtils.delete(sortie)
  local code = executer(M.commande(ffmpeg, entree, sortie, hdr, journal))
  local message = lireFichier(journal) or ''
  LrFileUtils.delete(journal)
  if code == 0 and LrFileUtils.exists(sortie) == 'file' then return true end
  LrFileUtils.delete(sortie)
  local derniere = nil
  for ligne in message:gmatch('[^\r\n]+') do
    if ligne:find('%S') then derniere = ligne end
  end
  return false, 'conversion de la vidéo impossible (ffmpeg' .. (derniere and (' : ' .. derniere) or '') .. ').'
end

return M
