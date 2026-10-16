# Conventions

Ces règles gardent le projet homogène quand plusieurs personnes y écrivent. La plupart sont vérifiées automatiquement par pre-commit et par le job `Lint` de la CI ; les autres le sont en revue.

## Langue

Tout est rédigé en **français** : commentaires SQL, descriptions YAML, documentation, messages des scripts, titres de PR et messages de commit (le type Conventional Commits reste en anglais : `feat`, `fix`...). Phrases courtes, précises, qui expliquent le **pourquoi** plutôt que le quoi.

Les identifiants (modèles, colonnes) sont en français, en `snake_case`, sans accent : `nom_client`, `montant_prevu`, `anciennete_jours`.

## Nommage des modèles

| Préfixe | Couche | Règle | Exemple |
|---|---|---|---|
| `stg_` | staging | `stg_<table source sans raw_>`, une vue par table source | `stg_transactions` |
| `int_` | intermediate | `int_<entité>_<transformation>` | `int_transactions_enrichies` |
| `dim_` | marts | dimension : une ligne par entité métier | `dim_comptes` |
| `fct_` | marts | faits : une ligne par événement | `fct_transactions` |
| `mart_` | marts | agrégat prêt pour la BI, nommé d'après la question à laquelle il répond | `mart_budget_vs_reel` |

Colonnes :

- clé primaire : `<entité>_id` (`compte_id`, `transaction_id`), jamais `id` seul après le staging ;
- clé étrangère : même nom que la clé primaire référencée ;
- dates : `date_<événement>` pour une date, `mois` ou `mois_<événement>` pour un premier jour du mois ;
- booléens : formulés comme une affirmation (`depassement`, `a_un_budget`).

## Fichiers

- Un fichier SQL par modèle, dans le dossier de sa couche.
- Un fichier YAML par couche, préfixé par `_` pour rester en tête du dossier : `_stg_sources.yml`, `_stg_models.yml`, `_int_models.yml`, `_marts_models.yml`.
- Les tests singuliers vont dans `tests/`, nommés `assert_<règle>.sql`.
- Les macros vont dans `macros/`, avec un en-tête qui explique leur rôle.

## Style SQL

Le style est celui des modèles existants. sqlfluff le vérifie (dialecte `snowflake`, templater `jinja`, configuration dans `.sqlfluff`).

- Mots-clés et fonctions **en minuscules** : `select`, `left join`, `coalesce`.
- **Virgules en fin de ligne**, une colonne par ligne. Seule exception : une petite CTE de correspondance de deux colonnes tient sur une ligne (`select compte_id, nom_client from {{ ref('dim_comptes') }}`).
- Indentation de **4 espaces**, jamais de tabulation. Lignes de **100 caractères** au plus.
- Conversions écrites `cast(x as date)`, jamais `x::date`. `group by` et `order by` avec les noms de colonnes, jamais leur position (`group by compte_id, mois`, pas `group by 1, 2`).
- Un modèle = une suite de CTE : d'abord les CTE d'import (`select * from {{ ref(...) }}`), puis les CTE de transformation, et une dernière CTE `final`. Le modèle se termine par `select * from final`.
- Une ligne vide après l'ouverture et avant la fermeture de chaque CTE, et entre la liste de colonnes et le `from`.
- Alias explicites avec `as`. Jointures explicites (`left join ... on ...`), condition sur la ligne suivante.
- Jamais de nom de base ou de schéma en dur : `{{ ref('...') }}` pour un modèle, `{{ source('raw', '...') }}` pour une source.
- Un commentaire `--` avant chaque calcul non évident.

```sql
with transactions as (

    select * from {{ ref('int_transactions_enrichies') }}

),

final as (

    select
        transaction_id,
        compte_id,
        montant_signe

    from transactions

    -- seules les transactions validées comptent dans les analyses
    where statut = 'validee'

)

select * from final
```

Vérifier et corriger :

```bash
make lint                                       # tous les contrôles, comme la CI
sqlfluff lint models/marts/fct_transactions.sql # un fichier
make fix                                        # corrections automatiques (sqlfluff fix)
```

sqlfluff couvre `models/`, `tests/` et `analyses/`. Les scripts de `snowflake/`, écrits pour Snowsight, et les macros de `macros/`, du Jinja pur, en sont exclus (voir `.sqlfluffignore`). Le templater `jinja` remplace `ref()` et `source()` sans se connecter à Snowflake : le lint fonctionne hors ligne.

## YAML : descriptions et tests

**Chaque modèle et chaque colonne a une description.** C'est ce texte qu'affiche le catalogue dbt ; une colonne sans description est refusée en revue.

Tests obligatoires :

| Colonne | Tests |
|---|---|
| Clé primaire | `unique` + `not_null` |
| Clé étrangère | `relationships` vers le modèle référencé + `not_null` |
| Colonne à valeurs fixes (statut, type) | `accepted_values` + `not_null` |
| Grain composé de plusieurs colonnes | `dbt_utils.unique_combination_of_columns` au niveau du modèle |
| Règle métier qui porte sur plusieurs lignes | test singulier dans `tests/` |

`accepted_values` et `relationships` ignorent `NULL` : sans `not_null` à côté, une ligne sans valeur passerait inaperçue.

Écrivez les tests sous la clé `data_tests:`, avec les paramètres sous `arguments:` (dbt 1.10.5 et plus) :

```yaml
models:
  - name: mart_solde_mensuel
    description: >
      Solde mensuel de chaque compte, calculé à partir des transactions
      validées. Une ligne par compte et par mois.
    data_tests:
      - dbt_utils.unique_combination_of_columns:
          arguments:
            combination_of_columns:
              - compte_id
              - mois
    columns:
      - name: compte_id
        description: "Compte concerné. Clé étrangère vers dim_comptes."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_comptes')
                field: compte_id
```

Le style YAML (indentation de 2 espaces, longueur de ligne, `on:` des workflows) est vérifié par yamllint, configuré dans `.yamllint.yml`.

## Matérialisations et schémas

- Les matérialisations sont fixées par couche dans `dbt_project.yml`. Ne les surchargez dans un modèle qu'avec une raison écrite en commentaire.
- Ne modifiez pas `generate_schema_name` sans revue du mainteneur : la macro décide dans quel schéma la production écrit.

## Scripts et workflows

- Scripts shell : `#!/usr/bin/env bash` et `set -euo pipefail`, vérifiés par shellcheck. Messages en français.
- Workflows GitHub Actions : vérifiés par actionlint. Une donnée fournie par l'utilisateur (titre de PR, nom de branche) passe par `env:`, jamais par `${{ }}` directement dans `run:`.
- Aucun secret dans le code : voir [Secrets](secrets.md).

## Commits et pull requests

Les titres de PR suivent [Conventional Commits](workflow-git.md#titre-de-pr-conventional-commits) : c'est le titre qui devient le message du commit lors d'un squash. Les branches suivent le [nommage](workflow-git.md#branches-de-travail) du workflow Git.
