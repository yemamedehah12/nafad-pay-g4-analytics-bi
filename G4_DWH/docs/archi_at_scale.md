# Architecture AWS — At Scale

**Groupe 4 — Analytics & BI — NAFAD PAY**  
**Région AWS : eu-west-3 (Paris)**

---

## 1. Contexte & contraintes

### Objectif

Supporter une charge 10× supérieure au MVP avec haute disponibilité,
sécurité renforcée et gouvernance des données PII.

### Contraintes

| Contrainte        | Valeur                                  |
| ----------------- | --------------------------------------- |
| Volume            | 5M transactions/mois, 500K utilisateurs |
| Utilisateurs BI   | 100+ simultanés                         |
| SLA               | Disponibilité 99.9%, RPO < 1h, RTO < 4h |
| Latence dashboard | p99 < 1 seconde                         |
| Sécurité          | PII protégées (phone, nni, email)       |
| Compliance        | Row-Level Security par wilaya           |

---

## 2. Diagramme d'architecture

Utilisateurs BI (navigateur)
│ HTTPS
▼
┌─────────────────────────────────────────────────────┐
│ AWS eu-west-3 │
│ │
│ [Cognito User Pool] ←── SSO SAML/OIDC │
│ │ JWT Token │
│ ▼ │
│ [ALB + WAF] ←── Shield Standard (DDoS) │
│ │ │
│ ▼ │
│ [ECS Fargate — Metabase] │
│ │ JDBC TLS │
│ ▼ │
│ [Redshift Serverless] ←── [dbt Core CI/CD] │
│ │ │
│ ▼ │
│ [S3 Parquet Gold] ←── [Glue + Macie PII] │
│ │ │
│ ▼ │
│ [Athena — requêtes ad hoc] │
│ │
│ [ElastiCache Redis] ←── cache requêtes fréquentes │
└─────────────────────────────────────────────────────┘

---

## 3. Composants détaillés

### 3.1 Redshift Serverless (DWH cible)

| Composant  | Valeur                                |
| ---------- | ------------------------------------- |
| Type       | Serverless (pas de cluster à gérer)   |
| Namespace  | nafadpay-dwh                          |
| Scale      | Automatique selon la charge           |
| Pause auto | Oui (économise les coûts hors heures) |
| Stockage   | S3 Parquet via Spectrum               |

**Avantages vs RDS PostgreSQL :**

- Requêtes analytiques 10× plus rapides
- Scale automatique sans intervention
- Séparation stockage/compute

### 3.2 ECS Fargate (Metabase)

| Composant     | Valeur                    |
| ------------- | ------------------------- |
| CPU           | 1 vCPU                    |
| RAM           | 2 Go                      |
| Auto-scaling  | 1 à 5 tâches selon charge |
| Load Balancer | ALB avec certificat ACM   |

### 3.3 Cognito SSO

| Composant  | Valeur                       |
| ---------- | ---------------------------- |
| Type       | User Pool + Identity Pool    |
| Fédération | SAML/OIDC (Active Directory) |
| Session    | 8h maximum                   |
| MFA        | Obligatoire pour les admins  |

### 3.4 Row-Level Security (RLS)

```sql
-- Un chef d'agence ne voit que sa wilaya
CREATE RLS POLICY wilaya_policy
ON fact_transactions
USING (wilaya_name = current_user_wilaya());

ATTACH RLS POLICY wilaya_policy
ON fact_transactions TO ROLE chef_agence;
```

### 3.5 Column Masking (PII)

```sql
-- Les analystes juniors ne voient pas les données sensibles
CREATE MASKING POLICY mask_phone
WITH (phone VARCHAR)
USING ('***-***-' || RIGHT(phone, 4));

ATTACH MASKING POLICY mask_phone
ON dim_user(phone) TO ROLE analyste_junior;
```

### 3.6 Glue + Macie

