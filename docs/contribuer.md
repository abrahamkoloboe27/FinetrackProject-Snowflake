# Contribuer

Toute modification, même d'une ligne, passe par une issue, une branche et une pull request. Ce rythme donne à chacun la même visibilité sur ce qui change, et laisse la CI tester chaque modification avant qu'elle n'atteigne un environnement partagé.

## Le parcours d'une contribution

1. **Une issue** décrit le besoin. Deux formulaires sont proposés (les issues vierges sont désactivées) :
    - **Bug / anomalie de données** (label `bug`) : un modèle échoue, un test casse ou un chiffre semble faux. Le formulaire demande l'environnement, le modèle ou test concerné, comment reproduire, le résultat attendu et le résultat obtenu.
    - **Nouveau modèle / évolution** (label `enhancement`) : le besoin métier, la couche concernée, les sources, les règles de gestion (grain, filtres, calculs), les critères d'acceptation (tests attendus) et l'impact.

    Ne collez jamais de secret ni de donnée personnelle réelle dans une issue.
2. **Une branche** depuis `dev`, nommée d'après le type de changement : voir [Workflow Git](workflow-git.md#branches-de-travail).
3. **Le développement**, testé dans vos schémas `DEV_<PRENOM>_*`, dans le respect des [Conventions](conventions.md).
4. **Une pull request** vers `dev`, au titre Conventional Commits, qui remplit le modèle de PR.
5. **La revue**, puis la fusion par squash quand les cinq checks sont verts.

## La checklist de la pull request

Le modèle `.github/pull_request_template.md` structure chaque PR : **Contexte** (avec le ticket), **Changements**, **Type de changement**, **Checklist**, **Impact sur les environnements**, **Notes pour la revue**. Une PR est prête à être relue quand :

- le contexte explique le **pourquoi** et renvoie à l'issue (`Closes #12`) ;
- `dbt build` passe en local dans vos schémas `DEV_<PRENOM>_*`, sur les modèles touchés et leurs descendants (`make build SELECT=<modele>+`) ;
- chaque modèle nouveau ou modifié a une description et les tests obligatoires dans le YAML de sa couche ;
- `pre-commit run --all-files` passe (ou `make lint`) ;
- la documentation (`docs/`, YAML, README) est à jour ;
- la branche cible respecte le flux : travail → `dev` → `staging` → `main`, `hotfix/*` → `main` ;
- l'impact est coché : aucun impact sur les données, modèles reconstruits à l'identique, changement de schéma à annoncer aux consommateurs BI, ou action manuelle dans Snowflake.

## Relire une pull request

Toute PR doit être approuvée par une autre personne que son auteur. `.github/CODEOWNERS` désigne les propriétaires du code : leur revue est demandée automatiquement, et elle est **obligatoire** pour les PR vers `main`. Les zones sensibles (`.github/`, `scripts/`, `ci/`, `snowflake/`) y sont listées explicitement. Pour ajouter un membre à la relecture d'un dossier : `/models/ @abrahamkoloboe27 @login`.

Ce que le relecteur vérifie :

| Point | Où regarder |
|---|---|
| Le résultat métier est juste | résumé du job `dbt build (CI)`, requêtes sur `CI_PR_<n>_MARTS` |
| Les tests protègent vraiment | YAML : clés, relations, valeurs acceptées, grain |
| Le code suit le style du projet | diff, et le check `Lint` |
| L'impact en aval est maîtrisé | lineage du [catalogue dbt](https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/dbt/), modèles reconstruits par la Slim CI |
| La documentation suit | descriptions YAML, pages de `docs/` |

Commentez avec bienveillance et précision. Une suggestion GitHub (bouton **Add a suggestion**) s'applique en un clic. Distinguez ce qui bloque de ce qui est une préférence (« Suggestion, non bloquant : ... »). L'auteur résout chaque conversation ou y répond : les rulesets bloquent la fusion tant qu'une conversation reste ouverte.

Délai visé : une première revue dans la journée ouvrée.

## Modifier la documentation

Ce site est construit à partir de `docs/` et de `mkdocs.yml`. Chaque page a un bouton **Modifier** qui ouvre le fichier sur la branche `dev`.

Dans la fenêtre de commit de GitHub, choisissez « Create a new branch for this commit and start a pull request » et remplacez le nom proposé (`<login>-patch-1`, refusé par le check `PR policy`) par `docs/<sujet>` ; titre de PR `docs: ...`.

```bash
make docs-serve        # http://127.0.0.1:8000, rechargé à chaque sauvegarde
make docs              # contrôle strict, comme le job « Docs build »
```

- Une nouvelle page doit être ajoutée à `nav` dans `mkdocs.yml`.
- Les liens internes pointent vers le fichier `.md` (`[Secrets](secrets.md#verifier)`) ; le mode strict vérifie qu'ils existent.
- Les captures d'écran vont dans `assets/`, à la racine du dépôt : le README et le site les affichent avec le même chemin `assets/<nom>.png`.
- Les diagrammes s'écrivent en [Mermaid](https://mermaid.js.org/), dans un bloc de code `mermaid`.

Une PR qui ne touche que la documentation (`docs/...`) ne redéploie pas dbt. Elle met le site à jour une fois arrivée sur `main`.

## Questions

Ouvrez une issue, ou demandez dans la PR concernée. La [FAQ](faq.md) répond aux questions les plus fréquentes.
