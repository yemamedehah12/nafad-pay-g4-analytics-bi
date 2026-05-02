{{
  config(
    materialized='view',
    description='Transactions nettoyées et typées depuis tmp_transactions'
  )
}}

/*
  Stratégie CONFLICT (1 549 cas, dont 1 529 sans amount_node_a/b) :
  - Si amount_node_a ET amount_node_b présents → prendre la moyenne pondérée
  - Si seul amount_node_a présent → prendre amount_node_a
  - Sinon (98.7% des CONFLICT) → garder amount original + flag UNRESOLVABLE
*/

WITH base AS (
    SELECT
        id::BIGINT                                  AS transaction_id,
        reference,
        idempotency_key,
        transaction_type,
        status,
        NULLIF(TRIM(failure_reason), '')            AS failure_reason,
        NULLIF(TRIM(channel), '')                   AS channel,
        NULLIF(TRIM(device_type), '')               AS device_type,
        sync_status,
        node_id,
        datacenter,

        -- Résolution montant CONFLICT
        CASE
            WHEN sync_status = 'CONFLICT'
                 AND TRIM(amount_node_a) != '' AND amount_node_a IS NOT NULL
                 AND TRIM(amount_node_b) != '' AND amount_node_b IS NOT NULL
                THEN (TRIM(amount_node_a)::NUMERIC + TRIM(amount_node_b)::NUMERIC) / 2
            WHEN sync_status = 'CONFLICT'
                 AND TRIM(amount_node_a) != '' AND amount_node_a IS NOT NULL
                THEN TRIM(amount_node_a)::NUMERIC
            ELSE TRIM(amount)::NUMERIC
        END                                         AS amount,

        -- Flag de résolvabilité du CONFLICT
        CASE
            WHEN sync_status = 'CONFLICT'
                 AND (TRIM(COALESCE(amount_node_a, '')) = ''
                      AND TRIM(COALESCE(amount_node_b, '')) = '')
                THEN TRUE
            ELSE FALSE
        END                                         AS is_unresolvable_conflict,

        CASE WHEN TRIM(fee) = ''          THEN 0    ELSE TRIM(fee)::NUMERIC          END AS fee,
        CASE WHEN TRIM(total_amount) = '' THEN NULL ELSE TRIM(total_amount)::NUMERIC END AS total_amount,
        CASE WHEN TRIM(balance_before) = '' THEN NULL ELSE TRIM(balance_before)::NUMERIC END AS balance_before,
        CASE WHEN TRIM(balance_after)  = '' THEN NULL ELSE TRIM(balance_after)::NUMERIC  END AS balance_after,
        CASE WHEN TRIM(risk_score) = ''   THEN NULL ELSE TRIM(risk_score)::NUMERIC   END AS risk_score,

        -- Flags distribués / qualité
        (sync_status = 'CONFLICT')                  AS is_conflict,
        (sync_status = 'LAGGING')                   AS is_lagging,
        (sync_status = 'PENDING')                   AS is_pending_sync,
        (
            (datacenter = 'DC-NDB'     AND node_id LIKE 'NKC%') OR
            (datacenter LIKE 'DC-NKC%' AND node_id LIKE 'NDB%')
        )                                           AS is_cross_dc,

        -- Timestamps
        transaction_date::DATE                      AS transaction_date,
        CASE WHEN TRIM(transaction_time) = '' THEN NULL
             ELSE TRIM(transaction_time)::TIME END  AS transaction_time,
        CASE WHEN TRIM(created_at) = '' THEN NULL
             ELSE TRIM(created_at)::TIMESTAMP END   AS created_at,
        CASE WHEN TRIM(completed_at) = '' THEN NULL
             ELSE TRIM(completed_at)::TIMESTAMP END AS completed_at,

        source_user_id::BIGINT                      AS user_id,
        CASE WHEN TRIM(COALESCE(merchant_id,'')) = '' THEN NULL
             ELSE merchant_id::BIGINT END           AS merchant_id,
        CASE WHEN TRIM(COALESCE(agency_id,'')) = '' THEN NULL
             ELSE agency_id::BIGINT END             AS agency_id

    FROM {{ source('raw', 'tmp_transactions') }}
),

with_clock_skew AS (
    SELECT
        *,
        -- Clock skew : last_synced_at < created_at (anomalie de synchronisation)
        CASE
            WHEN completed_at IS NOT NULL AND created_at IS NOT NULL
                 AND completed_at < created_at
                THEN TRUE
            ELSE FALSE
        END AS has_clock_skew
    FROM base
)

SELECT * FROM with_clock_skew
