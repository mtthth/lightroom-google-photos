-- Empreintes sur de vrais fichiers, avec un faux SDK Lightroom. Le faux digesteur hache chaque
-- bloc puis leur liste : il vérifie le parcours de tous les blocs, sans les garder en mémoire.
local PLUGIN, SCRATCH = assert(arg[1]), assert(arg[2])
package.path = PLUGIN .. '/?.lua;' .. package.path
local md5, sha2 = require 'md5', require 'sha2'
local ouvrir = io.open
local nb, echecs = 0, 0
local function verifier(nom, obtenu, attendu)
  nb = nb + 1
  if obtenu ~= attendu then
    echecs = echecs + 1
    print('ÉCHEC ' .. nom .. '\n  obtenu  : ' .. tostring(obtenu) .. '\n  attendu : ' .. tostring(attendu))
  end
end
local function hex(s) return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
local function chemin(nom) return SCRATCH .. '/empreintes-' .. nom end
local function taille(p)
  local f = ouvrir(p, 'rb')
  if not f then return nil end
  local n = f:seek('end'); f:close(); return n
end
local function ecrire(p, texte)
  local f = assert(ouvrir(p, 'wb')); assert(f:write(texte)); assert(f:close()); return p
end
local function boite(type_, contenu)
  local n = #contenu + 8
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
    math.floor(n / 256) % 256, n % 256) .. type_ .. contenu
end
local function video(meta) return boite('ftyp', 'isom') .. boite('moov', meta) .. boite('mdat', 'MEMES-DONNEES') end

local stats, refus, panneLecture, exceptionLecture, copieRefusee, digestRefuse, tailleInexacte
local function remettre()
  stats = { copies = 0, supprimes = {}, fermes = 0, ouverts = 0, blocs = 0, lus = 0, maximum = 0, yields = 0 }
  refus, panneLecture, exceptionLecture, copieRefusee, digestRefuse, tailleInexacte = {}, false, false, false, false, false
