# Qualité des données

Le projet compte **53 tests**, tous exécutés par `dbt build`, juste après le modèle qu'ils contrôlent. Un test en échec arrête la construction des modèles qui en dépendent.

## Les tests du projet

| Type | Nombre | Exemples |
|---|---|---|
| `not_null` | 26 | clés, statuts, montants, types d'opération |
| `unique` | 7 | `compte_id`, `transaction_id`, `categorie_id`, `budget_id` |
| `relationships` | 9 | transactions vers comptes et catégories, faits vers dimensions |
| `accepted_values` | 5 | `type_compte`, `statut`, `type_operation`, `type_categorie` |
| `unique_combination_of_columns` | 3 | grain de `stg_budgets` et des deux marts |
| `accepted_range` | 1 | `montant` strictement positif |
| `expression_is_true` | 1 | `mois` des budgets = premier jour du mois |
| singulier | 1 | `assert_solde_mensuel_positif` : aucun compte épargne à solde cumulé négatif |

Les tests génériques sont déclarés dans les YAML de modèles (`data_tests:`). `unique_combination_of_columns`, `accepted_range` et `expression_is_true` viennent du package `dbt_utils`. Le test singulier est une requête SQL dans `tests/` : elle renvoie les lignes en erreur, zéro ligne signifie que le test réussit.

`accepted_values` et `relationships` ignorent les valeurs `NULL` : c'est pourquoi les colonnes concernées ont aussi un test `not_null`. Sans lui, une transaction sans statut disparaîtrait des marts sans qu'aucun test n'échoue.

Snowflake n'applique pas les clés étrangères. Le test `relationships` vérifie donc l'intégrité référentielle : une transaction qui pointe vers un compte ou une catégorie inexistants est détectée avant de fausser les agrégats des marts.

## Où les tests tournent

| Moment | Où | Échec = |
|---|---|---|
| Sur votre poste | `make build` dans `DEV_<PRENOM>_*` | à corriger avant d'ouvrir la PR |
| Sur chaque PR | job `dbt build (CI)` dans `CI_PR_<n>_*` | check rouge, fusion bloquée |
| À chaque fusion dans `dev`, `staging`, `main` | job `Deploy (<env>)` du workflow CD | déploiement en échec, l'équipe est prévenue |
| Chaque matin à 05:00 UTC | workflow `Scheduled prod run` sur la production | anomalie dans les données de `RAW` (voir [Runbooks](runbooks.md#le-run-quotidien-de-prod-echoue)) |

Le run quotidien est le seul à détecter un problème qui vient des **données** et non du code : un nouveau compte sans statut, un budget en double, une transaction orpheline.

Après avoir modifié des données sources, relancez `dbt build` et non `dbt test` seul : les tests des marts portent sur les tables telles qu'elles ont été construites la dernière fois.

## Ajouter un test

Les tests génériques s'écrivent avec la clé `arguments:` (syntaxe de dbt 1.10.5 et plus) :

```yaml
      - name: type_compte
        description: "Type de compte : courant, epargne ou joint."
        data_tests:
          - not_null
          - accepted_values:
              arguments:
                values: ['courant', 'epargne', 'joint']
```

Un test singulier est un fichier `tests/assert_<regle>.sql` qui renvoie les lignes fautives :

```sql
-- Test singulier : retourne les lignes en erreur, zéro ligne = test réussi.
-- Un compte épargne ne doit jamais avoir un solde cumulé négatif.

select
    compte_id,
    nom_client,
    mois,
    solde_cumule

from {{ ref('mart_solde_mensuel') }}
where type_compte = 'epargne'
    and solde_cumule < 0
```

Les tests attendus pour chaque type de colonne sont listés dans [Conventions](conventions.md#yaml-descriptions-et-tests).

Pour vérifier qu'un test protège vraiment, corrompez volontairement une donnée dans vos schémas de développement (doublon, compte inconnu, statut `NULL`...) et vérifiez qu'il échoue.

## Résultats attendus sur l'échantillon

Après `dbt build`, ces valeurs doivent apparaître :

| Compte | Solde cumulé fin mars 2024 |
|---|---|
| 1 Alice Dupont | 7 350,83 |
| 2 Bob Martin | 5 476,92 |
| 3 Claire Leroy | 5 900,00 |
| 4 David Moreau | 7 748,70 |
| 5 Emma Bernard | 2 355,00 |
| 6 Frank Petit | aucune ligne (aucune transaction validée) |

`fct_transactions` compte 43 lignes sur 45 : une transaction en attente et une rejetée sont exclues. `mart_budget_vs_reel` compte 32 lignes dont 2 dépassements : Alice, Restaurant, février 2024 (60 prévus, 89 dépensés) et Bob, Vêtements, janvier 2024 (80 prévus, 120 dépensés).

Une requête de contrôle rapide (dernier solde connu de chaque compte), à adapter au schéma de votre environnement :

```sql
select compte_id, nom_client, mois, solde_cumule
from fintrack_db.dev_abraham_marts.mart_solde_mensuel
qualify row_number() over (partition by compte_id order by mois desc) = 1
order by compte_id;
```

## Validation

- `dbt build` sur Snowflake : 62 nœuds (9 modèles et 53 tests), 0 erreur. Le projet compte 10 modèles, mais le modèle éphémère n'est pas exécuté en tant que tel.
- Les tables `fct_transactions`, `mart_solde_mensuel`, `mart_budget_vs_reel` et `dim_comptes` ont été comparées, ligne par ligne, à un calcul indépendant en Python : résultats identiques.
- Les tests ont été éprouvés en corrompant volontairement les données (doublon, compte inconnu, statut `NULL`, montant négatif, budget en double, retrait massif sur le compte épargne...) : chaque corruption fait échouer le test attendu.

??? example "Captures d'un `dbt build` complet (62 nœuds, 0 erreur)"

    ![dbt build : vues staging et premiers tests](assets/dbt_build_1.png)

    ![dbt build : tables marts, derniers tests et résumé PASS=62](assets/dbt_build_2.png)
