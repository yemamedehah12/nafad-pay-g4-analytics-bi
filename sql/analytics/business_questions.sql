-- ============================================================
-- NAFAD PAY G4 — 15 Questions Métier avec SQL optimisé
-- Source : business_questions.md — réponses analytiques complètes
-- Utilise mv_daily_kpis (MV) pour les requêtes lourdes
-- ============================================================

-- ============================================================
-- Q1 : Volume total des transactions par mois (MoM)
-- Type : Barres + courbe croissance
-- ============================================================
SELECT
    month,
    month_name,
    SUM(nb_transactions)            AS nb_transactions,
    ROUND(SUM(volume_mru), 0)       AS volume_mru,
    ROUND(SUM(fees_mru), 0)         AS fees_mru,
    LAG(ROUND(SUM(volume_mru),0)) OVER (ORDER BY month) AS volume_mois_precedent,
    ROUND(
        (SUM(volume_mru) - LAG(SUM(volume_mru)) OVER (ORDER BY month))
        * 100.0 / NULLIF(LAG(SUM(volume_mru)) OVER (ORDER BY month), 0),
        1
    )                               AS croissance_mom_pct
FROM mv_daily_kpis
GROUP BY month, month_name
ORDER BY month;

-- ============================================================
-- Q2 : Taux de succès global et par type de transaction
-- Type : KPI card + tableau
-- ============================================================
SELECT
    transaction_type,
    SUM(nb_transactions)                    AS total_tx,
    SUM(nb_succes)                          AS nb_succes,
    SUM(nb_echecs)                          AS nb_echecs,
    ROUND(SUM(nb_succes) * 100.0 / NULLIF(SUM(nb_transactions), 0), 1)
                                            AS taux_succes_pct,
    ROUND(SUM(volume_mru), 0)               AS volume_mru
FROM mv_daily_kpis
GROUP BY transaction_type
ORDER BY total_tx DESC;

-- ============================================================
-- Q3 : Top 15 wilayas par volume transactionnel
-- Type : Carte choroplèthe + barres horizontales
-- ============================================================
SELECT
    wilaya_id,
    wilaya_name,
    SUM(nb_transactions)                    AS nb_transactions,
    ROUND(SUM(volume_mru), 0)               AS volume_mru,
    ROUND(AVG(montant_moyen), 0)            AS panier_moyen,
    SUM(utilisateurs_uniques)               AS utilisateurs_actifs,
    RANK() OVER (ORDER BY SUM(volume_mru) DESC) AS rang_volume,
    ROUND(
        SUM(volume_mru) * 100.0 / SUM(SUM(volume_mru)) OVER (),
        2
    )                                       AS part_pct
FROM mv_daily_kpis
WHERE wilaya_name IS NOT NULL
GROUP BY wilaya_id, wilaya_name
ORDER BY volume_mru DESC;

-- ============================================================
-- Q4 : Performance des agences (top 10 + bottom 10)
-- Type : Tableau avec indicateurs couleur
-- ============================================================
SELECT
    agency_name,
    wilaya_name,
    tier,
    SUM(nb_transactions)            AS nb_transactions,
    ROUND(SUM(volume_mru), 0)       AS volume_mru,
    ROUND(SUM(fees_collectees), 0)  AS fees_collectees,
    ROUND(AVG(taux_succes_pct), 1)  AS taux_succes_pct,
    SUM(clients_uniques)            AS clients_uniques,
    DENSE_RANK() OVER (ORDER BY SUM(volume_mru) DESC) AS rang
FROM mv_agency_performance
GROUP BY agency_name, wilaya_name, tier
ORDER BY rang
LIMIT 20;

