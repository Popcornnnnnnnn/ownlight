#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.local"
  set +a
fi

base_bundle_id="${PRIVATE_MOMENTS_IOS_BUNDLE_ID:-dev.privatemoments.app}"
uat_bundle_id="${PRIVATE_MOMENTS_UAT_IOS_BUNDLE_ID:-${base_bundle_id}.uat}"

export PRIVATE_MOMENTS_IOS_BUNDLE_ID="$uat_bundle_id"
export PRIVATE_MOMENTS_IOS_SHARE_BUNDLE_ID="${PRIVATE_MOMENTS_UAT_IOS_SHARE_BUNDLE_ID:-${uat_bundle_id}.share}"
export PRIVATE_MOMENTS_IOS_TESTS_BUNDLE_ID="${PRIVATE_MOMENTS_UAT_IOS_TESTS_BUNDLE_ID:-${uat_bundle_id}.tests}"
export PRIVATE_MOMENTS_IOS_LIST_TESTS_BUNDLE_ID="${PRIVATE_MOMENTS_UAT_IOS_LIST_TESTS_BUNDLE_ID:-${uat_bundle_id}.list-continuation-tests}"
export PRIVATE_MOMENTS_IOS_APP_GROUP="${PRIVATE_MOMENTS_UAT_IOS_APP_GROUP:-group.${uat_bundle_id}}"
export PRIVATE_MOMENTS_ICLOUD_CONTAINER_ID="${PRIVATE_MOMENTS_UAT_ICLOUD_CONTAINER_ID:-iCloud.${uat_bundle_id}}"
export PRIVATE_MOMENTS_IOS_DISPLAY_NAME="${PRIVATE_MOMENTS_UAT_IOS_DISPLAY_NAME:-Ownlight UAT}"
export PRIVATE_MOMENTS_IOS_SHARE_DISPLAY_NAME="${PRIVATE_MOMENTS_UAT_IOS_SHARE_DISPLAY_NAME:-Save to Ownlight UAT}"
export PRIVATE_MOMENTS_SKIP_ENV_LOCAL=1

echo "Installing isolated UAT build:"
echo "  App: $PRIVATE_MOMENTS_IOS_DISPLAY_NAME"
echo "  Bundle ID: $PRIVATE_MOMENTS_IOS_BUNDLE_ID"
echo "  App Group: $PRIVATE_MOMENTS_IOS_APP_GROUP"
echo "  iCloud Container: $PRIVATE_MOMENTS_ICLOUD_CONTAINER_ID"
echo

exec "$ROOT_DIR/scripts/run-ios-device.sh"
