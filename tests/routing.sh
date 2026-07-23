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
FAKE_BIN=$TEST_ROOT/fake-bin
CALLS=$TEST_ROOT/calls
export CALLS
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" \
  "$BEROKA_GOV_BIN_DIR" "$FAKE_BIN"
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

FIX_WAVE_FAILURES=0

fix_wave_fail() {
  printf 'RED: %s\n' "$*" >&2
  FIX_WAVE_FAILURES=$((FIX_WAVE_FAILURES + 1))
}

fix_wave_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fix_wave_fail "expected [$2] in [$1]" ;;
  esac
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
  '--version') printf '%s\n' 'codex 1.0.0' ;;
  'mcp login --help'|'app-server --help') ;;
  'mcp get atlassian --json')
    [ -f "$XDG_CONFIG_HOME/fake-codex-configured" ] || exit 1
    printf '%s\n' '{"name":"atlassian","url":"https://mcp.atlassian.com/v1/mcp/authv2"}'
    ;;
  'mcp login atlassian')
    printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"
    ;;
  'app-server --stdio')
    input=$(cat)
    case "$input" in
      *'mcpServerStatus/list'*)
        health=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-health" 2>/dev/null || :)
        case "$health" in
          healthy-all)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-read-only)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"getJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-cross-server)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"getJiraIssue":{}},"authStatus":"oAuth"}, {"name":"other","tools":{"createJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-similar-tool)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssuePreview":{},"getJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-metadata-tool)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"getJiraIssue":{}},"metadata":{"createJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-nested-tool-metadata)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"metadata":{"createJiraIssue":{},"getJiraIssue":{}}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-nested-metadata)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"other","metadata":{"name":"atlassian","tools":{"metadata":{"createJiraIssue":{},"getJiraIssue":{}}},"authStatus":"oAuth"}}]}}'
            ;;
          healthy-wrong-id)
            printf '%s\n' \
              '{"id":0,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{}},"authStatus":"oAuth"}]}}' \
              '{"id":1,"result":{"data":[{"name":"other","tools":{},"authStatus":"oAuth"}]}}'
            ;;
          healthy-duplicate-id)
            printf '%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{}},"authStatus":"oAuth"}]}}' \
              '{"id":1,"result":{"data":[{"name":"other","tools":{},"authStatus":"oAuth"}]}}'
            ;;
          healthy-string-id)
            printf '%s\n' '{"id":"1","result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-array-wrapped)
            printf '%s\n' '[{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{}},"authStatus":"oAuth"}]}}]'
            ;;
          healthy-duplicate-data)
            printf '%s\n' '{"id":1,"result":{"data":[],"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-unrelated-reauth)
            printf '%s\n' \
              '{"method":"mcpServer/startupStatus/updated","params":{"name":"other","metadata":{"name":"atlassian","failureReason":"reauthenticationRequired"}}}' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          auth-required|'')
            printf '%s\n' \
              '{"method":"mcpServer/startupStatus/updated","params":{"name":"atlassian","failureReason":"reauthenticationRequired"}}' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{},"authStatus":"oAuth"}]}}'
            ;;
          auth-401) printf '%s\n' 'server atlassian: 401 Unauthorized' ;;
          auth-403) printf '%s\n' 'server atlassian: 403 Forbidden' ;;
          *) exit 1 ;;
        esac
        ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$FAKE_BIN/claude" <<'EOF'
#!/bin/sh
set -eu
printf 'claude %s\n' "$*" >>"$CALLS"
case "$*" in
  '--version') printf '%s\n' '1.2.3 (Claude Code)' ;;
  'mcp add --help'|'mcp get --help'|'mcp list --help') ;;
  'mcp get atlassian')
    [ -f "$XDG_CONFIG_HOME/fake-claude-configured" ] || exit 1
    printf '%s\n' \
      'Name: atlassian' \
      'URL: https://mcp.atlassian.com/v1/mcp/authv2'
    ;;
  '')
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
    ;;
  'mcp list')
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-claude-health" 2>/dev/null || :)" in
      healthy)
        printf '%s\n' \
          'github: https://example.invalid/mcp (HTTP) - ✓ Connected' \
          'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - ✓ Connected'
        ;;
      auth-needs-realistic)
        printf '%s\n' \
          'atlassian-helper: https://example.invalid/mcp (HTTP) - ✓ Connected' \
          'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - ! Needs authentication'
        ;;
      auth-required-multiserver)
        printf '%s\n' \
          'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - Authentication required' \
          'github: https://example.invalid/mcp (HTTP) - ✓ Connected'
        ;;
      auth-required-helper)
        printf '%s\n' \
          'atlassian-helper: https://example.invalid/mcp (HTTP) - ✓ Connected' \
          'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - ! Needs authentication'
        ;;
      not-connected)
        printf '%s\n' 'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - ✗ Not connected'
        ;;
      disconnected)
        printf '%s\n' 'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - Disconnected'
        ;;
      auth-required|'')
        printf '%s\n' 'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - ! Needs authentication'
        ;;
      *)
        printf '%s\n' 'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - Failed'
        ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$FAKE_BIN/cursor-agent" <<'EOF'
