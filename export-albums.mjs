// Exporte la liste des albums Google Photos et des photos qu'ils contiennent, sans passer par
// Takeout.
//
// Usage : node export-albums.mjs [année]        (Node 22 ou plus)
//   sans année : tous les albums du compte, en mode incrémental (voir plus bas) ;
//   avec une année : seulement les albums qui remplissent au moins un de ces critères :
//     - ils ont été créés pendant l'année ;
//     - ils contiennent au moins une photo prise pendant l'année ;
//     - leur titre contient l'année.
//
// Le script ouvre Chrome avec un profil dédié. La première fois, connecte-toi à ton compte
// Google dans la fenêtre qui s'ouvre : la session est ensuite conservée dans ce profil.
// Il interroge photos.google.com avec les mêmes requêtes internes que le site. Ces requêtes
// ne sont pas documentées : le script peut cesser de marcher si Google modifie son site.
//
// Mode incrémental (sans année) : le script relit le fichier produit la fois précédente et ne
// recharge que les albums nouveaux ou modifiés (titre, nombre de photos ou date de modification
// différents). Les autres sont repris tels quels. Pour tout refaire, supprime
// photos-albums-tous.csv avant de le lancer.
//
// Fichiers produits dans le dossier courant (<suffixe> : l'année, ou « tous ») :
//   albums-<suffixe>.csv          un album par ligne
//   photos-albums-<suffixe>.csv   une photo par ligne (album, fichier, date de prise de vue)
//   photos-hors-album.csv         (sans année seulement) les photos de la bibliothèque qui ne sont
//                                 dans aucun album, au même format

import { existsSync } from 'node:fs';
import path from 'node:path';
import { attendreOngletPhotos, Cdp, demarrerChrome, evaluerDansPage, fermerChrome } from './chrome.mjs';
import { ecrireCsv, lireCsv } from './csv.mjs';

const PREFIXE_LOG = '[export]';

// --- Extraction, exécutée dans la page photos.google.com ---------------------------------
// Ces fonctions sont envoyées telles quelles à Chrome (voir evaluerDansPage) : elles ne doivent
// rien utiliser d'extérieur. rpc est la requête interne du site, fournie par chrome.mjs.

