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
set -eu
if [ -n "${FAKE_CODEX_READY_AFTER:-}" ]; then
  count=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-polls" 2>/dev/null || :)
  count=${count:-0}
  count=$((count + 1))
  printf '%s\n' "$count" >"$XDG_CONFIG_HOME/fake-codex-polls"
  if [ "$FAKE_CODEX_READY_AFTER" != never ] &&
     [ "$count" -ge "$FAKE_CODEX_READY_AFTER" ]
  then
    : >"$XDG_CONFIG_HOME/fake-codex-ready"
  fi
  /bin/sleep 0.01
fi
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

fix_wave_not_contains() {
  case "$1" in
    *"$2"*) fix_wave_fail "did not expect [$2] in [$1]" ;;
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
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-endpoint" 2>/dev/null || :)" in
      metadata-url)
        printf '%s\n' '{"name":"atlassian","url":"https://wrong.invalid/mcp","metadata":{"description":"https://mcp.atlassian.com/v1/mcp/authv2"}}'
        ;;
      duplicate-url)
        printf '%s\n' '{"name":"atlassian","url":"https://wrong.invalid/mcp","url":"https://mcp.atlassian.com/v1/mcp/authv2"}'
        ;;
      missing-url)
        printf '%s\n' '{"name":"atlassian","metadata":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}}'
        ;;
      transport-url)
        printf '%s\n' \
          '{"name":"atlassian","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.atlassian.com/v1/mcp/authv2","bearer_token_env_var":null,"http_headers":null,"env_http_headers":null}}'
        ;;
      duplicate-transport-url)
        printf '%s\n' \
          '{"name":"atlassian","transport":{"type":"streamable_http","url":"https://wrong.invalid/mcp","url":"https://mcp.atlassian.com/v1/mcp/authv2"}}'
        ;;
      both-url-shapes)
        printf '%s\n' \
          '{"name":"atlassian","url":"https://mcp.atlassian.com/v1/mcp/authv2","transport":{"type":"streamable_http","url":"https://mcp.atlassian.com/v1/mcp/authv2"}}'
        ;;
      wrong-name)
        printf '%s\n' '{"name":"atlassian-helper","url":"https://mcp.atlassian.com/v1/mcp/authv2"}'
        ;;
      malformed-json)
        printf '%s\n' '{"name":"atlassian","url":"https://mcp.atlassian.com/v1/mcp/authv2","broken":[,]}'
        ;;
      split-documents)
        printf '%s\n' \
          '{"name":"atlassian"}' \
          '{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}'
        ;;
      trailing-document)
        printf '%s\n' \
          '{"name":"atlassian","url":"https://mcp.atlassian.com/v1/mcp/authv2"}' \
          '{"unrelated":true}'
        ;;
      *)
        printf '{"name":"atlassian","url":"https://mcp.atlassian.com/v1/mcp/authv2"}\n'
        ;;
    esac
    ;;
  'mcp login atlassian')
    printf '%s\n' \
      'OAuth URL: https://auth.example.test/authorize?state=one-time'
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-codex-health"
    ;;
  'app-server --stdio')
    IFS= read -r request_1 || exit 1
    IFS= read -r request_2 || exit 1
    while IFS= read -r request; do
      case "$request" in
      *'config/value/write'*)
        : >"$XDG_CONFIG_HOME/fake-codex-configured"
        printf '{"id":1,"result":{}}\n'
        ;;
      *'mcpServerStatus/list'*)
        loops=0
        while [ -n "${FAKE_CODEX_READY_AFTER:-}" ] &&
              [ ! -f "$XDG_CONFIG_HOME/fake-codex-ready" ] &&
              [ "$loops" -lt 100 ]
        do
          /bin/sleep 0.01
          loops=$((loops + 1))
        done
        [ -z "${FAKE_CODEX_READY_AFTER:-}" ] ||
          [ -f "$XDG_CONFIG_HOME/fake-codex-ready" ] ||
          exit 0
        health=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-health" 2>/dev/null || :)
        case "$health" in
          unknown-then-healthy)
            probes=$(sed -n '1p' \
              "$XDG_CONFIG_HOME/fake-codex-probes" 2>/dev/null || :)
            probes=${probes:-0}
            probes=$((probes + 1))
            printf '%s\n' "$probes" \
              >"$XDG_CONFIG_HOME/fake-codex-probes"
            if [ "$probes" -eq 1 ]; then
              printf '%s\n' '{"id":1,"result":{"unexpected":true}}'
            else
              printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            fi
            ;;
          ignore-term)
            printf '%s\n' "$$" >"$XDG_CONFIG_HOME/fake-codex-pid"
            trap '' TERM
            while :; do :; done
            ;;
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
    done
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

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
for ready_after in 1 3 4; do
  rm -f \
    "$XDG_CONFIG_HOME/fake-codex-polls" \
    "$XDG_CONFIG_HOME/fake-codex-ready"
  export FAKE_CODEX_READY_AFTER=$ready_after
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fail "Codex delayed probe $ready_after unexpectedly passed authentication"
  fi
  assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
