#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
pubspec="$repo_root/pubspec.yaml"
tag="${1:-}"

fail() {
  printf '❌ %s\n' "$1" >&2
  exit 1
}

[[ -f "$pubspec" ]] || fail "未找到 pubspec.yaml"

version="$(
  sed -n 's/^version:[[:space:]]*//p' "$pubspec" |
    head -n 1 |
    tr -d '[:space:]'
)"

[[ "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?)\+([1-9][0-9]*)$ ]] ||
  fail "pubspec.yaml version 必须是有效的 versionName+versionCode：${version:-<empty>}"

version_name="${BASH_REMATCH[1]}"
version_code="${BASH_REMATCH[3]}"
expected_tag="v${version_name}"

if [[ -n "$tag" && "$tag" != "$expected_tag" ]]; then
  fail "tag ${tag} 必须等于 ${expected_tag}"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'version_name=%s\n' "$version_name"
    printf 'version_code=%s\n' "$version_code"
  } >> "$GITHUB_OUTPUT"
fi

printf '✅ Release 版本校验通过：%s (%s)\n' "$expected_tag" "$version_code"
