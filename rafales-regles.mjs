// Règles pures du rapport à blanc, alignées sur Doublons.lua, Similitude.lua et Rafales.lua.
const MARQUEURS_RETOUCHE = [/-modifi/, /-edit/, /-retouch/, /[_-]filtered/, /-\d{8}-dxo_/, /[ _-]dxo_/];
const SUFFIXES = [/\s*\(\d+\)$/, /-\d\d?$/, /-copie$/, /\s-\scopie$/,
  ...MARQUEURS_RETOUCHE.map((motif) => new RegExp(motif.source + '.*$'))];
const nomFichier = (nom) => nom.split(/[/\\]/).at(-1);

export function tailleBlocDemandee(args) {
  const indice = args.indexOf('--bloc');
  const valeur = indice < 0 ? 4 : Number(args[indice + 1]);
  return Number.isFinite(valeur) ? Math.max(2, Math.floor(valeur)) : 4;
}

export function nomDeBase(nom) {
  let base = nomFichier(nom).toLowerCase().replace(/\.[^.]*$/, '');
  for (let i = 0; i < 6; i++) {
    const avant = base;
    for (const suffixe of SUFFIXES) {
      const sans = base.replace(suffixe, '');
      if (sans !== '') base = sans;
    }
    if (base === avant) break;
  }
  return base;
}

export function nomRetouche(nom) {
  const bas = nomFichier(nom).toLowerCase();
  return MARQUEURS_RETOUCHE.some((motif) => motif.test(bas));
}

export function numeroCadre(nom) {
  return Number(nomDeBase(nom).match(/\d{3,}/g)?.at(-1) ?? -1);
}

export function cleCadre(dossier, t, nom) {
  const numero = numeroCadre(nom);
  return `${dossier.toLowerCase()}|${Math.floor(t)}|${numero}${numero < 0 ? '|' + nomDeBase(nom) : ''}`;
}

export function cadresAdjacents(a, b, ecartSecondes = 1, ecartNumero = 3) {
  return b.t - a.t <= ecartSecondes && (a.numero < 0 || b.numero < 0 || a.numero >= 100000
    || b.numero >= 100000 || Math.abs(b.numero - a.numero) <= ecartNumero);
}

export const normaliserChemin = (chemin) => chemin.replaceAll('/', '\\').toLowerCase();

export function cheminsExclus(contenu) {
  const chemins = new Set();
  for (const ligne of contenu.split(/\r?\n|\r/)) {
    if (ligne.startsWith('#')) continue;
    const champs = ligne.match(/^[^\t]+\t([^\t]*)\t[^\t]*\t.*$/);
    if (champs) chemins.add(normaliserChemin(champs[1]));
  }
  return chemins;
}

export function raisonsProtection(fichiers, appartenances, sansProtection) {
  const raisons = [];
  for (const f of fichiers) {
    if (f.note > 0) raisons.push(`note ${f.note}`);
    if (f.drapeau !== 0) raisons.push('drapeau');
    if (f.libelle !== '') raisons.push('libellé');
    if (f.retouche > 0) raisons.push('retouches Lightroom');
    if (f.virtuelles > 0) raisons.push('copies virtuelles');
    for (const a of appartenances.get(f.id) ?? []) {
      if (!sansProtection.has(a.racine)) raisons.push(`collection « ${a.racine === a.nom ? a.nom : `${a.racine} / ${a.nom}`} »`);
    }
    if (f.derive) raisons.push('version retouchée (éditeur externe)');
  }
  return [...new Set(raisons)];
}
