-- ============================================================
-- NAFAD PAY G4 — Peuplement dim_date
-- ============================================================

\echo 'Peuplement dim_date...'

INSERT INTO dim_date (
    date_key, full_date, year, quarter, month, month_name,
    week_of_year, day_of_month, day_of_week, day_name, is_weekend
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT         AS date_key,
    d                                    AS full_date,
    EXTRACT(YEAR FROM d)::SMALLINT       AS year,
    EXTRACT(QUARTER FROM d)::SMALLINT    AS quarter,
    EXTRACT(MONTH FROM d)::SMALLINT      AS month,
    TO_CHAR(d, 'TMMonth')                AS month_name,
    EXTRACT(WEEK FROM d)::SMALLINT       AS week_of_year,
    EXTRACT(DAY FROM d)::SMALLINT        AS day_of_month,
    EXTRACT(ISODOW FROM d)::SMALLINT     AS day_of_week,
    TO_CHAR(d, 'TMDay')                  AS day_name,
    EXTRACT(ISODOW FROM d) IN (6,7)      AS is_weekend
FROM generate_series(
    '2024-01-01'::DATE,
    '2024-12-31'::DATE,
    '1 day'::INTERVAL
) AS t(d)
ON CONFLICT (date_key) DO NOTHING;

SELECT COUNT(*) AS nb_dates FROM dim_date;
-- Attendu : 366 (2024 est bissextile)