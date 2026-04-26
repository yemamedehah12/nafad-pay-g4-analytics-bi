-- =============================================================================
-- ETL: Transform Staging Data to DWH Star Schema
-- =============================================================================

-- ============================================================================ 
-- STEP 1: Load dim_node (Datacenters)
-- ============================================================================
INSERT INTO dim_node (node_id, datacenter, aws_region, aws_az, status)
SELECT DISTINCT 
    node_id,
    datacenter,
    CASE 
        WHEN datacenter = 'DC-NKC-PRIMARY' THEN 'eu-west-3'
        WHEN datacenter = 'DC-NKC-SECONDARY' THEN 'eu-west-3'
        WHEN datacenter = 'DC-NDB' THEN 'eu-west-3'
        ELSE 'eu-west-3'
    END as aws_region,
    CASE 
        WHEN datacenter = 'DC-NKC-PRIMARY' THEN 'eu-west-3a'
        WHEN datacenter = 'DC-NKC-SECONDARY' THEN 'eu-west-3b'
        WHEN datacenter = 'DC-NDB' THEN 'eu-west-3c'
        ELSE 'eu-west-3a'
    END as aws_az,
    'ACTIVE'
FROM stg_transactions
ON CONFLICT (node_id) DO NOTHING;

-- ============================================================================
-- STEP 2: Load dim_date (Calendar Dimension)
-- ============================================================================
-- Generate dates from MIN to MAX transaction date
WITH date_range AS (
    SELECT GENERATE_SERIES(
        DATE(MIN(transaction_date)),
        DATE(MAX(transaction_date)),
        INTERVAL '1 day'
    )::DATE as date_value
    FROM stg_transactions
)
INSERT INTO dim_date (date_key, date_value, year, month, day, quarter, week_of_year, day_of_week, day_name, is_weekend)
SELECT 
    TO_CHAR(date_value, 'YYYYMMDD')::INT as date_key,
    date_value,
    EXTRACT(YEAR FROM date_value)::INT as year,
    EXTRACT(MONTH FROM date_value)::INT as month,
    EXTRACT(DAY FROM date_value)::INT as day,
    CEIL(EXTRACT(MONTH FROM date_value)::NUMERIC / 3)::INT as quarter,
    EXTRACT(WEEK FROM date_value)::INT as week_of_year,
    EXTRACT(DOW FROM date_value)::INT as day_of_week,
    TO_CHAR(date_value, 'Day') as day_name,
    EXTRACT(DOW FROM date_value)::INT IN (0, 6) as is_weekend
FROM date_range
ON CONFLICT (date_key) DO NOTHING;

-- ============================================================================
-- STEP 3: Load dim_merchant
-- ============================================================================
INSERT INTO dim_merchant (
    merchant_id, merchant_name, merchant_category, wilaya_name, business_type, status
)
SELECT 
    id as merchant_id,
    name as merchant_name,
    category as merchant_category,
    wilaya as wilaya_name,
    business_type,
    CASE WHEN status = 1 THEN 'ACTIVE' ELSE 'INACTIVE' END as status
FROM stg_merchants
ON CONFLICT (merchant_id) DO NOTHING;

-- ============================================================================
-- STEP 4: Load dim_agency
-- ============================================================================
INSERT INTO dim_agency (
    agency_id, agency_name, wilaya_name, float_balance, tier, license_number, status
)
SELECT 
    id as agency_id,
    name as agency_name,
    COALESCE(wilaya, 'UNKNOWN') as wilaya_name,
    COALESCE(float_balance, 0) as float_balance,
    COALESCE(tier, 'TIER_1') as tier,
    license_number,
    CASE WHEN status = 1 THEN 'ACTIVE' ELSE 'INACTIVE' END as status
FROM stg_agencies
ON CONFLICT (agency_id) DO NOTHING;

-- ============================================================================
-- STEP 5: Load dim_agent
-- ============================================================================
INSERT INTO dim_agent (agent_id, agent_name, agency_id, status)
SELECT 
    id as agent_id,
    name as agent_name,
    agency_id,
    CASE WHEN status = 1 THEN 'ACTIVE' ELSE 'INACTIVE' END as status
FROM stg_agents
ON CONFLICT (agent_id) DO NOTHING;

-- Update dim_agent with agency_key
UPDATE dim_agent da
SET agency_key = dag.agency_key
FROM dim_agency dag
WHERE da.agency_id = dag.agency_id;

