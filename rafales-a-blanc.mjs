// Rapport « à blanc » des rafales d'un dossier du catalogue Lightroom : détecte les rafales, mesure la
// netteté de chaque cadre et montre ce qui serait gardé et ce qui serait retiré. Ne modifie rien : le
// catalogue est lu en lecture seule (Lightroom peut rester ouvert ; les modifications des dernières
// minutes peuvent ne pas y figurer).
//
// Usage : node rafales-a-blanc.mjs <dossier> [--sous-dossiers] [--bloc N] [--ignorer "collection"]
//                                                                          (Node 22.13 ou plus)
//   <dossier>        nom du dossier tel qu'il apparaît dans Lightroom, par exemple 2026-08-15 ;
//   --sous-dossiers  inclut aussi les sous-dossiers ;
//   --bloc N         un cadre gardé pour N cadres (4 par défaut : on retire 3 cadres sur 4) ;
//   --ignorer NOM    ne compte pas cette collection (ou cet ensemble de collections de premier niveau)
//                    comme protection ; l'option peut être répétée. « Google Photos - époques » est
//                    toujours ignorée.
// Fichiers écrits dans le dossier courant : rafales-<dossier>.html (miniatures) et .csv (détail).
//
// Une rafale = au moins 3 cadres qui se suivent à une seconde d'écart au plus, avec des numéros de
// fichier voisins (le catalogue ne garde que la seconde entière : l'ordre des cadres d'une même
// seconde vient du numéro). RAW + JPEG, copies « -2 » et versions retouchées d'un même cadre
// comptent pour un seul cadre.
//
// Dans chaque rafale, les cadres sont découpés en blocs de N cadres consécutifs (blocs de taille
// égale) et on garde le plus net des cadres non protégés de chaque bloc. Sont protégés, donc toujours
// gardés EN PLUS : les cadres
//   - dans une collection autre que « Google Photos - époques » (les albums Google comptent) ;
//   - notés, marqués d'un drapeau ou d'un libellé de couleur, retouchés dans Lightroom ou avec des
//     copies virtuelles ;
//   - qui ont une version retouchée dans un éditeur externe (-Modifier, DxO_…).
// Les photos des collections « Doublons à retirer » et « Rafales à retirer », et celles qui portent le
// mot-clé « Rafale traitée » (posé par la commande Lightroom « Réduire les rafales »), sont ignorées.
// C'est le même calcul que la commande « Réduire les rafales… » du module Lightroom.
// La netteté est l'écart-type du laplacien de l'image réduite (ImageMagick) : plus il est grand,
// plus l'image est nette.

import { execFile } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import path from 'node:path';
import { promisify } from 'node:util';

const executer = promisify(execFile);

const ECART_MAX_SECONDES = 1;
const ECART_MAX_NUMERO = 3;
const MIN_CADRES = 3;
const PARALLELE = 6;
const LARGEUR_MESURE = 1200;
const COTE_MINIATURE = 200;
const COLLECTIONS_SANS_PROTECTION = new Set(['Google Photos - époques', 'Doublons à retirer', 'Rafales à retirer']);
const MARQUEUR_RETOUCHE = /-modifi|-edit|-retouch|[_-]filtered|[ _-]dxo_/i;
const RANG_FORMAT = { jpg: 0, jpeg: 0, tif: 1, tiff: 1, png: 2, heic: 3 };

// --- Entrée ----------------------------------------------------------------------------------------

const args = process.argv.slice(2);
const sousDossiers = args.includes('--sous-dossiers');
const tailleBloc = Number(args[args.indexOf('--bloc') + 1] || 4) || 4;
// Valeurs des options : elles ne sont pas le nom du dossier.
const valeursOptions = new Set(args.flatMap((a, i) => (a === '--bloc' || a === '--ignorer' ? [args[i + 1]] : [])));
const dossierDemande = args.find((a) => !a.startsWith('--') && !valeursOptions.has(a));
args.forEach((a, i) => { if (a === '--ignorer' && args[i + 1]) COLLECTIONS_SANS_PROTECTION.add(args[i + 1]); });
if (!dossierDemande) {
  console.error('Usage : node rafales-a-blanc.mjs <dossier> [--sous-dossiers] [--bloc N] [--ignorer "collection"]');
  process.exit(1);
}

