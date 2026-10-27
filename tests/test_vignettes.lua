-- Test de Similitude.lua et Vignettes.lua avec le vrai ImageMagick (images fabriquées).
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

local Similitude = require 'Similitude'

-- Similitude : cas synthétiques -------------------------------------------------------------
local function uniforme(v) return string.rep(string.char(v), 768) end
local function decale(sig, d, n)   -- ajoute d à n valeurs
  local t = {}
  for i = 1, #sig do
    local v = sig:byte(i)
    if i <= n then v = math.min(255, v + d) end
    t[i] = string.char(v)
  end
  return table.concat(t)
end
local base = uniforme(100)
local e = Similitude.ecarts(base, decale(base, 3, 768))
verifier('écart moyen', e.moyen, 3)
verifier('écart canal', e.canal, 3)
e = Similitude.ecarts(base, decale(base, 10, 3))
verifier('écart max', e.max, 10)
verifier('écarts de tailles différentes', Similitude.ecarts('abc', 'abcdef'), nil)
verifier('nom -Modifier', Similitude.nomRetouche('D:\\x\\DSCF5219-Modifier.JPG'), true)
verifier('nom -Edited', Similitude.nomRetouche('IMG_1-Edited.jpg'), true)
verifier('nom -2', Similitude.nomRetouche('DSCF5219-2.JPG'), false)

local function vue(sig, l, h, extra)
  local v = { signature = sig, largeur = l, hauteur = h }
  for k, x in pairs(extra or {}) do v[k] = x end
  return v
end
verifier('même vue, plus petite', Similitude.memeVue(vue(base, 4000, 3000), vue(decale(base, 1, 768), 1000, 750)), true)
verifier('exposition changée', Similitude.memeVue(vue(base, 4000, 3000), vue(decale(base, 6, 768), 4000, 3000)), false)
verifier('un bloc très différent', Similitude.memeVue(vue(base, 4000, 3000), vue(decale(base, 120, 6), 4000, 3000)), false)
-- Changement diffus (contraste, grain) : +3 / -3 en alternance, donc ni bloc ni canal ne dépasse
-- son seuil, seul l'écart moyen (3) le trahit.
local diffus = {}
for i = 1, #base do diffus[i] = string.char(base:byte(i) + ((i % 2 == 0) and 3 or -3)) end
diffus = table.concat(diffus)
local ed = Similitude.ecarts(base, diffus)
verifier('changement diffus : écart moyen', ed.moyen, 3)
verifier('changement diffus : peu de bloc et de canal', ed.max <= 3 and ed.canal < 0.1, true)
verifier('changement diffus : versions distinctes', Similitude.memeVue(vue(base, 4000, 3000), vue(diffus, 4000, 3000)), false)
verifier('forme différente', Similitude.memeVue(vue(base, 4000, 3000), vue(base, 3000, 3000)), false)
verifier('nom de retouche', Similitude.memeVue(vue(base, 4000, 3000), vue(base, 1000, 750, { retouchee = true })), false)
verifier('sans miniature', Similitude.memeVue(vue(base, 4000, 3000), { largeur = 10, hauteur = 10 }), false)

