-- =============================================================================
-- Create Staging Tables and Load CSV Data
-- Run this BEFORE the star schema ETL
-- =============================================================================

-- Create staging tables (exactly matching CSV structure)

CREATE TABLE IF NOT EXISTS stg_users (
    id BIGINT PRIMARY KEY,
    first_name VARCHAR,
    last_name VARCHAR,
    email VARCHAR,
    phone_number VARCHAR,
    nni VARCHAR,
    kyc_level VARCHAR,
    moughataa_name VARCHAR,
    user_status INT,
    account_count INT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS stg_accounts (
    id BIGINT PRIMARY KEY,
    user_id BIGINT,
    account_type_label VARCHAR,
    status INT,
    balance NUMERIC(18,2),
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS stg_transactions (
    id BIGINT PRIMARY KEY,
    reference VARCHAR,
    idempotency_key VARCHAR,
    transaction_type VARCHAR,
    amount NUMERIC(18,2),
    fee NUMERIC(18,2),
    total_amount NUMERIC(18,2),
    source_account_id BIGINT,
    source_user_id BIGINT,
    destination_account_id BIGINT,
    destination_user_id BIGINT,
    merchant_id BIGINT,
    agency_id BIGINT,
    agent_id BIGINT,
    status INT,
    failure_reason VARCHAR,
    balance_before NUMERIC(18,2),
    balance_after NUMERIC(18,2),
    node_id VARCHAR,
    datacenter VARCHAR,
    sync_status VARCHAR,
    last_synced_at TIMESTAMP,
    amount_node_a NUMERIC(18,2),
    amount_node_b NUMERIC(18,2),
    risk_score DECIMAL(5,2),
    channel VARCHAR,
    device_type VARCHAR,
    ip_address VARCHAR,
    transaction_date TIMESTAMP,
    transaction_time TIME,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS stg_fees (
    id BIGINT PRIMARY KEY,
    transaction_id BIGINT,
    amount NUMERIC(18,2),
    fee_type VARCHAR,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS stg_merchants (
    id BIGINT PRIMARY KEY,
    name VARCHAR,
    category VARCHAR,
    wilaya VARCHAR,
    business_type VARCHAR,
    status INT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS stg_agencies (
    id BIGINT PRIMARY KEY,
    name VARCHAR,
    wilaya VARCHAR,
    float_balance NUMERIC(18,2),
    tier VARCHAR,
    license_number VARCHAR,
    status INT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS stg_agents (
    id BIGINT PRIMARY KEY,
    name VARCHAR,
    agency_id BIGINT,
    status INT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS node_metrics (
    node_id VARCHAR,
    total_amount NUMERIC(18,2),
    transaction_count INT,
    unique_users INT,
    last_updated TIMESTAMP
);

-- =============================================================================
-- LOAD DATA FROM CSV FILES
-- Note: CSV files must be in the Docker volume at /staging/
-- =============================================================================

-- On Windows with Docker, use absolute path
-- Adjust path based on your Docker volume setup

COPY stg_users(id, first_name, last_name, email, phone_number, nni, kyc_level, 
               moughataa_name, user_status, account_count, created_at, updated_at)
FROM '/staging/stg_users.csv'
CSV HEADER ENCODING 'UTF-8';

COPY stg_accounts(id, user_id, account_type_label, status, balance, created_at, updated_at)
FROM '/staging/stg_accounts.csv'
CSV HEADER ENCODING 'UTF-8';

COPY stg_transactions(id, reference, idempotency_key, transaction_type, amount, fee, total_amount,
                      source_account_id, source_user_id, destination_account_id, destination_user_id,
                      merchant_id, agency_id, agent_id, status, failure_reason,
                      balance_before, balance_after, node_id, datacenter,
                      sync_status, last_synced_at, amount_node_a, amount_node_b, risk_score,
                      channel, device_type, ip_address, transaction_date, transaction_time,
                      created_at, updated_at, completed_at)
FROM '/staging/stg_transactions.csv'
CSV HEADER ENCODING 'UTF-8';

COPY stg_fees(id, transaction_id, amount, fee_type, created_at, updated_at)
FROM '/staging/stg_fees.csv'
CSV HEADER ENCODING 'UTF-8';

COPY stg_merchants(id, name, category, wilaya, business_type, status, created_at, updated_at)
FROM '/staging/stg_merchants.csv'
CSV HEADER ENCODING 'UTF-8';

COPY stg_agencies(id, name, wilaya, float_balance, tier, license_number, status, created_at, updated_at)
FROM '/staging/stg_agencies.csv'
CSV HEADER ENCODING 'UTF-8';

COPY stg_agents(id, name, agency_id, status, created_at, updated_at)
FROM '/staging/stg_agents.csv'
CSV HEADER ENCODING 'UTF-8';

COPY node_metrics(node_id, total_amount, transaction_count, unique_users, last_updated)
FROM '/staging/node_metrics.csv'
CSV HEADER ENCODING 'UTF-8';

-- =============================================================================
-- VALIDATION QUERIES (Run after loading)
-- =============================================================================

SELECT 'stg_users' as table_name, COUNT(*) as row_count FROM stg_users
UNION ALL
SELECT 'stg_accounts', COUNT(*) FROM stg_accounts
UNION ALL
SELECT 'stg_transactions', COUNT(*) FROM stg_transactions
UNION ALL
SELECT 'stg_fees', COUNT(*) FROM stg_fees
UNION ALL
SELECT 'stg_merchants', COUNT(*) FROM stg_merchants
UNION ALL
SELECT 'stg_agencies', COUNT(*) FROM stg_agencies
UNION ALL
SELECT 'stg_agents', COUNT(*) FROM stg_agents
UNION ALL
SELECT 'node_metrics', COUNT(*) FROM node_metrics
ORDER BY table_name;

-- Check for any data quality issues in staging
SELECT 
    'Missing emails' as issue,
    COUNT(*) as count
FROM stg_users
WHERE email IS NULL OR email = ''
UNION ALL
SELECT 'Missing kyc_level', COUNT(*)
FROM stg_users
WHERE kyc_level IS NULL OR kyc_level = ''
UNION ALL
SELECT 'Transactions with CONFLICT', COUNT(*)
FROM stg_transactions
WHERE sync_status = 'CONFLICT'
UNION ALL
SELECT 'Transactions with LAGGING', COUNT(*)
FROM stg_transactions
WHERE sync_status = 'LAGGING'
UNION ALL
SELECT 'Transactions with PENDING', COUNT(*)
FROM stg_transactions
WHERE sync_status = 'PENDING'
ORDER BY issue;
