{% snapshot snap_dim_user %}

{{
  config(
    target_schema='snapshots',
    strategy='check',
    unique_key='user_id',
    check_cols=[
      'wilaya_id',
      'wilaya_name',
      'kyc_level',
      'status',
      'profile_type',
      'device_type',
      'phone',
      'email'
    ],
    invalidate_hard_deletes=True
  )
}}

/*
  SCD Type 2 via dbt snapshot.
  Chaque run quotidien détecte les changements sur les colonnes surveillées
  et crée une nouvelle ligne avec dbt_valid_from / dbt_valid_to.

  En production : exécuter après le chargement des CSV Gold (G3→G4).
  Commande : dbt snapshot --select snap_dim_user
*/

SELECT
    id::BIGINT                                  AS user_id,
    NULLIF(TRIM(nni), '')                       AS nni,
    NULLIF(TRIM(full_name), '')                 AS full_name,
    NULLIF(TRIM(gender), '')                    AS gender,
    NULLIF(TRIM(phone), '')                     AS phone,
    NULLIF(TRIM(email), '')                     AS email,
    NULLIF(TRIM(wilaya_id::TEXT), '')::INT      AS wilaya_id,
    NULLIF(TRIM(wilaya_name), '')               AS wilaya_name,
    COALESCE(NULLIF(TRIM(kyc_level), ''), 'LEVEL_0') AS kyc_level,
    COALESCE(NULLIF(TRIM(status), ''), 'ACTIVE')     AS status,
    NULLIF(TRIM(profile_type), '')              AS profile_type,
    NULLIF(TRIM(device_type), '')               AS device_type,
    registration_date::DATE                     AS registration_date
FROM {{ source('raw', 'tmp_users') }}

{% endsnapshot %}
