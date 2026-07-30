#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected [$2] in [$1]" ;;
  esac
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

[ "$(cat "$ROOT/VERSION")" = v1.0.2 ] ||
  fail 'VERSION is not v1.0.2'

require_text README.md '`v1.0.2` is the current supported capability release.'
reject_text README.md '`v1.0.0` is the current supported capability release.'
reject_text README.md '`v1.0.1` is the current supported capability release.'
require_text handbook.md \
  '`v1.0.2` là capability release được hỗ trợ hiện tại.'
reject_text handbook.md \
  '`v1.0.0` là capability release được hỗ trợ hiện tại.'
reject_text handbook.md '`v1.0.1` là capability release được hỗ trợ hiện tại.'
require_text PACKAGE-DESIGN.md \
  '`v1.0.2` is the current supported capability release.'
reject_text PACKAGE-DESIGN.md \
  '`v1.0.0` is the current supported capability release.'
reject_text PACKAGE-DESIGN.md \
  '`v1.0.1` is the current supported capability release.'
require_text README.md \
  'Bootstrap installs a missing Cursor Agent after one confirmation.'
require_text README.md \
  'gh release download v1.0.2 --repo beroka-vn/beroka-ai-governance'
require_text handbook.md \
  'Bootstrap tự cài Cursor Agent còn thiếu sau một lần xác nhận.'
require_text PACKAGE-DESIGN.md 'Cursor MCP commands run from `/`'
require_text README.md 'Backend and Frontend repositories'
require_text README.md 'cuongngo1801-beroka/Beroka_Backend'
require_text README.md 'cuongngo1801-beroka/Beroka_Frontend'
require_text README.md 'workspace or current Git repository changes'
require_text handbook.md 'cuongngo1801-beroka/Beroka_Backend'
reject_text handbook.md 'hungnx77/Beroka_Backend'
require_text handbook.md 'Chuyển quyết định cho developer'
require_text README.md 'gh release download'
require_text README.md 'one client on each execution environment'
require_text handbook.md 'AUTH_PENDING'
require_text handbook.md 'CONNECTOR_HEALTH_UNAVAILABLE'
require_text PACKAGE-DESIGN.md '15-second total deadline'
[ -f "$ROOT/release/bootstrap.sh.in" ] ||
  fail 'missing release launcher template'

interactive_launcher=$(cat <<'EOF'
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex
'
EOF
)

upgrade_launcher=$(cat <<'EOF'
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex --upgrade
'
EOF
)

noninteractive_launcher=$(cat <<'EOF'
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 || {
    printf "%s\n" \
      "Result: GITHUB_AUTH_REQUIRED" \
      "Remediation: gh auth login --hostname github.com --web" >&2
      exit 1
  }
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex --non-interactive
'
EOF
)
section_fixture=$(mktemp "$ROOT/tests/.release-section.XXXXXX")
trap 'rm -f "$section_fixture"' EXIT HUP INT TERM
{
  printf '%s\n' '### Release launcher' 'No launcher in this section.'
  printf '%s\n' '### Release launcher' '```bash'
  printf '%s\n' "$interactive_launcher" '```'
} >"$section_fixture"
if [ "$(first_code_block_after_heading \
  "tests/${section_fixture##*/}" '### Release launcher')" = \
  "$interactive_launcher" ]; then
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
printf 'gh %s\n' "$*" >>"$GH_CALLS"
case "$1:$2" in
  auth:status)
    [ "${GH_AUTH_STATE:-healthy}" = healthy ]
    ;;
  auth:login)
    ;;
  auth:setup-git)
    ;;
  release:download)
    [ "${GH_DOWNLOAD_FAIL:-0}" -eq 0 ] || exit 23
    printf '%s\n' '#!/bin/sh' 'exit 0'
    ;;
  *)
    exit 64
    ;;
esac
EOF
cat >"$behavior_root/bin/sh" <<'EOF'
#!/bin/sh
set -eu
cat >/dev/null
printf 'sh %s\n' "$*" >>"$GH_CALLS"
: >"$INNER_SH_CALLED"
EOF
chmod +x "$behavior_root/bin/gh" "$behavior_root/bin/sh"
first_code_block_after_heading README.md '## Quick start' \
  >"$behavior_root/quick-start.sh"
: >"$behavior_root/gh-calls"
if PATH="$behavior_root/bin:$PATH" GH_DOWNLOAD_FAIL=1 \
  GH_CALLS="$behavior_root/gh-calls" \
  INNER_SH_CALLED="$behavior_root/inner-sh-called" \
  /bin/sh "$behavior_root/quick-start.sh"; then
  fail 'README Quick start succeeds when gh release download fails'
fi
case "$(cat "$behavior_root/gh-calls")" in
  *'gh auth status --hostname github.com'*\
*'gh auth setup-git --hostname github.com'*\
*'gh release download --repo beroka-vn/beroka-ai-governance --pattern bootstrap.sh --output -'*) ;;
  *)
  fail 'README Quick start does not set up Git auth before release download'
    ;;
esac
rm -f "$behavior_root/inner-sh-called"

: >"$behavior_root/gh-calls"
GH_AUTH_STATE=required \
  PATH="$behavior_root/bin:$PATH" \
  GH_CALLS="$behavior_root/gh-calls" \
  INNER_SH_CALLED="$behavior_root/inner-sh-called" \
  /bin/sh "$behavior_root/quick-start.sh"
