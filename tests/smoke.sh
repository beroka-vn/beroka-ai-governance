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
git config --global advice.detachedHead false

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
  mkdir -p "$source_repo/bin" "$source_repo/runtime" "$source_repo/templates/agent-entrypoints"
  printf 'v1.0.0\n' >"$source_repo/VERSION"
  cp "$CLI" "$source_repo/bin/beroka-governance"
  chmod 755 "$source_repo/bin/beroka-governance"
  rm -rf "$source_repo/runtime"
  cp -R "$ROOT/runtime" "$source_repo/runtime"
  rm -f "$source_repo/runtime/routing-schema"
  rm -rf "$source_repo/runtime/rules" "$source_repo/runtime/profiles" \
    "$source_repo/runtime/integrations"
  printf 'PINNED ENTRYPOINT v1.0.0\n' >"$source_repo/runtime/entrypoint.md"
  printf 'GOVERNANCE v1.0.0\n' >"$source_repo/governance.md"
  printf 'HANDBOOK v1.0.0\n' >"$source_repo/handbook.md"
  printf 'WORKFLOW v1.0.0\n' >"$source_repo/workflow.md"
  printf 'ASSIGNMENT TEMPLATE v1.0.0\n' >"$source_repo/templates/ai-agent-assignment.md"
  printf 'GITHUB TEMPLATE v1.0.0\n' >"$source_repo/templates/github-issue.md"
  printf 'JIRA TEMPLATE v1.0.0\n' >"$source_repo/templates/jira-confluence.md"
  printf 'PULL REQUEST TEMPLATE v1.0.0\n' >"$source_repo/templates/pull-request.md"
  cp "$ROOT/templates/agent-entrypoints/AGENTS.md" "$source_repo/templates/agent-entrypoints/AGENTS.md"
  cp "$ROOT/templates/agent-entrypoints/CLAUDE.md" "$source_repo/templates/agent-entrypoints/CLAUDE.md"
  cp "$ROOT/templates/agent-entrypoints/team-dev-ai-workflow.mdc" "$source_repo/templates/agent-entrypoints/team-dev-ai-workflow.mdc"
  git -C "$source_repo" add .
  git -C "$source_repo" commit -qm 'test: create v1 fixture'
  git -C "$source_repo" tag -a v1.0.0 -m 'v1.0.0'
  printf 'v1.1.0\n' >"$source_repo/VERSION"
  rm -rf "$source_repo/runtime"
  cp -R "$ROOT/runtime" "$source_repo/runtime"
  printf 'PINNED ENTRYPOINT v1.1.0\n' >"$source_repo/runtime/entrypoint.md"
  printf 'GOVERNANCE v1.1.0\n' >"$source_repo/governance.md"
  git -C "$source_repo" add .
  git -C "$source_repo" commit -qm 'test: create v1.1 fixture'
  git -C "$source_repo" tag -a v1.1.0 -m 'v1.1.0'
  rm -f "$source_repo/bin/beroka-governance"
  printf 'v1.2.0\n' >"$source_repo/VERSION"
  git -C "$source_repo" add .
  git -C "$source_repo" commit -qm 'test: create malformed v1.2 fixture'
  git -C "$source_repo" tag -a v1.2.0 -m 'v1.2.0'
  git -C "$source_repo" show v1.1.0:bin/beroka-governance >"$source_repo/bin/beroka-governance"
  chmod 755 "$source_repo/bin/beroka-governance"
  printf 'v1.3.0\n' >"$source_repo/VERSION"
  rm -f "$source_repo/governance.md"
  ln -s handbook.md "$source_repo/governance.md"
  git -C "$source_repo" add .
  git -C "$source_repo" commit -qm 'test: create symlinked v1.3 fixture'
  git -C "$source_repo" tag -a v1.3.0 -m 'v1.3.0'
  rm -f "$source_repo/governance.md"
  printf 'GOVERNANCE v1.4.0\n' >"$source_repo/governance.md"
  printf 'v1.4.0\n' >"$source_repo/VERSION"
  printf '\n# v1.4.0 fixture\n' >>"$source_repo/bin/beroka-governance"
  awk -v end='<!-- BEROKA-GOVERNANCE:END -->' '
    $0 == end { print "V1.4 ROUTING" }
    { print }
  ' "$source_repo/templates/agent-entrypoints/AGENTS.md" >"$source_repo/AGENTS.next"
  mv "$source_repo/AGENTS.next" "$source_repo/templates/agent-entrypoints/AGENTS.md"
  git -C "$source_repo" add .
  git -C "$source_repo" commit -qm 'test: create valid v1.4 fixture'
  git -C "$source_repo" tag -a v1.4.0 -m 'v1.4.0'
  git config --global url."file://$source_repo".insteadOf https://github.com/beroka-vn/beroka-ai-governance.git
  release_dir=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.0.0
  mkdir -p "$(dirname -- "$release_dir")"
  git clone -q --depth 1 --branch v1.0.0 https://github.com/beroka-vn/beroka-ai-governance.git "$release_dir"
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
  cp "$release_dir/templates/agent-entrypoints/AGENTS.md" "$consumer/AGENTS.md"
  cp "$release_dir/templates/agent-entrypoints/CLAUDE.md" "$consumer/CLAUDE.md"
  mkdir -p "$consumer/.cursor/rules"
  cp "$release_dir/templates/agent-entrypoints/team-dev-ai-workflow.mdc" "$consumer/.cursor/rules/beroka-governance.mdc"
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
case "$context_output" in
  *'Routing:'*) fail 'legacy Context resolved routing' ;;
