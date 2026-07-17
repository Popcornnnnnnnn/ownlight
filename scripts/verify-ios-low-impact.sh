#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
XCODEBUILD_JOBS="${PRIVATE_MOMENTS_XCODEBUILD_JOBS:-2}"

cd "$IOS_DIR"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

xcodebuild \
  -project PrivateMoments.xcodeproj \
  -scheme PrivateMoments \
  -destination generic/platform=iOS \
  -configuration Debug \
  -jobs "$XCODEBUILD_JOBS" \
  CODE_SIGNING_ALLOWED=NO \
  build
