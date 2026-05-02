-- ============================================================
-- NAFAD PAY G4 — Peuplement dim_user
-- ============================================================

\echo 'Peuplement dim_user...'

INSERT INTO dim_user (
    user_id, nni, full_name, gender, phone, email,
    wilaya_id, wilaya_name, moughataa_id, moughataa_name,
    profile_type, kyc_level, status, device_type,
    registration_date, effective_from, effective_to, is_current
)
SELECT
    id,
    NULLIF(TRIM(nni), ''),
    NULLIF(TRIM(full_name), ''),
    NULLIF(TRIM(gender), ''),
    NULLIF(TRIM(phone), ''),
    NULLIF(TRIM(email), ''),
    wilaya_id,
    NULLIF(TRIM(wilaya_name), ''),
    moughataa_id,
    NULLIF(TRIM(moughataa_name), ''),   -- 100% vide dans les données
    NULLIF(TRIM(profile_type), ''),
    NULLIF(TRIM(kyc_level), ''),        -- 100% vide dans les données
    NULLIF(TRIM(status), ''),
    NULLIF(TRIM(device_type), ''),
    CASE WHEN TRIM(registration_date) = ''
         THEN NULL
         ELSE TRIM(registration_date)::DATE
    END,
    CURRENT_DATE,   -- effective_from
    NULL,           -- effective_to NULL = actif
    TRUE            -- is_current
FROM tmp_users;

SELECT COUNT(*) AS nb_users FROM dim_user;
-- Attendu : 10 000