#!/bin/sh
set -eu
printf 'cursor-agent %s\n' "$*" >>"$CALLS"
case "$*" in
  '--version') printf '%s\n' 'cursor-agent 1.0.0' ;;
  'mcp login --help') ;;
  'mcp login atlassian')
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
    ;;
  'mcp list')
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-cursor-health" 2>/dev/null || :)" in
      healthy) printf '%s\n' 'atlassian: Ready' ;;
      auth-required|'') printf '%s\n' 'atlassian: Authentication required' ;;
      *) printf '%s\n' 'atlassian: Failed' ;;
    esac
    ;;
  'mcp list-tools atlassian')
    [ "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-cursor-health" 2>/dev/null || :)" = healthy ] ||
      exit 1
    printf '%s\n' 'createJiraIssue getJiraIssue'
    ;;
  *) exit 1 ;;
esac
EOF
chmod 755 "$FAKE_BIN/sleep" "$FAKE_BIN/codex" "$FAKE_BIN/claude" \
  "$FAKE_BIN/cursor-agent"
: >"$CALLS"

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
printf '%s\n' v1.1.0 >"$source_repo/VERSION"
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
git -C "$source_repo" tag -a v1.1.0 -m v1.1.0

git config --global \
  url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git
release_dir=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.1.0
mkdir -p "$(dirname -- "$release_dir")"
git clone -q --depth 1 --branch v1.1.0 \
  https://github.com/beroka-vn/beroka-ai-governance.git "$release_dir"

consumer=$TEST_ROOT/consumer
new_repo "$consumer"
git -C "$consumer" remote add upstream \
  https://github.com/beroka-vn/routing-consumer.git
git -C "$consumer" fetch -q upstream trunk
git -C "$consumer" switch -qc trunk FETCH_HEAD
$CLI register "$consumer" --version v1.1.0
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

pin_test_release() {
  ptr_version=$1
  printf '%s\n' "$ptr_version" >"$source_repo/VERSION"
  git -C "$source_repo" add VERSION runtime/compatibility/atlassian.tsv
  git -C "$source_repo" commit -qm "test: create $ptr_version release"
  git -C "$source_repo" tag -a "$ptr_version" -m "$ptr_version"
  ptr_release=$XDG_DATA_HOME/beroka-ai-governance/releases/$ptr_version
  git clone -q --depth 1 --branch "$ptr_version" \
    https://github.com/beroka-vn/beroka-ai-governance.git "$ptr_release"
  ptr_commit=$(git -C "$ptr_release" rev-parse HEAD)
  sed -i \
    "s/^VERSION=.*/VERSION=$ptr_version/;s/^COMMIT=.*/COMMIT=$ptr_commit/" \
    "$consumer/.beroka-governance.lock"
  git -C "$consumer" add .beroka-governance.lock
  git -C "$consumer" commit -qm "test: pin $ptr_version release"
}

printf '%s\n' \
  'SCHEMA_VERSION=1' \
  'PROFILE=standalone' \
  'JIRA_PROJECT_KEY=APP' \
  'JIRA_BOARD_ID=12' \
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

: >"$XDG_CONFIG_HOME/fake-codex-configured"
printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fix_wave_fail 'empty Codex tool schemas supplied semantic capability'
else
  fix_wave_contains "$output" 'Capability state: UNKNOWN'
  fix_wave_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
fi

mkdir -p "$HOME/.cursor"
printf '%s\n' \
  '{"mcpServers":{"atlassian":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}}}' \
  >"$HOME/.cursor/mcp.json"
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
if output=$($CLI preflight "$consumer" \
  --client cursor --operation jira-write --non-interactive 2>&1)
