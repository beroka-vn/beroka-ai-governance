#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLI=$ROOT/bin/beroka-governance
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-routing-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export HOME=$TEST_ROOT/home
export XDG_CONFIG_HOME=$TEST_ROOT/config
export XDG_DATA_HOME=$TEST_ROOT/data
export BEROKA_GOV_BIN_DIR=$TEST_ROOT/bin
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$BEROKA_GOV_BIN_DIR"

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

new_repo() {
  nr_path=$1
  mkdir -p "$nr_path"
  git -C "$nr_path" init -q
  git -C "$nr_path" config user.name test-user
  git -C "$nr_path" config user.email test@example.invalid
}

snapshot_repo() {
  sr_repo=$1
  {
    git -C "$sr_repo" for-each-ref --format='%(refname) %(objectname)'
    git -C "$sr_repo" count-objects -v
    git -C "$sr_repo" config --local --list
    git -C "$sr_repo" status --porcelain=v1 --untracked-files=all
    git -C "$sr_repo" ls-files -s
  }
}

remote_work=$TEST_ROOT/remote-work
remote_bare=$TEST_ROOT/remote.git
new_repo "$remote_work"
git -C "$remote_work" switch -qc trunk
printf '%s\n' '# application' >"$remote_work/README.md"
git -C "$remote_work" add README.md
git -C "$remote_work" commit -qm 'test: initialize application'
git clone -q --bare "$remote_work" "$remote_bare"
git -C "$remote_bare" symbolic-ref HEAD refs/heads/trunk
git -C "$remote_work" remote add origin "$remote_bare"

git config --global \
  url."file://$remote_bare".insteadOf \
  https://github.com/beroka-vn/routing-consumer.git

source_repo=$TEST_ROOT/governance-source
new_repo "$source_repo"
mkdir -p "$source_repo/bin" "$source_repo/templates"
cp "$ROOT/VERSION" "$source_repo/VERSION"
cp "$CLI" "$source_repo/bin/beroka-governance"
chmod 755 "$source_repo/bin/beroka-governance"
cp -R "$ROOT/runtime" "$source_repo/runtime"
mkdir -p "$source_repo/runtime/integrations"
printf 'beroka-vn/routing-consumer\tbackend\n' \
  >>"$source_repo/runtime/integrations/beroka-be-fe.repositories"
cp "$ROOT/governance.md" "$ROOT/handbook.md" "$ROOT/workflow.md" "$source_repo/"
cp -R "$ROOT/templates/." "$source_repo/templates/"
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'test: create governance release'
git -C "$source_repo" tag -a v1.0.0 -m v1.0.0

git config --global \
  url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git
release_dir=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.0.0
mkdir -p "$(dirname -- "$release_dir")"
git clone -q --depth 1 --branch v1.0.0 \
  https://github.com/beroka-vn/beroka-ai-governance.git "$release_dir"

consumer=$TEST_ROOT/consumer
new_repo "$consumer"
git -C "$consumer" remote add upstream \
  https://github.com/beroka-vn/routing-consumer.git
git -C "$consumer" fetch -q upstream trunk
git -C "$consumer" switch -qc trunk FETCH_HEAD
$CLI register "$consumer" --version v1.0.0
git -C "$consumer" add .
git -C "$consumer" commit -qm 'test: register governance'
cp "$consumer/.beroka-governance.lock" "$remote_work/.beroka-governance.lock"
cp "$consumer/AGENTS.md" "$consumer/CLAUDE.md" "$remote_work/"
mkdir -p "$remote_work/.cursor/rules"
cp "$consumer/.cursor/rules/beroka-governance.mdc" \
  "$remote_work/.cursor/rules/beroka-governance.mdc"
git -C "$remote_work" add .beroka-governance.lock AGENTS.md CLAUDE.md \
  .cursor/rules/beroka-governance.mdc
git -C "$remote_work" commit -qm 'test: register application'
git -C "$remote_work" push -q origin trunk

before=$(snapshot_repo "$consumer")
output=$($CLI context "$consumer")
after=$(snapshot_repo "$consumer")

[ "$before" = "$after" ] ||
  fail 'context changed application repository state'
assert_contains "$output" 'Routing: ROUTING_REQUIRED'

publish_routing() {
  pr_content=$1
  printf '%s\n' "$pr_content" >"$remote_work/.beroka-governance.conf"
  git -C "$remote_work" add .beroka-governance.conf
  git -C "$remote_work" commit -qm 'test: publish routing'
  git -C "$remote_work" push -q "file://$remote_bare" trunk
  git -C "$consumer" fetch -q "file://$remote_bare" trunk
  git -C "$consumer" reset -q --hard FETCH_HEAD
}

