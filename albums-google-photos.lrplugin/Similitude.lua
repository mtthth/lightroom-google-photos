-- Reconnaît deux versions d'une même prise de vue : une copie réduite ou recompressée (à fusionner
-- en gardant la plus grande) contre une version retouchée (à garder avec l'original).
-- Pur Lua, sans appel à Lightroom, pour pouvoir être testé à part.
--
-- Chaque version est décrite par une miniature de 16 × 16 pixels (768 octets, rouge-vert-bleu,
-- voir Vignettes.lua) et par ses dimensions après rotation EXIF. Mesures faites sur le catalogue
-- (copies de même nom d'origine et de même date, images différentes) :
--   - copie réduite ou recompressée : écart moyen de 0,3 à 1,5 sur 255 (au plus 10 sur un bloc) ;
--   - retouche (exposition, teinte, effacement, recadrage) : écart moyen de 4 et plus.
-- Les seuils sont placés entre les deux, du côté prudent : dans le doute, les deux versions sont
-- gardées. Un nom qui annonce une retouche (« -Modifier ») interdit cette comparaison approximative;
-- une empreinte exacte identique est traitée séparément comme un doublon.

local M = {}

M.ECART_MOYEN_MAX = 2.0   -- écart moyen sur l'ensemble des valeurs (0 à 255)
M.ECART_BLOC_MAX = 16     -- écart maximal sur une seule valeur
M.ECART_CANAL_MAX = 2.0   -- écart de la moyenne d'un canal (exposition, teinte)
M.TOLERANCE_FORME = 0.02  -- écart relatif toléré entre les rapports largeur / hauteur

-- Écarts entre deux miniatures de même taille : { moyen, max, canal } ou nil.
function M.ecarts(a, b)
  if type(a) ~= 'string' or type(b) ~= 'string' or #a ~= #b or #a == 0 or #a % 3 ~= 0 then return nil end
  local somme, max = 0, 0
  local canaux = { 0, 0, 0 }
  for i = 1, #a do
    local x, y = a:byte(i), b:byte(i)
    local d = math.abs(x - y)
    somme = somme + d
    if d > max then max = d end
    local c = (i - 1) % 3 + 1
    canaux[c] = canaux[c] + (x - y)
  end
  local nbPixels = #a / 3
  local canal = 0
  for c = 1, 3 do canal = math.max(canal, math.abs(canaux[c]) / nbPixels) end
  return { moyen = somme / #a, max = max, canal = canal }
end

-- Marqueurs de retouche dans un nom de fichier (motifs Lua, en minuscules) :
--   « -Modifier » et « -Modifié » (éditeurs externes en français, y compris « -Modifié-2026-08-02T22-37-43 »),
--   « -Edit », « -Edited », « -Retouche », « _filtered »,
--   « -20260821-DxO_DeepPRIME XD3 » et « -DxO_DeepPRIME 3 » (DxO PureRAW, avec ou sans date).
-- Pour en ajouter un, il suffit de l'inscrire ici : la comparaison visuelle approximative comme la
-- recherche des copies d'un même fichier (Doublons.nomDeBase) s'en servent. Le marqueur le plus
-- long (date + DxO) doit précéder le plus court, car nomDeBase les retire dans cet ordre.
M.MARQUEURS_RETOUCHE = { '%-modifi', '%-edit', '%-retouch', '[_%-]filtered',
  '%-%d%d%d%d%d%d%d%d%-dxo_', '[ _%-]dxo_' }

-- Vrai si le nom annonce une version retouchée.
function M.nomRetouche(nom)
  local bas = (nom:match('[^/\\]+$') or nom):lower()
  for _, marqueur in ipairs(M.MARQUEURS_RETOUCHE) do
    if bas:find(marqueur) then return true end
  end
  return false
end

-- a, b : { signature, largeur, hauteur, retouchee } ; retouchee = tous les fichiers de cette
-- image portent un nom de retouche.
function M.memeVue(a, b)
  if not a.signature or not b.signature or a.retouchee or b.retouchee then return false end
  if not (a.largeur and a.hauteur and b.largeur and b.hauteur) or a.hauteur == 0 or b.hauteur == 0 then return false end
  local formeA, formeB = a.largeur / a.hauteur, b.largeur / b.hauteur
  if math.abs(formeA / formeB - 1) > M.TOLERANCE_FORME then return false end
  local e = M.ecarts(a.signature, b.signature)
  return e ~= nil and e.moyen <= M.ECART_MOYEN_MAX and e.max <= M.ECART_BLOC_MAX and e.canal <= M.ECART_CANAL_MAX
end

-- classes : images différentes d'une même prise de vue possible, chacune
--   { pixels, octets, signature, largeur, hauteur, retouchee, … }.
-- Renvoie des groupes de classes qui montrent la même vue ; la première de chaque groupe est la
-- plus grande (pixels, puis taille du fichier), les autres sont des versions plus petites ou
-- recompressées d'elle. Les classes sans miniature, retouchées ou différentes restent seules.
-- Chaque classe est comparée à la plus grande seulement : pas d'enchaînement de ressemblances.
function M.regrouper(classes)
  local restantes = {}
  for i, c in ipairs(classes) do restantes[i] = c end
  table.sort(restantes, function(a, b)
    if (a.pixels or 0) ~= (b.pixels or 0) then return (a.pixels or 0) > (b.pixels or 0) end
    return (a.octets or 0) > (b.octets or 0)
  end)
  local groupes = {}
  while #restantes > 0 do
    local maitresse = table.remove(restantes, 1)
    local groupe, autres = { maitresse }, {}
    for _, c in ipairs(restantes) do
      if M.memeVue(maitresse, c) then groupe[#groupe + 1] = c else autres[#autres + 1] = c end
    end
    restantes = autres
    groupes[#groupes + 1] = groupe
  end
  return groupes
end

return M
