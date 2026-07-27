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

first_code_block_after_heading() {
  file=$1 heading=$2
  awk -v heading="$heading" '
    !after_heading && $0 == heading { after_heading = 1; next }
    after_heading && !in_block && /^#{1,6}[[:space:]]/ { exit }
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

require_text README.md 'Backend and Frontend repositories'
require_text handbook.md 'Chuyển quyết định cho developer'
require_text README.md 'releases/latest/download/bootstrap.sh'
require_text README.md 'one client on each execution environment'
require_text handbook.md 'AUTH_PENDING'
require_text handbook.md 'CONNECTOR_HEALTH_UNAVAILABLE'
require_text PACKAGE-DESIGN.md '15-second total deadline'
require_text PACKAGE-DESIGN.md \
  'The release launcher asset is piped into a shell; it clones the embedded'
require_text PACKAGE-DESIGN.md \
  'annotated tag and invokes the package CLI only after tag type, peeled commit,'
require_text PACKAGE-DESIGN.md 'checked-out HEAD each equal the embedded commit'
[ -f "$ROOT/release/bootstrap.sh.in" ] ||
  fail 'missing release launcher template'

noninteractive_launcher='curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive'
section_fixture=$(mktemp "$ROOT/tests/.release-section.XXXXXX")
trap 'rm -f "$section_fixture"' EXIT HUP INT TERM
{
  printf '%s\n' '### Release launcher' 'No launcher in this section.'
  printf '%s\n' '### Release launcher' '```bash'
  printf '%s\n' "$noninteractive_launcher" '```'
} >"$section_fixture"
if [ "$(first_code_block_after_heading \
  "tests/${section_fixture##*/}" '### Release launcher')" = \
  "$noninteractive_launcher" ]; then
  fail 'section parser accepts a launcher from a later section'
fi
rm -f "$section_fixture"
trap - EXIT HUP INT TERM

[ "$(first_code_block_after_heading README.md '## Quick start')" = \
  "$noninteractive_launcher" ] ||
  fail 'README Quick start does not begin with the exact non-interactive launcher'
[ "$(first_code_block_after_heading \
  handbook.md '### Bootstrap và install')" = "$noninteractive_launcher" ] ||
  fail 'handbook Bootstrap và install does not begin with the exact non-interactive launcher'
[ "$(first_code_block_after_heading \
  PACKAGE-DESIGN.md '### Release launcher')" = "$noninteractive_launcher" ] ||
  fail 'PACKAGE-DESIGN Release launcher does not begin with the exact non-interactive launcher'

for file in README.md handbook.md PACKAGE-DESIGN.md; do
  if awk '
    /^[[:space:]]*sh -s -- --client (codex|claude|cursor)([[:space:]]|$)/ &&
      $0 !~ /--non-interactive([[:space:]]|$)/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$ROOT/$file"; then
    fail "interactive launcher remains in active onboarding: $file"
  fi
done

reject_text README.md '`v1.0.0` is the first public stable release'
reject_text handbook.md '`v1.0.0` là first public stable release'
reject_text PACKAGE-DESIGN.md \
  '`v1.0.0` is the first public stable release'

reject_text handbook.md 'canonical remote chưa có `v1.0.0`'
reject_text handbook.md 'tạo annotated `v1.0.0`'
reject_text handbook.md 'Install published `v1.0.0`'
reject_text PACKAGE-DESIGN.md 'It never pipes network output directly to a shell.'
reject_active_v100_release_gate

for file in README.md handbook.md PACKAGE-DESIGN.md; do
  reject_text "$file" 'immutable legacy test sample'
  reject_text "$file" 'Backend-only'
  reject_text "$file" 'do not register a Frontend repository'
done
reject_text handbook.md 'GITHUB_PAT'
reject_text handbook.md 'GitHub client bắt buộc PAT'

printf '%s\n' 'First public release readiness: PASS'
