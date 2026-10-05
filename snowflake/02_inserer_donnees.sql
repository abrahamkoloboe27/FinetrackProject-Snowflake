-- =====================================================================
-- FinTrack Analytics — 02 : données d'exemple (schéma RAW)
-- Insère les jeux de données de la section 1.3 du sujet :
--   12 catégories · 6 comptes · 45 transactions · 25 budgets
--
-- À exécuter APRÈS 01_creer_tables.sql.
-- Ré-exécutable : chaque table est vidée (TRUNCATE) avant l'insertion.
-- Sans cela, relancer le script doublerait les lignes, car Snowflake
-- n'empêche pas les doublons d'id.
-- =====================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE FINTRACK_WH;
USE SCHEMA FINTRACK_DB.RAW;

TRUNCATE TABLE raw_categories;
TRUNCATE TABLE raw_comptes;
TRUNCATE TABLE raw_transactions;
TRUNCATE TABLE raw_budgets;

-- ---------------------------------------------------------------------
-- CATÉGORIES (12)
-- ---------------------------------------------------------------------
INSERT INTO raw_categories (id, nom, type, groupe) VALUES
(1,  'Salaire',          'revenu',  'Revenus'),
(2,  'Freelance',        'revenu',  'Revenus'),
(3,  'Alimentation',     'depense', 'Quotidien'),
(4,  'Transport',        'depense', 'Quotidien'),
(5,  'Loyer',            'depense', 'Logement'),
(6,  'Électricité',      'depense', 'Logement'),
(7,  'Restaurant',       'depense', 'Loisirs'),
(8,  'Abonnements',      'depense', 'Loisirs'),
(9,  'Épargne versée',   'depense', 'Épargne'),
(10, 'Remboursement',    'revenu',  'Divers'),
(11, 'Santé',            'depense', 'Quotidien'),
(12, 'Vêtements',        'depense', 'Loisirs');

-- ---------------------------------------------------------------------
-- COMPTES (6)
-- ---------------------------------------------------------------------
INSERT INTO raw_comptes
  (id, nom_client, email, type_compte, date_ouverture, solde_initial, statut)
VALUES
(1, 'Alice Dupont',  'alice.dupont@email.fr',  'courant', '2023-01-15', 2500.00, 'actif'),
(2, 'Bob Martin',    'bob.martin@email.fr',    'courant', '2023-03-22', 1800.00, 'actif'),
(3, 'Claire Leroy',  'claire.leroy@email.fr',  'epargne', '2023-06-01', 5000.00, 'actif'),
(4, 'David Moreau',  'david.moreau@email.fr',  'joint',   '2022-11-10', 3200.00, 'actif'),
(5, 'Emma Bernard',  'emma.bernard@email.fr',  'courant', '2024-01-05', 900.00,  'inactif'),
(6, 'Frank Petit',   'frank.petit@email.fr',   'courant', '2023-09-18', 1500.00, 'cloture');

-- ---------------------------------------------------------------------
-- TRANSACTIONS (45) — échantillon de janvier à mars 2024
-- ---------------------------------------------------------------------
INSERT INTO raw_transactions
  (id, compte_id, date_transaction, montant, type_operation,
   categorie_id, description, statut)