-- ============================================================
-- Q5 : Identification wilayas à fort potentiel de croissance
-- Métrique : Volume/habitant (proxy = volume/nb_utilisateurs)
-- Type : Matrice potentiel × volume actuel
-- ============================================================
SELECT
    wilaya_name,
    SUM(nb_transactions)    AS nb_transactions,
    ROUND(SUM(volume_mru),0) AS volume_mru,
    SUM(utilisateurs_uniques) AS utilisateurs_actifs,
    ROUND(SUM(volume_mru) / NULLIF(SUM(utilisateurs_uniques), 0), 0)
                            AS volume_par_utilisateur,
    -- Quadrant : fort volume + peu d'utilisateurs = fort potentiel
    CASE
        WHEN SUM(volume_mru) > (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY SUM(volume_mru)) FROM mv_daily_kpis GROUP BY wilaya_name LIMIT 1)
             AND SUM(utilisateurs_uniques) < (SELECT AVG(x) FROM (SELECT SUM(utilisateurs_uniques) x FROM mv_daily_kpis GROUP BY wilaya_name) sub)
            THEN 'FORT_POTENTIEL'
        WHEN SUM(volume_mru) > (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY SUM(volume_mru)) FROM mv_daily_kpis GROUP BY wilaya_name LIMIT 1)
            THEN 'MATURE'
        ELSE 'DEVELOPPEMENT'
    END                     AS segment
FROM mv_daily_kpis
WHERE wilaya_name IS NOT NULL
GROUP BY wilaya_name
ORDER BY volume_par_utilisateur DESC;

-- ============================================================
-- Q6 : Nouveaux utilisateurs par mois + taux d'activation
-- Type : Barres empilées (nouveau vs récurrent)
-- ============================================================
WITH premier_tx AS (
    SELECT
        u.user_id,
        u.wilaya_name,
        u.kyc_level,
        DATE_TRUNC('month', MIN(f.transaction_date)) AS mois_premiere_tx,
        DATE_TRUNC('month', u.registration_date)     AS mois_inscription
    FROM dim_user u
    LEFT JOIN fact_transactions f ON f.user_key = u.user_key
    WHERE u.is_current = TRUE AND u.user_id != -1
    GROUP BY u.user_id, u.wilaya_name, u.kyc_level, u.registration_date
)
SELECT
    TO_CHAR(mois_inscription, 'YYYY-MM')    AS mois,
    COUNT(*)                                AS inscrits,
    COUNT(mois_premiere_tx)                 AS activations,
    ROUND(COUNT(mois_premiere_tx) * 100.0 / COUNT(*), 1)
                                            AS taux_activation_pct,
    -- Délai moyen inscription→première transaction
    ROUND(AVG(EXTRACT(DAY FROM (mois_premiere_tx - mois_inscription))), 0)
                                            AS delai_moyen_activation_j
FROM premier_tx
GROUP BY mois_inscription
ORDER BY mois_inscription;

-- ============================================================
-- Q7 : Rétention mensuelle (cohortes)
-- Type : Heatmap mois inscription × mois actif
-- ============================================================
WITH cohorts AS (
    SELECT
        u.user_id,
        DATE_TRUNC('month', u.registration_date)     AS cohort,
        DATE_TRUNC('month', f.transaction_date)      AS activity_month
    FROM dim_user u
    JOIN fact_transactions f ON f.user_key = u.user_key
    WHERE u.is_current = TRUE AND u.user_id != -1
      AND (f.is_unresolvable_conflict = FALSE OR f.is_unresolvable_conflict IS NULL)
    GROUP BY u.user_id, cohort, activity_month
),
cohort_sizes AS (
    SELECT cohort, COUNT(DISTINCT user_id) AS cohort_size
    FROM cohorts GROUP BY cohort
)
SELECT
    TO_CHAR(c.cohort, 'YYYY-MM')        AS cohort,
    cs.cohort_size,
    EXTRACT(MONTH FROM AGE(c.activity_month, c.cohort))::INT
                                        AS mois_depuis_inscription,
    COUNT(DISTINCT c.user_id)           AS utilisateurs_actifs,
    ROUND(COUNT(DISTINCT c.user_id) * 100.0 / cs.cohort_size, 1)
                                        AS retention_pct
FROM cohorts c
JOIN cohort_sizes cs USING (cohort)
GROUP BY c.cohort, c.activity_month, cs.cohort_size
ORDER BY c.cohort, mois_depuis_inscription;