then
  fix_wave_fail 'Cursor free-text tool names supplied semantic capability'
else
  fix_wave_contains "$output" 'Capability state: UNKNOWN'
  fix_wave_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
fi

printf '%s\n' \
  'codex	1.0.0	https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,createJiraIssue,getConfluencePage,getJiraIssue	2026-07-23	jira-issue-write	SUPPORTED' \
  'codex	1.0.0	https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,createJiraIssue,getConfluencePage,getJiraIssue	2026-07-23	confluence-page-parent-write	SUPPORTED' \
  'codex	1.0.0	https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getJiraIssue	2026-07-23	jira-issue-write	SUPPORTED' \
  'cursor	1.0.0	https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getJiraIssue	2026-07-23	jira-issue-write	SUPPORTED' \
  >>"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.1

: >"$CALLS"
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Jira project: APP'
assert_contains "$output" 'Capability: jira-issue-write'
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Result: PASS'
assert_not_contains "$output" 'createJiraIssue'
[ "$(grep -Fc 'codex app-server --stdio' "$CALLS")" -eq 1 ] ||
  fail 'preflight repeated its selected-client inventory probe'

printf '%s\n' healthy-unrelated-reauth \
  >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Result: PASS'

printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI preflight "$consumer" \
  --client codex --operation confluence-write --non-interactive)
assert_contains "$output" 'Confluence root type: page'
assert_contains "$output" 'Capability: confluence-page-parent-write'
assert_contains "$output" 'Capability state: SUPPORTED'

printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
output=$($CLI preflight "$consumer" \
  --client cursor --operation jira-write --non-interactive)
assert_contains "$output" 'Client: cursor'
assert_contains "$output" 'Capability state: SUPPORTED'

if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-board-verify --non-interactive 2>&1)
then
  fail 'board verification passed without board capability evidence'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

if output=$($CLI preflight "$consumer" \
  --client codex --operation invalid --non-interactive 2>&1)
then
  fail 'preflight accepted an unknown operation'
fi
assert_contains "$output" 'Usage:'

printf '%s\n' healthy-read-only >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'jira write passed without create capability'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

printf '%s\n' healthy-cross-server >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'another server supplied the missing Atlassian capability'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'

printf '%s\n' healthy-similar-tool >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'similarly named tool satisfied the Jira write capability'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'

printf '%s\n' healthy-metadata-tool >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'metadata outside the tools object satisfied Jira write'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'

printf '%s\n' healthy-nested-tool-metadata \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'nested tool metadata satisfied Jira write'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'

printf '%s\n' healthy-nested-metadata >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'nested server and tool metadata satisfied Jira write'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
assert_not_contains "$output" 'Capability state: SUPPORTED'

for invalid_response in \
  healthy-duplicate-data healthy-array-wrapped \
  healthy-wrong-id healthy-duplicate-id healthy-string-id
do
  printf '%s\n' "$invalid_response" >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fail "$invalid_response supplied the Atlassian inventory"
  fi
  assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
  assert_not_contains "$output" 'Capability state: SUPPORTED'
done

: >"$XDG_CONFIG_HOME/fake-claude-configured"
printf '%s\n' auth-required-multiserver \
  >"$XDG_CONFIG_HOME/fake-claude-health"
if output=$($CLI preflight "$consumer" \
  --client claude --operation jira-write --non-interactive 2>&1)
then
  fail 'another server masked required Atlassian authentication'
fi
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'

printf '%s\n' auth-required-helper >"$XDG_CONFIG_HOME/fake-claude-health"
if output=$($CLI preflight "$consumer" \
  --client claude --operation jira-write --non-interactive 2>&1)
then
  fail 'an atlassian-helper status masked Atlassian authentication'
fi
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'

for negative_health in not-connected disconnected; do
  printf '%s\n' "$negative_health" >"$XDG_CONFIG_HOME/fake-claude-health"
  if output=$($CLI preflight "$consumer" \
    --client claude --operation jira-write --non-interactive 2>&1)
  then
    fail "Claude $negative_health status passed"
  fi
  assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
done

if output=$($CLI preflight "$consumer" --client codex \
  --operation jira-write --api-token should-not-appear 2>&1)
then
  fail 'preflight accepted a developer API token'
fi
assert_not_contains "$output" 'should-not-appear'

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'non-interactive preflight invoked OAuth'
fi
assert_contains "$output" 'Remediation: codex mcp login atlassian'
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'

