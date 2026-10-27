# Albums Google Photos → collections Lightroom Classic

Recrée dans Lightroom Classic les albums de Google Photos (sans passer par Takeout) :

- **Google Photos - albums** : une collection par album, rangée par année
  (`2025 / 2025-07-24 – Gien dans le Loiret`).
- **Google Photos - époques** : pour chaque album, toutes les photos du catalogue prises entre sa première et sa
  dernière photo, plus des collections « Intercalaire jusqu'au… » dans les trous entre deux périodes.

Les photos de Google Photos qui ne sont dans **aucun album** sont rangées dans une collection `(hors album)` à l'intérieur
de chaque année (`Google Photos - albums / 2019 / (hors album)`, année de la photo, ou `Sans date`). Comme toutes les
photos du catalogue prises pendant une époque en font partie, elles se retrouvent aussi dans la bonne époque.

La date du nom est celle du titre de l'album s'il en porte une (`110909. Méchoui`, `2025.07.24 Gien…`,
`20260423. Saint-Tropez`…), sinon celle de sa première photo. L'ancien préfixe de date est retiré du titre.

## Ce qu'il faut

- Node 22 ou plus récent, et Chrome.
- Le module Lightroom : Fichier → Gestionnaire de modules externes → Ajouter → dossier `albums-google-photos.lrplugin`.
- La première fois, `export-albums.mjs` ouvre une fenêtre Chrome : connecte-toi à ton compte Google
  (la session est conservée dans un profil dédié, `%LOCALAPPDATA%\lightroom-google-photos\chrome-profile`).

## Mise à jour (tous les quelques mois)

Rien n'est refait : chaque étape ne traite que les nouveautés.

1. **Lire les albums Google Photos** (de 1 à quelques minutes si peu de choses ont changé) :

   ```
   node export-albums.mjs
   ```

   Seuls les albums nouveaux ou modifiés (renommés, photos ajoutées ou retirées) sont relus ; les autres sont repris
   du fichier précédent. Résultat : `albums-tous.csv` et `photos-albums-tous.csv`.

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

## Autres commandes du module

Dans Lightroom : Bibliothèque → Options du module externe → …

### Fusionner les doublons…

Une même photo importée plusieurs fois (dossier « Désordre », copies `-2`, `-3`, `(2)`, versions `-Modifier`…).

**Sur quelles photos ?** Sur les photos **sélectionnées** s'il y en a au moins deux, sinon sur toutes les photos
**affichées** dans la grille (le dossier ou la collection ouverte). Une boîte l'annonce avant de commencer. Une copie
n'est trouvée que si ses doublons sont aussi dans ces photos : sélectionne une année, un dossier parent…

La commande cherche les photos de même nom d'origine (les suffixes de copie ou de retouche sont ignorés : `-2`,
`(2)`, `-Modifier`, `-Modifié-2026-08-02T22-37-43`, `_filtered`, `-20260821-DxO_DeepPRIME XD3`) et de même date de
prise de vue, puis compare les **images**, pas les fichiers (des métadonnées XMP différentes ne font pas des fichiers
différents) :

- image identique : doublons, on garde un seul fichier ;
- même vue en plus petit ou recompressée (miniature ImageMagick de 16 × 16, même forme, mêmes couleurs) : on garde la
  plus grande ;
- image différente (retouche, recadrage…) : les deux sont gardées ; un fichier dont le nom annonce une retouche n'est
  jamais retiré.

La copie gardée est la plus grande image, puis celle qui est retouchée dans Lightroom, puis la mieux rangée. Elle prend
la place des autres dans leurs collections et récupère mots-clés, note, drapeau, position GPS, et les champs de texte
(titre, légende, auteur, lieu, ville, pays…) qu'elle n'a pas. Les autres copies vont dans la collection
« Doublons à retirer » (jamais supprimées par le module : Ctrl+A, Suppr dans cette collection).
« Recréer les albums » ignore cette collection tant qu'elle contient des copies.

