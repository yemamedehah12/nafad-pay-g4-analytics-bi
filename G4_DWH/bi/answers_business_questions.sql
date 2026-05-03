-- ============================================================
-- NAFAD PAY G4 — Réponses aux 15 Questions Métier du DG
-- Schéma : fact_transactions + dim_date, dim_user,
--          dim_merchant, dim_agency, dim_node
-- Monnaie : MRU (Ouguiya mauritanien)
-- ============================================================


-- ============================================================
-- SECTION 1 : PERFORMANCE GLOBALE
-- ============================================================

-- Q1 : Volume total ce mois vs mois précédent
-- Résultat : volume + variation absolue et en % entre les 2 derniers mois
WITH monthly_volume AS (
    SELECT
        d.year,
        d.month,
        d.month_name,
        ROUND(SUM(f.amount), 0)  AS volume_mru,
        COUNT(*)                 AS nb_transactions,
        RANK() OVER (ORDER BY d.year DESC, d.month DESC) AS rk
    FROM fact_transactions f
    JOIN dim_date d ON f.date_key = d.date_key
    WHERE f.is_conflict = FALSE
    GROUP BY d.year, d.month, d.month_name
)
SELECT
    cur.month_name                                       AS mois_courant,
    cur.volume_mru                                       AS volume_mois_courant_mru,
    pre.month_name                                       AS mois_precedent,
    pre.volume_mru                                       AS volume_mois_precedent_mru,
    cur.volume_mru - pre.volume_mru                     AS variation_absolue_mru,
    ROUND((cur.volume_mru - pre.volume_mru) * 100.0
          / NULLIF(pre.volume_mru, 0), 1)               AS variation_pct
FROM monthly_volume cur
JOIN monthly_volume pre ON pre.rk = 2
WHERE cur.rk = 1;


-- Q2 : Taux de succès global des transactions
SELECT
    ROUND(
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    ) AS taux_succes_pct,
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS nb_succes,
    SUM(CASE WHEN status = 'FAILED'  THEN 1 ELSE 0 END) AS nb_echecs,
    COUNT(*) AS total
FROM fact_transactions;
-- Résultat attendu : ~67.3%


-- Q3 : Total des frais collectés (en MRU)
SELECT
    ROUND(SUM(fee), 0)          AS frais_total_mru,
    ROUND(AVG(fee), 2)          AS frais_moyen_par_tx,
    ROUND(SUM(fee) / NULLIF(SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END), 0), 2)
                                AS frais_moyen_tx_succes,
    COUNT(CASE WHEN fee > 0 THEN 1 END) AS nb_tx_avec_frais
FROM fact_transactions
WHERE is_conflict = FALSE;


-- ============================================================
-- SECTION 2 : ANALYSE GÉOGRAPHIQUE
-- ============================================================

-- Q4 : Wilaya qui génère le plus de volume
SELECT
    u.wilaya_name                       AS wilaya,
    COUNT(*)                            AS nb_transactions,
    ROUND(SUM(f.amount), 0)             AS volume_mru,
    ROUND(AVG(f.amount), 0)             AS panier_moyen_mru,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct_transactions
FROM fact_transactions f
JOIN dim_user u ON f.user_key = u.user_key
WHERE u.wilaya_name IS NOT NULL
  AND u.is_current = TRUE
  AND f.is_conflict = FALSE
GROUP BY u.wilaya_name
ORDER BY volume_mru DESC
LIMIT 10;


-- Q5 : Agence la plus performante
SELECT
    a.name                              AS agence,
    a.wilaya_name                       AS wilaya,
    a.tier                              AS tier,
    COUNT(*)                            AS nb_transactions,
    ROUND(SUM(f.amount), 0)             AS volume_mru,
    ROUND(SUM(f.fee), 0)               AS frais_generes_mru,
    ROUND(AVG(f.amount), 0)            AS panier_moyen_mru,
    SUM(CASE WHEN f.status = 'SUCCESS' THEN 1 ELSE 0 END) AS nb_succes,
    ROUND(SUM(CASE WHEN f.status = 'SUCCESS' THEN 1 ELSE 0 END) * 100.0
          / NULLIF(COUNT(*), 0), 1)    AS taux_succes_pct
FROM fact_transactions f
JOIN dim_agency a ON f.agency_key = a.agency_key
WHERE a.agency_key != -1
  AND f.is_conflict = FALSE
GROUP BY a.agency_key, a.name, a.wilaya_name, a.tier
ORDER BY volume_mru DESC
LIMIT 10;


