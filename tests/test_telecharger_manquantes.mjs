import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const source = readFileSync(new URL('../telecharger-manquantes.mjs', import.meta.url), 'utf8');

async function scenario(panne, lanceParScript = false) {
  let connexionsFermees = 0, telechargeursFermes = 0, chromeFerme = 0, attentes = 0, sauvegardes = 0;
  let actif = 0;
  const cdp = { fermer() { connexionsFermees++; } };
  const ctx = vm.createContext({
    process: { argv: ['node', 'telecharger-manquantes.mjs'] }, WebSocket: class {}, console: { log() {} }, path,
    TELECHARGEMENTS_SIMULTANES: 3, TAILLE_LOT_ADRESSES: 40, EXTENSIONS_VIDEO: /mp4$/,
    cle: (...v) => v.join('\0'), empreinte() {}, mkdirSync() {}, adressesTelechargement() {},
    existsSync: (f) => ['photos-albums-tous.csv', 'photos-albums-tous-non-trouvees.csv'].includes(f),
    lireCsv: () => [['album', 'fichier', 'date', 'id'], ['A', 'a.jpg', '', 'p1']],
    ecrireCsv: () => { sauvegardes++; },
    demarrerChrome: async () => lanceParScript, fermerChrome: async () => { chromeFerme++; },
    attendreOngletPhotos: async () => ({}), Cdp: { connecter: async () => cdp },
    Telechargeur: { creer: async () => {
      if (panne === 'initialisation') throw new Error('initialisation refusée');
      return {
        fermer() { telechargeursFermes++; },
        telecharger: async () => { actif++; await Promise.resolve(); actif--; return { chemin: 'tmp', nom: 'a.jpg' }; },
      };
    } },
    evaluerDansPage: async () => {
      if (panne === 'recherche') throw new Error('recherche refusée');
      return [{ url: 'https://exemple.test/photo' }];
    },
    ranger: () => 'photo.jpg',
    attendre: async () => {
      attentes++;
      // Borne la reproduction de l'ancien bug sans laisser de vrais minuteurs en vie.
      if (attentes > 6) throw new Error('travailleur encore actif');
      await Promise.resolve();
    },
  });
  vm.runInContext(source.slice(source.indexOf('async function main()'), source.indexOf('main().catch')), ctx);
  if (panne) await assert.rejects(ctx.main(), new RegExp(panne));
  else await ctx.main();
  const aLaFin = attentes;
  for (let i = 0; i < 10; i++) await Promise.resolve();
  assert.equal(attentes, aLaFin, 'aucun travailleur ne continue après le retour');
  assert.equal(actif, 0);
  assert.equal(connexionsFermees, 1, 'la connexion à l’onglet est fermée même sur erreur');
  assert.equal(telechargeursFermes, panne === 'initialisation' ? 0 : 1);
  assert.equal(chromeFerme, lanceParScript ? 1 : 0, 'seul le Chrome démarré par le script est fermé');
  assert.ok(sauvegardes > 0, 'le manifeste de reprise est conservé');
}

await scenario('recherche');
await scenario('recherche', true);
await scenario('initialisation');
await scenario(null);

// Le vrai téléchargeur doit aussi interrompre les promesses en cours et leurs minuteurs.
async function verifierFermeture(pendantCreation = false, panneInitialisation = false) {
  let fermetures = 0, creation;
  const minuteurs = new Set();
  const contexte = vm.createContext({
    path, DELAI_TELECHARGEMENT_MS: 300000,
    setTimeout: (f) => { minuteurs.add(f); return f; }, clearTimeout: (f) => minuteurs.delete(f),
    connecterNavigateur: async () => ({
      sur() {}, fermer() { fermetures++; },
      envoyer: async (methode) => {
        if (methode === 'Browser.setDownloadBehavior' && panneInitialisation) throw new Error('initialisation refusée');
        if (methode === 'Target.createTarget') {
          if (pendantCreation) return new Promise((resolve) => { creation = resolve; });
          return { targetId: 'cible' };
        }
        return {};
      },
    }),
  });
  vm.runInContext(source.slice(source.indexOf('class Telechargeur'), source.indexOf('// Empreinte du contenu'))
    + '\nglobalThis.Telechargeur = Telechargeur;', contexte);
  if (panneInitialisation) {
    await assert.rejects(contexte.Telechargeur.creer('tmp'), /initialisation/);
  } else {
    const t = await contexte.Telechargeur.creer('tmp');
    const resultat = t.telecharger('https://exemple.test/photo');
    for (let i = 0; i < 4; i++) await Promise.resolve();
    t.fermer(); t.fermer();
    if (creation) creation({ targetId: 'cible' });
    await assert.rejects(resultat, /arrêtés/);
    await assert.rejects(t.telecharger('https://exemple.test/photo'), /arrêtés/);
  }
  assert.equal(minuteurs.size, 0, 'la fermeture ne laisse aucun minuteur actif');
  assert.equal(fermetures, 1, 'la fermeture est idempotente, y compris sur échec d’initialisation');
}
await verifierFermeture();
await verifierFermeture(true);
await verifierFermeture(false, true);
console.log('Téléchargements : arrêt des travailleurs et transferts, fermeture et manifeste sur erreur OK');
