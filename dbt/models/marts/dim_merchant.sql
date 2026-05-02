{{ config(materialized='table') }}

WITH source AS (
    SELECT
        id::BIGINT                              AS merchant_id,
        NULLIF(TRIM(code), '')                  AS code,
        NULLIF(TRIM(name), '')                  AS name,
        NULLIF(TRIM(category_code), '')         AS category_code,
        NULLIF(TRIM(category_label), '')        AS category_label,
        NULLIF(TRIM(mcc), '')                   AS mcc,
        NULLIF(TRIM(wilaya_id::TEXT), '')::INT  AS wilaya_id,
        NULLIF(TRIM(wilaya_name), '')           AS wilaya_name,
        NULLIF(TRIM(moughataa_id::TEXT),'')::INT AS moughataa_id,
        NULLIF(TRIM(moughataa_name), '')        AS moughataa_name,
        CASE WHEN TRIM(COALESCE(commission_rate,''))='' THEN NULL
             ELSE TRIM(commission_rate)::NUMERIC(5,4) END AS commission_rate,
        COALESCE(NULLIF(TRIM(status),''), 'ACTIVE') AS status,
        CASE WHEN TRIM(COALESCE(registration_date::TEXT,''))='' THEN NULL
             ELSE registration_date::DATE END   AS registration_date
    FROM {{ source('raw', 'tmp_merchants') }}
),
dummy AS (
    SELECT -1::BIGINT, NULL, 'Sans marchand', NULL, NULL, NULL,
           NULL, NULL, NULL, NULL, NULL, 'N/A'::VARCHAR, NULL
)
SELECT * FROM source
UNION ALL
SELECT -1, NULL, 'Sans marchand', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'N/A', NULL
