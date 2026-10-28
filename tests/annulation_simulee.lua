-- Faux Undo Lightroom : conserve les identités des photos/collections et distingue les propriétés
-- écrites dans une action normale de celles mises à jour hors de la pile Undo par un accès privé.
local M = {}

local function copier(t)
  local r = {}; for k, v in pairs(t) do r[k] = v end; return r
end

local function capturer(racines)
  local etat = {}
  local function voir(t)
    if type(t) ~= 'table' or etat[t] then return end
    etat[t] = copier(t)
    for k, v in pairs(t) do voir(k); voir(v) end
  end
  for _, racine in ipairs(racines) do voir(racine) end
  return etat
end

local function restaurer(etat)
  for t, valeurs in pairs(etat) do
    for k in pairs(t) do t[k] = nil end
    for k, v in pairs(valeurs) do t[k] = v end
  end
end

function M.brancher(catalogue, racines)
  local proprietes, annulations, retablissements = {}, {}, {}
  function catalogue:getPropertyForPlugin(_, cle) return proprietes[cle] end
  function catalogue:setPropertyForPlugin(_, cle, valeur) proprietes[cle] = valeur end
  function catalogue:withPrivateWriteAccessDo(f) f(); return 'executed' end
  local ecrire = catalogue.withWriteAccessDo
  function catalogue:withWriteAccessDo(titre, f, options)
    local avant, proprietesAvant = capturer(racines()), copier(proprietes)
    local ok, erreur = pcall(ecrire, self, titre, f, options)
    if not ok then
      restaurer(avant)
      proprietes = proprietesAvant
      error(erreur, 0)
    end
    local modifications, vues = {}, {}
    for cle in pairs(proprietesAvant) do vues[cle] = true end
    for cle in pairs(proprietes) do vues[cle] = true end
    for cle in pairs(vues) do
      if proprietesAvant[cle] ~= proprietes[cle] then
        modifications[#modifications + 1] = { cle = cle, avant = proprietesAvant[cle], apres = proprietes[cle] }
      end
    end
    annulations[#annulations + 1] = {
      titre = titre, avant = avant, apres = capturer(racines()), proprietes = modifications,
    }
    retablissements = {}
    return 'executed'
  end
  local function appliquer(source, destination, sens)
    local action = table.remove(source)
    assert(action, 'aucune action à ' .. sens)
    restaurer(action[sens])
    for _, p in ipairs(action.proprietes) do proprietes[p.cle] = p[sens] end
    destination[#destination + 1] = action
  end
  function catalogue:annuler() appliquer(annulations, retablissements, 'avant') end
  function catalogue:retablir() appliquer(retablissements, annulations, 'apres') end
  function catalogue:nombreActions() return #annulations end
  function catalogue:derniereAction() return annulations[#annulations] and annulations[#annulations].titre end
end

return M