-- Q6 : Opportunités de croissance (wilayas sous-exploitées)
-- Identifie les wilayas avec un fort nombre d'utilisateurs mais un faible volume
WITH wilaya_stats AS (
    SELECT
        u.wilaya_name,
        COUNT(DISTINCT u.user_key)      AS nb_utilisateurs,
        COUNT(DISTINCT f.tx_pk)         AS nb_transactions,
        ROUND(SUM(f.amount), 0)         AS volume_mru
    FROM dim_user u
    LEFT JOIN fact_transactions f
           ON f.user_key = u.user_key AND f.is_conflict = FALSE
    WHERE u.wilaya_name IS NOT NULL
      AND u.is_current = TRUE
    GROUP BY u.wilaya_name
),
moyennes AS (
    SELECT
        ROUND(AVG(nb_transactions::NUMERIC / NULLIF(nb_utilisateurs, 0)), 2) AS moy_tx_par_user,
        ROUND(AVG(volume_mru::NUMERIC / NULLIF(nb_utilisateurs, 0)), 0)      AS moy_volume_par_user
    FROM wilaya_stats
)
SELECT
    ws.wilaya_name,
    ws.nb_utilisateurs,
    ws.nb_transactions,
    ROUND(ws.nb_transactions::NUMERIC / NULLIF(ws.nb_utilisateurs, 0), 2) AS tx_par_user,
    m.moy_tx_par_user                                                     AS moy_nationale_tx_par_user,
    CASE
        WHEN ws.nb_transactions::NUMERIC / NULLIF(ws.nb_utilisateurs, 0)
             < m.moy_tx_par_user * 0.75
        THEN 'Fort potentiel'
        WHEN ws.nb_transactions::NUMERIC / NULLIF(ws.nb_utilisateurs, 0)
             < m.moy_tx_par_user
        THEN 'Potentiel modéré'
        ELSE 'Déjà performante'
    END AS opportunite
FROM wilaya_stats ws, moyennes m
ORDER BY
    CASE WHEN ws.nb_transactions::NUMERIC / NULLIF(ws.nb_utilisateurs, 0)
              < m.moy_tx_par_user * 0.75 THEN 1
         WHEN ws.nb_transactions::NUMERIC / NULLIF(ws.nb_utilisateurs, 0)
              < m.moy_tx_par_user THEN 2
         ELSE 3 END,
    ws.nb_utilisateurs DESC;


-- ============================================================
-- SECTION 3 : ANALYSE UTILISATEURS
-- ============================================================

-- Q7 : Nouveaux utilisateurs ce mois (dernier mois présent dans les données)
WITH dernier_mois AS (
    SELECT
        EXTRACT(YEAR FROM MAX(f.transaction_date))::INT  AS annee,
        EXTRACT(MONTH FROM MAX(f.transaction_date))::INT AS mois
    FROM fact_transactions f
)
SELECT
    dm.annee,
    dm.mois,
    COUNT(*) AS nouveaux_utilisateurs
FROM dim_user u, dernier_mois dm
WHERE u.is_current = TRUE
  AND EXTRACT(YEAR  FROM u.registration_date) = dm.annee
  AND EXTRACT(MONTH FROM u.registration_date) = dm.mois
GROUP BY dm.annee, dm.mois;

-- Évolution mensuelle des inscriptions (vue complète)
SELECT
    EXTRACT(YEAR  FROM registration_date)::INT AS annee,
    EXTRACT(MONTH FROM registration_date)::INT AS mois,
    COUNT(*) AS nouveaux_utilisateurs
FROM dim_user
WHERE is_current = TRUE
GROUP BY annee, mois
ORDER BY annee, mois;


-- Q8 : Taux de rétention mensuel
-- Définition : % d'utilisateurs actifs le mois M qui étaient déjà actifs le mois M-1
WITH monthly_active AS (
    SELECT DISTINCT
        d.year,
        d.month,
        f.user_key
    FROM fact_transactions f
    JOIN dim_date d ON f.date_key = d.date_key
    WHERE f.status = 'SUCCESS'
),
retention AS (
    SELECT
        cur.year,
        cur.month,
        COUNT(DISTINCT cur.user_key)  AS actifs_mois_courant,
        COUNT(DISTINCT pre.user_key)  AS retenus_du_mois_precedent
    FROM monthly_active cur
    LEFT JOIN monthly_active pre
           ON cur.user_key = pre.user_key
          AND (cur.year * 12 + cur.month) = (pre.year * 12 + pre.month) + 1
    GROUP BY cur.year, cur.month
)
SELECT
    year,
    month,
    actifs_mois_courant,
    retenus_du_mois_precedent,
    ROUND(retenus_du_mois_precedent * 100.0
          / NULLIF(actifs_mois_courant, 0), 1) AS taux_retention_pct
FROM retention
ORDER BY year, month;


-- Q9 : Utilisateurs ayant complété leur KYC
-- ⚠ NOTE : kyc_level est NULL à 100% dans stg_users.csv (anomalie connue).
--   La requête est fournie pour le jour où la colonne sera renseignée.
SELECT
    COALESCE(NULLIF(kyc_level, ''), 'Non renseigné') AS niveau_kyc,
    COUNT(*)                                          AS nb_utilisateurs,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pourcentage
FROM dim_user
WHERE is_current = TRUE
GROUP BY kyc_level
ORDER BY nb_utilisateurs DESC;

-- Proxy utilisable en attendant : répartition par statut de compte
SELECT
    status                                              AS statut_compte,
    COUNT(*)                                           AS nb_utilisateurs,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pourcentage
FROM dim_user
WHERE is_current = TRUE
GROUP BY status
ORDER BY nb_utilisateurs DESC;


