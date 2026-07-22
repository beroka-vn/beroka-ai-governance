#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLI=$ROOT/bin/beroka-governance
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

export HOME=$TMP_ROOT/home
export XDG_DATA_HOME=$TMP_ROOT/data
export XDG_CONFIG_HOME=$TMP_ROOT/config
export BEROKA_GOV_BIN_DIR=$TMP_ROOT/bin
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$BEROKA_GOV_BIN_DIR"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

grep -F "trap 'tx_abort; exit 1' HUP INT TERM" "$CLI" >/dev/null ||
  fail 'signal trap does not abort with a non-zero exit'

assert_contains() {
  haystack=$1
  needle=$2
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "expected [$needle] in [$haystack]" ;;
  esac
}

new_repo() {
  path=$1
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name test-user
  git -C "$path" config user.email test@example.invalid
}

make_release_fixture() {
  source_repo=$TMP_ROOT/source
  new_repo "$source_repo"
  mkdir -p "$source_repo/runtime" "$source_repo/templates/agent-entrypoints"
  printf 'v1.0.0\n' >"$source_repo/VERSION"
  printf 'PINNED ENTRYPOINT v1.0.0\n' >"$source_repo/runtime/entrypoint.md"
  printf 'GOVERNANCE v1.0.0\n' >"$source_repo/governance.md"
  printf 'HANDBOOK v1.0.0\n' >"$source_repo/handbook.md"
  printf 'WORKFLOW v1.0.0\n' >"$source_repo/workflow.md"
  printf 'JIRA TEMPLATE v1.0.0\n' >"$source_repo/templates/jira-confluence.md"
  cp "$ROOT/templates/agent-entrypoints/AGENTS.md" "$source_repo/templates/agent-entrypoints/AGENTS.md"
  cp "$ROOT/templates/agent-entrypoints/CLAUDE.md" "$source_repo/templates/agent-entrypoints/CLAUDE.md"
  cp "$ROOT/templates/agent-entrypoints/team-dev-ai-workflow.mdc" "$source_repo/templates/agent-entrypoints/team-dev-ai-workflow.mdc"
  git -C "$source_repo" add .
  git -C "$source_repo" commit -qm 'test: create v1 fixture'
  git -C "$source_repo" tag -a v1.0.0 -m 'v1.0.0'
  release_dir=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.0.0
  mkdir -p "$(dirname -- "$release_dir")"
  git clone -q --depth 1 --branch v1.0.0 "file://$source_repo" "$release_dir"
  RELEASE_COMMIT=$(git -C "$release_dir" rev-parse HEAD)
  export RELEASE_COMMIT
}

make_consumer_fixture() {
  consumer=$TMP_ROOT/consumer
  new_repo "$consumer"
  git -C "$consumer" remote add origin https://github.com/beroka-vn/example-backend.git
  printf '%s\n' \
    'SOURCE=beroka-vn/beroka-ai-governance' \
    'REPOSITORY=beroka-vn/example-backend' \
    'VERSION=v1.0.0' \
    "COMMIT=$RELEASE_COMMIT" >"$consumer/.beroka-governance.lock"
  cp "$source_repo/templates/agent-entrypoints/AGENTS.md" "$consumer/AGENTS.md"
  cp "$source_repo/templates/agent-entrypoints/CLAUDE.md" "$consumer/CLAUDE.md"
  mkdir -p "$consumer/.cursor/rules"
  cp "$source_repo/templates/agent-entrypoints/team-dev-ai-workflow.mdc" "$consumer/.cursor/rules/beroka-governance.mdc"
  git -C "$consumer" add .beroka-governance.lock AGENTS.md CLAUDE.md .cursor/rules/beroka-governance.mdc
  git -C "$consumer" commit -qm 'test: register governance lock'
}

make_release_fixture
make_consumer_fixture

doctor_output=$($CLI doctor "$consumer")
assert_contains "$doctor_output" 'Result: PASS'
assert_contains "$doctor_output" 'Version: v1.0.0'

context_output=$($CLI context "$consumer")
assert_contains "$context_output" 'PINNED ENTRYPOINT v1.0.0'

show_output=$($CLI show "$consumer" governance)
assert_contains "$show_output" 'GOVERNANCE v1.0.0'

template_output=$($CLI show "$consumer" template jira-confluence)
assert_contains "$template_output" 'JIRA TEMPLATE v1.0.0'

git -C "$release_dir" tag -d v1.0.0
git -C "$release_dir" tag v1.0.0 "$RELEASE_COMMIT"
if $CLI doctor "$consumer" >/dev/null 2>&1; then
  fail 'doctor accepted lightweight tag'
