# NAFAD-PAY — G4 Analytics & BI

Data Warehouse + Pipeline ETL + Dashboard BI pour le système de paiement fictif NAFAD-PAY.

**Stack** : PostgreSQL 16 · Apache Superset · dbt-core · AWS Redshift (prod)  
**Données** : 100 000 transactions · 10 000 utilisateurs · 500 marchands · 100 agences

---

## Démarrage rapide

```bash
cp .env.example .env
bash run_etl.sh
# Dashboard : http://localhost:8088  (admin / Admin1234)
```

---

## Structure du projet

```
nafad-pay-g4-analytics-bi/
│
├── docker-compose.yml        # PostgreSQL + Superset + pgAdmin
├── .env.example              # Variables d'environnement
├── run_etl.sh                # Script de démarrage complet
│
├── data/                     # Données CSV (montées dans Docker)
│   ├── stg_transactions.csv  # 100 000 transactions (40 MB)
│   ├── stg_users.csv         # 10 000 utilisateurs
│   ├── stg_accounts.csv      # 11 019 comptes
│   ├── stg_merchants.csv     # 500 marchands
│   ├── stg_agencies.csv      # 100 agences
│   ├── stg_agents.csv        # 392 agents
│   ├── stg_fees.csv          # 41 391 frais
│   ├── node_metrics.csv      # Métriques noeuds (5 lignes)
│   └── reference/            # Tables de référence (wilayas, catégories, types)
│
├── sql/                      # Pipeline ETL SQL — exécuter dans l'ordre
│   ├── 00_create_staging.sql # Tables temporaires (tmp_*)
│   ├── 01_load_csv.sql       # COPY CSV → tmp_*
│   ├── 02_star_schema_ddl.sql # DDL schéma en étoile
│   ├── 03_populate_dim_date.sql
│   ├── 04_populate_dim_user.sql    # SCD Type 2
│   ├── 05_populate_dim_merchant.sql
│   ├── 06_populate_dim_agency.sql
│   ├── 07_populate_fact_transactions.sql  # Gestion CONFLICT/LAGGING
│   ├── 08_validation_checks.sql    # Contrôles post-ETL
│   ├── 09_conflict_resolution.sql  # Analyse des 1 549 CONFLICT
│   ├── 10_gap_analysis.sql         # Écart node_metrics vs transactions
│   ├── 11_materialized_views.sql   # Vues matérialisées (performance BI)
│   ├── 12_pii_security.sql         # RLS + masquage PII
│   └── analytics/
│       ├── dashboard_queries.sql   # 6 visuels principaux
│       └── business_questions.sql  # 15 questions métier complètes
│
├── dbt/                      # Projet dbt-core (alternative au SQL direct)
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── models/
│   │   ├── staging/          # stg_transactions (nettoyage + flags)
│   │   └── marts/            # dim_user, fact_transactions + tests
│   └── snapshots/            # SCD Type 2 automatique (snap_dim_user)
│
├── docs/                     # Documentation
│   ├── archi_early_stage.md  # Architecture MVP (RDS + EC2, <$100/mois)
│   ├── archi_at_scale.md     # Architecture prod (Redshift Serverless, ~$300/mois)
│   ├── anomalies_report.md   # Analyse des anomalies intentionnelles
│   ├── business_questions.md # 15 questions métier
│   └── screenshots/          # Captures Superset
│
└── sujet/
    └── PROJET_NAFAD_PAY.html # Enoncé pédagogique
```

---

## Modèle en étoile

```
              dim_date ──┐
              dim_user ──┤
           dim_merchant ─┼── fact_transactions
            dim_agency ──┤
              dim_node ──┘
```

| Table | Lignes | Note |
|---|---|---|
| `fact_transactions` | 100 000 | Grain = 1 transaction |
| `dim_user` | 10 000 | SCD Type 2 |
| `dim_merchant` | 501 | +1 dummy (-1) |
| `dim_agency` | 101 | +1 dummy (-1) |
| `dim_date` | 366 | 2024 (année bissextile) |
| `dim_node` | 5 | 3 DC fictifs → AWS eu-west-3 a/b/c |

---

## Anomalies détectées

| Anomalie | Volume | Traitement |
|---|---|---|
| CONFLICT sans montant nodal | 1 529 (98,7%) | Flag `is_unresolvable_conflict` — exclus KPIs financiers |
| CONFLICT avec montants | 20 | Montant = moyenne(node_a, node_b) |
| LAGGING | 1 912 (1,91%) | Flag `is_lagging` |
| PENDING | 1 616 (1,62%) | Flag `is_pending_sync` |
| Clock skew | 7 058 (7,06%) | Flag `has_clock_skew` |
| Ecart node_metrics | ~462 M MRU | Double comptage cross-DC + LAGGING |

---

## Utilisation dbt (optionnel)

```bash
cd dbt
pip install dbt-postgres
dbt snapshot    # SCD Type 2 dim_user
dbt run         # Staging → Marts
dbt test        # 20+ tests qualité
```

---

## Architecture AWS

- **Early Stage** : RDS PostgreSQL t3.medium + EC2 — < $100/mois → [docs/archi_early_stage.md](docs/archi_early_stage.md)
- **At Scale** : Redshift Serverless + ECS Fargate + Cognito SSO + RLS — ~$300/mois → [docs/archi_at_scale.md](docs/archi_at_scale.md)