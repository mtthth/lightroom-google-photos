// Tests autonomes du plugin Albums Google Photos, sans catalogue personnel ni connexion à Google.
// node tests/lancer.mjs [--js | --mutants]
// TEXLUA permet de choisir l'exécutable texlua (MiKTeX).
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dossierTests = path.dirname(fileURLToPath(import.meta.url));
const plugin = path.resolve(dossierTests, '..', 'albums-google-photos.lrplugin');
const options = new Set(process.argv.slice(2));
if ([...options].some((o) => !['--js', '--mutants'].includes(o))
  || (options.has('--js') && options.has('--mutants'))) {
  console.error('Usage : node tests/lancer.mjs [--js | --mutants]');
  process.exit(2);
}

let echecs = 0;
function lancer(nom, executable, args) {
  try {
    const sortie = execFileSync(executable, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    console.log(`ok      ${nom}\n${sortie.trim()}`);
    return true;
  } catch (erreur) {
    echecs++;
    console.error(`ÉCHEC   ${nom}\n${erreur.stdout ?? ''}${erreur.stderr ?? ''}${erreur.code ?? ''}`);
    return false;
  }
}

// Les suites JavaScript restent exécutables sans MiKTeX.
for (const nom of ['rafales_node', 'export_albums', 'convertir_videos', 'telecharger_manquantes']) {
  lancer(nom, process.execPath, [path.join(dossierTests, `test_${nom}.mjs`)]);
}

if (!options.has('--js')) {
  const candidats = process.env.TEXLUA ? [process.env.TEXLUA] : [
    path.join(process.env.LOCALAPPDATA ?? '', 'Programs/MiKTeX/miktex/bin/x64/texlua.exe'),
    path.join(os.homedir(), 'AppData/Local/Programs/MiKTeX/miktex/bin/x64/texlua.exe'),
  ];
  const lua = candidats.find((p) => existsSync(p));
  if (!lua) {
    console.error('texlua introuvable. Installe MiKTeX ou indique son chemin dans TEXLUA. '
      + 'Pour les seuls tests JavaScript : node tests/lancer.mjs --js');
    process.exit(2);
  }
  const scratch = mkdtempSync(path.join(os.tmpdir(), 'lrgp-tests-'));
  try {
    for (const nom of ['albums', 'empreintes', 'service', 'json']) {
      const travail = path.join(scratch, nom);
      mkdirSync(travail);
      lancer(nom, lua, [path.join(dossierTests, `test_${nom}.lua`), plugin, travail]);
    }
    // Une erreur du témoin ne doit jamais passer pour une mutation détectée.
    if (options.has('--mutants') && echecs === 0) {
      lancer('mutants', process.execPath, [path.join(dossierTests, 'mutants.js'), plugin, scratch, lua]);
    }
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}
process.exitCode = echecs === 0 ? 0 : 1;
