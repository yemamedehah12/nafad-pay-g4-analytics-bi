# NAFAD-PAY G4 DWH - Early Stage Architecture

**Objectif** : Architecture simple et rapide pour démarrage en 10 jours  
**Cible** : POC/MVP capable de répondre aux 15 questions métier  
**Coût estimé** : ~500 USD/mois (non-production)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   AWS Account (Sandbox)                  │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │         Data Ingestion & Staging (S3)            │   │
│  │  - stg_*.csv files uploaded via AWS DataSync      │   │
│  │  - Bucket: s3://nafad-pay-staging-dev/staging/  │   │
│  └──────────────────────────────────────────────────┘   │
│           ↓ (Weekly via Lambda/EventBridge)            │
│  ┌──────────────────────────────────────────────────┐   │
│  │     RDS PostgreSQL (DWH Database)                 │   │
│  │  - Instance: db.t3.medium (2 vCPU, 4 GB RAM)      │   │
│  │  - Storage: 100 GB gp3 (dev); auto-backup        │   │
│  │  - Subnet: Private (no internet)                 │   │
│  │  - Port: 5432 (access via Bastion only)         │   │
│  └──────────────────────────────────────────────────┘   │
│           ↓ (SQL queries)                              │
│  ┌──────────────────────────────────────────────────┐   │
│  │  BI Tool (Metabase on EC2)                       │   │
│  │  - Instance: t3.small (2 vCPU, 2 GB)             │   │
│  │  - Connects to RDS PostgreSQL                    │   │
│  │  - Access: http://metabase.nafad-pay.internal   │   │
│  └──────────────────────────────────────────────────┘   │
│           ↓ (HTTP)                                      │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Business Users                                  │   │
│  │  - Dashboard: 5-6 Key Questions                 │   │
│  │  - Access: Metabase UI                          │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. S3 - Data Lake (Staging)

**Purpose**: Store raw CSV files  
**Bucket Name**: `nafad-pay-staging-dev`  
**Structure**:

```
s3://nafad-pay-staging-dev/
├── staging/
│   ├── stg_users.csv
│   ├── stg_transactions.csv
│   ├── stg_merchants.csv
│   └── ...
├── archive/
│   └── [old backups]
└── logs/
    └── [import logs]
```

**Access Control**:

- RDS PostgreSQL IAM role: Read-only
- Developers: PutObject (upload only, no delete)
- Cannot be accessed from internet (VPC endpoint)

**Cost**: ~50 MRU/month (10 GB storage)

---

### 2. RDS PostgreSQL - DWH Database

**Instance Sizing**:

- Class: `db.t3.medium` (2 vCPU, 4 GB RAM) — right-size for 100K transactions
- Storage: 100 GB gp3 (SSD)
- Multi-AZ: FALSE (dev only; enable in production)
- Backup: 7-day retention (auto)

**Database Configuration**:

- Engine: PostgreSQL 16 (latest stable)
- Database: `dwh_nafad_pay`
- Encoding: UTF-8

**Security**:

- Subnet: Private (no internet access)
- Security Group: Only allow Metabase EC2 + Bastion
- Encryption: KMS (default AWS managed key)
- IAM Database Auth: Enabled (but password auth for dev simplicity)

**DDL/ETL**:

1. Star schema tables (fact_transactions + 7 dimensions)
2. Staging tables (stg_users, stg_transactions, etc.)
3. ETL jobs run nightly (Lambda trigger)

**Cost**: ~400 MRU/month (small instance + storage)

---

### 3. Lambda - ETL Orchestration

**Trigger**: EventBridge Rule (Daily at 02:00 UTC)

**Function**: `trigger_dwh_etl`

```python
# Pseudo-code
def lambda_handler(event, context):
    # 1. Download stg_*.csv from S3
    # 2. Connect to RDS (via Secret Manager credentials)
    # 3. TRUNCATE staging tables
    # 4. Load CSV data (COPY command)
    # 5. Run ETL: 02_load_star_schema.sql
    # 6. Return result (success/failure)
    # 7. Send SNS notification
```

**Timeout**: 15 minutes (should complete in < 5 min)  
**Memory**: 512 MB  
**Cost**: ~5 MRU/month

---

### 4. EC2 - Metabase BI Server

**Instance**:

- Type: `t3.small` (2 vCPU, 2 GB RAM + 20 GB SSD)
- OS: Amazon Linux 2
- Subnet: Private (no direct internet)

**Docker Setup**:

```dockerfile
FROM metabase/metabase:latest
EXPOSE 3000
```

**Startup Script**:

```bash
#!/bin/bash
docker run -d \
  --name metabase \
  -e MB_DB_TYPE=postgres \
  -e MB_DB_HOST=<RDS_ENDPOINT> \
  -e MB_DB_USER=metabase_app \
  -e MB_DB_PASS=$(aws secretsmanager get-secret-value --secret-id metabase-db-pass --query SecretString --output text) \
  -p 3000:3000 \
  metabase/metabase:latest
```

**Access**:

- Via ALB (Application Load Balancer) with self-signed cert
- URL: `https://bi-dev.nafad-pay.internal:443`

**Cost**: ~100 MRU/month

---

### 5. Secrets Manager - Credentials

**Secrets Stored**:

- `rds-master-password` : DWH admin password
- `metabase-db-pass` : Metabase read-only user
- `s3-sync-credentials` : AWS DataSync role

