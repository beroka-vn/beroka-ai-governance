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
START_MARKER='<!-- BEROKA-GOVERNANCE:START -->'
END_MARKER='<!-- BEROKA-GOVERNANCE:END -->'
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

assert_separate_managed_block() {
  asmb_file=$1
  asmb_start_count=$(grep -Fxc "$START_MARKER" "$asmb_file" || :)
  asmb_end_count=$(grep -Fxc "$END_MARKER" "$asmb_file" || :)
  [ "$asmb_start_count" -eq 1 ] && [ "$asmb_end_count" -eq 1 ] ||
    fail "instruction markers are not separately delimited in $asmb_file"
}

assert_cursor_hook() {
  ach_file=$1 ach_event=$2 ach_command=$3 ach_fail_closed=$4
  ach_count=$(jq --arg event "$ach_event" --arg command "$ach_command" \
    '[.hooks[$event][] | select(.command == $command)] | length' "$ach_file")
  [ "$ach_count" -eq 1 ] ||
    fail "expected one managed Cursor hook for $ach_event"
  ach_expected=$(jq -nc --arg command "$ach_command" --argjson fail_closed "$ach_fail_closed" \
    'if $fail_closed then {command:$command,failClosed:true} else {command:$command} end')
  jq -e --arg event "$ach_event" --argjson expected "$ach_expected" \
    '.hooks[$event] | any(. == $expected)' "$ach_file" >/dev/null ||
    fail "Cursor hook has the wrong security setting for $ach_event"
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

cat >"$FAKE_BIN/gh" <<'EOF'
#!/bin/sh
set -eu
printf 'gh %s\n' "$*" >>"$CALLS"
case "$*" in
  'auth status --help'|'auth login --help'|'api --help') exit 0 ;;
  'auth status --hostname github.com')
    [ "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-github-health")" = healthy ]
    ;;
  'api --paginate /user/teams')
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-github-teams")" in
      frontend)
        printf '%s\n' \
          '[{"slug":"frontend","organization":{"login":"beroka-vn"}}]'
        ;;
      backend)
        printf '%s\n' \
          '[{"slug":"backend","organization":{"login":"beroka-vn"}}]'
        ;;
      both)
        printf '%s\n' \
          '[{"slug":"frontend","organization":{"login":"beroka-vn"}},{"slug":"backend","organization":{"login":"beroka-vn"}}]'
        ;;
      neither) printf '%s\n' '[]' ;;
      *) exit 1 ;;
    esac
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

chmod 755 "$FAKE_BIN/sleep" "$FAKE_BIN/codex" "$FAKE_BIN/gh" \
  "$DISABLED_BIN/claude"
: >"$CALLS"
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-github-health"
printf '%s\n' frontend >"$XDG_CONFIG_HOME/fake-github-teams"

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
rm "$source_repo/runtime/rules/work-items.md"
printf '%s\n' v1.0.1 >"$source_repo/VERSION"
git -C "$source_repo" init -q
git -C "$source_repo" config user.name bootstrap-release
git -C "$source_repo" config user.email release@example.invalid
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'test: historical release v1.0.1'
git -C "$source_repo" tag -a v1.0.1 -m v1.0.1
v1_0_1_commit=$(git -C "$source_repo" rev-parse v1.0.1^{commit})

printf '%s\n' v1.0.2 >"$source_repo/VERSION"
git -C "$source_repo" add VERSION
git -C "$source_repo" commit -qm 'test: invalid release v1.0.2'
git -C "$source_repo" tag -a v1.0.2 -m v1.0.2

cp "$ROOT/runtime/rules/work-items.md" \
  "$source_repo/runtime/rules/work-items.md"
printf '%s\n' v1.0.3 >"$source_repo/VERSION"
git -C "$source_repo" add VERSION runtime/rules/work-items.md
git -C "$source_repo" commit -qm 'test: release v1.0.3'
git -C "$source_repo" tag -a v1.0.3 -m v1.0.3
v1_0_3_commit=$(git -C "$source_repo" rev-parse v1.0.3^{commit})

printf '%s\n' v1.1.0 >"$source_repo/VERSION"
git -C "$source_repo" add VERSION
git -C "$source_repo" commit -qm 'test: release v1.1.0'
git -C "$source_repo" tag -a v1.1.0 -m v1.1.0
v1_1_commit=$(git -C "$source_repo" rev-parse v1.1.0^{commit})

printf '%s\n' v1.2.0 >"$source_repo/VERSION"
for entrypoint in AGENTS.md CLAUDE.md; do
  sed 's/verified Beroka governance/verified v1.2 Beroka governance/' \
    "$source_repo/templates/agent-entrypoints/$entrypoint" \
    >"$source_repo/templates/agent-entrypoints/$entrypoint.next"
  mv "$source_repo/templates/agent-entrypoints/$entrypoint.next" \
    "$source_repo/templates/agent-entrypoints/$entrypoint"
