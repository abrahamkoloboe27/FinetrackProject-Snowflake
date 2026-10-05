-- =====================================================================
-- FinTrack Analytics — 01 : tables sources (schéma RAW)
-- Crée les 4 tables de données brutes décrites en section 1.2 du sujet.
--
-- À exécuter APRÈS 00_setup_environnement.sql.
-- Ré-exécutable : CREATE OR REPLACE repart d'une table vide
-- (relancez ensuite 02_inserer_donnees.sql).
--
-- Remarque : RAW = données brutes, volontairement sans contraintes.
-- Snowflake n'applique de toute façon pas PRIMARY KEY / FOREIGN KEY
-- (seul NOT NULL est appliqué). L'unicité et l'intégrité référentielle
-- sont vérifiées plus tard par les tests dbt (unique, not_null,
-- relationships).
-- =====================================================================

USE ROLE SYSADMIN;
USE SCHEMA FINTRACK_DB.RAW;

-- ---------------------------------------------------------------------
-- raw_comptes : un compte bancaire par ligne
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE raw_comptes (
    id              INTEGER        COMMENT 'Identifiant unique du compte',
    nom_client      VARCHAR(100)   COMMENT 'Nom complet du client',
    email           VARCHAR(150)   COMMENT 'Adresse email du client',
    type_compte     VARCHAR(20)    COMMENT 'Type : courant, epargne, joint',
    date_ouverture  DATE           COMMENT 'Date d''ouverture du compte',
    solde_initial   DECIMAL(12,2)  COMMENT 'Solde à l''ouverture du compte',
    statut          VARCHAR(10)    COMMENT 'Statut : actif, inactif, cloture'
)
COMMENT = 'Source brute : comptes des clients FinTrack';

-- ---------------------------------------------------------------------
-- raw_transactions : une opération bancaire par ligne
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE raw_transactions (
    id                INTEGER        COMMENT 'Identifiant unique de la transaction',
    compte_id         INTEGER        COMMENT 'Référence vers raw_comptes.id',
    date_transaction  TIMESTAMP_NTZ  COMMENT 'Date et heure de la transaction',
    montant           DECIMAL(10,2)  COMMENT 'Montant (toujours positif)',
    type_operation    VARCHAR(10)    COMMENT 'Type : debit ou credit',
    categorie_id      INTEGER        COMMENT 'Référence vers raw_categories.id',
    description       VARCHAR(255)   COMMENT 'Libellé de la transaction',
    statut            VARCHAR(15)    COMMENT 'Statut : validee, en_attente, rejetee'
)
COMMENT = 'Source brute : transactions bancaires';

-- ---------------------------------------------------------------------
-- raw_categories : référentiel des catégories de dépenses / revenus
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE raw_categories (
    id      INTEGER       COMMENT 'Identifiant unique de la catégorie',
    nom     VARCHAR(50)   COMMENT 'Nom de la catégorie',
    type    VARCHAR(10)   COMMENT 'Type : depense ou revenu',
    groupe  VARCHAR(30)   COMMENT 'Groupe parent (Quotidien, Logement, Loisirs...)'
)
COMMENT = 'Source brute : catégories de transactions';

-- ---------------------------------------------------------------------
-- raw_budgets : budget mensuel prévu par compte et par catégorie
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE raw_budgets (
    id             INTEGER        COMMENT 'Identifiant unique du budget',
    compte_id      INTEGER        COMMENT 'Référence vers raw_comptes.id',
    categorie_id   INTEGER        COMMENT 'Référence vers raw_categories.id',
    mois           DATE           COMMENT 'Premier jour du mois concerné',
    montant_prevu  DECIMAL(10,2)  COMMENT 'Montant budgété pour ce mois'
)
COMMENT = 'Source brute : budgets mensuels par catégorie';

-- ---------------------------------------------------------------------
-- Droit de lecture pour dbt
-- Chaque CREATE OR REPLACE efface les droits posés directement sur la
-- table. Le droit FUTURE de 00 les rétablit normalement ; on les
-- ré-accorde ici (SYSADMIN est propriétaire des tables) pour que dbt
-- puisse toujours lire les sources, même si le droit FUTURE manquait.
-- ---------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA FINTRACK_DB.RAW TO ROLE FINTRACK_ROLE;

-- Contrôle : doit lister les 4 tables RAW_*
SHOW TABLES LIKE 'RAW_%' IN SCHEMA FINTRACK_DB.RAW;