fi

lightweight_repo=$TMP_ROOT/lightweight-consumer
new_repo "$lightweight_repo"
git -C "$lightweight_repo" remote add origin https://github.com/beroka-vn/lightweight-backend.git
if $CLI register "$lightweight_repo" --version v1.0.0 >/dev/null 2>&1; then
  fail 'register accepted lightweight tag'
fi
[ ! -e "$lightweight_repo/.beroka-governance.lock" ] || fail 'lightweight tag wrote a lock'
git -C "$release_dir" tag -d v1.0.0
git -C "$release_dir" config user.name test-user
git -C "$release_dir" config user.email test@example.invalid
git -C "$release_dir" tag -a v1.0.0 -m 'v1.0.0' "$RELEASE_COMMIT"

if $CLI show "$consumer" ../../etc/passwd >/dev/null 2>&1; then
  fail 'show accepted path traversal'
fi

printf 'PASS: read-only package validation\n'

register_repo=$TMP_ROOT/register-consumer
new_repo "$register_repo"
git -C "$register_repo" remote add origin git@github.com:beroka-vn/register-backend.git
printf '# Existing repository rules\n\nKeep this line.\n' >"$register_repo/AGENTS.md"
printf '# Existing Claude rules\n\nKeep this Claude line.\n' >"$register_repo/CLAUDE.md"
git -C "$register_repo" add AGENTS.md CLAUDE.md
git -C "$register_repo" commit -qm 'test: add existing agent rules'

$CLI register "$register_repo" --version v1.0.0
first_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
$CLI register "$register_repo" --version v1.0.0
second_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
[ "$first_hash" = "$second_hash" ] || fail 'repeated register changed managed files'
assert_contains "$(cat "$register_repo/AGENTS.md")" 'Keep this line.'
assert_contains "$(cat "$register_repo/CLAUDE.md")" 'Keep this Claude line.'
assert_contains "$(cat "$register_repo/.beroka-governance.lock")" 'REPOSITORY=beroka-vn/register-backend'
idempotent_dry_output=$($CLI register "$register_repo" --version v1.0.0 --dry-run)
assert_contains "$idempotent_dry_output" "$register_repo/.beroka-governance.lock"
assert_contains "$idempotent_dry_output" "$register_repo/AGENTS.md"
assert_contains "$idempotent_dry_output" "$register_repo/CLAUDE.md"
assert_contains "$idempotent_dry_output" "$register_repo/.cursor/rules/beroka-governance.mdc"
third_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
[ "$second_hash" = "$third_hash" ] || fail 'idempotent dry-run changed managed files'

dry_repo=$TMP_ROOT/dry-consumer
new_repo "$dry_repo"
git -C "$dry_repo" remote add origin https://github.com/beroka-vn/dry-backend.git
$CLI register "$dry_repo" --version v1.0.0 --dry-run >/dev/null
[ ! -e "$dry_repo/.beroka-governance.lock" ] || fail 'dry-run created a lock'

dirty_repo=$TMP_ROOT/dirty-consumer
new_repo "$dirty_repo"
git -C "$dirty_repo" remote add origin https://github.com/beroka-vn/dirty-backend.git
printf 'uncommitted rules\n' >"$dirty_repo/AGENTS.md"
if $CLI register "$dirty_repo" --version v1.0.0 >/dev/null 2>&1; then fail 'register accepted a dirty target entrypoint'; fi
[ "$(cat "$dirty_repo/AGENTS.md")" = 'uncommitted rules' ] || fail 'failed preflight modified AGENTS.md'

printf '%s\n' '<!-- BEROKA-GOVERNANCE:END -->' '<!-- BEROKA-GOVERNANCE:START -->' >"$release_dir/templates/agent-entrypoints/AGENTS.md"
git -C "$release_dir" add templates/agent-entrypoints/AGENTS.md
git -C "$release_dir" commit -qm 'test: corrupt template marker order'
git -C "$release_dir" tag -d v1.0.0
git -C "$release_dir" tag -a v1.0.0 -m 'v1.0.0' HEAD
marker_repo=$TMP_ROOT/marker-consumer
new_repo "$marker_repo"
git -C "$marker_repo" remote add origin https://github.com/beroka-vn/marker-backend.git
if $CLI register "$marker_repo" --version v1.0.0 >/dev/null 2>&1; then
  fail 'register accepted end-before-start template markers'
fi
[ ! -e "$marker_repo/.beroka-governance.lock" ] || fail 'malformed template wrote a lock'

printf 'PASS: repository registration\n'
