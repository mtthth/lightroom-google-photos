// Casse volontairement une règle à la fois dans une copie du module et lance les suites de tests : au
// moins une doit échouer. Lancé par `node tests/lancer.mjs --mutants`, qui fournit les arguments
// (dossier du module, dossier de travail, texlua). Une règle dont la casse passe inaperçue signale un
// test manquant.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const [plugin, scratch, texlua] = process.argv.slice(2);
const mutantsDir = scratch + '/mutant/projet/albums-google-photos.lrplugin';

const mutants = [
  ['la sélection est ignorée : on prend toujours toute la grille', 'Catalogue.lua',
    "if #selection >= 2 then return { photos = selection, genre = 'selection', nom = nom } end",
    "if false then return { photos = selection, genre = 'selection', nom = nom } end"],
  ['la copie gardée ne rejoint plus les collections des copies retirées', 'Doublons.lua',
    "        if not dedans[col.id] then\n          dedans[col.id] = true\n          e.collections[#e.collections + 1] = col\n        end\n",
    "        dedans[col.id] = true\n"],
  ['les corbeilles comptent comme des collections à reprendre', 'Doublons.lua',
    'if not col.dynamique and not col.exclue then', 'if not col.dynamique then'],
  ['la note la plus haute n\'est plus reprise', 'Doublons.lua',
    "    if (c.note or 0) > note then\n      note = c.note\n      e.note = note\n    end\n", ''],
  ['le « pourquoi » ne cite plus la plus grande image', 'Doublons.lua',
    "if a.pixels ~= b.pixels then return 'la plus grande image' end", "if false then return 'la plus grande image' end"],
  ['les copies retirées ne sortent plus de leurs collections', 'FusionnerDoublons.lua',
    '  for _, q in ipairs(e.quittees) do q.collection.objet:removePhotos({ q.copie.photo }) end\n', ''],
  ['les corbeilles ne sont plus reconnues', 'FusionnerDoublons.lua',
    'dynamique = collection:isSmartCollection(), exclue = CORBEILLES[collection:getName()] or false,',
    'dynamique = collection:isSmartCollection(), exclue = false,'],
  ['les aperçus déjà écrits sont refaits à chaque rapport', 'FusionnerDoublons.lua',
    "if LrFileUtils.exists(c.cheminApercu) ~= 'file' then aFaire[#aFaire + 1] = c end", 'aFaire[#aFaire + 1] = c'],
  ['« Voir le rapport » n\'ouvre plus la page', 'FusionnerDoublons.lua',
    "if choix == 'other' then LrHttp.openUrlInBrowser(RapportHtml.urlFichier(RAPPORT_HTML)) end", ''],
  ['le rapport n\'échappe plus le HTML', 'RapportHtml.lua', "['<'] = '&lt;', ['>'] = '&gt;'", "['<'] = '<', ['>'] = '>'"],
  ['le rapport n\'est plus trié du plus ancien au plus récent', 'RapportHtml.lua',
    'if da ~= db then return da < db end', 'if da ~= db then return da > db end'],
  ['l\'adresse du rapport n\'est plus encodée', 'RapportHtml.lua', "string.format('%%%02X', x:byte())", 'x'],
  ["règle A abandonnée : le protégé tient lieu de gardé", 'Rafales.lua',
    "        if c == meilleur then\n          c.decision = 'garder'", "        if c == meilleur and #libres == #bloc then\n          c.decision = 'garder'"],
  ['les époques protègent à nouveau', 'Rafales.lua', '[Noms.ENSEMBLE_EPOQUES] = true, ', ''],
  ['le ratio choisi est ignoré', 'Rafales.lua', 'math.ceil(#rafale / (ratio or M.RATIO))', 'math.ceil(#rafale / M.RATIO)'],
  ['le numéro est la première suite de chiffres', 'Rafales.lua', 'dernier = suite', 'dernier = dernier or suite'],
  ['les numéros de fichier ne comptent plus', 'Rafales.lua', 'or math.abs(b.numero - a.numero) <= M.ECART_NUMERO', 'or true'],
  ['l\'écart de temps ne compte plus', 'Rafales.lua', 'if b.t - a.t > M.ECART_SECONDES then return false end', ''],
  ['le mot-clé n\'est plus posé', 'ReduireRafales.lua', 'for _, photo in ipairs(traitees) do photo:addKeyword(motCle) end', ''],
  ['les photos marquées ne sont plus ignorées', 'ReduireRafales.lua',
    'for id in pairs((Catalogue.photosAvecMotCle(catalogue, Rafales.MOT_CLE))) do ignorees[id] = true end', ''],
  ['le mot-clé est exporté', 'ReduireRafales.lua', 'catalogue:createKeyword(Rafales.MOT_CLE, {}, false, nil, true)',
    'catalogue:createKeyword(Rafales.MOT_CLE, {}, true, nil, true)'],
  ['les collections dynamiques protègent', 'ReduireRafales.lua', 'if not collection:isSmartCollection() then', 'if true then'],
  ['les copies virtuelles ne protègent plus', 'ReduireRafales.lua', 'if (b.countVirtualCopies or 0) > 0 then', 'if false then'],
  ['les retouches Lightroom ne protègent plus', 'ReduireRafales.lua', "if estRetouchee[f.id] then table.insert(f.raisons, 'retouches Lightroom') end", ''],
  ['la netteté n\'est plus mesurée', 'ReduireRafales.lua', 'if not magickAbsent and not mesurerNettete(rafales, progression) then return end', ''],
  ['les retouches externes ne protègent plus', 'Rafales.lua', "if f.derive then ajouter('version retouchée (éditeur externe)') end", ''],
  ['un fichier à nom de retouche (image identique) est de nouveau retiré', 'FusionnerDoublons.lua',
    'local melange = #marques > 0 and #ordinaires > 0', 'local melange = false'],
  ["DxO n'est plus un marqueur de retouche", 'Similitude.lua',
    "'%-%d%d%d%d%d%d%d%d%-dxo_', '[ _%-]dxo_' }", "'zzz' }"],
  ['le suffixe horodaté (-Modifié-2026-08-02T22-37-43) n\'est plus retiré du nom', 'Doublons.lua',
    "SUFFIXES[#SUFFIXES + 1] = marqueur .. '.*$'", "SUFFIXES[#SUFFIXES + 1] = marqueur .. '[^%-%.]*$'"],
  ['les copies en trop sont de nouveau indexées par les albums', 'RecreerAlbums.lua',
    'if not brut.isVirtualCopy and not ignorees[photo.localIdentifier] then', 'if not brut.isVirtualCopy then'],
  ["_filtered n'est plus un marqueur de retouche", 'Similitude.lua', "'[_%-]filtered',", "'zzz',"],
  ["-Modifié n'est plus un marqueur de retouche", 'Similitude.lua', "'%-modifi', ", "'%-modifier', "],
  ['les champs de texte ne sont plus recopiés', 'Doublons.lua',
    "if (textes[cle] or '') == '' and valeur ~= '' then", 'if false then'],
  ['un champ de texte déjà renseigné est écrasé', 'Doublons.lua',
    "if (textes[cle] or '') == '' and valeur ~= '' then", "if valeur ~= '' then"],
  ['la plus grande image ne passe plus en premier', 'Doublons.lua',
    "  if a.pixels ~= b.pixels then return a.pixels > b.pixels end\n  if a.octetsImage ~= b.octetsImage then return a.octetsImage > b.octetsImage end\n", ''],
  ['un nom « -Modifier » n\'est plus une retouche', 'Similitude.lua',
    "    if bas:find(marqueur) then return true end\n", ''],
  ['une copie réduite retouchée est retirée sans alerte', 'Doublons.lua',
    "  elseif travailPerdu then\n    raison = 'une copie à retirer est retouchée ou a des copies virtuelles'\n", '  elseif false then\n    raison = nil\n'],
  ['seuil de ressemblance trop large', 'Similitude.lua', 'M.ECART_MOYEN_MAX = 2.0', 'M.ECART_MOYEN_MAX = 100'],
  ['seuil sur un bloc trop large', 'Similitude.lua', 'M.ECART_BLOC_MAX = 16', 'M.ECART_BLOC_MAX = 255'],
  ['la forme n\'est plus comparée', 'Similitude.lua', 'M.TOLERANCE_FORME = 0.02', 'M.TOLERANCE_FORME = 100'],
  ['ImageMagick jamais utilisé', 'FusionnerDoublons.lua', 'local magickDispo = Vignettes.magick() ~= nil', 'local magickDispo = false'],
  ['aucune comparaison de forme (rotation)', 'Vignettes.lua', 'if ORIENTATIONS_PIVOTEES[orientation] then largeur, hauteur = hauteur, largeur end', ''],
];

