# Albums Google Photos → collections Lightroom Classic

Recrée dans Lightroom Classic les albums de Google Photos (sans passer par Takeout) :

- **Google Photos - albums** : une collection par album, rangée par année
  (`2025 / 2025-07-24 – Week-end à Lyon`).
- **Google Photos - époques** : pour chaque album, toutes les photos du catalogue prises entre sa première et sa
  dernière photo, plus des collections « Intercalaire jusqu'au… » dans les trous entre deux périodes.

Les photos de Google Photos qui ne sont dans **aucun album** sont rangées dans une collection `(hors album)` à l'intérieur
de chaque année (`Google Photos - albums / 2019 / (hors album)`, année de la photo, ou `Sans date`). Comme toutes les
photos du catalogue prises pendant une époque en font partie, elles se retrouvent aussi dans la bonne époque.

La date du nom est celle du titre de l'album s'il en porte une (`110909. Mariage`, `2025.07.24 Lyon…`,
`20260423. Plage`…), sinon celle de sa première photo. L'ancien préfixe de date est retiré du titre.

## Ce qu'il faut

- Node 22 ou plus récent, et Chrome.
- Le module Lightroom : Fichier → Gestionnaire de modules externes → Ajouter → dossier `albums-google-photos.lrplugin`.
- La première fois, `export-albums.mjs` ouvre une fenêtre Chrome : connecte-toi à ton compte Google
  (la session est conservée dans un profil dédié, `%LOCALAPPDATA%\lightroom-google-photos\chrome-profile`).

**Mise à jour depuis une version antérieure à 1.0 (26.10.0 ou avant).** L'identifiant du module est devenu
`io.github.mtthth.albumsgooglephotos` (il était `fr.matthieu.albumsgooglephotos`). Lightroom le voit comme un
nouveau module : retire l'ancien du Gestionnaire de modules externes avant d'ajouter celui-ci. Les collections
déjà créées et la connexion à Google Photos sont conservées ; les préréglages d'export « Google Photos » que tu
as enregistrés toi-même sont à recréer à partir du préréglage fourni « Google Photos 4K ».

## Mise à jour (tous les quelques mois)

Rien n'est refait : chaque étape ne traite que les nouveautés.

1. **Lire les albums Google Photos** (de 1 à quelques minutes si peu de choses ont changé) :

   ```
   node export-albums.mjs
   ```

   Seuls les albums nouveaux ou modifiés (renommés, photos ajoutées ou retirées) sont relus ; les autres sont repris
   du fichier précédent. Résultat : `albums-tous.csv` et `photos-albums-tous.csv`.

   Une réponse Google invalide, une pagination répétée ou un nombre de photos incohérent arrête l'export
   avant de remplacer les fichiers précédents. Relance le script pour réessayer. Les anciens exports dont
   le compte ne correspond pas à leur signature Google sont automatiquement relus en entier.

   Le script liste aussi toute la bibliothèque (une ou deux minutes pour environ 70 000 photos) et en déduit les
   photos qui ne sont dans aucun album (`photos-hors-album.csv`). Une photo est « dans un album » si son identifiant
   ou l'empreinte de son contenu figure dans un album, ce qui couvre les photos partagées, dont l'identifiant change
   d'un album à l'autre.

2. **Lightroom : Bibliothèque → Options du module externe → Recréer les albums Google Photos…**
   et choisir `photos-albums-tous.csv` (le module lit aussi `photos-hors-album.csv`, placé à côté).
   Les collections existantes sont complétées, pas dupliquées. Le message final indique combien de photos n'ont pas
   été retrouvées dans le catalogue (elles sont listées dans `photos-albums-tous-non-trouvees.csv`).

3. **S'il y a des photos introuvables** (typiquement des photos d'autres personnes dans un album partagé, ou jamais
   synchronisées avec Lightroom) :

   ```
   node telecharger-manquantes.mjs
   ```

   Les photos sont téléchargées en qualité originale dans `photos-albums-tous-manquantes\`. Ce qui est déjà
   téléchargé n'est pas retéléchargé.

4. **Importer ces photos dans Lightroom, puis relancer le module** (étape 2) :
   - S'il n'y en a qu'une poignée, le module les importe lui-même (il suffit de le relancer).
   - S'il y en a plus d'une cinquantaine, utilise plutôt l'import de Lightroom (Fichier → Importer des photos et
     vidéos, source `photos-albums-tous-manquantes`, avec « Ne pas importer les doublons suspects »), puis relance le
     module : l'import par le module prend environ 4 secondes par photo sur un gros catalogue, celui de Lightroom
     quelques minutes pour un millier. Choisis « Copier » pour les ranger dans ton dossier photo, ou « Ajouter »
     pour les laisser sur place.

S'il n'y a aucune photo introuvable à l'étape 2, les étapes 3 et 4 sont inutiles.

## Photos envoyées en basse définition depuis le téléphone

Quand Google Photos contient une version réduite d'une photo dont Lightroom a l'original (JPEG, RAF…), le module
retrouve l'original et ne télécharge rien : par le nom de fichier (en ignorant la date en préfixe, les dimensions
`-4032 x 3024`, `__4096px`, `-2`, `~2`, l'extension), puis, pour les noms que le téléphone aurait changés, par
l'heure de prise de vue à la seconde. Si Lightroom a un RAF et un JPEG du même cliché, c'est celui qui a la même
extension que le fichier Google qui est mis dans la collection d'album (les deux sont dans l'époque).

## Déduplication

Les commandes de fusion des doublons et de réduction des rafales sont dans le dépôt séparé
[`lightroom-deduplicate`](https://github.com/mtthth/lightroom-deduplicate). Les deux projets doivent être voisins :

```text
projets/
  lightroom-google-photos/
    albums-google-photos.lrplugin/
    photos-traitees.txt
  lightroom-deduplicate/
    lightroom-deduplicate.lrplugin/