// precedent : { identifiant d'album → signature } de l'export précédent (mode incrémental).
async function extraireAlbums(rpc, annee, precedent) {
  const log = (...msg) => console.log('[export]', ...msg);

  log('Lecture de la liste des albums…');
  const albums = [];
  const pagesVues = new Set();
  const albumsVus = new Set();
  let page = null;
  do {
    const rep = await rpc('Z5xsfc', [page, null, null, null, 1, null, null, 100, [2], 5]);
    if (!Array.isArray(rep) || !(Array.isArray(rep[0]) || rep[0] === null)) {
      throw new Error('Réponse invalide à la lecture de la liste des albums. Export précédent conservé.');
    }
    for (const a of rep[0] ?? []) {
      if (!Array.isArray(a) || typeof a[0] !== 'string' || !a[0] || !Array.isArray(a.at(-1)?.[72930366])) {
        throw new Error('Réponse invalide : album sans identifiant ou métadonnées.');
      }
      if (albumsVus.has(a[0])) throw new Error('Album répété dans la liste de Google Photos.');
      albumsVus.add(a[0]);
      const info = a.at(-1)[72930366];
      const dates = info[2] ?? [];
      const titre = info[1] || '(sans titre)';
      albums.push({
        cle: a[0],
        titre,
        creation: dates[4] ?? null,
        premierePhoto: dates[0] ?? dates[5]?.[0] ?? null,
        dernierePhoto: dates[1] ?? dates[6]?.[0] ?? null,
        cleAcces: info[5] ?? null,
        nombrePhotos: Number.isSafeInteger(info[3]) && info[3] >= 0 ? info[3] : null,
        // Change quand l'album est renommé, qu'on y ajoute ou retire des photos, ou qu'il est modifié.
        signature: [titre, info[3] ?? '', dates[9] ?? ''].join('|'),
      });
    }
    page = rep?.[1];
    if (page && pagesVues.has(page)) throw new Error('Page répétée dans la liste des albums.');
    if (page) pagesVues.add(page);
  } while (page);
  log(`${albums.length} albums dans le compte.`);

  // Sans année, on ouvre tous les albums. Avec une année, on ouvre ceux qui remplissent déjà un
  // critère, et ceux dont les photos couvrent une période qui chevauche l'année (à un jour près,
  // pour les fuseaux horaires).
  const tous = annee === null;
  const unJour = 24 * 3600 * 1000;
  const debut = tous ? 0 : Date.UTC(annee, 0, 1) - unJour;
  const fin = tous ? 0 : Date.UTC(annee + 1, 0, 1) + unJour;
  const aOuvrir = albums.filter((a) => {
    a.criteres = [];
    if (tous) return true;
    if (a.titre.includes(String(annee))) a.criteres.push('titre');
    if (a.creation && new Date(a.creation).getFullYear() === annee) a.criteres.push('créé');
    const periodeInconnue = a.premierePhoto === null || a.dernierePhoto === null;
    return a.criteres.length > 0 || periodeInconnue || (a.premierePhoto < fin && a.dernierePhoto >= debut);
  });
  const inchanges = tous ? aOuvrir.filter((a) => precedent[a.cle] === a.signature).length : 0;
  log(`${aOuvrir.length} albums à examiner${inchanges > 0 ? `, dont ${inchanges} inchangés depuis le dernier export` : ''}.`);

  const retenus = [];
  let relus = 0;
  for (const [i, album] of aOuvrir.entries()) {
    if (tous && precedent[album.cle] === album.signature) {
      retenus.push({ ...album, criteres: ['tous'], inchange: true, photos: [] });
      continue;
    }
    relus++;
    const photos = [];
    const photosVues = new Set();
    const pagesAlbumVues = new Set();
    let pageAlbum = null;
    do {
      const rep = await rpc('snAcKc', [album.cle, pageAlbum, null, album.cleAcces]);
      if (!Array.isArray(rep) || !(Array.isArray(rep[1])
        || (rep[1] === null && album.nombrePhotos === 0 && !pageAlbum))) {
        throw new Error(`Réponse invalide pour l'album « ${album.titre} ». Export précédent conservé.`);
      }
      for (const p of rep[1] ?? []) {
        if (!Array.isArray(p) || typeof p[0] !== 'string' || !p[0]) {
          throw new Error(`Réponse invalide : photo sans identifiant dans « ${album.titre} ».`);
        }
        if (photosVues.has(p[0])) throw new Error(`Photo répétée dans l'album « ${album.titre} ».`);
        photosVues.add(p[0]);
        // Heure locale de la prise de vue : horodatage UTC + décalage du fuseau.
        const local = new Date(p[2] + (p[4] ?? 0));
        photos.push({
          cle: p[0],
          dedup: p[3],   // empreinte du contenu : la même pour une photo présente dans plusieurs albums
          date: local.toISOString().slice(0, 19).replace('T', ' '),
          annee: local.getUTCFullYear(),
        });
      }
      pageAlbum = rep?.[2];
      if (pageAlbum && pagesAlbumVues.has(pageAlbum)) throw new Error(`Page répétée dans l'album « ${album.titre} ».`);
      if (pageAlbum) pagesAlbumVues.add(pageAlbum);
    } while (pageAlbum);
    if (album.nombrePhotos !== null && photos.length !== album.nombrePhotos) {
      throw new Error(`Album « ${album.titre} » incomplet : ${photos.length} photos reçues, `
        + `${album.nombrePhotos} annoncées. Relance l'export ; les fichiers précédents sont conservés.`);
    }

    if (tous) album.criteres.push('tous');
    else if (photos.some((p) => p.annee === annee)) album.criteres.push('photos');
    if (album.criteres.length > 0) {
      retenus.push({ ...album, photos });
      log(`[${i + 1}/${aOuvrir.length}] ${album.titre} : ${photos.length} photos${tous ? '' : ` (${album.criteres.join(', ')})`}`);
    }
  }
  if (tous) log(`${relus} albums relus, ${inchanges} repris de l'export précédent.`);

  return retenus.map((a) => ({
    titre: a.titre,
    cle: a.cle,
    criteres: a.criteres,
    creeLe: a.creation ? new Date(a.creation).toLocaleDateString('sv-SE') : '',
    signature: a.signature,
    inchange: a.inchange === true,
    photos: a.photos.map((p) => ({ date: p.date, cle: p.cle, dedup: p.dedup })),
  }));
}

