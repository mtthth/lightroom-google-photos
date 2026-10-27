// Connexion à Google Photos pour le service d'export « Google Photos » du module Lightroom
// (albums-google-photos.lrplugin), qui passe par l'API officielle de Google Photos.
//
// Usage : node connexion-google-photos.mjs [fichier client_secret….json]      (Node 22 ou plus)
//
// Le module Lightroom lance ce script tout seul quand il n'est pas encore connecté, ou quand
// Google a coupé la connexion : il n'y a normalement pas besoin de le lancer à la main.
//
// À faire une seule fois avant, sur https://console.cloud.google.com :
//   1. créer un projet (nom au choix) ;
//   2. « API et services » → « Bibliothèque » : activer « Photos Library API » ;
//   3. « Google Auth Platform » : la configurer (nom de l'application, adresse, audience
//      « Externe »), puis dans « Audience » → « Utilisateurs test », ajouter son adresse Gmail.
//      L'application reste en mode « Test » : la publier demanderait un site web et une page de
//      confidentialité. En mode « Test », Google coupe la connexion au bout de 7 jours ;
//      Lightroom propose alors de se reconnecter ;
//   4. « Google Auth Platform » → « Clients » → « Créer un client », type « Application de
//      bureau » ; télécharger le fichier JSON (client_secret_….json) et le poser dans ce dossier.
// Pendant la connexion, Google prévient que l'application n'est pas validée : « Paramètres
// avancés », puis « Accéder à … ». Laisser cochées les deux autorisations demandées.
//
// La connexion (identifiants du client et jeton de renouvellement) est enregistrée dans
// %LOCALAPPDATA%\lightroom-google-photos\google-photos.json. Supprimer ce fichier pour se
// déconnecter.

import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DOSSIER_SCRIPT = path.dirname(fileURLToPath(import.meta.url));
const DOSSIER_CONNEXION = path.join(process.env.LOCALAPPDATA ?? '.', 'lightroom-google-photos');
const FICHIER_CONNEXION = path.join(DOSSIER_CONNEXION, 'google-photos.json');
// Envoyer des photos et créer des albums ; relire les albums et photos créés par l'application.
const AUTORISATIONS = [
  'https://www.googleapis.com/auth/photoslibrary.appendonly',
  'https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata',
];
const DELAI_CONNEXION_MS = 10 * 60 * 1000;

// Identifiants du client OAuth : fichier donné en argument, sinon client_secret….json dans le
// dossier du script, sinon ceux de la connexion précédente.
function lireClient() {
  let chemin = process.argv[2];
  if (!chemin) {
    const trouve = readdirSync(DOSSIER_SCRIPT).find((f) => /^client_secret.*\.json$/i.test(f));
    if (trouve) chemin = path.join(DOSSIER_SCRIPT, trouve);
  }
  if (chemin) {
    const json = JSON.parse(readFileSync(chemin, 'utf8'));
    if (json.web) {
      throw new Error(`${chemin} est un client « Application Web » : crée plutôt un client « Application de bureau ».`);
    }
    const { client_id, client_secret } = json.installed ?? {};
    if (!client_id || !client_secret) throw new Error(`${chemin} ne contient pas d'identifiants de client OAuth.`);
    return { client_id, client_secret };
  }
  if (existsSync(FICHIER_CONNEXION)) {
    const { client_id, client_secret } = JSON.parse(readFileSync(FICHIER_CONNEXION, 'utf8'));
    if (client_id && client_secret) return { client_id, client_secret };
  }
  throw new Error(`Fichier client_secret_….json introuvable dans ${DOSSIER_SCRIPT} : ` +
    'voir les explications en tête de connexion-google-photos.mjs.');
}

function ouvrirNavigateur(url) {
  // rundll32 transmet l'adresse telle quelle (« cmd /c start » la couperait aux « & »).
  spawn('rundll32', ['url.dll,FileProtocolHandler', url], { detached: true, stdio: 'ignore' }).unref();
}

const page = (message) => `<!doctype html><meta charset="utf-8"><title>Google Photos</title>
<body style="font: 16px system-ui, sans-serif; margin: 3em">${message}</body>`;

// Ouvre la page de connexion de Google dans le navigateur et attend son retour sur un petit
// serveur local (127.0.0.1, port libre quelconque). Renvoie le code d'autorisation.
async function obtenirCode(client) {
  const verificateur = randomBytes(32).toString('base64url');
  const defi = createHash('sha256').update(verificateur).digest('base64url');
  const etat = randomBytes(16).toString('hex');

  let terminer;
  const resultat = new Promise((resolve, reject) => { terminer = { resolve, reject }; });
  const serveur = createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname !== '/') {
      res.writeHead(404).end();
      return;
    }
    const code = url.searchParams.get('code');
    const ok = code && url.searchParams.get('state') === etat;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    if (ok) {
      res.end(page('Connexion à Google Photos réussie. Tu peux fermer cette page et revenir à Lightroom.'));
      terminer.resolve(code);
    } else {
      const erreur = url.searchParams.get('error') ?? 'réponse inattendue';
      res.end(page(`Connexion à Google Photos refusée (${erreur}).`));
      terminer.reject(new Error(`connexion refusée (${erreur}).`));
    }
  });
  await new Promise((resolve) => serveur.listen(0, '127.0.0.1', resolve));
  const redirection = `http://127.0.0.1:${serveur.address().port}`;

  const adresse = 'https://accounts.google.com/o/oauth2/v2/auth?' + new URLSearchParams({
    client_id: client.client_id,
    redirect_uri: redirection,
    response_type: 'code',
    scope: AUTORISATIONS.join(' '),
    access_type: 'offline',
    prompt: 'consent',
    code_challenge: defi,
    code_challenge_method: 'S256',
    state: etat,
  });
  console.log("Connecte-toi à Google dans la page qui vient de s'ouvrir (attente : 10 minutes).");
  console.log(`Si elle ne s'est pas ouverte : ${adresse}`);
  ouvrirNavigateur(adresse);

  const minuteur = setTimeout(() => terminer.reject(new Error('pas de connexion dans le délai imparti.')), DELAI_CONNEXION_MS);
  try {
    return { code: await resultat, verificateur, redirection };
  } finally {
    clearTimeout(minuteur);
    serveur.closeAllConnections();
    serveur.close();
  }
}

async function main() {
  const client = lireClient();
  const { code, verificateur, redirection } = await obtenirCode(client);

  const rep = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    body: new URLSearchParams({
      ...client,
      code,
      code_verifier: verificateur,
      redirect_uri: redirection,
      grant_type: 'authorization_code',
    }),
  });
  const jetons = await rep.json();
  if (!rep.ok) throw new Error(`Google a refusé la connexion : ${jetons.error_description ?? jetons.error}`);
  if (!jetons.refresh_token) throw new Error("Google n'a pas fourni de jeton de renouvellement.");
  const accordees = (jetons.scope ?? '').split(' ');
  if (AUTORISATIONS.some((a) => !accordees.includes(a))) {
    throw new Error("toutes les autorisations n'ont pas été accordées : relance la connexion en laissant les cases cochées.");
  }

  mkdirSync(DOSSIER_CONNEXION, { recursive: true });
  writeFileSync(FICHIER_CONNEXION, JSON.stringify({ ...client, refresh_token: jetons.refresh_token }, null, 2));
  console.log(`Connexion enregistrée dans ${FICHIER_CONNEXION}`);
}

main().catch((erreur) => {
  console.error(`Erreur : ${erreur.message}`);
  process.exitCode = 1;
});
