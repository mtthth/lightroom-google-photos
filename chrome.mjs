// Pilotage de Chrome (protocole DevTools, sans dépendance), partagé par les scripts
// export-albums.mjs et telecharger-manquantes.mjs.
//
// Chrome est lancé avec un profil dédié. La première fois, il faut s'y connecter à son
// compte Google : la session est ensuite conservée dans ce profil.

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';

const PORT = 9333;
const PROFIL = path.join(process.env.LOCALAPPDATA ?? '.', 'lightroom-google-photos', 'chrome-profile');
const CHROMES = [
  path.join(process.env.PROGRAMFILES ?? '', 'Google/Chrome/Application/chrome.exe'),
  path.join(process.env['PROGRAMFILES(X86)'] ?? '', 'Google/Chrome/Application/chrome.exe'),
  path.join(process.env.LOCALAPPDATA ?? '', 'Google/Chrome/Application/chrome.exe'),
];
const URL_DEPART = 'https://photos.google.com/albums';
const DELAI_CONNEXION_MS = 10 * 60 * 1000;

export const attendre = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function debogage(chemin, options) {
  try {
    const rep = await fetch(`http://127.0.0.1:${PORT}${chemin}`, options);
    return rep.ok ? await rep.json() : null;
  } catch {
    return null;
  }
}

// Réutilise le Chrome du script s'il est déjà ouvert, sinon le lance.
// Renvoie true si c’est cet appel qui l'a lancé.
export async function demarrerChrome() {
  if (await debogage('/json/version')) return false;

  const chrome = CHROMES.find((chemin) => existsSync(chemin));
  if (!chrome) throw new Error('Chrome est introuvable sur cette machine.');
  mkdirSync(PROFIL, { recursive: true });
  spawn(chrome, [
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${PROFIL}`,
    '--no-first-run',
    '--no-default-browser-check',
    URL_DEPART,
  ], { detached: true, stdio: 'ignore' }).unref();

  for (let i = 0; i < 100; i++) {
    if (await debogage('/json/version')) return true;
    await attendre(200);
  }
  throw new Error("Chrome ne répond pas. Ferme les fenêtres Chrome ouvertes par ce script, puis relance-le.");
}

// Attend un onglet ouvert sur photos.google.com, donc un compte connecté.
// On ne s'attache pas à la page pendant la connexion pour ne pas gêner Google.
export async function attendreOngletPhotos() {
  let averti = false;
  let ouvert = false;
  const limite = Date.now() + DELAI_CONNEXION_MS;
  while (Date.now() < limite) {
    const pages = ((await debogage('/json/list')) ?? []).filter((cible) => cible.type === 'page');
    const photos = pages.find((page) => page.url.startsWith('https://photos.google.com/'));
    if (photos) return photos;
    if (pages.length === 0 && !ouvert) {
      await debogage(`/json/new?${URL_DEPART}`, { method: 'PUT' });
      ouvert = true;
    }
    if (!averti) {
      console.log("Connecte-toi à ton compte Google dans la fenêtre Chrome ouverte par le script (attente : 10 minutes).");
      averti = true;
    }
    await attendre(2000);
  }
  throw new Error("Pas de connexion à Google Photos dans le délai imparti.");
}

export class Cdp {
  #ws;
  #id = 0;
  #enAttente = new Map();
  #ecouteurs = new Map();

  static async connecter(url) {
    const cdp = new Cdp();
    cdp.#ws = new WebSocket(url);
    await new Promise((resolve, reject) => {
      cdp.#ws.onopen = resolve;
      cdp.#ws.onerror = () => reject(new Error('Connexion à Chrome impossible.'));
    });
    cdp.#ws.onmessage = (ev) => cdp.#recevoir(JSON.parse(ev.data));
    cdp.#ws.onclose = () => {
      for (const { reject } of cdp.#enAttente.values()) reject(new Error('Chrome a été fermé pendant l’opération.'));
      cdp.#enAttente.clear();
    };
    return cdp;
  }

  #recevoir(msg) {
    if (msg.id === undefined) {
      this.#ecouteurs.get(msg.method)?.(msg.params);
      return;
    }
    const attente = this.#enAttente.get(msg.id);
    this.#enAttente.delete(msg.id);
    if (msg.error) attente?.reject(new Error(msg.error.message));
    else attente?.resolve(msg.result);
  }

  envoyer(method, params = {}) {
    const id = ++this.#id;
    this.#ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.#enAttente.set(id, { resolve, reject }));
  }

  sur(method, ecouteur) {
    this.#ecouteurs.set(method, ecouteur);
  }

  fermer() {
    this.#ws.close();
  }
}

// Connexion au navigateur lui-même (et non à un onglet) : téléchargements, onglets.
export async function connecterNavigateur() {
  const version = await debogage('/json/version');
  if (!version) throw new Error('Chrome ne répond pas.');
  return Cdp.connecter(version.webSocketDebuggerUrl);
}

export async function fermerChrome() {
  if (!(await debogage('/json/version'))) return;
  const navigateur = await connecterNavigateur();
  await navigateur.envoyer('Browser.close').catch(() => {});
}

// Requête interne du site (protocole « batchexecute »), avec deux nouvelles tentatives.
// Exécutée dans la page photos.google.com : elle ne doit rien utiliser d'extérieur.
async function creerRpc() {
  const attendre = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  for (let i = 0; !window.WIZ_global_data?.SNlM0e; i++) {
    if (i > 60) throw new Error("La page Google Photos ne s'est pas chargée. Es-tu bien connecté ?");
    await attendre(500);
  }
  const g = window.WIZ_global_data;

  return async function rpc(rpcid, donnees) {
    const params = new URLSearchParams({
      rpcids: rpcid,
      'source-path': location.pathname,
      'f.sid': g.FdrFJe,
      bl: g.cfb2h,
      pageId: 'none',
      rt: 'c',
    });
    const corps = new URLSearchParams({
      'f.req': JSON.stringify([[[rpcid, JSON.stringify(donnees), null, 'generic']]]),
      at: g.SNlM0e,
    });
    const url = `https://photos.google.com${g.eptZe ?? '/_/PhotosUi/'}data/batchexecute?${params}`;
    for (let essai = 1; ; essai++) {
      try {
        const rep = await fetch(url, { method: 'POST', body: corps, credentials: 'include' });
        if (!rep.ok) throw new Error(`HTTP ${rep.status}`);
        const ligne = (await rep.text()).split('\n').find((l) => l.includes('"wrb.fr"'));
        if (!ligne) throw new Error('réponse inattendue');
        const charge = JSON.parse(ligne)[0][2];
        return charge ? JSON.parse(charge) : null;
      } catch (e) {
        if (essai === 3) throw new Error(`requête ${rpcid} en échec : ${e.message}`);
        await attendre(2000 * essai);
      }
    }
  };
}

// Exécute `fonction(rpc, ...args)` dans l'onglet Google Photos et renvoie son résultat.
// `fonction` est envoyée telle quelle à Chrome : elle ne doit rien utiliser d'extérieur.
export async function evaluerDansPage(cdp, fonction, ...args) {
  const expression = `(async () => (${fonction})(await (${creerRpc})(), ...${JSON.stringify(args)}))()`;
  const { result, exceptionDetails } = await cdp.envoyer('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (exceptionDetails) throw new Error(exceptionDetails.exception?.description ?? exceptionDetails.text);
  return result.value;
}
