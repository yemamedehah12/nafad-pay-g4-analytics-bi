-- ============================================================
-- NAFAD PAY G4 — Stratégie de résolution des CONFLICT
-- 1 549 CONFLICT dont 1 529 (98.7%) sans amount_node_a/b
-- ============================================================

-- DIAGNOSTIC 1 : Distribution des CONFLICT
SELECT
    sync_status,
    COUNT(*)                        AS nb,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM fact_transactions), 3) AS pct,
    ROUND(SUM(amount), 0)           AS volume_total_mru,
    ROUND(AVG(amount), 0)           AS montant_moyen
FROM fact_transactions
WHERE is_conflict = TRUE
GROUP BY sync_status;

-- DIAGNOSTIC 2 : CONFLICT avec et sans montants nodaux
SELECT
    CASE
        WHEN is_unresolvable_conflict = TRUE THEN 'SANS_MONTANT_NODAL (exclu des KPI financiers)'
        ELSE 'AVEC_MONTANT_NODAL (montant réconcilié)'
    END                             AS categorie,
    COUNT(*)                        AS nb,
    ROUND(SUM(amount), 0)           AS volume_mru,
    ROUND(AVG(amount), 0)           AS montant_moyen
FROM fact_transactions
WHERE is_conflict = TRUE
-- is_unresolvable_conflict doit exister dans fact_transactions (ajouté dans le DDL)
GROUP BY is_unresolvable_conflict;

-- DIAGNOSTIC 3 : Répartition par noeud des CONFLICT non résolvables
SELECT
    n.node_id,
    n.datacenter,
    COUNT(*)                        AS nb_conflict_sans_montant,
    ROUND(SUM(f.amount), 0)         AS volume_mru_estime
FROM fact_transactions f
JOIN dim_node n ON f.node_key = n.node_key
WHERE f.is_conflict = TRUE
  AND f.is_unresolvable_conflict = TRUE
GROUP BY n.node_id, n.datacenter
ORDER BY nb_conflict_sans_montant DESC;

-- ============================================================
-- STRATÉGIE ADOPTÉE (à documenter dans le rapport) :
--
-- Cas 1 : CONFLICT avec amount_node_a ET amount_node_b (20 cas)
--   → Règle métier : prendre la MOYENNE des deux noeuds
--   → Justification : divergence faible (<2% attendu), aucun tiers-arbitre
--   → Annotation : is_conflict=TRUE, montant=moyenne
--
-- Cas 2 : CONFLICT avec seul amount_node_a (0 cas dans ce dataset)
--   → Prendre amount_node_a (seule source fiable)
--
-- Cas 3 : CONFLICT sans aucun montant nodal (1 529 cas = 98.7%)
--   → Conserver amount original de la source primaire
--   → Flag : is_unresolvable_conflict=TRUE
--   → EXCLUSION des KPIs financiers critiques (total volume, marges)
--   → INCLUSION dans les KPIs opérationnels (nb tx, taux de succès)
--   → Raison d'exclusion : montant non fiable, risque de double-comptage
-- ============================================================

-- IMPACT FINANCIER : combien représentent les CONFLICT non résolvables ?
SELECT
    ROUND(SUM(CASE WHEN is_unresolvable_conflict = FALSE THEN amount ELSE 0 END), 0)
        AS volume_fiable_mru,
    ROUND(SUM(CASE WHEN is_unresolvable_conflict = TRUE  THEN amount ELSE 0 END), 0)
        AS volume_sujet_caution_mru,
    ROUND(
        SUM(CASE WHEN is_unresolvable_conflict = TRUE THEN amount ELSE 0 END) * 100.0
        / SUM(amount), 2
    )                               AS pct_volume_sujet_caution
FROM fact_transactions
WHERE is_conflict = TRUE;

-- KPI VOLUME FIABLE (à utiliser dans tous les dashboards)
-- = exclure les CONFLICT non résolvables
SELECT
    ROUND(SUM(amount), 0) AS volume_kpi_fiable_mru
FROM fact_transactions
WHERE is_unresolvable_conflict = FALSE
  OR is_unresolvable_conflict IS NULL;

-- ============================================================
-- VUE MATÉRIALISÉE : transactions_clean (pour les dashboards)
-- Exclut les CONFLICT non résolvables des calculs financiers
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_transactions_clean AS
SELECT
    f.*,
    u.wilaya_name,
    u.wilaya_id,
    u.kyc_level,
    u.profile_type,
    m.category_code,
    m.category_label,
    a.name AS agency_name,
    a.tier AS agency_tier,
    n.datacenter,
    n.aws_az,
    d.month,
    d.month_name,
    d.quarter,
    d.is_weekend
FROM fact_transactions f
JOIN dim_date     d ON f.date_key     = d.date_key
JOIN dim_user     u ON f.user_key     = u.user_key AND u.is_current = TRUE
JOIN dim_merchant m ON f.merchant_key = m.merchant_key
JOIN dim_agency   a ON f.agency_key   = a.agency_key
JOIN dim_node     n ON f.node_key     = n.node_key
-- Exclure les CONFLICT non résolvables DES MÉTRIQUES FINANCIÈRES
WHERE (f.is_conflict = FALSE OR f.is_unresolvable_conflict = FALSE)
WITH DATA;

CREATE INDEX ON mv_transactions_clean (transaction_date);
CREATE INDEX ON mv_transactions_clean (wilaya_id);
CREATE INDEX ON mv_transactions_clean (status);
CREATE INDEX ON mv_transactions_clean (transaction_type);
