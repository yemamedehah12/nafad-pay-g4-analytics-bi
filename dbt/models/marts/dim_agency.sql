{{ config(materialized='table') }}

WITH source AS (
    SELECT
        id::BIGINT                              AS agency_id,
        NULLIF(TRIM(code), '')                  AS code,
        NULLIF(TRIM(name), '')                  AS name,
        NULLIF(TRIM(wilaya_id::TEXT), '')::INT  AS wilaya_id,
        NULLIF(TRIM(wilaya_name), '')           AS wilaya_name,
        NULLIF(TRIM(moughataa_id::TEXT),'')::INT AS moughataa_id,
        NULLIF(TRIM(moughataa_name), '')        AS moughataa_name,
        NULLIF(TRIM(tier), '')                  AS tier,
        COALESCE(NULLIF(TRIM(status),''), 'ACTIVE') AS status,
        NULLIF(TRIM(opening_hours), '')         AS opening_hours
    FROM {{ source('raw', 'tmp_agencies') }}
)
SELECT * FROM source
UNION ALL
SELECT -1, NULL, 'Sans agence', NULL, NULL, NULL, NULL, NULL, 'N/A', NULL
