# G4 - Analytics & BI Team : Data Warehouse & Dashboard

## Rôle dans l'entreprise

Vous êtes la **Data / Analytics / BI Team**. Vous fournissez les chiffres au DG et aux métiers. Un chiffre faux = décision stratégique fausse. Vous êtes aussi le dernier rempart de la gouvernance des données - vous manipulez les PII des 10 000 utilisateurs.

## Objectif en 10 jours

1. Modèle en étoile sur PostgreSQL (ou équivalent)
2. Transformations Gold (G3) → star schema (SQL pur ou dbt)
3. Dashboard BI avec outil de visualisation **au choix** (5-6 des 15 questions métier)
4. Rapport d'analyse des incohérences inter-nœuds
5. Deux documents d'architecture **AWS** : Early Stage et At Scale
6. Déploiement test sur AWS Redshift ou Athena + outil BI au choix (compte sandbox fourni)

Référez-vous à `PROJET_NAFAD_PAY.html` à la racine pour le planning, la grille d'évaluation et le template d'archi. Les 15 questions métier sont dans `business_questions.md`.

## Données fournies

| Fichier | Lignes | Colonnes | Notes |
|---|---|---|---|
| `stg_users.csv` | 10 000 | 22 | `email` vide à 59 %, `kyc_level` et `moughataa_name` vides à 100 % |
| `stg_accounts.csv` | 11 019 | 16 | `account_type_label` vide à 100 % |
| `stg_transactions.csv` | 100 000 | **45** | Contient `sync_status`, `amount_node_a/b`, `risk_score`, `last_synced_at` |
| `stg_fees.csv` | 41 391 | 11 | Frais par transaction |
| `stg_merchants.csv` | 500 | 27 | 13 catégories, 15 wilayas |
| `stg_agencies.csv` | 100 | 21 | `float_balance`, `tier`, `license_number` |
| `stg_agents.csv` | 392 | 20 | Agents rattachés aux agences |
| `node_metrics.csv` | 5 | 5 | **Totaux volontairement incohérents** avec `stg_transactions` |

Volume 10× G1 (G1 = 1 000 users, G4 = 10 000 users).

## Anomalies intentionnelles mesurées

| Anomalie | Volume | Traitement attendu |
|---|---|---|
| Écart `node_metrics.total_amount` (2,091 Mds MRU) vs `stg_transactions.amount` (2,090 Mds MRU) | **1 300 875 MRU (0,062 %)** | À documenter dans le rapport |
| `sync_status = CONFLICT` | **1 549 lignes (1,5 %)** | Stratégie à choisir : exclure, prendre `amount_node_a`, `amount_node_b`, ou `amount` |
| `sync_status = LAGGING` | 1 912 lignes (1,9 %) | À flagger dans le DWH |
| `sync_status = PENDING` | 1 616 lignes (1,6 %) | À flagger |
| `amount_node_a/b` remplis alors que `sync_status=CONFLICT` | **Seulement ~20 / 1 549** | Incohérence méta : choisir une stratégie (imputation, exclusion, ou remplissage par défaut) |
| Cohérence FK (merchant/agency/agent) | **100 % (aucun orphelin)** | Rien à faire |

## Schéma `stg_transactions` - colonnes clés

```
id, reference, idempotency_key, transaction_type, amount, fee, total_amount,
source_account_id, source_user_id, destination_account_id, destination_user_id,
merchant_id, agency_id, agent_id,
status, failure_reason, balance_before, balance_after,
node_id, datacenter,
sync_status, last_synced_at, amount_node_a, amount_node_b, risk_score,
channel, device_type, ip_address,
transaction_date, transaction_time, created_at, updated_at, completed_at
```

**Différences par rapport à G1** : ajouts `sync_status`, `last_synced_at`, `amount_node_a`, `amount_node_b`, `risk_score`, `updated_at`. Retraits : pas de `processing_node` (seul `node_id`), pas de `sequence_number`.

## Livrables attendus

1. **Modèle dimensionnel** (diagramme + DDL) : fact + dimensions
2. **Scripts de transformation** staging → DWH (SQL ou dbt)
3. **Dashboard BI (outil au choix)** avec 5-6 des 15 questions métier
4. **Rapport d'analyse** (1-2 pages MD) sur les incohérences inter-nœuds, incluant la justification du **choix SCD**
5. **Document d'architecture Early Stage** (1-2 pages)
6. **Document d'architecture At Scale** (2-3 pages, focus gouvernance + sécurité BI)
7. `docker-compose.yml` (minimum : `postgres_dwh`; outil BI optionnel)

## Guidelines techniques

### Modèle en étoile recommandé

**Fact (grain = 1 ligne par transaction)**
```sql
fact_transactions (
  tx_pk BIGSERIAL PRIMARY KEY,
  transaction_id BIGINT UNIQUE,
  date_key INT REFERENCES dim_date(date_key),
  user_key BIGINT REFERENCES dim_user(user_key),
  merchant_key BIGINT REFERENCES dim_merchant(merchant_key),
  agency_key BIGINT REFERENCES dim_agency(agency_key),
  node_key INT REFERENCES dim_node(node_key),
  amount NUMERIC(18,2),
  fee NUMERIC(18,2),
  status VARCHAR,
  sync_status VARCHAR,
  is_cross_dc BOOLEAN,
  -- autres mesures
)
```

