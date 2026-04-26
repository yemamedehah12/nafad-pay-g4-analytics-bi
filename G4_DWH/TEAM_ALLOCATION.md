# 👥 Allocation Équitable - 5 Personnes (10 jours)

**Membres de l'équipe:**

1. **Touba**
2. **Yemame**
3. **Khadije**
4. **Oumlvadli**
5. **Ishaghe**

**Objectif**: Chacun contribue 20% = 80 heures total / 5 = 16 heures par personne

---

## 📋 Répartition des Rôles

```
🏢 NAFAD-PAY G4 DWH Project
│
├─ 👨‍💼 TOUBA (Lead Data Engineer)
│  └─ Infrastructure + PostgreSQL + DDL
│
├─ 👩‍💼 YEMAME (ETL Engineer)
│  └─ ETL Pipeline + Data Transformation
│
├─ 📊 KHADIJE (BI Analyst)
│  └─ Dashboard Metabase + Queries SQL
│
├─ 🏗️ OUMLVADLI (Architect)
│  └─ Architecture AWS + Documentation
│
└─ 🧪 ISHAGHE (QA / Testing)
   └─ Validation + Testing + Optimization
```

---

## 🔄 DETAILED WORK BREAKDOWN (5 personnes = chacun ~16 heures)

### JOUR 1-2: Infrastructure (32 heures total)

**TOUBA** (16 heures - Lead Data Engineer)

- [x] Configurer Docker + PostgreSQL
  - Vérifier Docker Desktop
  - Lancer `docker-compose up -d postgres_dwh`
  - Valider la connection
  - **Time: 2 heures**
- [x] Charger la DDL star schema
  - Exécuter `ddl/00_create_staging.sql`
  - Exécuter `ddl/01_star_schema.sql`
  - Vérifier toutes les tables créées
  - **Time: 3 heures**

- [x] Créer indexes + optimisations
  - Valider 15+ indexes
  - Tester performance des indexes
  - Document performance baseline
  - **Time: 4 heures**

- [x] Documentation DDL
  - Documenter schéma dimensionnel
  - Créer diagram ER (optionnel)
  - Écrire notes techniques
  - **Time: 3 heures**

- [x] Support & troubleshooting
  - Help team avec setup
  - Debug Docker issues
  - **Time: 4 heures**

**YEMAME** (16 heures - ETL Engineer)

- [x] Préparer les données staging
  - Examiner stg\_\*.csv files
  - Vérifier structure CSV
  - Document anomalies trouvées
  - **Time: 3 heures**

- [x] Charger CSV dans PostgreSQL
  - COPY commands pour 8 tables
  - Valider row counts
  - Document any errors
  - **Time: 4 heures**

- [x] Valider intégrité données
  - Check FK/PK
  - Vérifier nulls, anomalies
  - Create data profile report
  - **Time: 5 heures**

- [x] Support TOUBA
  - Help avec setup
  - Pair programming si needed
  - **Time: 4 heures**

### JOUR 3: ETL Pipeline (8 heures)

**YEMAME** (8 heures - FULL FOCUS)

- [x] Exécuter ETL complet
  - Run `etl/02_load_star_schema.sql`
  - Monitor execution
  - **Time: 2 heures**

- [x] Valider transformations
  - Check row counts
  - Verify anomalies flagged
  - **Time: 3 heures**

- [x] Document ETL results
  - Create execution report
  - Note any issues
  - **Time: 3 heures**

**Support Léger** (4 heures total):

- TOUBA: QA checks (2h)
- KHADIJE: Learn the data (2h)

### JOUR 4-5: Dashboard BI (32 heures)

**KHADIJE** (16 heures - BI Analyst)

- [ ] Setup Metabase
  - Lancer `docker-compose --profile bi up -d metabase`
  - Configure PostgreSQL connection
  - **Time: 2 heures**

- [ ] Create 6 SQL Queries
  - Q1: Volume MoM (2h)
  - Q2: Success Rate (1.5h)
  - Q3: Geographic (1.5h)
  - Q4: Peak Hours (2h)
  - Q5: Top Merchants (1.5h)
  - Q6: Failure Reasons (1.5h)
  - **Time: 10 heures**

