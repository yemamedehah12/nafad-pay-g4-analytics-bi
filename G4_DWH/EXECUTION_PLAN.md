# Plan d'Exécution: 10 Jours pour livrer le DWH G4

**Objectif**: Livrer un DWH complet + dashboard + architecture AWS en 10 jours  
**Équipe**: G4 Analytics & BI (4-5 personnes)  
**Deadline**: J+10

---

## Vue d'ensemble des livrables par jour

```
J1-J2: Infrastructure (DWH local)  ✅ CORE
J3: Data Load + ETL             ✅ CORE
J4-J5: Dashboard BI             ✅ STAKEHOLDER DEMO
J6-J7: Architecture AWS         ✅ GOVERNANCE
J8-J9: Testing + Optimisation   ✅ QUALITY
J10: Présentation + Handoff     ✅ DEPLOYMENT
```

---

## JOUR 1: Setup Infrastructure Locale

**Equipe**: 1 Data Engineer + 1 DevOps

### Matin (08:00-12:00)

**Tâches**:

- [ ] Clone projet / Pull latest code
- [ ] Install Docker Desktop (si pas encore)
- [ ] Lire `QUICKSTART.md` + `DELIVERABLES.md`
- [ ] Vérifier CSV files sont dans `./staging/`

**Commandes**:

```bash
cd G4_DWH
docker-compose ps
docker-compose up -d postgres_dwh
```

**Validation**:

```bash
docker-compose logs postgres_dwh | grep "ready to accept"
# Expected: ✅ Database is now accepting connections
```

### Après-midi (14:00-17:00)

**Tâches**:

- [ ] Charger les tables staging
- [ ] Vérifier les counts
- [ ] Document any issues

**Commandes**:

```bash
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay < ddl/00_create_staging.sql
# Expected: CREATE TABLE messages

# Vérifier
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';"
```

**Expected result**:

```
stg_users, stg_transactions, stg_merchants, stg_agencies, stg_agents, stg_accounts, stg_fees, node_metrics
```

---

## JOUR 2: Créer Star Schema

**Equipe**: 1 Data Engineer + 1 BI Analyst

### Matin (08:00-12:00)

**Tâches**:

- [ ] Charger la DDL du star schema
- [ ] Vérifier dimensions et fact table
- [ ] Index creation status

**Commandes**:

```bash
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay < ddl/01_star_schema.sql

# Vérifier les tables
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay << EOF
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name LIKE 'dim_%' OR table_name = 'fact_transactions'
ORDER BY table_name;
EOF
```

**Expected tables** (8 total):

- dim_date, dim_node, dim_user, dim_merchant, dim_agency, dim_agent, dim_account
- fact_transactions

### Après-midi (14:00-17:00)

**Tâches**:

- [ ] Documenter schéma
- [ ] Créer diagram ER (optionnel, mais recommandé)
- [ ] Review business logic (SCD Type 2, etc.)

**Documentation à compléter**:

```markdown
# Star Schema Notes

## Grain

1 row = 1 transaction

## Dimensions

- dim_date: Calendar dimension
- dim_user: SCD Type 2 (tracks history)
- dim_merchant: Type 1 (latest only)
- ...

## Checks

- All FKs present?
- All indexes created?
- Constraints OK?
```

---

## JOUR 3: Charger les Données

**Equipe**: 1 Data Engineer

### Matin (08:00-12:00)

**Tâches**:

- [ ] Charger CSV → staging tables
- [ ] Valider counts

**Commandes**:

```bash
# Charger CSV (COPY commands)
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay << EOF
COPY stg_users(id, first_name, last_name, email, phone_number, nni, kyc_level, moughataa_name, user_status, account_count, created_at, updated_at)
FROM '/staging/stg_users.csv' CSV HEADER ENCODING 'UTF-8';

COPY stg_transactions(id, reference, idempotency_key, transaction_type, amount, fee, total_amount, source_account_id, source_user_id, destination_account_id, destination_user_id, merchant_id, agency_id, agent_id, status, failure_reason, balance_before, balance_after, node_id, datacenter, sync_status, last_synced_at, amount_node_a, amount_node_b, risk_score, channel, device_type, ip_address, transaction_date, transaction_time, created_at, updated_at, completed_at)
FROM '/staging/stg_transactions.csv' CSV HEADER ENCODING 'UTF-8';

-- ... repeat for other tables

SELECT 'stg_users' as table, COUNT(*) as rows FROM stg_users
UNION ALL
SELECT 'stg_transactions', COUNT(*) FROM stg_transactions
-- ...
EOF
```

**Validation**:

