-- ============================================================
-- NAFAD PAY G4 — Sécurité PII + Row-Level Security
-- Contexte : 10 000 utilisateurs, données sensibles NNI/phone/email
-- ============================================================

-- ============================================================
-- 1. VUES DE MASQUAGE PII (Column-Level Security)
-- Analogue au Redshift Dynamic Data Masking en local PostgreSQL
-- ============================================================

-- Vue pour les ANALYSTES JUNIORS (phone/nni/email masqués)
CREATE OR REPLACE VIEW v_dim_user_masked AS
SELECT
    user_key,
    user_id,
    -- NNI partiellement masqué : 10 chiffres → '****' + 6 derniers
    CASE
        WHEN current_user = 'dwh_analyst_junior'
            THEN REGEXP_REPLACE(COALESCE(nni, ''), '.{4}', '****', 1, 1)
        ELSE nni
    END                             AS nni,
    full_name,
    gender,
    -- Phone masqué : +222 XX XXX → +222 ****XX
    CASE
        WHEN current_user = 'dwh_analyst_junior'
            THEN REGEXP_REPLACE(COALESCE(phone, ''), '(\+\d{3})\d+(\d{4})', '\1****\2')
        ELSE phone
    END                             AS phone,
    -- Email masqué : user@domain.com → u***@domain.com
    CASE
        WHEN current_user = 'dwh_analyst_junior'
            THEN REGEXP_REPLACE(COALESCE(email, ''), '^(.).+(@.+)$', '\1***\2')
        ELSE email
    END                             AS email,
    wilaya_id,
    wilaya_name,
    moughataa_id,
    moughataa_name,
    profile_type,
    kyc_level,
    status,
    device_type,
    registration_date,
    effective_from,
    effective_to,
    is_current
FROM dim_user;

-- ============================================================
-- 2. ROW-LEVEL SECURITY (RLS)
-- Chef d'agence → voit uniquement sa wilaya
-- Analyste DWH → voit tout
-- DG → voit tout
-- ============================================================

-- Activer RLS sur la vue matérialisée des transactions
ALTER TABLE mv_daily_kpis ENABLE ROW LEVEL SECURITY;
ALTER TABLE mv_daily_kpis FORCE ROW LEVEL SECURITY;

-- Politique : analyste voit toutes les wilayas
CREATE POLICY policy_all_wilayas ON mv_daily_kpis
    AS PERMISSIVE
    FOR SELECT
    TO dwh_analyst_senior, dwh_admin, dwh_dg
    USING (TRUE);

-- Politique : chef d'agence voit uniquement sa wilaya
-- La wilaya est stockée dans une table de mapping IAM→wilaya
CREATE TABLE IF NOT EXISTS user_wilaya_access (
    db_username VARCHAR(50) PRIMARY KEY,
    wilaya_id   INT NOT NULL,
    wilaya_name VARCHAR(100)
);

CREATE POLICY policy_wilaya_restricted ON mv_daily_kpis
    AS PERMISSIVE
    FOR SELECT
    TO dwh_chef_agence
    USING (
        wilaya_id = (
            SELECT wilaya_id
            FROM user_wilaya_access
            WHERE db_username = current_user
        )
    );

-- Exemple de mapping chef d'agence (à gérer via IAM en production AWS)
-- INSERT INTO user_wilaya_access VALUES ('chef_agence_nkc', 1, 'Nouakchott-Nord');
-- INSERT INTO user_wilaya_access VALUES ('chef_agence_ndb', 5, 'Dakhlet Nouadhibou');

-- RLS sur la table de faits principale
ALTER TABLE fact_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE fact_transactions FORCE ROW LEVEL SECURITY;

-- Admins et analystes seniors voient tout
CREATE POLICY policy_fact_all ON fact_transactions
    AS PERMISSIVE FOR SELECT
    TO dwh_admin, dwh_analyst_senior, dwh_dg
    USING (TRUE);

