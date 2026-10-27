-- Test du rapport HTML de « Fusionner les doublons » : RapportHtml.lua (page, échappement, tri, chiffres),
-- et Vignettes.apercu avec le vrai ImageMagick (images fabriquées). Écrit aussi une page d'exemple, avec de
-- vraies miniatures, dans <dossier de travail>/rapport-demo/index.html.
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
local function contient(texte, motif) return texte:find(motif, 1, true) ~= nil end

local RapportHtml = require 'RapportHtml'
local Doublons = require 'Doublons'
local Epoques = require 'Epoques'
local function dateLr(texte) return Epoques.secondes(texte) - 978307200 end

-- urlFichier ----------------------------------------------------------------------------------------
verifier('url : espaces', RapportHtml.urlFichier('D:\\Documents Phemios\\Mon projet\\rapport-doublons\\index.html'),
  'file:///D:/Documents%20Phemios/Mon%20projet/rapport-doublons/index.html')
verifier('url : accents en UTF-8', RapportHtml.urlFichier('D:\\Photos\\\195\137t\195\169\\a.html'), 'file:///D:/Photos/%C3%89t%C3%A9/a.html')
verifier('url : caractères spéciaux', RapportHtml.urlFichier('C:\\a#b&c\\x.html'), 'file:///C:/a%23b%26c/x.html')

-- Un modèle réaliste -----------------------------------------------------------------------------------
local A = 'D:\\Photographies src 2\\Archives\\'
local P = A .. '# Photos personnelles\\'
local function col(id, nom, extra) local c = { id = id, nom = nom, dynamique = false, exclue = false }; for k, v in pairs(extra or {}) do c[k] = v end; return c end
local function mot(nom) return { nom = nom, objet = nom } end
local function copie(id, chemin, extra)
  local c = { id = id, chemin = chemin, date = dateLr('2018-08-19 15:00:00'), taille = 3000000, octets = 3000000, empreinte = 'e1',
    pixels = 12000000, dimensions = '4000x3000', collections = {}, motsCles = {}, note = 0, drapeau = 0, textes = {} }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end
local function decision(copies)
  local d = Doublons.decider(copies)
  if not d.aVerifier then d.effets = Doublons.effets(d) end
  return d
end

-- Groupe 1 (2020) : trois fichiers identiques ; groupe 2 (2018) : copie réduite ; groupe 3 : à vérifier.
local album = col(1, 'Google Photos - albums / 2020-03-01 – Gien')
local d1 = decision({
  copie(1, P .. '202x\\2020\\200301. Gien\\IMG_1.JPG', { date = dateLr('2020-03-01 10:00:00'), collections = { col(2, 'Époques / 2020') }, octets = 2500000 }),
  copie(2, A .. 'Désordre\\2020\\IMG_1.JPG', { date = dateLr('2020-03-01 10:00:00'), collections = { album, col(2, 'Époques / 2020') },
    motsCles = { mot('Gien'), mot('Loire') }, note = 3, textes = { city = 'Gien', creator = 'Moi' }, gps = { latitude = 47.7 }, octets = 2600000 }),
  copie(3, A .. 'photos-albums-tous-manquantes\\IMG_1.JPG', { date = dateLr('2020-03-01 10:00:00'), collections = { col(3, 'Doublons à retirer', { exclue = true }) } }),
})
local d2 = decision({
  copie(4, P .. '201x\\2018\\180819. Fête\\IMG_2.JPG', { empreinte = 'a', pixels = 12000000, octets = 5200000 }),
  copie(5, A .. 'Désordre\\2018\\IMG_2-2.JPG', { empreinte = 'b', pixels = 750000, dimensions = '1000x750', octets = 140000,
    collections = { col(4, 'Albums / Fête') } }),
})
local d3 = decision({
  copie(6, P .. 'x\\IMG_3.JPG', { retouchee = true, empreinte = 'e1', pixels = 1000 }),
  copie(7, P .. 'y\\IMG_3.JPG', { retouchee = true, empreinte = 'e1', pixels = 1000 }),
})
verifier('modèle : groupe 1 sans alerte', d1.aVerifier, nil)
verifier('modèle : groupe 3 à vérifier', d3.aVerifier, 'plusieurs copies retouchées')
local differents = { {
  copie(8, P .. 'z\\IMG_4.JPG', { empreinte = 'p' }), copie(9, P .. 'z\\IMG_4-Modifier.JPG', { empreinte = 'q', dimensions = '4000x3000' }),
} }

