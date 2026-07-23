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
  'app-server --stdio')
    input=$(cat)
    case "$input" in
      *'config/value/write'*)
        : >"$XDG_CONFIG_HOME/fake-codex-configured"
        printf '{"id":1,"result":{}}\n'
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
  'mcp get atlassian')
    [ -f "$XDG_CONFIG_HOME/fake-claude-configured" ] || exit 1
    printf 'atlassian: https://mcp.atlassian.com/v1/mcp/authv2\n'
    ;;
  'mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2')
    : >"$XDG_CONFIG_HOME/fake-claude-configured"
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

printf '%s\n' 'Connector selection tests: PASS'
