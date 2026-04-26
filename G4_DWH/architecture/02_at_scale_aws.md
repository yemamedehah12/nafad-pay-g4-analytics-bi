# NAFAD-PAY G4 DWH - At Scale Architecture

**Objectif** : Architecture production robuste, scalable, sécurisée  
**Cible** : 10,000+ users, real-time + historical analytics, 99.9% availability  
**Coût estimé** : ~5,000-10,000 USD/mois (production)

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    Multi-AZ Deployment (us-east-1)                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────┐      │
│  │                   Internet                                      │      │
│  │  - Cloudflare CDN (caching + DDoS protection)                 │      │
│  └────────────────────────────────────────────────────────────────┘      │
│                         ↓ (TLS 1.3)                               │      │
│  ┌────────────────────────────────────────────────────────────────┐      │
│  │           Application Load Balancer (ALB)                      │      │
│  │  - Health checks every 30s                                    │      │
│  │  - WAF rules (rate limiting, SQL injection blocking)         │      │
│  │  - Sticky sessions for QuickSight                            │      │
│  └────────────────────────────────────────────────────────────────┘      │
│           ↓ (Private network)                                    │      │
│  ┌────────────────────────────────────────────────────────────────┐      │
│  │ VPC (10.0.0.0/16) with 3 AZs                                 │      │
│  │                                                                 │      │
│  │  Private Subnets:                                              │      │
│  │  ├─ us-east-1a: 10.0.1.0/24                                 │      │
│  │  ├─ us-east-1b: 10.0.2.0/24                                 │      │
│  │  └─ us-east-1c: 10.0.3.0/24                                 │      │
│  │                                                                 │      │
│  │  NAT Gateway: Single endpoint for egress                      │      │
│  └────────────────────────────────────────────────────────────────┘      │
│                         ↓                                        │      │
│  ┌─────────────────────────────────────────────────────────────┐         │
│  │       DATA INGESTION TIER                                   │         │
│  │                                                             │         │
│  │  ┌─ Glue Crawlers ──────────────────────────────────────┐  │         │
│  │  │ Detects schema changes in S3 Parquet files          │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                    ↓                                        │         │
│  │  ┌─ S3 Data Lake (Parquet) ─────────────────────────────┐  │         │
│  │  │ s3://nafad-pay-datalake/                             │  │         │
│  │  │ ├── bronze/ (raw CSV → Parquet)                      │  │         │
│  │  │ ├── silver/ (cleaned, deduplicated)                  │  │         │
│  │  │ └── gold/ (aggregated, business ready)               │  │         │
│  │  │ Lifecycle: 7yr retention, archive to Glacier after 1y│ │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                    ↓                                        │         │
│  │  ┌─ Glue Data Catalog ───────────────────────────────────┐ │         │
│  │  │ + Macie (Auto PII detection)                         │ │         │
│  │  │ + LakeFormation (Access Control)                    │ │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  └─────────────────────────────────────────────────────────────┘         │
│                         ↓                                        │      │
│  ┌─────────────────────────────────────────────────────────────┐         │
│  │       ANALYTICS TIER                                        │         │
│  │                                                             │         │
│  │  ┌─ Redshift Cluster (Multi-node) ──────────────────────┐  │         │
│  │  │ Node Type: ra3.4xlplus (24 nodes = 192 GB memory)    │  │         │
│  │  │ Concurrency Scaling enabled (burst capacity)          │  │         │
│  │  │ • Managed storage (512 TB across nodes)               │  │         │
│  │  │ • Auto-vacuum + deep copy maintenance               │  │         │
│  │  │ • Query monitoring rules (max 60s queries)           │  │         │
│  │  │                                                        │  │         │
│  │  │ Tables:                                               │  │         │
│  │  │  ├─ fact_transactions (100M+ rows, compression)       │  │         │
│  │  │  ├─ dim_* (slowly changing dimensions, SCD Type 2)    │  │         │
│  │  │  ├─ Materialized views for hourly aggregates         │  │         │
│  │  │  └─ RLS enabled (masking for junior analysts)        │  │         │
│  │  │                                                        │  │         │
│  │  │ Security:                                              │  │         │
│  │  │  ├─ Redshift IAM auth (no passwords)                 │  │         │
│  │  │  ├─ Enhanced encryption (AES-256)                    │  │         │
│  │  │  ├─ Audit logging → S3 + Athena queries              │  │         │
│  │  │  └─ Database-level + schema-level RLS               │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                    ↓ (SQL queries)                         │         │
│  │  ┌─ Redshift Spectrum ───────────────────────────────────┐  │         │
│  │  │ Query S3 Parquet directly (no load needed)           │  │         │
│  │  │ Cost: Pay only for GB scanned                         │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                    ↓                                        │         │
│  │  ┌─ dbt-core + CI/CD ────────────────────────────────────┐  │         │
│  │  │ GitHub → dbt cloud → Test → Deploy → Redshift        │  │         │
│  │  │ • Lineage tracking                                    │  │         │
│  │  │ • Data quality tests (freshness, uniqueness)         │  │         │
│  │  │ • Scheduled runs (every 4 hours)                      │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                    ↓                                        │         │
│  │  ┌─ ElastiCache (Redis) ─────────────────────────────────┐  │         │
│  │  │ Node Type: cache.r7g.xlarge (3 nodes, 32GB each)     │  │         │
│  │  │ Caching popular dashboard queries                     │  │         │
│  │  │ TTL: 1 hour for metrics, 24h for slow-moving dims    │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  └─────────────────────────────────────────────────────────────┘         │
│                         ↓                                        │      │
│  ┌─────────────────────────────────────────────────────────────┐         │
│  │       BI & VISUALIZATION TIER                              │         │
│  │                                                             │         │
│  │  ┌─ AWS QuickSight (Enterprise) ────────────────────────┐  │         │
│  │  │ Dashboards: 5-6 key questions for executives         │  │         │
│  │  │ Capacity: 50 Pro users + unlimited viewers          │  │         │
│  │  │ • Direct connection to Redshift (IAM auth)           │  │         │
│  │  │ • RLS policies (agency heads see only their agency)  │  │         │
│  │  │ • Email reports (daily at 07:00 AM)                  │  │         │
│  │  │ • Mobile app (iOS/Android)                           │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                                                             │         │
│  │  ┌─ Amazon Cognito (SSO) ────────────────────────────────┐  │         │
│  │  │ Identity Provider:                                    │  │         │
│  │  │  • SAML 2.0 (Office 365, if company uses it)        │  │         │
│  │  │  • MFA (SMS + Google Authenticator)                  │  │         │
│  │  │  • Group management (DG team, Finance, Ops)          │  │         │
│  │  │ • Session duration: 8 hours (auto-logout)            │  │         │
│  │  │ • Token refresh: Rotate every 2 hours               │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  └─────────────────────────────────────────────────────────────┘         │
│                         ↓                                        │      │
│  ┌─────────────────────────────────────────────────────────────┐         │
│  │       MONITORING & GOVERNANCE TIER                          │         │
│  │                                                             │         │
│  │  ┌─ CloudWatch ──────────────────────────────────────────┐  │         │
│  │  │ Metrics: RDS/Redshift CPU, memory, queries            │  │         │
│  │  │ Logs: Application logs, ETL logs, query logs          │  │         │
│  │  │ Dashboards: Real-time monitoring                      │  │         │
│  │  │ Alarms: Triggers SNS → PagerDuty (on-call)           │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                                                             │         │
│  │  ┌─ CloudTrail ──────────────────────────────────────────┐  │         │
│  │  │ Logs: All API calls → S3 → Athena queries            │  │         │
│  │  │ Detects: Who accessed what data, when, from where    │  │         │
│  │  │ Events: Database schema changes, credential rotations │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                                                             │         │
│  │  ┌─ AWS Config ──────────────────────────────────────────┐  │         │
│  │  │ Compliance: VPC config, security group rules          │  │         │
│  │  │ Detects: Unauthorized changes                         │  │         │
│  │  │ Reports: Weekly compliance status                     │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                                                             │         │
│  │  ┌─ AWS Security Hub ────────────────────────────────────┐  │         │
│  │  │ Aggregates findings from: CloudTrail, GuardDuty       │  │         │
│  │  │ Threat detection: Unusual access patterns             │  │         │
│  │  │ Priority scores: Critical → Low                       │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  └─────────────────────────────────────────────────────────────┘         │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────┐         │
│  │       INCIDENT RESPONSE                                     │         │
│  │                                                             │         │
│  │  ┌─ SNS Topics ──────────────────────────────────────────┐  │         │
│  │  │ • #dwh-alerts (Slack)                                │  │         │
│  │  │ • PagerDuty (on-call rotations)                      │  │         │
│  │  │ • Email (critical only)                              │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  │                                                             │         │
│  │  ┌─ Runbooks ────────────────────────────────────────────┐  │         │
│  │  │ • "Redshift query timeout" → scale up, kill long    │  │         │
│  │  │ • "S3 data lake corruption" → restore from backup   │  │         │
│  │  │ • "Unauthorized access attempt" → revoke token      │  │         │
│  │  └───────────────────────────────────────────────────────┘ │         │
│  └─────────────────────────────────────────────────────────────┘         │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. Data Ingestion: S3 Data Lake + Glue

