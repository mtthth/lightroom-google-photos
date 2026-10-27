// Convertit en H.264 (MP4) les vidéos que Lightroom a refusées à l'import, pour pouvoir les importer.
//
// Usage : node convertir-videos.mjs [journal.txt]        (journal.txt par défaut)
//
// Le journal est le texte de la fenêtre « Certaines opérations d'importation n'ont pas été exécutées »
// de Lightroom, enregistré dans un fichier : les lignes qui commencent par un chemin de fichier sont
// converties. Google transcode souvent les vidéos en VP9, et les vidéos iPhone en 4K HEVC passent mal :
// Lightroom lit en revanche le H.264.
//
// Les fichiers convertis vont dans photos-albums-tous-videos-converties\, sous le même nom avec
// l'extension .mp4 (IMG_5932.MOV → IMG_5932.mp4). Les originaux ne sont pas touchés. Importe ensuite ce
// dossier dans Lightroom, puis relance le module : il retrouve les vidéos par leur nom.
// Relancer le script ne reconvertit pas ce qui l'est déjà.
//
// Demande ffmpeg : winget install Gyan.FFmpeg

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, utimesSync } from 'node:fs';
import path from 'node:path';

const DOSSIER_SORTIE = 'photos-albums-tous-videos-converties';
const CONVERSIONS_SIMULTANEES = 2;

// ffmpeg : dans le PATH, sinon dans le dossier où winget l'installe.
function trouverFfmpeg() {
  const winget = path.join(process.env.LOCALAPPDATA ?? '', 'Microsoft', 'WinGet', 'Packages');
  if (existsSync(winget)) {
    for (const paquet of readdirSync(winget).filter((n) => /ffmpeg/i.test(n))) {
      const racine = path.join(winget, paquet);
      for (const sous of readdirSync(racine)) {
        const exe = path.join(racine, sous, 'bin', 'ffmpeg.exe');
        if (existsSync(exe)) return exe;
      }
    }
  }
  return 'ffmpeg';
}

function lireJournal(chemin) {
  const texte = readFileSync(chemin, 'utf8');
  return texte.split(/\r?\n/)
    .filter((ligne) => /^\s+[A-Za-z]:\\/.test(ligne))
    .map((ligne) => ligne.trim());
}

function convertir(ffmpeg, entree, sortie) {
  return new Promise((resolve) => {
    const args = [
      '-nostdin', '-y', '-loglevel', 'error', '-i', entree,
      '-map', '0:v:0', '-map', '0:a:0?', '-map_metadata', '0',
      '-c:v', 'libx264', '-crf', '18', '-preset', 'medium', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-movflags', '+faststart', sortie,
    ];
    const processus = spawn(ffmpeg, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let erreur = '';
    processus.stderr.on('data', (d) => { erreur += d; });
    processus.on('error', (e) => resolve({ ok: false, erreur: e.message }));
    processus.on('close', (code) => resolve({ ok: code === 0, erreur: erreur.trim().split('\n').slice(-2).join(' ') }));
  });
}

async function main() {
  const journal = process.argv[2] ?? 'log.txt';
  if (!existsSync(journal)) throw new Error(`${journal} est introuvable.`);
  const ffmpeg = trouverFfmpeg();

  const fichiers = lireJournal(journal);
  const absents = fichiers.filter((f) => !existsSync(f));
  const aConvertir = fichiers.filter((f) => existsSync(f));
  console.log(`${fichiers.length} vidéos dans le journal${absents.length > 0 ? `, ${absents.length} introuvables sur le disque` : ''}.`);

  mkdirSync(DOSSIER_SORTIE, { recursive: true });
  // Deux vidéos qui ne diffèrent que par l'extension (A.MOV, A.mp4) ne doivent pas s'écraser :
  // la seconde devient A_2.mp4. L'ordre du journal étant fixe, le nom reste le même d'un passage à l'autre.
  const pris = new Set();
  const travaux = aConvertir.map((entree) => {
    const base = path.basename(entree, path.extname(entree));
    let nom = base + '.mp4';
    for (let n = 2; pris.has(nom.toLowerCase()); n++) nom = base + '_' + n + '.mp4';
    pris.add(nom.toLowerCase());
    return { entree, sortie: path.join(DOSSIER_SORTIE, nom) };
  });

  const echecs = [];
  let faits = 0, ignores = 0;
  const debut = Date.now();
  const file = [...travaux];
  await Promise.all(Array.from({ length: CONVERSIONS_SIMULTANEES }, async () => {
    while (file.length > 0) {
      const { entree, sortie } = file.shift();
      if (existsSync(sortie) && statSync(sortie).size > 0 && Math.abs(statSync(sortie).mtimeMs - statSync(entree).mtimeMs) < 2000) {
        ignores++;
      } else {
        const provisoire = sortie.replace(/\.mp4$/i, '.partiel.mp4');
        const r = await convertir(ffmpeg, entree, provisoire);
        if (r.ok) {
          // La date du fichier converti = celle de l'original : sert à reconnaître un passage déjà fait.
          const date = statSync(entree);
          utimesSync(provisoire, date.atime, date.mtime);
          renameSync(provisoire, sortie);
        } else {
          echecs.push({ entree, erreur: r.erreur });
        }
      }
      faits++;
      if (faits % 10 === 0 || faits === travaux.length) {
        const minutes = (Date.now() - debut) / 60000;
        const reste = Math.round((travaux.length - faits) * minutes / faits);
        console.log(`[${faits}/${travaux.length}] échecs : ${echecs.length}, temps restant estimé : ${reste} min`);
      }
    }
  }));

  console.log(`\n${travaux.length - echecs.length} vidéos prêtes dans ${path.resolve(DOSSIER_SORTIE)}` +
    (ignores > 0 ? ` (dont ${ignores} déjà converties)` : ''));
  if (echecs.length > 0) {
    console.log(`${echecs.length} échecs :`);
    for (const e of echecs) console.log(`  ${path.basename(e.entree)} : ${e.erreur}`);
    process.exitCode = 1;
  }
}

main().catch((erreur) => {
  console.error(`Erreur : ${erreur.message}`);
  process.exitCode = 1;
});
