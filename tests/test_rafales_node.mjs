import assert from 'node:assert/strict';
import { cadresAdjacents, cheminsExclus, cleCadre, nomDeBase, nomRetouche, normaliserChemin,
  numeroCadre, raisonsProtection, tailleBlocDemandee } from '../rafales-regles.mjs';

let nb = 0;
function verifier(nom, actuel, attendu) {
  assert.deepEqual(actuel, attendu, nom);
  nb++;
}

verifier('dossier numérique sans --bloc : ratio par défaut', tailleBlocDemandee(['2026']), 4);
verifier('ratio explicite', tailleBlocDemandee(['2026', '--bloc', '8']), 8);
verifier('ratio minimum comme Lightroom', tailleBlocDemandee(['2026', '--bloc', '1']), 2);
verifier('ratio entier comme Lightroom', tailleBlocDemandee(['2026', '--bloc', '3.8']), 3);
verifier('ratio invalide : valeur par défaut', tailleBlocDemandee(['2026', '--bloc', 'invalide']), 4);

for (const [nom, numero] of [
  ['DSCF1003-2.JPG', 1003], ['P1210938 (2).jpg', 1210938], ['DSCF1003-2-Modifier.JPG', 1003],
  ['PXL_20260416_164548400.TS.mp4', 164548400],
  ['IMG-20260802-WA0003-Modifié-2026-08-02T22-37-43.jpg', 3],
  ['DSCF5219-20260821-DxO_DeepPRIME XD3.tif', 5219], ['portrait.jpg', -1],
]) verifier('numéro de ' + nom, numeroCadre(nom), numero);

const pixelA = cleCadre('D:/Photos/', 100, 'PXL_20260416_164548400.jpg');
verifier('Pixel : deux prises à la même seconde restent distinctes',
  pixelA !== cleCadre('D:/Photos/', 100, 'PXL_20260416_164548800.jpg'), true);
verifier('RAW et copie JPEG : un seul cadre', cleCadre('D:/Photos/', 100, 'DSCF1003.RAF'),
  cleCadre('d:/photos/', 100, 'DSCF1003-2.JPG'));
verifier('sans numéro : noms distincts', cleCadre('D:/Photos/', 100, 'portrait.jpg')
  !== cleCadre('D:/Photos/', 100, 'paysage.jpg'), true);
verifier('sans numéro : copie et original regroupés', cleCadre('D:/Photos/', 100, 'portrait.jpg'),
  cleCadre('D:/Photos/', 100, 'portrait (2).jpg'));
verifier('les suffixes imbriqués sont retirés', nomDeBase('D:/Photos/DSCF1003-2-Modifier.jpg'), 'dscf1003');
verifier('cadre sans numéro adjacent à un cadre numéroté', cadresAdjacents({ t: 1, numero: -1 }, { t: 2, numero: 500 }), true);
verifier('deux secondes ne forment pas une rafale', cadresAdjacents({ t: 1, numero: -1 }, { t: 3, numero: -1 }), false);
verifier('numéros distants interrompent la rafale', cadresAdjacents({ t: 1, numero: 100 }, { t: 1, numero: 110 }), false);

const exclus = cheminsExclus('# type\tchemin\tfichier\tdate\r\n'
  + 'doublon\tD:\\Photos\\DSCF1000.JPG\tDSCF1000.JPG\t2026-08-15\r\n'
  + '#commentaire\tD:\\Photos\\DSCF2000.JPG\tDSCF2000.JPG\t\n'
  + 'rafale\td:/Photos/DSCF1001.JPG\tDSCF1001.JPG\t\n'
  + 'ligne incomplète\tD:\\Photos\\DSCF3000.JPG\n');
verifier('historique : chemins Windows normalisés', exclus.has(normaliserChemin('d:/photos/DSCF1000.jpg')), true);
verifier('historique : chemins Unix normalisés', exclus.has(normaliserChemin('D:\\PHOTOS\\DSCF1001.jpg')), true);
verifier('historique : commentaires et lignes invalides ignorés', exclus.size, 2);
verifier('historique absent : aucune exclusion', cheminsExclus('').size, 0);

const retouche = { id: 1, note: 0, drapeau: 0, libelle: '', retouche: 0, virtuelles: 0,
  derive: nomRetouche('DSCF1000-Modifier.jpg') };
verifier('version retouchée seule : protégée', raisonsProtection([retouche], new Map(), new Set()),
  ['version retouchée (éditeur externe)']);
verifier('version retouchée avec original : protection unique', raisonsProtection([retouche, { ...retouche, derive: false }], new Map(), new Set()),
  ['version retouchée (éditeur externe)']);
verifier('original seul : aucune protection', raisonsProtection([{ ...retouche, derive: false }], new Map(), new Set()), []);

console.log(`${nb} vérifications, 0 échecs`);
