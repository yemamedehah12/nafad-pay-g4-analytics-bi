# Document d'Architecture — G4 Analytics & BI — At Scale
**Version** : 2.0 (Expert)  **Région** : `eu-west-3` Paris  **Date** : 2026-05-02

---

## 1. Contexte & Contraintes

| Dimension | Valeur cible |
|---|---|
| Transactions/mois | 5 M (≈ 2 tx/s en moyenne, 50 tx/s en pic) |
| Utilisateurs actifs | 500 000 (×50 par rapport au dataset initial) |
| Volume DWH | 1 TB/an (fact_transactions + historique SCD2) |
| SLA disponibilité | 99,9 % (43 min/mois de downtime toléré) |
| RPO | 15 minutes (batch J+1), 5 min (near-realtime) |
| RTO | 30 minutes |
| Latence p50 dashboard | < 500 ms (requête sur MV) |
| Latence p99 dashboard | < 5 s (requête analytique complexe) |
| Budget mensuel | < 400 USD (hors coûts d'ingestion G3) |
| Conformité | BCM Mauritanie, GDPR-like, PII 10k→500k users |

**Contrainte incompressible** : latence Nouakchott↔Paris = 40–60 ms. Les dashboards sont consultés depuis Mauritanie → CloudFront edge caching obligatoire sur les réponses Superset statiques.

---

## 2. Diagramme d'Architecture (C4 — Niveau 2 Containers)

```
┌─────────────────────────────────────────────────────────────────────────┐
│  INTERNET (Analystes, DG, Chefs d'agence — depuis Mauritanie)           │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ HTTPS (TLS 1.3)
                     ┌──────────▼──────────┐
                     │   CloudFront CDN    │  Cache des assets statiques
                     │   + WAF (OWASP)     │  + Rate limiting 1000 req/min/IP
                     └──────────┬──────────┘
                                │
                     ┌──────────▼──────────┐
                     │   ALB (Application  │  HTTPS → HTTP interne
                     │   Load Balancer)    │  Listener rules par path
                     │   Subnet PUBLIC     │
                     └──────────┬──────────┘
                                │
              ┌─────────────────▼──────────────────┐
              │  ECS Fargate (Superset)             │  Subnet PRIVÉ
              │  Task: 2 vCPU / 4 GB               │  Multi-AZ (3a + 3b)
              │  Auto Scaling: 1→6 tasks            │
              │  IAM Task Role: redshift:GetCredentials │
              └─────────┬──────────────┬────────────┘
                        │ JDBC/TLS     │ ElastiCache
              ┌─────────▼──────┐  ┌───▼────────────┐
              │ Redshift        │  │ ElastiCache     │
              │ Serverless      │  │ Redis (cluster) │
              │ (Namespace DWH) │  │ Compteurs live  │
              │ Subnet PRIVÉ    │  │ Subnet PRIVÉ    │
              │ Enhanced VPC    │  └────────────────┘
              │ Routing ON      │
              └─────────┬───────┘
                        │ PrivateLink / VPC Peering
              ┌─────────▼────────────────────────────────────────┐
              │  COUCHE DATA (Inputs depuis G3)                   │
              │                                                   │
              │  S3 Gold ──► Glue ETL ──► Redshift COPY          │
              │  (Parquet)    (dbt-run)    (staging → marts)      │
              │                                                   │
              │  Kinesis ──► Lambda ──► ElastiCache Redis         │
              │  (stream)    (consumer)   (compteurs live)        │
              └──────────────────────────────────────────────────┘

[SÉPARATION OLTP / DWH — OBLIGATOIRE]
G1 RDS PostgreSQL (OLTP)  ←──── AUCUN LIEN DIRECT ────→  G4 Redshift (DWH)
         │                                                      ▲
         │ CDC via AWS DMS                                      │
         └──── G3 Bronze/Silver/Gold (S3) ─────────────────────┘
```

---

## 3. Choix Techniques & ADR-Lite

### ADR-1 : Redshift Serverless vs Athena

| Critère | Redshift Serverless | Athena |
|---|---|---|
| Requêtes interactives (<1s) | ✅ Sub-second sur MV | ❌ 3-10s minimum |
| Coût à faible usage | ❌ $0.36/RPU-h (min 8 RPU) | ✅ $5/TB scanné |
| SQL analytique complexe | ✅ Window functions, ROLLUP | ✅ Presto-based |
| Concurrence 10+ utilisateurs | ✅ WLM intégré | ❌ Throttling possible |
| Maintenance | ✅ Serverless | ✅ Serverless |
| COPY depuis S3 | ✅ Natif rapide | N/A (query only) |

**Décision** : **Redshift Serverless** — les 10 analystes + DG nécessitent des requêtes sub-second sur les dashboards. Athena serait choisi si le volume restait < 100 GB et l'équipe < 3 analystes.

**Seuil de bascule vers Athena** : Si utilisation < 20h/mois et pas de SLA latence → économie de ~$200/mois.

### ADR-2 : Apache Superset vs Metabase vs QuickSight

| Critère | Superset | Metabase | QuickSight |
|---|---|---|---|
| RLS natif | ✅ Row-Level Security | ⚠️ Limité | ✅ Natif AWS |
| Open source | ✅ | ✅ | ❌ $18/user/mois |
| SQL natif | ✅ SQLLab | ⚠️ | ⚠️ |
| Contrôle PII | ✅ Via rôles DB | ❌ | ✅ Via IAM |

**Décision** : **Apache Superset** — open source, SQL complet, intégration Redshift native, RLS possible via rôles PostgreSQL/Redshift. QuickSight écarté (coût, vendor lock-in).

### ADR-3 : SCD Type 2 pour dim_user

**Décision** : Type 2 (Track Full History).  
**Alternatives** : Type 1 (overwrite), Type 3 (colonne précédente), Hybride (Type 1 attributs non-analytiques + Type 2 analytiques).  
**Pourquoi Type 2** : Obligation réglementaire fintech de reproductibilité des transactions avec les attributs valables au moment T. Un virement du 15 janvier doit toujours référencer la wilaya de l'utilisateur au 15 janvier, même s'il a déménagé en mars.

---

## 4. Flux de Données Critiques

### 4.1 Pipeline Batch J+1 (01h30–03h00)

```
01:30  EventBridge Scheduler
  └──► Step Functions (orchestration)
       ├── État 1 : ECS Task "dbt-run staging"
       │     → dbt run --models staging.*
       │     → valide les sources (dbt test)
       ├── État 2 : ECS Task "dbt-run marts"  
       │     → dbt run --models marts.*
       │     → dbt snapshot (SCD Type 2 dim_user)
       ├── État 3 : Lambda "refresh-mvs"
       │     → CALL refresh_all_materialized_views()
       └── État 4 : SNS "pipeline-success"
             → Slack/email à l'équipe G4
```

### 4.2 Near Real-Time (toutes les 5 min)

```
G3 Gold S3 ──► EventBridge S3 PutObject ──► Step Functions light
  └──► ECS Task "dbt-run --models marts.fact_transactions --full-refresh=false"
  └──► Lambda "refresh mv_daily_kpis WHERE transaction_date = TODAY"
```

### 4.3 Live Counter (Kinesis → Redis)

```
G1 OLTP ──► DMS Change Capture ──► Kinesis Data Stream
  └──► Lambda Consumer (Python, 128 MB)
       └──► ElastiCache Redis INCR nafad:live:tx_count
       └──► ElastiCache Redis INCRBYFLOAT nafad:live:volume_mru
       └──► TTL 86400s (reset auto à minuit)
```

Superset lit le compteur live via une **datasource custom** qui appelle une Lambda HTTP proxy → Redis GET.

---

## 5. Sécurité & Gouvernance AWS

### 5.1 Row-Level Security Redshift

```sql
-- Redshift : policy wilaya pour chef d'agence
CREATE RLS POLICY policy_wilaya
    USING (wilaya_id = (
        SELECT wilaya_id FROM nafad_iam_mapping
        WHERE iam_user = current_user
    ));

ATTACH RLS POLICY policy_wilaya ON fact_transactions TO ROLE role_chef_agence;
ALTER TABLE fact_transactions ROW LEVEL SECURITY ON;
```

### 5.2 Dynamic Data Masking Redshift (PII)

```sql
-- Masque phone pour les analystes juniors (Redshift DDM)
CREATE MASKING POLICY mask_phone
    WITH (phone VARCHAR(30))
    USING (
        CASE WHEN IS_MEMBER('analysts_junior')
            THEN REGEXP_REPLACE(phone, '(\+\d{3})\d+(\d{4})', '\1****\2')
        ELSE phone
        END
    );

ATTACH MASKING POLICY mask_phone ON dim_user(phone)
    TO ROLE analysts_junior PRIORITY 10;
```

### 5.3 IAM Roles (principe moindre privilège)

```
iam:role/nafad-superset-task
  → redshift:GetClusterCredentials (namespace DWH uniquement)
  → secretsmanager:GetSecretValue (arn:...:nafad/redshift/*)
  → s3:GetObject (s3://nafad-gold/* — lecture uniquement)

iam:role/nafad-etl-dbt
  → redshift:ExecuteStatement
  → s3:GetObject + s3:PutObject (buckets Bronze/Silver/Gold)
  → glue:GetTable, glue:UpdateTable

iam:role/nafad-kinesis-consumer
  → kinesis:GetRecords (stream nafad-transactions)
  → elasticache:DescribeCacheClusters (lecture seule)
```

### 5.4 Threat Model — 3 Risques Réels

#### Risque 1 : Exfiltration complète des données (10K → 500K PII)

**Scénario** : Analyste avec `SELECT *` sur `dim_user` exporte via CSV.

**Mitigations** :
1. **Dynamic Data Masking** sur phone/nni/email (Redshift DDM) — même `SELECT *` retourne des données masquées
2. **Redshift Query Monitoring Rules** : `ABORT` si `rows_returned > 50000` et `user != etl_loader`
3. **CloudTrail** : alerte SNS si `SELECT` sur `dim_user` > 1000 lignes par un compte non-ETL

```sql
-- WLM Rule anti-exfiltration
CREATE QUERY MONITORING RULE no_bulk_export
    WHEN rows_returned > 50000
    AND user_name NOT IN ('etl_loader', 'dbt_runner')
    THEN ABORT;
```

#### Risque 2 : Fuite de session Superset (token JWT volé)

**Scénario** : Cookie Superset intercepté → accès complet tableau de bord.

**Mitigations** :
1. **Cognito SSO** avec MFA obligatoire pour tous les analystes
2. **ALB OIDC integration** : Superset ne gère pas l'auth (délégué à ALB → Cognito)
3. **Session timeout** : 4h max, rotation de token à chaque requête, IP binding en option

```yaml
# ALB Listener Rule — OIDC Auth
Type: authenticate-oidc
AuthenticationRequestExtraParams:
  max_age: "14400"  # 4h
Issuer: https://cognito-idp.eu-west-3.amazonaws.com/eu-west-3_XXXXX
ClientId: !Ref SupersetAppClientId
```

#### Risque 3 : Requête runaway coûteuse (full scan 500K users × 5M tx)

**Scénario** : Analyste écrit `SELECT * FROM fact_transactions` sans WHERE → 500K RPU-secondes = $500.

**Mitigations** :
1. **WLM Queue** avec `query_execution_time > 300s → ABORT` pour le role `analysts_*`
2. **Concurrency Scaling Limit** : max 2 concurrent queries par user dans Superset
3. **Budget AWS** : alerte SNS si coût Redshift > $50/jour

```sql
-- Redshift Serverless : Resource Policy
ALTER RESOURCE POLICY SET max_query_execution_time = 300;  -- 5 min max

-- WLM pour analystes
MODIFY WLM QUEUE analyst_queue SET query_execution_time = 300;
```

---

## 6. Performance & Scale

### 6.1 Optimisations Redshift

```sql
-- Distribution key : wilaya_id (join fréquent avec dim_user)
CREATE TABLE fact_transactions (
    ...
) DISTSTYLE KEY DISTKEY(wilaya_id)
  SORTKEY(transaction_date, status);

-- Materialized view Redshift (auto-refresh)
CREATE MATERIALIZED VIEW mv_daily_kpis
AUTO REFRESH YES
AS SELECT ...;
```

### 6.2 Partitionnement PostgreSQL (local/RDS)

```sql
-- Partitionnement par mois sur fact_transactions
CREATE TABLE fact_transactions (
    ...
) PARTITION BY RANGE (transaction_date);

CREATE TABLE fact_transactions_2024_01
    PARTITION OF fact_transactions
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
-- ... repeat pour chaque mois
```

### 6.3 Réconciliation Batch + Near-RT + Live

| Vue | Fraîcheur | Mécanisme | Incohérence possible |
|---|---|---|---|
| Batch J+1 | 24h | dbt run + MV refresh | Aucune (données stables) |
| Near-RT 5min | 5 min | dbt incremental + MV partial refresh | Tx du jour partiel |
| Live counter | < 1s | Kinesis → Redis INCR | +/- 0.5% (écriture async) |

**Stratégie de réconciliation** :
- Les dashboards DG affichent le **batch J+1** pour tous les KPIs financiers (seule source fiable, CONFLICT résolus).
- Les dashboards opérationnels affichent le **near-RT** pour le jour courant avec une bannière "données provisoires — actualisées toutes les 5 min".
- Le **live counter** (tx/s) est affiché séparément comme indicateur technique, pas financier.

```python
# Lambda réconciliation : vérifier cohérence Redis vs Redshift
def check_consistency():
    redis_count = redis.get('nafad:live:tx_count')
    redshift_count = execute_sql("SELECT COUNT(*) FROM fact_transactions WHERE transaction_date = TODAY")
    delta_pct = abs(redis_count - redshift_count) / redshift_count * 100
    if delta_pct > 2.0:
        sns.publish(TopicArn=ALERT_TOPIC, Message=f"Live counter drift: {delta_pct:.1f}%")
```

---

## 7. Coûts AWS (estimation mensuelle)

| Service | Config | Coût/mois |
|---|---|---|
| Redshift Serverless | 8 RPU × 20h/jour × 30 jours = 4800 RPU-h × $0.36 | ~$173 |
| ECS Fargate Superset | 2 tasks × 2vCPU × 4GB × 720h | ~$55 |
| ElastiCache Redis | cache.t3.micro × 1 instance | ~$15 |
| ALB | 1 ALB + 20 LCU | ~$20 |
| CloudFront | 100 GB transfer (Mauritanie→Paris) | ~$12 |
| S3 Gold | 50 GB + requêtes | ~$5 |
| Glue Data Catalog | 1M objets | ~$1 |
| CloudTrail | 1 trail | ~$2 |
| Secrets Manager | 5 secrets + rotations | ~$3 |
| Kinesis | 1 shard × 720h | ~$11 |
| **TOTAL** | | **~$297/mois** |

**Optimisations coût** :
- Redshift Serverless → Reserved Nodes (1 an) si utilisation > 15h/jour : économie 30%
- ECS Fargate Spot pour les tâches dbt batch (pas de SLA stricte) : -40%
- CloudFront compression + cache agressif : -50% sur le transfer

---

## 8. Plan de Migration Early Stage → At Scale

| Étape | Action | Downtime | Effort |
|---|---|---|---|
| J1-J2 | Créer namespace Redshift Serverless, migrer schéma DDL | 0 | 1 j |
| J3 | dbt run complet depuis S3 Gold → Redshift | 0 | 0.5 j |
| J4 | Déployer ECS Fargate Superset + ALB | 0 | 1 j |
| J5 | Configurer Cognito + ALB OIDC | 30 min (migration sessions) | 1 j |
| J6 | Activer RLS + DDM Redshift | 0 (transparent) | 0.5 j |
| J7 | Déployer Kinesis consumer + Redis | 0 | 1 j |
| J8 | CloudTrail + WLM rules + Budget alerts | 0 | 0.5 j |
| **Total** | | **< 1h** | **~5.5 j** |

---

## 9. Points de Rupture & Signaux de Bascule

| Signal | Valeur seuil | Action |
|---|---|---|
| Superset p99 latence | > 10s | Ajouter tasks ECS, augmenter RPU Redshift |
| Redis memory | > 80% | Scale out Redis (cluster mode) |
| Redshift RPU-h coût | > $300/jour | Passer aux Reserved Nodes |
| S3 Gold size | > 500 GB | Activer Intelligent-Tiering + partitionnement Hive fin |
| Utilisateurs Superset | > 50 simultanés | Superset horizontal scaling (4→12 tasks) |