**Rotation**: Manual (every 90 days)

**Cost**: ~20 MRU/month

---

## Data Flow: End-to-End

### Daily ETL Flow

```
1. [08:00 UTC] New stg_transactions.csv uploaded to S3 via DataSync
   └─→ Trigger: EventBridge Rule "daily_etl_trigger"

2. [02:00 UTC] Lambda starts
   └─→ Action: Download CSV from S3 → Load into RDS staging tables
   └─→ Action: Execute 02_load_star_schema.sql
   └─→ Result: fact_transactions + dimensions updated

3. [02:15 UTC] Metabase queries DWH
   └─→ Cached dashboard refreshed
   └─→ Users see new metrics on morning dashboard

4. [02:30 UTC] SNS notification sent
   └─→ Message: "ETL completed | 100K transactions loaded | 0 errors"
   └─→ Alert: If errors occur, send to #dwh-alerts Slack channel
```

---

## BI Dashboard: 5-6 Key Questions

### Dashboard 1: Executive Overview

1. **Volume Total (ce mois vs mois précédent)**
   - KPI: 2.1B vs 1.9B MRU (+10%)
   - Trend: Line chart (daily volume)

2. **Taux de Succès**
   - KPI: 97.5%
   - Breakdown: Success / Failed / Pending

3. **Frais Collectés**
   - KPI: 40M MRU
   - Trend: Stacked area chart

### Dashboard 2: Geographic

4. **Wilaya avec Plus de Volume**
   - Map: Heat map des wilayas
   - Table: Top 5 agencies

### Dashboard 3: Operational

5. **Heures de Pointe**
   - Chart: Hourly transaction count (heatmap)
   - Table: Peak hours (10-15h, 17-20h)

6. **Motifs d'Échec**
   - Pie chart: Failed reasons distribution
   - Table: Count by failure_reason

---

## Security Posture (Early Stage)

### What's Implemented ✅

- [x] HTTPS via ALB (TLS 1.2)
- [x] Private subnets for RDS + Metabase
- [x] Security groups (strictest rules)
- [x] 7-day backup retention
- [x] CloudTrail logging all API calls
- [x] KMS encryption at rest (S3 + RDS)

### What's NOT in Early Stage ⚠️

- [ ] Multi-AZ (single AZ only)
- [ ] VPN/SSO for BI access (basic auth only)
- [ ] Row-level Security (RLS) in database
- [ ] Column masking for PII
- [ ] Dynamic monitoring + alerting
- [ ] Automated failover

---

## Deployment Checklist

- [ ] VPC & Networking (default VPC acceptable for dev)
- [ ] S3 bucket created + IAM roles
- [ ] RDS PostgreSQL instance running
- [ ] Load DDL: `ddl/00_create_staging.sql`
- [ ] Load DDL: `ddl/01_star_schema.sql`
- [ ] Upload CSV to S3 + test COPY
- [ ] Lambda function deployed + tested
- [ ] EC2 launched + Metabase running
- [ ] Metabase datasource connected to RDS
- [ ] Dashboard created (5-6 questions)
- [ ] Tested by business users
- [ ] Documentation complete

---

## Cost Summary

| Component       | Instance        | Cost/Month         |
| --------------- | --------------- | ------------------ |
| RDS PostgreSQL  | db.t3.medium    | ~400 MRU           |
| EC2 Metabase    | t3.small        | ~100 MRU           |
| S3 Storage      | 10 GB           | ~50 MRU            |
| Lambda          | ~30 invocations | ~5 MRU             |
| Secrets Manager | 1 secret        | ~20 MRU            |
| Data Transfer   | Minimal         | ~25 MRU            |
| **TOTAL**       |                 | **~600 MRU/month** |

---

## Operational Runbook

### Daily Tasks

- [ ] Check Metabase dashboard (no red alerts)
- [ ] Monitor RDS CPU/Memory (CloudWatch)
- [ ] Verify ETL logs (CloudWatch Logs)

### Weekly Tasks

- [ ] Test RDS backups (restore to test instance)
- [ ] Review Metabase query performance
- [ ] Check S3 bucket size growth

### Monthly Tasks

- [ ] Rotate credentials (Secrets Manager)
- [ ] Review AWS Cost Explorer
- [ ] Archive old data to Glacier

---

## Limitations & Next Steps

### Current Limitations (Early Stage)

- ❌ No real-time data (batch daily only)
- ❌ No row-level security (all analysts see all data)
- ❌ Single point of failure (no redundancy)
- ❌ No BI tool SSO (basic authentication)

### Upgrade to `At Scale` (In 2-3 months)

- Migrate from RDS PostgreSQL → **AWS Redshift** (big data)
- Add **Redshift Spectrum** for S3 data lake
- Enable **Redshift RLS** (row-level security)
- Add **Cognito** for SSO
- Setup **dbt-core** for CI/CD ETL
- Implement **Glue Data Catalog** for metadata
- Add **QuickSight** for advanced BI

---

## Conclusion

✅ **Early Stage is optimized for**:

- Quick deployment (< 2 days)
- Low cost (< 1K MRU/month)
- Simple operations (minimal monitoring)
- Ability to answer 15 business questions

⚡ **Ready to upgrade to At Scale when** business needs real-time, multi-user deployment with security/governance.