-- ============================================================
-- Q8 : Distribution horaire des transactions (heures de pointe)
-- Type : Heatmap heure × jour de semaine
-- ============================================================
SELECT
    EXTRACT(HOUR FROM f.transaction_time)::INT  AS heure,
    TO_CHAR(f.transaction_date, 'Day')          AS jour_semaine,
    d.day_of_week,
    d.is_weekend,
    COUNT(*)                                    AS nb_transactions,
    ROUND(SUM(f.amount), 0)                     AS volume_mru
FROM fact_transactions f
JOIN dim_date d ON f.date_key = d.date_key
WHERE f.transaction_time IS NOT NULL
  AND (f.is_unresolvable_conflict = FALSE OR f.is_unresolvable_conflict IS NULL)
GROUP BY heure, jour_semaine, d.day_of_week, d.is_weekend
ORDER BY d.day_of_week, heure;

-- ============================================================
-- Q9 : Top motifs d'échec et taux de résolution
-- Type : Barres horizontales + tendance
-- ============================================================
SELECT
    COALESCE(NULLIF(TRIM(failure_reason), ''), 'Non précisé')  AS motif,
    f.transaction_type,
    COUNT(*)                                    AS nb_echecs,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)
                                                AS pct_echecs,
    ROUND(AVG(f.amount), 0)                     AS montant_moyen_echoue,
    ROUND(SUM(f.amount), 0)                     AS volume_perdu_mru
FROM fact_transactions f
WHERE f.status = 'FAILED'
GROUP BY motif, f.transaction_type
ORDER BY nb_echecs DESC
LIMIT 15;

-- ============================================================
-- Q10 : Frais collectés — analyse rentabilité
-- Type : Barres + tableau
-- ============================================================
SELECT
    transaction_type,
    COUNT(*)                    AS nb_transactions,
    ROUND(SUM(f.amount), 0)     AS volume_mru,
    ROUND(SUM(f.fee), 0)        AS fees_mru,
    ROUND(AVG(f.fee), 2)        AS fee_moyen,
    ROUND(SUM(f.fee) * 100.0 / NULLIF(SUM(f.amount), 0), 4)
                                AS taux_fee_effectif_pct
FROM fact_transactions f
WHERE f.status = 'SUCCESS'
  AND (f.is_unresolvable_conflict = FALSE OR f.is_unresolvable_conflict IS NULL)
GROUP BY transaction_type
ORDER BY fees_mru DESC;

-- ============================================================
-- Q11 : Top 10 marchands par volume + catégorie
-- Type : Treemap ou barres empilées par catégorie
-- ============================================================
SELECT
    m.name              AS merchant_name,
    m.category_label,
    m.wilaya_name,
    COUNT(*)            AS nb_transactions,
    ROUND(SUM(f.amount), 0) AS volume_mru,
    ROUND(AVG(f.amount), 0) AS panier_moyen,
    ROUND(SUM(f.amount * m.commission_rate), 0) AS commissions_mru,
    COUNT(DISTINCT f.user_key) AS clients_uniques
FROM fact_transactions f
JOIN dim_merchant m ON f.merchant_key = m.merchant_key
WHERE m.merchant_id != -1
  AND f.status = 'SUCCESS'
  AND (f.is_unresolvable_conflict = FALSE OR f.is_unresolvable_conflict IS NULL)
GROUP BY m.name, m.category_label, m.wilaya_name, m.commission_rate
ORDER BY volume_mru DESC
LIMIT 10;

-- ============================================================
-- Q12 : Marchands inactifs (opportunités de réengagement)
-- ============================================================
SELECT
    m.name,
    m.category_label,
    m.wilaya_name,
    m.status,
    COALESCE(tx.dernier_usage, 'Jamais utilisé') AS dernier_usage,
    COALESCE(tx.nb_transactions, 0) AS nb_transactions_total
