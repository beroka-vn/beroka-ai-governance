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

require_code_block() {
  file=$1 expected=$2
  awk -v expected="$expected" '
    /^```/ {
      if (in_block) {
        if (block == expected) found = 1
        in_block = 0
        block = ""
      } else {
        in_block = 1
      }
      next
    }
    in_block {
      block = block (block ? "\n" : "") $0
    }
    END { exit found ? 0 : 1 }
  ' "$ROOT/$file" || fail "missing exact command block in $file"
}

first_code_block_after_heading() {
  file=$1 heading=$2
  awk -v heading="$heading" '
    $0 == heading { after_heading = 1; next }
    after_heading && !in_block && /^```/ { in_block = 1; next }
    in_block && /^```/ { exit }
    in_block { print }
  ' "$ROOT/$file"
}

reject_active_v100_release_gate() {
  active_lines=$(awk '
    /^## Release gate trước khi publish tag/ { in_gate = 1; next }
    in_gate && /^## / { exit }
    in_gate && /v1\.0\.0/ &&
      $0 !~ /immutable: never/ &&
      $0 !~ /Không dùng candidate flow/ &&
      $0 !~ /replace hoặc delete/ { print }
  ' "$ROOT/handbook.md")
  [ -z "$active_lines" ] ||
    fail 'release gate contains active v1.0.0 instructions'
}

reject_text() {
  file=$1 text=$2
  if grep -F "$text" "$ROOT/$file" >/dev/null; then
    fail "forbidden [$text] in $file"
  fi
}

[ "$(cat "$ROOT/VERSION")" = v1.0.1 ] ||
  fail 'VERSION is not v1.0.1'

require_text README.md '`v1.0.0` is the first public stable release'
require_text README.md 'Backend and Frontend repositories'
require_text handbook.md 'Chuyển quyết định cho developer'
require_text PACKAGE-DESIGN.md \
  '`v1.0.0` is the first public stable release'
require_text README.md 'releases/latest/download/bootstrap.sh'
require_text README.md 'sh -s -- --client codex'
require_text README.md 'one client on each execution environment'
require_text handbook.md 'AUTH_PENDING'
require_text handbook.md 'CONNECTOR_HEALTH_UNAVAILABLE'
require_text PACKAGE-DESIGN.md '15-second total deadline'
[ -f "$ROOT/release/bootstrap.sh.in" ] ||
  fail 'missing release launcher template'

interactive_launcher='curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex'
noninteractive_launcher='curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive'
[ "$(first_code_block_after_heading README.md '## Quick start')" = \
  "$interactive_launcher" ] ||
  fail 'README Quick start does not begin with the exact interactive launcher'
require_code_block README.md "$noninteractive_launcher"

reject_text handbook.md 'canonical remote chưa có `v1.0.0`'
reject_text handbook.md 'tạo annotated `v1.0.0`'
reject_text handbook.md 'Install published `v1.0.0`'
reject_active_v100_release_gate

for file in README.md handbook.md PACKAGE-DESIGN.md; do
  reject_text "$file" 'immutable legacy test sample'
  reject_text "$file" 'Backend-only'
  reject_text "$file" 'do not register a Frontend repository'
done
reject_text handbook.md 'GITHUB_PAT'
reject_text handbook.md 'GitHub client bắt buộc PAT'

printf '%s\n' 'First public release readiness: PASS'
