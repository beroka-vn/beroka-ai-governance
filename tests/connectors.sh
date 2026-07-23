#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLI=$ROOT/bin/beroka-governance
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-connectors-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export HOME=$TEST_ROOT/home
export XDG_CONFIG_HOME=$TEST_ROOT/config
export XDG_DATA_HOME=$TEST_ROOT/data
export BEROKA_GOV_BIN_DIR=$TEST_ROOT/bin
FAKE_BIN=$TEST_ROOT/fake-bin
CALLS=$TEST_ROOT/calls
export CALLS
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$BEROKA_GOV_BIN_DIR" "$FAKE_BIN"
PATH=$FAKE_BIN:/usr/bin:/bin
export PATH

cat >"$FAKE_BIN/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$FAKE_BIN/sleep"

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

if output=$($CLI setup-connectors --client codex --non-interactive 2>&1); then
  fail 'setup accepted missing Codex'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'

if $CLI setup-connectors --client invalid --non-interactive >/dev/null 2>&1; then
  fail 'setup accepted an unsupported client'
fi
if output=$($CLI setup-connectors --client codex --api-token should-not-appear 2>&1); then
  fail 'setup accepted a developer API token'
fi
assert_not_contains "$output" 'should-not-appear'

if output=$(printf '\n' | script -qec "$CLI setup-connectors" /dev/null 2>&1); then
  fail 'interactive setup accepted no detected client'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'

cat >"$FAKE_BIN/codex" <<'EOF'
#!/bin/sh
set -eu
printf 'codex %s\n' "$*" >>"$CALLS"
case "$*" in
  'mcp login --help'|'app-server --help') exit 0 ;;
  'mcp get atlassian --json')
    [ -f "$XDG_CONFIG_HOME/fake-codex-configured" ] || exit 1
    printf '{"name":"atlassian","url":"https://mcp.atlassian.com/v1/mcp/authv2"}\n'
    ;;
  'mcp login atlassian')
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-codex-health"
    ;;
  'app-server --stdio')
    input=$(cat)
    case "$input" in
      *'config/value/write'*)
        : >"$XDG_CONFIG_HOME/fake-codex-configured"
        printf '{"id":1,"result":{}}\n'
        ;;
      *'mcpServerStatus/list'*)
        health=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-health" 2>/dev/null || :)
        case "$health" in
          healthy)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          healthy-custom-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"searchJiraIssuesUsingJql":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          auth-required|'')
            printf '%s\n' \
              '{"method":"mcpServer/startupStatus/updated","params":{"name":"atlassian","status":"failed","failureReason":"reauthenticationRequired"}}' \
              '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          missing)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{},"resources":[],"resourceTemplates":[],"authStatus":"notLoggedIn"}]}}'
            ;;
          failed)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
        esac
        ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
chmod 755 "$FAKE_BIN/codex"
: >"$CALLS"

if output=$($CLI setup-connectors --client codex --non-interactive 2>&1); then
  fail 'non-interactive setup accepted missing Atlassian authentication'
fi
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_contains "$(cat "$CALLS")" 'codex app-server --stdio'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'

rm -f "$XDG_CONFIG_HOME/fake-codex-configured"
: >"$CALLS"
if output=$(printf 'y\nn\n' | script -qec "$CLI setup-connectors" /dev/null 2>&1); then
  fail 'interactive setup accepted declined Codex authentication'
fi
assert_contains "$output" 'Detected client: codex'
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_contains "$(cat "$CALLS")" 'codex app-server --stdio'

cat >"$FAKE_BIN/claude" <<'EOF'
#!/bin/sh
set -eu
printf 'claude %s\n' "$*" >>"$CALLS"
case "$*" in
  'mcp login --help') exit 0 ;;
  'mcp login atlassian')
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
    ;;
  'mcp get atlassian')
    [ -f "$XDG_CONFIG_HOME/fake-claude-configured" ] || exit 1
    printf 'atlassian: https://mcp.atlassian.com/v1/mcp/authv2\n'
    ;;
  'mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2')
    : >"$XDG_CONFIG_HOME/fake-claude-configured"
    ;;
  'mcp list')
    health=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-claude-health" 2>/dev/null || :)
    case "$health" in
      healthy) printf '%s\n' 'atlassian: Connected' ;;
      auth-required|'') printf '%s\n' 'atlassian: Authentication required' ;;
      failed) printf '%s\n' 'atlassian: Failed' ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
