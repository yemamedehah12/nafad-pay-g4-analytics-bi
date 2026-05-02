{{ config(materialized='table') }}

-- Génère le calendrier 2024 (année bissextile, 366 jours)
WITH series AS (
    SELECT generate_series(
        '2024-01-01'::DATE,
        '2024-12-31'::DATE,
        '1 day'::INTERVAL
    )::DATE AS full_date
)
SELECT
    TO_CHAR(full_date, 'YYYYMMDD')::INT     AS date_key,
    full_date,
    EXTRACT(YEAR    FROM full_date)::SMALLINT AS year,
    EXTRACT(QUARTER FROM full_date)::SMALLINT AS quarter,
    EXTRACT(MONTH   FROM full_date)::SMALLINT AS month,
    TO_CHAR(full_date, 'TMMonth')            AS month_name,
    EXTRACT(WEEK    FROM full_date)::SMALLINT AS week_of_year,
    EXTRACT(DAY     FROM full_date)::SMALLINT AS day_of_month,
    EXTRACT(ISODOW  FROM full_date)::SMALLINT AS day_of_week,
    TO_CHAR(full_date, 'TMDay')              AS day_name,
    EXTRACT(ISODOW  FROM full_date) IN (6,7) AS is_weekend
FROM series
