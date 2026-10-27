-- Retrouve une photo Google Photos parmi les photos du catalogue.
-- Pur Lua, sans appel à Lightroom, pour pouvoir être testé à part.
--
-- Les fichiers envoyés sur Google Photos ont souvent été renommés à l'export, par exemple
-- « 20250101T184015-IMG_6323-4032 x 3024.jpg » pour IMG_6323.HEIC dans le catalogue :
-- on compare donc le nom d'origine, débarrassé de la date en tête et des dimensions en fin.
--
-- Ordre des essais :
--   1. même nom de fichier ;
--   2. même nom d'origine (sans extension, préfixe de date ni dimensions) ;
--   3. même nom d'origine sans suffixe de copie (« IMG_6368-2 » → « IMG_6368 ») ;
--   4. même date de prise de vue à la seconde.
-- Quand plusieurs photos correspondent, on garde celle qui a la même date, puis la même
-- extension, puis un nom d'origine proche ; si le doute subsiste, la photo n'est pas retenue.

local M = {}

local function sansExtension(nom)
  return (nom:gsub('%.[^%.]*$', ''))
end

local function extension(nom)
  return nom:match('%.([^%.]*)$') or ''
end

-- Nom d'origine, en minuscules et sans extension.
local function nomOrigine(nom)
  local base = sansExtension(string.lower(nom))
  base = base:gsub('^%d%d%d%d%d%d%d%dt%d%d%d%d%d%d%-', '')   -- 20250101T184015-
  base = base:gsub('^%d%d%d%d%d%d%d%d%d%d%d%d%d%d_', '')     -- 20250726134024_
  base = base:gsub('%-%d+ x %d+$', '')                       -- -4032 x 3024
  base = base:gsub('__%d+px$', '')                           -- __4096px
  base = base:gsub('~%d+$', '')                              -- DSCF3765~2 (appli de transfert)
  return base
end

local function sansSuffixeCopie(base)
  return (base:gsub('%-%d$', ''))
end

-- Date contenue dans un nom de la forme « 20250101T184015-… » ou « 20250726134024_… »,
-- au format AAAA-MM-JJ HH:MM:SS.
function M.dateDuNom(nom)
  local a, mo, j, h, mi, s = nom:match('^(%d%d%d%d)(%d%d)(%d%d)[tT]?(%d%d)(%d%d)(%d%d)[%-_]')
  if not a then return nil end
  return string.format('%s-%s-%s %s:%s:%s', a, mo, j, h, mi, s)
end

function M.nouvelIndex()
  return { fichier = {}, origine = {}, date = {} }
end

local function ajouter(table_, cle, entree)
  if not cle or cle == '' then return end
  table_[cle] = table_[cle] or {}
  table.insert(table_[cle], entree)
end

-- date : date de prise de vue du catalogue (AAAA-MM-JJ HH:MM:SS), ou nil si inconnue.
function M.ajouterPhoto(index, photo, nomFichier, date)
  local nom = string.lower(nomFichier or '')
  local origine = nomOrigine(nom)
  local dateNom = M.dateDuNom(nom)
  local entree = { photo = photo, origine = origine, extension = extension(nom), date = date or dateNom }

  ajouter(index.fichier, nom, entree)
  ajouter(index.origine, origine, entree)
  if sansSuffixeCopie(origine) ~= origine then ajouter(index.origine, sansSuffixeCopie(origine), entree) end
  ajouter(index.date, entree.date, entree)
  if dateNom and dateNom ~= entree.date then ajouter(index.date, dateNom, entree) end
end

local function filtrer(candidats, critere)
  local gardes = {}
  for _, c in ipairs(candidats) do
    if critere(c) then table.insert(gardes, c) end
  end
  return gardes
end

local function enSecondes(date)
  local a, mo, j, h, mi, s = (date or ''):match('^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)$')
  if not a then return nil end
  -- Nombre de jours depuis une origine fixe (algorithme des jours civils).
  local annee, mois = tonumber(a), tonumber(mo)
  if mois <= 2 then annee = annee - 1 end
  local ere = math.floor(annee / 400)
  local an = annee - ere * 400
  local jourAn = math.floor((153 * ((mois + 9) % 12) + 2) / 5) + tonumber(j) - 1
  local jourEre = an * 365 + math.floor(an / 4) - math.floor(an / 100) + jourAn
  local jours = ere * 146097 + jourEre
  return ((jours * 24 + tonumber(h)) * 60 + tonumber(mi)) * 60 + tonumber(s)
