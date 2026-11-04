# Albums Google Photos pour Lightroom Classic

Recrée les albums Google Photos en collections Lightroom, récupère les photos manquantes et exporte une
collection Lightroom vers Google Photos.

Le mode d’emploi complet est dans [LISEZ-MOI.md](LISEZ-MOI.md).

La fusion des doublons et la réduction des rafales sont maintenues dans le dépôt séparé
[lightroom-deduplicate](https://github.com/mtthth/lightroom-deduplicate). Les deux projets s’installent côte à
côte et partagent l’historique des photos écartées ; chaque dépôt possède ses propres tests.

```powershell
node tests/lancer.mjs             # Windows, Node 22+, MiKTeX
node tests/lancer.mjs --js        # sans MiKTeX
node tests/lancer.mjs --mutants   # tests et quatre régressions contrôlées
```

Les exports personnels, les photos, l’historique et les secrets OAuth sont exclus du suivi Git.
