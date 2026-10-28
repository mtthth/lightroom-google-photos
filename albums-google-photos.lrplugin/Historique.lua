-- Historique persistant des photos mises de côté par le module.
-- Le fichier est volontairement lisible et peut être conservé hors du catalogue Lightroom.

local LrFileUtils = import 'LrFileUtils'
local LrTasks = import 'LrTasks'

local M = {}

local function normaliser(chemin)
  return (chemin or ''):gsub('/', '\\'):lower()
end

-- Lit les chemins et les alias (nom/date) enregistrés. Les chemins identifient une photo tant
-- qu'elle reste au même endroit ; nom et date permettent de reconnaître une ligne Google Photos
-- si le fichier a ensuite été retiré du catalogue.
function M.lire(cheminFichier)
  local historique = { chemins = {}, entrees = {} }
  -- Le SDK lève une erreur si le fichier est absent ; ce n'est pas un historique illisible.
  if not LrFileUtils.exists(cheminFichier) then return historique end
  local contenu = LrFileUtils.readFile(cheminFichier)
  if not contenu then return historique end

  for ligne in contenu:gmatch('[^\r\n]+') do
    local type_, chemin, fichier, date = ligne:match('^([^\t]+)\t([^\t]*)\t([^\t]*)\t(.*)$')
    if chemin and ligne:sub(1, 1) ~= '#' then
      local entree = { type = type_, chemin = chemin, fichier = fichier, date = date }
      historique.chemins[normaliser(chemin)] = true
      table.insert(historique.entrees, entree)
    end
  end
  return historique
end

function M.contient(historique, chemin)
  return chemin ~= nil and historique.chemins[normaliser(chemin)] == true
end

local function ouvrirAjout(cheminFichier)
  local vide = not LrFileUtils.exists(cheminFichier)
    or (LrFileUtils.fileAttributes(cheminFichier) or {}).fileSize == 0
  local f = io.open(cheminFichier, 'ab')
  if not f then error('Impossible d’écrire l’historique des photos : ' .. cheminFichier, 0) end
  if vide then
    local ok, erreur = f:write('# type\tchemin\tfichier\tdate_prise_de_vue\r\n')
    if not ok then f:close(); error('Impossible d’écrire l’historique des photos : ' .. tostring(erreur), 0) end
  end
  return f
end

local function fermerAjout(f)
  local ok, erreur = f:close()
  if not ok then error('Impossible de terminer l’écriture de l’historique des photos : ' .. tostring(erreur), 0) end
end

-- Vérifie l'accès en écriture avant de modifier le catalogue, en créant l'en-tête si nécessaire.
function M.preparer(cheminFichier)
  M.lire(cheminFichier)
  fermerAjout(ouvrirAjout(cheminFichier))
end

