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

before=$(snapshot_repo "$consumer")
output=$($CLI context "$consumer")
after=$(snapshot_repo "$consumer")

[ "$before" = "$after" ] ||
  fail 'context changed application repository state'
assert_contains "$output" 'Routing: ROUTING_REQUIRED'

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

printf '%s\n' 'PASS: routing state'
