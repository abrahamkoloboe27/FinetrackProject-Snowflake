# Runbooks

Procédures pour les incidents courants. Chacune suit le même plan : symptôme, diagnostic, action, vérification. Toutes les commandes `gh` se lancent depuis le dossier du dépôt.

Pour lire le journal d'une exécution en échec :

```bash
gh run list --limit 10                        # dernières exécutions, tous workflows
gh run view <run-id>                          # jobs et résumé
gh run view <run-id> --log-failed             # journal des seules étapes en échec
```

## Un check de PR est rouge

Ouvrez l'onglet **Checks** de la PR, puis le check en échec. Pour les jobs dbt, lisez d'abord l'onglet **Summary** de l'exécution : il liste chaque nœud en échec avec son message.

### Lint

- **Diagnostic** : le journal affiche le hook en échec et, grâce à `--show-diff-on-failure`, la correction qu'il aurait appliquée.
- **Action** : `make lint` en local. Les hooks qui corrigent (espaces, fins de fichier, fins de ligne) modifient les fichiers : relisez, `git add`, committez. Pour le SQL, `make fix` applique les corrections de sqlfluff ; relisez le diff avant de committer.
- **Clé privée détectée** (`detect-private-key` pour une clé PEM, `detect-private-key-base64` pour une clé en base64 sur une ligne) : ne contournez jamais ces hooks. Retirez la clé du commit. Si elle a été poussée, considérez-la comme compromise : [faites tourner la clé](#faire-tourner-la-cle-rsa).
- **Identifiant en clair dans `ci/profiles.yml`** (`ci-profiles-env-var-only`) : remettez l'appel `env_var(...)` et exportez la valeur dans votre terminal ([Secrets](secrets.md#verifier)). Aucun hook ne repère un mot de passe dans les autres fichiers : relisez votre diff.

### dbt parse

- **Diagnostic** : `make parse` en local reproduit l'erreur, sans connexion.
- **Causes fréquentes** : `ref()` vers un modèle renommé ou supprimé, YAML mal indenté, test générique sans la clé `arguments:`, erreur Jinja, avertissement de syntaxe dépréciée (bloquant avec `--warn-error`).

### Docs build

- **Diagnostic** : `make docs` en local affiche les avertissements que `--strict` transforme en erreurs.
- **Causes fréquentes** : lien vers une page inexistante, ancre (`page.md#section`) qui ne correspond plus à un titre, nouvelle page absente de `nav` dans `mkdocs.yml`. Un titre modifié change son ancre : cherchez les liens qui y pointent (`grep -rn "page.md#" docs/`).

### dbt build (CI)

- **Secret manquant** : l'étape de vérification des secrets échoue avec la liste des noms absents. Voir [Secrets Snowflake manquants ou invalides](#secrets-snowflake-manquants-ou-invalides).
- **Test en échec** : le résumé donne le test et le nombre de lignes fautives. Les schémas `CI_PR_<n>_*` existent tant que la PR est ouverte : interrogez-les dans Snowsight, ou rejouez en local avec `dbt build --select <modele>+` dans vos schémas.
- **Modèle en erreur** : le message SQL est dans le résumé ; le journal complet est dans l'artefact `dbt-ci-pr-<n>` (`logs/dbt.log`) :

    ```bash
    gh run download <run-id> -n dbt-ci-pr-<n> -D /tmp/dbt-ci
    ```

- **Job ignoré** (« skipped ») : la PR est en brouillon (`gh pr ready <n>`), vient d'un fork ou a été ouverte par Dependabot (voir [CI/CD](ci-cd.md#securite-des-workflows)).

### PR policy

Le message d'erreur indique la règle enfreinte et la correction :

- **titre non conforme** : `gh pr edit <n> --title "feat(marts): ajoute mart_epargne_mensuelle"`. Le check se relance seul ;
- **mauvaise base** : `gh pr edit <n> --base dev` ;
- **nom de branche non autorisé** : une PR ne peut pas changer de branche source. Renommez la branche et ouvrez une nouvelle PR :

    ```bash
    git switch -c feature/bon-nom
    git push -u origin feature/bon-nom
    gh pr close <n> --delete-branch --comment "Remplacée par une PR depuis feature/bon-nom"
    gh pr create --base dev --title "feat(...): ..."
    ```

### Un check reste en attente

« Expected — Waiting for status to be reported » signifie que le workflow n'a pas démarré :

- **la PR a un conflit** : GitHub ne lance pas les workflows de PR tant que la branche ne fusionne pas proprement. Résolvez le conflit (`git merge origin/dev`, ou bouton **Resolve conflicts**) ;
- **un job a été renommé** : le ruleset attend l'ancien nom (voir [CI/CD](ci-cd.md#les-checks-requis)) ;
- **les Actions sont désactivées** pour le dépôt : onglet **Actions**.

## Secrets Snowflake manquants ou invalides

- **Symptôme** : l'étape de vérification des secrets ou `dbt debug` échoue.
- **Action** : retrouvez le message dans le journal, appliquez la correction, puis [relancez le job](#relancer-un-job-ou-un-deploiement).

| Message | Cause | Correction |
|---|---|---|
| « Secrets manquants ou vides : ... » (étape « Vérifier les secrets Snowflake ») | secret absent ou vide | l'ajouter : [Secrets](secrets.md#ou-ajouter-les-secrets) |
| « SNOWFLAKE_PRIVATE_KEY commence par une espace... », « contient des `\n` littéraux », « clé chiffrée mais ... PASSPHRASE est vide » (même étape) | format de clé | recoller la clé : [format](secrets.md#le-format-de-la-cle-privee) |
| `Env var required but not provided` | variable non transmise au job | vérifier le nom exact du secret |
| `251006: Password is empty` | ni clé ni mot de passe n'arrivent à dbt | ajouter `SNOWFLAKE_PRIVATE_KEY` ou `SNOWFLAKE_PASSWORD` |
| `JWT token is invalid` | la clé publique enregistrée dans Snowflake ne correspond pas à la clé privée, ou mauvais utilisateur | comparer les empreintes : [Secrets](secrets.md#script-04) |
| `Incorrect padding`, `Unable to load PEM file` | format de clé | recoller la clé en base64 sur une ligne : [format](secrets.md#le-format-de-la-cle-privee) |
| `Password was given but private key is not encrypted` | phrase secrète fournie pour une clé non chiffrée | supprimer `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` |
| `Password was not given but private key is encrypted`, `Incorrect password` | phrase secrète absente ou fausse | corriger `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` |
| `Incorrect username or password was specified` | mauvais mot de passe, ou mot de passe utilisé avec un utilisateur `SERVICE` | corriger le secret, ou passer à la paire de clés |
| message contenant « Multi-factor authentication » ou « MFA », ou `dbt debug` qui attend une validation (Duo) jusqu'au délai | compte d'essai converti en compte payant (second facteur obligatoire pour un utilisateur `PERSON` connecté par mot de passe), ou utilisateur inscrit au MFA | passer à la paire de clés : `FINTRACK_CI_USER` (sections 2 et 3 de `snowflake/04_ci_cd.sql`), secrets `SNOWFLAKE_USER` et `SNOWFLAKE_PRIVATE_KEY`, puis supprimer `SNOWFLAKE_PASSWORD` : [Secrets](secrets.md#passer-a-la-paire-de-cles) |
| `Role 'FINTRACK_ROLE' ... is not granted to this user` | rôle non attribué ; après la [séparation de la CI](secrets.md#separer-la-ci-de-la-production), secret `SNOWFLAKE_ROLE` absent | `GRANT ROLE FINTRACK_ROLE TO USER <utilisateur>;` (script `04`) ; après la séparation, `SNOWFLAKE_ROLE` = `FINTRACK_CI_ROLE` au niveau du dépôt, `FINTRACK_ROLE` dans chaque environnement |
| `Insufficient privileges to operate on database 'FINTRACK_DB'` à la création d'un schéma | droit `CREATE SCHEMA` absent | exécuter la section 1 de `snowflake/04_ci_cd.sql` ([Secrets](secrets.md#script-04)) |
| erreur de connexion ou délai dépassé sur l'URL du compte | `SNOWFLAKE_ACCOUNT` mal formé | utiliser `ORGNAME-ACCOUNTNAME`, sans `.snowflakecomputing.com` |

Sur une erreur réseau, dbt réessaie la connexion trois fois, à 10 secondes d'intervalle, avant d'abandonner. Une erreur d'identifiants, elle, échoue tout de suite.

## Un déploiement a échoué

- **Symptôme** : le job `Deploy (<env>)` du workflow CD est rouge.
- **Diagnostic** : `gh run view <run-id> --log-failed` et l'onglet **Summary**.
    - **secrets** : voir [la section précédente](#secrets-snowflake-manquants-ou-invalides) ;
    - **test en échec** : le code a passé la CI, donc l'écart vient le plus souvent des **données** de l'environnement, ou d'un modèle que la Slim CI n'a pas reconstruit ;
    - **« Déploiement refusé : la branche « X » n'a pas d'environnement »** (job `Résoudre l'environnement`) : CD lancé à la main depuis une autre branche que `dev`, `staging` ou `main`. Relancez-le avec `--ref dev`, `--ref staging` ou `--ref main` ;
    - **« Branch ... is not allowed to deploy to <env> »** : la politique de branches de l'environnement GitHub a été modifiée à la main. Relancez `scripts/setup_github.sh` ;
    - **« Relance refusée »** : vous avez relancé une ancienne exécution alors que la branche a avancé ; elle aurait redéployé du code périmé. Redéployez avec `gh workflow run cd.yml --ref <branche>` ;
    - **job annulé** (« cancelled ») sans action de votre part : un autre déploiement ou le run planifié a pris sa place dans la file (un seul job en attente par groupe de concurrence). Sur `main`, relancez `gh workflow run cd.yml --ref main` pour produire la release et `dbt-manifest-prod` ;
    - **job en attente** (« Waiting for review ») : l'environnement exige une approbation, bouton **Review deployments**.
- **État de l'environnement** : `dbt build` s'arrête en aval de l'erreur. Les modèles en amont sont à jour, ceux en aval gardent leur version précédente. Une table en échec garde ses anciennes données : Snowflake la remplace en une seule opération.
- **Action** : corrigez par une PR de correctif vers `dev` qui suit le cycle normal, ou par un [hotfix](workflow-git.md#corriger-en-urgence-hotfix) si la production est touchée. Pour une cause passagère (Snowflake indisponible), [relancez](#relancer-un-job-ou-un-deploiement).
- **Vérification** : le job `Deploy (<env>)` suivant est vert.

## Revenir en arrière en production

- **Symptôme** : une release en production donne des résultats faux, et la correction prendra du temps.
- **Principe** : on ne redéploie pas un ancien commit, on **annule** la modification par un commit (`git revert`) qui suit le chemin du hotfix. L'historique reste lisible et le déploiement passe par la CI.

1. Repérez le commit fautif sur `main` :

    ```bash
    git switch main && git pull --ff-only
    git log --oneline --first-parent -10
    ```

2. Créez la branche d'annulation et annulez :

    ```bash
    git switch -c hotfix/revert-release-1-2-0
    git revert -m 1 <sha_du_merge_commit>   # une release (merge commit staging → main)
    # ou : git revert <sha>                 # un hotfix (commit squashé)
    git push -u origin hotfix/revert-release-1-2-0
    gh pr create --base main --title "revert: annule la release 1.2.0" \
      --body "Retour arrière : <description du problème>."
    ```

3. Fusionnez (squash) quand les checks sont verts. Le workflow CD redéploie la production avec le code précédent. Attention : l'annulation remet aussi l'ancienne version dans `dbt_project.yml` et retire la section `[1.2.0]` du CHANGELOG. Pour tracer l'annulation par une release, dans la même PR : fixez `version: '1.2.1'` (au-dessus de la version annulée, jamais 1.1.x), rétablissez la section `[1.2.0]` du CHANGELOG et ajoutez une section `[1.2.1]` dont l'entrée « Supprimé » annonce l'annulation de 1.2.0.
4. **Objets orphelins** : dbt ne supprime pas la table d'un modèle qui n'existe plus. Si la release annulée avait ajouté un modèle, supprimez son objet à la main, avec `FINTRACK_ROLE` : `drop table if exists fintrack_db.marts.<modele>;`.
5. **Back-merge** `main` → `staging` → `dev` comme après un hotfix. L'annulation descend alors aussi sur `dev`.
6. Pour réintroduire la fonctionnalité corrigée : sur une branche depuis `dev`, `git revert <sha_du_commit_d_annulation>` (« revert du revert »), ajoutez la correction, puis suivez le cycle normal.

- **Vérification** : `Deploy (prod)` vert, puis les contrôles de [Qualité des données](qualite.md#resultats-attendus-sur-lechantillon) sur `MARTS`.

## Relancer un job ou un déploiement

| Besoin | Interface | Ligne de commande |
|---|---|---|
| Relancer les jobs en échec d'une exécution | exécution → **Re-run jobs** → **Re-run failed jobs** | `gh run rerun <run-id> --failed` |
| Relancer toute une exécution | **Re-run all jobs** | `gh run rerun <run-id>` |
| Redéployer un environnement | **Actions** → **CD** → **Run workflow** → branche | `gh workflow run cd.yml --ref dev` (ou `staging`, `main`) |
| Republier la documentation | **Actions** → **Docs** → **Run workflow** | `gh workflow run docs.yml --ref main` |
| Lancer le build de production quotidien | **Actions** → **Scheduled prod run** → **Run workflow** | `gh workflow run scheduled-run.yml --ref main` |
| Nettoyer les schémas CI | **Actions** → **CI cleanup** → **Run workflow** | `gh workflow run cleanup-ci.yml` |
| Relancer les checks d'une PR | **Re-run jobs** sur le check | `gh run rerun <run-id>`, ou un nouveau push |

Pour le CD, redéployez par `gh workflow run cd.yml --ref <branche>` plutôt que par une relance : une relance garde le commit d'origine, et elle est refusée (« Relance refusée ») si la branche a avancé depuis. Le run planifié, lui, reconstruit toujours la pointe de `main`, même relancé.

Suivre une exécution : `gh run watch`.

## Nettoyer les schémas CI

- **Symptôme** : des schémas `CI_PR_<n>_*` restent dans `FINTRACK_DB` alors que la PR est fermée.
- **Diagnostic** : dans Snowsight, `show terse schemas like 'CI_PR_%' in database fintrack_db;`, et comparez aux PR ouvertes : `gh pr list --state open`.
- **Action automatique** : `gh workflow run cleanup-ci.yml` supprime les schémas de toutes les PR qui ne sont plus ouvertes. Ajoutez `-f dry_run=true` pour voir d'abord la liste dans le journal.
- **Action manuelle**, avec dbt et le profil de la CI (identifiants exportés comme dans [Secrets](secrets.md#verifier)) :

    ```bash
    # lister ce qui serait supprimé, sans rien supprimer
    DBT_PROFILES_DIR=ci dbt run-operation drop_ci_schemas --target ci --args '{pr_number: 12, dry_run: true}'

    # supprimer les schémas de la PR 12
    DBT_PROFILES_DIR=ci dbt run-operation drop_ci_schemas --target ci --args '{pr_number: 12}'

    # supprimer tous les schémas CI_PR_* sauf ceux des PR 3 et 7
    DBT_PROFILES_DIR=ci dbt run-operation drop_ci_schemas --target ci --args '{keep_pr_numbers: [3, 7]}'
    ```

    La macro exige exactement un des deux paramètres, ne touche qu'aux schémas qui commencent par `CI_PR_<numéro>`, compare le numéro en entier (1 ne désigne jamais 12) et journalise chaque suppression. Attention : `keep_pr_numbers: []` supprime **tous** les schémas CI. Sa logique de sélection se vérifie sans connexion : `DBT_PROFILES_DIR=ci SNOWFLAKE_ACCOUNT=ci-offline SNOWFLAKE_USER=ci-offline dbt run-operation drop_ci_schemas_selftest --target ci`.

- **Ne supprimez pas à la main** avec un `like 'CI_PR_1_%'` : dans un `like`, `_` remplace n'importe quel caractère, et ce motif attraperait aussi `CI_PR_12_...`.
- **Vérification** : la commande de diagnostic ne liste plus que les schémas des PR ouvertes.

## Faire tourner la clé RSA

- **Quand** : périodiquement (par exemple tous les 90 jours), au départ d'une personne qui y avait accès, et **immédiatement** si la clé a pu fuiter.
- **Principe** : Snowflake accepte deux clés publiques par utilisateur (`RSA_PUBLIC_KEY` et `RSA_PUBLIC_KEY_2`). On ajoute la nouvelle, on bascule, puis on retire l'ancienne : aucune interruption.

1. Générez une nouvelle paire (`rsa_key_2.p8`, `rsa_key_2.pub`) comme dans [Secrets](secrets.md#generer-une-paire-de-cles-rsa).
2. Dans Snowsight, avec `USERADMIN` (voir la section rotation de `snowflake/04_ci_cd.sql`) :

    ```sql
    use role useradmin;
    alter user fintrack_ci_user set rsa_public_key_2 = '<nouvelle clé publique sur une ligne>';
    ```

3. Remplacez le secret, au niveau du dépôt et partout où il existe (environnements, Dependabot) :

    ```bash
    grep -v -- '-----' rsa_key_2.p8 | tr -d '\n' | gh secret set SNOWFLAKE_PRIVATE_KEY
    ```

4. Vérifiez : `gh workflow run cd.yml --ref dev`, puis `dbt debug` vert dans le journal.
5. Retirez l'ancienne clé, puis détruisez l'ancien fichier de clé privée :

    ```sql
    alter user fintrack_ci_user unset rsa_public_key;
    ```

    À la rotation suivante, la nouvelle clé ira dans l'emplacement libéré, `RSA_PUBLIC_KEY`.

- **En cas de fuite** : retirez d'abord la clé compromise (`unset`), puis suivez les étapes 1 à 4. Les jobs échouent entre les deux : c'est voulu.

## Ajouter un membre de l'équipe

- **Avant** d'accorder le droit d'écriture sur le dépôt à quelqu'un d'autre que le mainteneur : [séparez la CI de la production](secrets.md#separer-la-ci-de-la-production). Sinon, le code de ses PR s'exécuterait avec un rôle qui écrit en production.
- **GitHub** : **Settings** → **Collaborators** → **Add people**, rôle **Write**. Ajoutez-le à `.github/CODEOWNERS` s'il doit relire certains dossiers.
- **Snowflake** : un utilisateur personnel par membre, jamais `FINTRACK_USER` partagé. Dans Snowsight :

    ```sql
    use role useradmin;
    create user if not exists <PRENOM> type = person password = '<provisoire>' must_change_password = true
        default_role = FINTRACK_ROLE default_warehouse = FINTRACK_WH default_namespace = FINTRACK_DB.STAGING;
    grant role FINTRACK_ROLE to user <PRENOM>;
    ```

    Transmettez le mot de passe provisoire hors du dépôt et des tickets. Le membre se connecte d'abord à Snowsight pour le changer (dbt ne sait pas le faire), puis suit [Démarrage](demarrage.md). Sur un compte payant, préférez une paire de clés (`rsa_public_key = '...'`) à un mot de passe.

- **Vérification** : le membre lance `make debug` puis `make build` dans ses schémas `DEV_<PRENOM>_*`.

## Back-merge nécessaire

- **Symptôme** : le job `sync-check` du workflow CD affiche « back-merge main → staging → dev nécessaire ».
- **Cause** : un hotfix (ou une annulation) a été fusionné dans `main` et n'existe pas encore sur `staging` ou `dev`.
- **Action** : la procédure [Back-merge après un hotfix](workflow-git.md#back-merge-apres-un-hotfix).
- **Vérification** : ces commandes ne renvoient plus rien.

    ```bash
    git fetch origin
    git log origin/staging..origin/main --no-merges --oneline
    git log origin/dev..origin/main --no-merges --oneline
    ```

## Conflit lors d'une release ou d'un back-merge

- **Release `dev` → `staging` en conflit** : `staging` contient un commit que `dev` n'a pas, presque toujours un back-merge inachevé. Terminez d'abord le back-merge `staging` → `dev`, puis la release ne présente plus de conflit.
- **Back-merge `main` → `staging` en conflit** : résolvez sur une branche intermédiaire, jamais directement sur une branche longue.

    ```bash
    git fetch origin
    git switch -c hotfix/back-merge-statut-null origin/main
    git merge origin/staging              # résoudre les conflits, puis :
    git commit
    git push -u origin hotfix/back-merge-statut-null
    gh pr create --base staging --title "chore: back-merge main → staging"
    gh pr merge <numero> --merge          # merge commit ; mainteneur seul : ajoutez --admin
    ```

    Même méthode pour `staging` → `dev`, avec une branche `chore/back-merge-...` créée depuis `origin/staging`.

## Le run quotidien de prod échoue

- **Symptôme** : l'exécution du matin de `Scheduled prod run` est rouge, alors que le code n'a pas changé.
- **Diagnostic** : l'onglet **Summary** du job `dbt build (prod)` donne les tests en échec ; le journal complet est dans l'artefact `dbt-scheduled-prod`. Le code étant celui du dernier déploiement réussi, la cause est presque toujours dans les **données** de `RAW` : nouvelle valeur de statut, compte inconnu, doublon. Reprenez la logique du test en échec et exécutez-la dans Snowsight sur `MARTS` ou `STAGING`, en lecture seule. Ne lancez jamais dbt en local avec la target `prod`.
- **Action** :
    - donnée fausse à la source : la faire corriger par l'équipe qui alimente `RAW`, puis relancer le run ;
    - nouvelle réalité métier (nouveau statut légitime) : PR qui adapte le modèle et ses tests, cycle normal ou hotfix.
- **Run absent** : GitHub désactive les workflows planifiés d'un dépôt public après 60 jours sans activité. Réactivez-le dans **Actions** → **Scheduled prod run** → **Enable workflow**.
- **Vérification** : `gh workflow run scheduled-run.yml --ref main`, exécution verte.

## Le site de documentation n'est pas à jour

- **Diagnostic** : `gh run list --workflow docs.yml --limit 5`.
    - aucune exécution : le workflow Docs ne suit qu'un CD **réussi et déclenché par un push** (un déploiement de prod en échec, ou lancé à la main, ne republie pas le site), et un push direct ne le déclenche que s'il touche `docs/`, `assets/`, `mkdocs.yml` ou `requirements-docs.txt` (un `README.md` seul ne republie rien) ;
    - exécution rouge à l'étape de déploiement : GitHub Pages n'est pas activé en mode « GitHub Actions » (relancer `scripts/setup_github.sh`) ;
    - catalogue dbt sans types de colonnes : le workflow est passé en mode hors ligne faute de secrets Snowflake au niveau du dépôt (notice dans l'exécution).
- **Action** : `gh workflow run docs.yml --ref main`.
- **Vérification** : la page d'accueil et https://abrahamkoloboe27.github.io/FinetrackProject-Snowflake/dbt/ affichent le contenu de `main`.
