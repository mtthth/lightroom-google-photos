-- Lecture et écriture de JSON, pour les échanges avec l'API Google Photos.
-- Pur Lua, sans appel à Lightroom, pour pouvoir être testé à part.
--
-- Les objets JSON deviennent des tables à clés, les tableaux des listes ; null devient nil.
-- À l'écriture, une table dont les clés sont 1..n devient un tableau, les autres des objets.

local M = {}

-- Écriture -------------------------------------------------------------------------------

local ECHAPPEMENTS = {
  ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
  ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
}

local function texte(s)
  local echappe = s:gsub('[%c"\\]', function(c)
    return ECHAPPEMENTS[c] or string.format('\\u%04x', c:byte())
  end)
  return '"' .. echappe .. '"'
end

local function estTableau(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n == #t
end

function M.encoder(valeur)
  local genre = type(valeur)
  if genre == 'nil' then
    return 'null'
  elseif genre == 'boolean' then
    return tostring(valeur)
  elseif genre == 'number' then
    if valeur ~= valeur or valeur == math.huge or valeur == -math.huge then
      error('nombre impossible à écrire en JSON : ' .. tostring(valeur), 0)
    end
    if valeur == math.floor(valeur) and math.abs(valeur) < 2 ^ 53 then
      return string.format('%d', valeur)
    end
    return string.format('%.17g', valeur)
  elseif genre == 'string' then
    return texte(valeur)
  elseif genre == 'table' then
    local parties = {}
    if estTableau(valeur) then
      for i, v in ipairs(valeur) do parties[i] = M.encoder(v) end
      return '[' .. table.concat(parties, ',') .. ']'
    end
    local cles = {}
    for cle in pairs(valeur) do
      if type(cle) ~= 'string' then error('clé d’objet JSON qui n’est pas un texte : ' .. tostring(cle), 0) end
      cles[#cles + 1] = cle
    end
    table.sort(cles)
    for i, cle in ipairs(cles) do parties[i] = texte(cle) .. ':' .. M.encoder(valeur[cle]) end
    return '{' .. table.concat(parties, ',') .. '}'
  end
  error('valeur impossible à écrire en JSON : ' .. genre, 0)
end

-- Lecture --------------------------------------------------------------------------------

local function erreur(pos, message)
  error(string.format('JSON invalide (caractère %d) : %s', pos, message), 0)
end

local function sauterBlancs(s, pos)
  return s:find('[^ \t\r\n]', pos) or #s + 1
end

-- Point de code Unicode → UTF-8.
local function utf8(code)
  if code < 0x80 then return string.char(code) end
  if code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
  end
  if code < 0x10000 then
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
  end
  return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
    0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local SIMPLES = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

-- pos : position du guillemet ouvrant. Renvoie le texte et la position qui suit.
local function lireTexte(s, pos)
  local morceaux = {}
  local i = pos + 1
  while true do
    local special = s:find('["\\]', i)
    if not special then erreur(pos, 'texte non terminé') end
    morceaux[#morceaux + 1] = s:sub(i, special - 1)
    if s:sub(special, special) == '"' then return table.concat(morceaux), special + 1 end

    local c = s:sub(special + 1, special + 1)
    if SIMPLES[c] then
      morceaux[#morceaux + 1] = SIMPLES[c]
      i = special + 2
    elseif c == 'u' then
      local hex = s:match('^%x%x%x%x', special + 2)
      if not hex then erreur(special, 'échappement \\u invalide') end
      local code = tonumber(hex, 16)
      i = special + 6
      -- Caractère hors du plan de base : deux échappements successifs (paire de substitution).
      local bas = code >= 0xD800 and code <= 0xDBFF and s:match('^\\u(%x%x%x%x)', i)
      if bas and tonumber(bas, 16) >= 0xDC00 and tonumber(bas, 16) <= 0xDFFF then
        code = 0x10000 + (code - 0xD800) * 0x400 + (tonumber(bas, 16) - 0xDC00)
        i = i + 6
      end
      morceaux[#morceaux + 1] = utf8(code)
    else
      erreur(special, 'échappement invalide')
    end
  end
end

local lireValeur

local function lireNombre(s, pos)
  local nombre = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
  local valeur = nombre and tonumber(nombre)
  if not valeur then erreur(pos, 'nombre invalide') end
  return valeur, pos + #nombre
end

-- Renvoie la valeur qui commence à pos (après d'éventuels blancs) et la position qui suit.
function lireValeur(s, pos)
  pos = sauterBlancs(s, pos)
  local c = s:sub(pos, pos)
  if c == '{' then
    local objet = {}
    pos = sauterBlancs(s, pos + 1)
    if s:sub(pos, pos) == '}' then return objet, pos + 1 end
    while true do
      if s:sub(pos, pos) ~= '"' then erreur(pos, 'clé attendue') end
      local cle, valeur
      cle, pos = lireTexte(s, pos)
      pos = sauterBlancs(s, pos)
      if s:sub(pos, pos) ~= ':' then erreur(pos, '« : » attendu') end
      valeur, pos = lireValeur(s, pos + 1)
      objet[cle] = valeur
      pos = sauterBlancs(s, pos)
      local suivant = s:sub(pos, pos)
      if suivant == '}' then return objet, pos + 1 end
      if suivant ~= ',' then erreur(pos, '« , » ou « } » attendu') end
      pos = sauterBlancs(s, pos + 1)
    end
  elseif c == '[' then
    local liste, n = {}, 0
    pos = sauterBlancs(s, pos + 1)
    if s:sub(pos, pos) == ']' then return liste, pos + 1 end
    while true do
      n = n + 1
      liste[n], pos = lireValeur(s, pos)
      pos = sauterBlancs(s, pos)
      local suivant = s:sub(pos, pos)
      if suivant == ']' then return liste, pos + 1 end
      if suivant ~= ',' then erreur(pos, '« , » ou « ] » attendu') end
      pos = pos + 1
    end
  elseif c == '"' then
    return lireTexte(s, pos)
  elseif c == '-' or c:match('%d') then
    return lireNombre(s, pos)
  elseif s:sub(pos, pos + 3) == 'true' then
    return true, pos + 4
  elseif s:sub(pos, pos + 4) == 'false' then
    return false, pos + 5
  elseif s:sub(pos, pos + 3) == 'null' then
    return nil, pos + 4
  end
  erreur(pos, c == '' and 'fin de texte inattendue' or 'valeur attendue')
end

function M.decoder(s)
  if type(s) ~= 'string' then error('JSON attendu, reçu : ' .. type(s), 0) end
  local valeur, pos = lireValeur(s, 1)
  if sauterBlancs(s, pos) <= #s then erreur(pos, 'texte en trop après la valeur') end
  return valeur
end

return M