```

Ajoute les deux dossiers `.lrplugin` au gestionnaire de modules externes de Lightroom et active-les.
Après leur mise à jour, redémarre Lightroom. Deduplicate initialise et synchronise seul l’historique commun
`lightroom-google-photos/photos-traitees.txt`, y compris après Annuler / Rétablir. Google Photos le lit pour
que les photos écartées ne réapparaissent pas dans les albums, les époques ou les téléchargements.
Si le module signale un historique non initialisé, recharge Deduplicate avant de recréer les albums.

### Export « Google Photos » (envoyer une collection)

Dans la boîte d'export de Lightroom, le service « Google Photos » envoie les photos exportées dans un album, par l'API
officielle. Préréglage fourni : « Google Photos 4K » (JPEG de 4096 pixels, qualité 75, mêmes noms de fichier que les
exports habituels, vidéos converties en 1080p).

La section « Google Photos » de la boîte d'export règle aussi :

- **Photos** : grand côté limité à 4096, 2048 ou 1600 pixels (sans agrandir), taille d'origine, ou « Selon
  Dimensionnement de l'image » pour garder les réglages de cette section de Lightroom (choix par défaut des
  préréglages antérieurs). Le choix se reporte dans la section « Dimensionnement de l'image ».
- **Vidéos** : non envoyées (par défaut), converties en 1080p léger, ou envoyées telles que Lightroom les exporte
  (section « Vidéo »). La conversion demande ffmpeg (`winget install Gyan.FFmpeg`) : MP4 H.264 et AAC 128 kbit/s,
  petit côté ramené à 1080 pixels, 30 images/s et 6 Mbit/s au plus, date de prise de vue et rotation conservées,
  vidéos HDR d'iPhone ramenées en SDR. Lightroom fournit pour cela le fichier d'origine : les découpes faites dans
  Lightroom ne sont pas appliquées. Dans l'album, la vidéo garde le nom d'export avec l'extension `.mp4`.

1. **Une fois** : créer un projet Google Cloud, activer « Photos Library API », créer un client OAuth « Application de
   bureau » et poser `client_secret_….json` dans ce dossier (les étapes sont en tête de `connexion-google-photos.mjs`).
   Ce fichier est un secret : il est exclu de git.
2. Sélectionner les photos d'une collection, puis Fichier → Exporter → « Google Photos 4K ». L'album porte le nom
   de la collection affichée (ou celui saisi dans la boîte d'export).
3. Au premier envoi, Lightroom ouvre le navigateur pour la connexion à Google. En mode « Test », Google coupe la
   connexion au bout de 7 jours : ajoute ton adresse comme utilisateur test ; Lightroom propose de se reconnecter.

Un nouvel envoi complète l'album créé par le service sans renvoyer les photos dont le nom de fichier y figure déjà.
Depuis mars 2025, l'API ne permet de compléter que les albums créés par l'application elle-même.

## Tests

```
node tests/lancer.mjs             # quatre suites Lua et quatre suites JavaScript
node tests/lancer.mjs --js        # JavaScript seul, sans MiKTeX
node tests/lancer.mjs --mutants   # puis vérifie quatre régressions de recréation des albums
```

Ils tournent sous Windows, hors de Lightroom, avec `texlua` (le Lua de MiKTeX ; variable `TEXLUA` pour un autre
chemin) et un faux Lightroom. Ils n’ouvrent pas Chrome, n’appellent pas Google et n’utilisent pas ton catalogue
ni tes exports personnels. Les suites Lua vérifient la recréation des albums, les exclusions de l’historique,
les empreintes de fichiers, le service d’export (taille des photos, conversion et envoi des vidéos avec un faux
ffmpeg) et le JSON. Les tests JavaScript vérifient les règles du rapport
des rafales à blanc et la reprise des exports incrémentaux. Les tests de Deduplicate se lancent depuis son
propre dépôt ; aucun checkout de Deduplicate n’est nécessaire pour tester Google Photos.
Les suites JavaScript couvrent aussi la reprise des conversions vidéo et l'arrêt des téléchargements sur erreur.

## À savoir

- **Album renommé** : une nouvelle collection est créée, l'ancienne reste (à supprimer à la main).
- **Photo retirée d'un album Google Photos** : elle reste dans la collection Lightroom.
- **Photos importées par le module : « sur place »** : ne déplace pas et ne supprime pas
  `photos-albums-tous-manquantes\` (sinon, Lightroom les signale manquantes). Si tu les as importées avec
  « Copier », le dossier peut être supprimé.
- **Live Photos d'iPhone** : Google les livre dans un zip (photo + courte vidéo). Le script garde la photo seule.
- **Vidéos et formats non pris en charge** : Google transcode parfois les vidéos en VP9 (conteneur MOV ou MP4), que
  Lightroom ne lit pas, et les vidéos iPhone en 4K 60 images/s HEVC lui posent aussi problème. Lightroom refuse
  aussi les BMP. Ces fichiers restent dans `photos-albums-tous-non-trouvees.csv`. Pour les récupérer : installer
  ffmpeg (`winget install Gyan.FFmpeg`), convertir (`ffmpeg -i entree.MOV -map 0:v:0 -map 0:a:0? -map_metadata 0
  -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac sortie.mp4`, ou `ffmpeg -i x.bmp -q:v 2 x.jpg`), puis mettre le
  chemin du fichier converti dans la dernière colonne de la ligne correspondante de
  `photos-albums-tous-manquantes\telechargements.csv` et relancer le module.
- **Albums plus longs que 45 jours** (album annuel, album de plusieurs années…) : ils ont leur collection d'album mais
  ne créent ni époque ni période intercalaire. La limite est la constante `DUREE_MAX_EPOQUE_JOURS` en haut de
  `albums-google-photos.lrplugin\RecreerAlbums.lua` (`nil` pour aucune limite).
- **Deux albums de même titre** portent le même nom de collection : le second est suffixé « (2) ».
  Ils sont distingués par leur identifiant Google (les anciens CSV sans identifiant restent lisibles).
  Si une ancienne version a déjà mélangé leurs photos, supprime les collections concernées puis relance le
  module pour les recréer : la mise à jour complète les collections existantes sans en retirer les photos.
- Les noms de collection ne peuvent pas contenir certains caractères : le module les remplace par « - » si
  Lightroom refuse le titre. Si plusieurs titres deviennent identiques après ce remplacement, un suffixe
  « (2) », « (3) »… les distingue dans les albums comme dans les époques.
- **Conversions vidéo** : `convertir-videos.mjs` conserve dans le dossier de sortie un fichier `conversions.json`
  qui associe chaque source à sa vidéo convertie. Garde ce fichier pour reprendre les conversions, même si le
  journal change d'ordre ou ne contient plus qu'une partie des sources. Une ancienne sortie sans correspondance
  est conservée ; la nouvelle conversion prend un nom suffixé.
- **Rapport de rafales à blanc** : les dossiers et les séries de noms de fichiers sont traités séparément.
  `IMG_0123` et `DSCF0123` restent deux cadres, même s'ils ont été pris à la même seconde.
- Les requêtes de Google Photos utilisées ne sont pas documentées : si Google modifie son site, `export-albums.mjs`
  et `telecharger-manquantes.mjs` peuvent cesser de fonctionner et devront être adaptés.

## Fichiers

| Fichier | Rôle |
|---|---|
| `export-albums.mjs` | Liste les albums et leurs photos (`node export-albums.mjs [année]`) |
| `telecharger-manquantes.mjs` | Télécharge les photos absentes du catalogue |
| `chrome.mjs`, `csv.mjs` | Code commun aux deux scripts |
| `connexion-google-photos.mjs` | Connexion à Google pour l'export « Google Photos » (lancé par le module au besoin) |
| `rafales-a-blanc.mjs`, `rafales-regles.mjs` | Rapport HTML des rafales d'un dossier et ses règles, sans rien modifier |
| `albums-google-photos.lrplugin` | Plugin Lightroom Albums Google Photos : recréation des albums (`RecreerAlbums.lua`, `Correspondance.lua`, `Epoques.lua`, `Noms.lua`) et export (`ServiceGooglePhotos.lua`, `GooglePhotos.lua`, `Videos.lua`, `Json.lua`, `presets\`) |
| Dépôt voisin [`lightroom-deduplicate`](https://github.com/mtthth/lightroom-deduplicate) | Plugin autonome de fusion des doublons et de réduction des rafales |
| `tests\` | Tests autonomes de Google Photos, hors de Lightroom (`node tests/lancer.mjs`) |
| `albums-tous.csv`, `photos-albums-tous.csv` | Export des albums (inutile d'y toucher) |
| `photos-hors-album.csv` | Photos de la bibliothèque qui ne sont dans aucun album, au même format |
| `photos-albums-tous-non-trouvees.csv` | Photos que le module n'a pas retrouvées dans le catalogue |
| `photos-albums-tous-manquantes\` | Photos téléchargées, avec `telechargements.csv` |