**Dimensions**
- `dim_date` (date_key, date, year, month, day, dow, week)
- `dim_user` (user_key, user_id, name, wilaya_name, kyc_level, ...) - stratégie SCD (Type 1, Type 2 ou hybride) **à choisir et justifier**
- `dim_merchant` (merchant_key, merchant_id, name, category, wilaya, ...)
- `dim_agency` (agency_key, agency_id, name, tier, wilaya, ...)
- `dim_node` (node_key, node_id, datacenter, aws_az)

### Docker Compose (minimum)

```yaml
services:
  postgres_dwh:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: dwh
      POSTGRES_PASSWORD: ${DB_PASSWORD}
```

L'outil de visualisation est libre (Metabase, Superset, Power BI, Tableau, Looker Studio, etc.).

### Questions métier à traiter (5-6 min sur les 15 de `business_questions.md`)

Choix recommandé pour avoir un dashboard qui "raconte une histoire" :
1. Volume total ce mois vs mois précédent
2. Taux de succès des transactions
3. Wilaya qui génère le plus de volume
4. Heures de pointe
5. Répartition par type de transaction
6. Principaux motifs d'échec

## Questions d'investigation obligatoires

1. Additionnez `total_amount` de `node_metrics.csv`, comparez à `SUM(amount)` de `stg_transactions`. Expliquez l'écart (1,3 M MRU).
2. Pour les 1 549 CONFLICT : exclure du DWH ? Prendre `amount_node_a` ? `amount_node_b` ? `amount` ? Justifier.
3. **Incohérence méta à investiguer** : 1 549 CONFLICT annoncés mais seulement ~20 ont `amount_node_a/b` remplis. Comment gérer les ~1 529 autres ?
4. `last_synced_at` antérieur à `created_at` : impact sur les agrégations par date ?
5. Un user change de wilaya : choisissez une stratégie SCD (Type 1, Type 2 ou hybride) et argumentez votre choix.
6. DG veut temps réel **et** comparaisons mois vs mois : Lambda, Kappa, ou materialized views ?

## Architecture AWS - points obligatoires

| Dimension | Early Stage | At Scale |
|---|---|---|
| **DWH** | RDS PostgreSQL séparé de l'OLTP | **Redshift Serverless** ou **Athena** sur S3 Parquet |
| **BI** | Outil BI au choix (Metabase, Superset, QuickSight, Power BI, etc.) | + SSO (Cognito/SAML/OIDC) |
| **Transformations** | SQL scripts | dbt-core + CI/CD |
| **Cache live** | - | ElastiCache Redis |
| **Catalog** | - | Glue Data Catalog + Macie (détection PII auto) |

### Gouvernance & sécurité (critique en BI)

1. **Row-level security** : un chef d'agence ne voit que sa wilaya (Redshift RLS)
2. **Column-level masking** : `phone`, `nni`, `email` masqués pour analystes juniors (Redshift Dynamic Data Masking)
3. **Catalog & PII** : tagging via Glue + détection automatique via Macie
4. **IAM** : roles par outil BI (pas de compte partagé), Redshift IAM database credentials
5. **Séparation OLTP/DWH** : jamais le même cluster que G1
6. **Audit** : CloudTrail + Redshift audit logs → S3 → Athena queries
7. **Export** : limite de taille par export, audit systématique

### Threat model (top 3)

1. **Analyste exfiltre un dump** → quota export + audit + détection d'anomalie sur les volumes
2. **Token/session d'outil BI qui fuite** → rotation + SSO Cognito + courte durée de session
3. **Requête runaway qui coûte 500 $** → Redshift Query Monitoring Rules + concurrency scaling limit + alarmes coût

### Protocoles

- Redshift via **JDBC/ODBC TLS** uniquement
- Outil BI ↔ Redshift via **IAM Database Auth** (credentials temporaires, pas de password statique)
- Accès utilisateur outil BI via **SSO** (Cognito/SAML/OIDC)

## Correspondance des datacenters fictifs

| Donnée | AWS (implémentation) | GCP (comparaison) | Hetzner (comparaison bare-metal) |
|---|---|---|---|
| `DC-NKC-PRIMARY` | `eu-west-3a` | `europe-west9-a` | `fsn1` (Falkenstein) |
| `DC-NKC-SECONDARY` | `eu-west-3b` | `europe-west9-b` | `nbg1` (Nuremberg) |
| `DC-NDB` | `eu-west-3c` | `europe-west9-c` | `hel1` (Helsinki, DR éloigné) |

Implémentation cible : **AWS**. GCP et Hetzner servent de référence comparative (coût BigQuery vs Redshift vs Postgres bare-metal).
