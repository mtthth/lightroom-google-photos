-- Calcul en parallèle : un appel à ImageMagick (LrTasks.execute) n'attend que sa propre tâche, les
-- autres avancent pendant ce temps. Sert à « Fusionner les doublons » (miniatures) et à
-- « Réduire les rafales » (netteté).

local LrTasks = import 'LrTasks'

local M = {}

-- Applique fonction(lot, debut, fin) à des lots de `taille` éléments ; s'arrête si elle renvoie false
-- (et renvoie alors false).
function M.parLots(elements, taille, fonction)
  for debut = 1, #elements, taille do
    local fin = math.min(debut + taille - 1, #elements)
    local lot = {}
    for i = debut, fin do lot[#lot + 1] = elements[i] end
    if fonction(lot, debut, fin) == false then return false end
  end
  return true
end

-- Exécute tache(element) pour chaque élément, `nb` à la fois, en affichant l'avancement
-- (legende : « … %d / %d »). Une erreur dans tache est ignorée pour cet élément. Renvoie false si
-- l'utilisateur annule.
function M.pourChaque(elements, nb, tache, progression, legende)
  local suivant, fait, actives = 1, 0, nb
  for _ = 1, nb do
    LrTasks.startAsyncTask(function()
      LrTasks.pcall(function()
        while not progression:isCanceled() do
          local i = suivant
          suivant = suivant + 1
          if i > #elements then break end
          LrTasks.pcall(tache, elements[i])
          fait = fait + 1
        end
      end)
      actives = actives - 1
    end)
  end
  while actives > 0 do
    progression:setCaption(string.format(legende, fait, #elements))
    progression:setPortionComplete(fait, #elements)
    LrTasks.sleep(0.25)
  end
  return not progression:isCanceled()
end

return M