end

local INCONNU = 1e12

-- Écart en secondes entre deux dates ; 0 si aucune n'est connue, INCONNU si une seule l'est.
local function ecartDates(d1, d2)
  local s1, s2 = enSecondes(d1), enSecondes(d2)
  if s1 and s2 then return math.abs(s1 - s2) end
  if not s1 and not s2 then return 0 end
  return INCONNU
end

-- Vrai si les deux dates sont connues et à plus de 26 heures d'écart.
local function datesEloignees(d1, d2)
  local s1, s2 = enSecondes(d1), enSecondes(d2)
  return s1 ~= nil and s2 ~= nil and math.abs(s1 - s2) > 26 * 3600
end

local function nomsProches(a, b)
  return a:find(b, 1, true) == 1 or b:find(a, 1, true) == 1
end

local function avantPhoto(a, b)
  local function identifiant(photo)
    if type(photo) == 'number' or type(photo) == 'string' then return photo end
    local ok, id = pcall(function() return photo.localIdentifier end)
    return ok and id or tostring(photo)
  end
  local idA, idB = identifiant(a.photo), identifiant(b.photo)
  if type(idA) == 'number' and type(idB) == 'number' and idA ~= idB then return idA < idB end
  return tostring(a.photo) < tostring(b.photo)
end

-- parNom : les candidats partagent déjà le nom ; sinon ils ne partagent que la date.
local function choisir(candidats, cherche, parNom)
  if not candidats or #candidats == 0 then return nil end

  local vus, uniques = {}, {}
  for _, c in ipairs(candidats) do
    if not vus[c.photo] then
      vus[c.photo] = true
      table.insert(uniques, c)
    end
  end
  local restants = uniques
  if parNom then
    -- Écarte les homonymes pris à un autre moment (compteur d'appareil revenu à zéro…),
    -- en tolérant un écart de fuseau horaire.
    restants = filtrer(uniques, function(c) return not datesEloignees(c.date, cherche.date) end)
    if #restants <= 1 then return restants[1] and restants[1].photo end
    -- Garde les plus proches dans le temps (même date si les horloges sont d'accord).
    local meilleur = nil
    for _, c in ipairs(restants) do
      c.ecart = ecartDates(c.date, cherche.date)
      if not meilleur or c.ecart < meilleur then meilleur = c.ecart end
    end
    if meilleur >= INCONNU then return nil end
    restants = filtrer(restants, function(c) return c.ecart == meilleur end)
  end
  if #restants == 1 then return restants[1].photo end

  local memeExtension = filtrer(restants, function(c) return c.extension == cherche.extension end)
  if #memeExtension == 1 then return memeExtension[1].photo end

  local proches = filtrer(restants, function(c) return nomsProches(c.origine, cherche.origine) end)
  if #proches == 1 then return proches[1].photo end

  -- Même nom et même date : choisir le même enregistrement à chaque exécution évite d'ajouter
  -- des doublons dans une collection si plusieurs entrées Lightroom sont ambiguës.
  if parNom then
    local choix = #memeExtension > 0 and memeExtension or restants
    table.sort(choix, avantPhoto)
    return choix[1].photo
  end
  return nil
end

-- Renvoie la photo du catalogue qui correspond, ou nil.
function M.retrouver(index, nomFichier, date)
  local nom = string.lower(nomFichier or '')
  if date == '' then date = nil end
  local cherche = {
    origine = nomOrigine(nom),
    extension = extension(nom),
    date = date or M.dateDuNom(nom),
  }

  return choisir(index.fichier[nom], cherche, true)
    or choisir(index.origine[cherche.origine], cherche, true)
    or choisir(index.origine[sansSuffixeCopie(cherche.origine)], cherche, true)
    or (cherche.date and choisir(index.date[cherche.date], cherche, false))
    or nil
end

M.nomOrigine = nomOrigine

return M