-- ============================================================================
-- STEP 6: Load dim_user (Type 2 SCD)
-- ============================================================================
-- Insert all users as current=TRUE with today's effective date
INSERT INTO dim_user (
    user_id, first_name, last_name, email, phone_number, nni, 
    kyc_level, wilaya_name, user_status, account_count,
    is_current, effective_date, end_date
)
SELECT 
    id as user_id,
    first_name,
    last_name,
    CASE WHEN email = '' OR email IS NULL THEN NULL ELSE email END as email,
    phone_number,
    CASE WHEN nni = '' OR nni IS NULL THEN NULL ELSE nni END as nni,
    COALESCE(NULLIF(kyc_level, ''), 'LEVEL_0') as kyc_level,
    COALESCE(NULLIF(moughataa_name, ''), 'UNKNOWN') as wilaya_name,
    CASE WHEN user_status = 1 THEN 'ACTIVE' ELSE 'INACTIVE' END as user_status,
    1 as account_count,
    TRUE as is_current,
    CURRENT_DATE as effective_date,
    NULL::DATE as end_date
FROM stg_users
ON CONFLICT (user_id, effective_date) DO NOTHING;

-- ============================================================================
-- STEP 7: Load dim_account
-- ============================================================================
INSERT INTO dim_account (account_id, user_id, account_type, account_status, balance)
SELECT 
    id as account_id,
    user_id,
    COALESCE(NULLIF(account_type_label, ''), 'STANDARD') as account_type,
    CASE WHEN status = 1 THEN 'ACTIVE' ELSE 'INACTIVE' END as account_status,
    COALESCE(balance, 0) as balance
FROM stg_accounts
ON CONFLICT (account_id) DO NOTHING;

-- Update dim_account with user_key from dim_user
UPDATE dim_account da
SET user_key = (
    SELECT user_key FROM dim_user du 
    WHERE du.user_id = da.user_id AND du.is_current = TRUE
    LIMIT 1
)
WHERE user_key IS NULL;

-- ============================================================================
-- STEP 8: Load fact_transactions (with anomaly handling)
-- ============================================================================
-- STRATEGY FOR ANOMALIES:
-- 1. CONFLICT transactions: Keep the amount from the primary field, but flag them
-- 2. LAGGING/PENDING: Include but flag with data_quality_flag
-- 3. amount_node_a/b only rilled for ~20 CONFLICT: For others, use amount field
--
INSERT INTO fact_transactions (
    transaction_id, idempotency_key, date_key,
    source_user_key, destination_user_key,
    source_account_key, destination_account_key,
    merchant_key, agency_key, agent_key, node_key,
    transaction_type, amount, fee, total_amount,
    status, failure_reason,
    balance_before, balance_after,
    sync_status, amount_node_a, amount_node_b, last_synced_at,
    data_source_node_a, data_source_node_b,
    risk_score, channel, device_type, ip_address,
    transaction_date, transaction_time,
    created_at, updated_at, completed_at,
    is_cross_dc, is_conflict,
    data_quality_flag
)
SELECT 
    st.id as transaction_id,
    st.idempotency_key,
    TO_CHAR(DATE(st.transaction_date), 'YYYYMMDD')::INT as date_key,
    
    -- Users
    COALESCE(du_src.user_key, -1) as source_user_key,
    COALESCE(du_dst.user_key, -1) as destination_user_key,
    COALESCE(da_src.account_key, -1) as source_account_key,
    COALESCE(da_dst.account_key, -1) as destination_account_key,
    
    -- Merchants & Agencies
    COALESCE(dm.merchant_key, -1) as merchant_key,
    COALESCE(dag.agency_key, -1) as agency_key,
    COALESCE(dagt.agent_key, -1) as agent_key,
    
    COALESCE(dn.node_key, 1) as node_key,
    
    -- Transaction Details
    st.transaction_type,
    st.amount as amount,
    st.fee,
    st.total_amount,
    
    -- Status
    CASE 
        WHEN st.status = 1 THEN 'SUCCESS'
        WHEN st.status = 2 THEN 'FAILED'
        ELSE 'PENDING'
    END as status,
    st.failure_reason,
    
    -- Balance
    st.balance_before,
    st.balance_after,
    
    -- Sync Status
    st.sync_status,
    st.amount_node_a,
    st.amount_node_b,
    st.last_synced_at,
    
    -- Data source flags
    CASE WHEN st.amount_node_a IS NOT NULL THEN TRUE ELSE FALSE END as data_source_node_a,
    CASE WHEN st.amount_node_b IS NOT NULL THEN TRUE ELSE FALSE END as data_source_node_b,
    
    -- Risk
    st.risk_score,
    st.channel,
    st.device_type,
    st.ip_address,
    
    -- Time
    DATE(st.transaction_date) as transaction_date,
    TIME(st.transaction_date) as transaction_time,
    st.created_at,
    st.updated_at,
    st.completed_at,
    
    -- Flags
    CASE WHEN st.datacenter IN ('DC-NKC-PRIMARY', 'DC-NKC-SECONDARY', 'DC-NDB') THEN TRUE ELSE FALSE END as is_cross_dc,
    CASE WHEN st.sync_status = 'CONFLICT' THEN TRUE ELSE FALSE END as is_conflict,
    
    -- Data Quality Flag (CRITICAL: Identifies anomalies)
    CASE 
        WHEN st.sync_status = 'CONFLICT' AND st.amount_node_a IS NULL AND st.amount_node_b IS NULL 
            THEN 'ANOMALY:CONFLICT_NO_NODE_AMOUNTS'
        WHEN st.sync_status = 'LAGGING' THEN 'FLAG:LAGGING_SYNC'
        WHEN st.sync_status = 'PENDING' THEN 'FLAG:PENDING_SYNC'
        WHEN st.last_synced_at < st.created_at THEN 'FLAG:LAST_SYNCED_BEFORE_CREATED'
        ELSE NULL
    END as data_quality_flag
