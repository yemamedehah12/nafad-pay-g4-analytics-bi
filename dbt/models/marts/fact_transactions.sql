{{
  config(
    materialized='table',
    description='Table de faits centrale — 1 ligne = 1 transaction',
    indexes=[
      {'columns': ['date_key']},
      {'columns': ['user_key']},
      {'columns': ['date_key', 'status']},
      {'columns': ['sync_status']},
      {'columns': ['transaction_type']},
      {'columns': ['merchant_key']}
    ]
  )
}}

WITH stg AS (
    SELECT * FROM {{ ref('stg_transactions') }}
),

dim_u AS (
    SELECT user_key, user_id FROM {{ ref('dim_user') }}
    WHERE is_current = TRUE
),

dim_m AS (
    SELECT merchant_key, merchant_id FROM {{ ref('dim_merchant') }}
),

dim_a AS (
    SELECT agency_key, agency_id FROM {{ ref('dim_agency') }}
),

dim_n AS (
    SELECT node_key, node_id FROM {{ ref('dim_node') }}
),

dim_d AS (
    SELECT date_key, full_date FROM {{ ref('dim_date') }}
)

SELECT
    stg.transaction_id,
    stg.reference,
    stg.idempotency_key,

    -- Clés de dimension
    d.date_key,
    COALESCE(u.user_key, -1)        AS user_key,
    COALESCE(m.merchant_key, -1)    AS merchant_key,
    COALESCE(a.agency_key, -1)      AS agency_key,
    n.node_key,

    -- Mesures
    stg.amount,
    stg.fee,
    stg.total_amount,
    stg.balance_before,
    stg.balance_after,
    stg.risk_score,

    -- Attributs
    stg.transaction_type,
    stg.status,
    stg.failure_reason,
    stg.channel,
    stg.device_type,

    -- Qualité
    stg.sync_status,
    stg.is_conflict,
    stg.is_unresolvable_conflict,
    stg.is_lagging,
    stg.is_pending_sync,
    stg.is_cross_dc,
    stg.has_clock_skew,

    -- Timestamps
    stg.transaction_date,
    stg.transaction_time,
    stg.created_at,
    stg.completed_at

FROM stg
JOIN dim_d d ON d.full_date = stg.transaction_date
LEFT JOIN dim_u u ON u.user_id = stg.user_id
LEFT JOIN dim_m m ON m.merchant_id = stg.merchant_id
LEFT JOIN dim_a a ON a.agency_id = stg.agency_id
JOIN dim_n n ON n.node_id = stg.node_id