local function apercu(c) return 'vignettes/' .. c.id .. '.jpg' end
local html = RapportHtml.page({
  portee = 'les 312 photos sélectionnées', date = '2026-10-27 14:05', collection = 'Doublons à retirer',
  decisions = { d1, d2, d3 }, differents = differents, vignette = apercu, notes = { '3 fichiers illisibles (absents ou hors ligne) n’ont pas pu être comparés.' },
})

-- Contenu de la page --------------------------------------------------------------------------------------
verifier('page : document HTML', html:sub(1, 15), '<!doctype html>')
verifier('page : langue', contient(html, '<html lang="fr">'), true)
verifier('page : titre', contient(html, '<title>Doublons — rapport avant fusion</title>'), true)
verifier('page : rien n’a été modifié', contient(html, 'Rien n’a été modifié dans Lightroom'), true)
verifier('page : portée et date', contient(html, 'les 312 photos sélectionnées · 2026-10-27 14:05'), true)
verifier('page : bouton à utiliser', contient(html, 'clique sur « Fusionner »'), true)
verifier('chiffre : 2 groupes à fusionner', contient(html, '<b style="color:var(--garder)">2</b><span>groupes à fusionner</span>'), true)
verifier('chiffre : 3 copies retirées', contient(html, '<b style="color:var(--retirer)">3</b><span>copies retirées (mises de côté)</span>'), true)
verifier('chiffre : 1 réduite (singulier)', contient(html, '<b>1</b><span>dont copie réduite ou recompressée</span>'), true)
-- Retirées : copies 2 (2,6 Mo) et 3 (3 Mo) du groupe 1, copie 5 (140 Ko) du groupe 2 = 5 740 000 octets.
verifier('chiffre : octets libérés', contient(html, '<b>5,5 Mo</b><span>libérés si tu les supprimes du disque</span>'), true)
-- Collections touchées : l'album (1), l'époque (2) et « Fête » (4) ; la 3 est une corbeille, jamais touchée.
verifier('chiffre : 3 collections modifiées', contient(html, '<b>3</b><span>collections modifiées</span>'), true)
verifier('chiffre : 1 groupe à vérifier (singulier)', contient(html, '<b style="color:var(--verifier)">1</b><span>groupe à vérifier (rien de fait)</span>'), true)
verifier('chiffre : 1 groupe conservé à part (singulier)', contient(html, '<b style="color:var(--apart)">1</b><span>groupe de versions conservées</span>'), true)
verifier('titres : pluriel et singulier', contient(html, 'À fusionner <small>2 groupes</small>') and contient(html, 'À vérifier <small>1 groupe · rien n’est fait</small>')
  and contient(html, 'Versions conservées à part <small>1 groupe · tout est conservé</small>'), true)
verifier('filtre : accord du compteur', contient(html, "' groupes affichés' : ' groupe affiché'"), true)
verifier('sections', contient(html, 'id="fusions"') and contient(html, 'id="verifier"') and contient(html, 'id="apart"'), true)

local function position(motif) return html:find(motif, 1, true) end
verifier('tri : le plus ancien (groupe 2, 2018) avant le plus récent (groupe 1, 2020)', position('id="g2"') < position('id="g1"'), true)
verifier('numéros de groupe', contient(html, '<h3>Groupe 1 <small>') and contient(html, '<h3>Groupe 2 <small>') and contient(html, '<h3>Groupe 3 <small>'), true)
verifier('rôles : gardée', contient(html, '<em>Gardée</em>'), true)
verifier('rôles : retirée', contient(html, '<em>Retirée</em>'), true)
verifier('rôles : à vérifier', contient(html, '<em>À vérifier</em>') and contient(html, '<em>Serait gardée</em>'), true)
verifier('rôles : conservée', contient(html, '<em>Conservée</em>'), true)
verifier('aperçu : src relatif', contient(html, '<img src="vignettes/1.jpg" alt="" loading="lazy" decoding="async">'), true)
verifier('pourquoi (groupe 1)', contient(html, 'Copie gardée : retouchée dans Lightroom.') or contient(html, 'Copie gardée : dossier mieux rangé.')
  or contient(html, 'Copie gardée : déjà annotée'), true)