done

rm -f \
  "$XDG_CONFIG_HOME/fake-codex-polls" \
  "$XDG_CONFIG_HOME/fake-codex-ready"
export FAKE_CODEX_READY_AFTER=never
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fail 'Codex probe without a response passed'
fi
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
unset FAKE_CODEX_READY_AFTER

rm -f "$XDG_CONFIG_HOME/fake-codex-probes"
printf '%s\n' unknown-then-healthy \
  >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI setup-connectors --client codex --non-interactive)
assert_contains "$output" 'Result: PASS'
[ "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-probes")" -ge 2 ] ||
  fail 'Codex did not re-probe after an unclassifiable response'

printf '%s\n' ignore-term >"$XDG_CONFIG_HOME/fake-codex-health"
rm -f "$XDG_CONFIG_HOME/fake-codex-pid"
started=$(/bin/date +%s)
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fail 'Codex probe with an unresponsive app server passed'
fi
elapsed=$(( $(/bin/date +%s) - started ))
[ "$elapsed" -lt 5 ] ||
  fail "Codex probe teardown exceeded its bounded allowance: ${elapsed}s"
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
stubborn_pid=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-pid")
if kill -0 "$stubborn_pid" 2>/dev/null; then
  fail "Codex probe left app-server process $stubborn_pid running"
fi

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
rm -f "$XDG_CONFIG_HOME/fake-codex-configured"
: >"$CALLS"
if output=$(printf 'y\nn\n' | script -qec "$CLI setup-connectors" /dev/null 2>&1); then
  fail 'interactive setup accepted declined Codex authentication'
fi
assert_contains "$output" 'Detected client: codex'
assert_contains "$output" 'Result: AUTH_PENDING'
assert_contains "$(cat "$CALLS")" 'codex app-server --stdio'

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$(printf 'n\n' |
  script -qec "$CLI setup-connectors --client codex" /dev/null 2>&1)
then
  fail 'interactive setup accepted pending authentication'
fi
assert_contains "$output" 'Connector: AUTH_PENDING'
assert_contains "$output" 'Result: AUTH_PENDING'
assert_contains "$output" \
  'Resume: beroka-governance setup-connectors --client codex'

export FAKE_CODEX_READY_AFTER=never
rm -f \
  "$XDG_CONFIG_HOME/fake-codex-polls" \
  "$XDG_CONFIG_HOME/fake-codex-ready"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fail 'setup accepted unavailable connector health'
fi
assert_contains "$output" 'Connector: HEALTH_UNAVAILABLE'
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
unset FAKE_CODEX_READY_AFTER

