-- ============================================================
-- NAFAD PAY G4 — Vues Matérialisées (Performance)
-- Objectif : sub-second pour les dashboards Superset
-- ============================================================

-- ============================================================
-- MV 1 : Agrégats journaliers (rafraîchissement : J+1, 02h00)
-- Couvre les questions métier sur les tendances historiques
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_kpis AS
SELECT
    f.transaction_date,
    d.year,
    d.month,
    d.month_name,
    d.quarter,
    d.is_weekend,
    f.transaction_type,
    f.status,
    f.sync_status,
    u.wilaya_id,
    u.wilaya_name,
    COUNT(*)                                AS nb_transactions,
    ROUND(SUM(f.amount), 2)                 AS volume_mru,
    ROUND(SUM(f.fee), 2)                    AS fees_mru,
    ROUND(AVG(f.amount), 2)                 AS montant_moyen,
    COUNT(DISTINCT f.user_key)              AS utilisateurs_uniques,
    COUNT(DISTINCT f.merchant_key)          AS marchands_actifs,
    SUM(CASE WHEN f.status = 'SUCCESS'  THEN 1 ELSE 0 END) AS nb_succes,
    SUM(CASE WHEN f.status = 'FAILED'   THEN 1 ELSE 0 END) AS nb_echecs,
    SUM(CASE WHEN f.is_conflict = TRUE  THEN 1 ELSE 0 END) AS nb_conflict,
    SUM(CASE WHEN f.has_clock_skew = TRUE THEN 1 ELSE 0 END) AS nb_clock_skew
FROM fact_transactions f
JOIN dim_date     d ON f.date_key  = d.date_key
JOIN dim_user     u ON f.user_key  = u.user_key AND u.is_current = TRUE
WHERE f.is_unresolvable_conflict = FALSE OR f.is_unresolvable_conflict IS NULL
GROUP BY
    f.transaction_date, d.year, d.month, d.month_name, d.quarter, d.is_weekend,
    f.transaction_type, f.status, f.sync_status,
    u.wilaya_id, u.wilaya_name
WITH DATA;

CREATE INDEX ON mv_daily_kpis (transaction_date);
CREATE INDEX ON mv_daily_kpis (wilaya_id);
CREATE INDEX ON mv_daily_kpis (transaction_type);
CREATE INDEX ON mv_daily_kpis (status);

-- ============================================================
-- MV 2 : Performance agences (rafraîchissement : J+1)
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_agency_performance AS
SELECT
    a.agency_id,
    a.name                          AS agency_name,
    a.wilaya_id,
    a.wilaya_name,
    a.tier,
    d.year,
    d.month,
    d.month_name,
    COUNT(*)                        AS nb_transactions,
    ROUND(SUM(f.amount), 0)         AS volume_mru,
    ROUND(SUM(f.fee), 0)            AS fees_collectees,
    ROUND(AVG(f.amount), 0)         AS panier_moyen,
    COUNT(DISTINCT f.user_key)      AS clients_uniques,
    ROUND(
        SUM(CASE WHEN f.status = 'SUCCESS' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
        1
    )                               AS taux_succes_pct
FROM fact_transactions f
JOIN dim_agency a ON f.agency_key = a.agency_key
JOIN dim_date   d ON f.date_key   = d.date_key
WHERE a.agency_id != -1
  AND (f.is_unresolvable_conflict = FALSE OR f.is_unresolvable_conflict IS NULL)
GROUP BY
    a.agency_id, a.name, a.wilaya_id, a.wilaya_name, a.tier,
    d.year, d.month, d.month_name
WITH DATA;

CREATE INDEX ON mv_agency_performance (agency_id);
CREATE INDEX ON mv_agency_performance (wilaya_id, month);

-- ============================================================
-- MV 3 : Rétention utilisateurs (rafraîchissement : hebdo)
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_retention AS
SELECT
    u.user_id,
    u.wilaya_name,
    u.kyc_level,
    u.profile_type,
    u.registration_date,
    DATE_TRUNC('month', u.registration_date) AS cohort_month,
    MIN(f.transaction_date)                  AS premiere_transaction,
    MAX(f.transaction_date)                  AS derniere_transaction,
    COUNT(*)                                 AS nb_transactions_total,
    ROUND(SUM(f.amount), 0)                  AS volume_total_mru,
    COUNT(DISTINCT DATE_TRUNC('month', f.transaction_date)) AS mois_actifs,
    MAX(f.transaction_date) - MIN(f.transaction_date)       AS duree_activite_jours
FROM dim_user u
LEFT JOIN fact_transactions f ON f.user_key = u.user_key
    AND (f.is_unresolvable_conflict = FALSE OR f.is_unresolvable_conflict IS NULL)
WHERE u.is_current = TRUE AND u.user_id != -1
GROUP BY
    u.user_id, u.wilaya_name, u.kyc_level, u.profile_type,
    u.registration_date
WITH DATA;

CREATE INDEX ON mv_user_retention (cohort_month);
CREATE INDEX ON mv_user_retention (wilaya_name);
CREATE INDEX ON mv_user_retention (kyc_level);

-- ============================================================
-- MV 4 : Top marchands (rafraîchissement : J+1)
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_merchant_performance AS
SELECT
    m.merchant_id,
    m.name                          AS merchant_name,
    m.category_code,
    m.category_label,
    m.wilaya_name,
    m.commission_rate,
    d.month,
    d.month_name,
    COUNT(*)                        AS nb_transactions,
    ROUND(SUM(f.amount), 0)         AS volume_mru,
    ROUND(SUM(f.amount * m.commission_rate), 0) AS commissions_mru,
    ROUND(AVG(f.amount), 0)         AS panier_moyen,
    COUNT(DISTINCT f.user_key)      AS clients_uniques
FROM fact_transactions f
JOIN dim_merchant m ON f.merchant_key = m.merchant_key
JOIN dim_date     d ON f.date_key     = d.date_key
WHERE m.merchant_id != -1
  AND (f.is_unresolvable_conflict = FALSE OR f.is_unresolvable_conflict IS NULL)
GROUP BY
    m.merchant_id, m.name, m.category_code, m.category_label,
    m.wilaya_name, m.commission_rate,
    d.month, d.month_name
WITH DATA;

CREATE INDEX ON mv_merchant_performance (category_code);
CREATE INDEX ON mv_merchant_performance (wilaya_name);

-- ============================================================
-- PROCÉDURE DE RAFRAÎCHISSEMENT (à appeler par cron J+1 à 02h00)
-- ============================================================
CREATE OR REPLACE PROCEDURE refresh_all_materialized_views()
LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_kpis;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_agency_performance;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_merchant_performance;
    -- Hebdomadaire seulement :
    -- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_user_retention;
    RAISE NOTICE 'Vues matérialisées rafraîchies à %', NOW();
END;
$$;

-- En prod AWS : EventBridge → Lambda → appel via psycopg2
-- SELECT refresh_all_materialized_views();
