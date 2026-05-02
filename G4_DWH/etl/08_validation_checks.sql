-- ============================================================
-- NAFAD PAY G4 — Requêtes de validation post-chargement
-- ============================================================

\echo '=== VALIDATION DWH NAFAD PAY ==='

\echo '1. Comptage des tables :'
SELECT 'dim_date'         AS table_name, COUNT(*) AS nb FROM dim_date
UNION ALL
SELECT 'dim_user',                       COUNT(*) FROM dim_user
UNION ALL
SELECT 'dim_merchant',                   COUNT(*) FROM dim_merchant
UNION ALL
SELECT 'dim_agency',                     COUNT(*) FROM dim_agency
UNION ALL
SELECT 'dim_node',                       COUNT(*) FROM dim_node
UNION ALL
SELECT 'fact_transactions',              COUNT(*) FROM fact_transactions;

\echo '2. Répartition sync_status :'
SELECT sync_status, COUNT(*) AS nb,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM fact_transactions
GROUP BY sync_status ORDER BY nb DESC;

\echo '3. Répartition statut transactions :'
SELECT status, COUNT(*) AS nb
FROM fact_transactions
GROUP BY status ORDER BY nb DESC;

\echo '4. Volume total (MRU) :'
SELECT
    ROUND(SUM(amount), 0) AS volume_total_mru,
    ROUND(SUM(fee), 0)    AS frais_total_mru
FROM fact_transactions;

\echo '5. Vérification FK orphelines :'
SELECT COUNT(*) AS transactions_sans_user
FROM fact_transactions WHERE user_key = -1;