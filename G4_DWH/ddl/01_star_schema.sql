-- =============================================================================
-- NAFAD-PAY G4 Data Warehouse - Star Schema
-- Grain: 1 row = 1 transaction
-- =============================================================================

-- Drop existing tables (for development)
-- DROP TABLE IF EXISTS fact_transactions CASCADE;
-- DROP TABLE IF EXISTS dim_date CASCADE;
-- DROP TABLE IF EXISTS dim_user CASCADE;
-- DROP TABLE IF EXISTS dim_merchant CASCADE;
-- DROP TABLE IF EXISTS dim_agency CASCADE;
-- DROP TABLE IF EXISTS dim_agent CASCADE;
-- DROP TABLE IF EXISTS dim_node CASCADE;
-- DROP TABLE IF EXISTS dim_account CASCADE;
-- DROP TABLE IF EXISTS staging_metadata CASCADE;

-- =============================================================================
-- DIMENSION: dim_date
-- =============================================================================
CREATE TABLE IF NOT EXISTS dim_date (
    date_key INT PRIMARY KEY,
    date_value DATE NOT NULL UNIQUE,
    year INT,
    month INT,
    day INT,
    quarter INT,
    week_of_year INT,
    day_of_week INT,
    day_name VARCHAR(10),
    is_weekend BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- DIMENSION: dim_node (Datacenters)
-- Description: Represents the distributed nodes/datacenters
-- =============================================================================
CREATE TABLE IF NOT EXISTS dim_node (
    node_key SERIAL PRIMARY KEY,
    node_id VARCHAR(50) NOT NULL UNIQUE,
    datacenter VARCHAR(50),
    aws_region VARCHAR(50),
    aws_az VARCHAR(50),
    status VARCHAR(20) DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- DIMENSION: dim_user (Type 2 SCD)
-- Description: Users with historical tracking
-- SCD Strategy: Type 2 (track history via effective/end dates)
-- =============================================================================
CREATE TABLE IF NOT EXISTS dim_user (
    user_key BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    phone_number VARCHAR(20),
    nni VARCHAR(20), -- National ID (masked in production BI)
    kyc_level VARCHAR(50), -- LEVEL_0, LEVEL_1, LEVEL_2, LEVEL_3
    wilaya_name VARCHAR(100),
    user_status VARCHAR(50), -- ACTIVE, INACTIVE, SUSPENDED
    account_count INT,
    -- SCD Type 2 fields
    is_current BOOLEAN DEFAULT TRUE,
    effective_date DATE,
    end_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, effective_date)
);
CREATE INDEX idx_dim_user_user_id ON dim_user(user_id);
CREATE INDEX idx_dim_user_is_current ON dim_user(is_current);

-- =============================================================================
-- DIMENSION: dim_merchant
-- Description: Merchants with category and location
-- SCD Strategy: Type 1 (overwrite - business assumption: merchants don't change much)
-- =============================================================================
CREATE TABLE IF NOT EXISTS dim_merchant (
    merchant_key BIGSERIAL PRIMARY KEY,
    merchant_id BIGINT NOT NULL UNIQUE,
    merchant_name VARCHAR(255),
    merchant_category VARCHAR(100),
    wilaya_name VARCHAR(100),
    business_type VARCHAR(50),
    status VARCHAR(20) DEFAULT 'ACTIVE',
    total_transaction_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_dim_merchant_merchant_id ON dim_merchant(merchant_id);
CREATE INDEX idx_dim_merchant_category ON dim_merchant(merchant_category);

-- =============================================================================
-- DIMENSION: dim_agency
-- Description: Agencies (cash-out points)
-- SCD Strategy: Type 1
-- =============================================================================
CREATE TABLE IF NOT EXISTS dim_agency (
    agency_key BIGSERIAL PRIMARY KEY,
    agency_id BIGINT NOT NULL UNIQUE,
    agency_name VARCHAR(255),
    wilaya_name VARCHAR(100),
    float_balance NUMERIC(18,2),
    tier VARCHAR(50), -- TIER_1, TIER_2, TIER_3
    license_number VARCHAR(100),
    status VARCHAR(20) DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_dim_agency_agency_id ON dim_agency(agency_id);
CREATE INDEX idx_dim_agency_wilaya ON dim_agency(wilaya_name);

-- =============================================================================
-- DIMENSION: dim_agent
-- Description: Agents working at agencies
-- =============================================================================
CREATE TABLE IF NOT EXISTS dim_agent (
    agent_key BIGSERIAL PRIMARY KEY,
    agent_id BIGINT NOT NULL UNIQUE,
    agent_name VARCHAR(255),
    agency_key BIGINT REFERENCES dim_agency(agency_key),
    agency_id BIGINT,
    status VARCHAR(20) DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_dim_agent_agency ON dim_agent(agency_key);

-- =============================================================================
-- DIMENSION: dim_account
-- Description: Bank accounts
-- =============================================================================
CREATE TABLE IF NOT EXISTS dim_account (
    account_key BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL UNIQUE,
    user_key BIGINT REFERENCES dim_user(user_key),
    user_id BIGINT,
    account_type VARCHAR(50),
    account_status VARCHAR(20),
    balance NUMERIC(18,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_dim_account_account_id ON dim_account(account_id);
CREATE INDEX idx_dim_account_user ON dim_account(user_id);

-- =============================================================================
-- FACT TABLE: fact_transactions
-- Grain: 1 row = 1 transaction
-- Description: All transactions with multi-node tracking
-- =============================================================================
CREATE TABLE IF NOT EXISTS fact_transactions (
    tx_pk BIGSERIAL PRIMARY KEY,
    
    -- Natural Keys
    transaction_id BIGINT NOT NULL UNIQUE,
    idempotency_key VARCHAR(255),
    
    -- Dimension Keys
    date_key INT REFERENCES dim_date(date_key),
    source_user_key BIGINT REFERENCES dim_user(user_key),
    destination_user_key BIGINT REFERENCES dim_user(user_key),
    source_account_key BIGINT REFERENCES dim_account(account_key),
    destination_account_key BIGINT REFERENCES dim_account(account_key),
    merchant_key BIGINT REFERENCES dim_merchant(merchant_key),
    agency_key BIGINT REFERENCES dim_agency(agency_key),
    agent_key BIGINT REFERENCES dim_agent(agent_key),
    node_key INT REFERENCES dim_node(node_key),
    
    -- Transaction Details
    transaction_type VARCHAR(50),
    amount NUMERIC(18,2),
    fee NUMERIC(18,2),
    total_amount NUMERIC(18,2),
    
    -- Transaction Status
    status VARCHAR(50), -- SUCCESS, FAILED, PENDING
    failure_reason VARCHAR(255),
    
    -- Balance Info
    balance_before NUMERIC(18,2),
    balance_after NUMERIC(18,2),
    
    -- Multi-node Tracking (CRITICAL for anomaly handling)
    sync_status VARCHAR(50), -- SYNCED, CONFLICT, LAGGING, PENDING
    amount_node_a NUMERIC(18,2),
    amount_node_b NUMERIC(18,2),
    last_synced_at TIMESTAMP,
    data_source_node_a BOOLEAN, -- TRUE if amount taken from node A
    data_source_node_b BOOLEAN, -- TRUE if amount taken from node B
    
    -- Risk & Security
    risk_score DECIMAL(5,2),
    
    -- Device & Channel Info
    channel VARCHAR(50), -- USSD, MOBILE_APP, WEB, API
    device_type VARCHAR(50),
    ip_address VARCHAR(50),
    
    -- Time Tracking
    transaction_date DATE,
    transaction_time TIME,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    completed_at TIMESTAMP,
    
    -- Flags
    is_cross_dc BOOLEAN DEFAULT FALSE, -- Transaction crosses datacenters
    is_conflict BOOLEAN DEFAULT FALSE, -- Syncing conflict
    data_quality_flag VARCHAR(100) DEFAULT NULL, -- Data quality notes
    
    created_at_dwh TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for Performance
CREATE INDEX idx_fact_tx_transaction_id ON fact_transactions(transaction_id);
CREATE INDEX idx_fact_tx_date_key ON fact_transactions(date_key);
CREATE INDEX idx_fact_tx_source_user ON fact_transactions(source_user_key);
CREATE INDEX idx_fact_tx_merchant ON fact_transactions(merchant_key);
CREATE INDEX idx_fact_tx_sync_status ON fact_transactions(sync_status);
CREATE INDEX idx_fact_tx_transaction_date ON fact_transactions(transaction_date);
CREATE INDEX idx_fact_tx_node ON fact_transactions(node_key);
CREATE INDEX idx_fact_tx_status ON fact_transactions(status);

-- =============================================================================
-- STAGING METADATA TABLE (for audit & data lineage)
-- =============================================================================
CREATE TABLE IF NOT EXISTS staging_metadata (
    metadata_id BIGSERIAL PRIMARY KEY,
    stage_name VARCHAR(100),
    total_records_processed INT,
    total_records_loaded INT,
    total_records_rejected INT,
    rejected_reasons TEXT,
    data_quality_issues TEXT,
    load_date DATE,
    load_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);

-- =============================================================================
-- Views for BI Tools (with PII masking for junior analysts)
-- =============================================================================

-- View with PII masking
CREATE OR REPLACE VIEW vw_fact_transactions_masked AS
SELECT 
    tx_pk,
    transaction_id,
    date_key,
    source_user_key,
    destination_user_key,
    source_account_key,
    destination_account_key,
    merchant_key,
    agency_key,
    node_key,
    transaction_type,
    amount,
    fee,
    total_amount,
    status,
    sync_status,
    risk_score,
    channel,
    transaction_date,
    created_at_dwh
FROM fact_transactions;

-- Materialized view for common aggregations (optional for performance)
-- Can be refreshed nightly
-- CREATE MATERIALIZED VIEW mv_daily_metrics AS
-- SELECT 
--     date_key,
--     SUM(amount) as total_amount,
--     COUNT(*) as transaction_count,
--     COUNT(DISTINCT source_user_key) as unique_users,
--     AVG(amount) as avg_transaction_amount
-- FROM fact_transactions
-- GROUP BY date_key;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO analyst_role;