done
git -C "$source_repo" add VERSION templates/agent-entrypoints
git -C "$source_repo" commit -qm 'test: release v1.2.0'
git -C "$source_repo" tag -a v1.2.0 -m v1.2.0
v1_2_commit=$(git -C "$source_repo" rev-parse v1.2.0^{commit})
git -C "$source_repo" tag -a v2.0.0-rc1 -m v2.0.0-rc1
git -C "$source_repo" tag v9.0.0

printf '%s\n' v2.0.0 >"$source_repo/VERSION"
git -C "$source_repo" add VERSION
git -C "$source_repo" commit -qm 'test: release v2.0.0'
git -C "$source_repo" tag -a v2.0.0 -m v2.0.0

printf '%s\n' v8.0.0 >"$source_repo/VERSION"
git -C "$source_repo" add VERSION
git -C "$source_repo" commit -qm 'test: untagged branch version'

git config --global \
  url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git

repo=$TEST_ROOT/application
new_repo "$repo" bootstrap-application

if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.0.2 --non-interactive 2>&1)
then
  fail 'bootstrap accepted v1.0.2 without work-item rules'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
assert_contains "$output" \
  'Missing release file: runtime/rules/work-items.md'
[ ! -e "$XDG_CONFIG_HOME/beroka-ai-governance/active-release" ] ||
  fail 'invalid v1.0.2 changed active-release state'

compat_repo_before=$(snapshot_repo "$repo")
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.0.1 --non-interactive)
assert_contains "$output" 'Version: v1.0.1'
[ "$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/active-release")" = \
  "$(printf '%s\n%s' 'VERSION=v1.0.1' "COMMIT=$v1_0_1_commit")" ] ||
  fail 'historical install activated the wrong verified commit'

output=$($CLI bootstrap "$repo" --client codex \
  --version v1.0.3 --upgrade --non-interactive)
assert_contains "$output" 'Version: v1.0.3'
[ "$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/active-release")" = \
  "$(printf '%s\n%s' 'VERSION=v1.0.3' "COMMIT=$v1_0_3_commit")" ] ||
  fail 'historical upgrade activated the wrong verified commit'
[ "$compat_repo_before" = "$(snapshot_repo "$repo")" ] ||
  fail 'historical upgrade changed the application repository'
$CLI uninstall --force >/dev/null
[ ! -e "$XDG_CONFIG_HOME/beroka-ai-governance/github-role" ] ||
  fail 'uninstall retained the managed GitHub role'
rm -f "$XDG_CONFIG_HOME/fake-codex-configured"

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
  --version v1.1.0 --upgrade --upgrade --non-interactive 2>&1)
then
  fail 'bootstrap accepted duplicate upgrade selection'
fi
assert_contains "$output" 'Usage:'

if output=$($CLI bootstrap "$repo" --client codex \
  --api-token should-not-appear 2>&1)
then
  fail 'bootstrap accepted a developer API token'
fi
assert_not_contains "$output" 'should-not-appear'

if output=$($CLI bootstrap "$repo" --client cursor \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'direct Cursor bootstrap accepted a missing cursor-agent'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
[ ! -e "$XDG_CONFIG_HOME/beroka-ai-governance/active-release" ] ||
  fail 'missing cursor-agent changed active-release state'

incidental_repo=$TEST_ROOT/incidental-gitlab-repository
new_repo "$incidental_repo" incidental-gitlab-repository
git -C "$incidental_repo" remote set-url origin \
  https://gitlab.com/example/incidental.git
incidental_before=$(snapshot_repo "$incidental_repo")
if ! output=$(cd "$incidental_repo" &&
  $CLI bootstrap --client codex --version v1.1.0 \
    --non-interactive 2>&1)
then
  fail "repo-independent bootstrap inferred incidental Git state: $output"
fi
assert_contains "$output" 'Result: PASS'
assert_contains "$output" 'Release: PASS'
assert_contains "$output" 'Connector: PASS'
assert_not_contains "$output" 'Repository:'
[ "$incidental_before" = "$(snapshot_repo "$incidental_repo")" ] ||
  fail 'repo-independent bootstrap changed the incidental repository'
[ "$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/clients")" = codex ] ||
  fail 'repo-independent bootstrap omitted Codex enrollment'
assert_separate_managed_block "$HOME/.codex/AGENTS.md"
$CLI uninstall --force >/dev/null
[ ! -e "$XDG_CONFIG_HOME/beroka-ai-governance/github-role" ] ||
  fail 'uninstall retained the managed GitHub role'
rm -f "$XDG_CONFIG_HOME/fake-codex-configured"

role_file=$XDG_CONFIG_HOME/beroka-ai-governance/github-role
printf '%s\n' backend >"$XDG_CONFIG_HOME/fake-github-teams"
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)
[ "$(cat "$role_file")" = BE ] ||
  fail 'Backend-only membership did not select BE'

