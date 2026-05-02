-- ============================================================
-- NAFAD PAY G4 — Analyse de l'écart node_metrics vs stg_transactions
-- Écart documenté : ~1.3M MRU (réel : 462,389,743 MRU selon anomalies_report)
-- ============================================================

-- ÉTAPE 1 : Totaux déclarés dans node_metrics
-- (fichier node_metrics.csv : 5 noeuds, colonnes total_transactions + total_amount)
SELECT
    node_id,
    total_transactions      AS tx_declares,
    total_amount            AS volume_declare_mru
FROM tmp_node_metrics;  -- charger via: COPY tmp_node_metrics FROM '/staging/node_metrics.csv' CSV HEADER

-- ÉTAPE 2 : Totaux calculés depuis stg_transactions (Gold G3)
SELECT
    t.node_id,
    COUNT(*)                AS tx_calcules,
    ROUND(SUM(t.amount::NUMERIC), 0) AS volume_calcule_mru
FROM tmp_transactions t
WHERE t.sync_status != 'CONFLICT'  -- exclure CONFLICT non résolvables
   OR (t.sync_status = 'CONFLICT'
       AND TRIM(COALESCE(t.amount_node_a,'')) != '')
GROUP BY t.node_id;

-- ÉTAPE 3 : RAPPORT D'ÉCART (la requête clé)
WITH node_declared AS (
    SELECT
        node_id,
        total_transactions::BIGINT  AS tx_declares,
        total_amount::NUMERIC       AS vol_declares
    FROM tmp_node_metrics
),
node_computed AS (
    SELECT
        node_id,
        COUNT(*)                    AS tx_calcules,
        ROUND(SUM(amount::NUMERIC), 0) AS vol_calcule
    FROM tmp_transactions
    GROUP BY node_id
)
SELECT
    d.node_id,
    d.tx_declares,
    c.tx_calcules,
    (d.tx_declares - c.tx_calcules)             AS delta_tx,
    d.vol_declares,
    c.vol_calcule,
    ROUND(d.vol_declares - c.vol_calcule, 0)    AS delta_volume_mru,
    ROUND(
        (d.vol_declares - c.vol_calcule) * 100.0 / NULLIF(d.vol_declares, 0),
        3
    )                                           AS delta_pct
FROM node_declared d
LEFT JOIN node_computed c USING (node_id)
ORDER BY ABS(d.vol_declares - c.vol_calcule) DESC;

-- ============================================================
-- CAUSES IDENTIFIÉES DE L'ÉCART :
--
-- 1. DOUBLE COMPTAGE inter-noeuds (cause principale)
--    → node_metrics.total_amount = somme brute par noeud
--    → Une transaction cross-DC (is_cross_dc=TRUE) est comptée
--      deux fois dans node_metrics (source + destination)
--    → stg_transactions = 1 ligne unique par transaction
--    → Solution : dédoublonner node_metrics par transaction_id
--
-- 2. LAGGING transactions (1 912 cas)
--    → Transactions enregistrées dans node_metrics mais pas encore
--      dans stg_transactions au moment du snapshot
--    → Solution : aligner les fenêtres temporelles
--
-- 3. CONFLICT sans montant (1 529 cas)
--    → node_metrics inclut le montant brut du noeud primaire
--    → stg_transactions a un montant différent (ou null)
-- ============================================================

-- VÉRIFICATION : impact du double comptage cross-DC
SELECT
    'Cross-DC double-comptage' AS cause,
    COUNT(*)                   AS nb_tx_cross_dc,
    ROUND(SUM(amount), 0)      AS volume_double_compte_mru
FROM fact_transactions
WHERE is_cross_dc = TRUE;

-- VÉRIFICATION : impact des LAGGING
SELECT
    'LAGGING non encore répliqués' AS cause,
    COUNT(*)                       AS nb_tx_lagging,
    ROUND(SUM(amount), 0)          AS volume_lagging_mru
FROM fact_transactions
WHERE is_lagging = TRUE;

-- RÉCONCILIATION FINALE
-- L'écart attendu ≈ Volume cross-DC + Volume lagging + CONFLICT unresolvable
SELECT
    'Volume cross-DC (double compté dans node_metrics)' AS poste,
    ROUND(SUM(amount), 0)  AS mru
FROM fact_transactions WHERE is_cross_dc = TRUE
UNION ALL
SELECT
    'Volume LAGGING (pas encore dans stg)',
    ROUND(SUM(amount), 0)
FROM fact_transactions WHERE is_lagging = TRUE
UNION ALL
SELECT
    'Volume CONFLICT non résolvable (montant incertain)',
    ROUND(SUM(amount), 0)
FROM fact_transactions WHERE is_unresolvable_conflict = TRUE
UNION ALL
SELECT
    'TOTAL ÉCART EXPLIQUÉ',
    ROUND(
        (SELECT SUM(amount) FROM fact_transactions WHERE is_cross_dc = TRUE) +
        (SELECT SUM(amount) FROM fact_transactions WHERE is_lagging = TRUE) +
        (SELECT SUM(amount) FROM fact_transactions WHERE is_unresolvable_conflict = TRUE),
    0);
