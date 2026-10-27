// Lecture et écriture des fichiers CSV du projet : séparateur « ; », guillemets éventuels,
// UTF-8 avec BOM (le format qu'Excel en français ouvre correctement).

import { readFileSync, writeFileSync } from 'node:fs';

export function lireCsv(chemin) {
  const texte = readFileSync(chemin, 'utf8').replace(/^﻿/, '');
  const lignes = [];
  let ligne = [];
  let champ = '';
  let entreGuillemets = false;
  for (let i = 0; i < texte.length; i++) {
    const c = texte[i];
    if (entreGuillemets) {
      if (c === '"' && texte[i + 1] === '"') { champ += '"'; i++; }
      else if (c === '"') entreGuillemets = false;
      else champ += c;
    } else if (c === '"') entreGuillemets = true;
    else if (c === ';') { ligne.push(champ); champ = ''; }
    else if (c === '\n') { ligne.push(champ); champ = ''; lignes.push(ligne); ligne = []; }
    else if (c !== '\r') champ += c;
  }
  if (champ !== '' || ligne.length > 0) { ligne.push(champ); lignes.push(ligne); }
  return lignes;
}

export function ecrireCsv(chemin, lignes) {
  const cellule = (valeur) => {
    const texte = String(valeur ?? '');
    return /[;"\r\n]/.test(texte) ? `"${texte.replaceAll('"', '""')}"` : texte;
  };
  writeFileSync(chemin, '﻿' + lignes.map((l) => l.map(cellule).join(';')).join('\r\n') + '\r\n');
}