printf '%s\n' both >"$XDG_CONFIG_HOME/fake-github-teams"
rm -f "$role_file"
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'dual membership defaulted a GitHub role'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_SELECTION_REQUIRED'

output=$(printf 'Full-stack\n' | script -qec \
  "$CLI bootstrap $repo --client codex --version v1.1.0" \
  /dev/null 2>&1)
assert_contains "$output" 'GitHub role: FULL_STACK'
[ "$(cat "$role_file")" = FULL_STACK ] ||
  fail 'dual membership did not store the explicit Full-stack choice'

printf '%s\n' FE >"$role_file"
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)
[ "$(cat "$role_file")" = FE ] ||
  fail 'dual membership discarded the stored FE choice'

printf '%s\n' neither >"$XDG_CONFIG_HOME/fake-github-teams"
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap accepted no eligible GitHub Team'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_REQUIRED'

printf '%s\n' frontend >"$XDG_CONFIG_HOME/fake-github-teams"

: >"$CALLS"
repo_before=$(snapshot_repo "$repo")
mkdir -p "$HOME/.codex"
codex_personal_expected=$TEST_ROOT/codex-personal-expected
printf '%s' '# Personal Codex instruction' >"$codex_personal_expected"
cp "$codex_personal_expected" "$HOME/.codex/AGENTS.md"

output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)

[ "$repo_before" = "$(snapshot_repo "$repo")" ] ||
  fail 'bootstrap changed the application repository'
assert_contains "$(cat "$HOME/.codex/AGENTS.md")" \
  '# Personal Codex instruction'
assert_contains "$(cat "$HOME/.codex/AGENTS.md")" \
  '<!-- BEROKA-GOVERNANCE:START -->'
assert_separate_managed_block "$HOME/.codex/AGENTS.md"
[ "$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/clients")" = codex ] ||
  fail 'bootstrap omitted Codex enrollment'
assert_not_contains "$output" 'Repository pull request:'
assert_contains "$(cat "$CALLS")" 'codex app-server --stdio'
assert_not_contains "$(cat "$CALLS")" 'claude '
assert_contains "$output" 'Repository: beroka-vn/bootstrap-application'
doctor_output=$($CLI doctor "$repo" --client codex)
assert_contains "$doctor_output" 'Instruction: INSTALLED'

cat_failure_before=$TEST_ROOT/codex-before-cat-failure
cp "$HOME/.codex/AGENTS.md" "$cat_failure_before"
cat >"$FAKE_BIN/cat" <<'EOF'
#!/bin/sh
case "${1:-}" in
  */beroka-governance-instruction.*) exit 73 ;;
esac
exec /usr/bin/cat "$@"
EOF
chmod 755 "$FAKE_BIN/cat"
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap masked a personal-instruction read failure'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
cmp -s "$cat_failure_before" "$HOME/.codex/AGENTS.md" ||
  fail 'failed instruction merge changed personal bytes'
rm -f "$FAKE_BIN/cat"