verifier('pourquoi (groupe 2) : la plus grande image', contient(html, 'Copie gardée : la plus grande image.'), true)
verifier('effets : collection rejointe', contient(html, 'La copie gardée rejoint 1 collection : « Google Photos - albums / 2020-03-01 – Gien »'), true)
verifier('effets : mots-clés', contient(html, 'Mots-clés ajoutés : « Gien », « Loire »'), true)
verifier('effets : note', contient(html, 'Note relevée à ★★★'), true)
verifier('effets : ville', contient(html, 'Ville recopié(e) : Gien'), true)
verifier('effets : auteur non recopié quand il y en a déjà un (ou tous deux sans)', true, true)
verifier('effets : gps', contient(html, 'Position GPS recopiée'), true)
verifier('effets : corbeille', contient(html, 'Les copies retirées vont dans la collection « Doublons à retirer » : rien n’est supprimé.'), true)
verifier('à vérifier : raison', contient(html, 'À vérifier : plusieurs copies retouchées. <b>Rien ne sera fait pour ce groupe.</b>'), true)
verifier('à part : explication du nom de retouche', contient(html, 'Un fichier dont le nom annonce une retouche'), true)
verifier('pastille : nom de retouche', contient(html, '<span class="badge b-nom">nom de retouche</span>'), true)
verifier('pastille : retouchée dans Lightroom', contient(html, '<span class="badge b-lr">retouchée dans Lightroom</span>'), true)
verifier('pastille : note', contient(html, '<span class="badge ">★★★</span>'), true)
verifier('pastille : mots-clés', contient(html, '2 mots-clés'), true)
verifier('formats : dimensions et date', contient(html, '4000x3000 · 2,4 Mo · 2020-03-01 10:00:00'), true)
verifier('formats : taille en Ko', contient(html, '137 Ko'), true)
verifier('dossier court', contient(html, '… / 202x / 2020 / 200301. Gien'), true)
verifier('chemin complet en infobulle', contient(html, 'title="D:/Photographies src 2/Archives/# Photos personnelles/202x/2020/200301. Gien"'), true)
verifier('notes de bas de page', contient(html, '<li>3 fichiers illisibles'), true)
verifier('filtre : script et champs', contient(html, 'id="recherche"') and contient(html, 'id="seulement-reduites"') and contient(html, 'function filtrer()'), true)
verifier('filtre : type réduite', contient(html, 'data-type="reduite"'), true)
verifier('filtre : texte de recherche en minuscules', contient(html, 'data-q="img_1.jpg d:/photographies src 2/archives/'), true)

