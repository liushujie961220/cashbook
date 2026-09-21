#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$ROOT_DIR/deploy/data"
BACKUP_DIR="$ROOT_DIR/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/cashbook-$STAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

if [[ ! -d "$DATA_DIR" ]]; then
  echo "Data directory not found: $DATA_DIR" >&2
  exit 1
fi

tar -C "$ROOT_DIR/deploy" -czf "$OUT" data
chmod 600 "$OUT"

# Keep local backups for 14 days by default.
find "$BACKUP_DIR" -type f -name 'cashbook-*.tar.gz' -mtime +14 -delete

echo "$OUT"
