#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="$ROOT_DIR/deploy"
ENV_FILE="$DEPLOY_DIR/.env"

mkdir -p "$DEPLOY_DIR/data"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$DEPLOY_DIR/.env.example" "$ENV_FILE"
fi

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
  fi
}

JWT="$(random_secret)"
PASS="$(random_secret | cut -c1-28)"

python3 - "$ENV_FILE" "$JWT" "$PASS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
jwt = sys.argv[2]
password = sys.argv[3]
text = path.read_text(encoding="utf-8")
text = text.replace("REPLACE_WITH_A_LONG_RANDOM_SECRET", jwt)
text = text.replace("REPLACE_WITH_A_LONG_RANDOM_PASSWORD", password)
path.write_text(text, encoding="utf-8")
PY

chmod 600 "$ENV_FILE"

echo "Initialized: $ENV_FILE"
echo "Generated a random bootstrap password and JWT secret."
echo "Edit BOOTSTRAP_ADMIN_EMAIL before first start."
echo
echo "Start with:"
echo "  cd $DEPLOY_DIR"
echo "  docker compose --env-file .env up -d"