-- Une copie autrefois écartée peut devenir la gardée d'une fusion manuelle. Retire uniquement ses
-- chemins de l'exclusion, sans perdre les autres lignes ni les commentaires. L'ancien fichier est
-- conservé en sauvegarde ; un échec de remplacement tente de le remettre en place.
local function filtrer(contenu, chemins)
  local voulus = {}
  for _, chemin in ipairs(chemins) do voulus[normaliser(chemin)] = true end
  local morceaux, nb, debut = {}, 0, 1
  while debut <= #contenu do
    local fin = contenu:find('[\r\n]', debut)
    local apres = fin and fin + 1 or #contenu + 1
    if fin and contenu:sub(fin, fin + 1) == '\r\n' then apres = apres + 1 end
    local ligne = contenu:sub(debut, (fin or #contenu + 1) - 1)
    local chemin = ligne:sub(1, 1) ~= '#' and ligne:match('^[^\t]+\t([^\t]*)\t') or nil
    if chemin and voulus[normaliser(chemin)] then
      nb = nb + 1
    else
      morceaux[#morceaux + 1] = contenu:sub(debut, apres - 1)
    end
    debut = apres
  end
  return table.concat(morceaux), nb
end

function M.contenu(cheminFichier)
  return LrFileUtils.exists(cheminFichier) and LrFileUtils.readFile(cheminFichier) or ''
end

-- Prépare le nouvel état en mémoire, pour l'enregistrer dans la même action annulable que le catalogue.
function M.modifier(contenu, options)
  contenu = filtrer(contenu, options.retablir or {})
  local connus, ajouts = {}, {}
  for ligne in contenu:gmatch('[^\r\n]+') do
    local chemin = ligne:sub(1, 1) ~= '#' and ligne:match('^[^\t]+\t([^\t]*)\t') or nil
    if chemin then connus[normaliser(chemin)] = true end
  end
  for _, photo in ipairs(options.photos or {}) do
    local cle = normaliser(photo.chemin)
    if photo.chemin and photo.chemin ~= '' and not connus[cle] then
      connus[cle] = true
      ajouts[#ajouts + 1] = table.concat({ options.type or 'doublon', photo.chemin, photo.fichier or '', photo.date or '' }, '\t') .. '\r\n'
    end
  end
  if #ajouts > 0 then
    if contenu == '' then contenu = '# type\tchemin\tfichier\tdate_prise_de_vue\r\n'
    elseif not contenu:match('[\r\n]$') then contenu = contenu .. '\r\n' end
    contenu = contenu .. table.concat(ajouts)
  end
  return contenu
end

-- Remplacement avec sauvegarde, partagé par la restauration et le suivi de Ctrl+Z / Rétablir.
function M.ecrire(cheminFichier, contenu)
  if LrFileUtils.exists(cheminFichier) and M.contenu(cheminFichier) == contenu then return end

  local temporaire = LrFileUtils.chooseUniqueFileName(cheminFichier .. '.tmp')
  local f = io.open(temporaire, 'wb')
  if not f then error('Impossible de préparer le rétablissement de l’historique : ' .. temporaire, 0) end
  local ok, erreur = f:write(contenu)
  if not ok then f:close(); error('Impossible de rétablir l’historique : ' .. tostring(erreur), 0) end
  fermerAjout(f)

  local sauvegarde
  if LrFileUtils.exists(cheminFichier) then
    sauvegarde = LrFileUtils.chooseUniqueFileName(cheminFichier .. '.bak')
    local deplace, resultat, detail = LrTasks.pcall(LrFileUtils.move, cheminFichier, sauvegarde)
    if not deplace or not resultat then
      error('Impossible de sauvegarder l’historique avant rétablissement : ' .. tostring(detail or resultat), 0)
    end
  end
  local deplace, resultat, detail = LrTasks.pcall(LrFileUtils.move, temporaire, cheminFichier)
  if not deplace or not resultat then
    local restaure, retour
    if sauvegarde then restaure, retour = LrTasks.pcall(LrFileUtils.move, sauvegarde, cheminFichier) end
    error('Impossible de remplacer l’historique : ' .. tostring(detail or resultat)
      .. ((restaure and retour) and ' (ancien fichier restauré).' or (' (fichier préparé conservé : ' .. temporaire .. ').')), 0)
  end
end

function M.retablir(cheminFichier, chemins)
  local contenu, nb = filtrer(M.contenu(cheminFichier), chemins)
  if nb > 0 then M.ecrire(cheminFichier, contenu) end
  return nb
end

-- Ajoute seulement les chemins nouveaux. Chaque ligne contient type, chemin, nom et date,
-- séparés par des tabulations (caractères interdits dans un nom de fichier Windows).
function M.ajouter(cheminFichier, type_, photos)
  local historique = M.lire(cheminFichier)
  local nouvelles = {}
  for _, photo in ipairs(photos) do
    local chemin = photo.chemin
    local cle = normaliser(chemin)
    if chemin and chemin ~= '' and not historique.chemins[cle] then
      historique.chemins[cle] = true
      local entree = {
        type = type_, chemin = chemin, fichier = photo.fichier or '', date = photo.date or '',
      }
      table.insert(nouvelles, entree)
      table.insert(historique.entrees, entree)
    end
  end
  if #nouvelles == 0 then return historique end

  local f = ouvrirAjout(cheminFichier)
  for _, entree in ipairs(nouvelles) do
    local ok, erreur = f:write(entree.type, '\t', entree.chemin, '\t', entree.fichier, '\t', entree.date, '\r\n')
    if not ok then f:close(); error('Impossible d’écrire l’historique des photos : ' .. tostring(erreur), 0) end
  end
  fermerAjout(f)
  return historique
end

return M