chmod 755 "$FAKE_BIN/claude"
rm -f "$XDG_CONFIG_HOME/fake-codex-configured" "$XDG_CONFIG_HOME/fake-claude-configured"
: >"$CALLS"

if output=$(printf '2\nn\n' | script -qec "$CLI setup-connectors" /dev/null 2>&1); then
  fail 'interactive setup accepted declined Claude authentication'
fi
assert_contains "$output" 'Select one client'
assert_not_contains "$output" 'cursor'
assert_contains "$(cat "$CALLS")" 'claude mcp add --transport http --scope user atlassian'
assert_not_contains "$(cat "$CALLS")" 'codex app-server --stdio'

cat >"$FAKE_BIN/cursor-agent" <<'EOF'
#!/bin/sh
set -eu
printf 'cursor-agent %s\n' "$*" >>"$CALLS"
case "$*" in
  'mcp login --help') exit 0 ;;
  'mcp login atlassian')
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
    ;;
  'mcp list')
    health=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-cursor-health" 2>/dev/null || :)
    case "$health" in
      healthy) printf '%s\n' 'atlassian: Ready' ;;
      ready-tools-failed) printf '%s\n' 'atlassian: Ready' ;;
      auth-required|'') printf '%s\n' 'atlassian: Authentication required' ;;
      failed) printf '%s\n' 'atlassian: Failed' ;;
    esac
    ;;
  'mcp list-tools atlassian')
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-cursor-health" 2>/dev/null || :)" in
      healthy) printf '%s\n' 'atlassianUserInfo' ;;
      ready-tools-failed) printf '%s\n' 'Tool inventory failed'; exit 1 ;;
      *) printf '%s\n' 'Authentication required'; exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
chmod 755 "$FAKE_BIN/cursor-agent"
mkdir -p "$HOME/.cursor"
printf '%s\n' '{"other":{"preserved":true}}' >"$HOME/.cursor/mcp.json"
: >"$CALLS"

if output=$($CLI setup-connectors --client cursor --non-interactive 2>&1); then
  fail 'non-interactive Cursor setup accepted missing authentication'
fi
assert_contains "$output" 'Remediation: cursor-agent mcp login atlassian'
jq -e '.other.preserved == true' "$HOME/.cursor/mcp.json" >/dev/null ||
  fail 'Cursor setup discarded existing JSON'
jq -e --arg url 'https://mcp.atlassian.com/v1/mcp/authv2' \
  '.mcpServers.atlassian.url == $url' "$HOME/.cursor/mcp.json" >/dev/null ||
  fail 'Cursor setup did not add Atlassian MCP'
assert_not_contains "$(cat "$CALLS")" 'claude '
assert_not_contains "$(cat "$CALLS")" 'codex '

printf '%s\n' '{"mcpServers":{"atlassian":{"url":"https://example.invalid/mcp"}}}' \
  >"$HOME/.cursor/mcp.json"
if output=$($CLI setup-connectors --client cursor --non-interactive 2>&1); then
  fail 'Cursor setup overwrote a conflicting connector'
fi
assert_contains "$output" 'Result: CONNECTOR_MISSING'
assert_contains "$(cat "$HOME/.cursor/mcp.json")" 'https://example.invalid/mcp'

rm -f "$XDG_CONFIG_HOME/fake-codex-configured"
printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1); then
  fail 'non-interactive setup accepted required authentication'
fi
assert_contains "$output" 'Authentication: AUTH_REQUIRED'
assert_contains "$output" 'Remediation: codex mcp login atlassian'
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'

printf '%s\n' missing >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1); then
  fail 'non-interactive setup accepted missing authentication'
fi
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'

printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI setup-connectors --client codex --non-interactive)
assert_contains "$output" 'Result: PASS'

