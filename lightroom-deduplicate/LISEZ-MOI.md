# Deduplicate pour Lightroom Classic

Le plugin `lightroom-deduplicate` regroupe les commandes de fusion des doublons et de réduction des rafales.

## Installation

Dans Lightroom Classic : Fichier → Gestionnaire de modules externes → Ajouter → dossier `lightroom-deduplicate`.

L’historique des photos mises de côté (`photos-traitees.txt`) est conservé à la racine du dépôt et partagé avec le plugin Albums Google Photos, qui s’en sert pour ne pas réintroduire ces photos dans les collections.

## Commandes

Dans Lightroom : Bibliothèque → Options du module externe → …

**Annuler / Rétablir.** Chaque fusion automatique, fusion forcée et réduction de rafales constitue une seule
action Lightroom : **Ctrl+Z** restaure les collections, métadonnées et mots-clés antérieurs. **Rétablir** réapplique
l'opération. L'état des exclusions est inclus dans cette action et conservé dans le catalogue ;
`photos-traitees.txt` en est le miroir, synchronisé après Annuler / Rétablir et avant toute nouvelle analyse.
Les éditions volontaires du fichier texte sont conservées comme base des opérations suivantes. Cette prise en
charge concerne les opérations réalisées à partir de la version 26.10, après rechargement du module.

### Fusionner les doublons…

Une même photo importée plusieurs fois (dossier « Désordre », copies `-2`, `-3`, `(2)`, versions `-Modifier`…).

**Vidéos aussi.** La recherche automatique fusionne les copies de fichiers vidéo strictement identiques,
même renommées ou de plus de 64 Mo. Le début et la fin servent de préfiltre pour les gros fichiers ;
l'identité est ensuite vérifiée sur tous les octets des candidats. Une vidéo convertie, recompressée,
recoupée ou dont le conteneur a changé se fusionne avec **Fusionner de force la sélection…** : choisis la
version à garder. Les collections et métadonnées sont réunies comme pour les photos ; les réglages et
les coupes vidéo restent sur leur version d'origine.

**Sur quelles photos ?** Sur les photos **sélectionnées** s'il y en a au moins deux, sinon sur toutes les photos
**affichées** dans la grille (le dossier ou la collection ouverte). Une boîte l'annonce avant de commencer. Une copie
n'est trouvée que si ses doublons sont aussi dans ces photos : sélectionne une année, un dossier parent…

La commande calcule d'abord une empreinte du contenu de toutes les photos de la portée : une empreinte identique
signale un doublon, quel que soit le nom ou la date. Pour les contenus différents, elle cherche aussi les variantes de
même nom d'origine (suffixes de copie ou de retouche ignorés : `-2`, `(2)`, `-Modifier`, `_filtered`, DxO…) et de même
date, puis compare les images par une miniature ImageMagick de 16 × 16 pixels :

- empreinte identique : doublons, on garde un seul fichier ;
- même vue en plus petit ou recompressée (miniature 16 × 16, même forme, mêmes couleurs) : on garde la
  plus grande ;
- image différente (retouche, recadrage…) : les deux sont gardées. Un nom qui annonce une retouche empêche la fusion
  par ressemblance de miniature, mais pas si l'empreinte exacte est identique.

La copie gardée est la plus grande image, puis celle qui est retouchée dans Lightroom, puis la mieux rangée. Elle prend
la place des autres dans leurs collections et récupère mots-clés, note, drapeau, position GPS, et les champs de texte
(titre, légende, auteur, lieu, ville, pays…) qu'elle n'a pas. Les autres copies vont dans la collection
« Doublons à retirer » (jamais supprimées par le module). Elles restent visibles dans les dossiers tant qu'elles
sont dans le catalogue. Pour terminer le retrait : sélectionner uniquement les copies écartées dans
**Catalogue → Toutes les photos**, puis **Suppr → Retirer**. Suppr depuis une collection peut simplement les sortir
de cette collection.
La fusion conserve la vue courante : elle n'ouvre pas automatiquement « Doublons à retirer ».
Les chemins, noms et dates des copies retirées sont aussi conservés dans `photos-traitees.txt`, à la racine du projet.
Ce fichier est exclu de git. « Recréer les albums » ignore ces photos même après vidage de la collection. Pour les
prendre de nouveau en compte, retire leur ligne de l'historique.

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