VALUES
-- Alice Dupont — Janvier 2024
(1,  1, '2024-01-02 09:00:00', 2800.00, 'credit', 1,  'Salaire janvier',            'validee'),
(2,  1, '2024-01-03 14:30:00', 850.00,  'debit',  5,  'Loyer janvier',              'validee'),
(3,  1, '2024-01-05 12:15:00', 65.40,   'debit',  3,  'Courses Carrefour',          'validee'),
(4,  1, '2024-01-08 19:45:00', 42.00,   'debit',  7,  'Restaurant Le Bistrot',      'validee'),
(5,  1, '2024-01-10 08:00:00', 75.00,   'debit',  4,  'Abonnement Navigo',          'validee'),
(6,  1, '2024-01-15 10:00:00', 15.99,   'debit',  8,  'Netflix',                    'validee'),
(7,  1, '2024-01-20 16:00:00', 200.00,  'debit',  9,  'Virement épargne',           'validee'),
(8,  1, '2024-01-22 11:30:00', 34.50,   'debit',  11, 'Pharmacie',                  'validee'),
-- Alice Dupont — Février 2024
(9,  1, '2024-02-01 09:00:00', 2800.00, 'credit', 1,  'Salaire février',            'validee'),
(10, 1, '2024-02-03 14:00:00', 850.00,  'debit',  5,  'Loyer février',              'validee'),
(11, 1, '2024-02-06 13:00:00', 78.20,   'debit',  3,  'Courses Monoprix',           'validee'),
(12, 1, '2024-02-10 08:00:00', 75.00,   'debit',  4,  'Abonnement Navigo',          'validee'),
(13, 1, '2024-02-14 20:00:00', 89.00,   'debit',  7,  'Restaurant Saint-Valentin',  'validee'),
(14, 1, '2024-02-15 10:00:00', 15.99,   'debit',  8,  'Netflix',                    'validee'),
(15, 1, '2024-02-20 16:00:00', 200.00,  'debit',  9,  'Virement épargne',           'validee'),
-- Alice Dupont — Mars 2024
(16, 1, '2024-03-01 09:00:00', 2800.00, 'credit', 1,  'Salaire mars',               'validee'),
(17, 1, '2024-03-03 14:00:00', 850.00,  'debit',  5,  'Loyer mars',                 'validee'),
(18, 1, '2024-03-07 10:30:00', 92.10,   'debit',  3,  'Courses Leclerc',            'validee'),
(19, 1, '2024-03-12 19:00:00', 55.00,   'debit',  7,  'Restaurant Sushi Shop',      'en_attente'),
(20, 1, '2024-03-15 10:00:00', 15.99,   'debit',  8,  'Netflix',                    'validee'),
-- Bob Martin — Janvier 2024
(21, 2, '2024-01-03 09:00:00', 2200.00, 'credit', 1,  'Salaire janvier',            'validee'),
(22, 2, '2024-01-05 15:00:00', 650.00,  'debit',  5,  'Loyer janvier',              'validee'),
(23, 2, '2024-01-07 18:00:00', 35.00,   'debit',  7,  'Kebab Chez Ali',             'validee'),
(24, 2, '2024-01-09 09:30:00', 45.80,   'debit',  3,  'Courses Lidl',               'validee'),
(25, 2, '2024-01-12 14:00:00', 350.00,  'credit', 2,  'Mission freelance design',   'validee'),
(26, 2, '2024-01-18 11:00:00', 9.99,    'debit',  8,  'Spotify',                    'validee'),
(27, 2, '2024-01-25 08:00:00', 120.00,  'debit',  12, 'Zara soldes',                'validee'),
-- Bob Martin — Février 2024
(28, 2, '2024-02-02 09:00:00', 2200.00, 'credit', 1,  'Salaire février',            'validee'),
(29, 2, '2024-02-04 15:00:00', 650.00,  'debit',  5,  'Loyer février',              'validee'),
(30, 2, '2024-02-08 13:00:00', 52.30,   'debit',  3,  'Courses Auchan',             'validee'),
(31, 2, '2024-02-12 20:00:00', 28.00,   'debit',  7,  'Pizza Hut',                  'rejetee'),
(32, 2, '2024-02-15 10:00:00', 9.99,    'debit',  8,  'Spotify',                    'validee'),
(33, 2, '2024-02-20 16:00:00', 500.00,  'credit', 2,  'Mission freelance dev',      'validee'),
-- David Moreau (compte joint) — Janvier 2024
(34, 4, '2024-01-02 09:00:00', 4500.00, 'credit', 1,  'Salaire David',              'validee'),
(35, 4, '2024-01-02 09:30:00', 2100.00, 'credit', 1,  'Salaire conjointe',          'validee'),
(36, 4, '2024-01-05 14:00:00', 1200.00, 'debit',  5,  'Loyer janvier',              'validee'),
(37, 4, '2024-01-06 17:00:00', 85.00,   'debit',  6,  'EDF facture',                'validee'),
(38, 4, '2024-01-10 12:00:00', 156.30,  'debit',  3,  'Courses familiales',         'validee'),
(39, 4, '2024-01-15 20:00:00', 110.00,  'debit',  7,  'Restaurant en famille',      'validee'),
(40, 4, '2024-01-20 10:00:00', 500.00,  'debit',  9,  'Épargne mensuelle',          'validee'),
-- Claire Leroy (épargne) — Janvier à Mars 2024
(41, 3, '2024-01-15 10:00:00', 300.00,  'credit', 9,  'Virement depuis courant',    'validee'),
(42, 3, '2024-02-15 10:00:00', 300.00,  'credit', 9,  'Virement depuis courant',    'validee'),
(43, 3, '2024-03-15 10:00:00', 300.00,  'credit', 9,  'Virement depuis courant',    'validee'),
-- Emma Bernard (inactive)
(44, 5, '2024-01-10 09:00:00', 1500.00, 'credit', 1,  'Salaire janvier',            'validee'),
(45, 5, '2024-01-12 14:00:00', 45.00,   'debit',  3,  'Courses',                    'validee');

-- ---------------------------------------------------------------------
-- BUDGETS (25) — janvier à mars 2024, Alice et Bob
-- ---------------------------------------------------------------------
INSERT INTO raw_budgets
  (id, compte_id, categorie_id, mois, montant_prevu)
VALUES
-- Alice — Janvier
(1,  1, 3,  '2024-01-01', 150.00),
(2,  1, 4,  '2024-01-01', 80.00),
(3,  1, 5,  '2024-01-01', 850.00),
(4,  1, 7,  '2024-01-01', 60.00),
(5,  1, 8,  '2024-01-01', 20.00),
(6,  1, 9,  '2024-01-01', 200.00),
-- Alice — Février
(7,  1, 3,  '2024-02-01', 150.00),
(8,  1, 4,  '2024-02-01', 80.00),
(9,  1, 5,  '2024-02-01', 850.00),
(10, 1, 7,  '2024-02-01', 60.00),
(11, 1, 8,  '2024-02-01', 20.00),
(12, 1, 9,  '2024-02-01', 200.00),
-- Alice — Mars
(13, 1, 3,  '2024-03-01', 160.00),
(14, 1, 5,  '2024-03-01', 850.00),
(15, 1, 7,  '2024-03-01', 50.00),
(16, 1, 8,  '2024-03-01', 20.00),
-- Bob — Janvier
(17, 2, 3,  '2024-01-01', 100.00),
(18, 2, 5,  '2024-01-01', 650.00),
(19, 2, 7,  '2024-01-01', 50.00),
(20, 2, 8,  '2024-01-01', 15.00),
(21, 2, 12, '2024-01-01', 80.00),
-- Bob — Février
(22, 2, 3,  '2024-02-01', 100.00),
(23, 2, 5,  '2024-02-01', 650.00),
(24, 2, 7,  '2024-02-01', 50.00),
(25, 2, 8,  '2024-02-01', 15.00);