-- ============================================================
-- SECTION 4 : ANALYSE TRANSACTIONS
-- ============================================================

-- Q10 : Répartition par type de transaction
-- DEP=Dépôt  WIT=Retrait  TRF=Transfert  PAY=Paiement
-- BIL=Facture  AIR=Airtime  SAL=Salaire  REV=Remboursement
SELECT
    transaction_type                                    AS type_tx,
    CASE transaction_type
        WHEN 'DEP' THEN 'Dépôt'
        WHEN 'WIT' THEN 'Retrait'
        WHEN 'TRF' THEN 'Transfert'
        WHEN 'PAY' THEN 'Paiement marchand'
        WHEN 'BIL' THEN 'Paiement facture'
        WHEN 'AIR' THEN 'Airtime'
        WHEN 'SAL' THEN 'Salaire'
        WHEN 'REV' THEN 'Remboursement'
        ELSE type_tx
    END                                                 AS libelle,
    COUNT(*)                                            AS nb_transactions,
    ROUND(SUM(amount), 0)                               AS volume_mru,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)  AS pct_volume_transactions
FROM fact_transactions
WHERE is_conflict = FALSE
GROUP BY transaction_type
ORDER BY nb_transactions DESC;


-- Q11 : Heures de pointe (transactions par heure)
SELECT
    EXTRACT(HOUR FROM transaction_time)::INT            AS heure,
    TO_CHAR(EXTRACT(HOUR FROM transaction_time)::INT, '00') || 'h' AS plage_horaire,
    COUNT(*)                                            AS nb_transactions,
    ROUND(SUM(amount), 0)                               AS volume_mru,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)  AS pct
FROM fact_transactions
WHERE transaction_time IS NOT NULL
GROUP BY heure
ORDER BY heure;


-- Q12 : Principaux motifs d'échec
SELECT
    COALESCE(NULLIF(TRIM(failure_reason), ''), 'Non précisé') AS motif_echec,
    COUNT(*)                                            AS nb_echecs,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)  AS pct_des_echecs
FROM fact_transactions
WHERE status = 'FAILED'
GROUP BY failure_reason
ORDER BY nb_echecs DESC
LIMIT 10;


-- ============================================================
-- SECTION 5 : ANALYSE MARCHANDS
-- ============================================================

-- Q13 : Catégories de marchands avec le plus de transactions
SELECT
    m.category_label                                    AS categorie,
    COUNT(DISTINCT f.tx_pk)                            AS nb_transactions,
    ROUND(SUM(f.amount), 0)                            AS volume_mru,
    ROUND(SUM(f.fee), 0)                               AS frais_generes_mru,
    COUNT(DISTINCT m.merchant_key)                     AS nb_marchands_actifs,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct_transactions
FROM fact_transactions f
JOIN dim_merchant m ON f.merchant_key = m.merchant_key
WHERE m.merchant_key != -1
  AND f.is_conflict = FALSE
GROUP BY m.category_label
ORDER BY nb_transactions DESC;


-- Q14 : Panier moyen par catégorie de marchand
SELECT
    m.category_label                                    AS categorie,
    COUNT(*)                                           AS nb_transactions,
    ROUND(AVG(f.amount), 0)                            AS panier_moyen_mru,
    ROUND(MIN(f.amount), 0)                            AS montant_min_mru,
    ROUND(MAX(f.amount), 0)                            AS montant_max_mru,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.amount), 0) AS mediane_mru
FROM fact_transactions f
JOIN dim_merchant m ON f.merchant_key = m.merchant_key
WHERE m.merchant_key != -1
  AND f.is_conflict = FALSE
  AND f.status = 'SUCCESS'
GROUP BY m.category_label
ORDER BY panier_moyen_mru DESC;


-- Q15 : Marchands actifs vs inactifs
SELECT
    m.status                                           AS statut_marchand,
    COUNT(*)                                           AS nb_marchands,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pourcentage
FROM dim_merchant m
WHERE m.merchant_key != -1
GROUP BY m.status
ORDER BY nb_marchands DESC;

-- Détail : marchands "actifs" selon l'activité transactionnelle réelle
WITH merchant_activity AS (
    SELECT
        m.merchant_id,
        m.name,
        m.category_label,
        m.status                                       AS statut_referentiel,
        COUNT(f.tx_pk)                                 AS nb_transactions_reelles
    FROM dim_merchant m
    LEFT JOIN fact_transactions f
           ON f.merchant_key = m.merchant_key
          AND f.is_conflict = FALSE
    WHERE m.merchant_key != -1
    GROUP BY m.merchant_id, m.name, m.category_label, m.status
)
SELECT
    statut_referentiel,
    SUM(CASE WHEN nb_transactions_reelles > 0 THEN 1 ELSE 0 END)  AS actifs_avec_transactions,
    SUM(CASE WHEN nb_transactions_reelles = 0 THEN 1 ELSE 0 END)  AS inactifs_sans_transaction,
    COUNT(*)                                                        AS total
FROM merchant_activity
GROUP BY statut_referentiel;