```sql
SELECT table_name, row_count FROM (
  SELECT 'stg_users' as table_name, COUNT(*) as row_count FROM stg_users
  UNION ALL
  SELECT 'stg_transactions', COUNT(*) FROM stg_transactions
  -- ... all 8 tables
) t;
```

**Expected counts**:

- stg_users: 10,000
- stg_transactions: 100,000
- stg_merchants: 500
- stg_agencies: 100
- stg_agents: 392
- stg_accounts: 11,019
- stg_fees: 41,391
- node_metrics: 5 rows

### Après-midi (14:00-17:00)

**Tâches**:

- [ ] Exécuter ETL (load star schema)
- [ ] Valider transformations
- [ ] Check data quality flags

**Commandes**:

```bash
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay < etl/02_load_star_schema.sql

# Vérifier résultats
docker exec -it nafad_dwh_postgres psql -U dwh_user -d dwh_nafad_pay << EOF
SELECT 'fact_transactions' as table_name, COUNT(*) as rows FROM fact_transactions
UNION ALL
SELECT 'dim_date', COUNT(*) FROM dim_date
UNION ALL
SELECT 'dim_user', COUNT(*) FROM dim_user
UNION ALL
SELECT 'dim_merchant', COUNT(*) FROM dim_merchant;

-- Check anomalies
SELECT sync_status, COUNT(*) as count FROM fact_transactions GROUP BY sync_status ORDER BY count DESC;

-- Check data quality flags
SELECT data_quality_flag, COUNT(*) FROM fact_transactions WHERE data_quality_flag IS NOT NULL GROUP BY 1;
EOF
```

**Expected results**:

- fact_transactions: ~100K rows
- dim_user: ~10K rows
- dim_merchant: ~500 rows
- Anomalies: CONFLICT (1,549), LAGGING (1,912), PENDING (1,616)

---

## JOUR 4-5: Concevoir Dashboard BI

**Equipe**: 2 BI Analysts

### JOUR 4 Matin (08:00-12:00)

**Tâches**:

- [ ] Lancer Metabase
- [ ] Connecter PostgreSQL
- [ ] Tester connexion

**Commandes**:

```bash
docker-compose --profile bi up -d metabase

sleep 30  # Attendre startup

# Accéder à http://localhost:3000
# Email: admin@nafad.com
# Password: Nafad@123456
```

**Metabase Setup**:

- Database connection: PostgreSQL (localhost:5432)
- DB name: dwh_nafad_pay
- User: dwh_user
- Password: RGHgv5#Kp9mX2wQl

### JOUR 4 Après-midi (14:00-17:00)

**Tâches**:

- [ ] Créer 3 questions (Volume, Success Rate, Geographic)
- [ ] Tester queries
- [ ] Optimiser requêtes si lentes

**Questions à créer** (voir `dashboards/METABASE_SETUP.md`):

1. Volume Total MoM
2. Taux de Succès
3. Wilaya + Volume

**Timeline**:

- 14:00-15:30: Questions 1-3
- 15:30-16:30: Testing + Optimization
- 16:30-17:00: Document queries

### JOUR 5 Matin (08:00-12:00)

**Tâches**:

- [ ] Créer 3 questions supplémentaires
- [ ] Organiser dans dashboard

**Questions**: 4. Heures de Pointe 5. Top Merchants 6. Motifs d'Échec

### JOUR 5 Après-midi (14:00-17:00)

**Tâches**:

- [ ] Créer dashboard final
- [ ] Ajouter filtres (optionnel)
- [ ] Style + branding
- [ ] Partager avec équipe

**Dashboard Layout**:

```
Executive Daily - NAFAD-PAY G4
┌──────────────┬──────────────┬──────────────┐
│ Volume MoM   │ Success %    │ Top Regions  │
├──────────────┼──────────────┼──────────────┤
│ Peak Hours   │ Top Merch.   │ Fail Reasons │
└──────────────┴──────────────┴──────────────┘
```

**Sharing**:

- Copy dashboard URL
- Email to: `dg@nafad.com`, team@nafad.com
- Permissions: View-only

---

## JOUR 6-7: Architecture AWS

**Equipe**: 1 Architect + 1 DevOps

### JOUR 6 (08:00-17:00)

**Tâches**:

- [ ] Lire `architecture/01_early_stage_aws.md`
- [ ] Lire `architecture/02_at_scale_aws.md`
- [ ] Décider: Early Stage vs At Scale?
- [ ] Commencer document: "G4_Architecture_Decision.md"

**Decision Tree**:

