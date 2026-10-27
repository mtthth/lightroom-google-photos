local PLUGIN = arg[1]
package.path = PLUGIN .. '/?.lua;' .. package.path
local Json = require 'Json'

local nb, echecs = 0, 0
local function verifier(nom, obtenu, attendu)
  nb = nb + 1
  if obtenu ~= attendu then
    echecs = echecs + 1
    print('ÉCHEC ' .. nom .. '\n  obtenu  : ' .. tostring(obtenu) .. '\n  attendu : ' .. tostring(attendu))
  end
end
local function leve(nom, f)
  nb = nb + 1
  local ok, e = pcall(f)
  if ok then echecs = echecs + 1; print('ÉCHEC ' .. nom .. ' : pas d’erreur') end
end

-- Écriture
verifier('objet trié', Json.encoder({ b = 1, a = 'x' }), '{"a":"x","b":1}')
verifier('tableau', Json.encoder({ 1, 2, 3 }), '[1,2,3]')
verifier('imbriqué', Json.encoder({ album = { title = 'Été « 2025 » – Gien' } }), '{"album":{"title":"Été « 2025 » – Gien"}}')
verifier('échappements', Json.encoder('a"b\\c\nd\te\1'), '"a\\"b\\\\c\\nd\\te\\u0001"')
verifier('décimal', Json.encoder(1.5), '1.5')
verifier('booléens', Json.encoder({ true, false }), '[true,false]')
verifier('batchCreate', Json.encoder({ albumId = 'A1', newMediaItems = { { simpleMediaItem = { uploadToken = 'T', fileName = 'f.jpg' } } } }),
  '{"albumId":"A1","newMediaItems":[{"simpleMediaItem":{"fileName":"f.jpg","uploadToken":"T"}}]}')
verifier('pageToken absent', Json.encoder({ albumId = 'A', pageSize = 100, pageToken = nil }), '{"albumId":"A","pageSize":100}')

-- Lecture
local v = Json.decoder('{ "albums": [ {"id": "a1", "title": "Gien", "mediaItemsCount": "12"}, {"id":"a2","title":"\\u00c9t\\u00e9 \\ud83d\\ude00"} ], "nextPageToken": "p2" }')
verifier('liste albums', #v.albums, 2)
verifier('titre', v.albums[1].title, 'Gien')
verifier('unicode', v.albums[2].title, 'Été 😀')
verifier('page suivante', v.nextPageToken, 'p2')
v = Json.decoder('{"a": -12.5e2, "b": true, "c": false, "d": null, "e": [], "f": {}, "g": "x\\/y\\"z"}')
verifier('nombre', v.a, -1250)
verifier('true', v.b, true)
verifier('false', v.c, false)
verifier('null', v.d, nil)
verifier('tableau vide', #v.e, 0)
verifier('objet vide', next(v.f), nil)
verifier('échappements lus', v.g, 'x/y"z')
verifier('utf-8 brut', Json.decoder('"Gâteau – Noël"'), 'Gâteau – Noël')
verifier('aller-retour', Json.decoder(Json.encoder({ t = 'l\1igne\nsuite « é »' })).t, 'l\1igne\nsuite « é »')
v = Json.decoder('{"newMediaItemResults":[{"uploadToken":"T1","status":{"message":"Success"},"mediaItem":{"id":"m1","filename":"a.jpg"}},{"uploadToken":"T2","status":{"code":3,"message":"Failed: invalid"}}]}')
verifier('batch ok', v.newMediaItemResults[1].mediaItem.id, 'm1')
verifier('batch refus', v.newMediaItemResults[2].status.message, 'Failed: invalid')

leve('texte non terminé', function() Json.decoder('{"a": "b') end)
leve('virgule finale', function() Json.decoder('[1,2,]') end)
leve('texte en trop', function() Json.decoder('{} x') end)
leve('vide', function() Json.decoder('') end)
leve('nil', function() Json.decoder(nil) end)
leve('HTML', function() Json.decoder('<html>Error 502</html>') end)

print(string.format('%d vérifications, %d échecs', nb, echecs))
os.exit(echecs == 0 and 0 or 1)
