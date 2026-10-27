-- Rapport HTML de « Fusionner les doublons » : montre, avant toute modification, ce que la commande ferait,
-- groupe par groupe (miniatures, copie gardée et pourquoi, ce qui change dans les collections et les
-- métadonnées). Pur Lua, sans appel à Lightroom, pour pouvoir être testé à part.
--
-- Le rapport est construit à partir des mêmes décisions et du même plan (Doublons.decider et
-- Doublons.effets) que ceux que la commande applique : il ne peut pas annoncer autre chose que ce qui sera fait.
--
-- Modèle (table passée à page) :
--   portee      texte : « les 312 photos sélectionnées »…
--   date        texte : date du rapport
--   collection  nom de la collection où vont les copies retirées
--   decisions   liste de décisions (Doublons.decider) ; celles sans aVerifier portent un champ effets
--   differents  listes de copies conservées à part (versions retouchées, images différentes)
--   vignette    fonction(copie) → chemin relatif de l'aperçu, ou nil
--   notes       phrases à ajouter en bas (fichiers illisibles, ImageMagick absent…)

local Doublons = require 'Doublons'
local Epoques = require 'Epoques'
local Similitude = require 'Similitude'

local M = {}

local function h(texte)
  return (tostring(texte):gsub('[&<>"\']', {
    ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;', ["'"] = '&#39;',
  }))
end

local function pluriel(n, singulier, plur)
  return n .. ' ' .. (n > 1 and (plur or (singulier .. 's')) or singulier)
end

local function nomFichier(chemin)
  return chemin:match('[^/\\]+$') or chemin
end

local function taille(octets)
  octets = octets or 0
  if octets >= 1024 ^ 3 then return (string.format('%.2f Go', octets / 1024 ^ 3):gsub('%.', ',')) end
  if octets >= 1024 ^ 2 then return (string.format('%.1f Mo', octets / 1024 ^ 2):gsub('%.', ',')) end
  return string.format('%d Ko', math.floor(octets / 1024 + 0.5))
end

local function dateTexte(date)
  return date and Epoques.texte(Epoques.depuisLightroom(date, 0)) or 'date inconnue'
end

