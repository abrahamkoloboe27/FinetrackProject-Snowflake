# Secrets

Aucun secret n'est versionné. Les identifiants Snowflake de GitHub Actions sont des **secrets GitHub** : chiffrés, masqués dans les journaux, et injectés dans les jobs sous forme de variables d'environnement lues par `ci/profiles.yml`.

## La configuration actuelle

Les secrets du dépôt sont déjà enregistrés : `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` (`FINTRACK_USER`, utilisateur de type `PERSON`) et `SNOWFLAKE_PASSWORD`. La CI s'authentifie donc par mot de passe, ce qu'accepte un compte d'essai. Les secrets optionnels prennent leur valeur par défaut.

1. **Obligatoire**, avant la CI de PR et avant les environnements `dev` et `staging` : la section 1 de `snowflake/04_ci_cd.sql`, qui donne le droit `CREATE SCHEMA` à `FINTRACK_ROLE`. Voir [Exécuter le script 04](#script-04).
2. **Recommandé** ensuite : la paire de clés avec l'utilisateur de service `FINTRACK_CI_USER`. Voir [Passer à la paire de clés](#passer-a-la-paire-de-cles).
3. **Obligatoire avant d'ajouter un collaborateur** qui a le droit d'écriture sur le dépôt : [séparer la CI de la production](#separer-la-ci-de-la-production).

## La liste des secrets

| Secret | Obligatoire | Contenu | Défaut si absent |
|---|---|---|---|
| `SNOWFLAKE_ACCOUNT` | **oui** | identifiant du compte, ex. `ORGNAME-ACCOUNTNAME` | — |
| `SNOWFLAKE_USER` | **oui** | utilisateur Snowflake : `FINTRACK_USER` aujourd'hui (mot de passe), `FINTRACK_CI_USER` avec la paire de clés | — |
| `SNOWFLAKE_PRIVATE_KEY` | oui, sauf mot de passe | clé privée RSA, en base64 sur une ligne ([format](#le-format-de-la-cle-privee)) | — |
| `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` | seulement si la clé est chiffrée | phrase secrète de la clé | aucune |
| `SNOWFLAKE_PASSWORD` | oui, sauf clé privée | mot de passe (compte d'essai uniquement, solution temporaire) | — |
| `SNOWFLAKE_ROLE` | non | rôle | `FINTRACK_ROLE` |
| `SNOWFLAKE_WAREHOUSE` | non | entrepôt | `FINTRACK_WH` |
| `SNOWFLAKE_DATABASE` | non | base | `FINTRACK_DB` |

Il faut donc `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` et **une** méthode d'authentification :

=== "Paire de clés (recommandé)"

    `SNOWFLAKE_PRIVATE_KEY`, plus `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` si la clé est chiffrée. L'utilisateur est `FINTRACK_CI_USER`, de type `SERVICE` : il ne peut pas se connecter avec un mot de passe ni à l'interface web, et n'est pas soumis à l'authentification multifacteur. Fonctionne sur tout compte Snowflake.

=== "Mot de passe (configuration actuelle, temporaire)"

    `SNOWFLAKE_PASSWORD`, avec un utilisateur de type `PERSON` comme `FINTRACK_USER`. Accepté sur un compte d'essai, exempté de l'authentification multifacteur obligatoire. C'est un dépannage temporaire :

    - ce mot de passe ouvre aussi Snowsight, sans second facteur ;
    - cinq échecs de connexion verrouillent l'utilisateur, ce qui bloque la CI/CD **et** le développeur qui s'en sert ;
    - sur un compte payant (à la fin de l'essai), ou si l'utilisateur est inscrit au MFA, Snowflake refuse la connexion : CI, CD, Docs et run planifié échouent tous.

    Passez à la paire de clés dès que possible : [Passer à la paire de clés](#passer-a-la-paire-de-cles).

Si une clé privée et un mot de passe sont tous deux présents, **la clé l'emporte**. Vous pouvez alors supprimer le mot de passe : `gh secret delete SNOWFLAKE_PASSWORD`.

## Où ajouter les secrets

### Au niveau du dépôt

**Settings → Secrets and variables → Actions → onglet Secrets → New repository secret.**

Ces secrets servent à tous les workflows : la CI de PR (`dbt build (CI)`), la documentation, le nettoyage des schémas CI, et les déploiements tant qu'un environnement ne les remplace pas.

### Au niveau d'un environnement

**Settings → Environments → `dev`, `staging` ou `prod` → Environment secrets → Add environment secret.**

Un secret d'environnement **remplace** le secret du dépôt de même nom, pour les seuls jobs qui déclarent cet environnement : `Deploy (dev)`, `Deploy (staging)`, `Deploy (prod)` et le run quotidien (`prod`). Usage principal : les identifiants de déploiement, qui écrivent dans les environnements (voir [Séparer la CI de la production](#separer-la-ci-de-la-production)). Seul, un utilisateur dédié dans l'environnement `prod` ne protège rien : l'utilisateur du dépôt, lu par la CI de PR, garderait `FINTRACK_ROLE` et donc le droit d'écrire en production.

| Workflow / job | Secrets utilisés |
|---|---|
| CI : `dbt build (CI)` | dépôt |
| CD : `Deploy (dev)` | environnement `dev`, sinon dépôt |
| CD : `Deploy (staging)` | environnement `staging`, sinon dépôt |
| CD : `Deploy (prod)` | environnement `prod`, sinon dépôt |
| Scheduled prod run | environnement `prod`, sinon dépôt |
| Docs : `Build docs` | dépôt |
| CI cleanup | dépôt |

Pour démarrer, et tant que vous êtes seul à avoir le droit d'écriture sur le dépôt, les secrets du dépôt suffisent. Après la [séparation de la CI et de la production](#separer-la-ci-de-la-production), les secrets des environnements deviennent obligatoires pour les déploiements.

### Dependabot

Les workflows déclenchés par Dependabot ne voient **pas** les secrets Actions, seulement les secrets Dependabot (**Settings → Secrets and variables → Dependabot**). Le job `dbt build (CI)` est donc **ignoré** sur les PR de Dependabot : inutile d'y recopier les secrets Snowflake. Ses mises à jour sont validées par `dbt parse`, `Lint` et `Docs build`, puis construites sur Snowflake au déploiement de `dev`. Pour une montée de version de dbt, lancez `make build` en local sur sa branche (`gh pr checkout <n>`) avant de fusionner.

### En ligne de commande

`gh secret set` lit la valeur sur l'entrée standard ou la demande sans l'afficher : elle n'apparaît ni à l'écran ni dans l'historique du shell.

```bash
gh secret set SNOWFLAKE_ACCOUNT                     # saisie masquée
gh secret set SNOWFLAKE_USER --body "FINTRACK_CI_USER"
grep -v -- '-----' rsa_key.p8 | tr -d '\n' | gh secret set SNOWFLAKE_PRIVATE_KEY
gh secret set SNOWFLAKE_USER --env prod             # secret de l'environnement prod
gh secret list                                      # noms et dates, jamais les valeurs
```

## Générer une paire de clés RSA

Sur votre poste, **hors du dépôt** (les fichiers `*.p8` et `*.pem` sont de toute façon ignorés par Git) :

```bash
mkdir -p ~/.snowflake && cd ~/.snowflake
chmod 700 ~/.snowflake

# clé privée non chiffrée, au format PKCS#8
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt

# clé publique correspondante
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
chmod 600 rsa_key.p8
```

??? note "Variante : clé privée chiffrée par une phrase secrète"

    ```bash
    openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes-256-cbc -inform PEM -out rsa_key.p8
    ```

    openssl demande la phrase secrète. Enregistrez-la dans `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE`.

La clé publique, sans ses lignes d'en-tête, va dans Snowflake :

```bash
grep -v -- '-----' rsa_key.pub | tr -d '\n'; echo
```

### Le format de la clé privée

`SNOWFLAKE_PRIVATE_KEY` attend **le corps de la clé, en base64, sur une seule ligne** : le contenu de `rsa_key.p8` sans les lignes `-----BEGIN/END ...-----` ni retours à la ligne. dbt-snowflake le décode lui-même. Ce format évite les pièges des secrets multi-lignes.

```bash
# Linux et macOS : directement vers le secret, sans affichage
grep -v -- '-----' rsa_key.p8 | tr -d '\n' | gh secret set SNOWFLAKE_PRIVATE_KEY

# équivalent avec openssl (Linux) : conversion explicite en DER puis base64
openssl pkcs8 -topk8 -nocrypt -in rsa_key.p8 -outform DER | base64 -w0 | gh secret set SNOWFLAKE_PRIVATE_KEY
```

Pour coller la valeur dans l'interface web à la place, copiez-la dans le presse-papiers sans l'afficher : `grep -v -- '-----' rsa_key.p8 | tr -d '\n' | pbcopy` (macOS) ou `| xclip -selection clipboard` (Linux).

!!! warning "Pièges connus"

    - **Clé non chiffrée** : `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` doit être **absent ou vide**. Une phrase fournie pour une clé non chiffrée fait échouer la connexion (`Password was given but private key is not encrypted`).
    - **Clé chiffrée** : la phrase est obligatoire (`Password was not given but private key is encrypted`), et doit être exacte (`Incorrect password`).
    - Le PEM complet avec ses en-têtes est aussi accepté, à condition de commencer **exactement** par `-----BEGIN`. Un espace ou une ligne vide avant donne `Incorrect padding`. Un PEM collé sur une ligne avec des `\n` littéraux est refusé.
    - Une clé mal formée ne casse ni `dbt parse` ni la documentation hors ligne : l'erreur n'apparaît qu'à la connexion, dans `dbt debug`.

## Exécuter le script 04_ci_cd.sql {#script-04}

`snowflake/04_ci_cd.sql` prépare Snowflake pour la CI/CD. Il est idempotent, et s'exécute après les scripts `00` à `03`, dans une feuille Snowsight, avec un compte qui peut utiliser `SECURITYADMIN` et `USERADMIN` (`ACCOUNTADMIN` d'un compte d'essai convient ; il sert aussi au moniteur de ressources optionnel et à la requête de suivi de consommation).

Sa **section 1** (droit `CREATE SCHEMA`) est obligatoire avant la première CI de PR et avant la création de `dev` et `staging`. Les sections 2 et 3 ne servent qu'à la paire de clés.

=== "Mot de passe (configuration actuelle)"

    1. Ouvrez le script dans Snowsight.
    2. Sélectionnez **seulement la section 1** (`USE ROLE SECURITYADMIN;` et `GRANT CREATE SCHEMA ON DATABASE FINTRACK_DB TO ROLE FINTRACK_ROLE;`), puis Ctrl+Entrée. Pas de « Run all » : la section 3 tenterait de créer `FINTRACK_CI_USER` avec la clé fictive `<CLE_PUBLIQUE_RSA>`, et Snowsight s'arrêterait sur une erreur qui ferait croire à un échec complet.
    3. Contrôlez avec `SHOW GRANTS TO ROLE FINTRACK_ROLE;` : une ligne `CREATE SCHEMA` sur la base `FINTRACK_DB`.
    4. Les secrets `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` (`FINTRACK_USER`) et `SNOWFLAKE_PASSWORD` ne changent pas.

=== "Paire de clés (recommandé)"

    1. Ouvrez le script dans Snowsight.
    2. Remplacez `<CLE_PUBLIQUE_RSA>` par la clé publique sur une ligne (commande ci-dessus). Ne versionnez pas cette modification : remettez le texte d'origine ensuite. La clé publique n'est pas un secret, mais le fichier versionné reste un modèle.
    3. Exécutez le script (« Run all »). Il :
        - accorde, avec `SECURITYADMIN`, `CREATE SCHEMA` sur `FINTRACK_DB` à `FINTRACK_ROLE`, pour les schémas `DEV_*`, `PREPROD_*` et `CI_PR_*` ;
        - crée, avec `USERADMIN`, l'utilisateur de service `FINTRACK_CI_USER` (`TYPE = SERVICE`, clé publique RSA, rôle `FINTRACK_ROLE`, entrepôt `FINTRACK_WH`) et lui donne le rôle ;
        - documente en commentaire la rotation de la clé, un moniteur de ressources pour plafonner les crédits et la séparation de la CI et de la production.
    4. Lancez les contrôles de fin de script un par un (curseur dans la requête, puis Ctrl+Entrée) : `SHOW GRANTS TO ROLE FINTRACK_ROLE` (nouvelle ligne `CREATE SCHEMA`), `SHOW GRANTS TO USER FINTRACK_CI_USER`, `DESC USER FINTRACK_CI_USER` (`TYPE = SERVICE`, empreinte de clé renseignée).
    5. Mettez à jour les secrets du dépôt : [Passer à la paire de clés](#passer-a-la-paire-de-cles).

Pour vérifier que Snowflake a la bonne clé, comparez l'empreinte affichée par `DESC USER FINTRACK_CI_USER` (propriété `RSA_PUBLIC_KEY_FP`, de la forme `SHA256:...`) à celle de votre clé publique :

```bash
openssl rsa -pubin -in rsa_key.pub -outform DER | openssl dgst -sha256 -binary | openssl enc -base64
```

!!! danger "La clé privée ne quitte pas votre poste"

    Elle va dans le secret GitHub et dans un gestionnaire de mots de passe, nulle part ailleurs : ni dans le dépôt, ni dans un ticket, ni dans une conversation. Les hooks pre-commit `detect-private-key` (clé PEM avec en-tête) et `detect-private-key-base64` (clé RSA en base64 sur une ligne) bloquent un commit qui en contiendrait une, et `ci-profiles-env-var-only` refuse tout identifiant écrit en clair dans `ci/profiles.yml`. Aucun hook ne repère un mot de passe ailleurs : n'en collez jamais dans un fichier du dépôt.

## Passer à la paire de clés

Pour quitter le mot de passe de `FINTRACK_USER` :

1. Générez la paire ([plus haut](#generer-une-paire-de-cles-rsa)), puis exécutez les sections 2 et 3 du script 04 (onglet « Paire de clés » de [la section précédente](#script-04)).
2. Changez **ensemble** l'utilisateur et la clé. La clé l'emporte sur le mot de passe : une clé présentée pour `FINTRACK_USER` donnerait `JWT token is invalid`.

    ```bash
    gh secret set SNOWFLAKE_USER --body "FINTRACK_CI_USER"
    grep -v -- '-----' ~/.snowflake/rsa_key.p8 | tr -d '\n' | gh secret set SNOWFLAKE_PRIVATE_KEY
    ```

3. Vérifiez qu'un job passe ([Vérifier](#verifier)) : l'étape `dbt debug` affiche « All checks passed! ».
4. Supprimez le mot de passe : `gh secret delete SNOWFLAKE_PASSWORD`.
5. Conseillé : changez le mot de passe de `FINTRACK_USER`, qui a séjourné dans GitHub (puis votre `~/.dbt/profiles.yml`), et activez l'authentification multifacteur des utilisateurs humains.

## Séparer la CI de la production

Le job `dbt build (CI)` exécute le code de la PR (macros, hooks, et même les workflows qu'elle modifie) **avant toute revue**, avec les secrets du dépôt. Tant que ces secrets donnent `FINTRACK_ROLE`, propriétaire des tables de production, ce code peut les modifier ou les supprimer. Les règles d'un environnement (branche autorisée, relecteur) ne protègent que **ses** secrets, pas ceux du dépôt : toute personne qui peut pousser une branche peut aussi y ajouter un workflow qui les lit.

C'est acceptable tant que vous êtes seul à avoir le droit d'écriture sur le dépôt. **Avant d'ajouter un collaborateur**, séparez les deux :

| Utilisateur Snowflake | Rôle | Droits | Secrets GitHub |
|---|---|---|---|
| `FINTRACK_CI_USER` | `FINTRACK_CI_ROLE` | lecture de `RAW`, lecture seule de `STAGING` et `MARTS` (`--defer`, catalogue de la doc), création de ses schémas `CI_PR_*` | dépôt : `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY`, `SNOWFLAKE_ROLE` = `FINTRACK_CI_ROLE` |
| `FINTRACK_DEPLOY_USER` | `FINTRACK_ROLE` | écriture dans tous les environnements, production comprise | environnements `dev`, `staging` et `prod` : `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY`, `SNOWFLAKE_ROLE` = `FINTRACK_ROLE` |

1. Passez d'abord à la [paire de clés](#passer-a-la-paire-de-cles).
2. Générez une seconde paire, pour les déploiements : `rsa_key_deploy.p8` et `rsa_key_deploy.pub` ([plus haut](#generer-une-paire-de-cles-rsa)).
3. Fermez ou fusionnez les PR ouvertes, puis `gh workflow run cleanup-ci.yml` : les schémas `CI_PR_*` existants appartiennent à `FINTRACK_ROLE`, que l'utilisateur de la CI n'aura plus.
4. Dans Snowsight, section 6 de `snowflake/04_ci_cd.sql` : remplacez `<CLE_PUBLIQUE_RSA_DEPLOY>`, retirez les `--` en tête des commandes, exécutez la section seule, puis ses contrôles.
5. Enregistrez les secrets des trois environnements, puis le rôle de la CI au niveau du dépôt :

    ```bash
    for env in dev staging prod; do
      gh secret set SNOWFLAKE_USER --env "$env" --body "FINTRACK_DEPLOY_USER"
      gh secret set SNOWFLAKE_ROLE --env "$env" --body "FINTRACK_ROLE"
      grep -v -- '-----' ~/.snowflake/rsa_key_deploy.p8 | tr -d '\n' | gh secret set SNOWFLAKE_PRIVATE_KEY --env "$env"
    done
    gh secret set SNOWFLAKE_ROLE --body "FINTRACK_CI_ROLE"
    ```

6. Vérifiez : `gh workflow run cd.yml --ref dev` (vert), puis une PR de test vers `dev` (cinq checks verts).

Les workflows ne changent pas : la CI de PR, la documentation et le nettoyage lisent les secrets du dépôt, en lecture seule sur la production ; les déploiements et le run planifié lisent ceux de leur environnement. Un environnement sans ses secrets retombe sur l'utilisateur de la CI, qui ne peut pas écrire dans ses schémas : le déploiement échoue au lieu de passer avec de mauvais droits.

## Vérifier

1. Les secrets sont enregistrés :

    ```bash
    gh secret list
    gh secret list --env prod
    ```

2. La connexion fonctionne depuis votre poste, avec le profil de la CI (les variables restent dans ce terminal) :

    === "Mot de passe"

        ```bash
        export SNOWFLAKE_ACCOUNT="ORGNAME-ACCOUNTNAME" SNOWFLAKE_USER="FINTRACK_USER"
        unset SNOWFLAKE_PRIVATE_KEY SNOWFLAKE_PRIVATE_KEY_PASSPHRASE   # la clé l'emporterait
        read -rs SNOWFLAKE_PASSWORD && export SNOWFLAKE_PASSWORD      # saisie masquée (bash et zsh)
        DBT_PROFILES_DIR=ci dbt debug --target ci
        ```

    === "Paire de clés"

        ```bash
        export SNOWFLAKE_ACCOUNT="ORGNAME-ACCOUNTNAME" SNOWFLAKE_USER="FINTRACK_CI_USER"
        export SNOWFLAKE_PRIVATE_KEY="$(grep -v -- '-----' ~/.snowflake/rsa_key.p8 | tr -d '\n')"
        DBT_PROFILES_DIR=ci dbt debug --target ci
        ```

3. La connexion fonctionne dans GitHub Actions : relancez un job qui utilise les secrets.

    ```bash
    gh run list --workflow ci.yml --limit 5      # repérer une exécution en échec
    gh run rerun <run-id> --failed               # relancer ses jobs en échec
    gh workflow run cd.yml --ref dev             # ou redéployer dev
    gh run watch                                 # suivre l'exécution
    ```

    L'étape `dbt debug` doit afficher « All checks passed! ».

## Quand un secret manque

Avant toute connexion, `scripts/ci/check_snowflake_env.sh` vérifie que `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` et (`SNOWFLAKE_PRIVATE_KEY` ou `SNOWFLAKE_PASSWORD`) ne sont pas vides. Il repère aussi, sans jamais l'afficher, les pièges de format de la clé : espace ou ligne vide en tête, `\n` littéraux, clé chiffrée sans phrase secrète, phrase secrète fournie pour une clé PEM non chiffrée. Il signale enfin quand clé et mot de passe sont tous deux présents (la clé est utilisée).

| Mode | Utilisé par | Si un secret manque |
|---|---|---|
| strict (défaut) | `dbt build (CI)`, `Deploy (<env>)` | erreur qui liste les secrets manquants et les problèmes de format, et renvoie vers cette page : le job échoue |
| souple (`--soft`) | Docs, CI cleanup, Scheduled prod run | avertissement, puis le workflow passe en mode dégradé (documentation hors ligne) ou saute les étapes Snowflake |

La même liste apparaît dans l'onglet **Summary** de l'exécution. Pour tester en local, avec les variables exportées : `bash scripts/ci/check_snowflake_env.sh`.

Diagnostic des autres erreurs : [Runbooks](runbooks.md#secrets-snowflake-manquants-ou-invalides). Rotation de la clé : [Runbooks](runbooks.md#faire-tourner-la-cle-rsa).
