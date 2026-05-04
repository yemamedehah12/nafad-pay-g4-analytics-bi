#!/bin/bash
# ============================================================
# NAFAD PAY G4 — Script de démarrage complet
# Usage : ./scripts/run_all.sh
# ============================================================

set -e  # Arrêter si une commande échoue

echo "=============================="
echo " NAFAD PAY G4 — Démarrage"
echo "=============================="

# Vérifier que .env existe
if [ ! -f .env ]; then
    echo "❌ Fichier .env manquant"
    echo "   Tape : cp .env.example .env"
    exit 1
fi

# Vérifier que les CSV sont présents
if [ ! -f data/stg_transactions.csv ]; then
    echo "❌ CSV manquants dans data/"
    echo "   Copie les fichiers CSV dans le dossier data/"
    exit 1
fi

# Démarrer PostgreSQL
echo "→ Démarrage PostgreSQL..."
docker compose up -d postgres_dwh

# Attendre que PostgreSQL soit healthy
echo "→ Attente que PostgreSQL soit prêt..."
until [ "$(docker inspect --format='{{.State.Health.Status}}' nafad_dwh 2>/dev/null)" = "healthy" ]; do
    sleep 3
done

# Lancer l'ETL
echo "→ Chargement des données..."
docker compose --profile etl run --rm etl

# Démarrer Metabase
echo "→ Démarrage Metabase..."
docker compose up -d metabase

echo ""
echo "=============================="
echo " ✅ Tout est prêt !"
echo " Dashboard : http://localhost:3000"
echo "=============================="