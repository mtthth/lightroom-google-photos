// Télécharge depuis Google Photos les photos que le module Lightroom n'a pas retrouvées
// dans le catalogue (fichier photos-albums-<suffixe>-non-trouvees.csv, <suffixe> étant l'année
// ou « tous »).
//
// Usage : node telecharger-manquantes.mjs [année]        (sans année : « tous » ; Node 22 ou plus)
//
// À lancer après un premier passage du module Lightroom. Les photos sont téléchargées par
// Chrome (profil dédié, voir chrome.mjs), en qualité originale, dans :
//   photos-albums-<suffixe>-manquantes\
// avec un fichier telechargements.csv qui dit à quelle ligne du CSV chaque photo correspond.
// En relançant ensuite le module Lightroom, il importe ces fichiers dans le catalogue et les
// range dans les bonnes collections.
//
// Relancer le script ne retélécharge pas ce qui l'est déjà.

import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, renameSync, rmSync, unlinkSync } from 'node:fs';
import path from 'node:path';
import {
  attendre, attendreOngletPhotos, Cdp, connecterNavigateur, demarrerChrome, evaluerDansPage, fermerChrome,
} from './chrome.mjs';
import { ecrireCsv, lireCsv } from './csv.mjs';

const TELECHARGEMENTS_SIMULTANES = 3;
const DELAI_TELECHARGEMENT_MS = 5 * 60 * 1000;
const TAILLE_LOT_ADRESSES = 40;
const EXTENSIONS_VIDEO = /\.(mp4|mov|avi|mkv|m4v|3gp|webm)$/i;

const cle = (album, fichier, date) => `${album.trim()}\u0000${fichier}\u0000${date}`;

// --- Dans la page photos.google.com : adresse de téléchargement de chaque photo ----------
// Envoyée telle quelle à Chrome (voir evaluerDansPage) : elle ne doit rien utiliser d'extérieur.

async function adressesTelechargement(rpc, photos) {
  const resultats = new Array(photos.length);
  let suivant = 0;
  const travailleur = async () => {
    while (suivant < photos.length) {
      const i = suivant++;
      const { id, video } = photos[i];
      try {
        // Photo : adresse de l'original dans la fiche de l'élément. Vidéo : lien de téléchargement.
        const viaFiche = async () => (await rpc('VrseUb', [id, null, null, null, null]))?.[1];
        const viaLien = async () => (await rpc('pLFTfd', [[id], null, null]))?.[0];
        const url = video ? (await viaLien()) ?? (await viaFiche()) : (await viaFiche()) ?? (await viaLien());
        resultats[i] = { id, url: typeof url === 'string' ? url : null, erreur: url ? null : 'aucune adresse de téléchargement' };
      } catch (e) {
        resultats[i] = { id, url: null, erreur: e.message };
      }
    }
  };
  await Promise.all([travailleur(), travailleur(), travailleur(), travailleur()]);
  return resultats;
}

// --- Téléchargements par Chrome ----------------------------------------------------------

class Telechargeur {
  #navigateur;
  #entrees = new Map();   // identifiant de l'onglet → { promesse, resolve, reject, guid }
  #cibleParGuid = new Map();