// Catalogue ouvert dans Lightroom, lu dans ses préférences.
function cheminCatalogue() {
  const prefs = path.join(process.env.APPDATA ?? '', 'Adobe/Lightroom/Preferences/Lightroom Classic CC 7 Preferences.agprefs');
  const texte = readFileSync(prefs, 'utf8');
  const m = texte.match(/libraryToLoad20 = "([^"]+)"/);
  if (!m) throw new Error('Catalogue introuvable dans les préférences de Lightroom.');
  return m[1].replaceAll('\\\\', '\\');
}

function trouverMagick() {
  for (const d of [process.env.PROGRAMFILES, process.env['PROGRAMFILES(X86)']].filter(Boolean)) {
    try {
      for (const nom of readdirSync(d)) {
        const c = path.join(d, nom, 'magick.exe');
        if (/imagemagick/i.test(nom) && existsSync(c)) return c;
      }
    } catch { /* dossier illisible */ }
  }
  throw new Error('ImageMagick (magick.exe) est introuvable.');
}

// --- Lecture du catalogue ----------------------------------------------------------------------------

const catalogue = cheminCatalogue();
const db = new DatabaseSync('file:///' + catalogue.replaceAll('\\', '/').replaceAll(' ', '%20') + '?mode=ro&immutable=1', { readOnly: true });

const dossiers = db.prepare(`SELECT fo.id_local AS id, rf.absolutePath || fo.pathFromRoot AS chemin
  FROM AgLibraryFolder fo JOIN AgLibraryRootFolder rf ON fo.rootFolder = rf.id_local`).all()
  .filter((d) => {
    const morceaux = d.chemin.split('/').filter(Boolean);
    return sousDossiers ? morceaux.includes(dossierDemande) : morceaux.at(-1) === dossierDemande;
  });
if (dossiers.length === 0) throw new Error(`Aucun dossier « ${dossierDemande} » dans le catalogue ${catalogue}.`);
console.log(`Catalogue : ${catalogue}`);
console.log(`Dossier(s) : ${dossiers.map((d) => d.chemin).join(' ; ')}`);

const ids = dossiers.map((d) => d.id).join(',');
const fichiers = db.prepare(`SELECT i.id_local AS id, f.baseName AS nom, f.extension AS ext, i.captureTime AS date,
    COALESCE(i.rating, 0) AS note, COALESCE(i.pick, 0) AS drapeau, COALESCE(i.colorLabels, '') AS libelle,
    COALESCE(ds.hasDevelopAdjustmentsEx, 0) AS retouche, rf.absolutePath || fo.pathFromRoot AS dossier,
    (SELECT COUNT(*) FROM Adobe_images v WHERE v.masterImage = i.id_local) AS virtuelles
  FROM Adobe_images i JOIN AgLibraryFile f ON i.rootFile = f.id_local
  JOIN AgLibraryFolder fo ON f.folder = fo.id_local JOIN AgLibraryRootFolder rf ON fo.rootFolder = rf.id_local
  LEFT JOIN Adobe_imageDevelopSettings ds ON ds.image = i.id_local
  WHERE i.masterImage IS NULL AND fo.id_local IN (${ids})`).all();

// Photos ignorées : cadres en trop déjà mis de côté, et photos des rafales déjà traitées.
const ignorees = new Set([
  ...db.prepare(`SELECT ci.image AS id FROM AgLibraryCollectionImage ci JOIN AgLibraryCollection c ON c.id_local = ci.collection
    WHERE c.parent IS NULL AND c.name IN ('Doublons à retirer', 'Rafales à retirer')`).all().map((r) => r.id),
  ...db.prepare(`SELECT ki.image AS id FROM AgLibraryKeywordImage ki JOIN AgLibraryKeyword k ON k.id_local = ki.tag
    WHERE k.name = 'Rafale traitée'`).all().map((r) => r.id),
]);
const nbIgnorees = fichiers.filter((f) => ignorees.has(f.id)).length;
for (let i = fichiers.length - 1; i >= 0; i--) if (ignorees.has(fichiers[i].id)) fichiers.splice(i, 1);
if (nbIgnorees > 0) console.log(`${nbIgnorees} photos ignorées (déjà traitées ou dans « Doublons à retirer » / « Rafales à retirer »).`);