// Toute la bibliothèque (photos et vidéos, archivées comprises, corbeille exclue) : une ligne par
// photo, sous forme compacte [identifiant, empreinte du contenu, horodatage, décalage du fuseau].
async function listerBibliotheque(rpc) {
  const log = (...msg) => console.log('[export]', ...msg);
  const photos = [];
  const pagesVues = new Set();
  let page = null;
  do {
    const rep = await rpc('lcxiM', [page, null, 500, null, 1, 3]);
    if (!Array.isArray(rep) || !(Array.isArray(rep[0]) || rep[0] === null)) {
      throw new Error('Réponse invalide à la lecture de la bibliothèque. Export précédent conservé.');
    }
    for (const p of rep[0] ?? []) photos.push([p[0], p[3], p[2], p[4] ?? 0]);
    page = rep?.[1];
    if (page && pagesVues.has(page)) throw new Error('Page répétée dans la bibliothèque.');
    if (page) pagesVues.add(page);
    if (photos.length % 5000 < 500) log(`Bibliothèque : ${photos.length} photos listées…`);
  } while (page);
  return photos;
}

// Noms de fichiers des photos (identifiants → noms), par lots de 500.
async function nomsFichiers(rpc, cles) {
  const noms = {};
  for (let i = 0; i < cles.length; i += 500) {
    let manquants = cles.slice(i, i + 500);
    // Une réponse partielle ne provoque pas d'erreur RPC : redemander les noms absents une fois.
    for (let essai = 0; essai < 2 && manquants.length; essai++) {
      const lot = manquants.map((cle) => [cle]);
      // prettier-ignore
      const rep = await rpc('EWgK9e', [[[lot], [[null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, [], null, null, null, null, null, null, null, null, null, null, []]]]]);
      for (const info of rep?.[0]?.[1] ?? []) noms[info[0]] = info[1]?.[3] ?? '';
      manquants = manquants.filter((cle) => !noms[cle]);
    }
    if ((i / 500) % 20 === 19) console.log('[export]', `Noms de fichiers : ${Math.min(i + 500, cles.length)} / ${cles.length}`);
  }
  return noms;
}

// --- Export précédent (mode incrémental) -------------------------------------------------

// Relit les fichiers de la fois précédente. Renvoie des structures vides s'ils n'existent pas
// ou s'ils viennent d'une version plus ancienne du script (sans identifiants d'album).
function lirePrecedent(suffixe) {
  const vide = { signatures: {}, photosParAlbum: new Map(), noms: new Map() };
  const fichierAlbums = `albums-${suffixe}.csv`;
  const fichierPhotos = `photos-albums-${suffixe}.csv`;
  if (!existsSync(fichierAlbums) || !existsSync(fichierPhotos)) return vide;

  const [enteteAlbums, ...albums] = lireCsv(fichierAlbums);
  const [entetePhotos, ...photos] = lireCsv(fichierPhotos);
  if (enteteAlbums?.[5] !== 'signature' || entetePhotos?.[5] !== 'dedup') {
    console.log('Les fichiers précédents sont d\'un ancien format : export complet.');
    return vide;
  }

  const precedent = { signatures: {}, photosParAlbum: new Map(), noms: new Map() };
  const comptes = new Map();
  for (const ligne of albums) {
    if (ligne.length !== 6 || !ligne[4] || !ligne[5] || !/^\d+$/.test(ligne[1]) || comptes.has(ligne[4])) {
      console.log('Export précédent invalide : export complet.');
      return vide;
    }
    comptes.set(ligne[4], Number(ligne[1]));
    // Les anciennes versions pouvaient enregistrer une réponse partielle avec sa signature
    // complète. Le compte annoncé par Google est l'avant-dernier champ de cette signature.
    const annonce = ligne[5].match(/\|(\d+)\|[^|]*$/);
    if (annonce && Number(annonce[1]) !== Number(ligne[1])) {
      console.log('Export précédent incomplet selon la signature Google : export complet.');
      return vide;
    }
    precedent.signatures[ligne[4]] = ligne[5];
  }
  if (photos.some((ligne) => ligne.length !== 6 || !ligne[3] || !comptes.has(ligne[4]))) {
    console.log('Export précédent invalide : export complet.');
    return vide;
  }
  const identifiantsParAlbum = new Map();
  for (const [, fichier, date, idPhoto, idAlbum, dedup] of photos) {
    if (!identifiantsParAlbum.has(idAlbum)) identifiantsParAlbum.set(idAlbum, new Set());
    const identifiants = identifiantsParAlbum.get(idAlbum);
    if (identifiants.has(idPhoto)) {
      console.log('Export précédent avec des photos répétées dans un album : export complet.');
      return vide;
    }
    identifiants.add(idPhoto);
    if (!precedent.photosParAlbum.has(idAlbum)) precedent.photosParAlbum.set(idAlbum, []);
    precedent.photosParAlbum.get(idAlbum).push({ fichier, date, cle: idPhoto, dedup });
    if (fichier) precedent.noms.set(idPhoto, fichier);
  }
  for (const [id, nombre] of comptes) {
    if ((precedent.photosParAlbum.get(id)?.length ?? 0) !== nombre) {
      console.log('Export précédent incomplet : export complet.');
      return vide;
    }
  }
  return precedent;
}

