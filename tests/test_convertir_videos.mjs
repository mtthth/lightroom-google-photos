import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';

const source = readFileSync(new URL('../convertir-videos.mjs', import.meta.url), 'utf8');
const sortie = 'photos-albums-tous-videos-converties';
const a = 'D:\\appareil-1\\A.MOV', b = 'D:\\appareil-2\\A.MOV';

function environnement() {
  const fichiers = new Map(), conversions = [];
  const cle = (p) => path.win32.resolve(p).toLowerCase();
  const ajouter = (p, contenu, date = 10000) => fichiers.set(cle(p), {
    contenu, size: Buffer.byteLength(contenu), mtimeMs: date, atime: new Date(date), mtime: new Date(date),
  });
  let uuid = 0;
  const ctx = vm.createContext({
    console: { log() {} }, process: { argv: ['node', 'convertir-videos.mjs'], env: {} }, path: path.win32,
    randomUUID: () => String(++uuid),
    existsSync: (p) => fichiers.has(cle(p)), mkdirSync() {},
    readdirSync: (p) => [...fichiers.keys()].filter((f) => path.win32.dirname(f) === cle(p)).map((f) => path.win32.basename(f)),
    readFileSync: (p) => { assert.ok(fichiers.has(cle(p)), `fichier absent : ${p}`); return fichiers.get(cle(p)).contenu; },
    writeFileSync: (p, texte) => ajouter(p, texte), statSync: (p) => fichiers.get(cle(p)),
    unlinkSync: (p) => fichiers.delete(cle(p)),
    renameSync: (src, dst) => { fichiers.set(cle(dst), fichiers.get(cle(src))); fichiers.delete(cle(src)); },
    utimesSync: (p, atime, mtime) => Object.assign(fichiers.get(cle(p)), { atime, mtime, mtimeMs: mtime.getTime() }),
  });
  vm.runInContext(source.slice(source.indexOf('const DOSSIER_SORTIE'), source.indexOf('main().catch')), ctx);
  ctx.trouverFfmpeg = () => 'ffmpeg';
  ctx.convertir = async (_, entree, dest) => {
    conversions.push([entree, dest]); ajouter(dest, fichiers.get(cle(entree)).contenu); return { ok: true };
  };
  return {
    ajouter, fichiers, conversions, ctx, cle,
    lire: (nom) => fichiers.get(cle(path.win32.join(sortie, nom)))?.contenu,
    lancer: async (entrees) => { ajouter('log.txt', entrees.map((p) => '  ' + p).join('\r\n')); await ctx.main(); },
  };
}

const e = environnement();
e.ajouter(a, 'video-1', 10000); e.ajouter(b, 'video-2', 20000);
await e.lancer([a, b]);
assert.equal(e.lire('A.mp4'), 'video-1'); assert.equal(e.lire('A_2.mp4'), 'video-2');
await e.lancer([b]);
assert.equal(e.lire('A.mp4'), 'video-1', 'un journal réduit ne remplace pas la conversion d’une autre source');
await e.lancer([b, a, b]);
assert.equal(e.conversions.length, 2, 'ordre et répétitions du journal ne changent pas les destinations');
e.ajouter(b, 'video-2-modifiee', 20000);
await e.lancer([b]);
assert.equal(e.lire('A.mp4'), 'video-1');
assert.equal(e.lire('A_2.mp4'), 'video-2-modifiee', 'la taille source est vérifiée même si sa date ne change pas');

const ancien = environnement();
ancien.ajouter(a, 'nouvelle-video');
ancien.ajouter(path.win32.join(sortie, 'A.mp4'), 'ancienne-conversion');
await ancien.lancer([a]);
assert.equal(ancien.lire('A.mp4'), 'ancienne-conversion', 'une sortie sans manifeste ne doit jamais être écrasée');
assert.equal(ancien.lire('A_2.mp4'), 'nouvelle-video');

// Vérifie aussi le remplacement atomique du manifeste et la reprise sur le vrai système
// de fichiers, avec une conversion simulée ; aucun média personnel ni ffmpeg n'est utilisé.
const travail = fs.mkdtempSync(path.join(os.tmpdir(), 'lrgp-conversions-'));
const dossierInitial = process.cwd();
try {
  process.chdir(travail);
  const fichiers = ['source-1/A.MOV', 'source-2/A.MOV'].map((p) => path.resolve(p));
  for (const [i, p] of fichiers.entries()) {
    fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, 'video-' + i);
  }
  const reel = vm.createContext({ ...fs, path, randomUUID, console: { log() {} }, process: { argv: ['node', 'script'], env: {} } });
  vm.runInContext(source.slice(source.indexOf('const DOSSIER_SORTIE'), source.indexOf('main().catch')), reel);
  reel.trouverFfmpeg = () => 'ffmpeg';
  let appels = 0;
  reel.convertir = async (_, src, dest) => { appels++; fs.copyFileSync(src, dest); return { ok: true }; };
  fs.writeFileSync('log.txt', fichiers.map((p) => '  ' + p).join('\r\n'));
  await reel.main();
  fs.writeFileSync('log.txt', '  ' + fichiers[1]);
  await reel.main();
  assert.equal(appels, 2, 'le manifeste écrit sur disque permet de reprendre sans reconvertir');
  assert.equal(fs.readFileSync(path.join(sortie, 'A.mp4'), 'utf8'), 'video-0');
  assert.equal(fs.readFileSync(path.join(sortie, 'A_2.mp4'), 'utf8'), 'video-1');
  assert.equal(JSON.parse(fs.readFileSync(path.join(sortie, 'conversions.json'), 'utf8')).conversions.length, 2);
} finally {
  process.chdir(dossierInitial);
  fs.rmSync(travail, { recursive: true, force: true });
}
console.log('Conversions : destinations persistantes, reprise et anciens fichiers préservés OK');
