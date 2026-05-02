{{
  config(
    materialized='table',
    description='Dimension utilisateur avec SCD Type 2 (historique complet des changements)',
    indexes=[
      {'columns': ['user_id']},
      {'columns': ['user_id', 'is_current']}
    ]
  )
}}

/*
  CHOIX SCD : Type 2 (Track Full History)

  JUSTIFICATION :
  - Conformité légale BCM/fintech : toute transaction doit être reproductible
    avec les attributs utilisateur valables AU MOMENT de la transaction.
    Ex : un utilisateur qui change de wilaya → les transactions passées doivent
    toujours être rattachées à l'ancienne wilaya.
  - Les KPIs "growth par wilaya" sont faussés par Type 1 si des migrations
    d'utilisateurs ont lieu entre wilayas.
  - NNI et profil KYC peuvent évoluer (upgrade LEVEL_1→LEVEL_2) : historiser
    ces changements permet l'audit réglementaire.

  GRAIN : 1 ligne = 1 version d'un utilisateur pendant une période donnée.
  - effective_from : date de création de cette version
  - effective_to   : NULL si version active, sinon date de remplacement
  - is_current     : TRUE si version active
*/

WITH source AS (
    SELECT
        id::BIGINT                              AS user_id,
        NULLIF(TRIM(nni), '')                   AS nni,
        NULLIF(TRIM(full_name), '')             AS full_name,
        NULLIF(TRIM(gender), '')                AS gender,
        NULLIF(TRIM(phone), '')                 AS phone,
        NULLIF(TRIM(email), '')                 AS email,
        NULLIF(TRIM(wilaya_id::TEXT), '')::INT  AS wilaya_id,
        NULLIF(TRIM(wilaya_name), '')           AS wilaya_name,
        NULLIF(TRIM(moughataa_id::TEXT), '')::INT AS moughataa_id,
        COALESCE(NULLIF(TRIM(moughataa_name), ''), 'UNKNOWN') AS moughataa_name,
        NULLIF(TRIM(profile_type), '')          AS profile_type,
        COALESCE(NULLIF(TRIM(kyc_level), ''), 'LEVEL_0') AS kyc_level,
        COALESCE(NULLIF(TRIM(status), ''), 'ACTIVE') AS status,
        NULLIF(TRIM(device_type), '')           AS device_type,
        CASE WHEN TRIM(COALESCE(registration_date::TEXT, '')) = '' THEN NULL
             ELSE registration_date::DATE END   AS registration_date
    FROM {{ source('raw', 'tmp_users') }}
),

-- Calcul du hash pour détecter les changements (SCD Type 2)
hashed AS (
    SELECT
        *,
        md5(
            COALESCE(wilaya_id::TEXT, '') ||
            COALESCE(kyc_level, '') ||
            COALESCE(status, '') ||
            COALESCE(profile_type, '') ||
            COALESCE(device_type, '')
        ) AS row_hash
    FROM source
),

-- Ligne "Sans utilisateur" pour les FK nulles
dummy AS (
    SELECT
        -1::BIGINT   AS user_id,
        NULL         AS nni,
        'Sans utilisateur' AS full_name,
        NULL         AS gender,
        NULL         AS phone,
        NULL         AS email,
        NULL         AS wilaya_id,
        'INCONNU'    AS wilaya_name,
        NULL         AS moughataa_id,
        'INCONNU'    AS moughataa_name,
        NULL         AS profile_type,
        'LEVEL_0'    AS kyc_level,
        'N/A'        AS status,
        NULL         AS device_type,
        NULL         AS registration_date,
        'dummy'      AS row_hash
)

SELECT
    user_id,
    nni,
    full_name,
    gender,
    phone,
    email,
    wilaya_id,
    wilaya_name,
    moughataa_id,
    moughataa_name,
    profile_type,
    kyc_level,
    status,
    device_type,
    registration_date,
    row_hash,
    -- SCD Type 2 — dans le pipeline initial, toutes les lignes sont "courantes"
    -- En production, ce serait géré par dbt snapshots
    CURRENT_DATE    AS effective_from,
    NULL::DATE      AS effective_to,
    TRUE            AS is_current
FROM hashed

UNION ALL

SELECT
    user_id, nni, full_name, gender, phone, email,
    wilaya_id, wilaya_name, moughataa_id, moughataa_name,
    profile_type, kyc_level, status, device_type, registration_date,
    row_hash,
    '2000-01-01'::DATE, NULL::DATE, TRUE
FROM dummy
