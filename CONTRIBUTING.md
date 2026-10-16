# Contribuer à FinTrack Analytics

Merci de contribuer. Le guide complet est sur le site de l'équipe : **[Contribuer](https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/contribuer/)**. En résumé :

1. **Installez votre poste** : `make install`, puis un profil `~/.dbt/profiles.yml` sur votre schéma `DEV_<PRENOM>` ([Démarrage](https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/demarrage/)).
2. **Partez d'une issue** : formulaire « Bug / anomalie de données » ou « Nouveau modèle / évolution ».
3. **Créez une branche depuis `dev`** : `feature/<sujet>`, `fix/<sujet>`, `docs/<sujet>`... (`hotfix/<sujet>` depuis `main` pour un correctif urgent de production).
4. **Développez dans le style du projet** ([Conventions](https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/conventions/)) : chaque modèle et chaque colonne décrits dans le YAML, avec leurs tests. Vérifiez avec `make build` et `make lint`.
5. **Ouvrez une pull request vers `dev`**, avec un titre [Conventional Commits](https://www.conventionalcommits.org/fr/v1.0.0/) (`feat(marts): ajoute mart_epargne_mensuelle`) et le modèle de PR rempli.
6. **Faites-la relire.** Elle est fusionnée par squash quand les checks `Lint`, `dbt parse`, `Docs build`, `dbt build (CI)` et `PR policy` sont verts et qu'une autre personne l'a approuvée.

Les releases (`dev` → `staging` → `main`), les hotfix et les back-merges suivent le [Workflow Git](https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/workflow-git/).

Règles qui ne se discutent pas :

- aucun secret dans le dépôt, une issue ou une PR ([Secrets](https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/secrets/)) ;
- pas de push direct sur `dev`, `staging` ou `main` ;
- jamais de target locale nommée `prod`.

Une question ? Ouvrez une issue ou consultez la [FAQ](https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/faq/).