-- Équilibre des balises : une page mal formée se verrait mal dans un navigateur.
local desequilibres = {}
for _, balise in ipairs({ 'div', 'article', 'figure', 'figcaption', 'h1', 'h2', 'h3', 'ul', 'li', 'p', 'span', 'b', 'small', 'em', 'main', 'label', 'body', 'html', 'head', 'style', 'script' }) do
  local ouvertes = select(2, html:gsub('<' .. balise .. '[ >]', ''))
  local fermees = select(2, html:gsub('</' .. balise .. '>', ''))
  if ouvertes ~= fermees then desequilibres[#desequilibres + 1] = balise .. ' ' .. ouvertes .. '/' .. fermees end
end
verifier('balises équilibrées', table.concat(desequilibres, ', '), '')

-- Échappement : un nom ou un dossier ne doit jamais devenir du HTML.
local piege = '<img src=x onerror=alert(1)>&"\''
local dp = decision({
  copie(20, 'D:\\a\\' .. piege .. '\\IMG_9.JPG', { collections = { col(30, 'Album ' .. piege) }, motsCles = { mot(piege) } }),
  copie(21, 'D:\\b\\IMG_9.JPG', { collections = { col(31, 'Autre ' .. piege) }, motsCles = { mot('x') } }),
})
local pieges = RapportHtml.page({ portee = piege, date = piege, collection = piege, decisions = { dp }, differents = {}, notes = { piege } })
verifier('échappement : aucune balise injectée', contient(pieges, '<img src=x'), false)
verifier('échappement : rendu en texte', contient(pieges, '&lt;img src=x onerror=alert(1)&gt;&amp;&quot;&#39;'), true)
verifier('échappement : sans aperçu', contient(pieges, 'pas d’aperçu'), true)
verifier('échappement : pas de sections vides', contient(pieges, 'id="verifier"') or contient(pieges, 'id="apart"'), false)

local vide = RapportHtml.page({ portee = 'x', date = 'y', collection = 'z', decisions = {}, differents = {} })
verifier('rien à fusionner : la page le dit', contient(vide, 'Aucun groupe à fusionner.'), true)

-- Vignettes.apercu avec ImageMagick -------------------------------------------------------------------------
local MAGICK = 'C:\\Program Files\\ImageMagick-7.1.2-Q16-HDRI\\magick.exe'
local DOSSIER = (SCRATCH .. '/rapport'):gsub('/', '\\')
os.execute('rmdir /s /q "' .. DOSSIER .. '" 2>nul')
os.execute('mkdir "' .. DOSSIER .. '" 2>nul')
os.execute('mkdir "' .. DOSSIER .. '\\apercus" 2>nul')
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
local function magick(args) return executer('"' .. '"' .. MAGICK .. '" ' .. args .. '"') end
local function f(nom) return DOSSIER .. '\\' .. nom end
local function lire(chemin) local fh = io.open(chemin, 'rb'); if not fh then return nil end local o = fh:read('*a'); fh:close(); return o end

if not io.open(MAGICK, 'rb') then
  print('ImageMagick absent : tests des aperçus ignorés')
else
  verifier('image 1200x788', magick('rose: -resize 1200x788! -blur 0x5 -quality 95 "' .. f('A.jpg') .. '"'), true)
  verifier('image réduite', magick('"' .. f('A.jpg') .. '" -resize 40% -quality 85 "' .. f('B.jpg') .. '"'), true)
  verifier('image éclaircie', magick('"' .. f('A.jpg') .. '" -modulate 125,100,100 "' .. f('D.jpg') .. '"'), true)
  verifier('image portrait (EXIF)', magick('"' .. f('A.jpg') .. '" -rotate 270 "' .. f('H0.jpg') .. '"'), true)
  do   -- Photo prise en portrait : pixels pivotés et étiquette EXIF Orientation = 6 (voir test_vignettes.lua).
    local octets = lire(f('H0.jpg'))
    local tiff = 'II*\0\8\0\0\0' .. '\1\0' .. '\18\1\3\0\1\0\0\0\6\0\0\0' .. '\0\0\0\0'
    local app1 = '\255\225' .. string.char(0, #tiff + 8) .. 'Exif\0\0' .. tiff
    local sortie = io.open(f('H.jpg'), 'wb'); sortie:write(octets:sub(1, 2), app1, octets:sub(3)); sortie:close()
  end
  verifier('fichier qui n’est pas une image', (function() local fh = io.open(f('faux.jpg'), 'wb'); fh:write('pas une image'); fh:close(); return true end)(), true)

  local copies = {}
  local reel = {}   -- chemin « accentué » du test → fichier réel
  local mocks = {
    LrPathUtils = {
      child = function(a, b) return a .. '\\' .. b end,
      getStandardFilePath = function(nom) assert(nom == 'temp'); return DOSSIER end,
    },
    LrFileUtils = {
      directoryEntries = function(dossier)
        local liste = dossier == 'C:\\Program Files' and { 'C:\\Program Files\\ImageMagick-7.1.2-Q16-HDRI' } or {}
        local i = 0
        return function() i = i + 1; return liste[i] end
      end,
      exists = function(p) local fh = io.open(p, 'rb'); if fh then fh:close(); return 'file' end return false end,
      copy = function(source, destination)
        copies[#copies + 1] = source
        local o = lire(reel[source] or source); if not o then return false end
        local sortie = io.open(destination, 'wb'); sortie:write(o); sortie:close()
        return true
      end,
      move = function(a, b)
        local o = lire(a); if not o then return false end
        local sortie = io.open(b, 'wb'); if not sortie then return false end
        sortie:write(o); sortie:close(); os.remove(a)
        return true
      end,
      readFile = lire,
      delete = function(p) os.remove(p) end,
    },
    LrTasks = { pcall = pcall, execute = function(commande) return executer(commande) and 0 or 1 end },
  }
  function import(nom) return assert(mocks[nom], 'module inconnu : ' .. nom) end
  local Vignettes = require 'Vignettes'

  -- Dimensions d'un fichier, lues par ImageMagick.
  local function dimensions(chemin)
    executer('"' .. '"' .. MAGICK .. '" identify -format "%w %h" "' .. chemin .. '" > "' .. f('dims.txt') .. '"' .. '"')
    local l, h = (lire(f('dims.txt')) or ''):match('(%d+) (%d+)')
    return tonumber(l), tonumber(h)
  end

  verifier('aperçu écrit', Vignettes.apercu(f('A.jpg'), f('apercus\\a.jpg')), true)
  local l, h = dimensions(f('apercus\\a.jpg'))
  verifier('aperçu : 220 px sur le grand côté', math.max(l or 0, h or 0), 220)
  verifier('aperçu : proportions conservées', math.abs((l or 1) / (h or 1) - 1200 / 788) < 0.03, true)
  verifier('aperçu : léger', #(lire(f('apercus\\a.jpg')) or '') < 30000, true)
  verifier('aperçu : JPEG', (lire(f('apercus\\a.jpg')) or ''):sub(1, 2), '\255\216')
  verifier('aperçu d’une petite image : pas agrandie', Vignettes.apercu(f('B.jpg'), f('apercus\\b.jpg')), true)
  l, h = dimensions(f('apercus\\b.jpg'))
  verifier('aperçu d’une petite image : 480 px réduits à 220', math.max(l or 0, h or 0), 220)

  verifier('portrait : aperçu écrit', Vignettes.apercu(f('H.jpg'), f('apercus\\h.jpg')), true)
  l, h = dimensions(f('apercus\\h.jpg'))
  verifier('portrait : redressé selon l’étiquette EXIF (la photo est affichée à l’endroit)', l and h and l > h, true)

  -- Chemin accentué : copie sous un nom simple, destination accentuée acceptée.
  reel['D:\\Photographies\\D\195\169sordre\\A.jpg'] = f('A.jpg')
  copies = {}
  verifier('chemin accentué : aperçu écrit', Vignettes.apercu('D:\\Photographies\\D\195\169sordre\\A.jpg', f('apercus\\accent.jpg')), true)
  verifier('chemin accentué : source copiée', #copies, 1)
  verifier('chemin accentué : même aperçu', lire(f('apercus\\accent.jpg')), lire(f('apercus\\a.jpg')))

  -- Un aperçu déjà là est remplacé.
  local fh = io.open(f('apercus\\a.jpg'), 'wb'); fh:write('ancien'); fh:close()
  verifier('aperçu existant remplacé', Vignettes.apercu(f('A.jpg'), f('apercus\\a.jpg')), true)
  verifier('aperçu existant : nouveau contenu', #(lire(f('apercus\\a.jpg')) or '') > 100, true)

  verifier('fichier illisible : pas d’aperçu', Vignettes.apercu(f('faux.jpg'), f('apercus\\faux.jpg')), nil)
  verifier('fichier illisible : rien d’écrit', io.open(f('apercus\\faux.jpg'), 'rb'), nil)
  verifier('fichier absent', Vignettes.apercu(f('absent.jpg'), f('apercus\\absent.jpg')), nil)
  verifier('vidéo ignorée', Vignettes.apercu('D:\\x\\film.mp4', f('apercus\\film.jpg')), nil)
  local restes = {}
  for fichier in io.popen('dir /b "' .. DOSSIER .. '" 2>nul'):lines() do
    if fichier:find('^lrgp%-vignette') then restes[#restes + 1] = fichier end
  end
  verifier('fichiers temporaires supprimés', #restes, 0)

  -- Page d'exemple avec de vraies miniatures : à ouvrir dans un navigateur pour la regarder.
  local demo = (SCRATCH .. '/rapport-demo'):gsub('/', '\\')
  os.execute('rmdir /s /q "' .. demo .. '" 2>nul')
  os.execute('mkdir "' .. demo .. '\\vignettes" 2>nul')
  local sources = { A = 'A.jpg', B = 'B.jpg', D = 'D.jpg', H = 'H.jpg' }
  local function reelle(id, source, extra)
    local c = copie(id, extra.chemin, extra)
    local fichier = f(sources[source])
    c.octets = #lire(fichier)
    c.taille = c.octets
    local largeur, hauteur = dimensions(fichier)
    c.dimensions, c.pixels = largeur .. 'x' .. hauteur, largeur * hauteur
    Vignettes.apercu(fichier, demo .. '\\vignettes\\' .. id .. '.jpg')
    return c
  end
  local g1 = decision({
    reelle(101, 'A', { chemin = P .. '202x\\2020\\200301. Gien\\IMG_0001.JPG', date = dateLr('2020-03-01 10:00:00'), collections = { col(2, 'Google Photos - époques / 2020') } }),
    reelle(102, 'A', { chemin = A .. 'Désordre\\2020\\IMG_0001.JPG', date = dateLr('2020-03-01 10:00:00'), empreinte = 'e1',
      collections = { col(1, 'Google Photos - albums / 2020-03-01 – Gien'), col(2, 'Google Photos - époques / 2020') },
      motsCles = { mot('Gien'), mot('Loire') }, note = 3, drapeau = 1, textes = { city = 'Gien', country = 'France' }, gps = { latitude = 47.7 } }),
  })
  local g2 = decision({
    reelle(103, 'A', { chemin = P .. '201x\\2018\\180819. Fête\\IMG_0002.JPG', date = dateLr('2018-08-19 15:00:00'), empreinte = 'a' }),
    reelle(104, 'B', { chemin = A .. 'Désordre\\2018\\IMG_0002-2.JPG', date = dateLr('2018-08-19 15:00:00'), empreinte = 'b',
      collections = { col(4, 'Google Photos - albums / 2018-08-19 – Fête') }, motsCles = { mot('Fête') } }),
  })
  local g3 = decision({
    reelle(105, 'A', { chemin = P .. '202x\\2022\\IMG_0003.JPG', date = dateLr('2022-05-01 09:00:00'), retouchee = true, empreinte = 'e1' }),
    reelle(106, 'A', { chemin = A .. 'Désordre\\2022\\IMG_0003.JPG', date = dateLr('2022-05-01 09:00:00'), retouchee = true, empreinte = 'e1' }),
  })
  local apart = { {
    reelle(107, 'A', { chemin = P .. '202x\\2026\\DSCF5219.JPG', date = dateLr('2026-08-19 20:39:08'), empreinte = 'p' }),
    reelle(108, 'D', { chemin = P .. '202x\\2026\\DSCF5219-Modifier.JPG', date = dateLr('2026-08-19 20:39:08'), empreinte = 'q' }),
    reelle(109, 'H', { chemin = P .. '202x\\2026\\DSCF5219-2.JPG', date = dateLr('2026-08-19 20:39:08'), empreinte = 'r' }),
  } }
  local pageDemo = RapportHtml.page({
    portee = 'les 312 photos sélectionnées', date = '2026-10-27 14:05', collection = 'Doublons à retirer',
    decisions = { g1, g2, g3 }, differents = apart, vignette = apercu, notes = { 'Page d’exemple générée par le test.' },
  })
  local out = io.open(demo .. '\\index.html', 'wb'); out:write(pageDemo); out:close()
  verifier('page d’exemple écrite', #pageDemo > 5000, true)
  verifier('page d’exemple : les aperçus existent', lire(demo .. '\\vignettes\\101.jpg') ~= nil and lire(demo .. '\\vignettes\\109.jpg') ~= nil, true)
end

print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
