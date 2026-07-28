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
START_MARKER='<!-- BEROKA-GOVERNANCE:START -->'
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$BEROKA_GOV_BIN_DIR"
git config --global advice.detachedHead false

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

new_repo() {
  path=$1
  mkdir -p "$path"
  git -C "$path" init -qb trunk
  git -C "$path" config user.name test-user
  git -C "$path" config user.email test@example.invalid
}

snapshot_repo_complete() {
  src_repo=$1
  {
    git -C "$src_repo" rev-parse HEAD
    git -C "$src_repo" symbolic-ref -q HEAD || printf '%s\n' DETACHED
    git -C "$src_repo" status --porcelain=v1 --untracked-files=all
    git -C "$src_repo" ls-files -s
    git -C "$src_repo" diff --binary
    git -C "$src_repo" diff --cached --binary
    find "$src_repo" -path "$src_repo/.git" -prune -o -type f -print |
      sort |
      while IFS= read -r file; do
        sha256sum "$file"
      done
  }
}

source_repo=$TMP_ROOT/source
new_repo "$source_repo"
mkdir -p "$source_repo/bin" "$source_repo/templates/agent-entrypoints"
printf '%s\n' v1.1.0 >"$source_repo/VERSION"
cp "$CLI" "$source_repo/bin/beroka-governance"
chmod 755 "$source_repo/bin/beroka-governance"
cp -R "$ROOT/runtime" "$source_repo/runtime"
mkdir -p "$source_repo/runtime/repositories/beroka-vn"
cat >"$source_repo/runtime/repositories/beroka-vn/routing-consumer.conf" <<'EOF'
SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only
EOF
for release_file in governance.md handbook.md workflow.md; do
  printf '%s\n' "# $release_file v1.1.0" >"$source_repo/$release_file"
done
for template in ai-agent-assignment github-issue jira-confluence pull-request; do
  printf '%s\n' "# $template v1.1.0" >"$source_repo/templates/$template.md"
done
cp "$ROOT/templates/agent-entrypoints/AGENTS.md" \
  "$source_repo/templates/agent-entrypoints/AGENTS.md"
cp "$ROOT/templates/agent-entrypoints/CLAUDE.md" \
  "$source_repo/templates/agent-entrypoints/CLAUDE.md"
cp "$ROOT/templates/agent-entrypoints/CURSOR-USER-RULE.txt" \
  "$source_repo/templates/agent-entrypoints/CURSOR-USER-RULE.txt"
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'test: create release'
git -C "$source_repo" tag -a v1.1.0 -m v1.1.0
release_commit=$(git -C "$source_repo" rev-parse 'v1.1.0^{commit}')
git config --global url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git

$CLI install v1.1.0 >/dev/null
active_release=$XDG_CONFIG_HOME/beroka-ai-governance/active-release
[ "$(cat "$active_release")" = "$(printf '%s\n%s' \
  'VERSION=v1.1.0' "COMMIT=$release_commit")" ] ||
  fail 'install omitted the verified active release'
mkdir -p "$XDG_CONFIG_HOME/beroka-ai-governance"
printf '%s\n' codex >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"

known_repo=$TMP_ROOT/routing-consumer
new_repo "$known_repo"
printf '%s\n' '# known' >"$known_repo/README.md"
git -C "$known_repo" add README.md
git -C "$known_repo" commit -qm 'test: initialize known repository'
git -C "$known_repo" remote add origin \
  https://github.com/beroka-vn/routing-consumer.git

doctor_output=$($CLI doctor "$known_repo")
assert_contains "$doctor_output" 'Repository: beroka-vn/routing-consumer'
assert_contains "$doctor_output" 'Version: v1.1.0'
assert_contains "$doctor_output" "Commit: $release_commit"
assert_contains "$doctor_output" 'Legacy repository metadata: ABSENT'
assert_contains "$doctor_output" 'Routing: ROUTING_ACTIVE'
assert_contains "$doctor_output" 'Result: PASS'

context_output=$($CLI context "$known_repo")
assert_contains "$context_output" 'Repository: beroka-vn/routing-consumer'
assert_contains "$context_output" 'Version: v1.1.0'
assert_contains "$context_output" "Commit: $release_commit"
assert_contains "$context_output" 'Routing source: central catalog'
assert_contains "$context_output" 'Routing: ROUTING_ACTIVE'

assert_contains "$($CLI show "$known_repo" governance)" '# governance.md v1.1.0'

printf '%s\n' \
  'VERSION=v1.1.0' \
  'COMMIT=0000000000000000000000000000000000000000' >"$active_release"
