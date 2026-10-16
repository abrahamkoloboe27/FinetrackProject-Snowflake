# Journal des modifications

Toutes les évolutions notables du projet sont consignées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et les versions suivent le [versionnage sémantique](https://semver.org/lang/fr/). La version courante est celle de `dbt_project.yml` : à chaque fusion dans `main`, le workflow CD crée le tag `v<version>` et la release GitHub si elle n'existe pas encore. Avant une release, déplacez le contenu de « Non publié » sous le nouveau numéro de version.

## [Non publié]

## [1.1.0] - 2026-10-16

### Ajouté

- CI GitHub Actions sur chaque pull request vers `dev`, `staging` et `main` : `Lint` (pre-commit), `dbt parse` (sans connexion), `Docs build`, `dbt build (CI)` dans des schémas Snowflake jetables `CI_PR_<n>_*`, avec Slim CI vers `dev` (modèles modifiés et descendants, `--defer --favor-state` sur la production).
- Contrôle `PR policy` : flux de branches autorisés et titres Conventional Commits.
- CD : déploiement de `dev`, `staging` et `main` dans les environnements GitHub `dev`, `staging` et `prod` ; release `v<version>` automatique ; détection des back-merges à faire après un hotfix.
- Run quotidien de la production (05:00 UTC) et nettoyage des schémas de CI (à la fermeture de chaque PR et chaque lundi).
- Site de documentation de l'équipe (MkDocs Material), publié sur GitHub Pages avec le catalogue dbt sous `/dbt/`.
- Profil dbt de la CI versionné, sans secret (`ci/profiles.yml`), avec authentification par paire de clés RSA ou par mot de passe.
- Macro `drop_ci_schemas` pour supprimer les schémas de CI sans risque de toucher aux autres.
- Script `snowflake/04_ci_cd.sql` : droit `CREATE SCHEMA` pour `FINTRACK_ROLE`, utilisateur de service `FINTRACK_CI_USER`, rotation de clé.
- Outillage : `Makefile`, hooks pre-commit (sqlfluff, yamllint, shellcheck, actionlint...), dépendances Python épinglées, Python 3.12.
- Organisation de l'équipe : modèles de PR et d'issues, `CODEOWNERS`, Dependabot, rulesets de protection des branches, `scripts/setup_github.sh`.
- `CONTRIBUTING.md` et ce journal.

### Modifié

- `generate_schema_name` : hors production, le schéma de la target sert de préfixe (`DEV_ABRAHAM_STAGING`, `PREPROD_MARTS`, `CI_PR_12_MARTS`). La target `prod` écrit toujours dans `STAGING` et `MARTS`. **Action requise** : un profil local sur `schema: STAGING` doit passer à `DEV_<PRENOM>` (dbt s'arrête avec un message tant que le profil n'est pas corrigé), et la section 1 de `snowflake/04_ci_cd.sql` doit être exécutée (droit `CREATE SCHEMA`).
- README : badges, lien vers le site, structure du dépôt, profil local sur un schéma `DEV_<PRENOM>`, section « Travailler en équipe / CI-CD », sécurité de la CI.
- Version du projet dans `dbt_project.yml` : 1.1.0.

## [1.0.0] - 2026-10-05

### Ajouté

- Scripts Snowflake `00` à `03` : entrepôt, base `FINTRACK_DB`, schémas `RAW` / `STAGING` / `MARTS`, rôle et utilisateur, tables sources, données d'exemple, contrôles.
- Projet dbt : 4 sources, 4 vues staging, 1 modèle intermédiaire éphémère, 5 tables marts et 53 tests (packages `dbt_utils` et `codegen`).
- README : architecture, démarrage, modèles, tests, choix de conception et résultats attendus.

[Non publié]: https://github.com/abrahamkoloboe27/FinetrackProject-Snowflake/compare/v1.1.0...dev
[1.1.0]: https://github.com/abrahamkoloboe27/FinetrackProject-Snowflake/releases/tag/v1.1.0
[1.0.0]: https://github.com/abrahamkoloboe27/FinetrackProject-Snowflake/tree/a1fd54b