esac

show_output=$($CLI show "$consumer" governance)
assert_contains "$show_output" 'GOVERNANCE v1.0.0'

template_output=$($CLI show "$consumer" template jira-confluence)
assert_contains "$template_output" 'JIRA TEMPLATE v1.0.0'

git -C "$release_dir" remote set-url origin https://github.com/attacker/beroka-ai-governance.git
if forged_origin_output=$($CLI doctor "$consumer" 2>&1); then
  fail 'doctor accepted an installed release from an untrusted origin'
fi
assert_contains "$forged_origin_output" 'Result: VERSION_MISMATCH'
git -C "$release_dir" remote set-url origin https://github.com/beroka-vn/beroka-ai-governance.git

fail_cat_dir=$TMP_ROOT/fail-cat
mkdir -p "$fail_cat_dir"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$fail_cat_dir/cat"
chmod 755 "$fail_cat_dir/cat"
if context_error=$(PATH=$fail_cat_dir:$PATH $CLI context "$consumer" 2>&1); then
  fail 'context accepted an unreadable runtime entrypoint'
fi
assert_contains "$context_error" 'Result: GOVERNANCE_NOT_READY'
if show_error=$(PATH=$fail_cat_dir:$PATH $CLI show "$consumer" governance 2>&1); then
  fail 'show accepted an unreadable package document'
fi
assert_contains "$show_error" 'Result: GOVERNANCE_NOT_READY'

git -C "$release_dir" tag -d v1.0.0 >/dev/null
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
git -C "$release_dir" tag -d v1.0.0 >/dev/null
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
rm -f "$XDG_CONFIG_HOME/beroka-ai-governance/registered-repos"
$CLI register "$register_repo" --version v1.0.0
registry_row=$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/registered-repos")
assert_contains "$registry_row" "$register_repo"
assert_contains "$registry_row" 'beroka-vn/register-backend'
assert_contains "$registry_row" 'v1.0.0'
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

ignored_repo=$TMP_ROOT/ignored-consumer
new_repo "$ignored_repo"
git -C "$ignored_repo" remote add origin https://github.com/beroka-vn/ignored-backend.git///
printf 'AGENTS.md\n' >"$ignored_repo/.gitignore"
git -C "$ignored_repo" add .gitignore
git -C "$ignored_repo" commit -qm 'test: ignore managed target'
printf 'ignored unmanaged rules\n' >"$ignored_repo/AGENTS.md"
if ignored_output=$($CLI register "$ignored_repo" --version v1.0.0 2>&1); then
  fail 'register accepted an ignored dirty target entrypoint'
