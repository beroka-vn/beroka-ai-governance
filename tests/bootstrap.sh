#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLI=$ROOT/bin/beroka-governance
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-bootstrap-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export HOME=$TEST_ROOT/home
export XDG_CONFIG_HOME=$TEST_ROOT/config
export XDG_DATA_HOME=$TEST_ROOT/data
export BEROKA_GOV_BIN_DIR=$TEST_ROOT/bin
FAKE_BIN=$TEST_ROOT/fake-bin
DISABLED_BIN=$TEST_ROOT/disabled-bin
CALLS=$TEST_ROOT/calls
export CALLS
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" \
  "$BEROKA_GOV_BIN_DIR" "$FAKE_BIN" "$DISABLED_BIN"
PATH=$FAKE_BIN:/usr/bin:/bin
export PATH

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

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "did not expect [$2] in [$1]" ;;
    *) ;;
  esac
}

assert_one_result() {
  aor_count=$(printf '%s\n' "$1" | grep -c '^Result:' || :)
  [ "$aor_count" -eq 1 ] ||
    fail "expected exactly one Result line, found $aor_count in [$1]"
}

new_repo() {
  nr_path=$1 nr_name=$2
  mkdir -p "$nr_path"
  git -C "$nr_path" init -q
  git -C "$nr_path" config user.name bootstrap-test
  git -C "$nr_path" config user.email bootstrap@example.invalid
  git -C "$nr_path" switch -qc main
  printf '%s\n' "# $nr_name" >"$nr_path/README.md"
  git -C "$nr_path" add README.md
  git -C "$nr_path" commit -qm 'test: initialize repository'
  git -C "$nr_path" remote add origin \
    "https://github.com/beroka-vn/$nr_name.git"
}

snapshot_repo() {
  sr_repo=$1
  {
    git -C "$sr_repo" status --porcelain=v1 --untracked-files=all
    git -C "$sr_repo" ls-files -s
    git -C "$sr_repo" diff --binary
    git -C "$sr_repo" diff --cached --binary
  }
}

cat >"$FAKE_BIN/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$FAKE_BIN/codex" <<'EOF'
#!/bin/sh
set -eu
printf 'codex %s\n' "$*" >>"$CALLS"
case "$*" in
  'mcp login --help'|'app-server --help') exit 0 ;;
  'mcp get atlassian --json')
    [ -f "$XDG_CONFIG_HOME/fake-codex-configured" ] || exit 1
    printf '%s\n' \
      '{"name":"atlassian","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.atlassian.com/v1/mcp/authv2"}}'
    ;;
  'app-server --stdio')
    IFS= read -r request_1 || exit 1
    IFS= read -r request_2 || exit 1
    while IFS= read -r request; do
      case "$request" in
        *'config/value/write'*)
          : >"$XDG_CONFIG_HOME/fake-codex-configured"
          printf '%s\n' '{"id":1,"result":{}}'
          ;;
        *'mcpServerStatus/list'*)
          case "${FAKE_CODEX_HEALTH:-healthy}" in
            healthy)
              printf '%s\n' \
                '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
              ;;
            auth-required)
              printf '%s\n' \
                '{"method":"mcpServer/startupStatus/updated","params":{"name":"atlassian","status":"failed","failureReason":"reauthenticationRequired"}}' \
                '{"id":1,"result":{"data":[{"name":"atlassian","tools":{},"authStatus":"oAuth"}]}}'
              ;;
            unavailable)
              trap '' TERM
              while :; do :; done
              ;;
          esac
          ;;
        *) ;;
      esac
    done
    ;;
  'mcp login atlassian')
    [ "${FAKE_CODEX_OAUTH:-}" != fail ] || exit 1
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$DISABLED_BIN/claude" <<'EOF'
#!/bin/sh
set -eu
printf 'claude %s\n' "$*" >>"$CALLS"
case "$*" in
  '--version') printf '%s\n' '1.2.3 (Claude Code)' ;;
  'mcp add --help'|'mcp get --help'|'mcp list --help') exit 0 ;;
  'mcp get atlassian')
    [ -f "$XDG_CONFIG_HOME/fake-claude-configured" ] || exit 1
    printf '%s\n' \
      'Name: atlassian' \
      'URL: https://mcp.atlassian.com/v1/mcp/authv2'
    ;;
  'mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2')
    : >"$XDG_CONFIG_HOME/fake-claude-configured"
    ;;
  'mcp list')
    printf '%s\n' \
      'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - ✓ Connected'
    ;;
  '') fail 'bootstrap unexpectedly started Claude OAuth' ;;
  *) exit 1 ;;
