{{ config(materialized='view') }}

SELECT
    id::BIGINT                                      AS user_id,
    NULLIF(TRIM(nni), '')                           AS nni,
    NULLIF(TRIM(full_name), '')                     AS full_name,
    NULLIF(TRIM(gender), '')                        AS gender,
    NULLIF(TRIM(phone), '')                         AS phone,
    NULLIF(TRIM(email), '')                         AS email,
    NULLIF(TRIM(wilaya_id::TEXT), '')::INT          AS wilaya_id,
    NULLIF(TRIM(wilaya_name), '')                   AS wilaya_name,
    NULLIF(TRIM(moughataa_id::TEXT), '')::INT       AS moughataa_id,
    COALESCE(NULLIF(TRIM(moughataa_name),''), 'UNKNOWN') AS moughataa_name,
    NULLIF(TRIM(profile_type), '')                  AS profile_type,
    COALESCE(NULLIF(TRIM(kyc_level), ''), 'LEVEL_0') AS kyc_level,
    COALESCE(NULLIF(TRIM(status), ''), 'ACTIVE')    AS status,
    NULLIF(TRIM(device_type), '')                   AS device_type,
    CASE WHEN TRIM(COALESCE(registration_date::TEXT,''))='' THEN NULL
         ELSE registration_date::DATE END           AS registration_date
FROM {{ source('raw', 'tmp_users') }}