fi
assert_contains "$ignored_output" 'Result: WORKTREE_CONFLICT'
[ "$(cat "$ignored_repo/AGENTS.md")" = 'ignored unmanaged rules' ] || fail 'ignored-target refusal changed AGENTS.md'
[ ! -e "$ignored_repo/.beroka-governance.lock" ] || fail 'ignored-target refusal wrote a lock'

registry_path=$XDG_CONFIG_HOME/beroka-ai-governance/registered-repos
registry_contents=$(cat "$registry_path")
rm -f "$registry_path"
mkdir "$registry_path"
if registry_dir_output=$($CLI register "$register_repo" --version v1.0.0 2>&1); then
  fail 'register accepted a registry directory'
fi
assert_contains "$registry_dir_output" 'Result: GOVERNANCE_NOT_READY'
if registry_dir_repin_output=$($CLI update "$register_repo" --to v1.0.0 2>&1); then
  fail 'repin accepted a registry directory'
fi
assert_contains "$registry_dir_repin_output" 'Result: GOVERNANCE_NOT_READY'
rmdir "$registry_path"
registry_sentinel=$TMP_ROOT/registry-sentinel
printf 'keep registry target\n' >"$registry_sentinel"
ln -s "$registry_sentinel" "$registry_path"
if registry_link_output=$($CLI register "$register_repo" --version v1.0.0 2>&1); then
  fail 'register accepted a symlinked registry'
fi
assert_contains "$registry_link_output" 'Result: GOVERNANCE_NOT_READY'
if registry_link_unregister_output=$($CLI unregister "$register_repo" --dry-run 2>&1); then
  fail 'unregister accepted a symlinked registry'
fi
assert_contains "$registry_link_unregister_output" 'Result: GOVERNANCE_NOT_READY'
[ "$(cat "$registry_sentinel")" = 'keep registry target' ] || fail 'registry symlink failure changed its target'
rm -f "$registry_path"
printf '%s\n' "$registry_contents" >"$registry_path"

git -C "$register_repo" add .
git -C "$register_repo" commit -qm 'test: commit v1.0 registration'

printf '\nDirty unmanaged addition.\n' >>"$register_repo/AGENTS.md"
failed_repin_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
failed_repin_registry=$(cat "$registry_path")
[ ! -e "$BEROKA_GOV_BIN_DIR/beroka-governance" ] || fail 'unexpected installed CLI before atomic repin test'
if failed_repin_output=$($CLI update "$register_repo" --to v1.4.0 2>&1); then
  fail 'update accepted a dirty managed target'
fi
assert_contains "$failed_repin_output" 'Result: WORKTREE_CONFLICT'
[ ! -e "$XDG_DATA_HOME/beroka-ai-governance/releases/v1.4.0" ] || fail 'failed repin left the new release'
[ ! -e "$BEROKA_GOV_BIN_DIR/beroka-governance" ] || fail 'failed repin changed the user CLI'
[ "$failed_repin_hash" = "$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)" ] || fail 'failed repin changed repository files'
[ "$failed_repin_registry" = "$(cat "$registry_path")" ] || fail 'failed repin changed registry'
git -C "$register_repo" checkout -- AGENTS.md

fail_mv_dir=$TMP_ROOT/fail-mv
mkdir -p "$fail_mv_dir"
printf '%s\n' \
  '#!/bin/sh' \
  'for last_arg do :; done' \
  'if [ "${FAIL_PROMOTION_PATH:-}" = "$last_arg" ]; then printf "%s\n" "$1" >"$PROMOTION_SOURCE_FILE"; exit 1; fi' \
  'if [ "${INTERRUPT_AFTER_PROMOTION_PATH:-}" = "$last_arg" ]; then "$SYSTEM_MV" "$@"; kill -TERM "$PPID"; sleep 1; exit 1; fi' \
  'if [ "${FAIL_REGISTRY_PATH:-}" = "$last_arg" ]; then exit 1; fi' \
  'exec "$SYSTEM_MV" "$@"' >"$fail_mv_dir/mv"