printf '%s\n' healthy-custom-tools >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI setup-connectors --client codex --non-interactive)
assert_contains "$output" 'Result: PASS'

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
output=$(printf 'y\n' | script -qec "$CLI setup-connectors --client codex" /dev/null 2>&1)
assert_contains "$output" 'Authentication: AUTH_REQUIRED'
assert_contains "$output" 'Result: PASS'
assert_contains "$(cat "$CALLS")" 'codex mcp login atlassian'

printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
: >"$CALLS"
output=$($CLI setup-connectors --client claude --non-interactive)
assert_contains "$output" 'Authentication: PASS'
assert_contains "$(cat "$CALLS")" 'claude mcp list'
assert_not_contains "$(cat "$CALLS")" 'codex '
assert_not_contains "$(cat "$CALLS")" 'cursor-agent '

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-claude-health"
: >"$CALLS"
output=$(printf 'y\n' | script -qec "$CLI setup-connectors --client claude" /dev/null 2>&1)
assert_contains "$output" 'Result: PASS'
assert_contains "$(cat "$CALLS")" 'claude mcp login atlassian'

printf '%s\n' '{"mcpServers":{"atlassian":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}}}' \
  >"$HOME/.cursor/mcp.json"
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
: >"$CALLS"
output=$($CLI setup-connectors --client cursor --non-interactive)
assert_contains "$output" 'Authentication: PASS'
assert_contains "$(cat "$CALLS")" 'cursor-agent mcp list-tools atlassian'
assert_not_contains "$(cat "$CALLS")" 'codex '
assert_not_contains "$(cat "$CALLS")" 'claude '

printf '%s\n' ready-tools-failed >"$XDG_CONFIG_HOME/fake-cursor-health"
if output=$($CLI setup-connectors --client cursor --non-interactive 2>&1); then
  fail 'Cursor setup accepted a failed tool inventory'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-cursor-health"
: >"$CALLS"
output=$(printf 'y\n' | script -qec "$CLI setup-connectors --client cursor" /dev/null 2>&1)
assert_contains "$output" 'Result: PASS'
assert_contains "$(cat "$CALLS")" 'cursor-agent mcp login atlassian'

RELEASE_VERSION=v9.9.9
RELEASE_SOURCE=$TEST_ROOT/release-source
RELEASE_DIR=$XDG_DATA_HOME/beroka-ai-governance/releases/$RELEASE_VERSION
CONSUMER=$TEST_ROOT/consumer
mkdir -p \
  "$RELEASE_SOURCE/bin" \
  "$RELEASE_SOURCE/runtime" \
  "$RELEASE_SOURCE/templates/agent-entrypoints" \
  "$RELEASE_DIR" \
  "$CONSUMER/.cursor/rules"
cp "$CLI" "$RELEASE_SOURCE/bin/beroka-governance"
printf '%s\n' "$RELEASE_VERSION" >"$RELEASE_SOURCE/VERSION"
for release_file in governance.md handbook.md workflow.md; do
  printf '%s\n' "# $release_file" >"$RELEASE_SOURCE/$release_file"
done
printf '%s\n' '# Runtime' >"$RELEASE_SOURCE/runtime/entrypoint.md"
printf '%s\n' \
  '<!-- BEROKA-GOVERNANCE:START -->' \
  'Managed test content.' \
  '<!-- BEROKA-GOVERNANCE:END -->' \
  >"$RELEASE_SOURCE/templates/agent-entrypoints/AGENTS.md"
cp "$RELEASE_SOURCE/templates/agent-entrypoints/AGENTS.md" \
  "$RELEASE_SOURCE/templates/agent-entrypoints/CLAUDE.md"
printf '%s\n' 'Managed Cursor test content.' \
  >"$RELEASE_SOURCE/templates/agent-entrypoints/team-dev-ai-workflow.mdc"
for release_file in ai-agent-assignment github-issue jira-confluence pull-request; do
  printf '%s\n' "# $release_file" >"$RELEASE_SOURCE/templates/$release_file.md"
