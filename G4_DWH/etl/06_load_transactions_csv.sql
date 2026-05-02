-- ============================================================
-- NAFAD PAY G4 — Vérification chargement transactions
-- ============================================================

\echo 'Vérification chargement transactions...'

SELECT COUNT(*) AS total FROM tmp_transactions;

SELECT sync_status, COUNT(*) AS nb
FROM tmp_transactions
GROUP BY sync_status
ORDER BY nb DESC;