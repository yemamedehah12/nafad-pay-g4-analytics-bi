# ============================================================
# NAFAD PAY G4 — Script de démarrage (Windows PowerShell)
# Usage : cd G4_DWH ; .\scripts\run_all.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir   # = G4_DWH/

Set-Location $Root

Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "  NAFAD PAY G4 — Démarrage" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Vérifier Docker ──────────────────────────────────────
Write-Host "[ 1/5 ] Vérification de Docker..." -ForegroundColor Yellow
try {
    docker info > $null 2>&1
    Write-Host "        Docker OK" -ForegroundColor Green
} catch {
    Write-Host "ERREUR : Docker n'est pas lancé. Démarrez Docker Desktop puis relancez." -ForegroundColor Red
    exit 1
}

# ── 2. Créer .env si absent ─────────────────────────────────
Write-Host "[ 2/5 ] Vérification du fichier .env..." -ForegroundColor Yellow
if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "        .env créé depuis .env.example" -ForegroundColor Green
} else {
    Write-Host "        .env déjà présent" -ForegroundColor Green
}

# ── 3. Vérifier les CSV ─────────────────────────────────────
Write-Host "[ 3/5 ] Vérification des fichiers CSV..." -ForegroundColor Yellow
$csvFiles = @("stg_users.csv", "stg_merchants.csv", "stg_agencies.csv", "stg_transactions.csv")
$missing = @()
foreach ($f in $csvFiles) {
    if (-not (Test-Path "data\$f")) { $missing += $f }
}
if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "ERREUR : Fichiers CSV manquants dans data\" -ForegroundColor Red
    foreach ($f in $missing) { Write-Host "         - $f" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Copiez les 4 CSV dans le dossier G4_DWH\data\ puis relancez." -ForegroundColor Yellow
    exit 1
}
Write-Host "        4 CSV trouvés" -ForegroundColor Green

# ── 4. Démarrer PostgreSQL et attendre qu'il soit prêt ──────
Write-Host "[ 4/5 ] Démarrage PostgreSQL..." -ForegroundColor Yellow
docker compose up -d postgres_dwh

Write-Host "        Attente que PostgreSQL soit prêt..." -ForegroundColor Gray
$maxWait = 60
$waited  = 0
do {
    Start-Sleep -Seconds 3
    $waited += 3
    $status = docker inspect --format "{{.State.Health.Status}}" nafad_dwh 2>$null
} while ($status -ne "healthy" -and $waited -lt $maxWait)

if ($status -ne "healthy") {
    Write-Host "ERREUR : PostgreSQL n'est pas prêt après $maxWait secondes." -ForegroundColor Red
    Write-Host "Vérifiez les logs : docker logs nafad_dwh" -ForegroundColor Yellow
    exit 1
}
Write-Host "        PostgreSQL prêt" -ForegroundColor Green

# ── 5. Lancer l'ETL ─────────────────────────────────────────
Write-Host "[ 5/5 ] Chargement des données (ETL)..." -ForegroundColor Yellow
docker compose --profile etl run --rm etl
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR : L'ETL a échoué. Consultez les logs ci-dessus." -ForegroundColor Red
    exit 1
}
Write-Host "        ETL terminé avec succès" -ForegroundColor Green

# ── 6. Démarrer Metabase ────────────────────────────────────
Write-Host ""
Write-Host "Démarrage Metabase (peut prendre 1-2 minutes)..." -ForegroundColor Yellow
docker compose up -d metabase

Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "  Tout est prêt !" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Dashboard  : http://localhost:3000" -ForegroundColor White
Write-Host "  PostgreSQL : localhost:5432  |  db=dwh  user=dwh_user" -ForegroundColor White
Write-Host ""
Write-Host "Commandes utiles :" -ForegroundColor Gray
Write-Host "  Voir les logs ETL   : docker logs nafad_etl" -ForegroundColor Gray
Write-Host "  Voir les logs PG    : docker logs nafad_dwh" -ForegroundColor Gray
Write-Host "  Arrêter tout        : docker compose down" -ForegroundColor Gray
Write-Host "  Tout réinitialiser  : docker compose down -v" -ForegroundColor Gray
Write-Host ""

# Ouvrir le navigateur automatiquement
Start-Process "http://localhost:3000"