if output=$($CLI doctor "$known_repo" 2>&1); then
  fail 'doctor accepted a forged active release commit'
fi
assert_contains "$output" 'Result: VERSION_MISMATCH'
printf '%s\n' \
  'VERSION=v1.1.0' \
  "COMMIT=$release_commit" >"$active_release"

unknown_repo=$TMP_ROOT/unknown
new_repo "$unknown_repo"
printf '%s\n' '# unknown' >"$unknown_repo/README.md"
git -C "$unknown_repo" add README.md
git -C "$unknown_repo" commit -qm 'test: initialize unknown repository'
git -C "$unknown_repo" remote add origin \
  https://github.com/beroka-vn/unknown.git
unknown_output=$($CLI context "$unknown_repo")
assert_contains "$unknown_output" 'Routing: ROUTING_REQUIRED'
assert_contains "$unknown_output" 'Profile: standalone'
assert_contains "$unknown_output" 'Cross-repository policy: explicit-only'
assert_contains "$unknown_output" '# General Repository Governance'
assert_contains "$unknown_output" 'External routing-dependent writes: BLOCKED'

for state in clean modified untracked deleted detached behind feature; do
  state_repo=$TMP_ROOT/state-$state
  new_repo "$state_repo"
  printf '%s\n' "$state" >"$state_repo/README.md"
  git -C "$state_repo" add README.md
  git -C "$state_repo" commit -qm "test: initialize $state repository"
  git -C "$state_repo" remote add origin \
    "https://github.com/beroka-vn/state-$state.git"
  case "$state" in
    modified) printf '%s\n' modified >>"$state_repo/README.md" ;;
    untracked) printf '%s\n' untracked >"$state_repo/untracked.txt" ;;
    deleted) rm "$state_repo/README.md" ;;
    detached) git -C "$state_repo" checkout -q --detach ;;
    behind)
      behind_base=$(git -C "$state_repo" rev-parse HEAD)
      printf '%s\n' remote >"$state_repo/remote.txt"
      git -C "$state_repo" add remote.txt
      git -C "$state_repo" commit -qm 'test: remote commit'
      behind_tip=$(git -C "$state_repo" rev-parse HEAD)
      git -C "$state_repo" update-ref refs/remotes/origin/trunk "$behind_tip"
      git -C "$state_repo" reset -q --hard "$behind_base"
      git -C "$state_repo" branch --set-upstream-to origin/trunk trunk \
        >/dev/null 2>&1
      ;;
    feature) git -C "$state_repo" switch -qc feature ;;
  esac

  before=$(snapshot_repo_complete "$state_repo")
  $CLI doctor "$state_repo" >/dev/null
  $CLI context "$state_repo" >/dev/null
  [ "$before" = "$(snapshot_repo_complete "$state_repo")" ] ||
    fail "governed read changed the $state repository"
done

legacy_repo=$TMP_ROOT/legacy
new_repo "$legacy_repo"
printf '%s\n' '# legacy' >"$legacy_repo/README.md"
git -C "$legacy_repo" add README.md
git -C "$legacy_repo" commit -qm 'test: initialize legacy repository'
git -C "$legacy_repo" remote add origin \
  https://github.com/beroka-vn/legacy.git
mkdir -p "$legacy_repo/.cursor/rules"
printf '%s\n' \
  'SOURCE=obsolete/example' \
  'VERSION=v999.999.999' \
  'COMMIT=not-a-commit' >"$legacy_repo/.beroka-governance.lock"
printf '%s\n' \
  'personal agent text' \
  '<!-- BEROKA-GOVERNANCE:START -->' \
  'obsolete managed text' \
  '<!-- BEROKA-GOVERNANCE:END -->' >"$legacy_repo/AGENTS.md"
printf '%s\n' arbitrary >"$legacy_repo/CLAUDE.md"
printf '%s\n' arbitrary >"$legacy_repo/.cursor/rules/beroka-governance.mdc"

legacy_doctor=$($CLI doctor "$legacy_repo")
assert_contains "$legacy_doctor" \
  'Legacy repository metadata: PRESENT_IGNORED'
assert_not_contains "$legacy_doctor" 'VERSION_MISMATCH'

for command in register update rollback unregister; do
  before=$(snapshot_repo_complete "$legacy_repo")
  if output=$($CLI "$command" "$legacy_repo" 2>&1); then
    fail "$command remained active"
  fi
  assert_contains "$output" 'Result: COMMAND_RETIRED'
  [ "$before" = "$(snapshot_repo_complete "$legacy_repo")" ] ||
    fail "$command changed the repository"