// --- Photos hors album -------------------------------------------------------------------

const FICHIER_HORS_ALBUM = 'photos-hors-album.csv';
const TITRE_HORS_ALBUM = '(hors album)';

// Noms de fichiers déjà connus par l'export précédent (identifiant → nom).
function lireNomsHorsAlbum() {
  const noms = new Map();
  if (!existsSync(FICHIER_HORS_ALBUM)) return noms;
  const [entete, ...lignes] = lireCsv(FICHIER_HORS_ALBUM);
  if (entete?.[5] !== 'dedup') return noms;
  for (const [, fichier, , id] of lignes) if (fichier) noms.set(id, fichier);
  return noms;
}

function heureLocale(horodatage, decalage) {
  try {
    return new Date(horodatage + decalage).toISOString().slice(0, 19).replace('T', ' ');
  } catch {
    return '';
  }
}

// Photos de la bibliothèque qui ne figurent dans aucun album : ni par leur identifiant, ni par
// l'empreinte de leur contenu (une photo partagée a un identifiant différent dans chaque album).
function photosHorsAlbum(bibliotheque, albums) {
  const identifiants = new Set();
  const empreintes = new Set();
  for (const a of albums) {
    for (const p of a.photos) {
      identifiants.add(p.cle);
      if (p.dedup) empreintes.add(p.dedup);
    }
  }
  return bibliotheque.filter(([cle, empreinte]) => !identifiants.has(cle) && !empreintes.has(empreinte));
}

// Même format que photos-albums-<suffixe>.csv, avec « (hors album) » comme titre : le module
// Lightroom lit les deux de la même façon.
function ecrireHorsAlbum(photos, noms) {
  const lignes = photos
    .map(([cle, empreinte, horodatage, decalage]) => [TITRE_HORS_ALBUM, noms.get(cle) ?? '', heureLocale(horodatage, decalage), cle, 'hors-album', empreinte])
    .sort((a, b) => a[2].localeCompare(b[2]));
  ecrireCsv(FICHIER_HORS_ALBUM, [['album', 'fichier', 'date_prise_de_vue', 'id_photo', 'id_album', 'dedup'], ...lignes]);
  const sansNom = lignes.filter((l) => !l[1]).length;
  console.log(`\n${lignes.length} photos hors album${sansNom > 0 ? ` (dont ${sansNom} sans nom de fichier)` : ''}.`);
  console.log(`Fichier écrit : ${path.resolve(FICHIER_HORS_ALBUM)}`);
}

// --- Écriture des fichiers ---------------------------------------------------------------

function ecrireResultats(albums, suffixe) {
  albums.sort((a, b) => a.titre.localeCompare(b.titre, 'fr'));
  const fichierAlbums = `albums-${suffixe}.csv`;
  const fichierPhotos = `photos-albums-${suffixe}.csv`;

  ecrireCsv(fichierAlbums, [
    ['album', 'nb_photos', 'cree_le', 'criteres', 'id_album', 'signature'],
    ...albums.map((a) => [a.titre, a.photos.length, a.creeLe, a.criteres.join(', '), a.cle, a.signature]),
  ]);
  ecrireCsv(fichierPhotos, [
    ['album', 'fichier', 'date_prise_de_vue', 'id_photo', 'id_album', 'dedup'],
    ...albums.flatMap((a) => a.photos.map((p) => [a.titre, p.fichier, p.date, p.cle, a.cle, p.dedup ?? ''])),
  ]);

  const nbPhotos = albums.reduce((total, a) => total + a.photos.length, 0);
  const sansNom = albums.reduce((total, a) => total + a.photos.filter((p) => !p.fichier).length, 0);
  console.log(`\n${albums.length} albums retenus, ${nbPhotos} photos.`);
  if (sansNom > 0) console.log(`${sansNom} photos sans nom de fichier (souvent des photos ajoutées par d'autres personnes).`);
  console.log(`Fichiers écrits : ${path.resolve(fichierAlbums)}\n                  ${path.resolve(fichierPhotos)}`);
}