chmod 755 "$fail_mv_dir/mv"
SYSTEM_MV=$(command -v mv)
export SYSTEM_MV
rollback_repin_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
rollback_repin_registry=$(cat "$registry_path")
if rollback_repin_output=$(PATH=$fail_mv_dir:$PATH FAIL_REGISTRY_PATH=$registry_path $CLI update "$register_repo" --to v1.4.0 2>&1); then
  fail 'update ignored a registry activation failure'
fi
assert_contains "$rollback_repin_output" 'Result: GOVERNANCE_NOT_READY'
[ ! -e "$XDG_DATA_HOME/beroka-ai-governance/releases/v1.4.0" ] || fail 'rolled-back repin kept the new release'
[ ! -e "$BEROKA_GOV_BIN_DIR/beroka-governance" ] || fail 'rolled-back repin kept the new CLI'
[ "$rollback_repin_hash" = "$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)" ] || fail 'rolled-back repin kept repository changes'
[ "$rollback_repin_registry" = "$(cat "$registry_path")" ] || fail 'rolled-back repin changed registry'

promotion_source_file=$TMP_ROOT/promotion-source
promotion_target=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.4.0
failed_promotion_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
failed_promotion_registry=$(cat "$registry_path")
if failed_promotion_output=$(PATH=$fail_mv_dir:$PATH FAIL_PROMOTION_PATH=$promotion_target PROMOTION_SOURCE_FILE=$promotion_source_file $CLI update "$register_repo" --to v1.4.0 2>&1); then
  fail 'update ignored a release-promotion failure'
fi
assert_contains "$failed_promotion_output" 'Result: GOVERNANCE_NOT_READY'
case "$(cat "$promotion_source_file")" in
  "$XDG_DATA_HOME/beroka-ai-governance/releases/.install."*) ;;
  *) fail 'release stage was not a sibling beneath releases' ;;
esac
[ ! -e "$promotion_target" ] || fail 'failed promotion left the target release'
[ ! -e "$BEROKA_GOV_BIN_DIR/beroka-governance" ] || fail 'failed promotion changed the user CLI'
[ "$failed_promotion_hash" = "$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)" ] || fail 'failed promotion changed repository files'
[ "$failed_promotion_registry" = "$(cat "$registry_path")" ] || fail 'failed promotion changed registry'
for release_stage in "$XDG_DATA_HOME/beroka-ai-governance/releases"/.install.*; do
  [ ! -e "$release_stage" ] || fail 'failed promotion left its release stage'
done

interrupted_promotion_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
interrupted_promotion_registry=$(cat "$registry_path")
if PATH=$fail_mv_dir:$PATH INTERRUPT_AFTER_PROMOTION_PATH=$promotion_target $CLI update "$register_repo" --to v1.4.0 >/dev/null 2>&1; then
  fail 'update survived an interruption immediately after release promotion'
fi
[ ! -e "$promotion_target" ] || fail 'interrupted promotion leaked the target release'
[ ! -e "$BEROKA_GOV_BIN_DIR/beroka-governance" ] || fail 'interrupted promotion changed the user CLI'
[ "$interrupted_promotion_hash" = "$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)" ] || fail 'interrupted promotion changed repository files'
[ "$interrupted_promotion_registry" = "$(cat "$registry_path")" ] || fail 'interrupted promotion changed registry'
for release_stage in "$XDG_DATA_HOME/beroka-ai-governance/releases"/.install.*; do
  [ ! -e "$release_stage" ] || fail 'interrupted promotion left its release stage'
done

absent_dry_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
absent_dry_registry=$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/registered-repos")
absent_dry_output=$($CLI update "$register_repo" --to v1.2.0 --dry-run)
assert_contains "$absent_dry_output" 'INSTALL v1.2.0'
[ ! -e "$XDG_DATA_HOME/beroka-ai-governance/releases/v1.2.0" ] || fail 'absent dry-run installed a release'
[ "$absent_dry_hash" = "$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)" ] || fail 'absent dry-run changed entrypoints'
[ "$absent_dry_registry" = "$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/registered-repos")" ] || fail 'absent dry-run changed registry'