const appartenances = new Map();   // photo → liste de { racine, nom }
for (const l of db.prepare(`WITH RECURSIVE racine(id, nom, rac) AS (
    SELECT id_local, name, name FROM AgLibraryCollection WHERE parent IS NULL
    UNION ALL SELECT c.id_local, c.name, r.rac FROM AgLibraryCollection c JOIN racine r ON c.parent = r.id)
  SELECT ci.image AS image, r.rac AS racine, r.nom AS nom FROM AgLibraryCollectionImage ci JOIN racine r ON r.id = ci.collection
  WHERE ci.image IN (SELECT i.id_local FROM Adobe_images i JOIN AgLibraryFile f ON i.rootFile = f.id_local WHERE f.folder IN (${ids}))`).all()) {
  if (!appartenances.has(l.image)) appartenances.set(l.image, []);
  appartenances.get(l.image).push({ racine: l.racine, nom: l.nom });
}

// --- Cadres et rafales ----------------------------------------------------------------------------------

const cadres = new Map();
for (const f of fichiers) {
  f.t = Date.parse(f.date.slice(0, 19) + 'Z') / 1000;
  f.numero = Number(f.nom.match(/(\d{3,})/)?.[1] ?? -1);
  f.chemin = f.dossier + f.nom + '.' + f.ext;
  f.derive = MARQUEUR_RETOUCHE.test(f.nom);
  const cle = `${f.dossier}|${f.t}|${f.numero}`;
  if (!cadres.has(cle)) cadres.set(cle, { t: f.t, numero: f.numero, fichiers: [] });
  cadres.get(cle).fichiers.push(f);
}
const liste = [...cadres.values()].sort((a, b) => a.t - b.t || a.numero - b.numero);

for (const c of liste) {
  const raisons = [];
  for (const f of c.fichiers) {
    if (f.note > 0) raisons.push(`note ${f.note}`);
    if (f.drapeau !== 0) raisons.push('drapeau');
    if (f.libelle !== '') raisons.push('libellé');
    if (f.retouche > 0) raisons.push('retouches Lightroom');
    if (f.virtuelles > 0) raisons.push('copies virtuelles');
    for (const a of appartenances.get(f.id) ?? []) {
      if (!COLLECTIONS_SANS_PROTECTION.has(a.racine)) raisons.push(`collection « ${a.racine === a.nom ? a.nom : `${a.racine} / ${a.nom}`} »`);
    }
  }
  if (c.fichiers.some((f) => f.derive) && c.fichiers.some((f) => !f.derive)) raisons.push('version retouchée (éditeur externe)');
  c.raisons = [...new Set(raisons)];
  c.protege = c.raisons.length > 0;
  // Fichier mesuré : un fichier ordinaire que ImageMagick sait lire, de préférence un JPEG.
  const candidats = c.fichiers.filter((f) => !f.derive && RANG_FORMAT[f.ext.toLowerCase()] !== undefined)
    .sort((a, b) => RANG_FORMAT[a.ext.toLowerCase()] - RANG_FORMAT[b.ext.toLowerCase()] || a.nom.length - b.nom.length);
  c.mesure = candidats[0] ?? null;
  c.nom = (c.fichiers.find((f) => !f.derive && !/-\d$/.test(f.nom)) ?? c.fichiers[0]).nom;
}

const adjacents = (a, b) => b.t - a.t <= ECART_MAX_SECONDES && (a.numero >= 100000 || b.numero >= 100000 || Math.abs(b.numero - a.numero) <= ECART_MAX_NUMERO);
const rafales = [];
let courante = [];
for (const c of liste) {
  if (courante.length && adjacents(courante.at(-1), c)) courante.push(c);
  else { if (courante.length >= MIN_CADRES) rafales.push(courante); courante = [c]; }
}
if (courante.length >= MIN_CADRES) rafales.push(courante);

// --- Mesures (netteté, miniature) -------------------------------------------------------------------------