for codex_auth_error in auth-401 auth-403; do
  printf '%s\n' "$codex_auth_error" >"$XDG_CONFIG_HOME/fake-codex-health"
  : >"$CALLS"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fail "$codex_auth_error passed preflight"
  fi
  assert_contains "$output" 'Remediation: codex mcp login atlassian'
  assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'
done

: >"$CALLS"
if output=$(printf 'n\n' | script -qec \
  "$CLI preflight $consumer --client codex --operation jira-write" \
  /dev/null 2>&1)
then
  fail 'preflight accepted declined OAuth'
fi
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'

: >"$CALLS"
output=$(printf 'y\n' | script -qec \
  "$CLI preflight $consumer --client codex --operation jira-write" \
  /dev/null 2>&1)
assert_contains "$output" 'Result: PASS'
assert_contains "$(cat "$CALLS")" 'codex mcp login atlassian'
assert_not_contains "$(cat "$CALLS")" 'claude mcp login atlassian'
assert_not_contains "$(cat "$CALLS")" 'cursor-agent mcp login atlassian'

: >"$CALLS"
output=$($CLI doctor "$consumer" --client codex)
assert_contains "$output" 'Connector: PASS'
assert_contains "$output" 'Authentication: PASS'
assert_contains "$output" 'Result: PASS'
$CLI context "$consumer" >/dev/null
assert_not_contains "$(cat "$CALLS")" 'mcp login atlassian'

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

git -C "$consumer" update-index --skip-worktree .beroka-governance.conf
printf '%s\n' 'PROFILE=hidden-by-skip-worktree' \
  >"$consumer/.beroka-governance.conf"
skip_status=0
skip_output=$($CLI context "$consumer") || skip_status=$?
git -C "$consumer" update-index --no-skip-worktree .beroka-governance.conf
git -C "$consumer" checkout -- .beroka-governance.conf
[ "$skip_status" -eq 0 ] ||
  fix_wave_fail 'context failed while checking skip-worktree bytes'
fix_wave_contains "$skip_output" 'Routing: ROUTING_CHANGE_PENDING'

git -C "$consumer" update-index --assume-unchanged .beroka-governance.conf
printf '%s\n' 'PROFILE=hidden-by-assume-unchanged' \
  >"$consumer/.beroka-governance.conf"
assume_status=0
assume_output=$($CLI context "$consumer") || assume_status=$?
git -C "$consumer" update-index --no-assume-unchanged .beroka-governance.conf
git -C "$consumer" checkout -- .beroka-governance.conf
[ "$assume_status" -eq 0 ] ||
  fix_wave_fail 'context failed while checking assume-unchanged bytes'
fix_wave_contains "$assume_output" 'Routing: ROUTING_CHANGE_PENDING'

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

profile_controlled_config='SCHEMA_VERSION=1
PROFILE=backend
JIRA_PROJECT_KEY=APP
JIRA_BOARD_ID=12
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=beroka-be-fe
CROSS_REPO_POLICY=profile-controlled'
publish_routing "$profile_controlled_config"
printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
if output=$($CLI preflight "$consumer" \
  --client codex --operation cross-repo-write --non-interactive 2>&1)
then
  fix_wave_fail 'profile-controlled cross-repo write passed without exact mapping'
else
  fix_wave_contains "$output" 'Result: ROUTING_REQUIRED'
  fix_wave_contains "$output" \
    'Centrally reviewed exact counterpart and workflow mapping are required'
fi
[ ! -s "$CALLS" ] ||
  fix_wave_fail 'cross-repo routing failure inspected a client'

: >"$CALLS"
publish_routing 'SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
if output=$($CLI preflight "$consumer" \
  --client codex --operation cross-repo-write --non-interactive 2>&1)
then
  fail 'cross-repo write passed standalone routing'
fi
assert_contains "$output" 'Result: ROUTING_REQUIRED'
[ ! -s "$CALLS" ] || fail 'standalone cross-repo routing inspected a client'

: >"$CALLS"
publish_routing 'SCHEMA_VERSION=1
PROFILE=standalone
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'jira write passed without project routing'
fi
assert_contains "$output" 'Result: ROUTING_REQUIRED'
[ ! -s "$CALLS" ] || fail 'routing failure inspected a client'

folder_config='SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=folder
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
publish_routing "$folder_config"
printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation confluence-write --non-interactive 2>&1)
then
  fail 'folder write fell back to page capability'
