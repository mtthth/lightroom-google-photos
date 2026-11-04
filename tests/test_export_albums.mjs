import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Exécute les fonctions du script sans ouvrir Chrome ni toucher aux exports personnels.
const source = readFileSync(new URL('../export-albums.mjs', import.meta.url), 'utf8');
const fichiers = new Map();
const contexte = vm.createContext({
  console: { log() {} },
  existsSync: (f) => fichiers.has(f),
  lireCsv: (f) => fichiers.get(f),
});
vm.runInContext(source.slice(source.indexOf('async function nomsFichiers'), source.indexOf('// --- Photos hors album')), contexte);
vm.runInContext(source.slice(source.indexOf('async function extraireAlbums'), source.indexOf('// Noms de fichiers')), contexte);

const photo = (id) => [id, null, Date.UTC(2025, 0, 1), 'dedup-' + id, 0];
const listeAlbums = (nombre) => [[['id', { 72930366: [null, 'A', [], nombre] }]], null];
const rpcAlbum = (nombre, pages) => async (id, parametres) => {
  if (id === 'Z5xsfc') return listeAlbums(nombre);
  assert.equal(id, 'snAcKc');
  return pages.get(parametres[1]);
};
for (const reponse of [null, {}, [], [null], [null, {}]]) {
  await assert.rejects(contexte.extraireAlbums(rpcAlbum(2, new Map([[null, reponse]])), null, {}), /réponse|incomplet/i);
}
await assert.rejects(contexte.extraireAlbums(rpcAlbum(2, new Map([[null, [null, [photo('p1')], null]]])), null, {}), /incomplet/i);
await assert.rejects(contexte.extraireAlbums(rpcAlbum(2, new Map([[null, [null, [photo('p1'), photo('p1')], null]]])), null, {}), /doublon|répété/i);
await assert.rejects(contexte.extraireAlbums(rpcAlbum(2, new Map([
  [null, [null, [photo('p1')], 'suite']], ['suite', [null, [photo('p2')], 'suite']],
])), null, {}), /page|répété/i);
for (const reponse of [null, {}, []]) {
  await assert.rejects(contexte.extraireAlbums(async () => reponse, null, {}), /réponse/i);
  await assert.rejects(contexte.listerBibliotheque(async () => reponse), /réponse/i);
}
for (const listeVide of [[], null]) {
  const vide = await contexte.extraireAlbums(rpcAlbum(0, new Map([[null, [null, listeVide, null]]])), null, {});
  assert.equal(vide[0].photos.length, 0, 'un véritable album vide reste accepté');
}
assert.equal((await contexte.extraireAlbums(async () => [null, null], null, {})).length, 0);
assert.equal((await contexte.listerBibliotheque(async () => [null, null])).length, 0);
const complet = await contexte.extraireAlbums(rpcAlbum(2, new Map([
  [null, [null, [photo('p1')], 'suite']], ['suite', [null, [photo('p2')], null]],
])), null, {});
assert.deepEqual(Array.from(complet[0].photos, (p) => p.cle), ['p1', 'p2']);

let appels = [];
const noms = await contexte.nomsFichiers(async (_id, parametres) => {
  const cles = parametres[0][0][0].map((c) => c[0]);
  appels.push([...cles]);
  const resultats = cles.filter((cle) => cle !== 'b' || appels.length > 1)
    .map((cle) => [cle, [null, null, null, cle + '.jpg']]);
  return [[null, resultats]];
}, ['a', 'b']);
assert.equal(noms.a, 'a.jpg');
assert.equal(noms.b, 'b.jpg');
assert.deepEqual(appels, [['a', 'b'], ['b']]);