local classes = {
  vue(decale(base, 1, 768), 1000, 750, { pixels = 750000, octets = 100 }),
  vue(base, 4000, 3000, { pixels = 12000000, octets = 5000 }),
  vue(decale(base, 40, 768), 4000, 3000, { pixels = 12000000, octets = 6000, nom = 'retouchée' }),
  vue(decale(base, 2, 768), 2000, 1500, { pixels = 3000000, octets = 400 }),
}
local ensembles = Similitude.regrouper(classes)
verifier('regroupement : 2 ensembles', #ensembles, 2)
verifier('la plus grande en tête (poids)', ensembles[1][1].octets, 6000)   -- la retouchée est la plus lourde : maîtresse seule
verifier('la retouchée reste seule', #ensembles[1], 1)
verifier('l’autre ensemble : originale + 2 réduites', #ensembles[2], 3)
verifier('maîtresse = originale', ensembles[2][1].octets, 5000)

-- Vignettes avec ImageMagick -----------------------------------------------------------------
local MAGICK = 'C:\\Program Files\\ImageMagick-7.1.2-Q16-HDRI\\magick.exe'
local DOSSIER = (SCRATCH .. '/vignettes'):gsub('/', '\\')
os.execute('rmdir /s /q "' .. DOSSIER .. '" 2>nul')
os.execute('mkdir "' .. DOSSIER .. '" 2>nul')
-- Comme LrTasks.execute : « cmd /c » (via un .bat pour échapper aux guillemets que LuaTeX ajoute ;
-- les % sont doublés pour que cmd les reçoive tels quels, comme en ligne de commande).
local function executer(commande)
  local bat = DOSSIER .. '\\cmd.bat'
  local fh = io.open(bat, 'wb')
  local ligne = commande:gsub('%%', '%%%%')
  fh:write('@cmd /c ' .. ligne .. '\r\n')
  fh:close()
  local ok = os.execute(bat)
  return ok == true or ok == 0
end
local function sh(commande) return executer('"' .. commande .. '"') end
local function magick(args) return sh('"' .. MAGICK .. '" ' .. args) end
local function f(nom) return DOSSIER .. '\\' .. nom end

verifier('ImageMagick présent', magick('-version > nul'), true)
-- Image de départ : « rose: » agrandie (couleurs variées, formes nettes).
-- (adoucie : une photo n'a pas les arêtes dures d'une petite image agrandie)
verifier('original', magick('rose: -resize 1200x788! -blur 0x5 -quality 95 "' .. f('A.jpg') .. '"'), true)
verifier('réduite', magick('"' .. f('A.jpg') .. '" -resize 40% -quality 85 "' .. f('B.jpg') .. '"'), true)
verifier('recompressée', magick('"' .. f('A.jpg') .. '" -quality 55 "' .. f('C.jpg') .. '"'), true)
verifier('éclaircie', magick('"' .. f('A.jpg') .. '" -modulate 118,100,100 "' .. f('D.jpg') .. '"'), true)
verifier('noir et blanc', magick('"' .. f('A.jpg') .. '" -colorspace Gray "' .. f('E.jpg') .. '"'), true)
verifier('recadrée', magick('"' .. f('A.jpg') .. '" -gravity center -crop 80%x80%+0+0 +repage "' .. f('F.jpg') .. '"'), true)
-- Photo prise en portrait : pixels pivotés d'un quart de tour et étiquette EXIF Orientation = 6
-- (RightTop). ImageMagick n'écrit pas cette étiquette : le segment APP1 est fabriqué ici.
verifier('pixels pivotés', magick('"' .. f('A.jpg') .. '" -resize 50% -rotate 270 "' .. f('H0.jpg') .. '"'), true)
do
  local source = io.open(f('H0.jpg'), 'rb'); local octets = source:read('*a'); source:close()
  local tiff = 'II*\0\8\0\0\0' .. '\1\0' .. '\18\1\3\0\1\0\0\0\6\0\0\0' .. '\0\0\0\0'
  local app1 = '\255\225' .. string.char(0, #tiff + 8) .. 'Exif\0\0' .. tiff
  local sortie = io.open(f('H.jpg'), 'wb'); sortie:write(octets:sub(1, 2), app1, octets:sub(3)); sortie:close()
end
verifier('éclaircie et réduite', magick('"' .. f('A.jpg') .. '" -resize 50% -modulate 112,100,100 "' .. f('I.jpg') .. '"'), true)
verifier('bruit ajouté', magick('"' .. f('A.jpg') .. '" -attenuate 0.4 +noise Gaussian "' .. f('J.jpg') .. '"'), true)
verifier('effacement local', magick('"' .. f('A.jpg') .. '" -fill black -draw "rectangle 400,250 800,550" "' .. f('K.jpg') .. '"'), true)
verifier('copie accentuée', magick('"' .. f('A.jpg') .. '" -sharpen 0x2 "' .. f('L.jpg') .. '"'), true)

-- Faux Lightroom autour de Vignettes.lua : vrais fichiers, vrai ImageMagick.
local copies, supprimes = {}, {}
local reel = {}   -- chemin « accentué » du test → fichier réel
local mocks = {
  LrPathUtils = {
    child = function(a, b) return a .. '\\' .. b end,
    getStandardFilePath = function(nom) assert(nom == 'temp'); return DOSSIER end,
  },
  LrFileUtils = {
    directoryEntries = function(dossier)
      local liste = dossier == 'C:\\Program Files' and { 'C:\\Program Files\\ImageMagick-7.1.2-Q16-HDRI', 'C:\\Program Files\\Adobe' } or {}
      local i = 0
      return function() i = i + 1; return liste[i] end
    end,
    exists = function(p) local fh = io.open(p, 'rb'); if fh then fh:close(); return 'file' end return false end,
    copy = function(source, destination)
      copies[#copies + 1] = source
      local fh = io.open(reel[source] or source, 'rb'); if not fh then return false end
      local octets = fh:read('*a'); fh:close()
      local sortie = io.open(destination, 'wb'); sortie:write(octets); sortie:close()
      return true
    end,
    readFile = function(p) local fh = io.open(p, 'rb'); if not fh then return nil end local o = fh:read('*a'); fh:close(); return o end,
    delete = function(p) supprimes[#supprimes + 1] = p; os.remove(p) end,
  },
  LrTasks = {
    pcall = pcall,
    execute = function(commande) return executer(commande) and 0 or 1 end,
  },
}
function import(nom) return assert(mocks[nom], 'module inconnu : ' .. nom) end
local Vignettes = require 'Vignettes'

verifier('ImageMagick trouvé', Vignettes.magick(), MAGICK)

local function classe(nom)
  local v = Vignettes.signature(f(nom))
  return v and { signature = v.signature, largeur = v.largeur, hauteur = v.hauteur, pixels = v.largeur * v.hauteur } or nil
end
local A = classe('A.jpg')
verifier('miniature de 768 octets', A and #A.signature, 768)
verifier('dimensions de A', A and (A.largeur .. 'x' .. A.hauteur), '1200x788')
local H = classe('H.jpg')
verifier('rotation EXIF : dimensions après rotation', H and (H.largeur .. 'x' .. H.hauteur), '600x394')

local cas = {
  { 'B', true, 'copie réduite (40 %)' }, { 'C', true, 'copie recompressée (qualité 55)' },
  { 'H', true, 'réduite et pivotée par l’étiquette EXIF' },
  { 'D', false, 'éclaircie' }, { 'E', false, 'noir et blanc' }, { 'F', false, 'recadrée' },
  { 'I', false, 'éclaircie et réduite' }, { 'K', false, 'zone effacée' },
}
for _, c in ipairs(cas) do
  local x = classe(c[1] .. '.jpg')
  local e = x and Similitude.ecarts(A.signature, x.signature)
  print(string.format('  %-34s écart moyen %5.2f  bloc max %3d  canal %5.2f  → %s', c[3], e and e.moyen or -1, e and e.max or -1, e and e.canal or -1,
    x and Similitude.memeVue(A, x) and 'même vue' or 'versions distinctes'))
  verifier(c[3], x and Similitude.memeVue(A, x), c[2])
end
-- Cas laissés à l'appréciation : on affiche seulement l'écart (bruit léger, accentuation).
for _, c in ipairs({ { 'J', 'bruit gaussien léger' }, { 'L', 'accentuée' } }) do
  local x = classe(c[1] .. '.jpg')
  local e = Similitude.ecarts(A.signature, x.signature)
  print(string.format('  (info) %-27s écart moyen %5.2f  bloc max %3d  canal %5.2f  → %s', c[2], e.moyen, e.max, e.canal,
    Similitude.memeVue(A, x) and 'même vue' or 'versions distinctes'))
end

-- Chemin accentué : copie sous un nom simple, puis nettoyage.
reel['D:\\Photographies\\D\195\169sordre\\A.jpg'] = f('A.jpg')
copies = {}
local acc = Vignettes.signature('D:\\Photographies\\D\195\169sordre\\A.jpg')
verifier('chemin accentué : copié', #copies, 1)
verifier('chemin accentué : miniature identique', acc and acc.signature, A.signature)
verifier('chemin accentué : dimensions', acc and (acc.largeur .. 'x' .. acc.hauteur), '1200x788')
local reste = {}
for fichier in io.popen('dir /b "' .. DOSSIER .. '" 2>nul'):lines() do
  if fichier:find('^lrgp%-vignette') then reste[#reste + 1] = fichier end
end
verifier('fichiers temporaires supprimés', #reste, 0)

copies = {}
local simple = Vignettes.signature(f('A.jpg'))
verifier('chemin simple : pas de copie', #copies, 0)
verifier('fichier inexistant', Vignettes.signature(f('absent.jpg')), nil)
verifier('vidéo ignorée', Vignettes.signature('D:\\x\\film.mp4'), nil)
local faux = io.open(f('faux.jpg'), 'wb'); faux:write('pas une image'); faux:close()
verifier('fichier illisible', Vignettes.signature(f('faux.jpg')), nil)

-- Netteté : une image à grain fin, et ses versions de plus en plus floues.
verifier('image à grain fin', magick('-size 900x600 xc:gray +noise Random -blur 0x0.6 -quality 95 "' .. f('N0.jpg') .. '"'), true)
verifier('floutée un peu', magick('"' .. f('N0.jpg') .. '" -blur 0x1.5 -quality 95 "' .. f('N1.jpg') .. '"'), true)
verifier('floutée beaucoup', magick('"' .. f('N0.jpg') .. '" -blur 0x5 -quality 95 "' .. f('N2.jpg') .. '"'), true)
local n0, n1, n2 = Vignettes.nettete(f('N0.jpg')), Vignettes.nettete(f('N1.jpg')), Vignettes.nettete(f('N2.jpg'))
verifier('netteté : un nombre', type(n0), 'number')
verifier('netteté : positive', n0 and n0 > 0, true)
verifier('netteté : l’image floutée un peu est moins nette', n0 and n1 and n1 < n0, true)
verifier('netteté : l’image très floutée l’est encore moins', n1 and n2 and n2 < n1, true)
print(string.format('  netteté : nette %.1f, floue %.1f, très floue %.1f', n0 or -1, n1 or -1, n2 or -1))
verifier('netteté : même valeur à chaque appel', Vignettes.nettete(f('N0.jpg')), n0)
-- Photo (faux chemin accentué) : copiée sous un nom simple, même mesure, fichiers temporaires supprimés.
reel['D:\\Photographies\\D\195\169sordre\\N0.jpg'] = f('N0.jpg')
copies = {}
verifier('netteté d’un chemin accentué : même mesure', Vignettes.nettete('D:\\Photographies\\D\195\169sordre\\N0.jpg'), n0)
verifier('netteté d’un chemin accentué : copié', #copies, 1)
local restes = {}
for fichier in io.popen('dir /b "' .. DOSSIER .. '" 2>nul'):lines() do
  if fichier:find('^lrgp%-vignette') then restes[#restes + 1] = fichier end
end
verifier('netteté : fichiers temporaires supprimés', #restes, 0)
verifier('netteté : fichier absent', Vignettes.nettete(f('absent.jpg')), nil)
verifier('netteté : fichier illisible', Vignettes.nettete(f('faux.jpg')), nil)
verifier('netteté : vidéo ignorée', Vignettes.nettete('D:\\x\\film.mp4'), nil)
verifier('netteté : RAW non lu par ImageMagick', Vignettes.nettete('D:\\x\\absent.raf'), nil)

print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
