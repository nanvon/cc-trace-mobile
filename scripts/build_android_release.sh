#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

flutter build apk \
  --release \
  --target-platform android-arm64 \
  -P disable-abi-filtering=true

"$repo_root/scripts/verify_android_release.sh" \
  "$repo_root/build/app/outputs/flutter-apk/app-release.apk"
