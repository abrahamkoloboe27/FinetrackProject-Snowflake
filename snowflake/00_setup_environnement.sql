-- =====================================================================
-- FinTrack Analytics — 00 : environnement Snowflake
-- Crée : entrepôt XS, base FINTRACK_DB, schémas RAW / STAGING / MARTS,
--        rôle FINTRACK_ROLE et utilisateur FINTRACK_USER (pour dbt).
--
-- À exécuter en premier, dans une feuille Snowsight ("Run all"),
-- avec un compte pouvant utiliser SYSADMIN, SECURITYADMIN et USERADMIN
-- (ACCOUNTADMIN d'un compte d'essai convient).
-- Ré-exécutable : entrepôt, base, schémas, rôle et droits sont en
-- IF NOT EXISTS / idempotents. Attention, CREATE USER IF NOT EXISTS ne
-- modifie PAS un utilisateur déjà créé : pour changer son mot de passe
-- plus tard, utilisez (en USERADMIN) :
--   ALTER USER FINTRACK_USER SET PASSWORD = '...';
--
-- Répartition des rôles :
--   SYSADMIN       crée et possède l'entrepôt, la base et les schémas
--   USERADMIN      crée le rôle et l'utilisateur
--   SECURITYADMIN  accorde les droits (seul avec ACCOUNTADMIN à détenir
--                  MANAGE GRANTS, indispensable pour les droits FUTURE)
--
-- Avant de lancer : si FINTRACK_DB existe déjà (créée à la main avec un
-- autre rôle, par exemple ACCOUNTADMIN), SYSADMIN n'en est pas
-- propriétaire et les droits ci-dessous échoueraient. Vérifiez avec
--   SHOW DATABASES LIKE 'FINTRACK_DB';   -- colonne owner = SYSADMIN ?
-- Sinon, repartez de zéro (données d'exemple, sans perte) :
--   USE ROLE ACCOUNTADMIN; DROP DATABASE IF EXISTS FINTRACK_DB;
--
-- Dans Snowsight, "Run all" n'affiche que le résultat de la DERNIÈRE
-- requête. Pour voir les contrôles de la fin du script, exécutez-les un
-- par un (curseur dans la requête, puis Ctrl+Entrée).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Entrepôt, base de données et schémas
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS FINTRACK_WH
    WITH WAREHOUSE_SIZE      = 'XSMALL'
         AUTO_SUSPEND        = 60        -- s'éteint après 60 s d'inactivité
         AUTO_RESUME         = TRUE      -- se rallume tout seul à la requête
         INITIALLY_SUSPENDED = TRUE      -- ne consomme rien à la création
    COMMENT = 'Entrepôt XS du projet FinTrack Analytics';

CREATE DATABASE IF NOT EXISTS FINTRACK_DB
    COMMENT = 'Entrepôt de données FinTrack Analytics';

CREATE SCHEMA IF NOT EXISTS FINTRACK_DB.RAW
    COMMENT = 'Données brutes, telles que chargées (sources dbt)';

CREATE SCHEMA IF NOT EXISTS FINTRACK_DB.STAGING
    COMMENT = 'Modèles dbt staging : nettoyage et renommage des sources';

CREATE SCHEMA IF NOT EXISTS FINTRACK_DB.MARTS
    COMMENT = 'Modèles dbt marts : tables analytiques finales pour la BI';

-- ---------------------------------------------------------------------
-- 2. Rôle du projet
-- ---------------------------------------------------------------------
USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS FINTRACK_ROLE
    COMMENT = 'Rôle utilisé par dbt pour le projet FinTrack Analytics';

-- Bonne pratique : SYSADMIN hérite du rôle du projet et voit donc ses objets
GRANT ROLE FINTRACK_ROLE TO ROLE SYSADMIN;

-- ---------------------------------------------------------------------
-- 3. Droits du rôle
--    Accordés par SECURITYADMIN : accorder des droits FUTURE sur un
--    schéma standard exige MANAGE GRANTS, même pour son propriétaire
--    (SYSADMIN ne peut pas le faire).
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;

GRANT USAGE ON WAREHOUSE FINTRACK_WH TO ROLE FINTRACK_ROLE;
GRANT USAGE ON DATABASE  FINTRACK_DB TO ROLE FINTRACK_ROLE;

-- RAW : lecture seule (dbt lit les sources, il ne les modifie pas).
-- Les droits FUTURE couvrent les tables créées après ce script.
GRANT USAGE  ON SCHEMA FINTRACK_DB.RAW TO ROLE FINTRACK_ROLE;
GRANT SELECT ON ALL    TABLES IN SCHEMA FINTRACK_DB.RAW TO ROLE FINTRACK_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA FINTRACK_DB.RAW TO ROLE FINTRACK_ROLE;

-- STAGING et MARTS : dbt y crée et remplace vues et tables
GRANT ALL PRIVILEGES ON SCHEMA FINTRACK_DB.STAGING TO ROLE FINTRACK_ROLE;
GRANT ALL PRIVILEGES ON SCHEMA FINTRACK_DB.MARTS   TO ROLE FINTRACK_ROLE;

-- ---------------------------------------------------------------------
-- 4. Utilisateur dédié à dbt
--
-- ⚠ MOT DE PASSE : il est écrit en clair dans ce fichier. Ne versionnez
--   pas et ne partagez pas ce fichier avec un vrai mot de passe : remettez
--   un texte à la place (ex. <MOT_DE_PASSE_A_DEFINIR>) une fois l'utilisateur
--   créé, et recopiez le vrai dans ~/.dbt/profiles.yml.
--   CREATE USER accepte n'importe quel mot de passe, mais ALTER USER et
--   l'interface web imposent la politique Snowflake actuelle : 14
--   caractères minimum, avec majuscule, minuscule et chiffre.
--
-- Connexion par mot de passe : valable sur un compte d'ESSAI (exempté de
-- l'authentification multifacteur obligatoire). Sur un compte payant ou
-- d'entreprise, dbt devra utiliser une paire de clés RSA (TYPE = SERVICE
-- et RSA_PUBLIC_KEY, sans mot de passe). Le vrai test est `dbt debug`.
-- ---------------------------------------------------------------------
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS FINTRACK_USER
    TYPE                 = PERSON    -- valeur par défaut, écrite pour mémoire
    PASSWORD             = '<MOT_DE_PASSE_A_DEFINIR>'
    DEFAULT_ROLE         = FINTRACK_ROLE
    DEFAULT_WAREHOUSE    = FINTRACK_WH
    DEFAULT_NAMESPACE    = FINTRACK_DB.STAGING
    MUST_CHANGE_PASSWORD = FALSE
    COMMENT              = 'Utilisateur dbt du projet FinTrack Analytics';

GRANT ROLE FINTRACK_ROLE TO USER FINTRACK_USER;

-- ---------------------------------------------------------------------
-- Contrôles (à exécuter un par un, voir l'en-tête)
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;
SHOW WAREHOUSES LIKE 'FINTRACK_WH';              -- 1 ligne, taille X-Small
SHOW DATABASES LIKE 'FINTRACK_DB';               -- 1 ligne, owner = SYSADMIN
SHOW SCHEMAS IN DATABASE FINTRACK_DB;            -- 5 lignes : RAW, STAGING, MARTS + PUBLIC et INFORMATION_SCHEMA
SHOW GRANTS TO ROLE FINTRACK_ROLE;               -- warehouse, database, schémas RAW / STAGING / MARTS
SHOW FUTURE GRANTS IN SCHEMA FINTRACK_DB.RAW;    -- SELECT sur les futures tables (absent de SHOW GRANTS)

USE ROLE USERADMIN;
SHOW ROLES LIKE 'FINTRACK_ROLE';                 -- 1 ligne
SHOW USERS LIKE 'FINTRACK_USER';                 -- 1 ligne, default_role = FINTRACK_ROLE