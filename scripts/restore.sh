#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="$ROOT_DIR/deploy"
ENV_FILE="$DEPLOY_DIR/.env"
SERVICE="cashbook-cloud"

usage() {
  echo "Usage: $0 <backup.tar.gz|backup.tar.gz.enc> --yes" >&2
  exit 2
}

[[ $# -eq 2 ]] || usage
BACKUP="$1"
[[ "$2" == "--yes" ]] || usage

if [[ ! -f "$BACKUP" ]]; then
  echo "Backup not found: $BACKUP" >&2
  exit 1
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Run scripts/server-init.sh first." >&2
  exit 1
fi

compose() {
  docker compose     -f "$DEPLOY_DIR/docker-compose.yml"     --env-file "$ENV_FILE"     "$@"
}

TMP_ARCHIVE="$(mktemp "$ROOT_DIR/.cashbook-restore-XXXXXX.tar.gz")"
cleanup() {
  rm -f "$TMP_ARCHIVE"
}
trap cleanup EXIT

if [[ "$BACKUP" == *.enc ]]; then
  PASSPHRASE_FILE="${CASHBOOK_BACKUP_PASSPHRASE_FILE:-}"
  if [[ -z "$PASSPHRASE_FILE" ]]; then
    PASSPHRASE_FILE="$(grep -E '^CASHBOOK_BACKUP_PASSPHRASE_FILE=' "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  fi
  if [[ -z "$PASSPHRASE_FILE" || ! -r "$PASSPHRASE_FILE" ]]; then
    echo "Encrypted backup requires a readable CASHBOOK_BACKUP_PASSPHRASE_FILE." >&2
    exit 1
  fi

  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000     -in "$BACKUP"     -out "$TMP_ARCHIVE"     -pass "file:$PASSPHRASE_FILE"
else
  cp "$BACKUP" "$TMP_ARCHIVE"
fi

tar -tzf "$TMP_ARCHIVE" >/dev/null
if ! tar -tzf "$TMP_ARCHIVE" | awk '
  /^data\// { found = 1 }
  END { exit(found ? 0 : 1) }
'; then
  echo "Backup does not contain a data/ directory." >&2
  exit 1
fi

was_running=false
if compose ps --services --filter status=running 2>/dev/null | grep -qx "$SERVICE"; then
  was_running=true
  compose stop "$SERVICE" >/dev/null
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
ROLLBACK_DIR="$DEPLOY_DIR/data.pre-restore-$STAMP"

restore_failed=true
finish_restore() {
  if [[ "$restore_failed" == "true" && -d "$ROLLBACK_DIR" ]]; then
    rm -rf "$DEPLOY_DIR/data"
    mv "$ROLLBACK_DIR" "$DEPLOY_DIR/data"
  fi

  if [[ "$was_running" == "true" ]]; then
    compose up -d "$SERVICE" >/dev/null
  fi
}
trap 'finish_restore; cleanup' EXIT

if [[ -d "$DEPLOY_DIR/data" ]]; then
  mv "$DEPLOY_DIR/data" "$ROLLBACK_DIR"
fi

tar -C "$DEPLOY_DIR" -xzf "$TMP_ARCHIVE"
test -d "$DEPLOY_DIR/data"

restore_failed=false

if [[ "$was_running" == "true" ]]; then
  compose up -d "$SERVICE" >/dev/null
  was_running=false
fi

echo "Restore completed."
echo "Previous data kept at: $ROLLBACK_DIR"
echo "After validation, remove that rollback directory manually."
