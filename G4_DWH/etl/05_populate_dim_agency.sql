-- ============================================================
-- NAFAD PAY G4 — Peuplement dim_agency
-- Auteur : Oumlvadli
-- ============================================================

\echo 'Peuplement dim_agency...'

INSERT INTO dim_agency (
    agency_id, code, name,
    wilaya_id, wilaya_name,
    moughataa_id, moughataa_name,
    tier, status, opening_hours
)
SELECT
    id,
    NULLIF(TRIM(code), ''),
    NULLIF(TRIM(name), ''),
    wilaya_id,
    NULLIF(TRIM(wilaya_name), ''),
    moughataa_id,
    NULLIF(TRIM(moughataa_name), ''),
    NULLIF(TRIM(tier), ''),
    NULLIF(TRIM(status), ''),
    NULLIF(TRIM(opening_hours), '')
FROM tmp_agencies;

SELECT COUNT(*) AS nb_agencies FROM dim_agency;
-- Attendu : 101 (100 agences + la ligne -1)