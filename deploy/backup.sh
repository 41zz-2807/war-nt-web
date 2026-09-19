#!/usr/bin/env bash
# ============================================================================
#  Warnet Billing System - backup database Postgres (produksi)
#  Pakai:  BACKUP_DIR=/var/backups/billing ./backup.sh
#  Cron:   0 3 * * * BACKUP_DIR=/var/backups/billing /path/repo/deploy/backup.sh >> /var/log/billing-backup.log 2>&1
# ============================================================================
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
PG_CONTAINER="${PG_CONTAINER:-billing-postgres}"
PG_USER="${PG_USER:-billing_user}"
PG_DB="${PG_DB:-billing}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

TS="$(date +%Y%m%d_%H%M%S)"
OUT="${BACKUP_DIR}/billing_${TS}.sql.gz"

mkdir -p "${BACKUP_DIR}"
docker exec "${PG_CONTAINER}" pg_dump -U "${PG_USER}" "${PG_DB}" | gzip > "${OUT}"

find "${BACKUP_DIR}" -maxdepth 1 -name 'billing_*.sql.gz' -mtime "+${RETENTION_DAYS}" -delete

echo "[backup] OK -> ${OUT} ($(du -h "${OUT}" | cut -f1))"
echo "[backup] cleanup: simpan ${RETENTION_DAYS} hari di ${BACKUP_DIR}"