- **Glue Crawler** : détecte automatiquement les colonnes PII
- **AWS Macie** : alerte si données sensibles exposées dans S3
- **Tags automatiques** : `PII=true`, `Sensitivity=high`

### 3.7 ElastiCache Redis

- Cache les requêtes fréquentes du dashboard
- TTL : 1h pour les KPI, 5min pour les alertes
- Réduit la latence Nouakchott-Paris (40-60ms)

---

## 4. Réseau & sécurité

### VPC

| Composant         | Valeur                   |
| ----------------- | ------------------------ |
| VPC CIDR          | 10.0.0.0/16              |
| Subnet public     | ALB uniquement           |
| Subnet privé app  | ECS Fargate              |
| Subnet privé data | Redshift + ElastiCache   |
| AZ                | 3 zones (eu-west-3a/b/c) |

### Sécurité

| Mesure                 | Détail                                     |
| ---------------------- | ------------------------------------------ |
| WAF                    | Règles OWASP Top 10 + rate limiting        |
| Shield Standard        | Protection DDoS couche 3/4                 |
| Chiffrement at-rest    | KMS sur Redshift + S3 SSE-KMS              |
| Chiffrement in-transit | TLS 1.2+ obligatoire                       |
| IAM                    | Moindre privilège, credentials temporaires |
| Audit                  | CloudTrail + Redshift audit logs           |

---

## 5. Threat model — Top 3 attaques

| #   | Attaque                           | Mitigation                                                            |
| --- | --------------------------------- | --------------------------------------------------------------------- |
| 1   | Analyste exfiltre un dump complet | Quota export 10K lignes + audit CloudTrail + alerte si volume > seuil |
| 2   | Token Metabase compromis          | Cognito SSO + session 8h max + rotation automatique                   |
| 3   | Requête runaway coûte 500$        | Redshift Query Monitoring Rules + alarme AWS Budget                   |

---

## 6. Plan de migration Early Stage → At Scale

### Étapes sans downtime

**Phase 1 — Semaines 1-2**

1. Créer Redshift Serverless en parallèle de RDS
2. Répliquer les données via AWS DMS
3. Faire tourner les deux en parallèle

**Phase 2 — Semaine 3** 4. Pointer Metabase vers Redshift 5. Valider que les dashboards donnent les mêmes résultats 6. Mettre RDS en read-only

**Phase 3 — Semaine 4** 7. Activer SSO Cognito 8. Configurer RLS et column masking 9. Décommissionner RDS après 2 semaines de stabilité

**Durée totale : ~6 jours-personnes**

---

## 7. Estimation de coût mensuel

| Service             | Détail          | Coût/mois        |
| ------------------- | --------------- | ---------------- |
| Redshift Serverless | ~8h/jour        | ~120 $           |
| ECS Fargate         | 1-5 tâches      | ~40 $            |
| ALB                 | 1 load balancer | ~18 $            |
| ElastiCache Redis   | t3.micro        | ~15 $            |
| S3 Parquet          | 1 To            | ~23 $            |
| Glue Crawlers       | ~10 runs/jour   | ~5 $             |
| Cognito             | 10K users       | ~0 $ (free tier) |
| CloudTrail          | Tous les logs   | ~10 $            |
| Secrets Manager     | 5 secrets       | ~2 $             |
| **Total**           |                 | **~233 $/mois**  |

---

## 8. Comparaison Early Stage vs At Scale

| Critère          | Early Stage    | At Scale                |
| ---------------- | -------------- | ----------------------- |
| Coût             | ~93 $/mois     | ~233 $/mois             |
| Volume max       | 10M lignes     | 1Md+ lignes             |
| Utilisateurs BI  | 10             | 100+                    |
| Disponibilité    | 99%            | 99.9%                   |
| Authentification | Login/password | SSO Cognito             |
| Sécurité PII     | Basique        | RLS + masking           |
| ETL              | Manuel         | dbt + CI/CD             |
| Temps réel       | Non            | Materialized Views (1h) |