const suites = [['test_doublons.lua', 'doublons'], ['test_vignettes.lua', 'vignettes'], ['test_rafales.lua', 'rafales'],
  ['test_rapport.lua', 'rapport']];
let tousDetectes = true;
for (const [nom, fichier, avant, apres] of mutants) {
  fs.rmSync(scratch + '/mutant', { recursive: true, force: true });
  fs.mkdirSync(mutantsDir, { recursive: true });
  for (const f of fs.readdirSync(plugin)) if (f.endsWith('.lua')) fs.copyFileSync(plugin + '/' + f, mutantsDir + '/' + f);
  const chemin = mutantsDir + '/' + fichier;
  const texte = fs.readFileSync(chemin, 'utf8');
  if (!texte.includes(avant)) { console.log('MOTIF ABSENT pour « ' + nom + ' »'); tousDetectes = false; continue; }
  fs.writeFileSync(chemin, texte.replace(avant, () => apres));
  const echecs = [];
  for (const [suite] of suites) {
    let sortie = '';
    try { sortie = execFileSync(texlua, [path.join(__dirname, suite), mutantsDir, scratch], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }); }
    catch (e) { sortie = (e.stdout || '') + (e.stderr || ''); }
    for (const l of sortie.split('\n')) if (l.startsWith('ÉCHEC') || /error|erreur/i.test(l) && !l.startsWith(' ')) echecs.push(l.replace(/^ÉCHEC /, ''));
  }
  const detecte = echecs.length > 0;
  if (!detecte) tousDetectes = false;
  console.log((detecte ? 'détecté     ' : 'NON DÉTECTÉ ') + nom + (detecte ? ' → ' + echecs.slice(0, 3).join(' | ') : ''));
}
fs.rmSync(scratch + '/mutant', { recursive: true, force: true });
console.log(tousDetectes ? '\nToutes les régressions sont détectées.' : '\nAu moins une régression passe inaperçue.');
