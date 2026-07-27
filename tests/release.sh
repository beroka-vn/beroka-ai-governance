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

interactive_launcher=$(cat <<'EOF'
(
  set -eu
  client=codex

  dependency_error() {
    printf '%s\n' 'Result: DEPENDENCY_MISSING' "$1" >&2
    exit 1
  }
  run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
      "$@"
    elif command -v sudo >/dev/null 2>&1; then
      sudo "$@"
    else
      dependency_error "Install:$missing"
    fi
  }

  client_command=$client
  [ "$client" != cursor ] || client_command=cursor-agent
  command -v "$client_command" >/dev/null 2>&1 ||
    dependency_error "Install $client_command, then rerun this command"

  missing=
  for dependency in gh jq; do
    command -v "$dependency" >/dev/null 2>&1 ||
      missing="$missing $dependency"
  done
  if [ -n "$missing" ]; then
    [ -t 0 ] && [ -t 1 ] ||
      dependency_error "Install:$missing"
    installer=
    for candidate in apt-get dnf brew; do
      if command -v "$candidate" >/dev/null 2>&1; then
        installer=$candidate
        break
      fi
    done
    [ -n "$installer" ] || dependency_error "Install:$missing"
    printf 'Missing dependencies:%s\n' "$missing"
    printf 'Install with %s (may request sudo)? [y/N] ' "$installer"
    IFS= read -r answer || answer=
    case "$answer" in
      y|Y|yes|YES) ;;
      *) dependency_error "Install:$missing" ;;
    esac
    case "$installer" in
      apt-get)
        run_as_root apt-get update &&
          run_as_root apt-get install -y $missing ||
          dependency_error "Install:$missing"
        ;;
      dnf)
        run_as_root dnf install -y $missing ||
          dependency_error "Install:$missing"
        ;;
      brew)
        brew install $missing || dependency_error "Install:$missing"
        ;;
    esac
  fi

  for dependency in gh jq; do
    command -v "$dependency" >/dev/null 2>&1 ||
      dependency_error "Install: $dependency"
  done

  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    [ -t 0 ] && [ -t 1 ] || {
      printf '%s\n' \
        'Result: GITHUB_AUTH_REQUIRED' \
        'Remediation: gh auth login --hostname github.com --web' >&2
      exit 1
    }
    printf 'GitHub authentication required. Start browser OAuth? [y/N] '
    IFS= read -r answer || answer=
    case "$answer" in
      y|Y|yes|YES)
        gh auth login --hostname github.com --web
        ;;
      *)
        printf '%s\n' \
          'Result: GITHUB_AUTH_REQUIRED' \
          'Remediation: gh auth login --hostname github.com --web' >&2
        exit 1
        ;;
    esac
  fi

  bootstrap_file=$(mktemp "${TMPDIR:-/tmp}/beroka-bootstrap.XXXXXX")
  trap 'rm -f "$bootstrap_file"' EXIT HUP INT TERM
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --clobber \
    --output "$bootstrap_file"
  sh "$bootstrap_file" --client "$client"
)
EOF
)

noninteractive_launcher=$(cat <<'EOF'
(
  set -eu
  client=codex
  client_command=$client
  [ "$client" != cursor ] || client_command=cursor-agent
  for dependency in "$client_command" gh jq; do
    command -v "$dependency" >/dev/null 2>&1 || {
      printf '%s\n' \
        'Result: DEPENDENCY_MISSING' \
        "Remediation: install $dependency" >&2
      exit 1
    }
  done
  gh auth status --hostname github.com >/dev/null 2>&1 || {
    printf '%s\n' \
      'Result: GITHUB_AUTH_REQUIRED' \
      'Remediation: gh auth login --hostname github.com --web' >&2
    exit 1
  }
  bootstrap_file=$(mktemp "${TMPDIR:-/tmp}/beroka-bootstrap.XXXXXX")
  trap 'rm -f "$bootstrap_file"' EXIT HUP INT TERM
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --clobber \
    --output "$bootstrap_file"
  sh "$bootstrap_file" --client "$client" --non-interactive
)
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
case "$1:$2" in
  auth:status)
    [ "${GH_AUTH_STATE:-healthy}" = healthy ]
    ;;
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
cat >"$behavior_root/bin/jq" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$behavior_root/bin/codex" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$behavior_root/bin/sh" <<'EOF'
#!/bin/sh
set -eu
: >"$INNER_SH_CALLED"
EOF
chmod +x "$behavior_root/bin/gh" "$behavior_root/bin/jq" \
  "$behavior_root/bin/codex" "$behavior_root/bin/sh"
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
[ ! -s "$behavior_root/gh-calls" ] ||
  fail 'Automation / CI launcher continued after missing authentication'
rm -rf "$behavior_root"
trap - EXIT HUP INT TERM

overwrite_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-release-overwrite-test.XXXXXX")
trap 'rm -rf "$overwrite_root"' EXIT HUP INT TERM
mkdir "$overwrite_root/bin"
cat >"$overwrite_root/bin/gh" <<'EOF'
#!/bin/sh
set -eu
case "$1:$2" in
  auth:status)
    ;;
  auth:setup-git)
    ;;
  release:download)
    shift 2
    clobber=0
    output=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --clobber)
          clobber=1
          shift
          ;;
        --output)
          output=$2
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    [ -n "$output" ] && [ -e "$output" ] || exit 65
    [ "$clobber" -eq 1 ] || exit 17
    printf '%s\n' '#!/bin/sh' 'exit 0' >"$output"
    ;;
  *)
    exit 64
    ;;
esac
EOF
cat >"$overwrite_root/bin/jq" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$overwrite_root/bin/codex" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$overwrite_root/bin/sh" <<'EOF'
#!/bin/sh
set -eu
: >"$INNER_SH_CALLED"
EOF
chmod +x "$overwrite_root/bin/gh" "$overwrite_root/bin/jq" \
  "$overwrite_root/bin/codex" "$overwrite_root/bin/sh"
