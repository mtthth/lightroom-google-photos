// Régressions du seul plugin Google Photos. Lancé par tests/lancer.mjs --mutants.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const [plugin, scratch, texlua] = process.argv.slice(2);
if (!plugin || !scratch || !texlua) throw new Error('Utiliser node tests/lancer.mjs --mutants');

const mutants = [
  ['les collections de retrait ne sont plus exclues',
    'if not brut.isVirtualCopy and not dejaIgnoree then', 'if not brut.isVirtualCopy then'],
  ['les exclusions du fichier historique sont ignorées',
    'if not dejaIgnoree and Historique.contient(historique, brut.path) then', 'if false then'],
  ['un historique non migré est accepté',
    "contenu:find('# historique-commun-deduplicate-google-v1', 1, true)", 'true'],
  ['un fichier téléchargé déjà présent est réimporté',
    'photo = photoIdentique(index, chemin)', 'photo = nil'],
];

function tester(dossierPlugin, travail) {
  fs.mkdirSync(travail, { recursive: true });
  try {
    execFileSync(texlua, [path.join(__dirname, 'test_albums.lua'), dossierPlugin, travail],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return [];
  } catch (erreur) {
    if (erreur.status == null) throw erreur;
    const sortie = (erreur.stdout ?? '') + (erreur.stderr ?? '');
    // Une panne du runtime ou du faux SDK ne constitue pas une régression détectée.
    const details = sortie.split('\n').filter((l) => l.startsWith('ÉCHEC '));
    if (!details.length) throw new Error(`Test interrompu sans assertion :\n${sortie}`);
    return details;
  }
}

const controle = tester(plugin, path.join(scratch, 'controle-mutants'));
if (controle.length) throw new Error(`Échec du témoin sans mutation : ${controle.join(' | ')}`);
console.log('ok      témoin sans mutation');
let tousDetectes = true;
for (const [i, [nom, avant, apres]] of mutants.entries()) {
  const dossier = path.join(scratch, `mutant-${i}`);
  fs.cpSync(plugin, dossier, { recursive: true });
  const fichier = path.join(dossier, 'RecreerAlbums.lua');
  const source = fs.readFileSync(fichier, 'utf8');
  if (!source.includes(avant)) throw new Error(`Motif absent : ${nom}`);
  fs.writeFileSync(fichier, source.replace(avant, () => apres));
  const erreurs = tester(dossier, path.join(scratch, `test-mutant-${i}`));
  const detecte = erreurs.length > 0;
  tousDetectes &&= detecte;
  console.log(`${detecte ? 'détecté' : 'NON DÉTECTÉ'} ${nom}${detecte ? ' : ' + erreurs[0] : ''}`);
}
process.exitCode = tousDetectes ? 0 : 1;
