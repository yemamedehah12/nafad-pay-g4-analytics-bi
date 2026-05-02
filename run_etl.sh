#!/bin/bash
# NAFAD PAY G4 — Pipeline ETL complet
# Usage : bash run_etl.sh
# Prérequis : Docker, fichiers CSV dans data/

set -e

CONTAINER="nafad_dwh_postgres"
PSQL="docker exec -i $CONTAINER psql -U dwh_user -d dwh_nafad_pay"

check() {
    echo "── Vérification prérequis ──"
    [ -f .env ] || { echo "ERREUR: .env manquant → cp .env.example .env"; exit 1; }
    [ -f data/stg_transactions.csv ] || { echo "ERREUR: CSV manquants dans data/"; exit 1; }
    echo "OK"
}

start_db() {
    echo "── Démarrage PostgreSQL ──"
    docker compose up -d postgres_dwh
    echo -n "Attente santé DB"
    until docker exec $CONTAINER pg_isready -U dwh_user -q 2>/dev/null; do
        echo -n "."
        sleep 2
    done
    echo " OK"
}

run_etl() {
    echo "── ETL : $(date '+%H:%M:%S') ──"
    for f in sql/00 sql/01 sql/02 sql/03 sql/04 sql/05 sql/06 sql/07 sql/08; do
        script=$(ls ${f}_*.sql 2>/dev/null | head -1)
        [ -z "$script" ] && continue
        echo "  → $(basename $script)"
        $PSQL -f "/sql/$(basename $script)"
    done
    echo "  → Vues matérialisées"
    $PSQL -f "/sql/11_materialized_views.sql"
    echo "ETL terminé : $(date '+%H:%M:%S')"
}

start_bi() {
    echo "── Démarrage Superset ──"
    docker compose --profile bi up -d superset
    echo "Dashboard : http://localhost:8088  (admin / Admin1234)"
}

check
start_db
run_etl
start_bi

echo ""
echo "✓ Tout est prêt"
echo "  PostgreSQL : localhost:5432"
echo "  Superset   : http://localhost:8088"
echo "  pgAdmin    : docker compose --profile admin up -d"