tail_failure_personal=$TEST_ROOT/codex-tail-failure-personal
printf '%s\n' '# Newline Codex instruction' >"$tail_failure_personal"
cp "$tail_failure_personal" "$HOME/.codex/AGENTS.override.md"
tail_failure_before=$TEST_ROOT/codex-before-tail-failure
cp "$HOME/.codex/AGENTS.override.md" "$tail_failure_before"
tail_failure_tmp=$TEST_ROOT
tail_stage_mode_log=$TEST_ROOT/instruction-tail-stage-mode
export TAIL_STAGE_MODE_LOG=$tail_stage_mode_log
cat >"$FAKE_BIN/tail" <<'EOF'
#!/bin/sh
if [ "$#" -eq 3 ] && [ "$1" = -c ] && [ "$2" = 1 ]; then
  case "$3" in
    */beroka-governance-instruction.*)
      tail_stage_dir=${3%/*}
      tail_stage_mode=600
      check_stage_mode() {
        checked_mode=$(/usr/bin/stat -c '%a' "$1")
        [ "$checked_mode" = 600 ] || tail_stage_mode=$checked_mode
      }
      case "${tail_stage_dir##*/}" in
        beroka-governance-instruction.*)
          for tail_stage_file in "$tail_stage_dir"/*; do
            check_stage_mode "$tail_stage_file"
          done
          ;;
        *)
          for tail_stage_file in \
            "$tail_stage_dir"/beroka-governance-instruction.*
          do
            check_stage_mode "$tail_stage_file"
          done
          ;;
      esac
      printf '%s\n' "$tail_stage_mode" >"$TAIL_STAGE_MODE_LOG"
      exit 74
      ;;
  esac
fi
exec /usr/bin/tail "$@"
EOF
chmod 755 "$FAKE_BIN/tail"
if output=$(TMPDIR="$tail_failure_tmp" \
  $CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap masked a personal-instruction tail failure'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
assert_contains "$output" 'Cannot inspect codex instruction boundary'
cmp -s "$tail_failure_before" "$HOME/.codex/AGENTS.override.md" ||
  fail 'failed last-byte read changed personal bytes'
[ -z "$(find "$tail_failure_tmp" -maxdepth 1 \
  -name 'beroka-governance-instruction.*' -print)" ] ||
  fail 'failed instruction read left personal staging files'
[ "$(cat "$tail_stage_mode_log")" = 600 ] ||
  fail 'personal instruction staging files were not mode 600'
rm -f "$FAKE_BIN/tail"

output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)
assert_separate_managed_block "$HOME/.codex/AGENTS.override.md"
doctor_output=$($CLI doctor "$repo" --client codex)
assert_contains "$doctor_output" 'Instruction: INSTALLED'
rm -f "$HOME/.codex/AGENTS.override.md"

nul_personal_expected=$TEST_ROOT/codex-nul-personal-expected
printf '# NUL Codex instruction\000' >"$nul_personal_expected"
cp "$nul_personal_expected" "$HOME/.codex/AGENTS.override.md"
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)
assert_separate_managed_block "$HOME/.codex/AGENTS.override.md"
if ! doctor_output=$($CLI doctor "$repo" --client codex 2>&1); then
  fail "Doctor rejected NUL-ended personal instructions: $doctor_output"
fi
assert_contains "$doctor_output" 'Instruction: INSTALLED'
nul_instruction_before_repeat=$TEST_ROOT/codex-nul-before-repeat
cp "$HOME/.codex/AGENTS.override.md" "$nul_instruction_before_repeat"
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)
cmp -s "$nul_instruction_before_repeat" \
  "$HOME/.codex/AGENTS.override.md" ||
  fail 'repeat bootstrap changed NUL-ended personal instructions'
$CLI uninstall --force >/dev/null
cmp -s "$nul_personal_expected" "$HOME/.codex/AGENTS.override.md" ||
  fail 'uninstall changed NUL-ended personal instructions'
rm -f "$HOME/.codex/AGENTS.override.md"
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)
assert_separate_managed_block "$HOME/.codex/AGENTS.md"

active_release=$XDG_CONFIG_HOME/beroka-ai-governance/active-release
active_before=$(cat "$active_release")
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 \
  --expected-commit 0000000000000000000000000000000000000000 \
  --non-interactive 2>&1)
then
  fail 'bootstrap accepted a commit different from the verified launcher'
fi
assert_contains "$output" 'Result: VERSION_MISMATCH'
[ "$active_before" = "$(cat "$active_release")" ] ||
  fail 'commit mismatch changed the active release'

git -C "$source_repo" tag -fa v1.1.0 -m moved >/dev/null
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'direct bootstrap accepted a moved remote tag'
fi
assert_contains "$output" 'Result: VERSION_MISMATCH'
[ "$active_before" = "$(cat "$active_release")" ] ||
  fail 'moved tag changed the active release'
git -C "$source_repo" tag -fa v1.1.0 "$v1_1_commit" -m v1.1.0 \
  >/dev/null

codex_before=$TEST_ROOT/codex-before-repeat
cp "$HOME/.codex/AGENTS.md" "$codex_before"
output=$(cd "$TEST_ROOT" &&
  $CLI bootstrap --client codex --version v1.1.0 --non-interactive)
cmp -s "$codex_before" "$HOME/.codex/AGENTS.md" ||
  fail 'repeat Codex bootstrap changed user instructions'
assert_separate_managed_block "$HOME/.codex/AGENTS.md"
assert_not_contains "$output" 'Repository pull request:'
assert_not_contains "$output" 'Repository:'

output=$(cd "$repo" &&
  $CLI bootstrap --client codex --version v1.1.0 --non-interactive)
assert_not_contains "$output" 'Repository:'
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)
assert_contains "$output" 'Repository: beroka-vn/bootstrap-application'

codex_override_expected=$TEST_ROOT/codex-override-expected
printf '%s' '# Active override' >"$codex_override_expected"
cp "$codex_override_expected" "$HOME/.codex/AGENTS.override.md"
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)
assert_contains "$(cat "$HOME/.codex/AGENTS.override.md")" '# Active override'
assert_contains "$(cat "$HOME/.codex/AGENTS.override.md")" \
  '<!-- BEROKA-GOVERNANCE:START -->'
assert_separate_managed_block "$HOME/.codex/AGENTS.override.md"

mkdir -p "$HOME/.claude"
claude_personal_expected=$TEST_ROOT/claude-personal-expected
printf '%s' '# Personal Claude instruction' >"$claude_personal_expected"
cp "$claude_personal_expected" "$HOME/.claude/CLAUDE.md"
cp "$DISABLED_BIN/claude" "$FAKE_BIN/claude"
chmod 755 "$FAKE_BIN/claude"
: >"$CALLS"
output=$($CLI bootstrap "$repo" --client claude \
  --version v1.1.0 --non-interactive)
[ "$repo_before" = "$(snapshot_repo "$repo")" ] ||
  fail 'Claude bootstrap changed the application repository'
assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" \
  '# Personal Claude instruction'
assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" \
  '<!-- BEROKA-GOVERNANCE:START -->'
assert_separate_managed_block "$HOME/.claude/CLAUDE.md"
[ "$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/clients")" = codex,claude ] ||
  fail 'bootstrap omitted Claude enrollment'
assert_contains "$(cat "$CALLS")" 'claude mcp'
assert_not_contains "$(cat "$CALLS")" 'codex '

claude_after=$TEST_ROOT/claude-after
cp "$HOME/.claude/CLAUDE.md" "$claude_after"
output=$($CLI bootstrap "$repo" --client claude \
  --version v1.1.0 --non-interactive)
cmp -s "$claude_after" "$HOME/.claude/CLAUDE.md" ||
  fail 'repeat Claude bootstrap changed user instructions'
assert_separate_managed_block "$HOME/.claude/CLAUDE.md"
assert_not_contains "$output" 'Repository pull request:'

codex_instruction=$HOME/.codex/AGENTS.override.md
codex_instruction_healthy=$TEST_ROOT/codex-instruction-healthy
cp "$codex_instruction" "$codex_instruction_healthy"

: >"$CALLS"
doctor_output=$($CLI doctor "$repo" --client codex)
assert_contains "$doctor_output" 'Instruction: INSTALLED'
assert_contains "$doctor_output" 'Connector: PASS'

printf '%s\n' '# Active override without governance' >"$codex_instruction"
: >"$CALLS"
if output=$($CLI doctor "$repo" --client codex 2>&1); then
  fail 'Doctor accepted a missing active Codex instruction'
fi
assert_contains "$output" 'Result: CLIENT_INSTRUCTION_REQUIRED'
assert_contains "$output" \
  'Remediation: beroka-governance bootstrap --client codex'
[ ! -s "$CALLS" ] ||
  fail 'Doctor checked the connector before the missing instruction'

printf '%s\n' \
  '# Active override' \
  '<!-- BEROKA-GOVERNANCE:START -->' \
  'stale governance' \
  '<!-- BEROKA-GOVERNANCE:END -->' >"$codex_instruction"
: >"$CALLS"
if output=$($CLI preflight "$repo" --client codex \
  --operation github-write --non-interactive 2>&1)
then
  fail 'Preflight accepted a stale active Codex instruction'
fi
assert_contains "$output" 'Result: CLIENT_INSTRUCTION_REQUIRED'
[ ! -s "$CALLS" ] ||
  fail 'Preflight checked dependencies before the stale instruction'

printf '%s\n' \
  '# Active override' \
  '<!-- BEROKA-GOVERNANCE:START -->' \
  'unterminated governance' >"$codex_instruction"
: >"$CALLS"
if output=$($CLI doctor "$repo" --client codex 2>&1); then
  fail 'Doctor accepted malformed active Codex markers'
fi
assert_contains "$output" 'Result: CLIENT_INSTRUCTION_CONFLICT'
[ ! -s "$CALLS" ] ||
  fail 'Doctor checked the connector before malformed instructions'
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap replaced conflicting active Codex markers'
fi
assert_contains "$output" 'Result: CLIENT_INSTRUCTION_CONFLICT'
cp "$codex_instruction_healthy" "$codex_instruction"

doctor_output=$($CLI doctor "$repo" --client claude)
assert_contains "$doctor_output" 'Instruction: INSTALLED'

cat >"$FAKE_BIN/cursor-agent" <<'EOF'
#!/bin/sh
set -eu
printf 'cursor-agent %s\n' "$*" >>"$CALLS"
case "$*" in
  'mcp login --help') exit 0 ;;
  'mcp list') printf '%s\n' 'atlassian: Ready' ;;
  'mcp list-tools atlassian')
    printf '%s\n' '- getAccessibleAtlassianResources ()'
    ;;
  *) exit 1 ;;
esac
EOF
chmod 755 "$FAKE_BIN/cursor-agent"
cursor_rule=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.1.0/templates/agent-entrypoints/CURSOR-USER-RULE.txt
cursor_hash=$(git -C "$source_repo" hash-object --no-filters "$cursor_rule")
cursor_sha1_cwd=$TEST_ROOT/cursor-sha1-cwd
cursor_sha256_cwd=$TEST_ROOT/cursor-sha256-cwd
mkdir -p "$cursor_sha1_cwd" "$cursor_sha256_cwd"
git -C "$cursor_sha1_cwd" init -q --object-format=sha1
git -C "$cursor_sha256_cwd" init -q --object-format=sha256
git -C "$cursor_sha1_cwd" remote add origin \
  https://github.com/beroka-vn/cursor-sha1-cwd.git
git -C "$cursor_sha256_cwd" remote add origin \
  https://github.com/beroka-vn/cursor-sha256-cwd.git
[ "$(git -C "$cursor_sha1_cwd" rev-parse --show-object-format)" = sha1 ] ||
  fail 'Cursor SHA-1 fixture uses the wrong object format'
[ "$(git -C "$cursor_sha256_cwd" rev-parse --show-object-format)" = sha256 ] ||
  fail 'Cursor SHA-256 fixture uses the wrong object format'
printf '%s\n' codex,claude,cursor \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"
printf '%s\n' "$cursor_hash" \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"
mkdir -p "$HOME/.cursor"
printf '%s\n' \
  '{"mcpServers":{"atlassian":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}}}' \
  >"$HOME/.cursor/mcp.json"
cursor_hooks=$HOME/.cursor/hooks.json
installed_cursor_cli=$BEROKA_GOV_BIN_DIR/beroka-governance
cat >"$cursor_hooks" <<'EOF'
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "command": "/tmp/personal-hook",
        "timeout": 5
      }
    ]
  },
  "personal": {
    "preserved": true
  }
}
EOF
output=$(cd "$cursor_sha1_cwd" &&
  $CLI bootstrap --client cursor --version v1.1.0 --non-interactive)
assert_contains "$output" 'Instruction: USER_CONFIRMED'
assert_contains "$output" 'Runtime hook: INSTALLED'
assert_contains "$output" 'Result: PASS'
assert_contains "$(jq -r '.personal.preserved' "$cursor_hooks")" true
assert_contains "$(jq -r '.hooks.sessionStart[0].command' "$cursor_hooks")" /tmp/personal-hook
assert_cursor_hook "$cursor_hooks" sessionStart "$installed_cursor_cli cursor-hook sessionStart" false
assert_cursor_hook "$cursor_hooks" beforeSubmitPrompt "$installed_cursor_cli cursor-hook beforeSubmitPrompt" false
assert_cursor_hook "$cursor_hooks" preCompact "$installed_cursor_cli cursor-hook preCompact" false
assert_cursor_hook "$cursor_hooks" beforeMCPExecution "$installed_cursor_cli cursor-hook beforeMCPExecution" true
assert_cursor_hook "$cursor_hooks" beforeShellExecution "$installed_cursor_cli cursor-hook beforeShellExecution" true
cursor_hooks_before_repeat=$TEST_ROOT/cursor-hooks-before-repeat
cp "$cursor_hooks" "$cursor_hooks_before_repeat"
cursor_ack_before_format_change=$TEST_ROOT/cursor-ack-before-format-change
cp "$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256" \
  "$cursor_ack_before_format_change"
if ! output=$(cd "$cursor_sha256_cwd" &&
  $CLI bootstrap --client cursor --version v1.1.0 \
    --non-interactive 2>&1)
then
  fail "SHA-256 cwd invalidated Cursor acknowledgement: $output"
fi
assert_contains "$output" 'Instruction: USER_CONFIRMED'
assert_contains "$output" 'Runtime hook: INSTALLED'
assert_contains "$output" 'Result: PASS'
cmp -s "$cursor_ack_before_format_change" \
  "$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256" ||
  fail 'caller repository format changed Cursor acknowledgement'
cmp -s "$cursor_hooks_before_repeat" "$cursor_hooks" ||
  fail 'repeat Cursor bootstrap changed hooks configuration'

: >"$CALLS"
doctor_output=$(cd "$cursor_sha256_cwd" &&
  $CLI doctor "$repo" --client cursor)
assert_contains "$doctor_output" 'Instruction: USER_CONFIRMED'
assert_contains "$doctor_output" 'Runtime hook: INSTALLED'
assert_contains "$doctor_output" 'Runtime enforcement: PASS'
assert_contains "$doctor_output" 'Connector: PASS'
assert_contains "$doctor_output" 'Result: PASS'
cmp -s "$cursor_ack_before_format_change" \
  "$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256" ||
  fail 'Doctor changed Cursor acknowledgement across repository formats'

cursor_hooks_healthy=$TEST_ROOT/cursor-hooks-healthy
cp "$cursor_hooks" "$cursor_hooks_healthy"
jq 'del(.hooks.beforeMCPExecution)' "$cursor_hooks_healthy" >"$cursor_hooks"
if output=$($CLI doctor "$repo" --client cursor 2>&1); then
  fail 'Cursor Doctor accepted missing security hook'
fi
assert_not_contains "$output" 'Runtime enforcement: PASS'
cp "$cursor_hooks_healthy" "$cursor_hooks"
if output=$(jq '(.hooks.beforeMCPExecution[] | select(.command == $command) | .failClosed) = false' \
  --arg command "$installed_cursor_cli cursor-hook beforeMCPExecution" \
  "$cursor_hooks_healthy" >"$cursor_hooks" &&
  $CLI doctor "$repo" --client cursor 2>&1)
then
  fail 'Cursor Doctor accepted conflicting security hook'
fi
assert_not_contains "$output" 'Runtime enforcement: PASS'
cp "$cursor_hooks_healthy" "$cursor_hooks"

mv "$cursor_hooks" "$cursor_hooks_healthy"
ln -s "$cursor_hooks_healthy" "$cursor_hooks"
if output=$($CLI bootstrap --client cursor --version v1.1.0 --non-interactive 2>&1); then
  fail 'Cursor bootstrap accepted a symlinked hooks file'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
cmp -s "$cursor_hooks_healthy" "$(readlink "$cursor_hooks")" ||
  fail 'symlinked Cursor hooks target changed'
rm "$cursor_hooks"
mv "$cursor_hooks_healthy" "$cursor_hooks"

cursor_hooks_invalid=$TEST_ROOT/cursor-hooks-invalid
printf '%s\n' '{' >"$cursor_hooks"
cp "$cursor_hooks" "$cursor_hooks_invalid"
if output=$($CLI bootstrap --client cursor --version v1.1.0 --non-interactive 2>&1); then
  fail 'Cursor bootstrap accepted invalid hooks JSON'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
cmp -s "$cursor_hooks_invalid" "$cursor_hooks" ||
  fail 'invalid Cursor hooks JSON changed during bootstrap'
cp "$cursor_hooks_before_repeat" "$cursor_hooks"

cursor_hooks_multi=$TEST_ROOT/cursor-hooks-multi
printf '%s\n%s\n' '{"version":1}' '{"version":1}' >"$cursor_hooks"
cp "$cursor_hooks" "$cursor_hooks_multi"
if output=$($CLI bootstrap --client cursor --version v1.1.0 --non-interactive 2>&1); then
  fail 'Cursor bootstrap accepted multi-document hooks JSON'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
cmp -s "$cursor_hooks_multi" "$cursor_hooks" ||
  fail 'multi-document Cursor hooks JSON changed during bootstrap'
cp "$cursor_hooks_before_repeat" "$cursor_hooks"

cursor_hooks_conflict=$TEST_ROOT/cursor-hooks-conflict
jq '(.hooks.beforeMCPExecution[] | select(.command == $command) | .failClosed) = false' \
  --arg command "$installed_cursor_cli cursor-hook beforeMCPExecution" \
  "$cursor_hooks" >"$cursor_hooks_conflict"
cp "$cursor_hooks_conflict" "$cursor_hooks"
if output=$($CLI bootstrap --client cursor --version v1.1.0 --non-interactive 2>&1); then
  fail 'Cursor bootstrap accepted a conflicting managed hook'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
cmp -s "$cursor_hooks_conflict" "$cursor_hooks" ||
  fail 'conflicting Cursor hooks changed during bootstrap'
cp "$cursor_hooks_before_repeat" "$cursor_hooks"

mv "$cursor_hooks" "$cursor_hooks_healthy"
if output=$($CLI doctor "$repo" --client cursor 2>&1); then
  fail 'Cursor Doctor accepted an acknowledgement without hooks'
fi
assert_not_contains "$output" 'Runtime hook: INSTALLED'
assert_not_contains "$output" 'Runtime enforcement: PASS'
mv "$cursor_hooks_healthy" "$cursor_hooks"
rm -rf "$HOME/.cursor"

printf '%s\n' 0000000000000000000000000000000000000000 \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"
: >"$CALLS"
if output=$($CLI doctor "$repo" --client cursor 2>&1); then
  fail 'Cursor Doctor accepted a stale User Rule acknowledgement'
fi
assert_contains "$output" 'Result: CURSOR_USER_RULE_REQUIRED'
assert_contains "$output" \
  'Remediation: beroka-governance bootstrap --client cursor'
[ ! -s "$CALLS" ] ||
  fail 'Cursor Doctor checked dependencies before the stale acknowledgement'

printf '%s\n%s\n' "$cursor_hash" extra \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"
if output=$($CLI doctor "$repo" --client cursor 2>&1); then
  fail 'Cursor Doctor accepted a malformed User Rule acknowledgement'
fi
assert_contains "$output" 'Result: CURSOR_USER_RULE_REQUIRED'
printf '%s\n' codex,claude \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"
rm -f "$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"

if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.2.0 --non-interactive 2>&1)
then
  fail 'bootstrap silently changed the active release'
fi
assert_contains "$output" 'Result: GOVERNANCE_UPGRADE_REQUIRED'
assert_contains "$output" \
  'Remediation: beroka-governance bootstrap --client codex --version v1.2.0 --upgrade --non-interactive'
[ "$active_before" = "$(cat "$active_release")" ] ||
  fail 'upgrade-required failure changed the active release'

: >"$CALLS"
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.2.0 --upgrade --non-interactive)
assert_contains "$output" 'Version: v1.2.0'
[ "$(cat "$active_release")" = "$(printf '%s\n%s' \
  'VERSION=v1.2.0' "COMMIT=$v1_2_commit")" ] ||
  fail 'upgrade activated the wrong verified commit'
[ "$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/clients")" = codex,claude ] ||
  fail 'upgrade discarded enabled clients'
[ -f "$XDG_CONFIG_HOME/fake-codex-configured" ] &&
  [ -f "$XDG_CONFIG_HOME/fake-claude-configured" ] ||
  fail 'upgrade discarded client-owned connector state'
assert_contains "$(cat "$CALLS")" 'codex app-server --stdio'
assert_not_contains "$(cat "$CALLS")" 'claude '
assert_contains "$(cat "$HOME/.codex/AGENTS.override.md")" \
  'verified v1.2 Beroka governance'
assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" \
  'verified v1.2 Beroka governance'
doctor_output=$($CLI doctor "$repo" --client codex)
assert_contains "$doctor_output" 'Instruction: INSTALLED'
doctor_output=$($CLI doctor "$repo" --client claude)
assert_contains "$doctor_output" 'Instruction: INSTALLED'

active_v1_2=$(cat "$active_release")
clients_v1_2=$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/clients")
codex_v1_2=$(cat "$HOME/.codex/AGENTS.override.md")
claude_v1_2=$(cat "$HOME/.claude/CLAUDE.md")
output=$($CLI bootstrap "$repo" --client codex \
  --version v1.2.0 --upgrade --non-interactive)
assert_contains "$output" 'Version: v1.2.0'
[ "$active_v1_2" = "$(cat "$active_release")" ] ||
  fail 'same-version upgrade changed the active release'
[ "$clients_v1_2" = \
  "$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/clients")" ] ||
  fail 'same-version upgrade changed client enrollment'
[ "$codex_v1_2" = "$(cat "$HOME/.codex/AGENTS.override.md")" ] ||
  fail 'same-version upgrade changed Codex instructions'
[ "$claude_v1_2" = "$(cat "$HOME/.claude/CLAUDE.md")" ] ||
  fail 'same-version upgrade changed Claude instructions'

for invalid_upgrade in v1.1.0 v2.0.0; do
  if output=$($CLI bootstrap "$repo" --client codex \
    --version "$invalid_upgrade" --upgrade --non-interactive 2>&1)
  then
    fail "bootstrap accepted invalid upgrade target $invalid_upgrade"
  fi
  assert_contains "$output" 'Result: VERSION_MISMATCH'
  [ "$(cat "$active_release")" = "$(printf '%s\n%s' \
    'VERSION=v1.2.0' "COMMIT=$v1_2_commit")" ] ||
    fail "invalid upgrade $invalid_upgrade changed the active release"
done

if output=$($CLI bootstrap "$repo" --client cursor \
  --version v1.2.0 --non-interactive 2>&1)
then
  fail 'Cursor bootstrap accepted a missing User Rule acknowledgement'
fi
assert_contains "$output" 'Result: CURSOR_USER_RULE_REQUIRED'
assert_contains "$output" \
  'Remediation: beroka-governance bootstrap --client cursor'
[ ! -e "$HOME/.cursor" ] ||
  fail 'Cursor bootstrap edited undocumented Cursor state'

$CLI uninstall --force >/dev/null
cmp -s "$codex_personal_expected" "$HOME/.codex/AGENTS.md" ||
  fail 'uninstall changed no-newline Codex personal instructions'
cmp -s "$codex_override_expected" "$HOME/.codex/AGENTS.override.md" ||
  fail 'uninstall changed no-newline Codex override instructions'
cmp -s "$claude_personal_expected" "$HOME/.claude/CLAUDE.md" ||
  fail 'uninstall changed no-newline Claude personal instructions'

printf '%s\n' 'Bootstrap onboarding tests: PASS'