if $CLI install v1.2.0 >/dev/null 2>&1; then fail 'install accepted a release without the CLI'; fi
[ ! -e "$XDG_DATA_HOME/beroka-ai-governance/releases/v1.2.0" ] || fail 'malformed release left an installed checkout'
if $CLI install v1.3.0 >/dev/null 2>&1; then fail 'install accepted symlinked allowlisted release content'; fi
[ ! -e "$XDG_DATA_HOME/beroka-ai-governance/releases/v1.3.0" ] || fail 'symlinked release left an installed checkout'

external_data=$TMP_ROOT/external-data
mkdir -p "$external_data"
printf 'keep data\n' >"$external_data/sentinel"
ln -s "$external_data" "$HOME/data-link"
if data_escape_output=$(XDG_DATA_HOME=$HOME/data-link "$CLI" install v1.1.0 2>&1); then
  fail 'install accepted a symlinked data root'
fi
assert_contains "$data_escape_output" 'Result: GOVERNANCE_NOT_READY'
[ "$(cat "$external_data/sentinel")" = 'keep data' ] || fail 'data-root escape changed the external sentinel'

external_config=$TMP_ROOT/external-config
mkdir -p "$external_config"
printf 'keep config\n' >"$external_config/sentinel"
ln -s "$external_config" "$HOME/config-link"
if config_escape_output=$(XDG_CONFIG_HOME=$HOME/config-link "$CLI" register "$register_repo" --version v1.0.0 2>&1); then
  fail 'register accepted a symlinked config root'
fi
assert_contains "$config_escape_output" 'Result: GOVERNANCE_NOT_READY'
[ "$(cat "$external_config/sentinel")" = 'keep config' ] || fail 'config-root escape changed the external sentinel'
[ ! -e "$external_config/beroka-ai-governance/registered-repos" ] || fail 'config-root escape created an external registry'

external_bin=$TMP_ROOT/external-bin
mkdir -p "$external_bin"
printf 'keep cli\n' >"$external_bin/beroka-governance"
ln -s "$external_bin" "$HOME/bin-link"
if bin_escape_output=$(BEROKA_GOV_BIN_DIR=$HOME/bin-link "$CLI" install v1.1.0 2>&1); then
  fail 'install accepted a symlinked bin directory'
fi
assert_contains "$bin_escape_output" 'Result: GOVERNANCE_NOT_READY'
[ "$(cat "$external_bin/beroka-governance")" = 'keep cli' ] || fail 'bin escape changed the external sentinel'

if uninstall_data_escape=$(XDG_DATA_HOME=$HOME/data-link XDG_CONFIG_HOME=$TMP_ROOT/safe-data-config BEROKA_GOV_BIN_DIR=$TMP_ROOT/safe-data-bin "$CLI" uninstall --force 2>&1); then
  fail 'uninstall accepted a symlinked data root'
fi
assert_contains "$uninstall_data_escape" 'Result: GOVERNANCE_NOT_READY'
[ "$(cat "$external_data/sentinel")" = 'keep data' ] || fail 'uninstall data escape changed the external sentinel'

if uninstall_config_escape=$(XDG_DATA_HOME=$TMP_ROOT/safe-config-data XDG_CONFIG_HOME=$HOME/config-link BEROKA_GOV_BIN_DIR=$TMP_ROOT/safe-config-bin "$CLI" uninstall --force 2>&1); then
  fail 'uninstall accepted a symlinked config root'
fi
assert_contains "$uninstall_config_escape" 'Result: GOVERNANCE_NOT_READY'
[ "$(cat "$external_config/sentinel")" = 'keep config' ] || fail 'uninstall config escape changed the external sentinel'

