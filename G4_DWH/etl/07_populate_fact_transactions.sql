-- ============================================================
-- NAFAD PAY G4 — Peuplement fact_transactions
-- Description : Table centrale du DWH avec gestion des anomalies
-- ============================================================

\echo 'Peuplement fact_transactions...'

INSERT INTO fact_transactions (
    transaction_id, reference, idempotency_key,
    date_key, user_key, merchant_key, agency_key, node_key,
    amount, fee, total_amount,
    balance_before, balance_after, risk_score,
    transaction_type, status, failure_reason,
    channel, device_type,
    sync_status, is_conflict, is_lagging,
    is_pending_sync, is_cross_dc,
    transaction_date, transaction_time,
    created_at, completed_at
)
SELECT
    t.id,
    t.reference,
    t.idempotency_key,

    -- Jointure dim_date
    TO_CHAR(t.transaction_date::DATE, 'YYYYMMDD')::INT  AS date_key,

    -- Jointure dim_user (version actuelle)
    COALESCE(u.user_key, -1)                            AS user_key,

    -- Jointure dim_merchant (-1 si pas de marchand)
    COALESCE(m.merchant_key, -1)                        AS merchant_key,

    -- Jointure dim_agency (-1 si pas d'agence)
    COALESCE(a.agency_key, -1)                          AS agency_key,

    -- Jointure dim_node
    n.node_key,

    -- ⚠️ Gestion CONFLICT : choisir le bon montant
    CASE
        WHEN t.sync_status = 'CONFLICT'
         AND TRIM(t.amount_node_a) != ''
         AND t.amount_node_a IS NOT NULL
            THEN TRIM(t.amount_node_a)::NUMERIC
        ELSE TRIM(t.amount)::NUMERIC
    END                                                 AS amount,

    CASE WHEN TRIM(t.fee) = '' THEN 0
         ELSE TRIM(t.fee)::NUMERIC END                  AS fee,

    CASE WHEN TRIM(t.total_amount) = '' THEN NULL
         ELSE TRIM(t.total_amount)::NUMERIC END         AS total_amount,

    CASE WHEN TRIM(t.balance_before) = '' THEN NULL
         ELSE TRIM(t.balance_before)::NUMERIC END       AS balance_before,

    CASE WHEN TRIM(t.balance_after) = '' THEN NULL
         ELSE TRIM(t.balance_after)::NUMERIC END        AS balance_after,

    CASE WHEN TRIM(t.risk_score) = '' THEN NULL
         ELSE TRIM(t.risk_score)::NUMERIC END           AS risk_score,

    t.transaction_type,
    t.status,
    NULLIF(TRIM(t.failure_reason), ''),
    NULLIF(TRIM(t.channel), ''),
    NULLIF(TRIM(t.device_type), ''),

    -- Flags qualité
    t.sync_status,
    (t.sync_status = 'CONFLICT')                        AS is_conflict,
    (t.sync_status = 'LAGGING')                         AS is_lagging,
    (t.sync_status = 'PENDING')                         AS is_pending_sync,

    -- Cross datacenter
    (
        (t.datacenter = 'DC-NDB'      AND t.node_id LIKE 'NKC%') OR
        (t.datacenter LIKE 'DC-NKC%'  AND t.node_id LIKE 'NDB%')
    )                                                   AS is_cross_dc,

    t.transaction_date::DATE,
    CASE WHEN TRIM(t.transaction_time) = '' THEN NULL
         ELSE TRIM(t.transaction_time)::TIME END,

    CASE WHEN TRIM(t.created_at) = '' THEN NULL
         ELSE TRIM(t.created_at)::TIMESTAMP END,

    CASE WHEN TRIM(t.completed_at) = '' THEN NULL
         ELSE TRIM(t.completed_at)::TIMESTAMP END

FROM tmp_transactions t

LEFT JOIN dim_user u
    ON u.user_id = t.source_user_id::BIGINT
    AND u.is_current = TRUE

LEFT JOIN dim_merchant m
    ON m.merchant_id = t.merchant_id::BIGINT

LEFT JOIN dim_agency a
    ON a.agency_id = t.agency_id::BIGINT

JOIN dim_node n
    ON n.node_id = t.node_id;

SELECT COUNT(*) AS nb_transactions FROM fact_transactions;
-- Attendu : 100 000