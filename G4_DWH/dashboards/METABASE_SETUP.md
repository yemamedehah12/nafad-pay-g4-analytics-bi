# Metabase Dashboard Setup Guide - G4 DWH

**Objectif**: Créer un dashboard exécutif avec 5-6 questions métier clés  
**Outil**: Metabase Community Edition (gratuit, Docker-ready)  
**Temps**: ~2-3 heures pour la setup complète

---

## Part 1: Lancer Metabase

### Step 1.1: Démarrer les services

```bash
cd G4_DWH

# Démarrer PostgreSQL + Metabase
docker-compose --profile bi up -d

# Attendre 30 secondes (Metabase startup)
sleep 30

# Vérifier les services
docker-compose ps
```

**Expected output**:

```
CONTAINER ID   IMAGE                 STATUS
xxx            postgres:16-alpine    Up 2 minutes (healthy)
yyy            metabase/metabase     Up 1 minute (starting)
```

### Step 1.2: Accéder à Metabase

```
URL: http://localhost:3000
```

### Step 1.3: Configuration Initiale

1. **Créer un compte admin**
   - Email: `admin@nafad.com`
   - Mot de passe: `Nafad@123456` (change en prod!)
   - Nom entreprise: `NAFAD-PAY`
   - Base de données: `PostgreSQL`

2. **Connecter PostgreSQL**
   - Host: `postgres_dwh`
   - Port: `5432`
   - Database: `dwh_nafad_pay`
   - Username: `dwh_user`
   - Password: `RGHgv5#Kp9mX2wQl`

3. **Test Connection** → ✅ OK

---

## Part 2: Créer les Questions (Queries)

### Question 1: Volume Total (MoM Comparison)

**Objectif**: KPI - Compare mois courant vs mois précédent

**Query** (SQL):

```sql
WITH monthly_volumes AS (
  SELECT
    DATE_TRUNC('month', date_value)::DATE as month,
    SUM(ft.amount) as total_volume,
    COUNT(DISTINCT ft.source_user_key) as unique_senders,
    COUNT(*) as transaction_count
  FROM fact_transactions ft
  JOIN dim_date dd ON ft.date_key = dd.date_key
  GROUP BY 1
  ORDER BY 1 DESC
  LIMIT 2  -- Current + Previous month
)
SELECT
  month,
  total_volume,
  unique_senders,
  transaction_count,
  ROUND(total_volume / 1000000, 1) as volume_in_millions_mru,
  LAG(total_volume) OVER (ORDER BY month DESC) as previous_month_volume,
  CASE
    WHEN LAG(total_volume) OVER (ORDER BY month DESC) IS NOT NULL
    THEN ROUND(
      (total_volume - LAG(total_volume) OVER (ORDER BY month DESC)) * 100.0 /
      LAG(total_volume) OVER (ORDER BY month DESC),
      2
    )
    ELSE NULL
  END as mom_percent_change
FROM monthly_volumes
ORDER BY month DESC;
```

**Metabase Setup**:

1. New → Question → SQL Editor
2. Paste query above
3. Visualize → Number (KPI card)
4. Settings:
   - Title: `Volume Total MoM`
   - Format: `1,234,567 MRU`
   - Trending: `UP` if MoM > 0

---

### Question 2: Taux de Succès

**Objectif**: KPI - Show success rate % + breakdown

**Query**:

```sql
SELECT
  COALESCE(status, 'UNKNOWN') as status,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) as percent_of_total
FROM fact_transactions
GROUP BY status
ORDER BY count DESC;
```

**Metabase Setup**:

1. New → Question → SQL Editor
2. Paste query
3. Visualize → Pie Chart (distribution)
4. Drill-through: Click on pie slice → See failures by reason

---

### Question 3: Wilaya + Volume (Map)

**Objectif**: Geographic heat map - Which regions are hot?

**Query**:

```sql
SELECT
  m.wilaya_name,
  COUNT(*) as transaction_count,
  SUM(ft.amount) as total_volume,
  COUNT(DISTINCT ft.source_user_key) as unique_users,
  ROUND(AVG(ft.amount), 2) as avg_transaction
FROM fact_transactions ft
LEFT JOIN dim_merchant m ON ft.merchant_key = m.merchant_key
WHERE ft.status = 'SUCCESS'
GROUP BY m.wilaya_name
ORDER BY total_volume DESC;
```

**Metabase Setup**:

1. New → Question → SQL Editor
2. Paste query
3. Visualize → Map (if Metabase has map viz)
4. Alternative: Table with sorting by `total_volume DESC`

---

### Question 4: Heures de Pointe (Hourly Heatmap)

**Objectif**: When are transactions happening? (operational insight)

**Query**:

```sql
SELECT
  DATE(dd.date_value) as tx_date,
  EXTRACT(HOUR FROM ft.transaction_time)::INT as hour_of_day,
  COUNT(*) as hourly_count,
  SUM(ft.amount) as hourly_volume,
  ROUND(AVG(ft.amount), 2) as avg_amount,
  COUNT(*) FILTER (WHERE ft.status = 'SUCCESS') * 100.0 / COUNT(*) as success_rate
FROM fact_transactions ft
JOIN dim_date dd ON ft.date_key = dd.date_key
WHERE dd.date_value >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY 1, 2
ORDER BY tx_date DESC, hour_of_day ASC;
```

**Metabase Setup**:

1. New → Question → SQL Editor
2. Paste query
3. Visualize → Heatmap or Pivot Table
   - Rows: `hour_of_day`
   - Columns: `tx_date`
   - Values: `hourly_count` or `hourly_volume`

---

### Question 5: Top Merchants (by volume)

**Objectif**: Who are our biggest merchants?

**Query**:

```sql
SELECT
  m.merchant_name,
  m.merchant_category,
  m.wilaya_name,
  COUNT(*) as transaction_count,
  SUM(ft.amount) as total_volume,
  ROUND(AVG(ft.amount), 2) as avg_transaction,
  COUNT(DISTINCT ft.source_user_key) as unique_customers
FROM fact_transactions ft
LEFT JOIN dim_merchant m ON ft.merchant_key = m.merchant_key
WHERE ft.status = 'SUCCESS'
GROUP BY m.merchant_name, m.merchant_category, m.wilaya_name
ORDER BY total_volume DESC
LIMIT 20;
```

**Metabase Setup**:

1. New → Question → SQL Editor
2. Paste query
3. Visualize → Table
4. Sort by: `total_volume` DESC
5. Add card title: "Top 20 Merchants by Volume"

---

### Question 6: Failure Reasons (Pie Chart)

**Objectif**: Why do transactions fail?

**Query**:

```sql
SELECT
  COALESCE(failure_reason, 'UNKNOWN_FAILURE') as reason,
  COUNT(*) as failed_count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM fact_transactions WHERE status = 'FAILED'), 1) as percent_of_failures
FROM fact_transactions
WHERE status = 'FAILED'
GROUP BY failure_reason
ORDER BY failed_count DESC
LIMIT 15;
```

**Metabase Setup**:

1. New → Question → SQL Editor
2. Paste query
3. Visualize → Pie Chart
4. Hover shows: "Reason: XXX, Count: YYY, %: ZZZ"

---

## Part 3: Organiser le Dashboard

### Create Metabase Dashboard

1. **New Dashboard**
   - Name: `Executive Daily Dashboard`
   - Description: `5 key KPIs for DG`

2. **Add Questions to Dashboard**
   - Click "+" button
   - Add each of the 6 questions created above
   - Arrange in grid (3 cols × 2 rows):
     ```
     ┌─────────────┬─────────────┬─────────────┐
     │ Volume MoM  │ Success %   │ Top Regions │
     ├─────────────┼─────────────┼─────────────┤
     │ Peak Hours  │ Top Merchants│Fail Reasons│
     └─────────────┴─────────────┴─────────────┘
     ```