**S3 Structure (Bronze → Silver → Gold)**:

```
s3://nafad-pay-datalake/
├── bronze/                     # Raw data (no transformations)
│   ├── transactions/
│   │   ├── 2026-04-20/transactions.parquet
│   │   ├── 2026-04-21/transactions.parquet
│   │   └── ...
│   ├── users/
│   ├── merchants/
│   └── ...
├── silver/                     # Cleaned & deduplicated
│   ├── transactions_dedupe/    # Remove duplicates
│   ├── users_cleaned/          # Fix data types, nulls
│   └── ...
├── gold/                       # Ready for BI (aggregated)
│   ├── daily_metrics/          # Materialized views
│   ├── user_summary/           # Slowly changing dims
│   └── ...
├── archive/                    # Historical (> 1 year)
│   └── transactions_2024/
└── metadata/
    ├── schema_registry/        # Version control of schemas
    └── lineage/                # Data lineage tracking
```

**Glue Crawlers** (Auto-detect schema):

- Run: Daily at 03:00 UTC
- Output: Glue Data Catalog
- Actions: Email on schema changes

**Glue Macie** (PII Detection):

- Scans: S3 data lake every week
- Detects: Email, phone, NNI, credit card patterns
- Tags: Objects with `pii=true` in metadata
- Alert: If unencrypted PII found → escalate

