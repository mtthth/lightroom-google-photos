-- Langue de l'interface : réglage « langue » du module, 'fr' (par défaut) ou 'en'.
-- Chaque texte affiché passe par t(français, anglais), évalué au moment de l'affichage : un changement de
-- réglage vaut pour la commande suivante. Les données (noms des collections créées dans le catalogue,
-- fichiers CSV, historique) ne dépendent pas de la langue.
local M = {}
M.LANGUES = { { code = 'fr', nom = 'Français' }, { code = 'en', nom = 'English' } }

local forcee
-- Pour les tests : impose une langue (nil pour revenir au réglage).
function M.forcer(code) forcee = code end

function M.code()
  if forcee then return forcee end
  local ok, langue = pcall(function() return import('LrPrefs').prefsForPlugin().langue end)
  return (ok and langue == 'en') and 'en' or 'fr'
end

function M.anglais() return M.code() == 'en' end

-- Texte dans la langue choisie ; le français sert si la traduction manque.
function M.t(fr, en)
  if en ~= nil and M.code() == 'en' then return en end
  return fr
end

return M
