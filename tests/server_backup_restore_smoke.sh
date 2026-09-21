#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

TEST_REPO="$TMP_ROOT/repo"
FAKE_BIN="$TMP_ROOT/fakebin"
mkdir -p "$TEST_REPO/scripts" "$TEST_REPO/deploy/data" "$FAKE_BIN"

cp "$ROOT_DIR/scripts/backup.sh" "$TEST_REPO/scripts/backup.sh"
cp "$ROOT_DIR/scripts/restore.sh" "$TEST_REPO/scripts/restore.sh"
chmod +x "$TEST_REPO/scripts/backup.sh" "$TEST_REPO/scripts/restore.sh"

cat > "$FAKE_BIN/docker" <<'DOCKER_EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${FAKE_DOCKER_LOG:?}"
echo "$*" >> "$LOG"
if [[ "$*" == *" ps --services --filter status=running"* ]]; then
  echo cashbook-cloud
fi
DOCKER_EOF
chmod +x "$FAKE_BIN/docker"

: > "$TEST_REPO/deploy/docker-compose.yml"
cat > "$TEST_REPO/deploy/.env" <<'ENV_EOF'
JWT_SECRET=test
BOOTSTRAP_ADMIN_EMAIL=test@example.com
BOOTSTRAP_ADMIN_PASSWORD=test
ENV_EOF

export PATH="$FAKE_BIN:$PATH"
export FAKE_DOCKER_LOG="$TMP_ROOT/docker.log"
: > "$FAKE_DOCKER_LOG"

mkdir -p "$TEST_REPO/deploy/data"
echo 'seed-data' > "$TEST_REPO/deploy/data/state.txt"

# 1. Plain backup: consistent archive, restrictive mode, service stop/start.
bash "$TEST_REPO/scripts/backup.sh" >/dev/null
PLAIN="$(find "$TEST_REPO/backups" -type f -name '*.tar.gz' | head -n1)"
test -f "$PLAIN"
tar -tzf "$PLAIN" | grep -q '^data/state.txt$'
[[ "$(stat -c '%a' "$PLAIN")" == "600" ]]
grep -q 'stop cashbook-cloud' "$FAKE_DOCKER_LOG"
grep -q 'up -d cashbook-cloud' "$FAKE_DOCKER_LOG"

# 2. Encrypted backup: encrypted artifact exists, plaintext does not.
rm -rf "$TEST_REPO/backups"
mkdir -p "$TEST_REPO/backups"
echo 'test-passphrase-which-is-not-a-real-secret' > "$TMP_ROOT/passphrase"
chmod 600 "$TMP_ROOT/passphrase"
echo "CASHBOOK_BACKUP_PASSPHRASE_FILE=$TMP_ROOT/passphrase" >> "$TEST_REPO/deploy/.env"

bash "$TEST_REPO/scripts/backup.sh" >/dev/null
ENCRYPTED="$(find "$TEST_REPO/backups" -type f -name '*.tar.gz.enc' | head -n1)"
test -f "$ENCRYPTED"
! find "$TEST_REPO/backups" -type f -name '*.tar.gz' | grep -q .

openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000   -in "$ENCRYPTED"   -out "$TMP_ROOT/decrypted.tar.gz"   -pass "file:$TMP_ROOT/passphrase"
tar -tzf "$TMP_ROOT/decrypted.tar.gz" | grep -q '^data/state.txt$'

# Preserve source for restore tests.
cp "$ENCRYPTED" "$TMP_ROOT/restore-source.tar.gz.enc"

# 3. Encryption requested but key unavailable: fail closed, no artifact.
rm -rf "$TEST_REPO/backups"
mkdir -p "$TEST_REPO/backups"
sed -i "s#^CASHBOOK_BACKUP_PASSPHRASE_FILE=.*#CASHBOOK_BACKUP_PASSPHRASE_FILE=$TMP_ROOT/missing-key#" "$TEST_REPO/deploy/.env"
if bash "$TEST_REPO/scripts/backup.sh" >/dev/null 2>&1; then
  echo "Expected encrypted backup with missing key to fail." >&2
  exit 1
fi
! find "$TEST_REPO/backups" -type f | grep -q .

# Restore tests use the valid key.
sed -i "s#^CASHBOOK_BACKUP_PASSPHRASE_FILE=.*#CASHBOOK_BACKUP_PASSPHRASE_FILE=$TMP_ROOT/passphrase#" "$TEST_REPO/deploy/.env"

# 4. Successful restore: backup becomes live; previous live data is retained.
rm -rf "$TEST_REPO/deploy/data" "$TEST_REPO/deploy"/data.pre-restore-*
mkdir -p "$TEST_REPO/deploy/data"
echo 'current-live-data' > "$TEST_REPO/deploy/data/state.txt"
: > "$FAKE_DOCKER_LOG"

bash "$TEST_REPO/scripts/restore.sh" "$TMP_ROOT/restore-source.tar.gz.enc" --yes >/dev/null
[[ "$(cat "$TEST_REPO/deploy/data/state.txt")" == 'seed-data' ]]
ROLLBACK="$(find "$TEST_REPO/deploy" -maxdepth 1 -type d -name 'data.pre-restore-*' | head -n1)"
test -n "$ROLLBACK"
[[ "$(cat "$ROLLBACK/state.txt")" == 'current-live-data' ]]
grep -q 'stop cashbook-cloud' "$FAKE_DOCKER_LOG"
grep -q 'up -d cashbook-cloud' "$FAKE_DOCKER_LOG"

# 5. Corrupt archive: fail before touching live data or stopping service.
rm -rf "$TEST_REPO/deploy/data" "$TEST_REPO/deploy"/data.pre-restore-*
mkdir -p "$TEST_REPO/deploy/data"
echo 'must-survive' > "$TEST_REPO/deploy/data/state.txt"
printf 'not-a-tar' > "$TMP_ROOT/corrupt.tar.gz"
: > "$FAKE_DOCKER_LOG"

if bash "$TEST_REPO/scripts/restore.sh" "$TMP_ROOT/corrupt.tar.gz" --yes >/dev/null 2>&1; then
  echo "Expected corrupt restore to fail." >&2
  exit 1
fi
[[ "$(cat "$TEST_REPO/deploy/data/state.txt")" == 'must-survive' ]]
! grep -q 'stop cashbook-cloud' "$FAKE_DOCKER_LOG"

# 6. Wrong encryption key: fail before touching live data.
echo 'wrong-passphrase' > "$TMP_ROOT/wrong-passphrase"
chmod 600 "$TMP_ROOT/wrong-passphrase"
sed -i "s#^CASHBOOK_BACKUP_PASSPHRASE_FILE=.*#CASHBOOK_BACKUP_PASSPHRASE_FILE=$TMP_ROOT/wrong-passphrase#" "$TEST_REPO/deploy/.env"
: > "$FAKE_DOCKER_LOG"

if bash "$TEST_REPO/scripts/restore.sh" "$TMP_ROOT/restore-source.tar.gz.enc" --yes >/dev/null 2>&1; then
  echo "Expected restore with wrong passphrase to fail." >&2
  exit 1
fi
[[ "$(cat "$TEST_REPO/deploy/data/state.txt")" == 'must-survive' ]]
! grep -q 'stop cashbook-cloud' "$FAKE_DOCKER_LOG"

echo "Cashbook backup/restore smoke tests passed."
