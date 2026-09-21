#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="$ROOT_DIR/deploy"
DATA_DIR="$DEPLOY_DIR/data"
BACKUP_DIR="$ROOT_DIR/backups"
ENV_FILE="$DEPLOY_DIR/.env"
STAMP="$(date +%Y%m%d-%H%M%S)"
PLAIN_OUT="$BACKUP_DIR/cashbook-$STAMP.tar.gz"
PARTIAL_OUT="$PLAIN_OUT.partial"
SERVICE="cashbook-cloud"

mkdir -p "$BACKUP_DIR"

if [[ ! -d "$DATA_DIR" ]]; then
  echo "Data directory not found: $DATA_DIR" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Run scripts/server-init.sh first." >&2
  exit 1
fi

compose() {
  docker compose     -f "$DEPLOY_DIR/docker-compose.yml"     --env-file "$ENV_FILE"     "$@"
}

was_running=false
if compose ps --services --filter status=running 2>/dev/null | grep -qx "$SERVICE"; then
  was_running=true
fi

restart_if_needed() {
  if [[ "$was_running" == "true" ]]; then
    compose up -d "$SERVICE" >/dev/null
  fi
}

cleanup_partial() {
  rm -f "$PARTIAL_OUT"
}

trap 'restart_if_needed; cleanup_partial' EXIT

if [[ "$was_running" == "true" ]]; then
  echo "Stopping $SERVICE briefly for a consistent SQLite backup..."
  compose stop "$SERVICE" >/dev/null
fi

tar -C "$DEPLOY_DIR" -czf "$PARTIAL_OUT" data

# Bring the service back before doing slower integrity/encryption work.
restart_if_needed
was_running=false

tar -tzf "$PARTIAL_OUT" >/dev/null
mv "$PARTIAL_OUT" "$PLAIN_OUT"

# Optional encryption. Only the path is read from .env; the passphrase itself
# stays in a separate root-owned file.
PASSPHRASE_FILE="${CASHBOOK_BACKUP_PASSPHRASE_FILE:-}"
if [[ -z "$PASSPHRASE_FILE" ]]; then
  PASSPHRASE_FILE="$(grep -E '^CASHBOOK_BACKUP_PASSPHRASE_FILE=' "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
fi

FINAL_OUT="$PLAIN_OUT"
if [[ -n "$PASSPHRASE_FILE" ]]; then
  if [[ ! -r "$PASSPHRASE_FILE" ]]; then
    echo "Backup passphrase file is not readable: $PASSPHRASE_FILE" >&2
    exit 1
  fi
  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required for encrypted backups." >&2
    exit 1
  fi

  ENCRYPTED_OUT="$PLAIN_OUT.enc"
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000     -in "$PLAIN_OUT"     -out "$ENCRYPTED_OUT"     -pass "file:$PASSPHRASE_FILE"

  rm -f "$PLAIN_OUT"
  FINAL_OUT="$ENCRYPTED_OUT"
fi

chmod 600 "$FINAL_OUT"

# Keep local backups for 14 days by default.
find "$BACKUP_DIR" -type f   \( -name 'cashbook-*.tar.gz' -o -name 'cashbook-*.tar.gz.enc' \)   -mtime +14 -delete

echo "Backup created: $FINAL_OUT"