if uninstall_bin_escape=$(XDG_DATA_HOME=$TMP_ROOT/safe-bin-data XDG_CONFIG_HOME=$TMP_ROOT/safe-bin-config BEROKA_GOV_BIN_DIR=$HOME/bin-link "$CLI" uninstall --force 2>&1); then
  fail 'uninstall accepted a symlinked bin directory'
fi
assert_contains "$uninstall_bin_escape" 'Result: GOVERNANCE_NOT_READY'
[ "$(cat "$external_bin/beroka-governance")" = 'keep cli' ] || fail 'uninstall bin escape changed the external sentinel'

$CLI install v1.1.0
[ -d "$XDG_DATA_HOME/beroka-ai-governance/releases/v1.1.0/.git" ] || fail 'install did not create v1.1.0'
[ -x "$BEROKA_GOV_BIN_DIR/beroka-governance" ] || fail 'install did not update the user CLI'
installed_doctor_output=$("$BEROKA_GOV_BIN_DIR/beroka-governance" doctor "$register_repo")
assert_contains "$installed_doctor_output" 'Result: PASS'
release_v11=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.1.0
git -C "$release_v11" checkout -qb fixture-branch
if $CLI install v1.1.0 >/dev/null 2>&1; then fail 'install accepted a non-detached release'; fi
git -C "$release_v11" checkout -q --detach v1.1.0

agents_inode_before=$(ls -i "$register_repo/AGENTS.md" | awk '{ print $1 }')
claude_inode_before=$(ls -i "$register_repo/CLAUDE.md" | awk '{ print $1 }')
cursor_inode_before=$(ls -i "$register_repo/.cursor/rules/beroka-governance.mdc" | awk '{ print $1 }')
$CLI update "$register_repo" --to v1.1.0
assert_contains "$(cat "$register_repo/.beroka-governance.lock")" 'VERSION=v1.1.0'
assert_contains "$($CLI context "$register_repo")" 'PINNED ENTRYPOINT v1.1.0'
[ "$agents_inode_before" = "$(ls -i "$register_repo/AGENTS.md" | awk '{ print $1 }')" ] || fail 'repin rewrote identical AGENTS.md'
[ "$claude_inode_before" = "$(ls -i "$register_repo/CLAUDE.md" | awk '{ print $1 }')" ] || fail 'repin rewrote identical CLAUDE.md'
[ "$cursor_inode_before" = "$(ls -i "$register_repo/.cursor/rules/beroka-governance.mdc" | awk '{ print $1 }')" ] || fail 'repin rewrote identical Cursor rule'
git -C "$register_repo" add .
git -C "$register_repo" commit -qm 'test: commit v1.1 update'

$CLI rollback "$register_repo" --to v1.0.0
assert_contains "$(cat "$register_repo/.beroka-governance.lock")" 'VERSION=v1.0.0'
assert_contains "$($CLI context "$register_repo")" 'PINNED ENTRYPOINT v1.0.0'
git -C "$register_repo" add .
git -C "$register_repo" commit -qm 'test: commit v1.0 rollback'

