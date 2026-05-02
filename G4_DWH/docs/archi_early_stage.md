# Architecture AWS — Early Stage (MVP)

**Groupe 4 — Analytics & BI — NAFAD PAY**  
**Région AWS : eu-west-3 (Paris)**

---

## 1. Contexte & contraintes

### Objectif

Déployer un Data Warehouse analytique accessible à l'équipe BI
de NAFAD PAY avec un minimum de complexité et de coût.

### Contraintes

| Contrainte                 | Valeur                                      |
| -------------------------- | ------------------------------------------- |
| Volume de données          | 100 000 transactions, 10 000 utilisateurs   |
| Utilisateurs BI simultanés | 5 à 10 personnes                            |
| Budget mensuel             | < 100 $/mois                                |
| Latence réseau             | 40-60ms Nouakchott ↔ Paris (incompressible) |
| Équipe                     | 5 étudiants, pas d'ops dédié                |
| SLA                        | Disponibilité 99%, pas de temps réel requis |

### Hypothèses

- Le chargement des données est manuel (pas de streaming)
- Les utilisateurs BI sont peu nombreux (< 10)
- Pas besoin de haute disponibilité pour le MVP
- Les données sont rafraîchies 1 fois par jour

---

## 2. Diagramme d'architecture

┌─────────────────────────────────────────────────────┐
│ Internet │
└─────────────────────┬───────────────────────────────┘
│ HTTPS
▼
┌─────────────────────────────────────────────────────┐
│ AWS eu-west-3 │
│ │
│ ┌─────────────────────────────────────────────┐ │
│ │ VPC 10.0.0.0/16 │ │
│ │ │ │
│ │ ┌──────────────────────────────────────┐ │ │
│ │ │ Subnet Public 10.0.1.0/24 │ │ │
│ │ │ eu-west-3a │ │ │
│ │ │ │ │ │
│ │ │ ┌────────────────────────┐ │ │ │
│ │ │ │ EC2 t3.medium │ │ │ │
│ │ │ │ Metabase (port 3000) │ │ │ │
│ │ │ └───────────┬────────────┘ │ │ │
│ │ └───────────────│──────────────────────┘ │ │
│ │ │ port 5432 │ │
│ │ ┌───────────────│──────────────────────┐ │ │
│ │ │ Subnet Privé 10.0.2.0/24 │ │ │
│ │ │ eu-west-3a │ │ │
│ │ │ │ │ │
│ │ │ ┌────────────────────────┐ │ │ │
│ │ │ │ RDS PostgreSQL 16 │ │ │ │
│ │ │ │ db.t3.medium │ │ │ │
│ │ │ │ DWH (star schema) │ │ │ │
│ │ │ └────────────────────────┘ │ │ │
│ │ └──────────────────────────────────────┘ │ │
│ └─────────────────────────────────────────────┘ │
│ │
│ ┌──────────────┐ ┌──────────────────────────┐ │
│ │ S3 Bucket │ │ Secrets Manager │ │
│ │ CSV staging │ │ DB password │ │
│ └──────────────┘ └──────────────────────────┘ │
└─────────────────────────────────────────────────────┘

---

## 3. Composants détaillés

### 3.1 VPC & Réseau

| Composant        | Valeur                      |
| ---------------- | --------------------------- |
| VPC CIDR         | 10.0.0.0/16                 |
| Subnet public    | 10.0.1.0/24 — eu-west-3a    |
| Subnet privé     | 10.0.2.0/24 — eu-west-3a    |
| Internet Gateway | 1 (pour EC2 Metabase)       |
| NAT Gateway      | Non (pas nécessaire au MVP) |

### 3.2 RDS PostgreSQL (Data Warehouse)

| Composant          | Valeur                                          |
| ------------------ | ----------------------------------------------- |
| Moteur             | PostgreSQL 16                                   |
| Instance           | db.t3.medium (2 vCPU, 4 Go RAM)                 |
| Stockage           | gp3 50 Go                                       |
| Multi-AZ           | Non (MVP)                                       |
| Backup automatique | 7 jours de rétention                            |
| Security Group     | Accepte uniquement l'EC2 Metabase sur port 5432 |
| Accès Internet     | Non (subnet privé)                              |

### 3.3 EC2 Metabase

| Composant   | Valeur                                   |
| ----------- | ---------------------------------------- |
| Instance    | t3.medium (2 vCPU, 4 Go RAM)             |
| AMI         | Amazon Linux 2023                        |
| Port ouvert | 3000 (Metabase) — IPs équipe uniquement  |
| Accès SSH   | Via SSM Session Manager (pas de port 22) |
| Stockage    | EBS gp3 30 Go                            |

### 3.4 S3

- Stockage des fichiers CSV de staging
- Chargement manuel via AWS CLI vers RDS

### 3.5 Secrets Manager

- Stockage du mot de passe RDS
- Rotation manuelle
- L'EC2 Metabase récupère le password au démarrage

---

## 4. Flux de données

CSV files (local)
│
│ Upload manuel
▼
S3 Bucket
│
│ COPY via psql
▼
RDS PostgreSQL (staging tables)
│
│ Scripts ETL SQL
▼
RDS PostgreSQL (star schema DWH)
│
│ JDBC port 5432
▼
Metabase (EC2)
│
│ HTTPS port 3000
▼
Utilisateurs BI (navigateur)
**Latence totale :**

- Chargement ETL : ~5 minutes (manuel, 1 fois/jour)
- Requêtes dashboard : < 2 secondes

---

## 5. Sécurité

| Mesure                 | Détail                                       |
| ---------------------- | -------------------------------------------- |
| Chiffrement at-rest    | RDS chiffré via KMS                          |
| Chiffrement in-transit | TLS entre Metabase et RDS                    |
| Accès RDS              | Subnet privé, SG restrictif                  |
| Accès EC2              | SSM Session Manager, pas de port 22          |
| Secrets                | AWS Secrets Manager (pas de password en dur) |
| Accès Metabase         | Port 3000 restreint aux IPs de l'équipe      |

---

## 6. Points de rupture & seuils de bascule

Cette architecture atteint ses limites dans ces cas :

| Situation              | Seuil              | Solution                   |
| ---------------------- | ------------------ | -------------------------- |
| Trop de données        | > 10M transactions | Migrer vers Redshift       |
| Trop d'utilisateurs BI | > 20 simultanés    | ECS Fargate + RDS Multi-AZ |
| Requêtes lentes        | p99 > 2 secondes   | Ajouter ElastiCache Redis  |
| Besoin temps réel      | Refresh < 1h       | Architecture Lambda        |
| Haute disponibilité    | SLA > 99.9%        | RDS Multi-AZ + ALB         |

---

## 7. Estimation de coût mensuel

| Service         | Instance     | Coût/mois      |
| --------------- | ------------ | -------------- |
| RDS PostgreSQL  | db.t3.medium | ~55 $          |
| EC2 Metabase    | t3.medium    | ~30 $          |
| EBS stockage    | gp3 80 Go    | ~6 $           |
| S3 staging      | 10 Go        | ~0.23 $        |
| Secrets Manager | 1 secret     | ~0.40 $        |
| Data transfer   | ~10 Go/mois  | ~0.90 $        |
| **Total**       |              | **~93 $/mois** |

---

## 8. Correspondance datacenters fictifs → AWS

| Datacenter NAFAD PAY | AWS Zone   | AWS Région |
| -------------------- | ---------- | ---------- |
| DC-NKC-PRIMARY       | eu-west-3a | Paris      |
| DC-NKC-SECONDARY     | eu-west-3b | Paris      |
| DC-NDB               | eu-west-3c | Paris      |