const magick = trouverMagick();
const enRafale = rafales.flat();
// Blocs et mesures : la netteté ne sert qu'à départager les cadres non protégés d'un même bloc.
function decouper(cadresRafale, n) {
  const blocs = [];
  const taille = cadresRafale.length;
  for (let i = 0; i < n; i++) blocs.push(cadresRafale.slice(Math.floor(i * taille / n), Math.floor((i + 1) * taille / n)));
  return blocs;
}
for (const [numero, rafale] of rafales.entries()) {
  rafale.numero = numero + 1;
  rafale.blocs = decouper(rafale, Math.ceil(rafale.length / tailleBloc));
}
const aMesurer = rafales.flatMap((r) => r.blocs).flatMap((bloc) => {
  const libres = bloc.filter((c) => !c.protege && c.mesure);
  return bloc.filter((c) => !c.protege).length >= 2 ? libres : [];
});
let faits = 0;
async function parallele(elements, n, tache) {
  let suivant = 0;
  await Promise.all(Array.from({ length: n }, async () => {
    while (suivant < elements.length) await tache(elements[suivant++]);
  }));
}
console.log(`${fichiers.length} fichiers, ${liste.length} cadres, ${rafales.length} rafales (${enRafale.length} cadres). Mesure de la netteté de ${aMesurer.length} cadres…`);
await parallele(aMesurer, PARALLELE, async (c) => {
  if (c.mesure) {
    try {
      const { stdout } = await executer(magick, ['-define', `jpeg:size=${LARGEUR_MESURE * 4 / 3}x${LARGEUR_MESURE * 4 / 3}`, c.mesure.chemin + '[0]', '-auto-orient',
        '-resize', `${LARGEUR_MESURE}x${LARGEUR_MESURE}`, '-colorspace', 'Gray', '-morphology', 'Convolve', 'Laplacian:0',
        '-format', '%[fx:standard_deviation*1000]', 'info:']);
      c.nettete = Number(stdout);
      const { stdout: image } = await executer(magick, ['-define', `jpeg:size=${COTE_MINIATURE * 2}x${COTE_MINIATURE * 2}`, c.mesure.chemin + '[0]',
        '-auto-orient', '-thumbnail', `${COTE_MINIATURE}x${COTE_MINIATURE}`, '-quality', '72', 'jpg:-'], { encoding: 'buffer', maxBuffer: 4 << 20 });
      c.miniature = image.toString('base64');
    } catch { c.nettete = null; }
  }
  faits++;
  if (faits % 100 === 0) console.log(`  ${faits} / ${aMesurer.length}`);
});

// --- Décisions --------------------------------------------------------------------------------------------

for (const rafale of rafales) {
  for (const bloc of rafale.blocs) {
    // Règle A : les protégés sont gardés en plus du plus net des cadres non protégés du bloc.
    const libres = bloc.filter((c) => !c.protege);
    const meilleur = libres.reduce((a, b) => ((b.nettete ?? -1) > (a.nettete ?? -1) ? b : a), libres[0]);
    for (const c of bloc) {
      if (c.protege) c.decision = 'protégé';
      else if (c === meilleur) c.decision = 'garder';
      else {
        c.decision = 'retirer';
        c.pourquoi = meilleur.nettete == null ? 'netteté non mesurée' : `moins net que ${meilleur.nom}`;
      }
    }
  }
}

// --- Rapport ------------------------------------------------------------------------------------------------

