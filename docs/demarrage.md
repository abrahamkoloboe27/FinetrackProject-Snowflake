# Démarrage

Cette page amène un nouveau membre de l'équipe jusqu'à son premier `dbt build` réussi, dans ses propres schémas Snowflake. Comptez 30 minutes.

## Prérequis

| Outil | Version | Pourquoi |
|---|---|---|
| Git | récent | cloner le dépôt, créer des branches |
| Python | 3.12 (fichier `.python-version`) | dbt, sqlfluff, pre-commit, MkDocs |
| make | GNU make | raccourcis du `Makefile` |
| GitHub CLI `gh` | récent, conseillé | ouvrir et suivre les PR depuis le terminal |

Côté accès, il vous faut :

- un accès en écriture au dépôt GitHub (demandez-le au mainteneur) ;
- un utilisateur Snowflake personnel qui a le rôle `FINTRACK_ROLE` (demandez-le au mainteneur, voir [Runbooks](runbooks.md#ajouter-un-membre-de-lequipe) ; ne partagez pas `FINTRACK_USER`), et l'identifiant du compte (`ORGNAME-ACCOUNTNAME`) ;
- une base `FINTRACK_DB` préparée avec les scripts `snowflake/00` à `04` (voir [Architecture](architecture.md#les-scripts-snowflake)). La section 1 du script `04_ci_cd.sql` est indispensable : elle donne à `FINTRACK_ROLE` le droit de créer vos schémas personnels.

## 1. Cloner le dépôt

```bash
gh repo clone abrahamkoloboe27/FinetrackProject-Snowflake
# ou : git clone https://github.com/abrahamkoloboe27/FinetrackProject-Snowflake.git
cd FinetrackProject-Snowflake
git switch dev        # on part toujours de la branche d'intégration
```

## 2. Installer l'outillage

```bash
make install
```

Cette cible crée l'environnement virtuel `.venv` avec `python3.12` s'il est installé, sinon `python3.13`, `python3.11` ou `python3` : `make help` affiche l'interpréteur retenu. Elle installe ensuite `requirements-dev.txt` (dbt-core, dbt-snowflake, sqlfluff, pre-commit, MkDocs, aux versions exactes utilisées par la CI) et les hooks Git de pre-commit. Pour imposer la version de la CI : `make install PYTHON=/chemin/vers/python3.12`.

Activez ensuite l'environnement dans chaque nouveau terminal :

```bash
source .venv/bin/activate
dbt --version         # dbt-core 1.12.x et le plugin snowflake
```

??? note "Sans make"

    ```bash
    python3.12 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements-dev.txt
    pre-commit install
    ```

## 3. Créer son profil dbt local

dbt lit ses connexions dans `~/.dbt/profiles.yml`, **hors du dépôt**. Le nom du profil doit être celui de `dbt_project.yml` : `finetrack_analytics`.

Choisissez un schéma personnel `DEV_<PRENOM>`, en majuscules et sans accent (par exemple `DEV_ABRAHAM`). Vos modèles iront dans `DEV_ABRAHAM_STAGING` et `DEV_ABRAHAM_MARTS` : vous ne gênez ni vos collègues ni la production. Le mécanisme est décrit dans [Environnements](environnements.md#la-macro-generate_schema_name).

=== "Mot de passe (compte d'essai)"

    ```yaml
    finetrack_analytics:
      target: dev
      outputs:
        dev:
          type: snowflake
          account: <votre_compte>          # ex : ORGNAME-ACCOUNTNAME
          user: <VOTRE_UTILISATEUR>        # ex : ABRAHAM
          password: '<votre_mot_de_passe>'
          role: FINTRACK_ROLE
          database: FINTRACK_DB
          warehouse: FINTRACK_WH
          schema: DEV_<PRENOM>             # ex : DEV_ABRAHAM
          threads: 4
    ```

=== "Paire de clés RSA"

    ```yaml
    finetrack_analytics:
      target: dev
      outputs:
        dev:
          type: snowflake
          account: <votre_compte>
          user: <VOTRE_UTILISATEUR>
          private_key_path: "{{ env_var('HOME') }}/.snowflake/rsa_key.p8"   # hors du dépôt ; dbt ne développe pas « ~ »
          # private_key_passphrase: '<phrase>'        # seulement si la clé est chiffrée
          role: FINTRACK_ROLE
          database: FINTRACK_DB
          warehouse: FINTRACK_WH
          schema: DEV_<PRENOM>
          threads: 4
    ```

    La génération d'une paire de clés est décrite dans [Secrets](secrets.md#generer-une-paire-de-cles-rsa).

La connexion par mot de passe est valable sur un compte d'essai. Sur un compte payant ou d'entreprise, Snowflake impose une authentification renforcée : utilisez alors une paire de clés RSA.

!!! warning "Profil créé avant la version 1.1.0"

    L'ancienne consigne du README utilisait `schema: STAGING`. Remplacez-le par votre schéma `DEV_<PRENOM>` : sinon dbt s'arrête dès le chargement du projet avec le message « Le schéma STAGING de la target dev est réservé à la production ». Les schémas `STAGING` et `MARTS` sont refusés pour toute target autre que `prod`.

!!! danger "Deux règles à ne jamais enfreindre"

    - **Ne nommez jamais votre cible locale `prod`.** La macro `generate_schema_name` écrit alors dans les schémas de production `STAGING` et `MARTS`.
    - **Lancez toujours dbt avec `FINTRACK_ROLE`**, pas avec `ACCOUNTADMIN` : les objets créés appartiendraient à `ACCOUNTADMIN` et `FINTRACK_ROLE` ne pourrait plus les remplacer.

## 4. Vérifier la connexion

```bash
make deps             # dbt deps : installe dbt_utils et codegen (versions de package-lock.yml)
make debug            # dbt debug : doit finir par « All checks passed! »
```

En cas d'échec, relisez le profil : un `account` mal formé ou un rôle absent sont les causes les plus fréquentes.

## 5. Premier build

```bash
make build            # dbt build : modèles et tests, dans l'ordre du DAG
```

Résultat attendu : 62 nœuds en succès (9 modèles construits et 53 tests ; le modèle éphémère n'est pas un nœud exécuté). Vos objets sont dans `FINTRACK_DB.DEV_<PRENOM>_STAGING` (4 vues) et `FINTRACK_DB.DEV_<PRENOM>_MARTS` (5 tables). Les valeurs à retrouver sont dans [Qualité des données](qualite.md#resultats-attendus-sur-lechantillon).

## 6. Les commandes du quotidien

`make help` liste toutes les cibles. Les principales :

| Commande | Effet |
|---|---|
| `make install` | crée `.venv`, installe les dépendances et les hooks pre-commit |
| `make deps` | `dbt deps` (relancé automatiquement par les autres cibles si `packages.yml` ou `package-lock.yml` ont changé) |
| `make debug` | `dbt debug` : vérifie le profil et la connexion |
| `make lint` | `pre-commit run --all-files`, comme le job « Lint » de la CI |
| `make fix` | corrige automatiquement le style SQL (`sqlfluff fix models tests analyses`) |
| `make parse` | `dbt parse --warn-error` et `dbt ls` avec le profil de la CI et des identifiants factices : sans connexion, comme le job « dbt parse » |
| `make build` | `dbt build` dans vos schémas `DEV_<PRENOM>_*` |
| `make test` | `dbt test` seul |
| `make docs` | construit ce site dans `site/` en mode strict, comme le job « Docs build » |
| `make docs-serve` | sert ce site sur http://127.0.0.1:8000, rechargé à chaque sauvegarde |
| `make dbt-docs` | génère la documentation dbt (lineage, colonnes) et la sert sur http://localhost:8080 |
| `make clean` | supprime `target/`, `dbt_packages/`, `logs/`, `site/` et `prod-state/` |

Deux variables ciblent un sous-ensemble du DAG ou une autre target de votre profil :

```bash
make build SELECT=stg_transactions+       # un modèle et tout ce qui en dépend
make build SELECT=+mart_budget_vs_reel    # un modèle et tout ce dont il dépend
make test SELECT=fct_transactions         # les tests d'un modèle
make build TARGET=dev                     # target de ~/.dbt/profiles.yml (dev par défaut)
```

Toutes les options de dbt restent disponibles en direct, par exemple `dbt build --select state:modified+ --state <dossier_manifest>` pour ne reconstruire que ce qui a changé par rapport à un manifest.

## 7. pre-commit

Les hooks s'exécutent à chaque `git commit`, uniquement sur les fichiers modifiés. Ils corrigent les espaces et fins de fichier, valident le YAML (yamllint), le SQL (sqlfluff), les scripts shell (shellcheck) et les workflows GitHub (actionlint), et bloquent une clé privée commitée par erreur.

Si un hook modifie un fichier, le commit est annulé : relisez la modification, faites `git add`, puis recommitez. Pour tout vérifier d'un coup, comme la CI :

```bash
pre-commit run --all-files
```

## Et ensuite ?

Votre poste est prêt. Lisez [Workflow Git](workflow-git.md) pour ouvrir votre première PR, puis [Conventions](conventions.md) avant d'écrire votre premier modèle.
