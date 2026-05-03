# NAFAD PAY G4 — Architecture AWS à l'Échelle
> Data Warehouse Analytics & BI · Région cible : `eu-west-3` (Paris)

---

## Table des matières
1. [Comparaison Redshift Serverless vs Athena](#1-comparaison-redshift-serverless-vs-athena)
2. [Séparation OLTP / DWH](#2-séparation-oltp--dwh)
3. [Architecture Réseau](#3-architecture-réseau)
4. [Sécurité & Gouvernance](#4-sécurité--gouvernance)
5. [Threat Model](#5-threat-model)
6. [Protocoles de Connexion](#6-protocoles-de-connexion)
7. [Scale & Coût](#7-scale--coût)
8. [Fraîcheur des Données](#8-fraîcheur-des-données)

---

## 1. Comparaison Redshift Serverless vs Athena

### Matrice de décision

| Critère | Redshift Serverless | Athena + S3 Parquet |
|---|---|---|
| **Requêtes interactives** | Sub-seconde (cache + MPP) | 2 – 30 secondes |
| **Modèle de facturation** | $0,36/RPU-heure (min 60s) | $5/TB scanné |
| **Coût pour 100k tx/an** | ~$15–40/mois (8 RPU) | ~$0,02/requête |
| **Concurrence** | 50+ requêtes simultanées | Limitée (quota API) |
| **Row-Level Security natif** | ✅ Redshift RLS | ❌ (Lake Formation requis) |
| **Column Masking natif** | ✅ Dynamic Data Masking | ❌ (Lake Formation requis) |
| **Maintenance** | Zéro | Zéro |
| **Matérialized Views** | ✅ Auto-refresh | ❌ |
| **JDBC/ODBC standard** | ✅ | ❌ (driver Athena requis) |
| **Seuil de rentabilité** | > 5 utilisateurs BI concurrents | < 1 TB, requêtes rares |

### Recommandation pour NAFAD PAY

```
Architecture hybride :

┌──────────────────────────────────────────────────────┐
│  Dashboard DG + Chefs d'agence (interactif)          │
│  → Redshift Serverless                               │
│    RPU min : 8  │  RPU max cap : 64                  │
│    Raison : sub-seconde, RLS/DDM natif, concurrent   │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  Analyses ad-hoc, exports historiques (> 6 mois)     │
│  → Athena sur S3 Parquet (Glacier Instant Retrieval) │
│    Raison : coût minimal, requêtes occasionnelles    │
└──────────────────────────────────────────────────────┘
```

**Règle de basculement :** Si le volume dépasse 1 TB ou si le nombre de requêtes BI quotidiennes dépasse 200, migrer tout sur Redshift Serverless.

---

## 2. Séparation OLTP / DWH

### Principe

Une requête analytique lourde (`GROUP BY wilaya`, scan 100k lignes) ne doit **jamais** bloquer un paiement en cours. La séparation est physique et réseau — deux VPC distincts, zéro connexion directe.

```
┌─────────────────────────────────────────────────────────┐
│  VPC-PROD  (G1 — OLTP)          eu-west-3               │
│  ┌─────────────────────┐                                │
│  │  Aurora PostgreSQL   │  ← transactions temps réel   │
│  │  (NAFAD PAY OLTP)   │                                │
│  └──────────┬──────────┘                                │
│             │ DMS CDC (binlog replication)              │
│             │ Latence : < 1 min                        │
└─────────────┼───────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────┐
│  S3 Landing Zone  (zone neutre, compte AWS séparé)      │
│  s3://nafad-pay-landing/cdc/YYYY/MM/DD/HH/              │
│  Format : Parquet (SNAPPY), partitionné par date        │
└──────────────────────────┬──────────────────────────────┘
                           │ Glue ETL Job (toutes les 5min)
                           ▼
┌─────────────────────────────────────────────────────────┐
│  VPC-DWH  (G4 — Analytics)      eu-west-3               │
│  ┌──────────────────────────┐                           │
│  │  Redshift Serverless     │  ← requêtes analytiques  │
│  │  Namespace : nafad-dwh   │                           │
│  └──────────────────────────┘                           │
└─────────────────────────────────────────────────────────┘
```

### Règles d'isolation

| Règle | Implémentation |
|---|---|
| Pas de connexion directe DWH → OLTP | Security Group: aucune règle inbound depuis VPC-PROD |
| CDC unidirectionnel uniquement | DMS en mode lecture seule sur Aurora (replica endpoint) |
| S3 Landing Zone en compte séparé | Cross-account role avec politique `s3:PutObject` seulement |
| Quota analytique isolé | Redshift WLM queue séparée, RPU max cappé |

---

## 3. Architecture Réseau

```
Internet
    │
    ▼
┌───────────────────────────────────────┐
│  Route 53  (nafad-analytics.internal) │
└──────────────────┬────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│  Public Subnet (eu-west-3a / 3b)                         │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │  ALB (Application Load Balancer)                │    │
│  │  HTTPS :443 — Certificat ACM                    │    │
│  │  → Redirect HTTP → HTTPS                        │    │
│  └────────────────────┬────────────────────────────┘    │
│                       │ Cognito Authorizer               │
│  ┌────────────────────▼────────────────────────────┐    │
│  │  Amazon Cognito User Pool                       │    │
│  │  SSO SAML (Azure AD / Google Workspace)         │    │
│  │  MFA obligatoire pour rôle DG / chef d'agence   │    │
│  └────────────────────────────────────────────────-┘    │
└─────────────────────────────────────────────────────────┘
                   │ Token JWT validé
                   ▼
┌──────────────────────────────────────────────────────────┐
│  Private Subnet (eu-west-3a / 3b)                        │
│                                                          │
│  ┌─────────────────────────────────┐                    │
│  │  ECS Fargate — Metabase         │                    │
│  │  Task CPU: 1 vCPU / 2 GB RAM    │                    │
│  │  Auto-scaling : 1–4 tasks       │                    │
│  │  IAM Role → GetClusterCreds     │                    │
│  └────────────────┬────────────────┘                    │
│                   │ JDBC TLS (port 5439)                 │
│                   │ Enhanced VPC Routing                 │
│                   ▼                                      │
│  ┌─────────────────────────────────┐                    │
│  │  Redshift Serverless            │                    │
│  │  Namespace : nafad-dwh          │                    │
│  │  Workgroup : nafad-wg           │                    │
│  │  Base RPU : 8  │  Max RPU : 64  │                    │
│  └────────────────┬────────────────┘                    │
│                   │                                      │
│  ┌────────────────▼────────────────┐                    │
│  │  VPC Endpoint S3 (Gateway)      │                    │
│  │  → s3://nafad-pay-landing/      │                    │
│  └─────────────────────────────────┘                    │
│                                                          │
│  ┌─────────────────────────────────┐                    │
│  │  ElastiCache Redis (Cluster)    │                    │
│  │  → Compteurs live tx/seconde    │                    │
│  └─────────────────────────────────┘                    │
└──────────────────────────────────────────────────────────┘
```

### Points clés réseau

- **Enhanced VPC Routing** : tout le trafic `COPY`/`UNLOAD` Redshift transite par le VPC (jamais par l'internet public). Obligatoire pour la conformité.
- **VPC Endpoint S3 (Gateway)** : trafic S3 → Redshift sans traverser l'internet. Coût : $0.
- **Security Groups** : Metabase → Redshift uniquement sur port 5439 depuis le Security Group ECS. Redshift n'est pas accessible depuis l'extérieur du VPC.
- **NACLs** : deny all inbound sauf port 443 sur ALB, deny all outbound sauf réponses établies.

---

## 4. Sécurité & Gouvernance

### 4.1 Row-Level Security — Redshift RLS

Un chef d'agence ne voit que les transactions de sa wilaya.

```sql
-- Créer les rôles
CREATE ROLE chef_agence;
CREATE ROLE analyste_junior;
CREATE ROLE directeur_general;

-- Politique RLS : filtrage par wilaya
CREATE RLS POLICY wilaya_rls_policy
WITH (wilaya_id INT)
USING (wilaya_id = (
    SELECT wilaya_id FROM auth.user_profiles
    WHERE redshift_user = CURRENT_USER
));

-- Attacher la politique aux tables sensibles
ATTACH RLS POLICY wilaya_rls_policy
    ON fact_transactions TO ROLE chef_agence;

ATTACH RLS POLICY wilaya_rls_policy
    ON dim_user TO ROLE chef_agence;

-- Activer RLS sur les tables
ALTER TABLE fact_transactions ROW LEVEL SECURITY ON;
ALTER TABLE dim_user ROW LEVEL SECURITY ON;

-- Le DG voit tout (BYPASS)
GRANT IGNORE RLS ON TABLE fact_transactions TO ROLE directeur_general;
```

### 4.2 Column-Level Masking — Dynamic Data Masking

Les analystes juniors ne voient jamais le téléphone, NNI ou email en clair.

```sql
-- Masque partiel pour phone : "***-****-1234"
CREATE MASKING POLICY mask_phone
WITH (phone VARCHAR(30))
USING (
    CASE WHEN HAS_ROLE('directeur_general') OR HAS_ROLE('dpo')
         THEN phone
         ELSE CONCAT('***-****-', RIGHT(phone, 4))
    END
);

-- Masque total pour NNI
CREATE MASKING POLICY mask_nni
WITH (nni VARCHAR(20))
USING (
    CASE WHEN HAS_ROLE('directeur_general') OR HAS_ROLE('dpo')
         THEN nni
         ELSE '**********'
    END
);

-- Masque email : garder le domaine seulement
CREATE MASKING POLICY mask_email
WITH (email VARCHAR(200))
USING (
    CASE WHEN HAS_ROLE('directeur_general') OR HAS_ROLE('dpo')
         THEN email
         ELSE CONCAT('****@', SPLIT_PART(email, '@', 2))
    END
);

-- Attacher aux colonnes
ATTACH MASKING POLICY mask_phone  ON dim_user(phone)  TO ROLE analyste_junior;
ATTACH MASKING POLICY mask_nni    ON dim_user(nni)    TO ROLE analyste_junior;
ATTACH MASKING POLICY mask_email  ON dim_user(email)  TO ROLE analyste_junior;
```

### 4.3 AWS Glue Data Catalog + Amazon Macie

```
S3 Landing Zone
    │
    ├── Glue Crawler (schedule : toutes les heures)
    │   → Catalogue toutes les tables Parquet
    │   → Met à jour le schéma automatiquement
    │
    ├── Macie (scan continu)
    │   → Détection PII automatique : phone, email, NNI, IBAN
    │   → Tag S3 Object : pii=true / pii_type=PHONE_NUMBER
    │   → Alerte SNS si nouveau fichier PII non tagué détecté
    │
    └── Lake Formation
        → Fine-grained access control sur le catalogue Glue
        → Colonnes PII taguées → accès restreint aux rôles DPO
```

**Tags obligatoires sur toutes les ressources AWS :**

| Tag | Valeur exemple |
|---|---|
| `Project` | `nafad-pay` |
| `Team` | `g4-analytics` |
| `DataClassification` | `PII` / `INTERNAL` / `PUBLIC` |
| `Environment` | `prod` / `staging` |
| `CostCenter` | `analytics-bi` |

### 4.4 IAM — Principe du moindre privilège

| Entité | IAM Role / Policy | Permissions |
|---|---|---|
| ECS Fargate (Metabase) | `nafad-metabase-role` | `redshift:GetClusterCredentials`, `redshift-serverless:GetCredentials` uniquement |
| Glue ETL Job | `nafad-glue-etl-role` | `s3:GetObject` (landing), `s3:PutObject` (processed), `redshift-data:ExecuteStatement` |
| DMS Replication | `nafad-dms-role` | Lecture seule sur Aurora replica |
| Analyste (humain) | `nafad-analyst-role` | `redshift-data:ExecuteStatement` + accès Athena (quota) |
| Jamais | — | Credentials long-term sur des comptes partagés |

### 4.5 Redshift Query Monitoring Rules (QMR)

```sql
-- Règle 1 : tuer toute requête dépassant 5 minutes
CREATE QUERY MONITORING RULE kill_long_queries
WITH (
    predicate  = 'query_execution_time > 300',   -- secondes
    action     = 'abort',
    priority   = 'high'
);

-- Règle 2 : limiter les scans massifs (anti-exfiltration)
CREATE QUERY MONITORING RULE limit_full_scan
WITH (
    predicate  = 'scan_row_count > 500000',
    action     = 'log',
    priority   = 'normal'
);

-- Règle 3 : alerter sur les requêtes sans filtre WHERE
CREATE QUERY MONITORING RULE alert_no_filter
WITH (
    predicate  = 'scan_row_count > 90000 AND return_row_count > 10000',
    action     = 'log',
    priority   = 'normal'
);
```

### 4.6 Audit & CloudTrail

- **CloudTrail** : activé sur toutes les régions, logs vers S3 `s3://nafad-audit-logs/cloudtrail/`
- **S3 Object-level logging** : activé sur le bucket landing zone (tout `GetObject` est tracé)
- **Redshift Audit Logging** : connexions + requêtes SQL vers S3 `s3://nafad-audit-logs/redshift/`
- **Export CSV limité** : QMR limite `return_row_count` + policy S3 bloque les `UNLOAD` vers des buckets non approuvés

---

## 5. Threat Model

### Threat 1 — Analyste qui exfiltre un dump complet

**Scénario :** Un analyste junior exécute `SELECT * FROM dim_user` ou `UNLOAD` vers son bucket S3 personnel pour exporter 10 000 NNI/téléphones.

| # | Mitigation | Implémentation |
|---|---|---|
| M1 | **Column masking DDM** — même si la requête passe, les colonnes PII renvoient `***-****-1234` | `ATTACH MASKING POLICY` sur `nni`, `phone`, `email` pour le rôle `analyste_junior` |
| M2 | **QMR + quota de lignes** — toute requête retournant > 10 000 lignes est loguée + alertée, > 50 000 lignes est tuée | `CREATE QUERY MONITORING RULE limit_full_scan` (voir §4.5) |
| M3 | **CloudTrail + Macie alert** — si un fichier contenant des PII apparaît dans un bucket non approuvé, Macie déclenche une alerte SNS en < 5 min | Macie Job sur tous les buckets S3 du compte + EventBridge rule → SNS → Slack |

---

### Threat 2 — Token / session BI qui fuite

**Scénario :** Un token Cognito ou des credentials JDBC Metabase sont exposés dans un log, un repo Git, ou volés via phishing.

| # | Mitigation | Implémentation |
|---|---|---|
| M1 | **Credentials IAM temporaires** — Metabase utilise `GetClusterCredentials` (durée de vie 15 min), jamais de mot de passe statique Redshift | IAM Role ECS → `redshift:GetClusterCredentials` avec expiration 900 secondes |
| M2 | **Rotation automatique des secrets** — tous les secrets (DB, API keys) passent par AWS Secrets Manager avec rotation automatique tous les 30 jours | `aws secretsmanager rotate-secret --rotation-rules AutomaticallyAfterDays=30` |
| M3 | **SSO Cognito + MFA obligatoire** — si un token JWT Cognito fuite, l'attaquant ne peut pas le réutiliser sans le 2e facteur MFA ; révocation immédiate possible via `AdminUserGlobalSignOut` | Cognito User Pool : MFA = `REQUIRED` pour les groupes DG/chef-agence ; token expiry = 1h |

---

### Threat 3 — Requête runaway qui coûte 500 $

**Scénario :** Une requête mal écrite (jointure cartésienne, pas de filtre sur la date) fait scaler Redshift Serverless à 512 RPU pendant 2h → facture $368 pour une seule requête.

| # | Mitigation | Implémentation |
|---|---|---|
| M1 | **RPU max cap** — limiter le scale automatique à 64 RPU (plafond configurable dans le Workgroup Redshift Serverless) | `aws redshift-serverless update-workgroup --max-capacity 64` |
| M2 | **WLM + query timeout** — toute requête dépasse 5 min est tuée automatiquement (§4.5 QMR) ; les analytess sont dans une queue `analyst_queue` avec concurrency = 3 | `CREATE QUERY MONITORING RULE kill_long_queries` + WLM config JSON |
| M3 | **AWS Cost Anomaly Detection + alerte billing** — alerte automatique si la consommation Redshift dépasse $20/jour (seuil nominal : $5/jour) | AWS Cost Anomaly Detection : service = Redshift, threshold = $20 → SNS → email DBA |

---

## 6. Protocoles de Connexion

```
Utilisateur interne
    │
    │  HTTPS (TLS 1.3)
    ▼
ALB → Cognito (OIDC/SAML)
    │  JWT Token (exp: 1h)
    ▼
ECS Fargate — Metabase
    │
    │  (1) Appel IAM : AssumeRole → GetClusterCredentials
    │      → credentials temporaires (15 min, user=metabase_svc)
    │
    │  (2) JDBC over TLS 1.2+
    │      jdbc:redshift://nafad-wg.eu-west-3.redshift-serverless.amazonaws.com:5439/dwh
    │      ?ssl=true&sslfactory=com.amazon.redshift.ssl.NonValidatingFactory
    │
    ▼
Redshift Serverless
    │  (require_ssl = ON dans le parameter group)
    │  (Enhanced VPC Routing : tout le trafic reste dans le VPC)
    ▼
S3 (via VPC Gateway Endpoint — jamais internet)
```

### Paramètres TLS Redshift obligatoires

```sql
-- Dans le Workgroup Redshift Serverless
-- Paramètre à activer :
-- require_ssl = true
-- Forcer TLS sur toutes les connexions entrantes

-- Vérification :
SELECT name, setting
FROM pg_settings
WHERE name = 'require_ssl';
-- Attendu : require_ssl | on
```

### Authentification IAM database credentials

```python
# Exemple Python (Metabase utilise le driver JDBC équivalent)
import boto3

client = boto3.client('redshift-serverless', region_name='eu-west-3')

response = client.get_credentials(
    workgroupName='nafad-wg',
    dbName='dwh',
    durationSeconds=900,      # 15 minutes
    dbUser='metabase_svc'
)
# response['dbPassword'] : token temporaire, expire en 15 min
# Ne jamais logger cette valeur
```

---

## 7. Scale & Coût

### 7.1 Distribution & Sort Keys

```sql
-- Clé de distribution sur transaction_date (colonne la plus filtrée)
-- Sort key composé pour les requêtes wilaya + date
CREATE TABLE fact_transactions (
    tx_pk            BIGINT IDENTITY(1,1),
    transaction_date DATE        NOT NULL,
    date_key         INT         NOT NULL,
    user_key         BIGINT      NOT NULL REFERENCES dim_user(user_key),
    merchant_key     BIGINT      NOT NULL REFERENCES dim_merchant(merchant_key),
    agency_key       BIGINT      NOT NULL REFERENCES dim_agency(agency_key),
    node_key         INT         NOT NULL REFERENCES dim_node(node_key),
    amount           NUMERIC(18,2),
    fee              NUMERIC(18,2),
    status           VARCHAR(20),
    transaction_type VARCHAR(10),
    -- ... autres colonnes
    PRIMARY KEY (tx_pk)
)
DISTSTYLE KEY
DISTKEY (transaction_date)           -- distribue uniformément sur les slices par date
COMPOUND SORTKEY (transaction_date, status, transaction_type);
-- Bénéfice : les requêtes filtrées par date (99% des cas) ne scannent
-- que les blocs pertinents (zone map pruning)

-- Tables de dimension : DISTSTYLE ALL (petites tables, < 10 MB)
ALTER TABLE dim_date         DISTSTYLE ALL;
ALTER TABLE dim_user         DISTSTYLE ALL;
ALTER TABLE dim_merchant     DISTSTYLE ALL;
ALTER TABLE dim_agency       DISTSTYLE ALL;
ALTER TABLE dim_node         DISTSTYLE ALL;
```

### 7.2 Materialized Views pour les KPIs fréquents

```sql
-- MV 1 : KPIs journaliers (rafraîchie toutes les 5 min par Lambda)
CREATE MATERIALIZED VIEW mv_daily_kpis
AUTO REFRESH NO AS
SELECT
    d.full_date,
    d.year,
    d.month,
    d.day_of_month,
    COUNT(*)                                                    AS nb_transactions,
    ROUND(SUM(f.amount), 0)                                     AS volume_mru,
    ROUND(SUM(f.fee), 0)                                        AS frais_mru,
    SUM(CASE WHEN f.status = 'SUCCESS' THEN 1 ELSE 0 END)       AS nb_succes,
    ROUND(SUM(CASE WHEN f.status='SUCCESS' THEN 1 ELSE 0 END)
          * 100.0 / NULLIF(COUNT(*), 0), 1)                     AS taux_succes_pct
FROM fact_transactions f
JOIN dim_date d ON f.date_key = d.date_key
WHERE f.is_conflict = FALSE
GROUP BY d.full_date, d.year, d.month, d.day_of_month;

-- MV 2 : Volume par wilaya (rafraîchie toutes les 5 min)
CREATE MATERIALIZED VIEW mv_wilaya_volume
AUTO REFRESH NO AS
SELECT
    u.wilaya_id,
    u.wilaya_name,
    d.full_date,
    COUNT(*)                    AS nb_transactions,
    ROUND(SUM(f.amount), 0)     AS volume_mru
FROM fact_transactions f
JOIN dim_user u  ON f.user_key  = u.user_key  AND u.is_current = TRUE
JOIN dim_date d  ON f.date_key  = d.date_key
WHERE f.is_conflict = FALSE
GROUP BY u.wilaya_id, u.wilaya_name, d.full_date;

-- Refresh déclenché par EventBridge toutes les 5 min
-- (Lambda exécute : REFRESH MATERIALIZED VIEW mv_daily_kpis)
```

### 7.3 ElastiCache Redis — Compteurs live

```
Kinesis Data Stream (nafad-tx-stream)
    │  PutRecord à chaque transaction committed (G1 push)
    │
    ▼
Lambda (nafad-redis-counter)
    │  Triggered : batch size = 100, window = 5s
    │
    ▼
ElastiCache Redis (Cluster Mode, 1 shard, r7g.large)
    │
    ├── INCR  nafad:tx:count:live          → compteur brut (reset toutes les heures)
    ├── INCR  nafad:tx:count:today         → total du jour (reset à minuit)
    ├── INCRBY nafad:tx:volume:today {amount}
    ├── ZADD  nafad:tx:per_wilaya {score=amount} {member=wilaya_id}
    └── LPUSH nafad:tx:last5min  {timestamp}  (liste glissante 5 min)
        → LLEN nafad:tx:last5min = tx/5min

-- Le dashboard lit Redis pour le compteur live (latence < 1ms)
-- Le dashboard lit Redshift MV pour les KPIs historiques (latence < 500ms)
```

### 7.4 Estimation des coûts mensuels

| Service | Usage estimé | Coût/mois |
|---|---|---|
| Redshift Serverless | 8 RPU × 8h/jour × 30j | ~$70 |
| ECS Fargate (Metabase) | 1 vCPU / 2 GB × 24h | ~$15 |
| S3 (landing + processed) | 50 GB + requêtes | ~$2 |
| Glue ETL (5 min interval) | 288 runs/jour × 0,1 DPU × 30j | ~$8 |
| ElastiCache Redis | r7g.large × 1 shard | ~$50 |
| ALB | 1 LB + trafic | ~$20 |
| Kinesis Data Streams | 1 shard, 100k msg/jour | ~$2 |
| CloudTrail + S3 audit logs | 5 GB logs/mois | ~$3 |
| **Total estimé** | | **~$170/mois** |

**Optimisation Reserved Nodes :** Si l'usage Redshift est prévisible (> 8h/jour, 12 mois), les Reserved Nodes offrent **~40 % de réduction** → ~$42/mois au lieu de $70.

---

## 8. Fraîcheur des Données

### Les trois vues de données

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  VUE 1 — LIVE COUNTER  (latence < 1 seconde)                   │
│                                                                 │
│  G1 OLTP → Kinesis → Lambda → Redis                            │
│  Contenu : tx count, volume du jour, tx/min (glissant)         │
│  Garantie : TOUTES les transactions reçues (inc. PENDING)       │
│  Usage : widget "transactions aujourd'hui" sur dashboard DG     │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  VUE 2 — NEAR-REAL-TIME  (latence ~5 minutes)                  │
│                                                                 │
│  G1 OLTP → DMS CDC → S3 Landing → Glue (5 min) → Redshift     │
│  Contenu : toutes les transactions commitées du jour courant    │
│  Garantie : transactions validées uniquement (pas PENDING)      │
│  Usage : KPIs J courant dans Metabase, alertes wilaya           │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  VUE 3 — BATCH J+1  (latence ~12 heures)                       │
│                                                                 │
│  Glue ETL Full (nuit, 02h00) → Redshift + VACUUM + ANALYZE     │
│  Contenu : données J-1 complètes, déduplicquées, validées      │
│  Garantie : source de vérité pour le reporting officiel         │
│  Usage : rapport mensuel DG, exports comptables, KPI historique │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Réconciliation des trois vues

Le problème de cohérence : Redis compte 1 050 transactions à 14h, mais Redshift near-RT n'en montre que 1 031. Pourquoi ?

```
Explication et réconciliation :

Redis (live)          1 050 tx  ← toutes events Kinesis (inc. PENDING + FAILED en transit)
Redshift near-RT      1 031 tx  ← seulement les tx commitées dans Aurora avant le dernier
                                   flush Glue (lag 5 min + délai de commit OLTP)
Redshift batch J+1    1 049 tx  ← total final après déduplication (1 CONFLICT résolu)

Écart acceptable :
  Redis - Redshift_NRT  ≤ 5 min de transactions + transactions PENDING en vol
  Redis - Redshift_J+1  ≤ 1 tx (CONFLICT résolu) → tolérable

Règle d'affichage dans le dashboard :
  ┌──────────────────────────────────────────────────────┐
  │ Widget "Aujourd'hui"  → source Redis (live)          │
  │ Widget "Ce mois"      → source Redshift MV near-RT   │
  │ Widget "Historique"   → source Redshift batch J+1    │
  │                                                      │
  │ Badge d'avertissement si Redis > Redshift_NRT × 1.02 │
  │ (écart > 2% = anomalie à investiguer)                │
  └──────────────────────────────────────────────────────┘
```

### Schéma de réconciliation à minuit

```
00:00  ──► Redis : snapshot tx_count_today → S3 (archivage)
           Redis : RESET compteurs live (DEL nafad:tx:count:today)

02:00  ──► Glue ETL Full : charge toutes les tx du jour J-1
           VACUUM + ANALYZE sur fact_transactions
           REFRESH MATERIALIZED VIEW mv_daily_kpis
           REFRESH MATERIALIZED VIEW mv_wilaya_volume

02:30  ──► Lambda de réconciliation :
           Compare Redis snapshot (J-1) vs Redshift batch (J-1)
           Si écart > 0.5% → alerte SNS → DBA investigate
           Sinon → log "reconciliation OK" dans CloudWatch

06:00  ──► Rapport automatique envoyé au DG par email (SES)
           Source : Redshift batch J+1 (données validées)
```

---

## Schéma d'ensemble

```
┌──────────────────────────────────────────────────────────────────────┐
│  G1 OLTP  (Aurora PostgreSQL — VPC-PROD)                             │
│                                                                      │
│  Transactions temps réel                                             │
│       │                      │                                       │
│       │ DMS CDC              │ Kinesis PutRecord                    │
│       │ (< 1 min)            │ (< 1 sec)                            │
└───────┼──────────────────────┼───────────────────────────────────────┘
        │                      │
        ▼                      ▼
┌───────────────┐    ┌──────────────────────────────────────────────┐
│  S3 Landing   │    │  Kinesis Data Stream                         │
│  (Parquet)    │    │       │                                      │
│       │       │    │       ▼                                      │
│  Glue ETL     │    │  Lambda → ElastiCache Redis                  │
│  (5 min)      │    │          (compteurs live)                    │
│       │       │    │                │                             │
└───────┼───────┘    └───────-────────┼────────────────────────────┘
        │                             │
        ▼                             │
┌───────────────────────────────────────────────────────────────────┐
│  VPC-DWH                                                          │
│                                                                   │
│  Redshift Serverless ◄──────────── MV refresh (Lambda 5 min)     │
│  (fact + dims + MVs)                                              │
│       │                                                           │
│       │  JDBC TLS + IAM Credentials                               │
│       ▼                                                           │
│  ECS Fargate — Metabase                                           │
│       │                                                           │
│       │  HTTPS + Cognito SSO                                      │
│       ▼                                                           │
│  ALB → Internet → Utilisateurs internes (DG, chefs d'agence)     │
└───────────────────────────────────────────────────────────────────┘
```
