<!--
Titre de la PR au format Conventional Commits, par exemple :
  feat(marts): ajouter mart_epargne
  fix(staging): corriger le typage des montants
  release: dev → staging
Le titre devient le message du commit sur la branche cible : il est contrôlé par « PR policy ».
-->

## Contexte

<!-- Pourquoi ce changement ? Quel besoin métier ou quel problème ? -->

Ticket : <!-- #123, ou « aucun » -->

## Changements

<!-- Liste courte : modèles ajoutés ou modifiés, tests, macros, CI, documentation. -->

-

## Type de changement

- [ ] `feat` : nouveau modèle ou nouvelle colonne
- [ ] `fix` : correction d'un modèle, d'un test ou d'une donnée
- [ ] `refactor` / `perf` : même résultat, code ou performance améliorés
- [ ] `docs` : documentation seule
- [ ] `ci` / `build` / `chore` : outillage, CI/CD, dépendances
- [ ] `release` : promotion dev → staging ou staging → main
- [ ] Changement cassant (`!`) : colonne renommée ou supprimée, grain modifié

## Checklist

- [ ] `dbt build` passe en local sur mon schéma `DEV_<PRENOM>`
- [ ] Chaque modèle nouveau ou modifié a une description et des tests dans son YAML
- [ ] `pre-commit run --all-files` passe (sqlfluff, yamllint...)
- [ ] La documentation (`docs/`, YAML) est à jour
- [ ] La branche cible respecte le flux : travail → `dev` → `staging` → `main`, `hotfix/*` → `main`

## Impact sur les environnements

<!-- Cocher ce qui s'applique après la fusion. -->

- [ ] Aucun impact sur les données (documentation, CI)
- [ ] Modèles reconstruits à l'identique
- [ ] Changement de schéma (colonnes, types) : consommateurs BI à prévenir
- [ ] Action manuelle nécessaire dans Snowflake (script `snowflake/`, droits, secret)

## Notes pour la revue

<!-- Points d'attention, requêtes de vérification, captures. -->