**Lake Formation** (Access Control):

- Role-based access:
  - Analysts: Read `gold/` tables only
  - Data engineers: Read/write `silver/` + `gold/`
  - Finance: Read only `gold/financial_*`

---

### 2. Redshift: MPP Data Warehouse

**Cluster Architecture**:

- **Node Type**: `ra3.4xlplus` (24 nodes)
  - 128 GB RAM per node = 3.1 TB total
  - 512 TB managed storage (scalable)
  - 8 vCPU / node

**High Availability**:

- Multi-AZ: Automatic failover (< 5 minutes)
- Backup: Every 4 hours → S3
- Restore: Point-in-time (up to 35 days)

**Performance Features**:

- **Concurrency Scaling**: Auto-add nodes when queue > 10 queries
- **Result Caching**: 24-hour cache for identical queries
- **Materialized views**: Nightly aggregation refresh
- **Column compression**: 10:1 average (especially for dimensions)

**Security**:

- By **default**: All data encrypted at rest (AES-256)
- Audit logging → S3 + Athena
- **RLS (Row-Level Security)**: Database-level masking
  - Example: Junior analyst sees `nni = '****-****'`
  - Only senior analysts see full `nni`
- **IAM Auth**: No passwords, temp credentials via STS
- **Enhanced VPC**: PrivateLink, no public IP

**Maintenance**:

- Redshift automatically: Vacuum + ANALYZE (1x/week)
- User responsibilities: Monitor query duration, kill runaway jobs

**Cost**: ~8,000 MRU/month (24 nodes × 330 MRU/node)

---

### 3. dbt-core + CI/CD

**Workflow**:

```
Developer commits → GitHub PR
    ↓
  dbt cloud triggers:
    ├─ dbt parse (syntax check)
    ├─ dbt test (data quality)
    ├─ dbt doc generate
    ├─ dbt run (on dev schema)
    └─ dbt compile (generate SQL)
    ↓
  PR approved → Merge to main
    ↓
  dbt production job scheduled:
    ├─ 00:00 UTC: dbt run --models stg_*  (load staging)
    ├─ 01:00 UTC: dbt run --models dim_*  (load dimensions)
    ├─ 02:00 UTC: dbt run --models fact_* (load facts)
    ├─ 03:00 UTC: dbt test (validate)
    ├─ 04:00 UTC: dbt snapshot (SCD Type 2 captures)
    └─ 05:00 UTC: Alert if any failures
```