FROM dim_merchant m
LEFT JOIN (
    SELECT
        merchant_key,
        MAX(transaction_date)::TEXT AS dernier_usage,
        COUNT(*)                    AS nb_transactions
    FROM fact_transactions
    GROUP BY merchant_key
) tx ON tx.merchant_key = m.merchant_key
WHERE m.merchant_id != -1
  AND (tx.nb_transactions IS NULL OR tx.nb_transactions < 10)
ORDER BY m.wilaya_name, m.category_label;

-- ============================================================
-- Q13 : Taux de complétion KYC et impact sur le volume
-- Type : Funnel KYC + volume moyen par niveau
-- ============================================================
SELECT
    u.kyc_level,
    COUNT(DISTINCT u.user_id)           AS nb_utilisateurs,
    ROUND(COUNT(DISTINCT u.user_id) * 100.0
        / SUM(COUNT(DISTINCT u.user_id)) OVER (), 1)
                                        AS pct_utilisateurs,
    COALESCE(SUM(f_agg.nb_tx), 0)       AS nb_transactions,
    COALESCE(ROUND(SUM(f_agg.vol), 0), 0) AS volume_mru,
    COALESCE(ROUND(AVG(f_agg.vol), 0), 0) AS volume_moyen_par_user
FROM dim_user u
LEFT JOIN (
    SELECT user_key, COUNT(*) AS nb_tx, SUM(amount) AS vol
    FROM fact_transactions
    WHERE is_unresolvable_conflict = FALSE OR is_unresolvable_conflict IS NULL
    GROUP BY user_key
) f_agg ON f_agg.user_key = u.user_key
WHERE u.is_current = TRUE AND u.user_id != -1
GROUP BY u.kyc_level
ORDER BY u.kyc_level;

-- ============================================================
-- Q14 : Analyse des anomalies de synchronisation
-- Type : Tableau de bord opérationnel (pour équipe technique)
-- ============================================================
SELECT
    sync_status                         AS statut_sync,
    COUNT(*)                            AS nb_transactions,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 3) AS pct,
    ROUND(SUM(amount), 0)               AS volume_mru,
    n.datacenter,
    n.aws_az
FROM fact_transactions f
JOIN dim_node n ON f.node_key = n.node_key
GROUP BY sync_status, n.datacenter, n.aws_az
ORDER BY nb_transactions DESC;

-- ============================================================
-- Q15 : Tableau de bord DG — Vue synthétique (1 pager)
-- ============================================================
SELECT
    'KPI GLOBAL'                        AS section,
    COUNT(*)::TEXT                      AS valeur,
    'Transactions totales'              AS libelle
FROM fact_transactions
UNION ALL
SELECT 'KPI GLOBAL',
    ROUND(SUM(amount)/1000000.0, 2)::TEXT || ' M MRU',
    'Volume total (excl. conflits non résolvables)'
FROM fact_transactions
WHERE is_unresolvable_conflict = FALSE OR is_unresolvable_conflict IS NULL
UNION ALL
SELECT 'KPI GLOBAL',
    ROUND(SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END)*100.0/COUNT(*),1)::TEXT || ' %',
    'Taux de succès global'
FROM fact_transactions
UNION ALL
SELECT 'KPI GLOBAL',
    ROUND(SUM(fee), 0)::TEXT || ' MRU',
    'Frais collectés (SUCCESS uniquement)'
FROM fact_transactions WHERE status = 'SUCCESS'
UNION ALL
SELECT 'QUALITÉ DONNÉES',
    COUNT(*)::TEXT,
    'CONFLICT non résolvables'
FROM fact_transactions WHERE is_unresolvable_conflict = TRUE
UNION ALL
SELECT 'QUALITÉ DONNÉES',
    COUNT(*)::TEXT,
    'Transactions LAGGING'
FROM fact_transactions WHERE is_lagging = TRUE
UNION ALL
SELECT 'QUALITÉ DONNÉES',
    COUNT(*)::TEXT,
    'Clock skew détectés'
FROM fact_transactions WHERE has_clock_skew = TRUE;
