#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# V0.1 hard policy: these permissions/capabilities must not enter the product
# without an explicit architecture decision and checklist update.
FORBIDDEN_PATTERNS=(
  "android.permission.READ_SMS"
  "android.permission.RECEIVE_SMS"
  "android.permission.SEND_SMS"
  "android.permission.BIND_ACCESSIBILITY_SERVICE"
  "android.media.projection.MediaProjectionManager"
)

SCAN_DIRS=()
for dir in app mobile android prototype; do
  if [[ -d "$ROOT_DIR/$dir" ]]; then
    SCAN_DIRS+=("$ROOT_DIR/$dir")
  fi
done

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
  echo "No application source directories yet; privacy audit passed."
  exit 0
fi

failed=0
for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  if grep -RIn --exclude-dir=build --exclude-dir=.gradle --exclude='*.md' -- "$pattern" "${SCAN_DIRS[@]}" >/tmp/cashbook-privacy-match 2>/dev/null; then
    echo "Forbidden V0.1 capability found: $pattern" >&2
    cat /tmp/cashbook-privacy-match >&2
    failed=1
  fi
done

rm -f /tmp/cashbook-privacy-match

if [[ "$failed" -ne 0 ]]; then
  echo "Privacy audit failed. Review docs/PRIVACY_ARCHITECTURE.md before adding sensitive capabilities." >&2
  exit 1
fi

echo "Privacy audit passed."