**dbt Configuration** (`dbt_project.yml`):

```yaml

...
models:
  config:
    schema: analytics
    materialized: view # Default
    pre_hook: "GRANT SELECT ON TABLE {{ this }} TO analytics_group"
    post_hook: "REFRESH MATERIALIZED VIEW {{ this }}"

seeds:
  config:
    schema: reference_data

snapshots:
  config:
    unique_key: user_id
    updated_at: updated_at
    strategy: timestamp # SCD Type 2
```

**Data Quality Tests** (dbt test):

```sql
# models/dim_user.yml
models:
  - name: dim_user
    tests:
      - unique: {column_name: user_key}
      - not_null: {column_name: user_id}
      - relationships: {column_name: agency_key, to: ref('dim_agency'), field: agency_key}
```

---

### 4. ElastiCache (Redis)

**Cluster Setup**:

- Type: `cache.r7g.xlarge` (3 nodes)
- Multi-AZ: Yes (automatic failover)
- Replication: Enabled (read replicas)

**Caching Strategy**:

- **Hot data** (dashboards): 1-hour TTL
- **Cold data** (monthly reports): 24-hour TTL
- **User sessions**: 8-hour TTL (for QuickSight)
- Invalidation: Manually via Lambda on ETL completion

**Cost**: ~2,000 MRU/month

---

### 5. AWS QuickSight (BI Tool)

**Deployment Model**: Enterprise Edition

- Pro users: 50
- Readers (unlimited): Executive suite + all managers

**Dashboards** (5-6 key questions):

1. **Executive Daily** (real-time refresh)
   - YoY/MoM volume comparison
   - Success rate gauge
   - Top 5 merchants
2. **Operational** (hourly refresh)
   - 24-hour transaction heatmap
   - Failure reasons (drill-down)
   - Channel distribution
3. **Geographic** (daily refresh)
   - Wilaya performance map
   - Top agencies (mobile-optimized)

**Security**:

- **Cognito SAML SSO**: Office 365 integration
- **RLS Policies**:
  ```sql
  IF user @role = 'AGENCY_MANAGER'
    THEN show only transactions WHERE agency_id IN (user's agencies)
  ```
- **Column masking**: PII fields redacted for analysts

**Cost**: ~3,000 MRU/month (50 Pro users × 60 MRU/user)

---

### 6. Cognito (Identity & Access Management)

**User Pool**:

- Authentication: SAML 2.0 + email/SMS MFA
- Groups: `dg_team`, `finance`, `analysts`, `viewers`
- Attribute mapping: `department` → Group assignment

**Application Clients**:

- QuickSight (SSO)
- Redshift (IAM auth)
- Custom BI tools

**Session Management**:

- Access token: 1 hour
- Refresh token: 7 days
- Logout: Auto after 8 hours of inactivity

---

### 7. Monitoring & Governance

**CloudWatch Dashboards**:

```
Real-time metrics:
├─ Redshift: CPU%, memory, queue depth
├─ S3: Object count, bucket size, 4xx errors
├─ Cognito: Login attempts, MFA challenges
├─ QuickSight: Active sessions, query duration
└─ Lambda: Duration, errors, throttling
```

**Alarms** (SNS → Slack + PagerDuty):

- ⚠️ **Warning** (yellow): Redshift CPU > 75% for 10 min
- 🔴 **Critical** (red): Query timeout, failed ETL, unauthorized access

**CloudTrail Audit Logs**:

- Who: userIdentity.principalId
- What: getQueryResults, modifyDBCluster
- When: eventTime (UTC)
- Where: sourceIPAddress
- Result: errorCode (if failed)

Example query:

```sql
SELECT
    useridentity.principalid,
    eventsource,
    eventname,
    COUNT(*) as count
FROM cloudtrail_logs
WHERE eventtime > '2026-04-20'
GROUP BY 1, 2, 3
HAVING COUNT(*) > 100  -- Unusual activity
```

---

## Data Quality & Governance

### Data Quality Framework

