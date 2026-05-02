-- ============================================================
-- NAFAD PAY G4 — Chargement des CSV dans les tables staging
-- Note : /data correspond au dossier data/ monté dans Docker
-- ============================================================

\echo 'Chargement stg_users.csv...'
COPY tmp_users FROM '/data/stg_users.csv'
    WITH (FORMAT csv, HEADER true, NULL '');
SELECT COUNT(*) AS nb_users_charges FROM tmp_users;

\echo 'Chargement stg_merchants.csv...'
COPY tmp_merchants FROM '/data/stg_merchants.csv'
    WITH (FORMAT csv, HEADER true, NULL '');
SELECT COUNT(*) AS nb_merchants_charges FROM tmp_merchants;

\echo 'Chargement stg_agencies.csv...'
COPY tmp_agencies FROM '/data/stg_agencies.csv'
    WITH (FORMAT csv, HEADER true, NULL '');
SELECT COUNT(*) AS nb_agencies_charges FROM tmp_agencies;

\echo 'Chargement stg_transactions.csv...'
COPY tmp_transactions FROM '/data/stg_transactions.csv'
    WITH (FORMAT csv, HEADER true, NULL '');
SELECT COUNT(*) AS nb_transactions_chargees FROM tmp_transactions;