-- Chefs d'agence : uniquement leurs transactions (via wilaya user)
CREATE POLICY policy_fact_wilaya ON fact_transactions
    AS PERMISSIVE FOR SELECT
    TO dwh_chef_agence
    USING (
        user_key IN (
            SELECT u.user_key
            FROM dim_user u
            JOIN user_wilaya_access a ON u.wilaya_id = a.wilaya_id
            WHERE a.db_username = current_user
              AND u.is_current = TRUE
        )
    );

-- ============================================================
-- 3. RÔLES ET COMPTES (principe moindre privilège)
-- JAMAIS de compte partagé — 1 service = 1 rôle
-- ============================================================

-- Créer les rôles (à adapter selon droits DB)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dwh_admin') THEN
        CREATE ROLE dwh_admin LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dwh_analyst_senior') THEN
        CREATE ROLE dwh_analyst_senior LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dwh_analyst_junior') THEN
        CREATE ROLE dwh_analyst_junior LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dwh_chef_agence') THEN
        CREATE ROLE dwh_chef_agence LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dwh_dg') THEN
        CREATE ROLE dwh_dg LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'etl_loader') THEN
        CREATE ROLE etl_loader LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'superset_reader') THEN
        CREATE ROLE superset_reader LOGIN;
    END IF;
END
$$;

-- Droits par rôle
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dwh_analyst_senior;
GRANT SELECT ON v_dim_user_masked TO dwh_analyst_junior;
GRANT SELECT ON mv_daily_kpis, mv_agency_performance, mv_merchant_performance TO dwh_analyst_junior;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dwh_dg;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO dwh_admin;
GRANT INSERT, UPDATE ON fact_transactions, dim_user, dim_merchant, dim_agency TO etl_loader;
GRANT SELECT ON mv_daily_kpis, mv_agency_performance, mv_merchant_performance, mv_user_retention,
               mv_merchant_performance, v_dim_user_masked TO superset_reader;

-- Révoquer tout accès direct à la table users (données PII brutes)
REVOKE ALL ON dim_user FROM dwh_analyst_junior;
-- Accès uniquement via la vue masquée
GRANT SELECT ON v_dim_user_masked TO dwh_analyst_junior;

-- ============================================================
-- 4. AUDIT LOG TABLE (complément à CloudTrail en prod)
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_query_log (
    log_id          BIGSERIAL PRIMARY KEY,
    username        VARCHAR(50) NOT NULL DEFAULT current_user,
    query_start     TIMESTAMP NOT NULL DEFAULT NOW(),
    query_text      TEXT,
    table_accessed  VARCHAR(100),
    rows_returned   BIGINT,
    duration_ms     INTEGER
);

-- En prod AWS Redshift : STL_QUERY + CloudTrail + CloudWatch remplacent ce log
-- Sur PostgreSQL local : pgaudit extension
-- ALTER SYSTEM SET pgaudit.log = 'read,write';

-- ============================================================
-- 5. VUE DE CONFORMITÉ PII (audit Macie-like en local)
-- Identifier les colonnes sensibles
-- ============================================================
CREATE OR REPLACE VIEW v_pii_inventory AS
SELECT
    'dim_user'      AS table_name,
    'nni'           AS column_name,
    'IDENTIFIANT_NATIONAL' AS pii_type,
    'HIGH'          AS sensitivity,
    COUNT(*)        AS non_null_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM dim_user WHERE is_current=TRUE), 1) AS completeness_pct
FROM dim_user WHERE is_current = TRUE AND nni IS NOT NULL
UNION ALL
SELECT 'dim_user', 'phone', 'NUMERO_TELEPHONE', 'HIGH',
    COUNT(*), ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM dim_user WHERE is_current=TRUE),1)
FROM dim_user WHERE is_current = TRUE AND phone IS NOT NULL
UNION ALL
SELECT 'dim_user', 'email', 'ADRESSE_EMAIL', 'MEDIUM',
    COUNT(*), ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM dim_user WHERE is_current=TRUE),1)
FROM dim_user WHERE is_current = TRUE AND email IS NOT NULL
UNION ALL
SELECT 'dim_user', 'full_name', 'NOM_COMPLET', 'MEDIUM',
    COUNT(*), ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM dim_user WHERE is_current=TRUE),1)
FROM dim_user WHERE is_current = TRUE AND full_name IS NOT NULL;
