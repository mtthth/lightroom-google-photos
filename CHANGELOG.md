# Journal des versions

## 1.1.0

- **Interface en anglais** : la langue (français par défaut, ou anglais) se choisit dans Fichier → Gestionnaire de
  modules externes → Albums Google Photos. Elle s'applique aux dialogues, à la boîte d'export et aux messages de
  connexion à Google. Le titre du menu suit la langue de Lightroom. Les noms des collections ne changent pas.
- **« Google Photos - époques » devient « Google Photos - sessions ».** L'ensemble existant est renommé au premier
  passage de « Recréer les albums Google Photos… », et ses collections sont complétées comme avant. Si les deux
  ensembles existent, aucun n'est renommé.
- **Export** : le nom de l'album est prérempli avec celui de la collection ou du dossier affiché, et reste modifiable
  dans la boîte d'export.
- `rafales-a-blanc.mjs` ignore les deux noms de l'ensemble des sessions.

## 1.0.1

- « Recréer les albums Google Photos » fonctionne sans Deduplicate : quand l'historique commun
  `photos-traitees.txt` n'existe pas, les albums sont recréés avec un historique vide au lieu d'être refusés.
  Un historique présent mais pas encore repris par Deduplicate reste refusé.

## 1.0.0

Première version publique.

- Recréation des albums Google Photos en collections Lightroom, par année, avec les époques et les photos hors album.
- Correspondance avec les originaux du catalogue pour les photos que Google ne garde qu'en version réduite.
- Téléchargement des photos absentes du catalogue, en qualité originale.
- Service d'export « Google Photos » par l'API officielle : redimensionnement des photos, conversion des vidéos en
  1080p, préréglage « Google Photos 4K ».
- Licence MIT.
- **Mise à jour depuis 26.10.0 ou avant** : l'identifiant du module devient `io.github.mtthth.albumsgooglephotos`
  (il était `fr.matthieu.albumsgooglephotos`). Retirez l'ancien module du Gestionnaire de modules externes avant
  d'ajouter celui-ci, et recréez vos propres préréglages d'export « Google Photos ».
