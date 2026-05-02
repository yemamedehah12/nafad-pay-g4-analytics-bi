-- ============================================================
-- NAFAD PAY G4 — Star Schema DDL
-- Description : Data Warehouse analytique pour NAFAD PAY
-- ============================================================

-- Supprimer les tables si elles existent déjà (pour pouvoir relancer)
DROP TABLE IF EXISTS fact_transactions CASCADE;
DROP TABLE IF EXISTS dim_date CASCADE;
DROP TABLE IF EXISTS dim_user CASCADE;
DROP TABLE IF EXISTS dim_merchant CASCADE;
DROP TABLE IF EXISTS dim_agency CASCADE;
DROP TABLE IF EXISTS dim_node CASCADE;

-- ============================================================
-- DIMENSION 1 : dim_date
-- ============================================================
CREATE TABLE dim_date (
    date_key        INT PRIMARY KEY,        -- format YYYYMMDD ex: 20240115
    full_date       DATE NOT NULL,
    year            SMALLINT NOT NULL,
    quarter         SMALLINT NOT NULL,      -- 1 à 4
    month           SMALLINT NOT NULL,      -- 1 à 12
    month_name      VARCHAR(20),
    week_of_year    SMALLINT NOT NULL,
    day_of_month    SMALLINT NOT NULL,
    day_of_week     SMALLINT NOT NULL,      -- 1=Lundi, 7=Dimanche
    day_name        VARCHAR(20),
    is_weekend      BOOLEAN NOT NULL DEFAULT FALSE
);