first_code_block_after_heading README.md '## Quick start' \
  >"$overwrite_root/quick-start.sh"
if ! PATH="$overwrite_root/bin:$PATH" \
  INNER_SH_CALLED="$overwrite_root/inner-sh-called" \
  /bin/sh "$overwrite_root/quick-start.sh"; then
  fail 'README Quick start cannot replace its secure temporary file'
fi
[ -e "$overwrite_root/inner-sh-called" ] ||
  fail 'README Quick start did not invoke the downloaded bootstrap'
rm -rf "$overwrite_root"
trap - EXIT HUP INT TERM

dependency_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-release-dependency-test.XXXXXX")
trap 'rm -rf "$dependency_root"' EXIT HUP INT TERM
mkdir "$dependency_root/bin"
ln -s /usr/bin/mktemp "$dependency_root/bin/mktemp"
ln -s /bin/rm "$dependency_root/bin/rm"
cat >"$dependency_root/bin/codex" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$dependency_root/bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' 0
EOF
cat >"$dependency_root/bin/apt-get" <<'EOF'
#!/bin/sh
set -eu
printf 'apt-get %s\n' "$*" >>"$INSTALL_CALLS"
case "$1" in
  update) ;;
  install)
    /bin/cp "$READY_BIN/gh" "$ACTIVE_BIN/gh"
    /bin/cp "$READY_BIN/jq" "$ACTIVE_BIN/jq"
    /bin/chmod +x "$ACTIVE_BIN/gh" "$ACTIVE_BIN/jq"
    ;;
  *) exit 64 ;;
esac
EOF
cat >"$dependency_root/bin/sh" <<'EOF'
#!/bin/sh
printf 'sh %s\n' "$*" >>"$INSTALL_CALLS"
EOF
mkdir "$dependency_root/ready"
cat >"$dependency_root/ready/gh" <<'EOF'
#!/bin/sh
set -eu
printf 'gh %s\n' "$*" >>"$INSTALL_CALLS"
case "$1:$2" in
  auth:status)
    [ -e "$AUTH_MARKER" ]
    ;;
  auth:login)
    : >"$AUTH_MARKER"
    ;;
  auth:setup-git)
    ;;
  release:download)
    shift 2
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --output)
          output=$2
          shift 2
          ;;
        *) shift ;;
      esac
    done
    printf '%s\n' '#!/bin/sh' >"$output"
    ;;
  *) exit 64 ;;
esac
EOF
cat >"$dependency_root/ready/jq" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x \
  "$dependency_root/bin/apt-get" \
  "$dependency_root/bin/codex" \
  "$dependency_root/bin/id" \
  "$dependency_root/bin/sh" \
  "$dependency_root/ready/gh" \
  "$dependency_root/ready/jq"
first_code_block_after_heading README.md '## Quick start' \
  >"$dependency_root/quick-start.sh"
first_code_block_after_heading README.md '### Automation / CI' \
  >"$dependency_root/automation.sh"
: >"$dependency_root/install-calls"
if output=$(PATH="$dependency_root/bin" \
  INSTALL_CALLS="$dependency_root/install-calls" \
  /bin/sh "$dependency_root/automation.sh" 2>&1)
then
  fail 'Automation / CI launcher installed or accepted missing dependencies'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
assert_contains "$output" 'Remediation: install gh'
[ ! -s "$dependency_root/install-calls" ] ||
  fail 'Automation / CI launcher attempted dependency installation'
output=$(printf 'y\ny\n' | \
  PATH="$dependency_root/bin" \
  INSTALL_CALLS="$dependency_root/install-calls" \
  READY_BIN="$dependency_root/ready" \
  ACTIVE_BIN="$dependency_root/bin" \
  AUTH_MARKER="$dependency_root/authenticated" \
  /usr/bin/script -qec \
    "/bin/sh $dependency_root/quick-start.sh" /dev/null 2>&1)
assert_contains "$output" 'Missing dependencies: gh jq'
assert_contains "$output" \
  'GitHub authentication required. Start browser OAuth?'
require_call=$(cat "$dependency_root/install-calls")
case "$require_call" in
  *'apt-get update'*'apt-get install -y gh jq'*\
'gh auth login --hostname github.com --web'*\
'gh auth setup-git --hostname github.com'*\
'gh release download'*\
'sh '*"--client codex"*) ;;
  *) fail "interactive installer flow is incomplete: [$require_call]" ;;
esac
case "$require_call" in
  *--non-interactive*)
    fail 'interactive Quick start invokes non-interactive bootstrap'
    ;;
  *) ;;
esac
rm -rf "$dependency_root"
trap - EXIT HUP INT TERM

require_text PACKAGE-DESIGN.md \
  'The downloaded release launcher clones the embedded'
require_text PACKAGE-DESIGN.md \
  'annotated tag and invokes the package CLI only after tag type, peeled commit,'
require_text PACKAGE-DESIGN.md 'checked-out HEAD each equal the embedded commit'
[ "$(first_code_block_after_heading README.md '## Quick start')" = \
  "$interactive_launcher" ] ||
  fail 'README Quick start does not begin with the exact interactive launcher'
[ "$(first_code_block_after_heading \
  handbook.md '### Bootstrap và install')" = "$interactive_launcher" ] ||
  fail 'handbook Bootstrap và install does not begin with the exact interactive launcher'
[ "$(first_code_block_after_heading \
  PACKAGE-DESIGN.md '### Release launcher')" = "$interactive_launcher" ] ||
  fail 'PACKAGE-DESIGN Release launcher does not begin with the exact interactive launcher'

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