fi
assert_contains "$output" 'Capability: confluence-folder-parent-write'
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

: >"$XDG_CONFIG_HOME/fake-claude-configured"
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
if output=$($CLI preflight "$consumer" \
  --client claude --operation confluence-write --non-interactive 2>&1)
then
  fail 'folder write passed without compatibility evidence'
fi
assert_contains "$output" 'Capability state: UNKNOWN'

printf '%s\n' \
  'claude	1.2.3	https://mcp.atlassian.com/v1/mcp/authv2	UNAVAILABLE	2026-07-23	confluence-folder-parent-write	SUPPORTED' \
  'codex	1.0.0	https://mcp.atlassian.com/v1/mcp/authv2	getJiraIssue	2026-07-23	jira-issue-write	SUPPORTED' \
  >>"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.2
output=$($CLI preflight "$consumer" \
  --client claude --operation confluence-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Result: PASS'

if output=$($CLI preflight "$consumer" \
  --client claude --operation confluence-write --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Capability state: SUPPORTED'
else
  fix_wave_fail 'Claude Code parenthesized version did not match compatibility evidence'
fi

printf '%s\n' healthy-read-only >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'compatibility evidence overrode complete runtime inventory'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'

printf '%s\n' \
  'claude	1.2.3	https://mcp.atlassian.com/v1/mcp/authv2	UNAVAILABLE	2026-07-23	confluence-folder-parent-write	SUPPORTED' \
  >>"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.3
if output=$($CLI preflight "$consumer" \
  --client claude --operation confluence-write --non-interactive 2>&1)
then
  fail 'duplicate compatibility evidence passed'
fi
assert_contains "$output" 'Capability state: UNKNOWN'

sed -i '$d' "$source_repo/runtime/compatibility/atlassian.tsv"
printf '%s\n' malformed >>"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.4
if output=$($CLI preflight "$consumer" \
  --client claude --operation confluence-write --non-interactive 2>&1)
then
  fail 'malformed compatibility evidence passed'
fi
assert_contains "$output" 'Capability state: UNKNOWN'

sed -i '1s/schema=1/schema=2/; /malformed/d' \
  "$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.5
if output=$($CLI preflight "$consumer" \
  --client claude --operation confluence-write --non-interactive 2>&1)
then
  fail 'unsupported compatibility schema passed'
fi
assert_contains "$output" 'Result: VERSION_MISMATCH'

sed -i '1d' "$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.6
if output=$($CLI preflight "$consumer" \
  --client claude --operation confluence-write --non-interactive 2>&1)
then
  fail 'missing compatibility schema passed'
fi
assert_contains "$output" 'Result: VERSION_MISMATCH'

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

grep -F 'beroka-governance preflight' "$ROOT/README.md" >/dev/null ||
  fail 'README does not document preflight'
grep -F 'ROUTING_CHANGE_PENDING' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document pending routing'
grep -F 'central governance onboarding project' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document bootstrap issue provenance'
grep -F 'CONNECTOR_CAPABILITY_REQUIRED' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document capability remediation'
grep -F '`INTEGRATION_PROFILE=none` không trigger BE–FE hoặc cross-repository' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document standalone preflight scope'
grep -F 'Read access chỉ cần cho selected profile, requested operation và selected integration profile' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not scope team permissions'
grep -F 'BE–FE targets chỉ áp dụng khi reviewed beroka-be-fe integration profile được chọn và operation yêu cầu' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not scope required reads'

[ "$(sed -n '1p' "$ROOT/VERSION")" = v1.1.0 ] ||
  fix_wave_fail 'root VERSION does not select v1.1.0'
grep -F 'release=v1.1.0' "$ROOT/README.md" >/dev/null ||
  fix_wave_fail 'README does not select v1.1.0'
grep -F 'release=v1.1.0' "$ROOT/handbook.md" >/dev/null ||
  fix_wave_fail 'handbook does not select v1.1.0'
[ "$(git -C "$ROOT" rev-parse refs/tags/v1.0.0 2>/dev/null)" = \
  1f2db6bd75cf9d9a68d501c351fb2455448e04e1 ] ||
  fix_wave_fail 'real v1.0.0 tag object changed'

[ "$FIX_WAVE_FAILURES" -eq 0 ] ||
  fail "$FIX_WAVE_FAILURES fix-wave regressions remain"