cp "$register_repo/AGENTS.md" "$TMP_ROOT/register-agents.valid"
awk '{ if ($0 == "## Beroka AI Governance") print "## Modified Governance"; else print }' "$register_repo/AGENTS.md" >"$TMP_ROOT/register-agents.drifted"
cp "$TMP_ROOT/register-agents.drifted" "$register_repo/AGENTS.md"
git -C "$register_repo" add AGENTS.md
git -C "$register_repo" commit -qm 'test: drift managed agents'
drift_hash=$(git -C "$register_repo" hash-object CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
if drift_output=$($CLI update "$register_repo" --to v1.1.0 2>&1); then fail 'update accepted modified managed content'; fi
assert_contains "$drift_output" 'Result: ENTRYPOINT_DRIFT'
[ "$drift_hash" = "$(git -C "$register_repo" hash-object CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)" ] || fail 'drifted update changed package files'
cp "$TMP_ROOT/register-agents.valid" "$register_repo/AGENTS.md"
git -C "$register_repo" add AGENTS.md
git -C "$register_repo" commit -qm 'test: restore managed agents'

rm -f "$register_repo/.cursor/rules/beroka-governance.mdc"
git -C "$register_repo" add -A
git -C "$register_repo" commit -qm 'test: delete managed cursor rule'
before_deleted_rollback=$(git -C "$register_repo" hash-object .beroka-governance.lock)
if deleted_output=$($CLI rollback "$register_repo" --to v1.0.0 2>&1); then fail 'rollback accepted deleted Cursor rule'; fi
assert_contains "$deleted_output" 'Result: ENTRYPOINT_DRIFT'
[ ! -e "$register_repo/.cursor/rules/beroka-governance.mdc" ] || fail 'deleted Cursor rule was recreated'
[ "$before_deleted_rollback" = "$(git -C "$register_repo" hash-object .beroka-governance.lock)" ] || fail 'deleted-rule rollback changed the lock'
cp "$source_repo/templates/agent-entrypoints/team-dev-ai-workflow.mdc" "$register_repo/.cursor/rules/beroka-governance.mdc"
git -C "$register_repo" add .cursor/rules/beroka-governance.mdc
git -C "$register_repo" commit -qm 'test: restore managed cursor rule'

before_dry_update=$(git -C "$register_repo" hash-object .beroka-governance.lock)
$CLI update "$register_repo" --to v1.1.0 --dry-run >/dev/null
after_dry_update=$(git -C "$register_repo" hash-object .beroka-governance.lock)
[ "$before_dry_update" = "$after_dry_update" ] || fail 'update dry-run changed the lock'

printf 'PASS: repository registration\n'
printf 'PASS: release lifecycle\n'

$CLI update "$register_repo" --to v1.1.0
git -C "$register_repo" add .
git -C "$register_repo" commit -qm 'test: commit v1.1 registration'
awk '{ if ($0 == "## Beroka AI Governance") print "## Manual mutation"; else print }' "$register_repo/AGENTS.md" >"$TMP_ROOT/register-agents.mutated"
cp "$TMP_ROOT/register-agents.mutated" "$register_repo/AGENTS.md"
if $CLI doctor "$register_repo" >/dev/null 2>&1; then fail 'doctor accepted entrypoint drift'; fi
git -C "$register_repo" checkout -- AGENTS.md

if $CLI uninstall >/dev/null 2>&1; then fail 'uninstall accepted a registered repository'; fi

ignored_unregister_repo=$TMP_ROOT/ignored-unregister-consumer
new_repo "$ignored_unregister_repo"
git -C "$ignored_unregister_repo" remote add origin https://github.com/beroka-vn/ignored-unregister-backend.git
printf '.cursor/rules/beroka-governance.mdc\n' >"$ignored_unregister_repo/.gitignore"
git -C "$ignored_unregister_repo" add .gitignore
git -C "$ignored_unregister_repo" commit -qm 'test: ignore Cursor rule'
$CLI register "$ignored_unregister_repo" --version v1.1.0
git -C "$ignored_unregister_repo" add .
git -C "$ignored_unregister_repo" commit -qm 'test: commit non-ignored registration files'
if ignored_unregister_output=$($CLI unregister "$ignored_unregister_repo" 2>&1); then
  fail 'unregister accepted an ignored managed target'
fi
assert_contains "$ignored_unregister_output" 'Result: WORKTREE_CONFLICT'
[ -e "$ignored_unregister_repo/.cursor/rules/beroka-governance.mdc" ] || fail 'failed unregister deleted ignored Cursor rule'
git -C "$ignored_unregister_repo" add -f .cursor/rules/beroka-governance.mdc
git -C "$ignored_unregister_repo" commit -qm 'test: track ignored Cursor rule'
$CLI unregister "$ignored_unregister_repo"

unregister_dry_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock)
$CLI unregister "$register_repo" --dry-run >/dev/null
[ "$unregister_dry_hash" = "$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock)" ] || fail 'unregister dry-run modified files'

