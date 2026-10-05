-- =====================================================================
-- FinTrack Analytics — 03 : vérifications après chargement
-- Contrôle que les 4 tables sont bien remplies, sans doublon ni
-- référence orpheline. À exécuter APRÈS 02_inserer_donnees.sql.
-- Chaque requête indique le résultat attendu.
--
-- Dans Snowsight, "Run all" n'affiche que le résultat de la DERNIÈRE
-- requête. Exécutez donc chaque contrôle séparément : curseur dans la
-- requête, puis Ctrl+Entrée.
-- =====================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE FINTRACK_WH;
USE SCHEMA FINTRACK_DB.RAW;

-- 1. Nombre de lignes par table
--    attendu (dans n'importe quel ordre) :
--    raw_categories 12 · raw_comptes 6 · raw_transactions 45 · raw_budgets 25
SELECT 'raw_categories'   AS table_source, COUNT(*) AS nb_lignes FROM raw_categories
UNION ALL SELECT 'raw_comptes',      COUNT(*) FROM raw_comptes
UNION ALL SELECT 'raw_transactions', COUNT(*) FROM raw_transactions
UNION ALL SELECT 'raw_budgets',      COUNT(*) FROM raw_budgets;

-- 2. Doublons d'identifiant (aucune ligne attendue)
SELECT 'raw_categories' AS table_source, id, COUNT(*) AS nb FROM raw_categories   GROUP BY id HAVING COUNT(*) > 1
UNION ALL
SELECT 'raw_comptes',      id, COUNT(*) FROM raw_comptes       GROUP BY id HAVING COUNT(*) > 1
UNION ALL
SELECT 'raw_transactions', id, COUNT(*) FROM raw_transactions  GROUP BY id HAVING COUNT(*) > 1
UNION ALL
SELECT 'raw_budgets',      id, COUNT(*) FROM raw_budgets       GROUP BY id HAVING COUNT(*) > 1;

-- 3. Références orphelines (aucune ligne attendue)
SELECT 'transactions -> comptes' AS controle, t.id
FROM raw_transactions t LEFT JOIN raw_comptes c ON c.id = t.compte_id
WHERE c.id IS NULL
UNION ALL
SELECT 'transactions -> categories', t.id
FROM raw_transactions t LEFT JOIN raw_categories k ON k.id = t.categorie_id
WHERE k.id IS NULL
UNION ALL
SELECT 'budgets -> comptes', b.id
FROM raw_budgets b LEFT JOIN raw_comptes c ON c.id = b.compte_id
WHERE c.id IS NULL
UNION ALL
SELECT 'budgets -> categories', b.id
FROM raw_budgets b LEFT JOIN raw_categories k ON k.id = b.categorie_id
WHERE k.id IS NULL;

-- 4. Répartition des transactions par statut
--    attendu : validee 43 · en_attente 1 · rejetee 1
SELECT statut, COUNT(*) AS nb_transactions
FROM raw_transactions
GROUP BY statut
ORDER BY nb_transactions DESC, statut;

-- 5. Types chargés correctement (dates et montants)
--    attendu : 1 ligne, du 2024-01-02 09:00:00.000 au 2024-03-15 10:00:00.000
--    (Snowflake affiche les millisecondes) et total_montants = 29951.55
--    (somme brute des crédits et des débits : sert seulement de somme de contrôle)
SELECT MIN(date_transaction) AS premiere_transaction,
       MAX(date_transaction) AS derniere_transaction,
       SUM(montant)          AS total_montants
FROM raw_transactions;

-- 6. (Optionnel) Les droits du rôle dbt, à tester en tant que FINTRACK_ROLE.
--    Décommentez le bloc et exécutez-le ligne par ligne. Si Snowflake répond
--    que le rôle n'est pas accordé à votre utilisateur, ce test n'est pas
--    possible depuis votre connexion : le vrai test est alors `dbt debug`
--    puis le premier `dbt run`.
-- USE ROLE FINTRACK_ROLE;
-- USE WAREHOUSE FINTRACK_WH;
-- SELECT COUNT(*) FROM FINTRACK_DB.RAW.RAW_TRANSACTIONS;   -- lecture de RAW, attendu : 45
-- CREATE VIEW  FINTRACK_DB.STAGING.zz_test AS SELECT * FROM FINTRACK_DB.RAW.RAW_COMPTES;  -- doit réussir
-- CREATE TABLE FINTRACK_DB.MARTS.zz_test   AS SELECT * FROM FINTRACK_DB.RAW.RAW_COMPTES;  -- doit réussir
-- DROP VIEW  FINTRACK_DB.STAGING.zz_test;
-- DROP TABLE FINTRACK_DB.MARTS.zz_test;
-- USE ROLE SYSADMIN;   -- ne laissez pas la feuille sur FINTRACK_ROLE