done
git -C "$RELEASE_SOURCE" init -q
git -C "$RELEASE_SOURCE" config user.name 'Beroka Test'
git -C "$RELEASE_SOURCE" config user.email 'test@example.invalid'
git -C "$RELEASE_SOURCE" add .
git -C "$RELEASE_SOURCE" commit -qm 'test release'
git -C "$RELEASE_SOURCE" tag -am 'test release' "$RELEASE_VERSION"
RELEASE_COMMIT=$(git -C "$RELEASE_SOURCE" rev-parse "$RELEASE_VERSION^{commit}")
git clone -q "$RELEASE_SOURCE" "$RELEASE_DIR"
git -C "$RELEASE_DIR" remote set-url origin \
  https://github.com/beroka-vn/beroka-ai-governance.git
git -C "$RELEASE_DIR" checkout -q "$RELEASE_VERSION"

git -C "$CONSUMER" init -q
git -C "$CONSUMER" config user.name 'Beroka Test'
git -C "$CONSUMER" config user.email 'test@example.invalid'
printf '%s\n' '# Consumer' >"$CONSUMER/README.md"
git -C "$CONSUMER" add README.md
git -C "$CONSUMER" commit -qm 'test consumer'
git -C "$CONSUMER" remote add origin \
  https://github.com/beroka-vn/consumer.git
cp "$RELEASE_SOURCE/templates/agent-entrypoints/AGENTS.md" "$CONSUMER/AGENTS.md"
cp "$RELEASE_SOURCE/templates/agent-entrypoints/CLAUDE.md" "$CONSUMER/CLAUDE.md"
cp "$RELEASE_SOURCE/templates/agent-entrypoints/team-dev-ai-workflow.mdc" \
  "$CONSUMER/.cursor/rules/beroka-governance.mdc"
printf '%s\n' \
  'SOURCE=beroka-vn/beroka-ai-governance' \
  'REPOSITORY=beroka-vn/consumer' \
  "VERSION=$RELEASE_VERSION" \
  "COMMIT=$RELEASE_COMMIT" \
  >"$CONSUMER/.beroka-governance.lock"

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
output=$($CLI doctor "$CONSUMER")
assert_contains "$output" 'Result: PASS'
[ ! -s "$CALLS" ] || fail 'governance-only Doctor invoked a client'

rm -f "$XDG_CONFIG_HOME/fake-codex-configured"
if output=$($CLI doctor "$CONSUMER" --client codex 2>&1); then
  fail 'connector-aware Doctor accepted a missing connector'
fi
assert_contains "$output" 'Result: CONNECTOR_MISSING'

: >"$XDG_CONFIG_HOME/fake-codex-configured"
if output=$($CLI doctor "$CONSUMER" --client codex 2>&1); then
  fail 'connector-aware Doctor accepted required authentication'
fi
assert_contains "$output" 'Remediation: codex mcp login atlassian'
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'

printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
output=$($CLI doctor "$CONSUMER" --client codex)
assert_contains "$output" 'Connector: PASS'
assert_contains "$output" 'Authentication: PASS'
assert_contains "$output" 'Result: PASS'
assert_not_contains "$output" 'atlassianUserInfo'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'
[ "$(grep -Fc 'codex app-server --stdio' "$CALLS")" -eq 1 ] ||
  fail 'connector-aware Doctor repeated its health probe'

mv "$FAKE_BIN/codex" "$FAKE_BIN/codex.disabled"
if output=$($CLI doctor "$CONSUMER" --client codex 2>&1); then
  fail 'connector-aware Doctor accepted a missing client dependency'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
mv "$FAKE_BIN/codex.disabled" "$FAKE_BIN/codex"

for document in "$ROOT/README.md" "$ROOT/handbook.md" "$ROOT/PACKAGE-DESIGN.md"; do
  grep -F 'setup-connectors' "$document" >/dev/null ||
    fail "missing setup-connectors documentation in $document"
done
grep -F 'codex mcp login atlassian' "$ROOT/handbook.md" >/dev/null ||
  fail 'missing Codex remediation command'
grep -F 'ATLASSIAN_AUTH_REQUIRED' "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fail 'missing authentication result in package design'

printf '%s\n' 'Connector selection tests: PASS'