-- ============================================================
-- DIMENSION 2 : dim_user
-- ============================================================
CREATE TABLE dim_user (
    user_key            BIGSERIAL PRIMARY KEY,  -- clé surrogate DWH
    user_id             BIGINT NOT NULL,         -- clé naturelle du CSV
    nni                 VARCHAR(20),
    full_name           VARCHAR(200),
    gender              VARCHAR(10),
    phone               VARCHAR(30),
    email               VARCHAR(200),
    wilaya_id           INT,
    wilaya_name         VARCHAR(100),
    moughataa_id        INT,
    moughataa_name      VARCHAR(100),
    profile_type        VARCHAR(50),
    kyc_level           VARCHAR(20),
    status              VARCHAR(20),
    device_type         VARCHAR(50),
    registration_date   DATE,
    -- Colonnes SCD Type 2 (historique des changements)
    effective_from      DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_to        DATE,               -- NULL = enregistrement actif
    is_current          BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_dim_user_id      ON dim_user(user_id);
CREATE INDEX idx_dim_user_current ON dim_user(user_id, is_current);

-- ============================================================
-- DIMENSION 3 : dim_merchant
-- ============================================================
CREATE TABLE dim_merchant (
    merchant_key        BIGSERIAL PRIMARY KEY,
    merchant_id         BIGINT NOT NULL,
    code                VARCHAR(20),
    name                VARCHAR(200),
    category_code       VARCHAR(10),
    category_label      VARCHAR(100),
    mcc                 VARCHAR(10),
    wilaya_id           INT,
    wilaya_name         VARCHAR(100),
    moughataa_id        INT,
    moughataa_name      VARCHAR(100),
    commission_rate     NUMERIC(5,4),
    status              VARCHAR(20),
    registration_date   DATE
);

-- Ligne spéciale pour les transactions sans marchand
INSERT INTO dim_merchant
    (merchant_key, merchant_id, name, status)
VALUES
    (-1, -1, 'Sans marchand', 'N/A');

CREATE INDEX idx_dim_merchant_id ON dim_merchant(merchant_id);

-- ============================================================
-- DIMENSION 4 : dim_agency
-- ============================================================
CREATE TABLE dim_agency (
    agency_key      BIGSERIAL PRIMARY KEY,
    agency_id       BIGINT NOT NULL,
    code            VARCHAR(20),
    name            VARCHAR(200),
    wilaya_id       INT,
    wilaya_name     VARCHAR(100),
    moughataa_id    INT,
    moughataa_name  VARCHAR(100),
    tier            VARCHAR(20),
    status          VARCHAR(20),
    opening_hours   VARCHAR(100)
);

-- Ligne spéciale pour les transactions sans agence
INSERT INTO dim_agency
    (agency_key, agency_id, name, status)
VALUES
    (-1, -1, 'Sans agence', 'N/A');

CREATE INDEX idx_dim_agency_id ON dim_agency(agency_id);

-- ============================================================
-- DIMENSION 5 : dim_node
-- ============================================================
CREATE TABLE dim_node (
    node_key    SERIAL PRIMARY KEY,
    node_id     VARCHAR(50) NOT NULL UNIQUE,
    datacenter  VARCHAR(50) NOT NULL,
    aws_az      VARCHAR(30),
    aws_region  VARCHAR(30) DEFAULT 'eu-west-3'
);

-- Les 5 noeuds réels du fichier node_metrics.csv
INSERT INTO dim_node (node_id, datacenter, aws_az) VALUES
    ('NDB-NODE-1',  'DC-NDB',           'eu-west-3c'),
    ('NDB-NODE-2',  'DC-NDB',           'eu-west-3c'),
    ('NKC-NODE-1',  'DC-NKC-PRIMARY',   'eu-west-3a'),
    ('NKC-NODE-2',  'DC-NKC-PRIMARY',   'eu-west-3a'),
    ('NKC-NODE-3',  'DC-NKC-SECONDARY', 'eu-west-3b');

-- ============================================================
-- TABLE DE FAITS : fact_transactions (table centrale)
-- ============================================================
CREATE TABLE fact_transactions (
    tx_pk               BIGSERIAL PRIMARY KEY,
    transaction_id      BIGINT NOT NULL UNIQUE,
    reference           VARCHAR(100),
    idempotency_key     VARCHAR(200),

    -- Clés étrangères vers les dimensions
    date_key            INT NOT NULL
                            REFERENCES dim_date(date_key),
    user_key            BIGINT NOT NULL
                            REFERENCES dim_user(user_key),
    merchant_key        BIGINT NOT NULL DEFAULT -1
                            REFERENCES dim_merchant(merchant_key),
    agency_key          BIGINT NOT NULL DEFAULT -1
                            REFERENCES dim_agency(agency_key),
    node_key            INT NOT NULL
                            REFERENCES dim_node(node_key),

    -- Mesures financières
    amount              NUMERIC(18,2) NOT NULL,
    fee                 NUMERIC(18,2) DEFAULT 0,
    total_amount        NUMERIC(18,2),
    balance_before      NUMERIC(18,2),
    balance_after       NUMERIC(18,2),
    risk_score          NUMERIC(5,2),

    -- Attributs descriptifs
    transaction_type    VARCHAR(10) NOT NULL,
    status              VARCHAR(20) NOT NULL,
    failure_reason      VARCHAR(500),
    channel             VARCHAR(30),
    device_type         VARCHAR(50),

    -- Flags qualité / synchronisation
    sync_status         VARCHAR(20),
    is_conflict         BOOLEAN DEFAULT FALSE,
    is_lagging          BOOLEAN DEFAULT FALSE,
    is_pending_sync     BOOLEAN DEFAULT FALSE,
    is_cross_dc         BOOLEAN DEFAULT FALSE,

    -- Timestamps
    transaction_date    DATE NOT NULL,
    transaction_time    TIME,
    created_at          TIMESTAMP,
    completed_at        TIMESTAMP
);

-- Index pour accélérer les requêtes analytiques
CREATE INDEX idx_fact_date        ON fact_transactions(date_key);
CREATE INDEX idx_fact_user        ON fact_transactions(user_key);
CREATE INDEX idx_fact_status      ON fact_transactions(status);
CREATE INDEX idx_fact_sync        ON fact_transactions(sync_status);
CREATE INDEX idx_fact_type        ON fact_transactions(transaction_type);
CREATE INDEX idx_fact_merchant    ON fact_transactions(merchant_key);
CREATE INDEX idx_fact_date_status ON fact_transactions(date_key, status);