// --- Programme principal -----------------------------------------------------------------

async function main() {
  const annee = process.argv[2] === undefined ? null : Number(process.argv[2]);
  if (annee !== null && !Number.isInteger(annee)) throw new Error(`Année invalide : ${process.argv[2]}`);
  if (typeof WebSocket === 'undefined') throw new Error('Ce script demande Node 22 ou plus récent.');
  const suffixe = annee ?? 'tous';

  const precedent = annee === null ? lirePrecedent(suffixe) : lirePrecedent('(aucun)');

  const lanceParLeScript = await demarrerChrome();
  try {
    const onglet = await attendreOngletPhotos();
    const cdp = await Cdp.connecter(onglet.webSocketDebuggerUrl);
    cdp.sur('Runtime.consoleAPICalled', ({ args }) => {
      if (args[0]?.value === PREFIXE_LOG) console.log(args.slice(1).map((a) => a.value).join(' '));
    });
    await cdp.envoyer('Runtime.enable');
    console.log('Connecté à Google Photos. Ne touche pas à la fenêtre Chrome pendant l’export.');

    const albums = await evaluerDansPage(cdp, extraireAlbums, annee, precedent.signatures);

    // Restaurer d'abord les photos inchangées, y compris celles dont le nom manque encore.
    for (const a of albums) {
      if (a.inchange) a.photos = precedent.photosParAlbum.get(a.cle) ?? [];
    }
    // Noms de fichiers : on ne demande à Google que ceux qu'on ne connaît pas déjà.
    const inconnus = new Set();
    for (const a of albums) {
      for (const p of a.photos) if (!p.fichier && !precedent.noms.has(p.cle)) inconnus.add(p.cle);
    }
    let nouveauxNoms = {};
    if (inconnus.size > 0) {
      console.log(`Noms de fichiers de ${inconnus.size} photos…`);
      nouveauxNoms = await evaluerDansPage(cdp, nomsFichiers, [...inconnus]);
    }

    for (const a of albums) {
      a.photos = a.photos.map((p) => ({ ...p, fichier: p.fichier || precedent.noms.get(p.cle) || nouveauxNoms[p.cle] || '' }));
    }
    let resultatHorsAlbum = null;

    // Sans année : les photos hors album aussi (toute la bibliothèque, moins celles des albums).
    if (annee === null) {
      console.log('Liste de toute la bibliothèque (quelques minutes)…');
      const bibliotheque = await evaluerDansPage(cdp, listerBibliotheque);
      const horsAlbum = photosHorsAlbum(bibliotheque, albums);
      console.log(`${bibliotheque.length} photos dans la bibliothèque, ${horsAlbum.length} hors album.`);

      const noms = lireNomsHorsAlbum();
      const inconnus = horsAlbum.map(([cle]) => cle).filter((cle) => !noms.has(cle));
      if (inconnus.length > 0) {
        console.log(`Noms de fichiers de ${inconnus.length} photos…`);
        const nouveaux = await evaluerDansPage(cdp, nomsFichiers, inconnus);
        for (const [cle, nom] of Object.entries(nouveaux)) if (nom) noms.set(cle, nom);
      }
      resultatHorsAlbum = { photos: horsAlbum, noms };
    }
    // Toute la collecte doit réussir avant de remplacer un des exports précédents.
    ecrireResultats(albums, suffixe);
    if (resultatHorsAlbum) ecrireHorsAlbum(resultatHorsAlbum.photos, resultatHorsAlbum.noms);
    cdp.fermer();
  } finally {
    if (lanceParLeScript) await fermerChrome();
  }
}

main().catch((erreur) => {
  console.error(`Erreur : ${erreur.message}`);
  process.exitCode = 1;
});
