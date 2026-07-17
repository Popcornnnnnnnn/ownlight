#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/ios/Config"
LOCAL_CONFIG="$CONFIG_DIR/Local.xcconfig"

if [[ "${PRIVATE_MOMENTS_SKIP_ENV_LOCAL:-}" != "1" && -f "$ROOT_DIR/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.local"
  set +a
fi

mkdir -p "$CONFIG_DIR"

{
  echo "// Generated from .env.local by scripts/write-ios-local-config.sh."
  echo "// This file is git-ignored. Edit .env.local or this file for local signing."
  echo

  escape_xcconfig_value() {
    local value="$1"
    printf '%s' "$value" | sed 's|://|:/$()/|g'
  }

  write_setting() {
    local key="$1"
    local value="${!key:-}"
    if [[ -n "$value" ]]; then
      printf '%s = %s\n' "$key" "$(escape_xcconfig_value "$value")"
    fi
  }

  if [[ -z "${PRIVATE_MOMENTS_ICLOUD_CONTAINER_ID:-}" && -n "${PRIVATE_MOMENTS_IOS_BUNDLE_ID:-}" ]]; then
    PRIVATE_MOMENTS_ICLOUD_CONTAINER_ID="iCloud.${PRIVATE_MOMENTS_IOS_BUNDLE_ID}"
  fi

  write_setting PRIVATE_MOMENTS_IOS_BUNDLE_ID
  write_setting PRIVATE_MOMENTS_IOS_SHARE_BUNDLE_ID
  write_setting PRIVATE_MOMENTS_IOS_TESTS_BUNDLE_ID
  write_setting PRIVATE_MOMENTS_IOS_LIST_TESTS_BUNDLE_ID
  write_setting PRIVATE_MOMENTS_IOS_APP_GROUP
  write_setting PRIVATE_MOMENTS_ICLOUD_CONTAINER_ID
  write_setting PRIVATE_MOMENTS_ICLOUD_CONTAINER_ENVIRONMENT
  write_setting PRIVATE_MOMENTS_IOS_DISPLAY_NAME
  write_setting PRIVATE_MOMENTS_IOS_SHARE_DISPLAY_NAME
  write_setting PRIVATE_MOMENTS_DEVELOPMENT_TEAM
  write_setting PRIVATE_MOMENTS_FALLBACK_SERVER_URL
  write_setting PRIVATE_MOMENTS_PRIVACY_POLICY_URL
  write_setting PRIVATE_MOMENTS_PRIVACY_POLICY_URL_ZH_HANS
  write_setting PRIVATE_MOMENTS_PRIVACY_POLICY_URL_EN
  write_setting PRIVATE_MOMENTS_SUPPORT_URL
} >"$LOCAL_CONFIG"