cat >"$FAKE_BIN/claude" <<'EOF'
#!/bin/sh
set -eu
printf 'claude %s\n' "$*" >>"$CALLS"
case "$*" in
  '--version') printf '%s\n' '1.2.3 (Claude Code)' ;;
  'mcp add --help'|'mcp get --help'|'mcp list --help') exit 0 ;;
  '')
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
    ;;
  'mcp get atlassian')
    [ -f "$XDG_CONFIG_HOME/fake-claude-configured" ] || exit 1
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-claude-endpoint" 2>/dev/null || :)" in
      metadata-url)
        printf '%s\n' \
          'Description: https://mcp.atlassian.com/v1/mcp/authv2' \
          'URL: https://wrong.invalid/mcp'
        ;;
      duplicate-url)
        printf '%s\n' \
          'URL: https://wrong.invalid/mcp' \
          'URL: https://mcp.atlassian.com/v1/mcp/authv2'
        ;;
      missing-url)
        printf '%s\n' \
          'Name: atlassian' \
          'Description: https://mcp.atlassian.com/v1/mcp/authv2'
        ;;
      wrong-name)
        printf '%s\n' \
          'Name: atlassian-helper' \
          'URL: https://mcp.atlassian.com/v1/mcp/authv2'
        ;;
      duplicate-name)
        printf '%s\n' \
          'Name: atlassian' \
          'Name: atlassian-helper' \
          'URL: https://mcp.atlassian.com/v1/mcp/authv2'
        ;;
      missing-name)
        printf '%s\n' \
          'Description: atlassian' \
          'URL: https://mcp.atlassian.com/v1/mcp/authv2'
        ;;
      *)
        printf '%s\n' \
          'Name: atlassian' \
          'URL: https://mcp.atlassian.com/v1/mcp/authv2'
        ;;
    esac
    ;;
  'mcp add --transport http --scope user atlassian https://mcp.atlassian.com/v1/mcp/authv2')
    : >"$XDG_CONFIG_HOME/fake-claude-configured"
    ;;
  'mcp list')
    health=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-claude-health" 2>/dev/null || :)
    case "$health" in
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
      unrelated-only)
        printf '%s\n' \
          'atlassian-helper: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - ✓ Connected'
        ;;
      auth-required|'')
        printf '%s\n' 'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - Authentication required'
        ;;
      failed)
        printf '%s\n' 'atlassian: https://mcp.atlassian.com/v1/mcp/authv2 (HTTP) - Failed'
        ;;
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

: >"$XDG_CONFIG_HOME/fake-codex-configured"
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-codex-health"
for invalid_endpoint in \
  metadata-url duplicate-url missing-url wrong-name malformed-json \
  split-documents trailing-document duplicate-transport-url both-url-shapes
do
  printf '%s\n' "$invalid_endpoint" >"$XDG_CONFIG_HOME/fake-codex-endpoint"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_fail "Codex accepted $invalid_endpoint endpoint response"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_MISSING'
  fi
done
rm -f "$XDG_CONFIG_HOME/fake-codex-endpoint"

printf '%s\n' transport-url >"$XDG_CONFIG_HOME/fake-codex-endpoint"
output=$($CLI setup-connectors --client codex --non-interactive)
fix_wave_contains "$output" 'Authentication: PASS'
rm -f "$XDG_CONFIG_HOME/fake-codex-endpoint"

printf '%s\n' failed >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fix_wave_fail 'Codex OAuth with an empty tool inventory passed'
else
  fix_wave_contains "$output" 'Provider: atlassian'
  fix_wave_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
fi

: >"$XDG_CONFIG_HOME/fake-claude-configured"
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
for invalid_endpoint in \
  metadata-url duplicate-url missing-url wrong-name duplicate-name missing-name
do
  printf '%s\n' "$invalid_endpoint" >"$XDG_CONFIG_HOME/fake-claude-endpoint"
  if output=$($CLI setup-connectors --client claude --non-interactive 2>&1)
  then
    fix_wave_fail "Claude accepted $invalid_endpoint endpoint response"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_MISSING'
  fi
done
rm -f "$XDG_CONFIG_HOME/fake-claude-endpoint"

if output=$(PATH=$FAKE_BIN $CLI setup-connectors \
  --client codex --non-interactive 2>&1)
then
  fix_wave_fail 'Codex accepted a missing jq dependency'
else
  fix_wave_contains "$output" 'Result: DEPENDENCY_MISSING'
fi
if output=$(PATH=$FAKE_BIN $CLI setup-connectors \
  --client claude --non-interactive 2>&1)
then
  fix_wave_fail 'Claude accepted a missing jq dependency'
else
  fix_wave_contains "$output" 'Result: DEPENDENCY_MISSING'
fi

printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
if output=$($CLI setup-connectors --client claude --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Authentication: PASS'
else
  fix_wave_fail 'Claude realistic connected status did not pass'
fi

printf '%s\n' auth-needs-realistic >"$XDG_CONFIG_HOME/fake-claude-health"
if output=$($CLI setup-connectors --client claude --non-interactive 2>&1)
then
  fix_wave_fail 'Claude Needs authentication status passed'
else
  fix_wave_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
  fix_wave_contains "$output" 'Remediation: claude'
  fix_wave_contains "$output" \
    'In Claude: /mcp -> atlassian -> Authenticate'
fi

printf '%s\n' unrelated-only >"$XDG_CONFIG_HOME/fake-claude-health"
if output=$($CLI setup-connectors --client claude --non-interactive 2>&1)
then
  fix_wave_fail 'similarly named Claude server passed health'
else
  fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
fi

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
      healthy)
        printf '%s\n' \
          '- createJiraIssue (projectKey, issueType, summary)' \
          '- getAccessibleAtlassianResources ()' \
          '- getJiraIssue (issueKey)' \
          '- getJiraIssueTypeMetaWithFields (projectKey, issueType)' \
          '- getJiraProjectIssueTypesMetadata (projectKey)' \
          '- searchJiraIssuesUsingJql (cloudId, jql)'
        ;;
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
assert_contains "$output" 'Provider: atlassian'
assert_contains "$output" \
  'OAuth URL: https://auth.example.test/authorize?state=one-time'
assert_contains "$output" 'Result: PASS'
assert_contains "$(cat "$CALLS")" 'codex mcp login atlassian'
if rg -l -F 'auth.example.test' \
  "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" >/dev/null 2>&1
then
  fail 'Governance persisted the provider OAuth URL'
fi

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
fix_wave_contains "$output" 'In Claude: /mcp -> atlassian -> Authenticate'
if ! grep -Fx 'claude ' "$CALLS" >/dev/null; then
  fix_wave_fail 'interactive Claude authentication did not launch claude'
fi
fix_wave_not_contains "$(cat "$CALLS")" 'claude mcp login atlassian'

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
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'

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
  "$CONSUMER"
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
printf '%s\n' \
  'SOURCE=beroka-vn/beroka-ai-governance' \
  'REPOSITORY=beroka-vn/consumer' \
  "VERSION=$RELEASE_VERSION" \
  "COMMIT=$RELEASE_COMMIT" \
  'CLIENTS=codex' \
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
grep -F 'GITHUB_AUTH_REQUIRED' "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fail 'package design does not document GitHub authentication result'
grep -F 'gh auth login --hostname github.com --web' "$ROOT/handbook.md" \
  >/dev/null ||
  fail 'handbook does not document GitHub OAuth remediation'
grep -F 'provider OAuth output directly' "$ROOT/README.md" >/dev/null ||
  fail 'README does not document OAuth URL pass-through'
grep -F 'CLIENTS=codex,claude' "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fail 'package design does not document additive clients'
grep -F 'register "$repo" --version "$release" --client codex' \
  "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook register command does not select a client'
awk '
  /^```/ { in_block = !in_block; next }
  in_block &&
    $0 == "beroka-governance bootstrap \"$(git rev-parse --show-toplevel)\" \\" {
    getline
    if ($0 != "  --client claude \\") next
    getline
    if ($0 == "  --non-interactive") found = 1
  }
  END { exit found ? 0 : 1 }
' "$ROOT/README.md" ||
  fail 'README does not document adding another client'
grep -F 'gh release download' "$ROOT/README.md" >/dev/null ||
  fail 'README does not document the release launcher'
grep -F 'AUTH_PENDING' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document pending authentication'
grep -F 'CONNECTOR_HEALTH_UNAVAILABLE' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document unavailable connector health'
grep -F 'connector inspection requires `jq` for every selected client' \
  "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fix_wave_fail 'package design does not declare jq for connector inspection'

[ "$FIX_WAVE_FAILURES" -eq 0 ] ||
  fail "$FIX_WAVE_FAILURES fix-wave connector regressions remain"

printf '%s\n' 'Connector selection tests: PASS'