  static async creer(dossier) {
    const t = new Telechargeur();
    t.#navigateur = await connecterNavigateur();
    t.#navigateur.sur('Browser.downloadWillBegin', ({ frameId, guid, suggestedFilename }) => {
      t.#entree(frameId).guid = guid;
      t.#entree(frameId).nom = suggestedFilename;
      t.#cibleParGuid.set(guid, frameId);
    });
    t.#navigateur.sur('Browser.downloadProgress', ({ guid, state, filePath }) => {
      const entree = t.#entrees.get(t.#cibleParGuid.get(guid));
      if (state === 'completed') entree?.resolve(filePath);
      else if (state === 'canceled') entree?.reject(new Error('téléchargement annulé par Chrome'));
    });
    await t.#navigateur.envoyer('Browser.setDownloadBehavior', {
      behavior: 'allowAndName',   // Chrome nomme le fichier d'après un identifiant : jamais d'écrasement
      downloadPath: path.resolve(dossier),
      eventsEnabled: true,
    });
    return t;
  }

  // Les événements de Chrome peuvent arriver avant la réponse à la création de l'onglet :
  // l'entrée est créée par le premier des deux qui en a besoin.
  #entree(idCible) {
    if (!this.#entrees.has(idCible)) {
      const entree = {};
      entree.promesse = new Promise((resolve, reject) => Object.assign(entree, { resolve, reject }));
      entree.promesse.catch(() => {});
      this.#entrees.set(idCible, entree);
    }
    return this.#entrees.get(idCible);
  }

  // Renvoie { chemin, nom } : le fichier téléchargé (nom provisoire) et le nom que Google lui donne.
  async telecharger(url) {
    const { targetId } = await this.#navigateur.envoyer('Target.createTarget', { url });
    const entree = this.#entree(targetId);
    const minuteurs = [
      setTimeout(() => { if (!entree.guid) entree.reject(new Error("Chrome n'a pas lancé le téléchargement (adresse refusée ?)")); }, 30_000),
      setTimeout(() => entree.reject(new Error('délai dépassé')), DELAI_TELECHARGEMENT_MS),
    ];
    try {
      const chemin = await entree.promesse;
      return { chemin, nom: entree.nom };
    } finally {
      minuteurs.forEach(clearTimeout);
      this.#entrees.delete(targetId);
      if (entree.guid) this.#cibleParGuid.delete(entree.guid);
      await this.#navigateur.envoyer('Target.closeTarget', { targetId }).catch(() => {});
    }
  }

  fermer() {
    this.#navigateur.fermer();
  }
}

// Empreinte du contenu d'un fichier, pour reconnaître une même photo présente dans plusieurs albums.
const empreinte = (chemin) => createHash('sha256').update(readFileSync(chemin)).digest('hex');

// Range un fichier téléchargé dans le dossier sous son nom d'origine. Si le même contenu a déjà été
// téléchargé (la photo figure dans plusieurs albums), le doublon est supprimé et le fichier existant
// est réutilisé ; si un fichier différent porte déjà ce nom, on ajoute un suffixe.
function ranger(chemin, nom, id, dossier, parEmpreinte) {
  if (/.zip$/i.test(nom ?? '')) return dezipper(chemin, id, dossier, parEmpreinte);
  const hash = empreinte(chemin);
  const existant = parEmpreinte.get(hash);
  if (existant && existsSync(existant)) {
    unlinkSync(chemin);
    return existant;
  }
  const brut = path.basename(nom || 'photo');
  const point = brut.lastIndexOf('.');
  const base = point > 0 ? brut.slice(0, point) : brut;
  const extension = point > 0 ? brut.slice(point) : '';
  let destination = path.resolve(dossier, brut);
  for (let n = 1; existsSync(destination); n++) {
    destination = path.resolve(dossier, `${base}_${id.slice(-5)}${n > 1 ? `_${n}` : ''}${extension}`);
  }
  renameSync(chemin, destination);
  parEmpreinte.set(hash, destination);
  return destination;
}

// Les Live Photos d'iPhone sont servies par Google dans un zip qui contient la photo et sa courte
// vidéo (IMG_1234.heic + IMG_1234.mov). On ne garde que la photo.
// Le tar de Windows (bsdtar) lit les zip ; celui de Git, parfois placé avant dans le PATH, non.
const TAR = path.join(process.env.SystemRoot ?? 'C:/Windows', 'System32', 'tar.exe');
const EXTENSIONS_IMAGE = /.(heic|heif|jpe?g|png|dng|tiff?|webp)$/i;

function dezipper(zip, id, dossier, parEmpreinte) {
  const provisoire = mkdtempSync(path.join(dossier, '.zip-'));
  try {
    // bsdtar refuse les chemins qui sortiraient du dossier d'extraction.
    execFileSync(TAR, ['-xf', path.resolve(zip), '-C', path.resolve(provisoire)], { stdio: 'ignore' });
    const image = readdirSync(provisoire).find((f) => EXTENSIONS_IMAGE.test(f));
    if (!image) throw new Error('le zip ne contient aucune image');
    const chemin = ranger(path.join(provisoire, image), image, id, dossier, parEmpreinte);
    unlinkSync(zip);
    return chemin;
  } finally {
    rmSync(provisoire, { recursive: true, force: true });
  }
}

