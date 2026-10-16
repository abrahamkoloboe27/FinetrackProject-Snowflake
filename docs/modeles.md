# Modèles

Cette page résume ce que contient chaque modèle et à quel grain. Le détail colonne par colonne, les tests et le lineage interactif sont dans le [catalogue dbt](https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/dbt/), régénéré à chaque déploiement en production.

![Documentation dbt du projet](assets/overview.png)

## Sources

Déclarées dans `models/staging/_stg_sources.yml` (source `raw`, base `fintrack_db`, schéma `raw`). Ces tables sont chargées par les scripts `snowflake/01` et `02` ; dbt ne fait que les lire.

| Table | Lignes (échantillon) | Contenu |
|---|---|---|
| `raw_comptes` | 6 | une ligne par compte bancaire, quel que soit son statut (actif, inactif, clôturé) |
| `raw_transactions` | 45 | une ligne par opération, quel que soit son statut (validée, en attente, rejetée) |
| `raw_categories` | 12 | référentiel des catégories (dépenses et revenus), regroupées par groupe parent |
| `raw_budgets` | 25 | budgets mensuels par compte, catégorie et mois (seuls les comptes 1 et 2 en ont) |

## Catalogue des modèles

| Modèle | Couche | Matérialisation | Grain (une ligne par...) | Contenu |
|---|---|---|---|---|
| `stg_comptes` | staging | vue | compte | Comptes : `id` devient `compte_id`, statut en minuscules |
| `stg_transactions` | staging | vue | transaction | Transactions typées, avec `montant_signe` (+ pour un crédit, - pour un débit) |
| `stg_categories` | staging | vue | catégorie | Catégories renommées : `categorie_id`, `nom_categorie`, `type_categorie` |
| `stg_budgets` | staging | vue | compte, catégorie et mois | Budgets mensuels, mois typé en `DATE` |
| `int_transactions_enrichies` | intermediate | éphémère | transaction (tous statuts) | Transactions + client, type de compte, catégorie, groupe et `mois_transaction` |
| `dim_comptes` | marts | table | compte | Dimension des comptes, avec `anciennete_jours` |
| `dim_categories` | marts | table | catégorie | Dimension des catégories |
| `fct_transactions` | marts | table | transaction **validée** | Faits : transactions validées uniquement |
| `mart_solde_mensuel` | marts | table | compte et mois avec au moins une transaction validée | Crédits, débits, solde net et solde cumulé par compte et par mois |
| `mart_budget_vs_reel` | marts | table | compte, catégorie et mois ayant un budget, une dépense ou les deux | Dépenses réelles contre budget (`FULL OUTER JOIN`) |

Chaque modèle et chaque colonne est décrit dans le fichier YAML de sa couche (`_stg_models.yml`, `_int_models.yml`, `_marts_models.yml`), et les sources dans `_stg_sources.yml`. C'est ce texte qu'affiche le catalogue dbt.

## Colonnes à bien comprendre

`montant_signe` (`stg_transactions`, puis tous les modèles en aval)
:   `+montant` pour un crédit, `-montant` pour un débit, `NULL` si le type d'opération est inconnu. Le test `not_null` signale ce dernier cas au lieu de le masquer.

`anciennete_jours` (`dim_comptes`)
:   Nombre de jours entre l'ouverture du compte et la date d'exécution du modèle. La valeur est figée dans la table jusqu'au prochain build : le run quotidien de production la rafraîchit chaque matin.

`solde_cumule` (`mart_solde_mensuel`)
:   `solde_initial` + somme des soldes nets de tous les mois jusqu'au mois courant. C'est le solde réel seulement si toutes les transactions depuis l'ouverture sont chargées.

`ecart` et `depassement` (`mart_budget_vs_reel`)
:   `ecart = montant_reel - montant_prevu`. `depassement` n'est vrai que si un budget existe et qu'il est dépassé. Pour repérer les dépassements, filtrez sur `depassement`, pas sur le signe de `ecart`.

`type_categorie` et `type_operation`
:   Deux axes indépendants. Les virements reçus sur le compte épargne sont des crédits rangés dans « Épargne versée », une catégorie de type `depense`.

## Où trouver un modèle

Les vues staging et les tables marts sont construites dans un schéma différent selon l'environnement. Le modèle intermédiaire, éphémère, n'existe dans aucun schéma.

| Environnement | Vues staging | Tables marts |
|---|---|---|
| Production | `FINTRACK_DB.STAGING` | `FINTRACK_DB.MARTS` |
| Recette (staging) | `FINTRACK_DB.PREPROD_STAGING` | `FINTRACK_DB.PREPROD_MARTS` |
| Intégration (dev) | `FINTRACK_DB.DEV_STAGING` | `FINTRACK_DB.DEV_MARTS` |
| Votre poste | `FINTRACK_DB.DEV_<PRENOM>_STAGING` | `FINTRACK_DB.DEV_<PRENOM>_MARTS` |
| CI de la PR n | `FINTRACK_DB.CI_PR_<n>_STAGING` | `FINTRACK_DB.CI_PR_<n>_MARTS` |

!!! tip "Pour la BI"

    Branchez les tableaux de bord sur `FINTRACK_DB.MARTS` uniquement. Les schémas `PREPROD_*` et `DEV_*` sont reconstruits à chaque fusion et peuvent contenir des modèles pas encore validés.

## Ajouter ou modifier un modèle

1. Créez une branche depuis `dev` (voir [Workflow Git](workflow-git.md#demarrer-une-tache)).
2. Écrivez le SQL dans le dossier de sa couche, dans le style du projet (voir [Conventions](conventions.md)).
3. Décrivez le modèle et **chaque** colonne dans le YAML de la couche, avec les tests obligatoires (voir [Conventions](conventions.md#yaml-descriptions-et-tests)).
4. `dbt build --select <modele>+` dans vos schémas `DEV_<PRENOM>_*`, puis ouvrez la PR.

Le job `dbt build (CI)` reconstruira votre modèle et tout ce qui en dépend dans un schéma `CI_PR_<n>_*` dédié à votre PR.
