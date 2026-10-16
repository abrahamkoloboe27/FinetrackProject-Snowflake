-- =====================================================================
-- FinTrack Analytics — 04 : CI/CD (GitHub Actions)
-- Prépare Snowflake pour la CI/CD :
--   - FINTRACK_ROLE peut créer des schémas (un jeu par environnement et
--     par pull request, voir macros/generate_schema_name.sql) ;
--   - utilisateur de service FINTRACK_CI_USER, authentifié par paire de
--     clés RSA, pour GitHub Actions (recommandé) ;
--   - en option, séparation de la CI et de la production (section 6).
--
-- À exécuter après 00 à 03, dans une feuille Snowsight, avec un compte
-- pouvant utiliser SECURITYADMIN et USERADMIN (ACCOUNTADMIN d'un compte
-- d'essai convient).
--
-- La section 1 est OBLIGATOIRE avant la première CI de pull request et
-- avant la création des branches dev et staging : dbt y crée ses schémas.
--
-- DEUX VARIANTES, selon l'authentification de la CI :
--   - mot de passe (compte d'essai : SNOWFLAKE_USER = FINTRACK_USER et
--     SNOWFLAKE_PASSWORD) : exécutez UNIQUEMENT la section 1, puis le
--     contrôle SHOW GRANTS TO ROLE FINTRACK_ROLE, requête par requête
--     (sélection, puis Ctrl+Entrée). Pas de « Run all » : la section 3
--     tenterait de créer FINTRACK_CI_USER avec la clé fictive
--     <CLE_PUBLIQUE_RSA>. Les secrets GitHub ne changent pas.
--   - paire de clés (recommandé) : générez la paire (section 2), remplacez
--     <CLE_PUBLIQUE_RSA> (section 3), puis « Run all ». Dans les secrets
--     du dépôt (Settings → Secrets and variables → Actions), remplacez
--     ENSEMBLE SNOWFLAKE_USER (= FINTRACK_CI_USER) et SNOWFLAKE_PRIVATE_KEY,
--     vérifiez un job, puis supprimez SNOWFLAKE_PASSWORD.
-- Détail : docs/secrets.md.
--
-- Ré-exécutable : GRANT et CREATE USER IF NOT EXISTS sont idempotents.
-- Attention, CREATE USER IF NOT EXISTS ne modifie PAS un utilisateur déjà
-- créé : pour changer sa clé, suivez la rotation (section 4).
--
-- Dans Snowsight, "Run all" n'affiche que le résultat de la DERNIÈRE
-- requête. Pour voir les contrôles de la fin du script, exécutez-les un
-- par un (curseur dans la requête, puis Ctrl+Entrée).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Droit de créer des schémas (obligatoire, les deux variantes)
--
-- Hors production, chaque environnement a ses propres schémas, que dbt
-- crée à la volée :
--   DEV_STAGING, DEV_MARTS             branche dev
--   PREPROD_STAGING, PREPROD_MARTS     branche staging (recette)
--   CI_PR_<n>_STAGING, CI_PR_<n>_MARTS une paire par pull request,
--                                      supprimée à sa fermeture
--   DEV_<PRENOM>_STAGING, ...          poste de chaque développeur
-- FINTRACK_ROLE en devient propriétaire : il peut les remplacer et les
-- supprimer (macro drop_ci_schemas). La production reste dans STAGING et
-- MARTS, créés par 00 et possédés par SYSADMIN.
--
-- Accordé par SECURITYADMIN (MANAGE GRANTS), comme les droits de 00.
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;

GRANT CREATE SCHEMA ON DATABASE FINTRACK_DB TO ROLE FINTRACK_ROLE;

-- ---------------------------------------------------------------------
-- 2. Paire de clés RSA de la CI : à générer sur votre poste, PAS ici
--
-- Dans un terminal, dans un dossier HORS du dépôt :
--
--   # clé privée PKCS#8, non chiffrée (le plus simple pour la CI)
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -nocrypt -out rsa_key.p8
--   # variante chiffrée : remplacez -nocrypt par -v2 aes-256-cbc ;
--   # la passphrase va alors dans SNOWFLAKE_PRIVATE_KEY_PASSPHRASE
--
--   # clé publique correspondante
--   openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
--
--   # valeur à coller à la place de <CLE_PUBLIQUE_RSA> (section 3) :
--   # la clé sans ses lignes -----BEGIN/END----- ni retours à la ligne
--   grep -v -- '-----' rsa_key.pub | tr -d '\n'
--
--   # valeur du secret GitHub SNOWFLAKE_PRIVATE_KEY, sur une seule ligne
--   grep -v -- '-----' rsa_key.p8 | tr -d '\n'
--
-- ⚠ CLÉ PRIVÉE : elle ne sert qu'à remplir le secret GitHub. Ne la
--   versionnez jamais (.gitignore exclut *.p8, *.pem et rsa_key*), ne la
--   collez ni dans ce fichier, ni dans une PR, ni dans un ticket. Une fois
--   le secret enregistré, rangez-la dans un coffre-fort de mots de passe
--   ou supprimez-la : en cas de perte, on en génère simplement une autre.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 3. Utilisateur de service de la CI (variante paire de clés)
--
-- TYPE = SERVICE : pas de mot de passe, pas d'accès à l'interface web,
-- et pas d'authentification multifacteur à valider. Seule la clé privée
-- associée à RSA_PUBLIC_KEY permet de se connecter. Il reçoit
-- FINTRACK_ROLE, comme FINTRACK_USER.
--
-- Variante mot de passe (FINTRACK_USER et SNOWFLAKE_PASSWORD, sans cette
-- section) : un dépannage temporaire du compte d'essai. Ce mot de passe
-- ouvre aussi Snowsight, sans second facteur ; cinq échecs de connexion
-- verrouillent FINTRACK_USER, ce qui bloque la CI/CD ET le développeur ;
-- et Snowflake le refuse dès que le compte devient payant. Passez à la
-- paire de clés dès que possible.
--
-- Dans les deux variantes, la CI de PR et les déploiements utilisent le
-- même rôle, qui écrit en production. Acceptable tant que vous êtes seul
-- à avoir le droit d'écriture sur le dépôt : avant d'ajouter un
-- collaborateur, séparez la CI de la production (section 6).
-- ---------------------------------------------------------------------
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS FINTRACK_CI_USER
    TYPE              = SERVICE
    RSA_PUBLIC_KEY    = '<CLE_PUBLIQUE_RSA>'
    DEFAULT_ROLE      = FINTRACK_ROLE
    DEFAULT_WAREHOUSE = FINTRACK_WH
    DEFAULT_NAMESPACE = FINTRACK_DB.STAGING
    COMMENT           = 'Utilisateur de service de la CI/CD GitHub Actions (FinTrack Analytics)';

GRANT ROLE FINTRACK_ROLE TO USER FINTRACK_CI_USER;

-- ---------------------------------------------------------------------
-- 4. Rotation de la clé, sans interruption de la CI
--
-- Snowflake accepte deux clés publiques à la fois (RSA_PUBLIC_KEY et
-- RSA_PUBLIC_KEY_2). À faire le moment venu, étape par étape (retirez
-- le « -- » de la commande à exécuter) :
--   a. générez une nouvelle paire (section 2) ;
--   b. déclarez la nouvelle clé publique comme seconde clé :
-- USE ROLE USERADMIN;
-- ALTER USER FINTRACK_CI_USER SET RSA_PUBLIC_KEY_2 = '<NOUVELLE_CLE_PUBLIQUE_RSA>';
--   c. remplacez le secret GitHub SNOWFLAKE_PRIVATE_KEY par la nouvelle
--      clé privée, puis relancez un job : dbt debug doit réussir ;
--   d. retirez l'ancienne clé :
-- ALTER USER FINTRACK_CI_USER UNSET RSA_PUBLIC_KEY;
-- À la rotation suivante, inversez les rôles : nouvelle clé dans
-- RSA_PUBLIC_KEY, puis UNSET RSA_PUBLIC_KEY_2.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 5. (Optionnel) Plafond de crédits
--
-- Chaque pull request lance un dbt build : un moniteur de ressources
-- borne la consommation de l'entrepôt. Réservé à ACCOUNTADMIN. Pour
-- l'activer, retirez les « -- » et ajustez CREDIT_QUOTA.
-- ---------------------------------------------------------------------
-- USE ROLE ACCOUNTADMIN;
--
-- CREATE RESOURCE MONITOR IF NOT EXISTS FINTRACK_RM
--     WITH CREDIT_QUOTA    = 10            -- crédits par mois
--          FREQUENCY       = MONTHLY
--          START_TIMESTAMP = IMMEDIATELY
--          TRIGGERS ON  80 PERCENT DO NOTIFY              -- alerte des administrateurs
--                   ON 100 PERCENT DO SUSPEND             -- finit les requêtes en cours, puis s'arrête
--                   ON 110 PERCENT DO SUSPEND_IMMEDIATE;  -- coupe tout, tout de suite
--
-- ALTER WAREHOUSE FINTRACK_WH SET RESOURCE_MONITOR = FINTRACK_RM;

-- ---------------------------------------------------------------------
-- 6. Séparer la CI de la production : OBLIGATOIRE avant d'ajouter un
--    collaborateur qui a le droit d'écriture sur le dépôt
--
-- Les secrets du dépôt servent à la CI de PR, qui exécute le code de la
-- PR (macros, hooks) AVANT toute revue. Avec FINTRACK_ROLE, ce code peut
-- modifier ou supprimer la production. Après cette section :
--   - FINTRACK_CI_USER n'a plus que FINTRACK_CI_ROLE : lecture de RAW,
--     lecture seule de STAGING et MARTS (--defer de la Slim CI, catalogue
--     de la documentation), création de ses schémas CI_PR_* ; aucune
--     écriture en production ;
--   - FINTRACK_DEPLOY_USER (SERVICE, sa propre paire de clés) garde
--     FINTRACK_ROLE, et ses secrets ne vont QUE dans les environnements
--     GitHub dev, staging et prod, chacun limité à sa branche.
-- Secrets GitHub après la bascule (docs/secrets.md) :
--   dépôt               SNOWFLAKE_USER = FINTRACK_CI_USER, sa clé dans
--                       SNOWFLAKE_PRIVATE_KEY, SNOWFLAKE_ROLE = FINTRACK_CI_ROLE
--   dev, staging, prod  SNOWFLAKE_USER = FINTRACK_DEPLOY_USER, sa clé dans
--                       SNOWFLAKE_PRIVATE_KEY, SNOWFLAKE_ROLE = FINTRACK_ROLE
-- Prérequis : la variante paire de clés (sections 2 et 3). Basculez sans
-- PR ouverte, après le nettoyage des schémas CI (gh workflow run
-- cleanup-ci.yml) : les schémas CI_PR_* existants appartiennent à
-- FINTRACK_ROLE, que l'utilisateur de la CI n'aura plus.
-- Pour l'exécuter : générez une seconde paire de clés (section 2),
-- remplacez <CLE_PUBLIQUE_RSA_DEPLOY>, retirez les « -- » en tête des
-- commandes, puis exécutez cette section seule.
-- ---------------------------------------------------------------------
-- USE ROLE USERADMIN;
-- CREATE ROLE IF NOT EXISTS FINTRACK_CI_ROLE
--     COMMENT = 'CI de PR : lecture seule de la production, schémas CI_PR_* (FinTrack Analytics)';
-- GRANT ROLE FINTRACK_CI_ROLE TO ROLE SYSADMIN;
--
-- USE ROLE SECURITYADMIN;
-- GRANT USAGE ON WAREHOUSE FINTRACK_WH TO ROLE FINTRACK_CI_ROLE;
-- GRANT USAGE ON DATABASE  FINTRACK_DB TO ROLE FINTRACK_CI_ROLE;
-- GRANT CREATE SCHEMA ON DATABASE FINTRACK_DB TO ROLE FINTRACK_CI_ROLE;
-- GRANT USAGE  ON SCHEMA FINTRACK_DB.RAW TO ROLE FINTRACK_CI_ROLE;
-- GRANT SELECT ON ALL    TABLES IN SCHEMA FINTRACK_DB.RAW TO ROLE FINTRACK_CI_ROLE;
-- GRANT SELECT ON FUTURE TABLES IN SCHEMA FINTRACK_DB.RAW TO ROLE FINTRACK_CI_ROLE;
-- GRANT USAGE  ON SCHEMA FINTRACK_DB.STAGING TO ROLE FINTRACK_CI_ROLE;
-- GRANT SELECT ON ALL    VIEWS IN SCHEMA FINTRACK_DB.STAGING TO ROLE FINTRACK_CI_ROLE;
-- GRANT SELECT ON FUTURE VIEWS IN SCHEMA FINTRACK_DB.STAGING TO ROLE FINTRACK_CI_ROLE;
-- GRANT USAGE  ON SCHEMA FINTRACK_DB.MARTS TO ROLE FINTRACK_CI_ROLE;
-- GRANT SELECT ON ALL    TABLES IN SCHEMA FINTRACK_DB.MARTS TO ROLE FINTRACK_CI_ROLE;
-- GRANT SELECT ON FUTURE TABLES IN SCHEMA FINTRACK_DB.MARTS TO ROLE FINTRACK_CI_ROLE;
--
-- USE ROLE USERADMIN;
-- GRANT ROLE FINTRACK_CI_ROLE TO USER FINTRACK_CI_USER;
-- ALTER USER FINTRACK_CI_USER SET DEFAULT_ROLE = FINTRACK_CI_ROLE;
-- REVOKE ROLE FINTRACK_ROLE FROM USER FINTRACK_CI_USER;
--
-- CREATE USER IF NOT EXISTS FINTRACK_DEPLOY_USER
--     TYPE              = SERVICE
--     RSA_PUBLIC_KEY    = '<CLE_PUBLIQUE_RSA_DEPLOY>'
--     DEFAULT_ROLE      = FINTRACK_ROLE
--     DEFAULT_WAREHOUSE = FINTRACK_WH
--     DEFAULT_NAMESPACE = FINTRACK_DB.STAGING
--     COMMENT           = 'Déploiements dev, staging et prod de GitHub Actions (FinTrack Analytics)';
-- GRANT ROLE FINTRACK_ROLE TO USER FINTRACK_DEPLOY_USER;
--
-- Contrôles, un par un :
-- USE ROLE SECURITYADMIN;
-- SHOW GRANTS TO ROLE FINTRACK_CI_ROLE;        -- aucun droit d'écriture sur STAGING ni MARTS
-- SHOW GRANTS TO USER FINTRACK_CI_USER;        -- 1 ligne : FINTRACK_CI_ROLE
-- SHOW GRANTS TO USER FINTRACK_DEPLOY_USER;    -- 1 ligne : FINTRACK_ROLE

-- ---------------------------------------------------------------------
-- Contrôles (à exécuter un par un, voir l'en-tête). Variante mot de
-- passe : seul le premier SHOW GRANTS concerne votre configuration.
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;
SHOW GRANTS TO ROLE FINTRACK_ROLE;               -- nouvelle ligne : CREATE SCHEMA sur la base FINTRACK_DB
SHOW GRANTS TO USER FINTRACK_CI_USER;            -- paire de clés : 1 ligne, FINTRACK_ROLE

USE ROLE USERADMIN;
DESC USER FINTRACK_CI_USER;                      -- paire de clés : TYPE = SERVICE, RSA_PUBLIC_KEY_FP renseigné
-- RSA_PUBLIC_KEY_FP doit valoir « SHA256: » suivi de l'empreinte calculée
-- sur votre poste :
--   openssl rsa -pubin -in rsa_key.pub -outform DER | openssl dgst -sha256 -binary | openssl enc -base64

-- Valeur du secret SNOWFLAKE_ACCOUNT (identifiant ORGANISATION-COMPTE)
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS snowflake_account;

-- Schémas créés par dbt hors production (aucune ligne tant que la CI/CD
-- n'a pas tourné). STARTSWITH plutôt que LIKE : dans un motif LIKE, « _ »
-- remplace n'importe quel caractère.
USE ROLE FINTRACK_ROLE;
USE WAREHOUSE FINTRACK_WH;
SELECT schema_name, schema_owner, created
FROM FINTRACK_DB.INFORMATION_SCHEMA.SCHEMATA
WHERE STARTSWITH(schema_name, 'CI_PR_')
   OR STARTSWITH(schema_name, 'DEV_')
   OR STARTSWITH(schema_name, 'PREPROD_')
ORDER BY schema_name;

-- Requêtes de la CI/CD sur 7 jours, par étiquette (query_tag posé par les
-- workflows, ex. github-ci-pr-12). ACCOUNT_USAGE exige ACCOUNTADMIN (ou
-- IMPORTED PRIVILEGES sur la base SNOWFLAKE) et a jusqu'à 45 minutes de
-- retard.
USE ROLE ACCOUNTADMIN;
SELECT query_tag,
       user_name,
       COUNT(*)                                 AS nb_requetes,
       ROUND(SUM(total_elapsed_time) / 1000, 1) AS duree_totale_s,
       MIN(start_time)                          AS debut,
       MAX(end_time)                            AS fin
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_tag LIKE 'github-%'
  AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY query_tag, user_name
ORDER BY debut DESC;