FROM stg_transactions st
LEFT JOIN dim_user du_src ON st.source_user_id = du_src.user_id AND du_src.is_current = TRUE
LEFT JOIN dim_user du_dst ON st.destination_user_id = du_dst.user_id AND du_dst.is_current = TRUE
LEFT JOIN dim_account da_src ON st.source_account_id = da_src.account_id
LEFT JOIN dim_account da_dst ON st.destination_account_id = da_dst.account_id
LEFT JOIN dim_merchant dm ON st.merchant_id = dm.merchant_id
LEFT JOIN dim_agency dag ON st.agency_id = dag.agency_id
LEFT JOIN dim_agent dagt ON st.agent_id = dagt.agent_id
LEFT JOIN dim_node dn ON st.node_id = dn.node_id AND st.datacenter = dn.datacenter
ON CONFLICT (transaction_id) DO NOTHING;

-- ============================================================================
-- STEP 9: Quality Checks & Audit
-- ============================================================================
INSERT INTO staging_metadata (
    stage_name, total_records_processed, total_records_loaded, 
    total_records_rejected, rejected_reasons, data_quality_issues, load_date, notes
)
SELECT 
    'fact_transactions' as stage_name,
    COUNT(DISTINCT id) as total_records_processed,
    COUNT(DISTINCT ft.transaction_id) as total_records_loaded,
    COUNT(DISTINCT st.id) - COUNT(DISTINCT ft.transaction_id) as total_records_rejected,
    'See data_quality_flag in fact_transactions' as rejected_reasons,
    CONCAT(
        'CONFLICT: ', (SELECT COUNT(*) FROM fact_transactions WHERE sync_status = 'CONFLICT'), ', ',
        'LAGGING: ', (SELECT COUNT(*) FROM fact_transactions WHERE sync_status = 'LAGGING'), ', ',
        'PENDING: ', (SELECT COUNT(*) FROM fact_transactions WHERE sync_status = 'PENDING')
    ) as data_quality_issues,
    CURRENT_DATE as load_date,
    'ETL load completed - review data_quality_flag column for anomalies' as notes
FROM stg_transactions st
LEFT JOIN fact_transactions ft ON st.id = ft.transaction_id;

-- ============================================================================
-- STEP 10: Post-Load Validation Queries
-- ============================================================================
-- These can be extracted to separate analysis reports

-- Query 1: Verify record counts
SELECT 'Fact Transactions' as table_name, COUNT(*) as record_count FROM fact_transactions
UNION ALL
SELECT 'Dim User', COUNT(*) FROM dim_user
UNION ALL
SELECT 'Dim Merchant', COUNT(*) FROM dim_merchant
UNION ALL
SELECT 'Dim Agency', COUNT(*) FROM dim_agency;

-- Query 2: Check anomalies
SELECT 
    sync_status,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM fact_transactions), 2) as percent
FROM fact_transactions
GROUP BY sync_status
ORDER BY count DESC;

-- Query 3: Data quality issues
SELECT 
    data_quality_flag,
    COUNT(*) as count
FROM fact_transactions
WHERE data_quality_flag IS NOT NULL
GROUP BY data_quality_flag
ORDER BY count DESC;