done
for command in register update rollback unregister; do
  if output=$($CLI "$command" "$TMP_ROOT/does-not-exist" 2>&1); then
    fail "$command inspected a repository"
  fi
  assert_contains "$output" 'Result: COMMAND_RETIRED'
done

fake_bin=$TMP_ROOT/fake-bin
mkdir -p "$fake_bin"
cat >"$fake_bin/codex" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$fake_bin/gh" <<'EOF'
#!/bin/sh
case "$*" in
  'auth status --help'|'auth login --help'|'auth status --hostname github.com')
    exit 0
    ;;
esac
exit 1
EOF
chmod 755 "$fake_bin/codex" "$fake_bin/gh"

for preflight_repo in "$known_repo" "$unknown_repo"; do
  before=$(snapshot_repo_complete "$preflight_repo")
  PATH=$fake_bin:$PATH $CLI preflight "$preflight_repo" \
    --client codex --operation github-write --non-interactive >/dev/null
  [ "$before" = "$(snapshot_repo_complete "$preflight_repo")" ] ||
    fail 'GitHub preflight changed the repository'
done
for state in clean modified untracked deleted detached behind feature; do
  state_repo=$TMP_ROOT/state-$state
  before=$(snapshot_repo_complete "$state_repo")
  PATH=$fake_bin:$PATH $CLI preflight "$state_repo" \
    --client codex --operation github-write --non-interactive >/dev/null
  [ "$before" = "$(snapshot_repo_complete "$state_repo")" ] ||
    fail "GitHub preflight changed the $state repository"
done

before=$(snapshot_repo_complete "$known_repo")
PATH=$fake_bin:$PATH \
  $CLI setup-connectors --client codex --non-interactive >/dev/null 2>&1 || :
[ "$before" = "$(snapshot_repo_complete "$known_repo")" ] ||
  fail 'connector setup changed the repository'

printf '%s\n' claude >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"
if output=$(PATH=$fake_bin:$PATH $CLI doctor "$known_repo" \
  --client codex 2>&1)
then
  fail 'doctor accepted a client without user instructions'
fi
assert_contains "$output" 'Result: CLIENT_INSTRUCTION_REQUIRED'
assert_contains "$output" \
  'Remediation: beroka-governance bootstrap --client codex'
printf '%s\n' codex >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"

if output=$(PATH=$fake_bin:$PATH $CLI preflight "$unknown_repo" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'unknown repository passed routing-dependent preflight'
fi
assert_contains "$output" 'Result: ROUTING_REQUIRED'
assert_not_contains "$output" 'CONNECTOR_MISSING'

mkdir -p "$HOME/.codex" "$HOME/.claude"
{
  printf '%s\n' 'personal Codex text'
  cat "$source_repo/templates/agent-entrypoints/AGENTS.md"
} >"$HOME/.codex/AGENTS.md"
{
  printf '%s\n' 'personal Claude text'
  cat "$source_repo/templates/agent-entrypoints/CLAUDE.md"
} >"$HOME/.claude/CLAUDE.md"
printf '%s\n' acknowledged \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"
printf '%s\n' preserve \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/personal-sentinel"
before=$(snapshot_repo_complete "$legacy_repo")
$CLI uninstall --force >/dev/null
[ "$before" = "$(snapshot_repo_complete "$legacy_repo")" ] ||
  fail 'uninstall changed the application repository'
assert_contains "$(cat "$HOME/.codex/AGENTS.md")" 'personal Codex text'
assert_contains "$(cat "$HOME/.claude/CLAUDE.md")" 'personal Claude text'
assert_not_contains "$(cat "$HOME/.codex/AGENTS.md")" "$START_MARKER"
assert_not_contains "$(cat "$HOME/.claude/CLAUDE.md")" "$START_MARKER"
[ -f "$XDG_CONFIG_HOME/beroka-ai-governance/personal-sentinel" ] ||
  fail 'uninstall removed unrelated user configuration'
[ ! -e "$XDG_CONFIG_HOME/beroka-ai-governance/active-release" ] ||
  fail 'uninstall kept active release state'
[ ! -e "$XDG_CONFIG_HOME/beroka-ai-governance/clients" ] ||
  fail 'uninstall kept client enrollment'
[ ! -e "$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256" ] ||
  fail 'uninstall kept Cursor acknowledgement'
[ ! -e "$XDG_DATA_HOME/beroka-ai-governance" ] ||
  fail 'uninstall kept release data'
[ ! -e "$BEROKA_GOV_BIN_DIR/beroka-governance" ] ||
  fail 'uninstall kept user CLI'

printf '%s\n' 'PASS: user-scoped governance commands'