- [ ] Test + optimize queries
  - Performance tuning
  - Result validation
  - **Time: 2 heures**

- [ ] Document queries
  - Write query logic
  - **Time: 2 heures**

**TOUBA** (4 heures - Support)

- Optimize slow queries
- Help KHADIJE with SQL
- **Time: 4 heures**

**YEMAME** (4 heures - Support)

- Validate data in queries
- Help debug results
- **Time: 4 heures**

**ISHAGHE** (8 heures - Testing)

- [ ] Test dashboard setup
  - Verify Metabase runs
  - Check data loads
  - **Time: 2 heures**

- [ ] Validate SQL queries
  - Check query execution
  - Verify results accuracy
  - **Time: 4 heures**

- [ ] Document test results
  - Create test report
  - **Time: 2 heures**

### JOUR 6-7: Architecture AWS (32 heures)

**OUMLVADLI** (16 heures - Architect - FULL FOCUS)

- [ ] Read architecture docs
  - Study `01_early_stage_aws.md`
  - Study `02_at_scale_aws.md`
  - **Time: 4 heures**

- [ ] Create decision document
  - Compare Early Stage vs At Scale
  - Recommend architecture
  - Document justification
  - **Time: 6 heures**

- [ ] Design deployment plan
  - Create AWS deployment checklist
  - Document prerequisites
  - **Time: 4 heures**

- [ ] Prepare presentation
  - Create architecture slides
  - **Time: 2 heures**

**TOUBA** (6 heures - Support)

- Review architecture doc
- Validate technical correctness
- Help with deployment plan
- **Time: 6 heures**

**KHADIJE** (4 heures - Support)

- Review BI tool recommendations
- Document BI architecture
- **Time: 4 heures**

**YEMAME** (4 heures - Support)

- Review ETL architecture (dbt, Lambda)
- Document ETL recommendations
- **Time: 4 heures**

**ISHAGHE** (2 heures - Support)

- Review testing strategy
- Document QA architecture
- **Time: 2 heures**

### JOUR 8-9: Testing + Validation (24 heures)

**ISHAGHE** (12 heures - QA Lead - FULL FOCUS)

- [ ] Test Suite Execution
  - FK/PK integrity tests
  - Data quality tests
  - Performance tests
  - **Time: 5 heures**

- [ ] Dashboard Testing
  - Test all 6 dashboard questions
  - Verify results accuracy
  - Performance check (<2s)
  - **Time: 4 heures**

- [ ] Document test results
  - Create comprehensive test report
  - List any issues found
  - **Time: 3 heures**

**TOUBA** (4 heures)

- Performance optimization
- Database tuning
- **Time: 4 heures**

**YEMAME** (4 heures)

- Validate ETL correctness
- Check data quality flags
- **Time: 4 heures**

**KHADIJE** (4 heures)

- Test dashboard usability
- Verify all queries work
- **Time: 4 heures**

---

## JOUR 10: Présentation + Handoff (16 heures)

**Everyone** (4 heures each)

**OUMLVADLI** (4 heures)

- Lead presentation
- Present architecture
- Answer technical questions

**TOUBA** (4 heures)

- Present infrastructure + DDL
- Demonstrate DWH
- Technical Q&A

**YEMAME** (4 heures)

- Present ETL + data quality
- Explain anomalies
- Data Q&A

**KHADIJE** (4 heures)

- Present dashboard
- Live demo (5 business questions)
- BI Q&A

**ISHAGHE** (4 heures)

- Present testing results
- Quality metrics
- Handoff documentation

---

## 📊 ALLOCATION SUMMARY

| Personne      | Rôle               | J1-2     | J3      | J4-5     | J6-7     | J8-9     | J10     | Total     |
| ------------- | ------------------ | -------- | ------- | -------- | -------- | -------- | ------- | --------- |
| **TOUBA**     | Data Engineer Lead | 16h      | -       | 4h       | 6h       | 4h       | 4h      | **34h**   |
| **YEMAME**    | ETL Engineer       | 16h      | 8h      | 4h       | 4h       | 4h       | 4h      | **40h**   |
| **KHADIJE**   | BI Analyst         | -        | 2h      | 16h      | 4h       | 4h       | 4h      | **30h**   |
| **OUMLVADLI** | Architect          | -        | -       | -        | 16h      | 2h       | 4h      | **22h**   |
| **ISHAGHE**   | QA / Testing       | -        | -       | 8h       | 2h       | 12h      | 4h      | **26h**   |
|               |                    |          |         |          |          |          |         |
| **TOTAL**     |                    | **32h**  | **10h** | **32h**  | **32h**  | **26h**  | **20h** | **152h**  |
| **Average**   |                    | **6.4h** | **2h**  | **6.4h** | **6.4h** | **5.2h** | **4h**  | **30.4h** |

