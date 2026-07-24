#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_text() {
  file=$1 text=$2
  grep -F "$text" "$ROOT/$file" >/dev/null ||
    fail "missing [$text] in $file"
}

reject_text() {
  file=$1 text=$2
  if grep -F "$text" "$ROOT/$file" >/dev/null; then
    fail "forbidden [$text] in $file"
  fi
}

[ "$(cat "$ROOT/VERSION")" = v1.0.0 ] ||
  fail 'VERSION is not v1.0.0'

require_text README.md '`v1.0.0` is the first public stable release'
require_text README.md 'Backend and Frontend repositories'
require_text README.md 'repo=$(git rev-parse --show-toplevel)'
require_text handbook.md 'Chuyển quyết định cho developer'
require_text PACKAGE-DESIGN.md \
  '`v1.0.0` is the first public stable release'

for file in README.md handbook.md PACKAGE-DESIGN.md; do
  reject_text "$file" 'immutable legacy test sample'
  reject_text "$file" 'Backend-only'
  reject_text "$file" 'do not register a Frontend repository'
done
reject_text handbook.md 'GITHUB_PAT'
reject_text handbook.md 'GitHub client bắt buộc PAT'

printf '%s\n' 'First public release readiness: PASS'