printf '%s\n' \
  'SCHEMA_VERSION=1' \
  'PROFILE=standalone' \
  'JIRA_PROJECT_KEY=APP' \
  'CONFLUENCE_SPACE_KEY=APP' \
  'CONFLUENCE_ROOT_CONTENT_ID=123456' \
  'CONFLUENCE_ROOT_CONTENT_TYPE=page' \
  'INTEGRATION_PROFILE=none' \
  'CROSS_REPO_POLICY=explicit-only' \
  >"$consumer/.beroka-governance.conf"

output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_CHANGE_PENDING'

git -C "$consumer" add .beroka-governance.conf
git -C "$consumer" commit -qm 'test: commit local routing'
cp "$consumer/.beroka-governance.conf" "$remote_work/.beroka-governance.conf"
git -C "$remote_work" add .beroka-governance.conf
git -C "$remote_work" commit -qm 'test: add routing'
git -C "$remote_work" push -q origin trunk

output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_ACTIVE'
assert_contains "$output" 'Profile: standalone'
assert_contains "$output" 'Dependency state: NO_DEPENDENCY_DECLARED'
assert_contains "$output" '# Standalone Repository'
case "$output" in
  *'# Backend–Frontend Integration'*) fail 'standalone loaded BE-FE integration' ;;
esac

printf '%s\n' 'PROFILE=working-tree' >"$consumer/.beroka-governance.conf"
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_CHANGE_PENDING'
git -C "$consumer" checkout -- .beroka-governance.conf

printf '%s\n' 'PROFILE=index' >"$consumer/.beroka-governance.conf"
git -C "$consumer" add .beroka-governance.conf
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_CHANGE_PENDING'
git -C "$consumer" reset -q HEAD -- .beroka-governance.conf
git -C "$consumer" checkout -- .beroka-governance.conf

git -C "$consumer" switch -qc routing-task
printf '%s\n' 'PROFILE=task-branch' >"$consumer/.beroka-governance.conf"
git -C "$consumer" add .beroka-governance.conf
git -C "$consumer" commit -qm 'test: change routing on task branch'
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_CHANGE_PENDING'

mv "$remote_bare" "$TEST_ROOT/remote.offline"
doctor_output=$($CLI doctor "$consumer")
assert_contains "$doctor_output" 'Result: PASS'
context_output=$($CLI context "$consumer")
assert_contains "$context_output" 'Routing: ROUTING_VERIFICATION_REQUIRED'
assert_contains "$context_output" 'External routing-dependent writes: BLOCKED'
mv "$TEST_ROOT/remote.offline" "$remote_bare"

backend_config='SCHEMA_VERSION=1
PROFILE=backend
JIRA_PROJECT_KEY=APP
JIRA_BOARD_ID=12
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=beroka-be-fe
CROSS_REPO_POLICY=explicit-only'
publish_routing "$backend_config"
output=$($CLI context "$consumer")
assert_contains "$output" 'Profile: backend'
assert_contains "$output" 'Cross-repository policy: explicit-only'
assert_contains "$output" '# Backend–Frontend Integration'

invalid_config='SCHEMA_VERSION=1
PROFILE=standalone
PROFILE=backend
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
publish_routing "$invalid_config"
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_INVALID'

unknown_key_config='SCHEMA_VERSION=1
PROFILE=standalone
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only
UNKNOWN=value'
publish_routing "$unknown_key_config"
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_INVALID'

unsupported_schema_config='SCHEMA_VERSION=2
PROFILE=standalone
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
publish_routing "$unsupported_schema_config"
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_INVALID'

invalid_board_config='SCHEMA_VERSION=1
PROFILE=standalone
JIRA_BOARD_ID=0
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
publish_routing "$invalid_board_config"
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_INVALID'

standalone_integration_config='SCHEMA_VERSION=1
PROFILE=standalone
INTEGRATION_PROFILE=beroka-be-fe
CROSS_REPO_POLICY=profile-controlled'
publish_routing "$standalone_integration_config"
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_INVALID'

profile_controlled_none_config='SCHEMA_VERSION=1
PROFILE=backend
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=profile-controlled'
publish_routing "$profile_controlled_none_config"
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_INVALID'

rm -f "$remote_work/.beroka-governance.conf"
ln -s README.md "$remote_work/.beroka-governance.conf"
git -C "$remote_work" add .beroka-governance.conf
git -C "$remote_work" commit -qm 'test: publish symlinked routing'
git -C "$remote_work" push -q "file://$remote_bare" trunk
git -C "$consumer" fetch -q "file://$remote_bare" trunk
git -C "$consumer" reset -q --hard FETCH_HEAD
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_INVALID'

printf '%s\n' 'PASS: routing state'