const retirer = enRafale.filter((c) => c.decision === 'retirer');
const taille = (cs) => cs.flatMap((c) => c.fichiers).reduce((s, f) => { try { return s + statSync(f.chemin).size; } catch { return s; } }, 0);
const gigas = (o) => (o / 1024 ** 3).toFixed(2).replace('.', ',') + ' Go';
const stats = {
  fichiers: fichiers.length, cadres: liste.length, rafales: rafales.length, enRafale: enRafale.length,
  proteges: enRafale.filter((c) => c.decision === 'protégé').length, gardes: enRafale.filter((c) => c.decision === 'garder').length,
  retires: retirer.length, fichiersRetires: retirer.flatMap((c) => c.fichiers).length, octets: taille(retirer),
  hors: liste.length - enRafale.length,
};
// Ce qui protège les cadres, et à quel point la netteté départage les cadres d'un même bloc.
const parRaison = {};
for (const c of enRafale.filter((x) => x.protege)) for (const r of c.raisons) parRaison[r] = (parRaison[r] ?? 0) + 1;
const ecartsBlocs = rafales.flatMap((r) => r.blocs).filter((b) => !b.some((c) => c.protege)).map((b) => {
  const v = b.map((c) => c.nettete).filter((x) => x != null);
  return v.length > 1 ? (Math.max(...v) - Math.min(...v)) / Math.max(...v) : null;
}).filter((x) => x != null);
stats.blocs = ecartsBlocs.length;
stats.blocsNets = ecartsBlocs.filter((e) => e > 0.10).length;
stats.blocsEgaux = ecartsBlocs.filter((e) => e < 0.02).length;
const suffixe = dossierDemande.replace(/[^\w.-]/g, '_');
const echapper = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function csv(lignes) {
  const cellule = (v) => { const t = String(v ?? ''); return /[;"\r\n]/.test(t) ? `"${t.replaceAll('"', '""')}"` : t; };
  return '﻿' + lignes.map((l) => l.map(cellule).join(';')).join('\r\n') + '\r\n';
}
writeFileSync(`rafales-${suffixe}.csv`, csv([
  ['rafale', 'bloc', 'cadre', 'heure', 'decision', 'nettete', 'raison', 'fichiers'],
  ...rafales.flatMap((r) => r.blocs.flatMap((bloc, b) => bloc.map((c) => [
    r.numero, b + 1, c.nom, new Date(c.t * 1000).toISOString().slice(11, 19), c.decision, c.nettete == null ? '' : c.nettete.toFixed(2).replace('.', ','),
    c.decision === 'protégé' ? c.raisons.join(', ') : c.pourquoi ?? '', c.fichiers.map((f) => f.chemin).join(' | '),
  ]))),
]));

const tuile = (c) => `<figure class="${c.decision === 'garder' ? 'garder' : c.decision === 'protégé' ? 'protege' : 'retirer'}" title="${echapper(
  `${c.nom} — ${c.decision}${c.decision === 'protégé' ? ` (${c.raisons.join(', ')})` : c.pourquoi ? ` : ${c.pourquoi}` : ''}`)}">
  ${c.miniature ? `<img src="data:image/jpeg;base64,${c.miniature}" alt="${echapper(c.nom)}" loading="lazy">` : '<div class="vide">non mesuré</div>'}
  <figcaption><b>${echapper(c.nom.replace(/^\D*/, '') || c.nom)}</b> <span>${c.decision === 'garder' ? 'garder' : c.decision === 'protégé' ? 'protégé' : 'retirer'}</span>
  <small>${c.nettete == null ? '—' : c.nettete.toFixed(0)}${c.decision === 'protégé' ? ` · ${echapper(c.raisons[0])}` : ''}</small></figcaption></figure>`;

const heure = (t) => new Date(t * 1000).toISOString().slice(11, 19);
const sections = rafales.map((r) => {
  const nbGardes = r.flat().filter((c) => c.decision !== 'retirer').length;
  return `<section id="r${r.numero}"><h3>Rafale ${r.numero} <small>${heure(r[0].t)} · ${r.length} cadres (${echapper(r[0].nom)} → ${echapper(r.at(-1).nom)}) · ${nbGardes} gardés, ${r.length - nbGardes} à retirer</small></h3>
<div class="rafale">${r.blocs.map((b) => `<div class="bloc">${b.map(tuile).join('')}</div>`).join('')}</div></section>`;
}).join('\n');

const sommaire = [...rafales].sort((a, b) => b.length - a.length).slice(0, 12)
  .map((r) => `<a href="#r${r.numero}">${r.numero} (${r.length})</a>`).join(' · ');

writeFileSync(`rafales-${suffixe}.html`, `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Rafales ${echapper(dossierDemande)}</title>
<style>
:root { --fond:#fafaf8; --texte:#222; --doux:#666; --garder:#2e8b57; --protege:#2f6fd6; --retirer:#c0392b; --carte:#fff; --bord:#ddd; }
@media (prefers-color-scheme: dark) { :root { --fond:#16181a; --texte:#e8e8e8; --doux:#9a9a9a; --carte:#202326; --bord:#363a3e; } }
body { font: 15px/1.45 system-ui, sans-serif; margin: 0; padding: 24px 16px 60px; background: var(--fond); color: var(--texte); }
main { max-width: 1280px; margin: 0 auto; }
h1 { margin: 0 0 4px; font-size: 1.5rem; } h3 { margin: 26px 0 8px; font-size: 1.05rem; } h3 small { color: var(--doux); font-weight: normal; }
.resume { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; margin: 16px 0; }
.resume div { background: var(--carte); border: 1px solid var(--bord); border-radius: 8px; padding: 10px 12px; }
.resume b { display: block; font-size: 1.45rem; } .resume span { color: var(--doux); font-size: .85rem; }
.legende span { display: inline-block; margin-right: 14px; } .legende i { display:inline-block; width: 12px; height: 12px; border-radius: 3px; vertical-align: -1px; margin-right: 4px; }
.rafale { display: flex; flex-wrap: wrap; gap: 10px; } .bloc { display: flex; gap: 3px; padding: 4px; border: 1px dashed var(--bord); border-radius: 8px; }
figure { margin: 0; width: ${COTE_MINIATURE * 0.62}px; border: 3px solid var(--bord); border-radius: 6px; overflow: hidden; background: var(--carte); }
figure.garder { border-color: var(--garder); } figure.protege { border-color: var(--protege); } figure.retirer { border-color: var(--retirer); }
figure.retirer img { opacity: .78; }
figure img { display: block; width: 100%; height: auto; } .vide { height: 80px; display: grid; place-items: center; color: var(--doux); font-size: .75rem; }
figcaption { padding: 3px 5px 4px; font-size: .72rem; line-height: 1.25; } figcaption span { float: right; font-weight: 600; }
figure.garder span { color: var(--garder); } figure.protege span { color: var(--protege); } figure.retirer span { color: var(--retirer); }
figcaption small { display: block; color: var(--doux); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
a { color: var(--protege); }
</style></head><body><main>
<h1>Rafales de ${echapper(dossierDemande)} — rapport à blanc</h1>
<p>Rien n'a été modifié dans Lightroom. Dans chaque bloc entouré en pointillés (${tailleBloc} cadres), on garde le plus net des cadres non protégés ; les cadres protégés sont toujours gardés en plus.</p>
<div class="resume">
<div><b>${stats.cadres}</b><span>cadres (${stats.fichiers} fichiers)</span></div>
<div><b>${stats.rafales}</b><span>rafales de ${MIN_CADRES} cadres ou plus</span></div>
<div><b>${stats.enRafale}</b><span>cadres en rafale</span></div>
<div><b style="color:var(--protege)">${stats.proteges}</b><span>cadres protégés</span></div>
<div><b style="color:var(--garder)">${stats.gardes}</b><span>cadres gardés (le plus net de chaque bloc)</span></div>
<div><b style="color:var(--retirer)">${stats.retires}</b><span>cadres à retirer (${stats.fichiersRetires} fichiers)</span></div>
<div><b>${gigas(stats.octets)}</b><span>libérés si on supprime du disque</span></div>
</div>
<p class="legende"><span><i style="background:var(--garder)"></i>garder (le plus net du bloc)</span><span><i style="background:var(--protege)"></i>protégé (collection, note, retouche…)</span><span><i style="background:var(--retirer)"></i>à retirer</span> Le nombre sous chaque cadre est sa netteté.</p>
<p><b>Protégés par :</b> ${Object.entries(parRaison).sort((a, b) => b[1] - a[1]).map(([r, n]) => `${echapper(r)} (${n})`).join(' · ') || 'rien'}.
Un cadre peut avoir plusieurs raisons. Pour ne pas compter une collection comme protection, relancer avec <code>--ignorer "nom"</code>.</p>
<p><b>Netteté :</b> sur ${stats.blocs} blocs sans cadre protégé, elle tranche nettement (écart de plus de 10 % entre le plus net et le moins net) dans ${stats.blocsNets} ; elle ne départage presque rien (moins de 2 %) dans ${stats.blocsEgaux}, où le choix est arbitraire mais sans conséquence.</p>
<p>Les plus longues rafales : ${sommaire}</p>
${sections}
</main></body></html>
`);

console.log(`\n${stats.cadres} cadres : ${stats.enRafale} en rafale (${stats.rafales} rafales), dont ${stats.proteges} protégés, ${stats.gardes} gardés, ${stats.retires} à retirer (${stats.fichiersRetires} fichiers, ${gigas(stats.octets)}).`);
console.log(`Écrit : ${path.resolve(`rafales-${suffixe}.html`)}\n        ${path.resolve(`rafales-${suffixe}.csv`)}`);