case "$(cat "$behavior_root/gh-calls")" in
  *'gh auth login --hostname github.com --web'*\
*'sh -s -- --client codex'*) ;;
  *) fail 'README Quick start did not authenticate and install' ;;
esac

first_code_block_after_heading README.md '### Upgrade' \
  >"$behavior_root/upgrade.sh"
: >"$behavior_root/gh-calls"
PATH="$behavior_root/bin:$PATH" \
  GH_CALLS="$behavior_root/gh-calls" \
  INNER_SH_CALLED="$behavior_root/inner-sh-called" \
  /bin/sh "$behavior_root/upgrade.sh"
grep -F 'sh -s -- --client codex --upgrade' \
  "$behavior_root/gh-calls" >/dev/null ||
  fail 'README Upgrade omitted explicit --upgrade'

first_code_block_after_heading README.md '### Automation / CI' \
  >"$behavior_root/automation.sh"
: >"$behavior_root/gh-calls"
if output=$(PATH="$behavior_root/bin:$PATH" \
  GH_AUTH_STATE=required \
  GH_CALLS="$behavior_root/gh-calls" \
  INNER_SH_CALLED="$behavior_root/inner-sh-called" \
  /bin/sh "$behavior_root/automation.sh" 2>&1)
then
  fail 'Automation / CI launcher accepted missing GitHub authentication'
fi
assert_contains "$output" 'Result: GITHUB_AUTH_REQUIRED'
assert_contains "$output" \
  'Remediation: gh auth login --hostname github.com --web'
[ "$(cat "$behavior_root/gh-calls")" = \
  'gh auth status --hostname github.com' ] ||
  fail 'Automation / CI launcher continued after missing authentication'
rm -rf "$behavior_root"
trap - EXIT HUP INT TERM

require_text PACKAGE-DESIGN.md \
  'The downloaded release launcher clones the embedded'
require_text PACKAGE-DESIGN.md \
  'annotated tag and invokes the package CLI only after tag type, peeled commit,'
require_text PACKAGE-DESIGN.md 'checked-out HEAD each equal the embedded commit'
[ "$(first_code_block_after_heading README.md '## Quick start')" = \
  "$interactive_launcher" ] ||
  fail 'README Quick start does not begin with the exact interactive launcher'

for forbidden in \
  '.beroka-governance.lock' \
  'Repository pull request: REQUIRED' \
  'git add AGENTS.md' \
  'git commit' \
  'git push'
do
  if first_code_block_after_heading README.md '## Quick start' |
    grep -F "$forbidden" >/dev/null
  then
    fail "Quick start contains repository mutation: $forbidden"
  fi
done

for file in README.md handbook.md PACKAGE-DESIGN.md governance.md workflow.md; do
  reject_text "$file" 'pins each registered repository'
  reject_text "$file" 'Repository entrypoints and the lock are shared through Git.'
  reject_text "$file" 'resulting application-repository diff is reviewed'
  reject_text "$file" 'reviewed through its normal pull-request workflow'
done
[ "$(first_code_block_after_heading \
  handbook.md '### Bootstrap và install')" = "$interactive_launcher" ] ||
  fail 'handbook Bootstrap và install does not begin with the exact interactive launcher'
[ "$(first_code_block_after_heading \
  PACKAGE-DESIGN.md '### Release launcher')" = "$interactive_launcher" ] ||
  fail 'PACKAGE-DESIGN Release launcher does not begin with the exact interactive launcher'

[ "$(first_code_block_after_heading README.md '### Upgrade')" = \
  "$upgrade_launcher" ] ||
  fail 'README Upgrade does not use the exact upgrade launcher'
[ "$(first_code_block_after_heading handbook.md '### Upgrade')" = \
  "$upgrade_launcher" ] ||
  fail 'handbook Upgrade does not use the exact upgrade launcher'
[ "$(first_code_block_after_heading PACKAGE-DESIGN.md '### Upgrade')" = \
  "$upgrade_launcher" ] ||
  fail 'PACKAGE-DESIGN Upgrade does not use the exact upgrade launcher'

[ "$(first_code_block_after_heading README.md '### Automation / CI')" = \
  "$noninteractive_launcher" ] ||
  fail 'README Automation / CI launcher is not fail-closed'
[ "$(first_code_block_after_heading \
  handbook.md '### Automation / CI')" = "$noninteractive_launcher" ] ||
  fail 'handbook Automation / CI launcher is not fail-closed'
[ "$(first_code_block_after_heading \
  PACKAGE-DESIGN.md '### Automation / CI')" = "$noninteractive_launcher" ] ||
  fail 'PACKAGE-DESIGN Automation / CI launcher is not fail-closed'

reject_text PACKAGE-DESIGN.md 'It never pipes network output directly to a shell.'

for file in README.md handbook.md PACKAGE-DESIGN.md; do
  require_text "$file" 'bash -e -o pipefail -c'
  require_text "$file" 'gh auth login --hostname github.com --web'
  require_text "$file" 'gh auth setup-git --hostname github.com'
  require_text "$file" 'client-owned GitHub OAuth'
  require_text "$file" 'private HTTPS clone'
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
