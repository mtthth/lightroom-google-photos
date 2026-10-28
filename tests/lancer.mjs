// Lance les tests des deux modules Lightroom hors de Lightroom.
//
// Usage : node tests/lancer.mjs [--mutants]        (à lancer depuis le dossier du projet)
//
// Les tests tournent avec texlua, le Lua 5.3 de MiKTeX (Lightroom embarque Lua 5.1 : le code du module
// évite ce qui diffère), contre un faux Lightroom (des tables qui imitent les fonctions du SDK) et le
// vrai ImageMagick pour les images. Chemin de texlua : variable TEXLUA, sinon l'installation MiKTeX
// de l'utilisateur.
//
// Suites : doublons (fusion), vignettes (copies réduites, netteté, ImageMagick réel), rapport (page HTML
// des doublons, aperçus), rafales, service (export vers Google Photos), json.
// Complément JavaScript : règles du rapport des rafales à blanc, sans catalogue personnel.
// --mutants : casse ensuite une règle à la fois dans une copie du module et vérifie que les tests
// échouent (environ 3 minutes).

import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dossierTests = path.dirname(fileURLToPath(import.meta.url));
const googlePlugin = path.resolve(dossierTests, '..', 'albums-google-photos.lrplugin');
const deduplicatePlugin = path.resolve(dossierTests, '..', 'lightroom-deduplicate');
const lua = process.env.TEXLUA ?? path.join(process.env.LOCALAPPDATA ?? '', 'Programs/MiKTeX/miktex/bin/x64/texlua.exe');
if (!existsSync(lua)) {
  console.error(`texlua introuvable (${lua}). Installe MiKTeX ou indique son chemin dans la variable TEXLUA.`);
  process.exit(2);
}

const scratch = mkdtempSync(path.join(os.tmpdir(), 'lrgp-tests-'));
const suites = ['doublons', 'empreintes', 'vignettes', 'rapport', 'rafales', 'service', 'json'];
const pluginParSuite = {
  doublons: deduplicatePlugin, empreintes: deduplicatePlugin, vignettes: deduplicatePlugin,
  rapport: deduplicatePlugin, rafales: deduplicatePlugin, service: googlePlugin, json: googlePlugin,
};
let echecs = 0;
try {
  for (const suite of suites) {
    let sortie = '';
    let ok = true;
    try {
      sortie = execFileSync(lua, [path.join(dossierTests, `test_${suite}.lua`), pluginParSuite[suite], scratch,
        ...(suite === 'doublons' ? [googlePlugin] : [])], { encoding: 'utf8' });
    } catch (erreur) {
      ok = false;
      sortie = (erreur.stdout ?? '') + (erreur.stderr ?? '');
    }
    const lignes = sortie.split('\n').map((l) => l.trimEnd()).filter(Boolean);
    const bilan = lignes.findLast((l) => /vérifications/.test(l)) ?? lignes.at(-1) ?? '(aucune sortie)';
    console.log(`${ok ? 'ok     ' : 'ÉCHEC  '} ${suite.padEnd(10)} ${bilan}`);
    if (!ok) {
      echecs++;
      for (const l of lignes.filter((x) => !/vérifications/.test(x)).slice(0, 12)) console.log('         ' + l);
    }
  }
  try {
    const sortie = execFileSync(process.execPath, [path.join(dossierTests, 'test_rafales_node.mjs')], { encoding: 'utf8' });
    console.log('ok      rafales JS ' + sortie.trim());
  } catch (erreur) {
    echecs++;
    console.log('ÉCHEC   rafales JS\n' + (erreur.stdout ?? '') + (erreur.stderr ?? ''));
  }
  if (process.argv.includes('--mutants')) {
    try {
      console.log(execFileSync('node', [path.join(dossierTests, 'mutants.js'), deduplicatePlugin, scratch, lua, googlePlugin], { encoding: 'utf8' }));
    } catch (erreur) {
      echecs++;
      console.log((erreur.stdout ?? '') + (erreur.stderr ?? ''));
    }
  }
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
process.exit(echecs === 0 ? 0 : 1);
