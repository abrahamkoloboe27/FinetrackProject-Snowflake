# FAQ

## Branches et environnements

### Pourquoi « staging » et pas « stagging » ?

`staging` est l'orthographe standard, celle qu'attendent les outils et les habitudes de l'équipe. La branche, l'environnement GitHub et la target dbt s'appellent tous `staging`.

### Quelle différence entre la branche staging et le schéma STAGING ?

Ce sont deux choses distinctes qui portent le même mot :

- la **couche staging** du projet dbt (`models/staging/`) est construite, en production, dans le schéma `STAGING` ;
- l'**environnement de recette** `staging` (la branche du même nom) construit ses modèles dans `PREPROD_STAGING` et `PREPROD_MARTS`.

Voir [Environnements](environnements.md#vue-densemble).

### Pourquoi mes modèles sont-ils dans DEV_ABRAHAM_STAGING et pas dans STAGING ?

C'est voulu : hors production, la macro `generate_schema_name` préfixe chaque schéma par celui de votre profil. Chacun travaille dans ses propres schémas sans écraser ceux des autres ni la production. Voir [La macro generate_schema_name](environnements.md#la-macro-generate_schema_name).

### Puis-je pousser directement sur dev ?

Non. `dev`, `staging` et `main` n'acceptent que des pull requests dont les checks sont verts. Les administrateurs peuvent contourner les règles, mais ce contournement est réservé au cas du mainteneur seul (voir [Workflow Git](workflow-git.md#protections-des-branches)).

### Pourquoi un squash vers dev, mais un merge commit vers staging et main ?

Le squash donne sur `dev` un commit par PR, au message propre (le titre de la PR). Entre branches longues, au contraire, il faut conserver l'historique : un squash de `dev` vers `staging` créerait un commit inconnu de `dev`, et les deux branches divergeraient à chaque release.

### Comment savoir ce qui partira à la prochaine release ?

```bash
git fetch origin
git log origin/staging..origin/dev --oneline     # ce que la release dev → staging apportera
git log origin/main..origin/staging --oneline    # ce que la release staging → main apportera
```

## CI/CD

### Pourquoi le job dbt build (CI) est-il « skipped » ?

Il ne tourne pas pour :

- une PR en brouillon : passez-la en « Ready for review » (`gh pr ready <n>`), le build démarre ;
- une PR venant d'un fork, qui n'a pas accès aux secrets ;
- une PR de Dependabot, qui ne reçoit que les secrets Dependabot (voir [Secrets](secrets.md#dependabot)).

Un job ignoré compte comme réussi pour les rulesets. Pour une PR de fork ou une montée de version de dbt, le relecteur lance le build lui-même (`gh pr checkout <n>`, puis `make build`) avant de fusionner.

### Le run quotidien attend une approbation

Si l'environnement `prod` exige un relecteur (option `--prod-reviewer` de `scripts/setup_github.sh`), **chaque** job qui déclare cet environnement attend son approbation, y compris le run planifié de 05:00 UTC. Deux choix :

- approuver chaque matin (bouton **Review deployments** de l'exécution) ;
- ou ne pas exiger de relecteur sur `prod` et s'appuyer sur la revue obligatoire des PR vers `main`.

Un run approuvé tard construit la pointe de `main` du moment, jamais du code périmé. S'il attend depuis des heures et qu'un déploiement vient d'avoir lieu, rejetez-le plutôt.

### Pourquoi ma PR vers dev ne reconstruit-elle que quelques modèles ?

C'est la Slim CI : seuls les modèles modifiés et leurs descendants sont reconstruits, les autres sont lus en production. Les PR vers `staging` et `main` reconstruisent tout. Voir [CI/CD](ci-cd.md#slim-ci).

### Puis-je utiliser ci/profiles.yml sur mon poste ?

Oui, pour reproduire exactement les conditions de la CI. Exportez les variables `SNOWFLAKE_*` (voir [Secrets](secrets.md#verifier)), puis :

```bash
export DBT_PROFILES_DIR=ci DBT_TARGET=ci DBT_CI_SCHEMA=DEV_ABRAHAM
dbt build
```

N'utilisez **jamais** `DBT_TARGET=dev`, `staging` ou `prod` avec ce profil depuis votre poste : ces cibles écrivent dans les schémas partagés des environnements.

### Le catalogue dbt en ligne n'affiche pas les types des colonnes

Le workflow Docs est passé en mode hors ligne : sans secrets Snowflake au niveau du dépôt, il génère la documentation sans interroger Snowflake. Modèles, descriptions, tests et lineage sont présents, mais pas les métadonnées lues dans l'entrepôt. Ajoutez les secrets puis `gh workflow run docs.yml --ref main`.

### Combien coûte la CI ?

Tous les environnements partagent l'entrepôt XS `FINTRACK_WH`, qui s'éteint après 60 secondes d'inactivité. Un build complet dure environ une minute, et la Slim CI réduit les builds des PR vers `dev`. La requête de suivi par `query_tag` est dans [Environnements](environnements.md#couts).

## dbt

### Comment ajouter un package dbt ?

Ajoutez-le dans `packages.yml`, puis `dbt deps` : dbt met à jour `package-lock.yml`. Committez les deux fichiers. Le cache de `dbt_packages/` de la CI est indexé sur eux : il se renouvelle tout seul.

### Comment mettre à jour dbt ?

Dependabot propose chaque semaine les nouvelles versions de `requirements*.txt` par PR vers `dev`. Gardez `dbt-core` et `dbt-snowflake` sur la même version mineure, lisez leur changelog, et laissez la CI valider : `dbt parse` signale les syntaxes dépréciées.

### Un modèle supprimé disparaît-il de Snowflake ?

Non. dbt ne supprime jamais un objet qu'il ne connaît plus. Après la fusion d'une PR qui supprime ou renomme un modèle, supprimez l'ancien objet dans chaque environnement (`drop view` / `drop table`, avec `FINTRACK_ROLE`), et signalez-le dans la PR. Les schémas `CI_PR_*` sont supprimés en entier à la fermeture de la PR, rien à faire pour eux.

### Pourquoi dbt build plutôt que dbt run puis dbt test ?

`dbt build` exécute chaque test juste après son modèle et n'exécute pas les modèles en aval d'un test en échec : une erreur ne se propage pas dans les marts. Après une modification des données sources, relancez `dbt build` et non `dbt test` seul : les tests des marts portent sur les tables telles qu'elles ont été construites la dernière fois.

## Questions du sujet

### Quelle différence entre vue, table et éphémère ?

Une *vue* stocke la requête et la rejoue à chaque lecture : toujours à jour, mais recalculée. Une *table* stocke le résultat : rapide à lire, mise à jour à chaque `dbt run`. Un modèle *éphémère* ne crée aucun objet : dbt l'injecte comme CTE dans les modèles qui l'utilisent. D'où les choix : vues pour le staging (données changeantes, calcul léger), éphémère pour les jointures intermédiaires (jamais lues directement), tables pour les marts (lus souvent par la BI).

### Pourquoi séparer staging, intermediate et marts ?

Chaque couche a une seule responsabilité : le staging isole le contact avec les sources (si une colonne change à la source, un seul fichier est à corriger), l'intermediate factorise les jointures, les marts exposent des modèles finaux et stables à la BI. Cela rend les modèles lisibles, réutilisables et testables à la bonne étape.

### Quel avantage pour le test relationships ?

Snowflake n'applique pas les clés étrangères. Le test vérifie l'intégrité référentielle : une transaction qui pointe vers un compte ou une catégorie inexistants est détectée avant de fausser les agrégats des marts.