```
Quelle architecture pour notre groupe?

IF timeline = 10 days AND budget = limited:
  → Early Stage (RDS + Metabase, ~600 MRU/mo)
ELSE IF budget = flexible AND security = critical:
  → At Scale (Redshift + SSO + RLS, ~15K MRU/mo)
ELSE:
  → Hybrid (RDS now, migrate to Redshift later)
```

**Document Structure** (`G4_Architecture_Decision.md`):

```markdown
# G4 DWH Architecture Decision

## Contexte

- Utilisateurs: 10,000
- Transactions: 100K/mois
- Analyse: Ad-hoc + reporting mensuel

## Option 1: Early Stage

- Pros: Rapide, pas cher, simple
- Cons: Pas scalable, pas d'SSO, single point of failure
- Cost: ~600 MRU/mo

## Option 2: At Scale

- Pros: Production-ready, secure, scalable
- Cons: Complex, coûteux, expertise requise
- Cost: ~15K MRU/mo

## Choix: [EARLY STAGE / AT SCALE]

## Justification: ...
```

### JOUR 7 (08:00-17:00)

**Tâches**:

- [ ] Finaliser architecture decision
- [ ] Documenter choix + justification
- [ ] Créer deployment checklist
- [ ] Préparer présentation pour DG

**Préparation présentation** (J8):

- Slide 1: DWH overview (schema, 100K transactions)
- Slide 2: Architecture diagram (Early Stage vs At Scale)
- Slide 3: Cost comparison (600 MRU vs 15K MRU)
- Slide 4: Timeline (deploy in 2-3 days vs 2 weeks)
- Slide 5: Recommendation + next steps

---

## JOUR 8: Testing + Optimisation

**Equipe**: 1 Data Engineer + 1 QA

### Matin (08:00-12:00)

**Tâches**:

- [ ] Exécuter test suite (data quality checks)
- [ ] Valider FK/PK intégrité
- [ ] Vérifier performance queries

**SQL Test Suite**:

```sql
-- Test 1: All transactions have valid date_key
SELECT COUNT(*) FROM fact_transactions WHERE date_key IS NULL;
-- Expected: 0

-- Test 2: All dimensions referenced from facts exist
SELECT COUNT(*) FROM fact_transactions ft
WHERE ft.source_user_key NOT IN (SELECT user_key FROM dim_user);
-- Expected: 0

-- Test 3: No negative amounts
SELECT COUNT(*) FROM fact_transactions WHERE amount < 0;
-- Expected: 0

-- Test 4: Query performance
EXPLAIN ANALYZE
SELECT DATE(dd.date_value), COUNT(*), SUM(amount)
FROM fact_transactions ft
JOIN dim_date dd ON ft.date_key = dd.date_key
GROUP BY 1;
-- Expected query time: < 2 seconds
```

### Après-midi (14:00-17:00)

**Tâches**:

- [ ] Document performance baseline
- [ ] Valider dashboard queries (<2s)
- [ ] Check PII masking views

**Performance Report**:

```markdown
# DWH Performance Baseline

| Query            | Time (ms) | Rows | Status |
| ---------------- | --------- | ---- | ------ |
| Volume MoM       | 245       | 24   | ✅ OK  |
| Success Rate     | 156       | 3    | ✅ OK  |
| Top 20 Merchants | 389       | 20   | ✅ OK  |
| Hourly Heatmap   | 612       | 720  | ✅ OK  |
| Anomalies        | 218       | 4949 | ✅ OK  |

All queries < 1s average. Performance acceptable.
```

---

## JOUR 9: Préparation Présentation

**Equipe**: Full team

### Matin (08:00-12:00)

**Tâches**:

- [ ] Préparer slides présentation (DG + metiers)
- [ ] Valider dashboard avec stakeholders
- [ ] Collecter feedback

**Slides** (5-10 min présentation):

1. **Problem Statement** (existing issues)
2. **Solution** (DWH + dashboard)
3. **Demo** (live dashboard)
4. **Architecture** (current + future)
5. **Timeline** (deployment)
6. **Cost** (monthly budget)
7. **Next Steps** (AWS deployment, optimization)

### Après-midi (14:00-17:00)

**Tâches**:

- [ ] Testing final de la présentation
- [ ] Préparer demo script
- [ ] Standby dashboard (live demo)

**Demo Script** (max 5 mins):

```
1. Open Metabase (http://localhost:3000)
2. Show executive dashboard
3. Click on "Volume MoM" KPI
   - "This month we have 2.1B MRU, up 10% from last month"
4. Click on "Top Merchants"
   - "Our top 5 merchants account for 40% of volume"
5. Explain: "This dashboard answers 15 business questions"
6. Show: "Architecture for AWS deployment (if time allows)"
```

