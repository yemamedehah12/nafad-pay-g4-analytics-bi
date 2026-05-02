-- ============================================================
-- NAFAD PAY G4 — Requêtes Dashboard BI
-- Description : 6 visuels + 3 KPI cards pour le DG
-- ============================================================

-- ============================================================
-- KPI 1 : Total des transactions
-- ============================================================
SELECT COUNT(*) AS total_transactions
FROM fact_transactions;
-- Résultat attendu : 100 000

-- ============================================================
-- KPI 2 : Volume total en MRU (hors CONFLICT)
-- ============================================================
SELECT ROUND(SUM(amount), 0) AS volume_total_mru
FROM fact_transactions
WHERE is_conflict = FALSE;
-- Résultat attendu : ~2 089 707 250 MRU

-- ============================================================
-- KPI 3 : Taux de succès global
-- ============================================================
SELECT ROUND(
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
) AS taux_succes_pct
FROM fact_transactions;
-- Résultat attendu : 67.3%

-- ============================================================
-- VISUEL 1 : Volume mensuel (MRU) par mois
-- Type graphique : Barres verticales
-- Axe X : mois / Axe Y : volume_mru
-- ============================================================
SELECT
    d.month                         AS num_mois,
    d.month_name                    AS mois,
    COUNT(*)                        AS nb_transactions,
    ROUND(SUM(f.amount), 0)         AS volume_mru
FROM fact_transactions f
JOIN dim_date d ON f.date_key = d.date_key
WHERE f.is_conflict = FALSE
GROUP BY d.month, d.month_name
ORDER BY d.month;

-- ============================================================
-- VISUEL 2 : Taux de succès des transactions
-- Type graphique : Donut
-- ============================================================
SELECT
    status,
    COUNT(*) AS nb,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pourcentage
FROM fact_transactions
GROUP BY status
ORDER BY nb DESC;

-- ============================================================
-- VISUEL 3 : Top 10 wilayas par volume
-- Type graphique : Barres horizontales
-- Axe X : volume_mru / Axe Y : wilaya
-- ============================================================
SELECT
    u.wilaya_name                   AS wilaya,
    COUNT(*)                        AS nb_transactions,
    ROUND(SUM(f.amount), 0)         AS volume_mru,
    ROUND(AVG(f.amount), 0)         AS panier_moyen
FROM fact_transactions f
JOIN dim_user u ON f.user_key = u.user_key
WHERE u.wilaya_name IS NOT NULL
  AND u.is_current = TRUE
GROUP BY u.wilaya_name
ORDER BY volume_mru DESC
LIMIT 10;

-- ============================================================
-- VISUEL 4 : Heures de pointe
-- Type graphique : Courbe
-- Axe X : heure / Axe Y : nb_transactions
-- ============================================================
SELECT
    EXTRACT(HOUR FROM transaction_time)::INT    AS heure,
    COUNT(*)                                    AS nb_transactions
FROM fact_transactions
WHERE transaction_time IS NOT NULL
GROUP BY heure
ORDER BY heure;

-- ============================================================
-- VISUEL 5 : Répartition par type de transaction
-- Type graphique : Barres verticales
-- Axe X : type_tx / Axe Y : nb
-- DEP=Dépôt, WIT=Retrait, TRF=Transfert, PAY=Paiement
-- BIL=Facture, AIR=Airtime, SAL=Salaire, REV=Remboursement
-- ============================================================
SELECT
    transaction_type                AS type_tx,
    COUNT(*)                        AS nb,
    ROUND(SUM(amount), 0)           AS volume_mru,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM fact_transactions
GROUP BY transaction_type
ORDER BY nb DESC;

-- ============================================================
-- VISUEL 6 : Principaux motifs d'échec
-- Type graphique : Barres horizontales
-- Axe X : nb_echecs / Axe Y : motif
-- ============================================================
SELECT
    COALESCE(NULLIF(TRIM(failure_reason), ''), 'Non précisé') AS motif,
    COUNT(*)                        AS nb_echecs,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM fact_transactions
WHERE status = 'FAILED'
GROUP BY failure_reason
ORDER BY nb_echecs DESC
LIMIT 10;