### Fusionner de force la sélection…

Pour fusionner un groupe que la détection automatique ne reconnaît pas : sélectionne ses photos, puis lance la
commande dans **Bibliothèque → Options du module externe**. Le SDK Lightroom ne permet pas d'ajouter une commande
au menu du clic droit. La commande considère toute la sélection comme une seule photo, sans comparer les fichiers.
Elle propose la plus grande résolution (lue dans le catalogue Lightroom), puis la meilleure note, puis le nom le
plus simple. Les dimensions, la note et le poids sont visibles pour chaque choix. Si les dimensions sont incomplètes,
la note et le nom priment ; le poids du fichier départage les égalités. La proposition peut être changée.
Le récapitulatif liste explicitement tous les albums après fusion, y compris ceux où la photo gardée se trouve déjà,
avec leur chemin complet (année comprise), puis les autres collections ordinaires. Les métadonnées sont réunies :
note maximale, union des mots-clés, drapeau retenu prioritaire sur rejeté, textes et GPS déjà renseignés conservés,
champs vides complétés. L'accès à l'historique est vérifié avant toute modification du catalogue.
Cette commande force aussi la fusion de versions `_filtered`, `-Modifier` ou ayant des retouches Lightroom :
la confirmation « Fusionner de force » liste les réglages, copies virtuelles ou appartenances publiées qui ne
seront pas transférés. Ils restent sur les copies écartées tant qu'elles sont au catalogue ; leur retrait ultérieur
fera perdre ces éléments. Une copie virtuelle dont l'original est également sélectionné ne peut pas être la
gardée, puisque retirer son original la retirerait aussi. Une virtuelle dont l'original est déjà dans une collection
« à retirer » ne peut pas non plus être gardée : rétablis d'abord son original. Les copies virtuelles écartées n'excluent pas leur
fichier source de l'historique. Les copies fusionnées rejoignent « Doublons à retirer » et leurs fichiers sont
mémorisés dans `photos-traitees.txt`. La vue courante reste affichée après la fusion.
Si la photo gardée avait déjà été mise à retirer, la fusion la rétablit : elle sort de « Doublons à retirer » et de
« Rafales à retirer », et son chemin est enlevé des exclusions de `photos-traitees.txt`. L'ancien historique est
conservé dans un fichier `.bak`. La commande vérifie que la gardée n'est plus dans une collection de retrait
avant d'annoncer la réussite. Pour réparer un ancien groupe où toutes les copies avaient été écartées, relancer
la fusion forcée sur le groupe et confirmer la photo à garder.

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
- Les fichiers des cadres retirés sont aussi inscrits dans `photos-traitees.txt`, à la racine du projet. Le module
  les ignore lors des prochaines réductions et « Recréer les albums » ne les réintroduit pas après vidage de la
  collection. Pour les reprendre en compte, retire leurs lignes du fichier ; pour retraiter la rafale, ôte aussi le
  mot-clé « Rafale traitée » de toutes ses photos.
- Ctrl+Z annule ensemble la mise à l'écart, le mot-clé et l'historique. La vue courante reste affichée.

Pour juger un dossier sans toucher à Lightroom, `node rafales-a-blanc.mjs 2026-08-15` produit un rapport HTML avec
les miniatures (options : `--sous-dossiers`, `--bloc N`, `--ignorer "collection"` ; Node 22.13 ou plus). Il lit le
catalogue en lecture seule et applique les mêmes règles que la commande.

## Tests

Depuis la racine du dépôt, `node tests/lancer.mjs` lance les suites hors de Lightroom. `node tests/lancer.mjs --mutants` vérifie ensuite que les tests détectent les régressions connues.
