# Quick Start Guide - G4 DWH Setup

**Objectif** : Lancer le DWH en 30 minutes et valider les données

---

## Step 1: Lancer PostgreSQL avec Docker

```powershell
cd G4_DWH

# Démarrer le conteneur PostgreSQL
docker-compose up -d postgres_dwh

# Vérifier que c'est up
docker-compose ps

# Logs (optionnel)
docker-compose logs postgres_dwh
```

**Expected output** :

```
CONTAINER ID   IMAGE              STATUS
xxx            postgres:16-alpine  Up 2 minutes (healthy)
```

---

## Step 2: Charger les données Staging (stg\_\*.csv)

Connectez-vous à PostgreSQL et créez les tables staging :

```powershell
# Option 1: Via psql (si installé localement)
psql -h localhost -U dwh_user -d dwh_nafad_pay < ddl/01_staging.sql

# Option 2: Via Docker
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay < ddl/01_staging.sql
```

Créez un script SQL pour charger les CSV (à créer dans `ddl/01_staging.sql`) :

```sql
COPY stg_users FROM '/staging/stg_users.csv' CSV HEADER;
COPY stg_accounts FROM '/staging/stg_accounts.csv' CSV HEADER;
COPY stg_transactions FROM '/staging/stg_transactions.csv' CSV HEADER;
-- ...
```

---

## Step 3: Créer le Star Schema (DDL)

```powershell
# Charger la DDL
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay < ddl/01_star_schema.sql

# Vérifier
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay -c "
  SELECT table_name
  FROM information_schema.tables
  WHERE table_schema = 'public'
  ORDER BY table_name;
"
```

**Expected tables** :

- dim_date, dim_node, dim_user, dim_merchant, dim_agency, dim_agent, dim_account
- fact_transactions
- staging_metadata

---

## Step 4: Exécuter l'ETL (Transform Staging → DWH)

```powershell
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay < etl/02_load_star_schema.sql
```

**Vérifier l'ETL** :

```sql
-- Check row counts
SELECT 'fact_transactions' as table, COUNT(*) FROM fact_transactions
UNION ALL
SELECT 'dim_user', COUNT(*) FROM dim_user
UNION ALL
SELECT 'dim_merchant', COUNT(*) FROM dim_merchant
UNION ALL
SELECT 'dim_agency', COUNT(*) FROM dim_agency;

-- Check anomalies
SELECT
    sync_status,
    COUNT(*) as count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM fact_transactions), 2) as percent
FROM fact_transactions
GROUP BY sync_status
ORDER BY count DESC;

-- Check data quality flags
SELECT
    data_quality_flag,
    COUNT(*) as count
FROM fact_transactions
WHERE data_quality_flag IS NOT NULL
GROUP BY data_quality_flag
ORDER BY count DESC;
```

---

## Step 5: Connecter à DWH via Client

**Local Connection String** :

```
Host: localhost
Port: 5432
Database: dwh_nafad_pay
User: dwh_user
Password: RGHgv5#Kp9mX2wQl  (change en production!)
```

### Option A: DBeaver (GUI - Recommandé)

1. Télécharger [DBeaver Community](https://dbeaver.io)
2. New Database Connection → PostgreSQL
3. Remplir les paramètres ci-dessus
4. Test Connection

### Option B: psql CLI

```powershell
psql -h localhost -U dwh_user -d dwh_nafad_pay
```

### Option C: Python/Pandas

```python
import pandas as pd
import psycopg2

conn = psycopg2.connect(
    host='localhost',
    database='dwh_nafad_pay',
    user='dwh_user',
    password='RGHgv5#Kp9mX2wQl'
)

# Read from DWH
df = pd.read_sql("""
    SELECT
        COUNT(*) as tx_count,
        SUM(amount) as total_volume,
        COUNT(DISTINCT source_user_key) as unique_users
    FROM fact_transactions
""", conn)

print(df)
```

---

## Step 6: Lancer Metabase BI (Optionnel pour tests)

```powershell
docker-compose --profile bi up -d metabase

# Wait 30 seconds for startup
Start-Sleep -Seconds 30

# Access at http://localhost:3000
```

---

## Troubleshooting

### Erreur: "Connection refused"

```powershell
# Vérifier que PostgreSQL est running
docker-compose ps

# Si pas up, restart
docker-compose restart postgres_dwh
docker-compose logs postgres_dwh
```

### Erreur: "Permission denied on COPY"

```sql
-- CSV doit être dans le volume /staging
-- Copier les CSV à: G4_DWH/staging/
-- Puis utiliser:
COPY stg_users FROM '/staging/stg_users.csv' CSV HEADER;
```

### Erreur: "Table does not exist"

```powershell
# S'assurer que la DDL a été chargée
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay -c "\dt"
```

---

## Fichiers de Référence

| Fichier                                                                | Objectif                                    |
| ---------------------------------------------------------------------- | ------------------------------------------- |
| [`ddl/01_star_schema.sql`](./ddl/01_star_schema.sql)                   | Créer toutes les tables (dimensions + fact) |
| [`etl/02_load_star_schema.sql`](./etl/02_load_star_schema.sql)         | Transformer staging → DWH                   |
| [`docker-compose.yml`](./docker-compose.yml)                           | PostgreSQL + Metabase + pgAdmin             |
| [`analysis/01_anomalies_report.md`](./analysis/01_anomalies_report.md) | Explique les anomalies + stratégie          |

---

## Prochaines Étapes

✅ **Phase 1 (Aujourd'hui)** : Setup DWH local  
📊 **Phase 2 (Demain)** : Build BI Dashboard (5-6 questions métier)  
🏗️ **Phase 3 (Jour 3)** : Document Architecture AWS  
☁️ **Phase 4 (Jour 5)** : Deploy to AWS Redshift (optionnel)

---

**Questions?** Voir [README.md](../README.md) ou [analysis/01_anomalies_report.md](./analysis/01_anomalies_report.md)