---

## JOUR 10: Présentation + Handoff

**Equipe**: Full team + DG + Métiers

### Matin (08:00-12:00)

**Préparation**:

- [ ] Tester une dernière fois dashboard
- [ ] Confirmer accès réseau (si présentation en personne)
- [ ] Préparer copie des documents

### Après-midi (14:00-17:00)

**Présentation** (1 heure):

- [ ] 10 min: Contexte + problème
- [ ] 10 min: Solution overview
- [ ] 15 min: Live demo (dashboard)
- [ ] 10 min: Architecture + roadmap
- [ ] 5 min: Budget + timeline
- [ ] 10 min: Q&A

**Handoff**:

- [ ] Copier tous les documents à l'équipe métier
- [ ] Accès à Metabase dashboard
- [ ] Contact pour support/questions
- [ ] Schedule follow-up (1 semaine)

**Deliverables à remettre**:

1. ✅ Star schema DDL (`ddl/01_star_schema.sql`)
2. ✅ ETL pipeline (`etl/02_load_star_schema.sql`)
3. ✅ Docker Compose (`docker-compose.yml`)
4. ✅ Dashboard Metabase (live URL)
5. ✅ Architecture AWS (2 documents)
6. ✅ Rapport anomalies (`analysis/01_anomalies_report.md`)
7. ✅ Documentation complète

---

## ⚡ Timeline Récapitulatif

```
J1-J2: ⏱️ Infrastructure (local, ~16 heures)
  ├─ Docker PostgreSQL up
  ├─ Load staging tables
  └─ Star schema created

J3: ⏱️ Data Load + ETL (~8 heures)
  ├─ CSV → Staging
  ├─ ETL run
  └─ Validation

J4-J5: ⏱️ Dashboard (~16 heures)
  ├─ 6 questions créées
  ├─ Dashboard organized
  └─ Shared with team

J6-J7: ⏱️ Architecture (~16 heures)
  ├─ Early Stage vs At Scale
  ├─ Decision documented
  └─ Deployment plan

J8: ⏱️ Testing (~8 heures)
  ├─ Data quality tests
  ├─ Performance baseline
  └─ PII checks

J9: ⏱️ Présentation prep (~8 heures)
  ├─ Slides
  ├─ Demo script
  └─ Stakeholder review

J10: ⏱️ Présentation + Handoff (~8 heures)
  ├─ Live demo
  ├─ Q&A
  └─ Documentation transfer
```

---

## 👥 Allocation Équipe (Exemple)

**Total: 4-5 FTE**

### Option 1: 4 Personnes

- **Data Engineer 1** (60%): Infrastructure, ETL, performance
- **Data Engineer 2** (25%): Staging, testing
- **BI Analyst 1** (100%): Dashboard, queries
- **Solution Architect** (50%): AWS architecture, presentation

### Option 2: 5 Personnes

- **Data Engineer 1** (100%): Infrastructure, ETL
- **Data Engineer 2** (100%): Staging, testing
- **BI Analyst 1** (100%): Dashboard design
- **BI Analyst 2** (50%): Dashboard implementation, docs
- **Solution Architect** (50%): AWS architecture

---

## 🎯 Success Criteria

✅ **Projet réussi si**:

1. Dashboard répond 5-6 questions métier (working)
2. DG peut voir: Volume, Success Rate, Top Merchants
3. Aucune erreur FK/PK dans les données
4. Architecture documented (Early Stage ou At Scale)
5. Performances acceptable (<2s queries)
6. All CSV files loaded successfully (100K transactions)
7. Team trained + confident
8. Documentation complete

---

## 📞 Escalation Points

| Issue                    | Owner         | Escalate if                    |
| ------------------------ | ------------- | ------------------------------ |
| Query too slow           | Data Engineer | > 5 seconds                    |
| Dashboard not loading    | BI Analyst    | Reboot doesn't help            |
| Docker networking issues | DevOps        | Can't connect to DB            |
| Data looks wrong         | Data Engineer | Counts don't match staging     |
| Architecture questions   | Architect     | Can't decide Early vs At Scale |

---

## 📚 Reference Documents

- `QUICKSTART.md` - 30-min setup
- `DELIVERABLES.md` - Full project summary
- `analysis/01_anomalies_report.md` - Data quality deep dive
- `architecture/01_early_stage_aws.md` - POC architecture
- `architecture/02_at_scale_aws.md` - Production architecture
- `dashboards/METABASE_SETUP.md` - Dashboard guide

---

🚀 **Ready to execute?** Start with JOUR 1 tasks above!
