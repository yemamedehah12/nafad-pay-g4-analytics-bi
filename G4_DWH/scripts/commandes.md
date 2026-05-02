Étape 1 — Configurer l'environnement

# Copier le fichier de config

cp .env.example .env

# Ouvrir .env et vérifier que DB_PASSWORD est défini

cat .env

# Vérifier que les CSV sont bien là

ls data/

# Tu dois voir :

# stg_transactions.csv

# stg_users.csv

# stg_merchants.csv

# stg_agencies.csv

# stg_fees.csv

# node_metrics.csv

Étape 2 — Démarrer PostgreSQL
docker-compose up -d postgres_dwh
docker-compose ps

# postgres_dwh doit être "healthy"

Étape 3 — Lancer l'ETL (charger toutes les données)

docker-compose --profile etl run --rm etl

Étape 4 — Démarrer Metabase

docker-compose up -d metabase

# Vérifier les conteneurs actifs

docker-compose ps

# Vérifier le nombre de lignes dans le DWH

docker exec -it nafad*dwh psql -U dwh_user -d dwh -c "
SELECT table_name, COUNT(*)
FROM (
SELECT 'dim*date' AS table_name, COUNT(*) FROM dim*date
UNION ALL SELECT 'dim_user', COUNT(*) FROM dim*user
UNION ALL SELECT 'dim_merchant', COUNT(*) FROM dim*merchant
UNION ALL SELECT 'dim_agency', COUNT(*) FROM dim*agency
UNION ALL SELECT 'dim_node', COUNT(*) FROM dim_node
UNION ALL SELECT 'fact_transactions', COUNT(\*) FROM fact_transactions
) t GROUP BY table_name, count ORDER BY table_name;
"