end
remettre()
local mocks = {
  LrMD5 = { digest = md5.sumhexa },
  LrDigest = { SHA256 = { init = function()
    local blocs = {}
    return {
      update = function(_, bloc)
        if digestRefuse then error('digesteur indisponible') end
        stats.blocs = stats.blocs + 1
        blocs[#blocs + 1] = sha2.digest256(bloc)
      end,
      digest = function() return hex(sha2.digest256(table.concat(blocs))) end,
    }
  end } },
  LrTasks = { pcall = pcall, yield = function() stats.yields = stats.yields + 1 end },
  LrPathUtils = {
    child = function(parent, nom) return parent .. '/' .. nom end,
    getStandardFilePath = function() return SCRATCH end,
  },
  LrFileUtils = {
    fileAttributes = function(p)
      local n = taille(p)
      return n and { fileSize = n + (tailleInexacte and 1 or 0) } or nil
    end,
    readFile = function(p)
      local f = assert(ouvrir(p, 'rb')); local contenu = f:read('*a'); f:close(); return contenu
    end,
    chooseUniqueFileName = function(p)
      local candidat, i = p, 0
      while taille(candidat) do i = i + 1; candidat = p .. '-' .. i end
      return candidat
    end,
    copy = function(src, dest)
      stats.copies = stats.copies + 1
      stats.dernierTemporaire = dest
      local sortie = assert(ouvrir(dest, 'wb'))
      if copieRefusee then sortie:write('copie interrompue'); sortie:close(); return false end
      local entree = assert(ouvrir(src, 'rb'))
      while true do
        local bloc = entree:read(1024 * 1024)
        if not bloc then break end
        assert(sortie:write(bloc))
      end
      entree:close(); sortie:close(); return true
    end,
    delete = function(p) stats.supprimes[#stats.supprimes + 1] = p; return os.remove(p) end,
  },
}
function import(nom) return assert(mocks[nom], 'module inconnu : ' .. nom) end
io.open = function(p, mode)
  if refus[p] then return nil, 'chemin Unicode refusé par io.open' end
  local f, erreur = ouvrir(p, mode)
  if not f then return nil, erreur end
  stats.ouverts = stats.ouverts + 1
  local lectures = 0
  return {
    read = function(_, n)
      lectures = lectures + 1
      if exceptionLecture and lectures == 2 then error('erreur de lecture') end
      if panneLecture and lectures == 2 then return nil, 'erreur de lecture' end
      stats.maximum = math.max(stats.maximum, type(n) == 'number' and n or math.huge)
      local bloc, detail = f:read(n)
      stats.lus = stats.lus + (bloc and #bloc or 0)
      return bloc, detail
    end,
    seek = function(_, ...) return f:seek(...) end,
    close = function() stats.fermes = stats.fermes + 1; return f:close() end,
  }
end
local Empreintes = require 'Empreintes'

local ok, erreur = pcall(function()
  for _, nom in ipairs({ 'clip.MOV', 'clip.mp4', 'clip.m4v', 'clip.AVI', 'clip.mts', 'clip.m2ts',
    'clip.3gp', 'clip.3g2', 'clip.MPEG', 'clip.webm', 'clip.wmv', 'clip.mkv' }) do
    verifier('extension vidéo ' .. nom, Empreintes.estVideo(nom), true)
  end
  for _, nom in ipairs({ 'photo.jpg', 'photo.HEIC', 'clip.mp4.jpg', 'sans-extension', 'dossier.mp4/photo' }) do
    verifier('extension photo ' .. nom, Empreintes.estVideo(nom), false)
  end
  verifier('extension absente', Empreintes.estVideo(nil), false)

  local petiteA = ecrire(chemin('petite-a.mp4'), video('MONTAGE-A'))
  local petiteB = ecrire(chemin('petite-b.mp4'), video('MONTAGE-B'))
  verifier('vidéos : même mdat et conteneurs différents restent distincts',
    Empreintes.empreinte(petiteA) == Empreintes.empreinte(petiteB), false)
  verifier('photos ISO : comparaison du mdat conservée',
    Empreintes.empreinte(petiteA, false) == Empreintes.empreinte(petiteB, false), true)
  local renommee = ecrire(chemin('video-renommee.bin'), video('MONTAGE-B'))
  verifier('vidéo annoncée par le catalogue malgré extension inconnue',
    Empreintes.empreinte(renommee, true), Empreintes.empreinte(petiteB))

  local grandA, grandB = chemin('grande-a.mp4'), chemin('grande-b.mp4')
  local bloc = string.rep('A', 1024 * 1024)
  for _, p in ipairs({ grandA, grandB }) do
    local f = assert(ouvrir(p, 'wb'))
    for i = 1, 66 do assert(f:write(p == grandB and i == 33 and ('B' .. bloc:sub(2)) or bloc)) end
    assert(f:close())
  end
  verifier('fixture supérieure à 64 Mo', taille(grandA) > 64 * 1024 * 1024, true)
  local prefiltreA = Empreintes.empreinte(grandA)
  verifier('gros : préfiltre explicitement identifié', prefiltreA:sub(1, 5), 'gros:')
  verifier('même début et même fin : préfiltre identique malgré différence centrale',
    prefiltreA, Empreintes.empreinte(grandB))
  remettre()
  local completeA = Empreintes.empreinteComplete(grandA)
  verifier('empreinte complète identifiée', completeA:sub(1, 8), 'complet:')
  verifier('tous les octets sont lus', stats.lus, taille(grandA))
  verifier('lectures bornées à 8 Mo', stats.maximum, 8 * 1024 * 1024)
  verifier('plusieurs blocs sans charger le fichier entier', stats.blocs, 9)
  verifier('yield après chaque bloc', stats.yields, stats.blocs)
  verifier('fichier fermé après succès', stats.fermes, 1)
  verifier('aucune copie si io.open fonctionne', stats.copies, 0)
  verifier('différence centrale repérée', completeA == Empreintes.empreinteComplete(grandB), false)
  verifier('empreinte complète reproductible', completeA, Empreintes.empreinteComplete(grandA))

  local accents = chemin('Été – vidéo [2].MOV')
  mocks.LrFileUtils.copy(grandA, accents)
  remettre(); refus[accents] = true
  verifier('préfiltre Unicode : copie temporaire utilisable', Empreintes.empreinte(accents), prefiltreA)
  verifier('préfiltre Unicode : une copie seulement', stats.copies, 1)
  verifier('préfiltre Unicode : temporaire supprimé', taille(stats.dernierTemporaire), nil)
  verifier('préfiltre Unicode : fichier fermé', stats.fermes, 1)
  remettre(); refus[accents] = true
  verifier('SHA256 Unicode : même fichier entier', Empreintes.empreinteComplete(accents), completeA)
  verifier('SHA256 Unicode : une copie seulement', stats.copies, 1)
  verifier('SHA256 Unicode : temporaire supprimé', taille(stats.dernierTemporaire), nil)
  verifier('SHA256 Unicode : fichier fermé', stats.fermes, 1)

  remettre(); panneLecture = true
  verifier('erreur de lecture : aucune empreinte partielle', Empreintes.empreinteComplete(grandA), nil)
  verifier('erreur de lecture : fichier fermé', stats.fermes, 1)
  remettre(); refus[accents] = true; exceptionLecture = true
  verifier('exception Unicode : aucune empreinte', Empreintes.empreinteComplete(accents), nil)
  verifier('exception Unicode : fichier fermé', stats.fermes, 1)
  verifier('exception Unicode : temporaire supprimé', taille(stats.dernierTemporaire), nil)
  remettre(); refus[accents] = true; copieRefusee = true
  verifier('copie partielle refusée : aucune empreinte', Empreintes.empreinteComplete(accents), nil)
  verifier('copie partielle refusée : temporaire supprimé', taille(stats.dernierTemporaire), nil)
  remettre(); refus[accents] = true; digestRefuse = true
  verifier('digesteur en échec : aucune empreinte', Empreintes.empreinteComplete(accents), nil)
  verifier('digesteur en échec : fichier fermé', stats.fermes, 1)
  verifier('digesteur en échec : temporaire supprimé', taille(stats.dernierTemporaire), nil)
  remettre(); tailleInexacte = true
  verifier('lecture trop courte : aucune empreinte', Empreintes.empreinteComplete(grandA), nil)
  verifier('lecture trop courte : fichier fermé', stats.fermes, 1)

  remettre()
  verifier('annulation préalable : aucune empreinte', Empreintes.empreinteComplete(grandA, function() return true end), nil)
  verifier('annulation préalable : aucun fichier ouvert', stats.ouverts, 0)
  remettre(); refus[accents] = true
  verifier('annulation Unicode entre blocs : aucune empreinte',
    Empreintes.empreinteComplete(accents, function() return stats.blocs >= 1 end), nil)
  verifier('annulation Unicode : un seul bloc lu', stats.lus, 8 * 1024 * 1024)
  verifier('annulation Unicode : fichier fermé', stats.fermes, 1)
  verifier('annulation Unicode : temporaire supprimé', taille(stats.dernierTemporaire), nil)
  remettre()
  verifier('fichier absent : aucune empreinte', Empreintes.empreinteComplete(chemin('absente.mp4')), nil)
  verifier('fichier absent : aucune copie', stats.copies, 0)
  local vide = ecrire(chemin('vide.mp4'), '')
  verifier('fichier vide : empreinte déterministe', Empreintes.empreinteComplete(vide),
    'complet:' .. hex(sha2.digest256('')))
end)
io.open = ouvrir
if not ok then echecs = echecs + 1; print('ÉCHEC exception : ' .. tostring(erreur)) end
print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