-- Les trois derniers dossiers du chemin : « … / 2018 / 2018-08-12 ».
local function dossierCourt(chemin)
  local parties = {}
  for partie in (chemin:gsub('\\', '/')):gmatch('[^/]+') do parties[#parties + 1] = partie end
  table.remove(parties)   -- le nom du fichier
  local debut = math.max(1, #parties - 2)
  local texte = table.concat(parties, ' / ', debut)
  return (debut > 1 and '… / ' or '') .. texte
end

local function dossierComplet(chemin)
  return ((chemin:gsub('\\', '/')):gsub('/[^/]*$', ''))
end

-- Adresse file:/// d'un fichier, pour l'ouvrir dans le navigateur (espaces et accents encodés).
function M.urlFichier(chemin)
  local c = chemin:gsub('\\', '/')
  c = c:gsub('[^%w%-%._~/:]', function(x) return string.format('%%%02X', x:byte()) end)
  return 'file:///' .. c
end

local function badge(classe, texte)
  return string.format('<span class="badge %s">%s</span>', classe, h(texte))
end

-- Ce qui distingue une copie, en pastilles (retouches, copies virtuelles, notes, mots-clés…).
local function badges(c)
  local b = {}
  if Similitude.nomRetouche(nomFichier(c.chemin)) then b[#b + 1] = badge('b-nom', 'nom de retouche') end
  if c.retouchee then b[#b + 1] = badge('b-lr', 'retouchée dans Lightroom') end
  if (c.virtuelles or 0) > 0 then b[#b + 1] = badge('b-lr', pluriel(c.virtuelles, 'copie virtuelle', 'copies virtuelles')) end
  if c.publiee then b[#b + 1] = badge('b-lr', 'publiée') end
  if (c.note or 0) > 0 then b[#b + 1] = badge('', string.rep('★', c.note)) end
  if c.drapeau == 1 then b[#b + 1] = badge('', 'retenue') elseif c.drapeau == -1 then b[#b + 1] = badge('', 'rejetée') end
  if c.motsCles and #c.motsCles > 0 then b[#b + 1] = badge('', pluriel(#c.motsCles, 'mot-clé', 'mots-clés')) end
  local nbCollections = 0
  for _, col in ipairs(c.collections or {}) do
    if not col.dynamique and not col.exclue then nbCollections = nbCollections + 1 end
  end
  if nbCollections > 0 then b[#b + 1] = badge('', pluriel(nbCollections, 'collection')) end
  return table.concat(b)
end

local LIBELLES = { garder = 'Gardée', retirer = 'Retirée', verifier = 'À vérifier', serait = 'Serait gardée', apart = 'Conservée' }

local function figure(c, role, vignette)
  local chemin = vignette and vignette(c)
  local image = chemin and string.format('<img src="%s" alt="" loading="lazy" decoding="async">', h(chemin))
    or '<div class="vide">pas d’aperçu</div>'
  local infos = {}
  if c.dimensions then infos[#infos + 1] = c.dimensions end
  infos[#infos + 1] = taille(c.octets or c.taille)
  infos[#infos + 1] = dateTexte(c.date)
  return string.format(
    '<figure class="%s"><div class="img">%s<em>%s</em></div><figcaption><b title="%s">%s</b>'
    .. '<small title="%s">%s</small><small>%s</small><div class="badges">%s</div></figcaption></figure>',
    role == 'serait' and 'garder' or role, image, h(LIBELLES[role]), h(c.chemin), h(nomFichier(c.chemin)),
    h(dossierComplet(c.chemin)), h(dossierCourt(c.chemin)), h(table.concat(infos, ' · ')), badges(c))
end

local function liste(elements)
  local items = {}
  for _, e in ipairs(elements) do items[#items + 1] = '<li>' .. e .. '</li>' end
  return '<ul>' .. table.concat(items) .. '</ul>'
end

local function guillemets(noms)
  local r = {}
  for i, n in ipairs(noms) do r[i] = '« ' .. h(n) .. ' »' end
  return table.concat(r, ', ')
end

-- Les changements d'un groupe fusionné, en phrases (voir Doublons.effets).
local function lignesEffets(e, collectionARetirer)
  local l = {}
  if #e.collections > 0 then
    local noms = {}
    for i, col in ipairs(e.collections) do noms[i] = col.nom end
    l[#l + 1] = 'La copie gardée rejoint ' .. pluriel(#noms, 'collection') .. ' : ' .. guillemets(noms)
  end
  local quittees, vues = {}, {}
  for _, q in ipairs(e.quittees) do
    if not vues[q.collection.id] then
      vues[q.collection.id] = true
      quittees[#quittees + 1] = q.collection.nom
    end
  end
  if #quittees > 0 then l[#l + 1] = 'Les copies retirées sortent de : ' .. guillemets(quittees) end
  if #e.motsCles > 0 then
    local noms = {}
    for i, mot in ipairs(e.motsCles) do noms[i] = mot.nom end
    l[#l + 1] = 'Mots-clés ajoutés : ' .. guillemets(noms)
  end
  if e.note then l[#l + 1] = 'Note relevée à ' .. string.rep('★', e.note) end
  if e.drapeau then
    local choix = e.drapeau == 1 and 'retenue' or 'rejetée'
    l[#l + 1] = 'Drapeau « ' .. choix .. ' » recopié'
  end
  for _, t in ipairs(e.textes) do
    l[#l + 1] = h(Doublons.NOMS_CHAMPS[t.cle] or t.cle) .. ' recopié(e) : ' .. h(t.valeur)
  end
  if e.gps then l[#l + 1] = 'Position GPS recopiée' end
  l[#l + 1] = 'Les copies retirées vont dans la collection « ' .. h(collectionARetirer) .. ' » : rien n’est supprimé.'
  return l
end

local function texteRecherche(copies)
  local t = {}
  for _, c in ipairs(copies) do t[#t + 1] = (nomFichier(c.chemin) .. ' ' .. dossierComplet(c.chemin)):lower() end
  return table.concat(t, ' ')
end

-- Carte d'un groupe fusionné (classe « fusion ») ou laissé tel quel (classe « verifier »).
local function carteDecision(numero, d, m)
  local verifier = d.aVerifier ~= nil
  local copies = { d.garde }
  for _, c in ipairs(d.retirees) do copies[#copies + 1] = c end
  local figures = { figure(d.garde, verifier and 'serait' or 'garder', m.vignette) }
  for _, c in ipairs(d.retirees) do figures[#figures + 1] = figure(c, verifier and 'verifier' or 'retirer', m.vignette) end

  local corps
  if verifier then
    corps = '<p class="pourquoi">À vérifier : ' .. h(d.aVerifier) .. '. <b>Rien ne sera fait pour ce groupe.</b></p>'
  else
    corps = '<p class="pourquoi">Copie gardée : ' .. h(d.pourquoi or '') .. '.</p>'
      .. liste(lignesEffets(d.effets, m.collection))
  end
  local genre = d.memeImage and 'même image' or 'copie réduite ou recompressée'
  return string.format(
    '<article class="carte %s" id="g%d" data-type="%s" data-q="%s"><h3>Groupe %d <small>%s · %s · %s</small></h3>'
    .. '<div class="copies">%s</div>%s</article>',
    verifier and 'verifier' or 'fusion', numero, d.memeImage and 'identique' or 'reduite', h(texteRecherche(copies)),
    numero, h(nomFichier(d.garde.chemin)), h(dateTexte(d.garde.date)), h(genre), table.concat(figures), corps)
end

-- Carte d'un groupe dont les versions restent toutes à part.
local function carteApart(numero, copies, m)
  local figures, retouche = {}, false
  for _, c in ipairs(copies) do
    figures[#figures + 1] = figure(c, 'apart', m.vignette)
    if Similitude.nomRetouche(nomFichier(c.chemin)) then retouche = true end
  end
  local pourquoi = retouche
    and 'Un fichier dont le nom annonce une retouche n’est jamais retiré au profit d’une copie sans marqueur.'
    or 'Les images diffèrent (version retouchée, recadrée ou recompressée) : les copies ne sont pas fusionnées.'
  return string.format(
    '<article class="carte apart" id="d%d" data-type="apart" data-q="%s"><h3>Versions %d <small>%s</small></h3>'
    .. '<div class="copies">%s</div><p class="pourquoi">%s <b>Tout est conservé.</b></p></article>',
    numero, h(texteRecherche(copies)), numero, h(nomFichier(copies[1].chemin)), table.concat(figures), pourquoi)
end

local function triParDate(elements, date)
  local indices = {}
  for i = 1, #elements do indices[i] = i end
  table.sort(indices, function(a, b)
    local da, db = date(elements[a]) or math.huge, date(elements[b]) or math.huge
    if da ~= db then return da < db end
    return a < b
  end)
  return indices
end

local CSS = [==[
:root { --fond:#fafaf8; --texte:#222; --doux:#666; --garder:#2e8b57; --retirer:#c0392b; --apart:#2f6fd6; --verifier:#c27c0e; --carte:#fff; --bord:#ddd; }
@media (prefers-color-scheme: dark) { :root { --fond:#16181a; --texte:#e8e8e8; --doux:#9a9a9a; --carte:#202326; --bord:#363a3e; } }
* { box-sizing: border-box; }
body { font: 15px/1.45 system-ui, sans-serif; margin: 0; padding: 24px 16px 60px; background: var(--fond); color: var(--texte); }
main { max-width: 1280px; margin: 0 auto; }
h1 { margin: 0 0 4px; font-size: 1.5rem; } h2 { margin: 34px 0 6px; font-size: 1.2rem; } h2 small { color: var(--doux); font-weight: normal; }
h3 { margin: 0 0 8px; font-size: .98rem; } h3 small { color: var(--doux); font-weight: normal; }
.resume { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; margin: 16px 0; }
.resume div { background: var(--carte); border: 1px solid var(--bord); border-radius: 8px; padding: 10px 12px; }
.resume b { display: block; font-size: 1.45rem; } .resume span { color: var(--doux); font-size: .85rem; }
.legende span { display: inline-block; margin-right: 14px; } .legende i { display: inline-block; width: 12px; height: 12px; border-radius: 3px; vertical-align: -1px; margin-right: 4px; }
.barre { position: sticky; top: 0; z-index: 5; background: var(--fond); padding: 10px 0; border-bottom: 1px solid var(--bord); display: flex; flex-wrap: wrap; gap: 14px; align-items: center; }
.barre input[type=search] { padding: 6px 10px; border: 1px solid var(--bord); border-radius: 6px; background: var(--carte); color: var(--texte); min-width: 240px; }
.carte { background: var(--carte); border: 1px solid var(--bord); border-left: 5px solid var(--bord); border-radius: 8px; padding: 12px 14px; margin: 12px 0; content-visibility: auto; contain-intrinsic-size: 360px; }
.carte.fusion { border-left-color: var(--garder); } .carte.verifier { border-left-color: var(--verifier); } .carte.apart { border-left-color: var(--apart); }
.copies { display: flex; flex-wrap: wrap; gap: 12px; }
figure { margin: 0; width: 220px; border: 3px solid var(--bord); border-radius: 6px; overflow: hidden; background: var(--carte); }
figure.garder { border-color: var(--garder); } figure.retirer { border-color: var(--retirer); } figure.verifier { border-color: var(--verifier); } figure.apart { border-color: var(--apart); }
figure.retirer img { opacity: .72; }
.img { position: relative; height: 165px; background: rgba(128,128,128,.12); display: grid; place-items: center; }
.img img { max-width: 100%; max-height: 100%; display: block; }
.img em { position: absolute; top: 6px; left: 6px; font-style: normal; font-size: .72rem; font-weight: 600; color: #fff; padding: 2px 7px; border-radius: 10px; background: var(--garder); }
figure.retirer em { background: var(--retirer); } figure.verifier em { background: var(--verifier); } figure.apart em { background: var(--apart); }
.vide { color: var(--doux); font-size: .78rem; }
figcaption { padding: 6px 8px 8px; font-size: .78rem; line-height: 1.3; }
figcaption b { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
figcaption small { display: block; color: var(--doux); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.badges { margin-top: 4px; } .badge { display: inline-block; margin: 0 3px 3px 0; padding: 0 6px; border-radius: 9px; font-size: .68rem; border: 1px solid var(--bord); color: var(--doux); }
.badge.b-lr { border-color: var(--verifier); color: var(--verifier); } .badge.b-nom { border-color: var(--apart); color: var(--apart); }
.pourquoi { margin: 10px 0 4px; } .carte ul { margin: 4px 0 0; padding-left: 20px; color: var(--texte); } .carte li { margin: 1px 0; }
.notes { color: var(--doux); } code { background: rgba(128,128,128,.15); padding: 1px 5px; border-radius: 4px; }
]==]

local SCRIPT = [==[
const recherche = document.getElementById('recherche');
const seulementReduites = document.getElementById('seulement-reduites');
const compte = document.getElementById('compte');
function filtrer() {
  const t = recherche.value.trim().toLowerCase();
  let visibles = 0;
  document.querySelectorAll('.carte').forEach((c) => {
    const ok = (!t || c.dataset.q.includes(t)) && (!seulementReduites.checked || c.dataset.type === 'reduite');
    c.hidden = !ok;
    if (ok) visibles++;
  });
  compte.textContent = visibles + (visibles > 1 ? ' groupes affichés' : ' groupe affiché');
}
recherche.addEventListener('input', filtrer);
seulementReduites.addEventListener('change', filtrer);
filtrer();
]==]

-- Construit la page HTML (texte) du rapport.
function M.page(m)
  local fusions, verifier = {}, {}
  for i, d in ipairs(m.decisions) do
    local entree = { numero = i, decision = d }
    if d.aVerifier then verifier[#verifier + 1] = entree else fusions[#fusions + 1] = entree end
  end

  -- Chiffres du résumé.
  local retirees, reduites, octets, collections = 0, 0, 0, {}
  for _, f in ipairs(fusions) do
    local d = f.decision
    retirees = retirees + #d.retirees
    for _, c in ipairs(d.retirees) do
      octets = octets + (c.octets or c.taille or 0)
      if c.empreinte ~= d.garde.empreinte then reduites = reduites + 1 end
    end
    for _, col in ipairs(d.effets.collections) do collections[col.id] = true end
    for _, q in ipairs(d.effets.quittees) do collections[q.collection.id] = true end
  end
  local nbCollections = 0
  for _ in pairs(collections) do nbCollections = nbCollections + 1 end

  local p = {}
  local function ajouter(texte) p[#p + 1] = texte end
  ajouter('<!doctype html>\n<html lang="fr"><head><meta charset="utf-8">'
    .. '<meta name="viewport" content="width=device-width, initial-scale=1"><title>Doublons — rapport avant fusion</title>'
    .. '<style>' .. CSS .. '</style></head><body><main>')
  ajouter('<h1>Doublons — rapport avant fusion</h1>')
  ajouter('<p><b>Rien n’a été modifié dans Lightroom.</b> Recherche faite sur ' .. h(m.portee) .. ' · ' .. h(m.date)
    .. '. Pour appliquer ce qui est décrit ici, reviens dans Lightroom et clique sur « Fusionner ».</p>')

  ajouter('<div class="resume">')
  -- texte : « singulier|pluriel » (le nombre s'accorde ; une valeur déjà formatée, comme une taille, prend le pluriel).
  local function carteChiffre(valeur, texte, couleur)
    local singulier, plur = texte:match('^(.-)|(.*)$')
    local accorde = (type(valeur) == 'number' and valeur == 1) and singulier or plur
    ajouter(string.format('<div><b%s>%s</b><span>%s</span></div>', couleur and (' style="color:var(--' .. couleur .. ')"') or '',
      h(valeur), h(accorde or texte)))
  end
  carteChiffre(#fusions, 'groupe à fusionner|groupes à fusionner', 'garder')
  carteChiffre(retirees, 'copie retirée (mise de côté)|copies retirées (mises de côté)', 'retirer')
  carteChiffre(reduites, 'dont copie réduite ou recompressée|dont copies réduites ou recompressées')
  carteChiffre(taille(octets), 'libérés si tu les supprimes du disque|libérés si tu les supprimes du disque')
  carteChiffre(nbCollections, 'collection modifiée|collections modifiées')
  carteChiffre(#verifier, 'groupe à vérifier (rien de fait)|groupes à vérifier (rien de fait)', 'verifier')
  carteChiffre(#m.differents, 'groupe de versions conservées|groupes de versions conservées', 'apart')
  ajouter('</div>')

  ajouter('<p class="legende"><span><i style="background:var(--garder)"></i>copie gardée</span>'
    .. '<span><i style="background:var(--retirer)"></i>copie retirée</span>'
    .. '<span><i style="background:var(--verifier)"></i>à vérifier : rien n’est fait</span>'
    .. '<span><i style="background:var(--apart)"></i>version conservée à part</span></p>')
  ajouter('<p>Dans chaque groupe fusionné : la copie gardée est la plus grande image (puis, à image identique, la copie '
    .. 'retouchée dans Lightroom, la mieux rangée…). Elle prend la place des copies retirées dans leurs collections '
    .. '(albums Google Photos compris) et récupère leurs mots-clés, leur note, leur drapeau, leur position GPS et leurs '
    .. 'textes quand elle n’en a pas. Les copies retirées sont mises dans la collection « ' .. h(m.collection)
    .. ' » ; tu les retires ensuite du catalogue toi-même. Les retouches et copies virtuelles ne sont jamais recopiées : '
    .. 'si elles sont sur une copie à retirer, le groupe reste « à vérifier ».</p>')

  ajouter('<div class="barre"><input type="search" id="recherche" placeholder="Filtrer par nom ou dossier…">'
    .. '<label><input type="checkbox" id="seulement-reduites"> copies réduites seulement</label>'
    .. '<span id="compte" class="notes"></span>'
    .. '<span class="notes">Aller à : <a href="#fusions">à fusionner</a> · <a href="#verifier">à vérifier</a> · '
    .. '<a href="#apart">conservées à part</a></span></div>')

  -- Groupes à fusionner, du plus ancien au plus récent.
  ajouter('<h2 id="fusions">À fusionner <small>' .. pluriel(#fusions, 'groupe') .. '</small></h2>')
  for _, i in ipairs(triParDate(fusions, function(f) return f.decision.garde.date end)) do
    ajouter(carteDecision(fusions[i].numero, fusions[i].decision, m))
  end
  if #fusions == 0 then ajouter('<p class="notes">Aucun groupe à fusionner.</p>') end

  if #verifier > 0 then
    ajouter('<h2 id="verifier">À vérifier <small>' .. pluriel(#verifier, 'groupe') .. ' · rien n’est fait</small></h2>')
    for _, i in ipairs(triParDate(verifier, function(f) return f.decision.garde.date end)) do
      ajouter(carteDecision(verifier[i].numero, verifier[i].decision, m))
    end
  end

  if #m.differents > 0 then
    ajouter('<h2 id="apart">Versions conservées à part <small>' .. pluriel(#m.differents, 'groupe')
      .. ' · tout est conservé</small></h2>')
    for _, i in ipairs(triParDate(m.differents, function(copies) return copies[1] and copies[1].date end)) do
      ajouter(carteApart(i, m.differents[i], m))
    end
  end

  if m.notes and #m.notes > 0 then
    local notes = {}
    for i, n in ipairs(m.notes) do notes[i] = h(n) end
    ajouter('<h2>À savoir</h2><div class="notes">' .. liste(notes) .. '</div>')
  end
  ajouter('</main><script>' .. SCRIPT .. '</script></body></html>')
  return table.concat(p, '\n')
end

return M