const enteteAlbums = ['album', 'nb_photos', 'cree_le', 'criteres', 'id_album', 'signature'];
const entetePhotos = ['album', 'fichier', 'date_prise_de_vue', 'id_photo', 'id_album', 'dedup'];
fichiers.set('albums-tous.csv', [enteteAlbums, ['A', '2', '', 'tous', 'id', 'sig']]);
fichiers.set('photos-albums-tous.csv', [entetePhotos, ['A', '', '', 'p1', 'id', ''], ['A', 'b.jpg', '', 'p2', 'id', '']]);
let precedent = contexte.lirePrecedent('tous');
assert.equal(precedent.signatures.id, 'sig');
assert.equal(precedent.photosParAlbum.get('id').length, 2);
assert.equal(precedent.noms.has('p1'), false);
fichiers.get('photos-albums-tous.csv').pop();
precedent = contexte.lirePrecedent('tous');
assert.equal(Object.keys(precedent.signatures).length, 0);
fichiers.set('photos-albums-tous.csv', [entetePhotos, ['A', '', '', 'p1', 'autre', '']]);
assert.equal(Object.keys(contexte.lirePrecedent('tous').signatures).length, 0);
fichiers.set('albums-tous.csv', [enteteAlbums, ['Vide', '0', '', 'tous', 'vide', 'sig']]);
fichiers.set('photos-albums-tous.csv', [entetePhotos]);
assert.equal(contexte.lirePrecedent('tous').signatures.vide, 'sig');
// Répare aussi les caches déjà empoisonnés : le compte encodé dans la signature venait de Google.
fichiers.set('albums-tous.csv', [enteteAlbums, ['A', '0', '', 'tous', 'id', 'A|2|123']]);
assert.equal(Object.keys(contexte.lirePrecedent('tous').signatures).length, 0);
fichiers.set('albums-tous.csv', [enteteAlbums, ['A', '2', '', 'tous', 'id', 'A|2|123']]);
fichiers.set('photos-albums-tous.csv', [entetePhotos, ['A', '', '', 'p1', 'id', ''], ['A', '', '', 'p1', 'id', '']]);
assert.equal(Object.keys(contexte.lirePrecedent('tous').signatures).length, 0);

// Vérifie le chemin complet : un album inchangé récupère ses noms absents au prochain export.
let resultat;
const execution = vm.createContext({
  console: { log() {} }, process: { argv: ['node', 'export-albums.mjs'] }, WebSocket: class {},
  lirePrecedent: () => ({ signatures: { id: 'sig' }, photosParAlbum: new Map([['id', [{ cle: 'p1', fichier: '' }]]]), noms: new Map() }),
  demarrerChrome: async () => false, attendreOngletPhotos: async () => ({}),
  Cdp: { connecter: async () => ({ sur() {}, envoyer: async () => {}, fermer() {} }) },
  PREFIXE_LOG: '[export]', extraireAlbums: () => {}, nomsFichiers: () => {}, listerBibliotheque: () => {},
  evaluerDansPage: async (_cdp, fonction, ...args) => {
    if (fonction === execution.extraireAlbums) return [{ cle: 'id', inchange: true, photos: [] }];
    if (fonction === execution.nomsFichiers) { assert.deepEqual([...args[0]], ['p1']); return { p1: 'retrouve.jpg' }; }
    return [];
  },
  ecrireResultats: (albums) => { resultat = albums; }, photosHorsAlbum: () => [],
  lireNomsHorsAlbum: () => new Map(), ecrireHorsAlbum() {},
});
vm.runInContext(source.slice(source.indexOf('async function main()'), source.indexOf('main().catch')), execution);
await execution.main();
assert.equal(resultat[0].photos[0].fichier, 'retrouve.jpg');

// Aucune sortie ne remplace les exports précédents si la bibliothèque échoue après les albums.
resultat = undefined;
let horsAlbumEcrit = false;
execution.ecrireHorsAlbum = () => { horsAlbumEcrit = true; };
const evaluer = execution.evaluerDansPage;
execution.evaluerDansPage = async (cdp, fonction, ...args) => {
  if (fonction === execution.listerBibliotheque) throw new Error('bibliothèque indisponible');
  return evaluer(cdp, fonction, ...args);
};
await assert.rejects(execution.main(), /bibliothèque indisponible/);
assert.equal(resultat, undefined, 'les CSV d’albums précédents sont préservés');
assert.equal(horsAlbumEcrit, false);
console.log('Export albums : réponses partielles, pagination, cache et préservation des exports OK');
