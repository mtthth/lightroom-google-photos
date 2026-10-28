-- Écriture des rapports CSV : séparateur « ; », guillemets si besoin, UTF-8 avec BOM (le format
-- qu'Excel en français ouvre correctement).

local M = {}

-- lignes : liste de listes de valeurs. Lève une erreur si le fichier est impossible à écrire
-- (souvent : il est ouvert dans Excel).
function M.ecrire(chemin, lignes)
  local f = io.open(chemin, 'wb')
  if not f then error('Impossible d’écrire ' .. chemin .. ' (fichier ouvert dans Excel ?)', 0) end
  f:write('\239\187\191')
  for _, ligne in ipairs(lignes) do
    local cellules = {}
    for j, valeur in ipairs(ligne) do
      valeur = tostring(valeur)
      if valeur:find('[;"\r\n]') then valeur = '"' .. valeur:gsub('"', '""') .. '"' end
      cellules[j] = valeur
    end
    f:write(table.concat(cellules, ';'), '\r\n')
  end
  f:close()
end

return M