**Rapport HTML avant toute modification.** Après l'analyse, le module écrit `rapport-doublons\index.html` et propose
de le voir (bouton « Voir le rapport », il s'ouvre dans le navigateur) avant que tu confirmes. Pour chaque groupe : les
miniatures des copies, la copie gardée et pourquoi (« la plus grande image », « retouchée dans Lightroom », « dossier
mieux rangé »…), ce qui est retiré, les collections que la copie gardée rejoint ou que les copies retirées quittent,
les mots-clés, la note, le drapeau, les textes et la position GPS recopiés. Il montre aussi les groupes « à vérifier »
(rien n'est fait pour eux) et les versions conservées à part. Les chiffres clés (copies retirées, Go libérés,
collections modifiées) ouvrent la page, et une barre de filtre cherche par nom ou dossier. Le rapport est construit à partir du même plan
que celui qui est appliqué ensuite : il ne peut pas annoncer autre chose. Les miniatures sont des aperçus JPEG de
220 pixels écrits dans `rapport-doublons\vignettes\` (réutilisés d'un rapport à l'autre ; case à décocher dans la
boîte de départ pour s'en passer). Le détail est aussi dans `doublons.csv`.

### Réduire les rafales…

Affiche un dossier ou une collection, puis lance la commande (réglages : 1 cadre sur 4, sous-dossiers).

- Une rafale = au moins 3 cadres à une seconde d'écart au plus, avec des numéros de fichier voisins (RAW + JPEG et
  copies `-2` comptent pour un cadre).
- Chaque rafale est découpée en blocs de 4 cadres ; on garde le plus net de chaque bloc (netteté mesurée par
  ImageMagick).
- Sont toujours gardés, en plus : les cadres dans une collection autre que « Google Photos - époques » (les albums
  Google comptent), notés, avec drapeau ou libellé, retouchés dans Lightroom, avec copies virtuelles, publiés, ou
  qui ont une version retouchée dans un éditeur externe.
- Les autres cadres (tous leurs fichiers) vont dans la collection « Rafales à retirer » après confirmation, avec le
  détail dans `rafales.csv`. Rien n'est supprimé par le module.
- Toutes les photos des rafales traitées reçoivent le mot-clé « Rafale traitée » (non exporté) : une relance les
  ignore, même une fois la collection vidée. Pour retraiter une rafale, ôte ce mot-clé de ses photos.

Pour juger un dossier sans toucher à Lightroom, `node rafales-a-blanc.mjs 2026-08-15` produit un rapport HTML avec
les miniatures (options : `--sous-dossiers`, `--bloc N`, `--ignorer "collection"` ; Node 22.13 ou plus). Il lit le
catalogue en lecture seule et applique les mêmes règles que la commande.

### Export « Google Photos » (envoyer une collection)

Dans la boîte d'export de Lightroom, le service « Google Photos » envoie les photos exportées dans un album, par l'API
officielle. Préréglage fourni : « Google Photos 4K » (JPEG de 4096 pixels, qualité 75, mêmes noms de fichier que les
exports habituels).

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
node tests/lancer.mjs             # les six suites (une minute)
node tests/lancer.mjs --mutants   # puis casse une règle à la fois : les tests doivent échouer (quelques minutes)
```

Ils tournent hors de Lightroom avec `texlua` (le Lua de MiKTeX ; variable `TEXLUA` pour un autre chemin), un faux
Lightroom et le vrai ImageMagick.

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
- Les noms de collection ne peuvent pas contenir certains caractères : le module les remplace par « - » si
  Lightroom refuse le titre.
- Les requêtes de Google Photos utilisées ne sont pas documentées : si Google modifie son site, `export-albums.mjs`
  et `telecharger-manquantes.mjs` peuvent cesser de fonctionner et devront être adaptés.

## Fichiers

| Fichier | Rôle |
|---|---|
| `export-albums.mjs` | Liste les albums et leurs photos (`node export-albums.mjs [année]`) |
| `telecharger-manquantes.mjs` | Télécharge les photos absentes du catalogue |
| `chrome.mjs`, `csv.mjs` | Code commun aux deux scripts |
| `connexion-google-photos.mjs` | Connexion à Google pour l'export « Google Photos » (lancé par le module au besoin) |
| `rafales-a-blanc.mjs` | Rapport HTML des rafales d'un dossier, sans rien modifier |
| `albums-google-photos.lrplugin` | Module Lightroom. Recréer les albums : `RecreerAlbums.lua` (principal), `Correspondance.lua` (retrouver une photo), `Epoques.lua` (périodes), `Noms.lua` (noms des collections). Doublons : `FusionnerDoublons.lua`, `Doublons.lua`, `Empreintes.lua`, `Similitude.lua`, `RapportHtml.lua` (page du rapport). Rafales : `ReduireRafales.lua`, `Rafales.lua`. Export Google Photos : `ServiceGooglePhotos.lua`, `GooglePhotos.lua`, `Json.lua`, `presets\`. Commun : `Vignettes.lua` (ImageMagick), `Parallele.lua`, `Catalogue.lua`, `Csv.lua` |
| `tests\` | Tests du module, hors de Lightroom (`node tests/lancer.mjs`) |
| `albums-tous.csv`, `photos-albums-tous.csv` | Export des albums (inutile d'y toucher) |
| `photos-hors-album.csv` | Photos de la bibliothèque qui ne sont dans aucun album, au même format |
| `photos-albums-tous-non-trouvees.csv` | Photos que le module n'a pas retrouvées dans le catalogue |
| `photos-albums-tous-manquantes\` | Photos téléchargées, avec `telechargements.csv` |