esac
EOF

chmod 755 "$FAKE_BIN/sleep" "$FAKE_BIN/codex" "$DISABLED_BIN/claude"
: >"$CALLS"

source_repo=$TEST_ROOT/governance-source
mkdir -p "$source_repo/bin" "$source_repo/runtime" \
  "$source_repo/templates"
cp "$CLI" "$source_repo/bin/beroka-governance"
chmod 755 "$source_repo/bin/beroka-governance"
cp -R "$ROOT/runtime/." "$source_repo/runtime/"
cp -R "$ROOT/templates/." "$source_repo/templates/"
for release_file in \
  PACKAGE-DESIGN.md README.md governance.md handbook.md workflow.md
do
  cp "$ROOT/$release_file" "$source_repo/$release_file"
done
printf '%s\n' v1.1.0 >"$source_repo/VERSION"
git -C "$source_repo" init -q
git -C "$source_repo" config user.name bootstrap-release
git -C "$source_repo" config user.email release@example.invalid
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'test: release v1.1.0'
git -C "$source_repo" tag -a v1.1.0 -m v1.1.0

printf '%s\n' v1.2.0 >"$source_repo/VERSION"
git -C "$source_repo" add VERSION
git -C "$source_repo" commit -qm 'test: release v1.2.0'
git -C "$source_repo" tag -a v1.2.0 -m v1.2.0
v1_2_commit=$(git -C "$source_repo" rev-parse v1.2.0^{commit})
git -C "$source_repo" tag -a v2.0.0-rc1 -m v2.0.0-rc1
git -C "$source_repo" tag v9.0.0

printf '%s\n' v8.0.0 >"$source_repo/VERSION"
git -C "$source_repo" add VERSION
git -C "$source_repo" commit -qm 'test: untagged branch version'

git config --global \
  url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git

repo=$TEST_ROOT/application
new_repo "$repo" bootstrap-application

if output=$($CLI bootstrap "$repo" --client codex \
  --non-interactive 2>&1)
then
  fail 'bootstrap accepted an implicit non-interactive latest'
fi
assert_contains "$output" 'Result: RELEASE_RESOLUTION_REQUIRED'

if output=$($CLI bootstrap "$repo" --version v1.1.0 \
  --non-interactive 2>&1)
then
  fail 'non-interactive bootstrap accepted a missing client'
fi
assert_contains "$output" 'Usage:'

