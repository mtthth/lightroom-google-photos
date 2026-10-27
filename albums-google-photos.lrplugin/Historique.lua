-- Historique persistant des photos mises de côté par le module.
-- Le fichier est volontairement lisible et peut être conservé hors du catalogue Lightroom.

local LrFileUtils = import 'LrFileUtils'

local M = {}

local function normaliser(chemin)
  return (chemin or ''):gsub('/', '\\'):lower()
end

-- Lit les chemins et les alias (nom/date) enregistrés. Les chemins identifient une photo tant
-- qu'elle reste au même endroit ; nom et date permettent de reconnaître une ligne Google Photos
-- si le fichier a ensuite été retiré du catalogue.
function M.lire(cheminFichier)
  local historique = { chemins = {}, entrees = {} }
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

  local f = io.open(cheminFichier, 'ab')
  if not f then error('Impossible d’écrire l’historique des photos : ' .. cheminFichier, 0) end
  if not LrFileUtils.exists(cheminFichier) or (LrFileUtils.fileAttributes(cheminFichier) or {}).fileSize == 0 then
    local ok, erreur = f:write('# type\tchemin\tfichier\tdate_prise_de_vue\r\n')
    if not ok then f:close(); error('Impossible d’écrire l’historique des photos : ' .. tostring(erreur), 0) end
  end
  for _, entree in ipairs(nouvelles) do
    local ok, erreur = f:write(entree.type, '\t', entree.chemin, '\t', entree.fichier, '\t', entree.date, '\r\n')
    if not ok then f:close(); error('Impossible d’écrire l’historique des photos : ' .. tostring(erreur), 0) end
  end
  local ok, erreur = f:close()
  if not ok then error('Impossible de terminer l’écriture de l’historique des photos : ' .. tostring(erreur), 0) end
  return historique
end

return M
