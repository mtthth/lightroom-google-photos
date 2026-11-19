# Albums Google Photos pour Lightroom Classic

*[English version](README.en.md)*

Module externe pour **Lightroom Classic** (Windows), accompagné de scripts Node, qui fait le lien entre votre
catalogue et Google Photos, sans passer par Takeout :

- **Recrée vos albums Google Photos en collections Lightroom**, rangées par année
  (`Google Photos - albums / 2025 / 2025-07-24 – Week-end à Lyon`), et retrouve dans le catalogue les originaux
  des photos que Google ne garde qu'en version réduite.
- **Range les photos par époque** : pour chaque album, toutes les photos du catalogue prises pendant la même période,
  plus des collections intercalaires entre deux périodes.
- **Récupère les photos manquantes** : celles des albums partagés ou jamais synchronisées avec Lightroom sont
  téléchargées en qualité originale, prêtes à importer.
- **Exporte une collection vers un album Google Photos** depuis la boîte d'export de Lightroom, par l'API officielle,
  avec redimensionnement des photos et conversion des vidéos en 1080p.

Les mises à jour sont incrémentales : seuls les albums nouveaux ou modifiés sont relus, et les collections existantes
sont complétées, jamais dupliquées.

## Prérequis

- Lightroom Classic sous **Windows**.
- **Node 22 ou plus récent** ([nodejs.org](https://nodejs.org/)) et **Google Chrome**.
- **ffmpeg** : facultatif, pour convertir les vidéos à l'export (`winget install Gyan.FFmpeg`).
- Pour l'export vers Google Photos seulement : un projet Google Cloud avec un client OAuth à vous (voir le
  [mode d'emploi](LISEZ-MOI.md), section « Export Google Photos »).

## Installation

1. Téléchargez la dernière version dans [Releases](../../releases) et décompressez-la **en entier** dans un dossier où
   vous avez le droit d'écrire : le module utilise les scripts et les fichiers posés à côté de son dossier.
2. Dans Lightroom Classic : **Fichier → Gestionnaire de modules externes → Ajouter**, puis choisissez le dossier
   `albums-google-photos.lrplugin`.

## Premiers pas

1. Dans le dossier du projet, lisez vos albums Google Photos :

   ```powershell
   node export-albums.mjs
   ```

   La première fois, une fenêtre Chrome s'ouvre : connectez-vous à votre compte Google. La session est conservée dans
   un profil Chrome dédié.
2. Dans Lightroom : **Bibliothèque → Options du module externe → Recréer les albums Google Photos…**, puis choisissez
   `photos-albums-tous.csv`.
3. S'il manque des photos dans le catalogue, lancez `node telecharger-manquantes.mjs`, importez le dossier
   `photos-albums-tous-manquantes`, puis relancez l'étape 2.

Le [mode d'emploi complet](LISEZ-MOI.md) détaille chaque étape, l'export vers Google Photos, la correspondance avec
les photos réduites, les cas particuliers et les fichiers produits.

## Limites et précautions

- **Windows uniquement** : Chrome, Lightroom et les dossiers de travail sont cherchés à leurs emplacements Windows.
- **Interface et documentation en français.**
- **Lecture des albums par une interface non documentée.** L'API officielle de Google Photos ne donne plus accès aux
  albums de l'utilisateur depuis mars 2025 : `export-albums.mjs` et `telecharger-manquantes.mjs` lisent donc le site
  Google Photos à travers votre session Chrome. Ils peuvent cesser de fonctionner si Google modifie son site, et cet
  usage n'est pas approuvé par Google. L'export vers Google Photos utilise, lui, l'API officielle.
- **Connexion d'export à renouveler** : tant que votre client OAuth reste en mode « Test », Google coupe la connexion
  au bout de 7 jours ; Lightroom propose alors de se reconnecter.
- **L'export ne complète que les albums qu'il a créés** (restriction de l'API Google).
- Le module crée et complète des collections ; il ne retire aucune photo du catalogue et ne supprime aucun original.
  Comme pour tout outil qui touche un
  catalogue, **faites une sauvegarde du catalogue** avant la première utilisation.

Vos exports (CSV), les photos téléchargées et vos identifiants OAuth restent sur votre machine, dans le dossier du
projet et dans `%LOCALAPPDATA%\lightroom-google-photos` ; ils sont exclus du suivi Git.

## Module voisin facultatif

[Deduplicate](https://github.com/mtthth/lightroom-deduplicate) fusionne les doublons et réduit les rafales. Installés
dans deux dossiers voisins, `lightroom-google-photos` (nom à conserver) et `lightroom-deduplicate`, les deux modules
partagent l'historique des photos écartées : celles que Deduplicate a retirées ne réapparaissent ni dans les albums,
ni dans les époques, ni dans les téléchargements.

## Tests

```powershell
node tests/lancer.mjs             # suites Lua et JavaScript (Node 22+, texlua de MiKTeX)
node tests/lancer.mjs --js        # JavaScript seul, sans MiKTeX
node tests/lancer.mjs --mutants   # tests, puis quatre régressions contrôlées
```

Les tests tournent hors de Lightroom avec un faux Lightroom et des données synthétiques : ils n'ouvrent pas Chrome,
n'appellent pas Google et ne touchent ni à votre catalogue ni à vos exports.

## Licence

[MIT](LICENSE). Les évolutions sont décrites dans le [journal des versions](CHANGELOG.md).
