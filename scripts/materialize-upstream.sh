#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="$ROOT_DIR/UPSTREAM.lock"
WORK_DIR="$ROOT_DIR/.worktree"

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "Missing $LOCK_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$LOCK_FILE"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

clone_at() {
  local repo="$1"
  local commit="$2"
  local target="$3"

  git clone --filter=blob:none --no-checkout "$repo" "$target"
  git -C "$target" fetch --depth 1 origin "$commit"
  git -C "$target" checkout --detach "$commit"
}

clone_at "$BEECOUNT_REPO" "$BEECOUNT_COMMIT" "$WORK_DIR/BeeCount"
clone_at "$BEECOUNT_CLOUD_REPO" "$BEECOUNT_CLOUD_COMMIT" "$WORK_DIR/BeeCount-Cloud"

# Apply Cashbook-owned source overlay first.
python3 "$ROOT_DIR/scripts/apply-app-overlay.py"   "$WORK_DIR/BeeCount"   "$ROOT_DIR/overlay/app"

apply_patch_dir() {
  local target="$1"
  local patch_dir="$2"

  [[ -d "$patch_dir" ]] || return 0
  shopt -s nullglob
  local patches=("$patch_dir"/*.patch)
  for patch in "${patches[@]}"; do
    echo "Applying $(basename "$patch")"
    git -C "$target" apply --3way "$patch"
  done
  shopt -u nullglob
}

# Patch directories remain available for changes that are not suited to overlay injection.
apply_patch_dir "$WORK_DIR/BeeCount" "$ROOT_DIR/patches/app"
apply_patch_dir "$WORK_DIR/BeeCount-Cloud" "$ROOT_DIR/patches/cloud"

echo
echo "Materialized pinned sources:"
echo "  $WORK_DIR/BeeCount"
echo "  $WORK_DIR/BeeCount-Cloud"