$CLI unregister "$register_repo"
[ ! -e "$register_repo/.beroka-governance.lock" ] || fail 'unregister kept the lock'
[ ! -e "$register_repo/.cursor/rules/beroka-governance.mdc" ] || fail 'unregister kept Cursor rule'
assert_contains "$(cat "$register_repo/AGENTS.md")" 'Keep this line.'
assert_contains "$(cat "$register_repo/CLAUDE.md")" 'Keep this Claude line.'

printf '%s\n' '<!-- BEROKA-GOVERNANCE:END -->' '<!-- BEROKA-GOVERNANCE:START -->' >"$release_dir/templates/agent-entrypoints/AGENTS.md"
git -C "$release_dir" add templates/agent-entrypoints/AGENTS.md
git -C "$release_dir" commit -qm 'test: corrupt template marker order'
git -C "$release_dir" tag -d v1.0.0 >/dev/null
git -C "$release_dir" tag -a v1.0.0 -m 'v1.0.0' HEAD
marker_repo=$TMP_ROOT/marker-consumer
new_repo "$marker_repo"
git -C "$marker_repo" remote add origin https://github.com/beroka-vn/marker-backend.git
if $CLI register "$marker_repo" --version v1.0.0 >/dev/null 2>&1; then
  fail 'register accepted end-before-start template markers'
fi
[ ! -e "$marker_repo/.beroka-governance.lock" ] || fail 'malformed template wrote a lock'

$CLI uninstall
[ ! -e "$BEROKA_GOV_BIN_DIR/beroka-governance" ] || fail 'uninstall kept user CLI'
[ ! -e "$XDG_DATA_HOME/beroka-ai-governance" ] || fail 'uninstall kept release data'

$CLI install v1.1.0
force_repo=$TMP_ROOT/force-consumer
new_repo "$force_repo"
git -C "$force_repo" remote add origin https://github.com/beroka-vn/force-backend.git
$CLI register "$force_repo" --version v1.1.0

external_rules=$TMP_ROOT/external-rules
mkdir -p "$external_rules"
cp "$source_repo/templates/agent-entrypoints/team-dev-ai-workflow.mdc" "$external_rules/beroka-governance.mdc"
symlink_repo=$TMP_ROOT/symlink-consumer
new_repo "$symlink_repo"
git -C "$symlink_repo" remote add origin https://github.com/beroka-vn/symlink-backend.git
$CLI register "$symlink_repo" --version v1.1.0
rm -rf "$symlink_repo/.cursor/rules"
ln -s "$external_rules" "$symlink_repo/.cursor/rules"
if symlink_output=$($CLI unregister "$symlink_repo" 2>&1); then fail 'unregister accepted a managed-path symlink'; fi
assert_contains "$symlink_output" 'Result: ENTRYPOINT_DRIFT'
[ -L "$symlink_repo/.cursor/rules" ] || fail 'unregister replaced the managed-path symlink'
[ -f "$external_rules/beroka-governance.mdc" ] || fail 'unregister deleted the external sentinel'

create_repo=$TMP_ROOT/symlink-create-consumer
new_repo "$create_repo"
git -C "$create_repo" remote add origin https://github.com/beroka-vn/symlink-create-backend.git
mkdir -p "$create_repo/.cursor"
ln -s "$external_rules" "$create_repo/.cursor/rules"
if create_output=$($CLI register "$create_repo" --version v1.1.0 2>&1); then fail 'register accepted a managed-path symlink'; fi
assert_contains "$create_output" 'Result: ENTRYPOINT_DRIFT'
[ ! -e "$create_repo/.beroka-governance.lock" ] || fail 'symlinked register wrote a lock'
[ -f "$external_rules/beroka-governance.mdc" ] || fail 'register deleted the external sentinel'

$CLI uninstall --force
[ -e "$force_repo/.beroka-governance.lock" ] || fail 'force uninstall edited application repository'
if $CLI doctor "$force_repo" >/dev/null 2>&1; then fail 'force-uninstalled repository did not fail closed'; fi

printf 'PASS: safe removal and drift detection\n'