if output=$($CLI bootstrap "$repo" --client invalid \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap accepted an invalid client'
fi
assert_contains "$output" 'Usage:'

if output=$($CLI bootstrap "$repo" --client codex --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap accepted duplicate client selection'
fi
assert_contains "$output" 'Usage:'

if output=$($CLI bootstrap "$repo" --client codex \
  --api-token should-not-appear 2>&1)
then
  fail 'bootstrap accepted a developer API token'
fi
assert_not_contains "$output" 'should-not-appear'

: >"$CALLS"
output=$(printf 'y\ny\n' | script -qec \
  "$CLI bootstrap $repo" /dev/null 2>&1)
assert_contains "$output" 'Detected client: codex'
assert_contains "$output" 'Resolved release: v1.2.0'
assert_contains "$output" "Release commit: $v1_2_commit"
assert_contains "$output" 'Release: PASS'
assert_contains "$output" 'Repository registration: PASS'
assert_contains "$output" 'Client entrypoint: ADDED'
assert_contains "$output" 'Selected client: codex'
assert_contains "$output" 'Repository changes: REVIEW_REQUIRED'
assert_contains "$output" 'Result: PASS'
assert_one_result "$output"
assert_not_contains "$output" 'v2.0.0-rc1'
assert_not_contains "$output" 'v9.0.0'
grep -F 'VERSION=v1.2.0' "$repo/.beroka-governance.lock" >/dev/null ||
  fail 'bootstrap did not pin the resolved version'
grep -F "COMMIT=$v1_2_commit" "$repo/.beroka-governance.lock" >/dev/null ||
  fail 'bootstrap did not pin the resolved commit'
grep -Fx 'CLIENTS=codex' "$repo/.beroka-governance.lock" >/dev/null ||
  fail 'bootstrap did not record the selected client'
[ -f "$repo/AGENTS.md" ] ||
  fail 'Codex bootstrap omitted AGENTS.md'
[ ! -e "$repo/CLAUDE.md" ] ||
  fail 'Codex bootstrap created CLAUDE.md'
[ ! -e "$repo/.cursor" ] ||
  fail 'Codex bootstrap created .cursor'
assert_contains "$(cat "$CALLS")" 'codex app-server --stdio'
assert_not_contains "$(cat "$CALLS")" 'claude '

before=$(snapshot_repo "$repo")
: >"$CALLS"
output=$($CLI bootstrap "$repo" --client codex --non-interactive)
after=$(snapshot_repo "$repo")
[ "$before" = "$after" ] ||
  fail 'bootstrap changed an already registered repository'
assert_contains "$output" 'Version: v1.2.0'
assert_contains "$output" 'Repository registration: NO_CHANGE'
assert_contains "$output" 'Client entrypoint: ALREADY_CONFIGURED'
assert_contains "$output" 'Selected client: codex'
assert_contains "$output" 'Repository changes: NONE'
assert_one_result "$output"

git -C "$repo" add .beroka-governance.lock AGENTS.md
git -C "$repo" commit -qm 'test: commit Codex bootstrap'

if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap silently changed a pinned version'
fi
assert_contains "$output" 'Result: VERSION_MISMATCH'

cp "$DISABLED_BIN/claude" "$FAKE_BIN/claude"
chmod 755 "$FAKE_BIN/claude"
: >"$CALLS"
output=$($CLI bootstrap "$repo" --client claude --non-interactive)
assert_contains "$output" 'Selected client: claude'
assert_contains "$output" 'Repository changes: REVIEW_REQUIRED'
grep -Fx 'CLIENTS=codex,claude' \
  "$repo/.beroka-governance.lock" >/dev/null ||
  fail 'second bootstrap did not add Claude'
[ -f "$repo/CLAUDE.md" ] ||
  fail 'second bootstrap omitted CLAUDE.md'
[ ! -e "$repo/.cursor" ] ||
  fail 'second bootstrap created Cursor files'
assert_contains "$(cat "$CALLS")" 'claude mcp'
assert_not_contains "$(cat "$CALLS")" 'codex '

before=$(snapshot_repo "$repo")
output=$($CLI bootstrap "$repo" --client claude --non-interactive)
after=$(snapshot_repo "$repo")
[ "$before" = "$after" ] ||
  fail 'repeat Claude bootstrap changed an already registered repository'
assert_contains "$output" 'Repository changes: NONE'

multi_repo=$TEST_ROOT/multiple-clients
new_repo "$multi_repo" bootstrap-multiple
: >"$CALLS"
output=$(printf '2\ny\n' | script -qec \
  "$CLI bootstrap $multi_repo" /dev/null 2>&1)
assert_contains "$output" 'Select one client:'
assert_contains "$output" 'Selected client: claude'
assert_contains "$(cat "$CALLS")" 'claude mcp'
assert_not_contains "$(cat "$CALLS")" 'codex '

mv "$FAKE_BIN/codex" "$DISABLED_BIN/codex"
mv "$FAKE_BIN/claude" "$DISABLED_BIN/claude"
none_repo=$TEST_ROOT/no-client
new_repo "$none_repo" bootstrap-none
if output=$(printf '\n' | script -qec \
  "$CLI bootstrap $none_repo" /dev/null 2>&1)
then
  fail 'bootstrap accepted no detected client'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
mv "$DISABLED_BIN/codex" "$FAKE_BIN/codex"

broken_repo=$TEST_ROOT/broken-remote
new_repo "$broken_repo" bootstrap-broken
git config --global --unset-all \
  url."file://$source_repo".insteadOf
git config --global \
  url."file://$TEST_ROOT/missing-release-source".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git
if output=$(printf 'y\n' | script -qec \
  "$CLI bootstrap $broken_repo --client codex" /dev/null 2>&1)
then
  fail 'bootstrap accepted an unverifiable latest release'
fi
assert_contains "$output" 'Result: RELEASE_RESOLUTION_REQUIRED'
git config --global --unset-all \
  url."file://$TEST_ROOT/missing-release-source".insteadOf
git config --global \
  url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git

exact_repo=$TEST_ROOT/exact-version
new_repo "$exact_repo" bootstrap-exact
output=$($CLI bootstrap "$exact_repo" --client codex \
  --version v1.1.0 --non-interactive)
assert_contains "$output" 'Version: v1.1.0'
assert_one_result "$output"
grep -F 'VERSION=v1.1.0' \
  "$exact_repo/.beroka-governance.lock" >/dev/null ||
  fail 'bootstrap did not use the explicit non-interactive version'

pending_repo=$TEST_ROOT/auth-pending
new_repo "$pending_repo" bootstrap-auth-pending
export FAKE_CODEX_HEALTH=auth-required
export FAKE_CODEX_OAUTH=fail
if output=$(printf 'y\ny\n' | script -qec \
  "$CLI bootstrap $pending_repo --client codex --version v1.1.0" \
  /dev/null 2>&1)
then
  fail 'bootstrap accepted incomplete OAuth'
fi
assert_contains "$output" 'Result: AUTH_PENDING'
assert_contains "$output" \
  'Resume: beroka-governance setup-connectors --client codex'
assert_one_result "$output"
[ -f "$pending_repo/.beroka-governance.lock" ] &&
  [ -f "$pending_repo/AGENTS.md" ] ||
  fail 'AUTH_PENDING rolled back repository registration'
pending_before=$(snapshot_repo "$pending_repo")
if output=$(printf 'y\n' | script -qec \
  "$CLI bootstrap $pending_repo --client codex" /dev/null 2>&1)
then
  fail 'bootstrap rerun accepted incomplete OAuth'
fi
pending_after=$(snapshot_repo "$pending_repo")
[ "$pending_before" = "$pending_after" ] ||
  fail 'AUTH_PENDING bootstrap rerun changed managed files'
assert_contains "$output" 'Result: AUTH_PENDING'
assert_one_result "$output"

health_repo=$TEST_ROOT/health-unavailable
new_repo "$health_repo" bootstrap-health-unavailable
unset FAKE_CODEX_OAUTH
export FAKE_CODEX_HEALTH=unavailable
if output=$($CLI bootstrap "$health_repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap accepted unavailable connector health'
fi
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
assert_contains "$output" \
  'Resume: beroka-governance setup-connectors --client codex'
assert_one_result "$output"
[ -f "$health_repo/.beroka-governance.lock" ] &&
  [ -f "$health_repo/AGENTS.md" ] ||
  fail 'CONNECTOR_HEALTH_UNAVAILABLE rolled back repository registration'
health_before=$(snapshot_repo "$health_repo")
if output=$($CLI bootstrap "$health_repo" --client codex \
  --non-interactive 2>&1)
then
  fail 'bootstrap rerun accepted unavailable connector health'
fi
health_after=$(snapshot_repo "$health_repo")
[ "$health_before" = "$health_after" ] ||
  fail 'health-unavailable bootstrap rerun changed managed files'
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
assert_one_result "$output"
unset FAKE_CODEX_HEALTH

grep -F 'beroka-governance bootstrap' "$ROOT/README.md" >/dev/null ||
  fail 'README does not document bootstrap'
grep -F 'latest stable annotated' "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fail 'package design does not define latest'
grep -F 'fresh AI session' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document the bootstrap handoff'
grep -F 'gh release download' "$ROOT/README.md" >/dev/null ||
  fail 'README does not document the release launcher'
grep -F 'AUTH_PENDING' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document pending authentication'
grep -F 'CONNECTOR_HEALTH_UNAVAILABLE' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document unavailable connector health'

printf '%s\n' 'Bootstrap onboarding tests: PASS'