// Exécute `tache` sur chaque élément, `simultanes` à la fois.
async function enParallele(elements, simultanes, tache) {
  const file = [...elements];
  await Promise.all(Array.from({ length: simultanes }, async () => {
    while (file.length > 0) await tache(file.shift());
  }));
}

// --- Programme principal -----------------------------------------------------------------

async function main() {
  const suffixe = process.argv[2] ?? 'tous';
  if (suffixe !== 'tous' && !/^[0-9]{4}$/.test(suffixe)) throw new Error(`Année invalide : ${suffixe}`);
  if (typeof WebSocket === 'undefined') throw new Error('Ce script demande Node 22 ou plus récent.');

  const fichierPhotos = `photos-albums-${suffixe}.csv`;
  const fichierManquantes = `photos-albums-${suffixe}-non-trouvees.csv`;
  for (const f of [fichierPhotos, fichierManquantes]) {
    if (!existsSync(f)) {
      throw new Error(`${f} est introuvable. Lance d'abord export-albums.mjs, puis le module Lightroom.`);
    }
  }
  const dossier = `photos-albums-${suffixe}-manquantes`;
  const fichierManifeste = path.join(dossier, 'telechargements.csv');

  // Identifiant Google de chaque ligne manquante, retrouvé dans le CSV complet.
  const idsParCle = new Map();
  // Les photos hors album sont dans un second fichier (voir export-albums.mjs), au même format.
  const sourcesIds = [fichierPhotos, ...(suffixe === 'tous' && existsSync('photos-hors-album.csv') ? ['photos-hors-album.csv'] : [])];
  for (const [album, fichier, date, id] of sourcesIds.flatMap((f) => lireCsv(f).slice(1))) {
    const k = cle(album, fichier, date);
    if (!idsParCle.has(k)) idsParCle.set(k, []);
    idsParCle.get(k).push(id);
  }
  const lignes = [];
  const dejaUtilises = new Map();
  for (const [album, fichier, date] of lireCsv(fichierManquantes).slice(1)) {
    const k = cle(album, fichier, date);
    const n = dejaUtilises.get(k) ?? 0;
    dejaUtilises.set(k, n + 1);
    const id = idsParCle.get(k)?.[n];
    if (id) lignes.push({ album, fichier, date, id });
    else console.log(`Identifiant introuvable pour « ${fichier} » (${album}), ignorée.`);
  }

  // Une même photo peut figurer dans plusieurs albums : on ne la télécharge qu'une fois.
  mkdirSync(dossier, { recursive: true });
  const fichiersParId = new Map();
  if (existsSync(fichierManifeste)) {
    for (const [, , , id, chemin] of lireCsv(fichierManifeste).slice(1)) {
      if (chemin && existsSync(chemin)) fichiersParId.set(id, chemin);
    }
  }
  // Fichiers déjà téléchargés : on retient leur contenu pour ne pas en garder deux fois le même.
  const parEmpreinte = new Map();
  for (const chemin of new Set(fichiersParId.values())) parEmpreinte.set(empreinte(chemin), chemin);
  // Zip déjà téléchargés par une version précédente du script : on en extrait la photo.
  for (const [id, chemin] of [...fichiersParId]) {
    if (!/.zip$/i.test(chemin)) continue;
    try {
      fichiersParId.set(id, dezipper(chemin, id, dossier, parEmpreinte));
      console.log(`Zip ouvert : ${path.basename(chemin)} → ${path.basename(fichiersParId.get(id))}`);
    } catch (e) {
      console.log(`Zip impossible à ouvrir (${path.basename(chemin)}) : ${e.message}`);
    }
  }
  const aTelecharger = [...new Map(lignes.map((l) => [l.id, l])).values()].filter((l) => !fichiersParId.has(l.id));
  console.log(`${lignes.length} lignes manquantes, ${new Set(lignes.map((l) => l.id)).size} photos distinctes, ` +
    `${aTelecharger.length} à télécharger.`);

  const echecs = [];
  // Le manifeste garde aussi les entrées des téléchargements précédents (photos déjà importées dans
  // Lightroom depuis ce dossier) : le module en a besoin pour les retrouver, même si elles ne figurent
  // plus dans la liste des photos introuvables.
  const ancien = existsSync(fichierManifeste) ? lireCsv(fichierManifeste).slice(1) : [];
  const cleLigne = (album, fichier, date, id) => [album.trim(), fichier, date, id].join('|');
  const ecrireManifeste = () => {
    const courantes = lignes.filter((l) => fichiersParId.has(l.id))
      .map((l) => [l.album, l.fichier, l.date, l.id, fichiersParId.get(l.id)]);
    const cles = new Set(courantes.map((r) => cleLigne(...r.slice(0, 4))));
    const conservees = ancien.filter((r) => r[4] && !cles.has(cleLigne(r[0], r[1], r[2], r[3])) && existsSync(r[4]));
    ecrireCsv(fichierManifeste, [
      ['album', 'fichier', 'date_prise_de_vue', 'id_photo', 'fichier_telecharge'],
      ...courantes, ...conservees,
    ]);
  };

  if (aTelecharger.length > 0) {
    const lanceParLeScript = await demarrerChrome();
    try {
      const onglet = await attendreOngletPhotos();
      const cdp = await Cdp.connecter(onglet.webSocketDebuggerUrl);
      const telechargeur = await Telechargeur.creer(dossier);
      console.log('Connecté à Google Photos. Les téléchargements commencent dès que les premières adresses sont trouvées.');

      // Les adresses sont cherchées par lots ; les téléchargements démarrent sans attendre la fin.
      const file = [];
      let rechercheTerminee = false;
      let adressesTrouvees = 0;
      let faits = 0;
      const debut = Date.now();

      const chercher = async () => {
        for (let i = 0; i < aTelecharger.length; i += TAILLE_LOT_ADRESSES) {
          const lot = aTelecharger.slice(i, i + TAILLE_LOT_ADRESSES);
          const adresses = await evaluerDansPage(
            cdp, adressesTelechargement,
            lot.map((l) => ({ id: l.id, video: EXTENSIONS_VIDEO.test(l.fichier) })),
          );
          lot.forEach((ligne, k) => file.push({ ligne, adresse: adresses[k] }));
          adressesTrouvees += lot.length;
        }
        rechercheTerminee = true;
      };

      const telecharger = async () => {
        for (;;) {
          const element = file.shift();
          if (!element) {
            if (rechercheTerminee) return;
            await attendre(200);
            continue;
          }
          const { ligne, adresse } = element;
          try {
            if (!adresse?.url) throw new Error(adresse?.erreur ?? 'aucune adresse de téléchargement');
            const { chemin, nom } = await telechargeur.telecharger(adresse.url);
            fichiersParId.set(ligne.id, ranger(chemin, nom, ligne.id, dossier, parEmpreinte));
          } catch (e) {
            echecs.push({ ...ligne, erreur: e.message });
          }
          faits++;
          if (faits % 25 === 0) ecrireManifeste();   // reprise possible si le script est interrompu
          if (faits % 10 === 0 || faits === aTelecharger.length) {
            const minutes = (Date.now() - debut) / 60000;
            const reste = faits < aTelecharger.length ? Math.round((aTelecharger.length - faits) * minutes / faits) : 0;
            console.log(`[${faits}/${aTelecharger.length}] adresses trouvées : ${adressesTrouvees}, échecs : ${echecs.length}, ` +
              `temps restant estimé : ${reste} min`);
          }
        }
      };

      await Promise.all([chercher(), ...Array.from({ length: TELECHARGEMENTS_SIMULTANES }, telecharger)]);
      telechargeur.fermer();
      cdp.fermer();
    } finally {
      ecrireManifeste();
      if (lanceParLeScript) await fermerChrome();
    }
  }

  ecrireManifeste();

  const nbOk = new Set(lignes.filter((l) => fichiersParId.has(l.id)).map((l) => l.id)).size;
  console.log(`\n${nbOk} photos disponibles dans ${path.resolve(dossier)}`);
  if (echecs.length > 0) {
    console.log(`${echecs.length} échecs :`);
    for (const e of echecs) console.log(`  ${e.fichier} (${e.album}) : ${e.erreur}`);
    process.exitCode = 1;
  }
}

main().catch((erreur) => {
  console.error(`Erreur : ${erreur.message}`);
  process.exitCode = 1;
});
