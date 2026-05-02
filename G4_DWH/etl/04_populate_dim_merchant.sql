-- ============================================================
-- NAFAD PAY G4 — Peuplement dim_merchant
-- ============================================================

\echo 'Peuplement dim_merchant...'

INSERT INTO dim_merchant (
    merchant_id, code, name,
    category_code, category_label, mcc,
    wilaya_id, wilaya_name,
    moughataa_id, moughataa_name,
    commission_rate, status, registration_date
)
SELECT
    id,
    NULLIF(TRIM(code), ''),
    NULLIF(TRIM(name), ''),
    NULLIF(TRIM(category_code), ''),
    NULLIF(TRIM(category_label), ''),
    NULLIF(TRIM(mcc), ''),
    wilaya_id,
    NULLIF(TRIM(wilaya_name), ''),
    moughataa_id,
    NULLIF(TRIM(moughataa_name), ''),
    CASE WHEN TRIM(commission_rate) = ''
         THEN NULL
         ELSE TRIM(commission_rate)::NUMERIC
    END,
    NULLIF(TRIM(status), ''),
    CASE WHEN TRIM(registration_date) = ''
         THEN NULL
         ELSE TRIM(registration_date)::DATE
    END
FROM tmp_merchants;

SELECT COUNT(*) AS nb_merchants FROM dim_merchant;
-- Attendu : 501 (500 marchands + la ligne -1)