| Check                 | Tool         | Frequency     | Owner           |
| --------------------- | ------------ | ------------- | --------------- |
| PII detection         | Glue Macie   | Weekly        | Data Governance |
| Schema drift          | Glue Crawler | Daily         | Data Eng        |
| Freshness             | dbt test     | Every ETL run | Data Eng        |
| Uniqueness            | dbt test     | Every ETL run | Data Eng        |
| Referential integrity | dbt test     | Every ETL run | Data Eng        |
| Anomaly detection     | Redshift SQL | Daily         | Analytics       |

### Compliance & Regulation

**GDPR** (if applicable):

- ✅ PII masking in BI tools
- ✅ Audit trail of data access (CloudTrail)
- ✅ Data retention policy (Lifecycle: 7 years →Archive)
- ✅ Right to deletion (row-level purge via dbt)

**Data Dictionary** (dbt docs):

- Auto-generated schema documentation
- Column descriptions, business logic
- Lineage: Which queries fed this metric?
- Accessible via: `https://dbt-docs.nafad-pay.com`

---

## Security: Threat Model & Mitigations

### Top 3 Threats

| Threat                       | Likelihood | Impact   | Mitigation                                |
| ---------------------------- | ---------- | -------- | ----------------------------------------- |
| **Analyst exfiltrates dump** | Medium     | High     | Quota limits, audit logging, IP allowlist |
| **Credential leaked**        | Medium     | Critical | IAM auth (no passwords), rotation, MFA    |
| **Query runaway costs**      | High       | Medium   | Query monitoring rules, kill after 5 min  |

### Mitigations

1. **Export Quotas**:

   ```sql
   -- No single export > 100 MB
   -- No user exports > 1 GB/day
   -- All exports logged & auditable
   ```

2. **IP Allowlist**:
   - QuickSight: Only from corporate network
   - Redshift: Only from QuickSight + dbt cloud

3. **Session Isolation**:
   - Each user session: Unique temp credentials
   - Token expires: 1 hour
   - Auto-logout: 8 hours inactivity

---

## Cost Summary (Monthly)

| Component           | Units             | Cost                  |
| ------------------- | ----------------- | --------------------- |
| Redshift Serverless | 100 RPU-hours     | 8,000 MRU             |
| QuickSight          | 50 Pro users      | 3,000 MRU             |
| S3 Data Lake        | 10 TB             | 500 MRU               |
| Glue ETL            | 100 DPU-hours     | 1,000 MRU             |
| ElastiCache         | 3 nodes           | 2,000 MRU             |
| Cognito             | 10K MAU           | 200 MRU               |
| CloudWatch          | Logs + Dashboards | 500 MRU               |
| Data Transfer       | Inter-AZ          | 300 MRU               |
| **TOTAL**           |                   | **~15,500 MRU/month** |

---

## Operational Runbook

### Daily

- [ ] Monitor Redshift CPU/memory (CloudWatch)
- [ ] Check failed ETL jobs (Glue logs)
- [ ] Review unusual queries (CloudTrail)

### Weekly

- [ ] Test backup restore
- [ ] Review cost trends (Cost Explorer)
- [ ] Rotate credentials
- [ ] Macie PII scan results

### Monthly

- [ ] Security patch Redshift
- [ ] dbt documentation review
- [ ] Compliance checklist
- [ ] Capacity planning (add nodes?)

### Quarterly

- [ ] Security audit (CloudTrail + GuardDuty findings)
- [ ] Performance tuning (index optimization)
- [ ] SLA review with business

---

## Migration Path: Early Stage → At Scale

| Phase    | Timeline | Action                       | Cost Jump |
| -------- | -------- | ---------------------------- | --------- |
| Early    | Week 1-2 | RDS PostgreSQL + Metabase    | ~600 MRU  |
| —        | Week 3-4 | Migrate data to Redshift     | —         |
| At Scale | Week 5+  | Full multi-AZ, dbt, SSO, RLS | ~15K MRU  |

---

## Conclusion

✅ **At Scale is production-ready for**:

- 10,000+ concurrent users
- 100M+ fact records
- Real-time + historical analytics
- Regulatory compliance (audit trail, masking)
- 99.9% availability SLA

🔒 **Security-first design**:

- Zero-trust architecture (IAM for everything)
- Defense in depth (network + application + data)
- Continuous monitoring & alerting

📈 **Scalable by nature**:

- Redshift auto-scales to demand
- ElastiCache for hot data
- dbt for reproducible transformations
