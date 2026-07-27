#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_text() {
  file=$1 text=$2
  grep -F -- "$text" "$ROOT/$file" >/dev/null ||
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

reject_text() {
  file=$1 text=$2
  if grep -F -- "$text" "$ROOT/$file" >/dev/null; then
    fail "forbidden [$text] in $file"
  fi
}

[ "$(cat "$ROOT/VERSION")" = v1.0.1 ] ||
  fail 'VERSION is not v1.0.1'

require_text README.md '`v1.0.1` is the current supported corrective release.'
require_text README.md '`v1.0.0` remains'
require_text README.md 'immutable but is superseded for onboarding;'
reject_text README.md 'establishes `v1.0.0` as the first supported release'
require_text handbook.md \
  '`v1.0.1` là corrective release được hỗ trợ hiện tại.'
require_text handbook.md '`v1.0.0` vẫn immutable'
require_text handbook.md 'thay thế cho onboarding'
reject_text handbook.md 'thiết lập `v1.0.0` là release được hỗ trợ đầu tiên'
require_text PACKAGE-DESIGN.md \
  '`v1.0.1` is the current supported corrective release.'
require_text PACKAGE-DESIGN.md '`v1.0.0` remains'
require_text PACKAGE-DESIGN.md 'immutable but is superseded for onboarding.'
reject_text PACKAGE-DESIGN.md \
  'establishes `v1.0.0` as the first supported team release'
require_text handbook.md 'release=v1.0.1'
require_text PACKAGE-DESIGN.md 'VERSION=v1.0.1'
require_text PACKAGE-DESIGN.md 'beroka-governance install v1.0.1'
require_text PACKAGE-DESIGN.md \
  'beroka-governance register /path/to/repo --version v1.0.1 --client codex'

require_text README.md 'Backend and Frontend repositories'
require_text handbook.md 'Chuyển quyết định cho developer'
require_text README.md 'gh release download'
require_text README.md 'one client on each execution environment'
require_text handbook.md 'AUTH_PENDING'
require_text handbook.md 'CONNECTOR_HEALTH_UNAVAILABLE'
require_text PACKAGE-DESIGN.md '15-second total deadline'
[ -f "$ROOT/release/bootstrap.sh.in" ] ||
  fail 'missing release launcher template'

noninteractive_launcher=$(cat <<'EOF'
(
  set -eu
  bootstrap_file=$(mktemp "${TMPDIR:-/tmp}/beroka-bootstrap.XXXXXX")
  trap 'rm -f "$bootstrap_file"' EXIT HUP INT TERM
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output "$bootstrap_file"
  sh "$bootstrap_file" --client codex --non-interactive
)
EOF
)
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

behavior_root=$(mktemp -d "${TMPDIR:-/tmp}/beroka-release-test.XXXXXX")
trap 'rm -rf "$behavior_root"' EXIT HUP INT TERM
mkdir "$behavior_root/bin"
cat >"$behavior_root/bin/gh" <<'EOF'
#!/bin/sh
set -eu
case "$1:$2" in
  auth:setup-git)
    printf '%s\n' 'auth setup-git' >>"$GH_CALLS"
    ;;
  release:download)
    printf '%s\n' 'release download' >>"$GH_CALLS"
    exit 23
    ;;
  *)
    exit 64
    ;;
esac
EOF
cat >"$behavior_root/bin/sh" <<'EOF'
#!/bin/sh
set -eu
: >"$INNER_SH_CALLED"
EOF
chmod +x "$behavior_root/bin/gh" "$behavior_root/bin/sh"
first_code_block_after_heading README.md '## Quick start' \
  >"$behavior_root/quick-start.sh"
: >"$behavior_root/gh-calls"
if PATH="$behavior_root/bin:$PATH" \
  GH_CALLS="$behavior_root/gh-calls" \
  INNER_SH_CALLED="$behavior_root/inner-sh-called" \
  /bin/sh "$behavior_root/quick-start.sh"; then
  fail 'README Quick start succeeds when gh release download fails'
fi
[ "$(cat "$behavior_root/gh-calls")" = "$(printf '%s\n%s' \
  'auth setup-git' 'release download')" ] ||
  fail 'README Quick start does not set up Git auth before release download'
[ ! -e "$behavior_root/inner-sh-called" ] ||
  fail 'README Quick start invokes the bootstrap shell after download failure'
rm -rf "$behavior_root"
trap - EXIT HUP INT TERM

require_text PACKAGE-DESIGN.md \
  'The downloaded release launcher clones the embedded'
require_text PACKAGE-DESIGN.md \
  'annotated tag and invokes the package CLI only after tag type, peeled commit,'
require_text PACKAGE-DESIGN.md 'checked-out HEAD each equal the embedded commit'
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

reject_text PACKAGE-DESIGN.md 'It never pipes network output directly to a shell.'

for file in README.md handbook.md PACKAGE-DESIGN.md; do
  require_text "$file" 'gh auth login --hostname github.com --web'
  require_text "$file" 'gh auth setup-git --hostname github.com'
  require_text "$file" 'client-owned GitHub OAuth'
  require_text "$file" 'private HTTPS clone'
  reject_text "$file" '--output - |'
  reject_text "$file" 'curl | sh'
  reject_text "$file" 'releases/latest/download/bootstrap.sh'
  reject_text "$file" 'latest URL'
  reject_text "$file" 'immutable legacy test sample'
  reject_text "$file" 'Backend-only'
  reject_text "$file" 'do not register a Frontend repository'
done
require_text README.md 'No token is requested, printed, copied, logged, or stored.'
require_text handbook.md \
  'Không yêu cầu, in, sao chép, ghi log hoặc lưu token.'
require_text PACKAGE-DESIGN.md \
  'No token is requested, printed, copied, logged, or stored.'
reject_text handbook.md 'GITHUB_PAT'
reject_text handbook.md 'GitHub client bắt buộc PAT'

printf '%s\n' 'First public release readiness: PASS'
