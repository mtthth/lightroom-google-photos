-- Collections dont les photos doivent rester exclues des albums Google Photos.

local LrTasks = import 'LrTasks'

local M = {}

function M.photosDesCollections(catalogue, noms)
  local voulus = {}
  for _, nom in ipairs(noms) do voulus[nom] = true end
  local ids, nb = {}, 0
  LrTasks.pcall(function()
    for _, collection in ipairs(catalogue:getChildCollections()) do
      if voulus[collection:getName()] then
        for _, photo in ipairs(collection:getPhotos()) do
          if not ids[photo.localIdentifier] then nb = nb + 1 end
          ids[photo.localIdentifier] = true
        end
      end
    end
  end)
  return ids, nb
end

return M