---

## 📅 Daily Stand-up Schedule

**Tous les jours 09:00-09:15 (15 min)**

```
TOUBA:      "J'ai fait... Aujourd'hui je vais..."
↓
YEMAME:     "J'ai fait... Aujourd'hui je vais..."
↓
KHADIJE:    "J'ai fait... Aujourd'hui je vais..."
↓
OUMLVADLI:  "J'ai fait... Aujourd'hui je vais..."
↓
ISHAGHE:    "J'ai fait... Aujourd'hui je vais..."
```

---

## ✅ Checklists par Personne

### ✓ TOUBA (Data Engineer Lead)

- [ ] Docker setup + validation
- [ ] DDL execution (all tables created)
- [ ] Indexes created + verified
- [ ] Performance baseline documented
- [ ] Troubleshoot team issues
- [ ] Architecture review
- [ ] Final testing + sign-off

### ✓ YEMAME (ETL Engineer)

- [ ] CSV files examined
- [ ] Staging tables loaded
- [ ] Data quality profiled
- [ ] ETL pipeline executed (100K transactions)
- [ ] Anomalies documented (CONFLICT, LAGGING, PENDING)
- [ ] ETL results validated
- [ ] Handoff documentation

### ✓ KHADIJE (BI Analyst)

- [ ] Learn DWH schema
- [ ] Metabase setup
- [ ] 6 SQL queries created + tested
- [ ] Dashboard organized
- [ ] Shared with team
- [ ] Performance verified
- [ ] Live demo prepared

### ✓ OUMLVADLI (Architect)

- [ ] Architecture docs reviewed
- [ ] Decision: Early Stage vs At Scale
- [ ] Deployment plan created
- [ ] Architecture presentation ready
- [ ] Handoff guide prepared

### ✓ ISHAGHE (QA / Testing)

- [ ] Data quality tests passed
- [ ] FK/PK integrity verified
- [ ] Dashboard queries validated
- [ ] Performance benchmarked
- [ ] Test report documented
- [ ] Issues logged + resolved
- [ ] Sign-off given

---

## 🎯 Contribution Equal Criteria

**Each person will:**

- ✅ Contribute daily (stand-up)
- ✅ Own their deliverables
- ✅ Support others (pair programming)
- ✅ Document their work
- ✅ Present in final demo

\*\*Success = All 5 contribute equally to:

1. Infrastructure ready (TOUBA lead)
2. Data loaded + validated (YEMAME lead)
3. Dashboard working (KHADIJE lead)
4. Architecture documented (OUMLVADLI lead)
5. Testing complete (ISHAGHE lead)

---

## 📞 Communication Rules

| Issue                 | Owner            | Escalate if                   |
| --------------------- | ---------------- | ----------------------------- |
| Docker won't start    | TOUBA            | Can't fix in 30 min           |
| Query too slow        | YEMAME + KHADIJE | Still slow after optimization |
| Dashboard error       | KHADIJE          | Data issue suspected          |
| Architecture question | OUMLVADLI        | Team can't decide             |
| Test failed           | ISHAGHE          | Root cause uncertain          |

---

## 🏁 Final Deliverables (Chacun signe)

```
Project: NAFAD-PAY G4 DWH ✅

Infrastructure:    ✓ TOUBA + Team review
ETL Pipeline:      ✓ YEMAME + Team review
Dashboard:         ✓ KHADIJE + Team review
Architecture:      ✓ OUMLVADLI + Team review
Testing:           ✓ ISHAGHE + Team sign-off

FINAL APPROVAL:    ✓ All 5 signed
```

---

**Chacun a son rôle, tous contribuent 20%!** 🚀
