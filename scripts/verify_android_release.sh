#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
apk_path="${1:-$repo_root/build/app/outputs/flutter-apk/app-release.apk}"
certificate_pin_file="$repo_root/android/release-signing-certificate.sha256"

fail() {
  printf '❌ %s\n' "$1" >&2
  exit 1
}

[[ -f "$apk_path" ]] || fail "APK 不存在：$apk_path"
[[ -f "$certificate_pin_file" ]] || fail "正式签名证书指纹不存在：$certificate_pin_file"

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$sdk_root" && -f "$repo_root/android/local.properties" ]]; then
  sdk_root="$(sed -n 's/^sdk.dir=//p' "$repo_root/android/local.properties" | tail -n 1)"
fi
[[ -n "$sdk_root" ]] || fail "未找到 Android SDK"

apksigner="$(find "$sdk_root/build-tools" -mindepth 2 -maxdepth 2 -type f -name apksigner | sort | tail -n 1)"
apkanalyzer="$sdk_root/cmdline-tools/latest/bin/apkanalyzer"
[[ -x "$apksigner" ]] || fail "未找到 apksigner"
[[ -x "$apkanalyzer" ]] || fail "未找到 apkanalyzer"

pubspec_version="$(sed -n 's/^version:[[:space:]]*//p' "$repo_root/pubspec.yaml" | head -n 1)"
[[ "$pubspec_version" == *+* ]] || fail "pubspec.yaml version 必须同时包含 versionName 和 versionCode"
expected_version_name="${pubspec_version%+*}"
expected_version_code="${pubspec_version##*+}"

signature_report="$("$apksigner" verify --verbose --print-certs "$apk_path" 2>&1)"
actual_certificate_sha256="$(
  printf '%s\n' "$signature_report" |
    sed -En \
      -e 's/^[[:space:]]*Signer #[0-9]+ certificate SHA-256 digest:[[:space:]]*//p' \
      -e 's/^[[:space:]]*V[0-9.]+ Signer: certificate SHA-256 digest:[[:space:]]*//p' |
    head -n 1 |
    tr -d '[:space:]:' |
    tr '[:upper:]' '[:lower:]'
)"
expected_certificate_sha256="$(
  tr -d '[:space:]:' < "$certificate_pin_file" |
    tr '[:upper:]' '[:lower:]'
)"
signer_count="$(
  printf '%s\n' "$signature_report" |
    sed -n 's/^[[:space:]]*Number of signers:[[:space:]]*//p' |
    head -n 1 |
    tr -d '[:space:]'
)"

[[ -n "$signer_count" ]] || fail "无法从 apksigner 输出解析 signer 数量"
[[ "$signer_count" == "1" ]] || fail "APK signer 数量不是 1：${signer_count}"
if [[ -z "$actual_certificate_sha256" ]]; then
  printf 'apksigner 输出：\n%s\n' "$signature_report" >&2
  fail "无法从 apksigner 输出解析 APK 证书指纹"
fi
[[ "$actual_certificate_sha256" == "$expected_certificate_sha256" ]] ||
  fail "APK 证书不是仓库钉扎的正式证书：实际=${actual_certificate_sha256}，期望=${expected_certificate_sha256}"

actual_version_code="$("$apkanalyzer" manifest version-code "$apk_path")"
actual_version_name="$("$apkanalyzer" manifest version-name "$apk_path")"
[[ "$actual_version_code" == "$expected_version_code" ]] ||
  fail "versionCode 不一致：APK=${actual_version_code}，pubspec=${expected_version_code}"
[[ "$actual_version_name" == "$expected_version_name" ]] ||
  fail "versionName 不一致：APK=${actual_version_name}，pubspec=${expected_version_name}"

actual_abis="$(
  unzip -Z1 "$apk_path" |
    awk -F/ '$1 == "lib" && NF >= 3 { print $2 }' |
    sort -u |
    paste -sd, -
)"
[[ "$actual_abis" == "arm64-v8a" ]] || fail "ABI 不符合预期：${actual_abis}"

apk_sha256="$(shasum -a 256 "$apk_path" | awk '{ print $1 }')"
printf '%s  %s\n' "$apk_sha256" "$(basename "$apk_path")" > "$apk_path.sha256"

printf '✅ Android Release APK 验收通过\n'
printf 'APK: %s\n' "$apk_path"
printf '证书 SHA-256: %s\n' "$actual_certificate_sha256"
printf 'ABI: %s\n' "$actual_abis"
printf '版本: %s (%s)\n' "$actual_version_name" "$actual_version_code"
printf 'APK SHA-256: %s\n' "$apk_sha256"
