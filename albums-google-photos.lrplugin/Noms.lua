-- Noms des collections : « AAAA » (ensemble par année) puis « AAAA-MM-JJ – titre ».
-- Pur Lua, sans appel à Lightroom, pour pouvoir être testé à part.
--
-- La date est celle que le titre de l'album porte en préfixe, sinon celle de la première photo.
-- Le préfixe de date du titre est retiré, car son format est différent de celui des collections.
-- Formats de préfixe reconnus :
--   2025.07.24 Lyon…    2025-07-24 Lyon…    (AAAA.MM.JJ, avec ou sans point final)
--   20260423. Plage…    20250804 Plage…     (AAAAMMJJ)
--   110909. Mariage     131102.Rando…       (AAMMJJ, point obligatoire ; AA < 31 : 20AA, sinon 19AA)
--   2112. Noël          (AAMM, point obligatoire : mois seul, jour = première photo ou 01)
--   000000. Divers      (date inconnue : le préfixe est retiré, on prend la première photo)

local M = {}

-- Ensembles de collections créés par « Recréer les albums Google Photos ». Les autres commandes du
-- module s'en servent : les albums protègent une photo (rafales), les sessions non.
M.ENSEMBLE_ALBUMS = 'Google Photos - albums'
M.ENSEMBLE_SESSIONS = 'Google Photos - sessions'
-- Nom de l'ensemble des sessions jusqu'à la version 1.0.1 : renommé au premier passage.
M.ANCIEN_ENSEMBLE_SESSIONS = 'Google Photos - époques'

local SEPARATEUR = ' – '

local function dateValide(annee, mois, jour)
  annee, mois, jour = tonumber(annee), tonumber(mois), tonumber(jour)
  if not annee or not mois or not jour then return nil end
  if mois < 1 or mois > 12 or jour < 1 or jour > 31 then return nil end
  return string.format('%04d-%02d-%02d', annee, mois, jour)
end

local function siecle(aa)
  aa = tonumber(aa)
  return aa <= 30 and 2000 + aa or 1900 + aa
end

local function nettoyer(texte)
  texte = texte:gsub('^[%s%.%-_]+', '')
  texte = texte:gsub('%s+$', '')
  return texte
end

-- titre : titre de l'album ; premiere : date « AAAA-MM-JJ » de sa première photo (ou nil).
-- Renvoie { annee = 'AAAA', nom = 'AAAA-MM-JJ – titre', date = 'AAAA-MM-JJ' ou nil }.
function M.analyser(titre, premiere)
  local reste, date, partiel = titre, nil, nil

  local a, m, j, suite = titre:match('^(%d%d%d%d)[%.%-/_](%d%d)[%.%-/_](%d%d)%.?%s*(.*)$')
  if a then
    date, reste = dateValide(a, m, j), suite
  else
    local huit
    huit, suite = titre:match('^(%d%d%d%d%d%d%d%d)[%.%s]%s*(.*)$')
    if not huit and titre:match('^%d%d%d%d%d%d%d%d$') then huit, suite = titre, '' end
    if huit then
      date, reste = dateValide(huit:sub(1, 4), huit:sub(5, 6), huit:sub(7, 8)), suite
    else
      local six
      six, suite = titre:match('^(%d%d%d%d%d%d)%.%s*(.*)$')
      if six then
        date, reste = dateValide(siecle(six:sub(1, 2)), six:sub(3, 4), six:sub(5, 6)), suite
      else
        local quatre
        quatre, suite = titre:match('^(%d%d%d%d)%.%s*(.*)$')
        if quatre then
          local mois = tonumber(quatre:sub(3, 4))
          if mois >= 1 and mois <= 12 then
            partiel = string.format('%04d-%02d', siecle(quatre:sub(1, 2)), mois)
            reste = suite
          end
        end
      end
    end
  end

  reste = nettoyer(reste)
  if reste == '' then reste = '(sans titre)' end

  if not date then
    if partiel then
      date = (premiere and premiere:sub(1, 7) == partiel) and premiere or (partiel .. '-01')
    else
      date = premiere
    end
  end

  if not date then return { annee = 'Sans date', nom = reste } end
  return { annee = date:sub(1, 4), nom = date .. SEPARATEUR .. reste, date = date }
end

-- Nom d'une collection intercalaire entre deux périodes (dates « AAAA-MM-JJ »).
function M.intercalaire(debut, fin)
  return { annee = debut:sub(1, 4), nom = debut .. SEPARATEUR .. 'Intercalaire jusqu\'au ' .. fin, date = debut }
end

return M