3. **Auto-Refresh**
   - Set: Refresh every "1 hour"
   - Use case: Morning standup, execute once

4. **Share Dashboard**
   - Copy dashboard URL
   - Share with: `dg@nafad.com`, `analytics@nafad.com`
   - Permissions: View-only (read-only)

---

## Part 4: (Optional) Advanced: Add Filters

### Dashboard Filters

Add dropdowns to dashboard for interactive filtering:

```
[Wilaya Filter] [Agency Filter] [Date Range] [Status Filter]
```

### Example: Date Range Filter

1. Edit Dashboard → Add Filter
2. Type: "Date"
3. Target: Link to all cards
4. Cards affected:
   - Volume MoM (restrict to selected date range)
   - Peak Hours (show data for selected period)
   - Top Merchants (filter by date)

---

## Part 5: Troubleshooting

### Issue: Metabase won't connect to PostgreSQL

**Solution**:

```bash
# Check if PostgreSQL is running
docker-compose ps

# If not, restart
docker-compose restart postgres_dwh

# Check logs
docker-compose logs postgres_dwh

# Verify manually
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay -c "SELECT COUNT(*) FROM fact_transactions;"
```

### Issue: Query is very slow

**Solutions**:

1. Add LIMIT clause (e.g., `LIMIT 1000` for testing)
2. Check if indexes exist: `ddl/01_star_schema.sql`
3. Run `VACUUM ANALYZE` on fact_transactions:
   ```sql
   VACUUM ANALYZE fact_transactions;
   ```

### Issue: Dashboard not updating

**Solution**:

- Check Metabase refresh interval
- Manually refresh: F5 or "Refresh" button
- Check ETL log: Did new data get loaded?

---

## Part 6: Production Checklist

Before sharing dashboard with executives:

- [ ] All 6 questions return data (no errors)
- [ ] Queries execute <2 seconds
- [ ] Data looks reasonable (sanity check values)
- [ ] Formatting correct (currency, decimals, %)
- [ ] Filters work (if added)
- [ ] Share permissions set (read-only)
- [ ] Documentation updated with queries
- [ ] Team trained on dashboard interpretation

---

## Part 7: Next Steps

### Immediate

- [ ] Build dashboard with 5-6 questions (today)
- [ ] Share with team (internal review)
- [ ] Share with DG (executive review)

### Short-term (Week 2)

- [ ] Add more metrics (KYC completion, agency performance)
- [ ] Setup alerts (e.g., if success rate drops below 95%)
- [ ] Scheduled email reports (daily at 7 AM)

### Medium-term (Week 3+)

- [ ] Migrate to QuickSight (if moving to AWS)
- [ ] Add row-level security (analysts see only their region)
- [ ] Setup real-time refresh (if budget allows)

---

## 📊 Sample Dashboard JSON (for reference)

If you want to manually configure cards, here's a template:

```json
{
  "name": "Executive Daily Dashboard",
  "description": "Key metrics for DG",
  "cards": [
    {
      "id": 1,
      "title": "Volume Total MoM",
      "type": "number",
      "query": "SELECT total_volume FROM monthly_volumes LIMIT 1",
      "visualization": { "type": "number", "format": "$#,##0" }
    },
    {
      "id": 2,
      "title": "Success Rate",
      "type": "gauge",
      "query": "SELECT success_rate FROM transaction_stats",
      "visualization": { "type": "gauge", "min": 0, "max": 100 }
    }
  ]
}
```

---

## 🎓 Learning Resources

- **Metabase Docs**: https://www.metabase.com/docs/latest/
- **SQL for Analytics**: Khan Academy or Mode Analytics SQL Tutorial
- **Star Schema Queries**: See `etl/02_load_star_schema.sql` for examples

---

**Ready?** Dashboard should be live in < 3 hours! 🚀
