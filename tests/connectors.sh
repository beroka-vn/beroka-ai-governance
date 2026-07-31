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
if [ "${FAKE_CODEX_WAIT_FOR_UTF8_SPLIT:-0}" = 1 ]; then
  split_polls=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-split-polls" 2>/dev/null || :)
  split_polls=${split_polls:-0}
  split_polls=$((split_polls + 1))
  printf '%s\n' "$split_polls" >"$XDG_CONFIG_HOME/fake-codex-split-polls"
  if [ "$split_polls" -eq 1 ]; then
    split_marker=$XDG_CONFIG_HOME/fake-codex-split-first
  else
    split_marker=$XDG_CONFIG_HOME/fake-codex-split-complete
  fi
  split_waits=0
  while [ ! -f "$split_marker" ] && [ "$split_waits" -lt 100 ]; do
    /bin/sleep 0.01
    split_waits=$((split_waits + 1))
  done
  exit 0
fi
if [ "${FAKE_CODEX_WAIT_FOR_DECOY:-0}" = 1 ]; then
  decoy_polls=$(sed -n '1p' \
    "$XDG_CONFIG_HOME/fake-codex-decoy-polls" 2>/dev/null || :)
  decoy_polls=${decoy_polls:-0}
  decoy_polls=$((decoy_polls + 1))
  printf '%s\n' "$decoy_polls" \
    >"$XDG_CONFIG_HOME/fake-codex-decoy-polls"
  if [ "$decoy_polls" -eq 1 ]; then
    decoy_marker=$XDG_CONFIG_HOME/fake-codex-decoy
  else
    decoy_marker=$XDG_CONFIG_HOME/fake-codex-actual
  fi
  wait_loops=0
  while [ ! -f "$decoy_marker" ] && [ "$wait_loops" -lt 100 ]; do
    /bin/sleep 0.01
    wait_loops=$((wait_loops + 1))
  done
  /bin/sleep 0.01
  exit 0
fi
if [ "${FAKE_CODEX_WAIT_FOR_ESCAPED:-0}" = 1 ]; then
  wait_loops=0
  while [ ! -f "$XDG_CONFIG_HOME/fake-codex-escaped-probes" ] &&
        [ "$wait_loops" -lt 100 ]
  do
    /bin/sleep 0.01
    wait_loops=$((wait_loops + 1))
  done
  /bin/sleep 0.01
  exit 0
fi
if [ "${FAKE_CODEX_WAIT_FOR_ERROR:-0}" = 1 ]; then
  wait_loops=0
  while [ ! -f "$XDG_CONFIG_HOME/fake-codex-error-probes" ] &&
        [ "$wait_loops" -lt 100 ]
  do
    /bin/sleep 0.01
    wait_loops=$((wait_loops + 1))
  done
  /bin/sleep 0.01
  exit 0
fi
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
          escaped-id-one-result|escaped-result-only|escaped-error-with-result|\
          escaped-id-conflict-with-result|escaped-result-with-error|\
          semantic-duplicate-result|semantic-duplicate-error|\
          escaped-wrapper-keys|semantic-duplicate-data|\
          semantic-duplicate-name|semantic-duplicate-tools|\
          semantic-duplicate-auth-status|raw-nul-response|escaped-nul-text|\
          nested-extension-before-tools|valid-raw-unicode|invalid-utf8-*|\
          split-utf8-*)
            escaped_probes=$(sed -n '1p' \
              "$XDG_CONFIG_HOME/fake-codex-escaped-probes" \
              2>/dev/null || :)
            escaped_probes=${escaped_probes:-0}
            escaped_probes=$((escaped_probes + 1))
            printf '%s\n' "$escaped_probes" \
              >"$XDG_CONFIG_HOME/fake-codex-escaped-probes"
            ;;
        esac
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
          healthy-rpc-extensions)
            printf '%s\n' '{"jsonrpc":"2.0","id":1,"trace-id":"abc","key with space":true,"escaped\u002dextension":null,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          nested-id-before-healthy|string-id-before-healthy)
            decoy_requests=$(sed -n '1p' \
              "$XDG_CONFIG_HOME/fake-codex-decoy-requests" \
              2>/dev/null || :)
            decoy_requests=${decoy_requests:-0}
            decoy_requests=$((decoy_requests + 1))
            printf '%s\n' "$decoy_requests" \
              >"$XDG_CONFIG_HOME/fake-codex-decoy-requests"
            case "$health" in
              nested-id-before-healthy)
                printf '%s\n' \
                  '{"method":"notice","params":{"id":1,"result":{"ignored":true}}}'
                ;;
              string-id-before-healthy)
                printf '%s\n' \
                  '{"method":"notice","message":"saw \"id\":1 in text"}'
                ;;
            esac
            : >"$XDG_CONFIG_HOME/fake-codex-decoy"
            /bin/sleep 0.08
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            : >"$XDG_CONFIG_HOME/fake-codex-actual"
            ;;
          nested-id-only)
            printf '%s\n' \
              '{"method":"notice","params":{"id":1,"result":{"ignored":true}}}'
            ;;
          string-id-only)
            printf '%s\n' \
              '{"method":"notice","message":"saw \"id\":1 in text"}'
            ;;
          duplicate-rpc-id)
            printf '%s\n' '{"id":1,"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          duplicate-rpc-result)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]},"result":{}}'
            ;;
          duplicate-rpc-error)
            printf '%s\n' '{"id":1,"error":null,"error":{"code":-32603,"message":"failed"}}'
            ;;
          escaped-id-one-result)
            printf '%s\n' '{"\u0069\u0064":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          escaped-result-only)
            printf '%s\n' '{"id":1,"\u0072esult":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          escaped-error-with-result)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]},"e\u0072ror":null}'
            ;;
          escaped-id-conflict-with-result)
            printf '%s\n' '{"id":1,"i\u0064":2,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          escaped-result-with-error)
            printf '%s\n' '{"id":1,"\u0072esult":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]},"error":null}'
            ;;
          semantic-duplicate-result)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]},"r\u0065sult":{}}'
            ;;
          semantic-duplicate-error)
            printf '%s\n' '{"id":1,"error":null,"e\u0072ror":{"code":-32603,"message":"failed"}}'
            ;;
          escaped-wrapper-keys)
            printf '%s\n' '{"id":1,"result":{"d\u0061ta":[{"n\u0061me":"atlassian","serverInfo":null,"t\u006fols":{"atlassianUserInfo":{}},"resources":[],"resourceTemplates":[],"authSt\u0061tus":"oAuth"}]}}'
            ;;
          semantic-duplicate-data)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}],"d\u0061ta":[]}}'
            ;;
          semantic-duplicate-name)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","n\u0061me":"other","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          semantic-duplicate-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"atlassianUserInfo":{}},"t\u006fols":{},"authStatus":"oAuth"}]}}'
            ;;
          semantic-duplicate-auth-status)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth","authSt\u0061tus":"notLoggedIn"}]}}'
            ;;
          raw-nul-response)
            printf '%s\000%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' \
              'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          escaped-nul-text)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before\u0000after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          nested-extension-before-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","extension":{"nested":[{"text":"close } open { square ] [ escaped \" quote and \\ backslash"},["}",{"deeper":"{ [ ] }"}]]},"tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          malformed-nested-extension-before-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","extension":{"nested":[{"text":"invalid\qescape"}]},"tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          valid-raw-unicode)
            printf '%s\302\200\337\277\340\240\200\355\237\277\356\200\200\357\277\277\360\220\200\200\364\217\277\277%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","note":"ASCII ' \
              '","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          split-utf8-2)
            printf '%s\302' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before'
            : >"$XDG_CONFIG_HOME/fake-codex-split-first"
            /bin/sleep 0.08
            printf '\242%s\n' 'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            : >"$XDG_CONFIG_HOME/fake-codex-split-complete"
            ;;
          split-utf8-3)
            printf '%s\342' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before'
            : >"$XDG_CONFIG_HOME/fake-codex-split-first"
            /bin/sleep 0.08
            printf '\202\254%s\n' 'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            : >"$XDG_CONFIG_HOME/fake-codex-split-complete"
            ;;
          split-utf8-4)
            printf '%s\360' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before'
            : >"$XDG_CONFIG_HOME/fake-codex-split-first"
            /bin/sleep 0.08
            printf '\220\215\210%s\n' 'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            : >"$XDG_CONFIG_HOME/fake-codex-split-complete"
            ;;
          invalid-utf8-continuation)
            printf '%s\200%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-ff-fe)
            printf '%s\377\376%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-overlong)
            printf '%s\300\200%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-surrogate)
            printf '%s\355\240\200%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-too-high)
            printf '%s\364\220\200\200%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-truncated)
            printf '%s\342\202%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"atlassianUserInfo":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-eof-truncated)
            printf '%s\342\202' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before'
            exit 0
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
          healthy-empty-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":{},"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          healthy-array-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":[],"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          healthy-null-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"tools":null,"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          healthy-missing-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","serverInfo":null,"resources":[],"resourceTemplates":[],"authStatus":"oAuth"}]}}'
            ;;
          healthy-malformed-envelope-missing-comma)
            printf '%s\n' '{"jsonrpc":"2.0" "id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-malformed-record-illegal-escape)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","description":"invalid\qescape","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-malformed-record-missing-comma)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian" "tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-malformed-envelope-trailing-object)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}} {"trailing":true}'
            ;;
          healthy-malformed-envelope-trailing-member)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}},"extra":{}'
            ;;
          healthy-malformed-envelope-trailing-member-spaced)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}} , "extra" : {}'
            ;;
          healthy-malformed-envelope-trailing-member-whitespace)
            printf '%s \t,\r\t%s\t:\t%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}' \
              '"extra"' '{}'
            ;;
          dual-result-error|dual-result-error-null|\
          dual-result-error-string|dual-result-error-array|\
          dual-result-error-number|dual-result-error-bool)
            error_probes=$(sed -n '1p' \
              "$XDG_CONFIG_HOME/fake-codex-error-probes" 2>/dev/null || :)
            error_probes=${error_probes:-0}
            error_probes=$((error_probes + 1))
            printf '%s\n' "$error_probes" \
              >"$XDG_CONFIG_HOME/fake-codex-error-probes"
            case "$health" in
              *-null) error_value=null ;;
              *-string) error_value='"failed"' ;;
              *-array) error_value='["failed"]' ;;
              *-number) error_value=17 ;;
              *-bool) error_value=true ;;
              *) error_value='{"code":-32603,"message":"failed"}' ;;
            esac
            printf '%s%s%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]},"error":' \
              "$error_value" '}'
            ;;
          pure-error|pure-error-null|pure-error-string|pure-error-array|\
          pure-error-number|pure-error-bool)
            error_probes=$(sed -n '1p' \
              "$XDG_CONFIG_HOME/fake-codex-error-probes" 2>/dev/null || :)
            error_probes=${error_probes:-0}
            error_probes=$((error_probes + 1))
            printf '%s\n' "$error_probes" \
              >"$XDG_CONFIG_HOME/fake-codex-error-probes"
            case "$health" in
              *-null) error_value=null ;;
              *-string) error_value='"failed"' ;;
              *-array) error_value='["failed"]' ;;
              *-number) error_value=17 ;;
              *-bool) error_value=true ;;
              *) error_value='{"code":-32603,"message":"failed"}' ;;
            esac
            printf '%s%s%s\n' '{"id":1,"error":' "$error_value" '}'
            ;;
          neither-result-nor-error)
            error_probes=$(sed -n '1p' \
              "$XDG_CONFIG_HOME/fake-codex-error-probes" 2>/dev/null || :)
            error_probes=${error_probes:-0}
            error_probes=$((error_probes + 1))
            printf '%s\n' "$error_probes" \
              >"$XDG_CONFIG_HOME/fake-codex-error-probes"
            printf '%s\n' '{"jsonrpc":"2.0","id":1}'
            ;;
          malformed-reauth-missing-comma)
            printf '%s\n' '{"method":"mcpServer/startupStatus/updated" "params":{"name":"atlassian","failureReason":"reauthenticationRequired"}}'
            ;;
          malformed-reauth-illegal-escape)
            printf '%s\n' '{"method":"mcpServer/startupStatus/updated","params":{"name":"atlassian","failureReason":"reauthenticationRequired","message":"invalid\qescape"}}'
            ;;
          malformed-reauth-trailing-member)
            printf '%s\n' '{"method":"mcpServer/startupStatus/updated","params":{"name":"atlassian","failureReason":"reauthenticationRequired"}},"extra":{}'
            ;;
          malformed-reauth-trailing-token)
            printf '%s\n' '{"method":"mcpServer/startupStatus/updated","params":{"name":"atlassian","failureReason":"reauthenticationRequired"}} true'
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

printf '%s\n' healthy-rpc-extensions \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'Codex rejected valid JSON-RPC extension keys'
fi

export FAKE_CODEX_WAIT_FOR_DECOY=1
for delayed_response in \
  nested-id-before-healthy \
  string-id-before-healthy
do
  rm -f \
    "$XDG_CONFIG_HOME/fake-codex-decoy" \
    "$XDG_CONFIG_HOME/fake-codex-actual" \
    "$XDG_CONFIG_HOME/fake-codex-decoy-polls" \
    "$XDG_CONFIG_HOME/fake-codex-decoy-requests"
  printf '%s\n' "$delayed_response" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_contains "$output" 'Result: PASS'
  else
    fix_wave_fail "$delayed_response masked the actual Codex response"
  fi
  decoy_requests=$(sed -n '1p' \
    "$XDG_CONFIG_HOME/fake-codex-decoy-requests" 2>/dev/null || :)
  [ "$decoy_requests" = 1 ] ||
    fix_wave_fail "$delayed_response used ${decoy_requests:-0} probes"
done
unset FAKE_CODEX_WAIT_FOR_DECOY

for unrelated_only in nested-id-only string-id-only; do
  printf '%s\n' "$unrelated_only" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_fail "$unrelated_only passed Codex setup"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  fix_wave_not_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
done

for duplicate_rpc_member in \
  duplicate-rpc-id \
  duplicate-rpc-result \
  duplicate-rpc-error
do
  printf '%s\n' "$duplicate_rpc_member" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_fail "$duplicate_rpc_member passed Codex setup"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
done

export FAKE_CODEX_WAIT_FOR_ESCAPED=1
rm -f "$XDG_CONFIG_HOME/fake-codex-escaped-probes"
printf '%s\n' escaped-id-one-result \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'escaped semantic id=1 did not select the Codex response'
fi
escaped_probes=$(sed -n '1p' \
  "$XDG_CONFIG_HOME/fake-codex-escaped-probes" 2>/dev/null || :)
[ "$escaped_probes" = 1 ] ||
  fix_wave_fail "escaped-id-one-result used ${escaped_probes:-0} probes"

rm -f "$XDG_CONFIG_HOME/fake-codex-escaped-probes"
printf '%s\n' escaped-result-only \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'escaped semantic result did not select the Codex response'
fi
escaped_probes=$(sed -n '1p' \
  "$XDG_CONFIG_HOME/fake-codex-escaped-probes" 2>/dev/null || :)
[ "$escaped_probes" = 1 ] ||
  fix_wave_fail "escaped-result-only used ${escaped_probes:-0} probes"

for rejected_escaped_rpc in \
  escaped-error-with-result \
  escaped-id-conflict-with-result \
  escaped-result-with-error \
  semantic-duplicate-result \
  semantic-duplicate-error
do
  rm -f "$XDG_CONFIG_HOME/fake-codex-escaped-probes"
  printf '%s\n' "$rejected_escaped_rpc" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_fail "$rejected_escaped_rpc passed Codex setup"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  escaped_probes=$(sed -n '1p' \
    "$XDG_CONFIG_HOME/fake-codex-escaped-probes" 2>/dev/null || :)
  [ "$escaped_probes" = 1 ] ||
    fix_wave_fail \
      "$rejected_escaped_rpc used ${escaped_probes:-0} probes"
  fix_wave_not_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
  fix_wave_not_contains "$output" 'atlassianUserInfo'
done

rm -f "$XDG_CONFIG_HOME/fake-codex-escaped-probes"
printf '%s\n' escaped-wrapper-keys \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'escaped semantic wrapper keys did not pass Codex setup'
fi
wrapper_probes=$(sed -n '1p' \
  "$XDG_CONFIG_HOME/fake-codex-escaped-probes" 2>/dev/null || :)
[ "$wrapper_probes" = 1 ] ||
  fix_wave_fail "escaped-wrapper-keys used ${wrapper_probes:-0} probes"

for rejected_wrapper in \
  semantic-duplicate-data \
  semantic-duplicate-name \
  semantic-duplicate-tools \
  semantic-duplicate-auth-status
do
  rm -f "$XDG_CONFIG_HOME/fake-codex-escaped-probes"
  printf '%s\n' "$rejected_wrapper" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_fail "$rejected_wrapper passed Codex setup"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  wrapper_probes=$(sed -n '1p' \
    "$XDG_CONFIG_HOME/fake-codex-escaped-probes" 2>/dev/null || :)
  [ "$wrapper_probes" = 1 ] ||
    fix_wave_fail "$rejected_wrapper used ${wrapper_probes:-0} probes"
  fix_wave_not_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
  fix_wave_not_contains "$output" 'atlassianUserInfo'
done

rm -f "$XDG_CONFIG_HOME/fake-codex-escaped-probes"
printf '%s\n' raw-nul-response \
  >"$XDG_CONFIG_HOME/fake-codex-health"
raw_nul_output=$TEST_ROOT/raw-nul-output
if $CLI setup-connectors --client codex --non-interactive \
  >"$raw_nul_output" 2>&1
then
  fix_wave_fail 'raw-nul-response passed Codex setup'
fi
if LC_ALL=C od -An -v -t u1 "$raw_nul_output" |
  awk '{
    for (i=1; i<=NF; i++) if ($i == 0) found=1
  }
  END { exit !found }'
then
  fix_wave_fail 'raw NUL leaked into Codex setup output'
fi
output=$(cat "$raw_nul_output")
fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
raw_nul_probes=$(sed -n '1p' \
  "$XDG_CONFIG_HOME/fake-codex-escaped-probes" 2>/dev/null || :)
[ "$raw_nul_probes" = 1 ] ||
  fix_wave_fail "raw-nul-response used ${raw_nul_probes:-0} probes"
fix_wave_not_contains "$output" 'Capability state: SUPPORTED'
fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
fix_wave_not_contains "$output" 'codex mcp login atlassian'
fix_wave_not_contains "$output" 'OAuth URL:'
fix_wave_not_contains "$output" 'atlassianUserInfo'

rm -f "$XDG_CONFIG_HOME/fake-codex-escaped-probes"
printf '%s\n' escaped-nul-text \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'escaped JSON NUL text did not pass Codex setup'
fi
escaped_nul_probes=$(sed -n '1p' \
  "$XDG_CONFIG_HOME/fake-codex-escaped-probes" 2>/dev/null || :)
[ "$escaped_nul_probes" = 1 ] ||
  fix_wave_fail "escaped-nul-text used ${escaped_nul_probes:-0} probes"

printf '%s\n' valid-raw-unicode \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'valid raw UTF-8 did not pass Codex setup'
fi

export FAKE_CODEX_WAIT_FOR_UTF8_SPLIT=1
for split_utf8 in split-utf8-2 split-utf8-3 split-utf8-4; do
  rm -f "$XDG_CONFIG_HOME"/fake-codex-split-* \
    "$XDG_CONFIG_HOME/fake-codex-escaped-probes"
  printf '%s\n' "$split_utf8" >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_contains "$output" 'Result: PASS'
  else
    fix_wave_fail "$split_utf8 did not survive split transport"
  fi
  split_probes=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-escaped-probes" 2>/dev/null || :)
  [ "$split_probes" = 1 ] || fix_wave_fail "$split_utf8 used ${split_probes:-0} probes"
done
unset FAKE_CODEX_WAIT_FOR_UTF8_SPLIT

for invalid_utf8 in \
  invalid-utf8-continuation \
  invalid-utf8-ff-fe \
  invalid-utf8-overlong \
  invalid-utf8-surrogate \
  invalid-utf8-too-high \
  invalid-utf8-truncated \
  invalid-utf8-eof-truncated
do
  rm -f "$XDG_CONFIG_HOME/fake-codex-escaped-probes"
  printf '%s\n' "$invalid_utf8" >"$XDG_CONFIG_HOME/fake-codex-health"
  invalid_utf8_output=$TEST_ROOT/$invalid_utf8-output
  if $CLI setup-connectors --client codex --non-interactive \
    >"$invalid_utf8_output" 2>&1
  then
    fix_wave_fail "$invalid_utf8 passed Codex setup"
  fi
  if LC_ALL=C od -An -v -t u1 "$invalid_utf8_output" |
    awk '{
      for (i=1; i<=NF; i++) if ($i == 0 || $i > 127) found=1
    }
    END { exit !found }'
  then
    fix_wave_fail "$invalid_utf8 leaked raw bytes"
  fi
  output=$(cat "$invalid_utf8_output")
  fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  invalid_utf8_probes=$(sed -n '1p' \
    "$XDG_CONFIG_HOME/fake-codex-escaped-probes" 2>/dev/null || :)
  [ "$invalid_utf8_probes" = 1 ] ||
    fix_wave_fail "$invalid_utf8 used ${invalid_utf8_probes:-0} probes"
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
  fix_wave_not_contains "$output" 'atlassianUserInfo'
done

printf '%s\n' nested-extension-before-tools \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Authentication: PASS'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'nested extension corrupted Codex auth extraction'
fi
fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
fix_wave_not_contains "$output" 'codex mcp login atlassian'
fix_wave_not_contains "$output" 'OAuth URL:'
fix_wave_not_contains "$output" 'atlassianUserInfo'

unset FAKE_CODEX_WAIT_FOR_ESCAPED

for malformed_reauth in \
  malformed-reauth-missing-comma \
  malformed-reauth-illegal-escape \
  malformed-reauth-trailing-member \
  malformed-reauth-trailing-token
do
  printf '%s\n' "$malformed_reauth" >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_fail "$malformed_reauth passed Codex setup"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
  fix_wave_not_contains "$output" 'reauthenticationRequired'
done

export FAKE_CODEX_WAIT_FOR_ERROR=1
for terminal_error_response in \
  pure-error \
  pure-error-null \
  pure-error-string \
  pure-error-array \
  pure-error-number \
  pure-error-bool \
  dual-result-error \
  dual-result-error-null \
  dual-result-error-string \
  dual-result-error-array \
  dual-result-error-number \
  dual-result-error-bool \
  neither-result-nor-error
do
  rm -f "$XDG_CONFIG_HOME/fake-codex-error-probes"
  printf '%s\n' "$terminal_error_response" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_fail "$terminal_error_response passed Codex setup"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  error_probes=$(sed -n '1p' \
    "$XDG_CONFIG_HOME/fake-codex-error-probes" 2>/dev/null || :)
  [ "$error_probes" = 1 ] ||
    fix_wave_fail \
      "$terminal_error_response used ${error_probes:-0} probes"
  fix_wave_not_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
  fix_wave_not_contains "$output" 'createJiraIssue'
done
unset FAKE_CODEX_WAIT_FOR_ERROR

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

printf '%s\n' healthy-empty-tools >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI setup-connectors --client codex --non-interactive)
fix_wave_contains "$output" 'Authentication: PASS'
fix_wave_contains "$output" 'Result: PASS'
fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
fix_wave_not_contains "$output" 'codex mcp login atlassian'

for unusable_tool_map in \
  healthy-array-tools \
  healthy-null-tools \
  healthy-missing-tools
do
  printf '%s\n' "$unusable_tool_map" >"$XDG_CONFIG_HOME/fake-codex-health"
  output=$($CLI setup-connectors --client codex --non-interactive)
  fix_wave_contains "$output" 'Authentication: PASS'
  fix_wave_contains "$output" 'Result: PASS'
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
done

for malformed_response in \
  healthy-malformed-envelope-missing-comma \
  healthy-malformed-record-illegal-escape \
  healthy-malformed-record-missing-comma \
  malformed-nested-extension-before-tools \
  healthy-malformed-envelope-trailing-object \
  healthy-malformed-envelope-trailing-member \
  healthy-malformed-envelope-trailing-member-spaced \
  healthy-malformed-envelope-trailing-member-whitespace
do
  printf '%s\n' "$malformed_response" >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI setup-connectors --client codex --non-interactive 2>&1)
  then
    fix_wave_fail "$malformed_response passed Codex setup"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
  fix_wave_not_contains "$output" 'createJiraIssue'
done

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
printf 'cursor-agent %s | %s\n' "$*" "$PWD" >>"$CALLS"
case "$*" in
  'mcp login --help') exit 0 ;;
  'mcp login atlassian')
    printf '%s\n' \
      'OAuth URL: https://auth.example.test/cursor-first-run'
    case "$(sed -n '1p' \
      "$XDG_CONFIG_HOME/fake-cursor-health" 2>/dev/null || :)" in
      login-failed) exit 1 ;;
      post-login-unknown) ;;
      *) printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health" ;;
    esac
    ;;
  'mcp list')
    if [ "$PWD" = "$HOME" ]; then
      printf '%s\n' 'atlassian: not loaded (needs approval)'
      exit 0
    fi
    health=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-cursor-health" 2>/dev/null || :)
    case "$health" in
      healthy) printf '%s\n' 'atlassian: Ready' ;;
      ready-tools-failed) printf '%s\n' 'atlassian: Ready' ;;
      auth-required|'') printf '%s\n' 'atlassian: Authentication required' ;;
      failed) printf '%s\n' 'atlassian: Failed' ;;
      first-run-unknown|post-login-unknown) ;;
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
global_cursor_file=$HOME/.cursor/mcp.json
printf '%s\n' '{"other":{"preserved":true}}' >"$global_cursor_file"
global_before=$(cat "$global_cursor_file")
: >"$CALLS"

if output=$($CLI setup-connectors --client cursor \
  --non-interactive 2>&1)
then
  fail 'non-interactive Cursor first-run passed without global MCP'
fi
assert_contains "$output" \
  'Remediation: beroka-governance setup-connectors --client cursor'
[ "$(cat "$global_cursor_file")" = "$global_before" ] ||
  fail 'non-interactive Cursor first-run changed global MCP'
assert_not_contains "$(cat "$CALLS")" 'mcp login atlassian'

CURSOR_PROJECT=$TEST_ROOT/cursor-project
mkdir -p "$CURSOR_PROJECT/.cursor"
git init -q "$CURSOR_PROJECT"
project_cursor_file=$CURSOR_PROJECT/.cursor/mcp.json
printf '%s\n' \
  '{"mcpServers":{"atlassian":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}}}' \
  >"$project_cursor_file"
project_before=$(cat "$project_cursor_file")
: >"$CALLS"
if output=$(cd "$CURSOR_PROJECT" &&
  $CLI setup-connectors --client cursor --non-interactive 2>&1)
then
  fail 'project Cursor MCP passed without a global MCP'
fi
assert_contains "$output" 'Project MCP: PRESENT_IGNORED'
[ "$(cat "$project_cursor_file")" = "$project_before" ] ||
  fail 'Cursor setup changed project MCP'
[ "$(cat "$global_cursor_file")" = "$global_before" ] ||
  fail 'project MCP caused a global write'

printf '%s\n' first-run-unknown >"$XDG_CONFIG_HOME/fake-cursor-health"
: >"$CALLS"
output=$(printf 'y\n' |
  script -qec "$CLI setup-connectors --client cursor" /dev/null 2>&1)
assert_contains "$output" \
  'Install global Atlassian MCP and start OAuth now? [y/N]'
assert_contains "$output" \
  'OAuth URL: https://auth.example.test/cursor-first-run'
assert_contains "$output" 'Result: PASS'
jq -e '.other.preserved == true' "$global_cursor_file" >/dev/null ||
  fail 'Cursor first-run discarded unrelated global JSON'
jq -e --arg url 'https://mcp.atlassian.com/v1/mcp/authv2' \
  '.mcpServers.atlassian.url == $url' "$global_cursor_file" >/dev/null ||
  fail 'Cursor first-run omitted the global Atlassian MCP'
login_line=$(nl -ba "$CALLS" |
  awk '/cursor-agent mcp login atlassian/{print $1; exit}')
list_line=$(nl -ba "$CALLS" |
  awk '/cursor-agent mcp list( \||$)/{print $1; exit}')
[ -n "$login_line" ] && [ -n "$list_line" ] &&
  [ "$login_line" -lt "$list_line" ] ||
  fail 'Cursor first-run checked health before OAuth'

printf '%s\n' '{"other":{"preserved":true}}' >"$global_cursor_file"
printf '%s\n' first-run-unknown >"$XDG_CONFIG_HOME/fake-cursor-health"
: >"$CALLS"
decline_before=$(cat "$global_cursor_file")
if decline_output=$(printf 'n\n' |
  script -qec "$CLI setup-connectors --client cursor" /dev/null 2>&1)
then
  fail 'Cursor first-run accepted declined global MCP installation'
fi
assert_contains "$decline_output" 'Result: ATLASSIAN_AUTH_REQUIRED'
[ "$(cat "$global_cursor_file")" = "$decline_before" ] ||
  fail 'declined Cursor first-run changed global MCP'
assert_not_contains "$(cat "$CALLS")" 'mcp login atlassian'

printf '%s\n' '{invalid JSON' >"$global_cursor_file"
if invalid_output=$($CLI setup-connectors --client cursor --non-interactive 2>&1)
then
  fail 'Cursor first-run accepted invalid global JSON'
fi
assert_contains "$invalid_output" 'Result: GOVERNANCE_NOT_READY'

printf '%s\n%s\n' '{"other":{"first":true}}' '{"other":{"second":true}}' \
  >"$global_cursor_file"
multi_object_before=$(cat "$global_cursor_file")
if multi_object_output=$(
  $CLI setup-connectors --client cursor --non-interactive 2>&1
)
then
  fix_wave_fail 'Cursor first-run accepted multiple top-level JSON objects'
fi
fix_wave_contains "$multi_object_output" 'Result: GOVERNANCE_NOT_READY'
[ "$(cat "$global_cursor_file")" = "$multi_object_before" ] ||
  fix_wave_fail 'multi-object Cursor config changed before rejection'

printf '%s\n' '{"other":{"preserved":true}}' >"$global_cursor_file"
printf '%s\n' first-run-unknown >"$XDG_CONFIG_HOME/fake-cursor-health"
: >"$CALLS"
race_input=$TEST_ROOT/cursor-race-input
race_output=$TEST_ROOT/cursor-race-output
mkfifo "$race_input"
script -qec "$CLI setup-connectors --client cursor" /dev/null \
  <"$race_input" >"$race_output" 2>&1 &
race_pid=$!
exec 3>"$race_input"
race_waits=0
while ! grep -F \
  'Install global Atlassian MCP and start OAuth now? [y/N]' \
  "$race_output" >/dev/null 2>&1
do
  [ "$race_waits" -lt 100 ] ||
    fail 'Cursor first-run mutation test did not reach its prompt'
  /bin/sleep 0.01
  race_waits=$((race_waits + 1))
done
printf '%s\n' \
  '{"mcpServers":{"atlassian":{"url":"https://example.invalid/race"}}}' \
  >"$global_cursor_file"
race_before=$(cat "$global_cursor_file")
printf 'y\n' >&3
exec 3>&-
race_status=0
wait "$race_pid" || race_status=$?
race_output_text=$(cat "$race_output")
[ "$race_status" -ne 0 ] ||
  fix_wave_fail 'Cursor first-run overwrote a mutation-time conflict'
fix_wave_contains "$race_output_text" 'Result: CONNECTOR_MISSING'
[ "$(cat "$global_cursor_file")" = "$race_before" ] ||
  fix_wave_fail 'Cursor first-run changed a mutation-time conflict'
fix_wave_not_contains "$(cat "$CALLS")" 'mcp login atlassian'

printf '%s\n' '{"other":{"preserved":true}}' >"$global_cursor_file"
printf '%s\n' login-failed >"$XDG_CONFIG_HOME/fake-cursor-health"
if login_failed_output=$(printf 'y\n' |
  script -qec "$CLI setup-connectors --client cursor" /dev/null 2>&1)
then
  fail 'Cursor first-run accepted failed OAuth login'
fi
assert_contains "$login_failed_output" 'Result: AUTH_PENDING'

printf '%s\n' '{"other":{"preserved":true}}' >"$global_cursor_file"
printf '%s\n' post-login-unknown >"$XDG_CONFIG_HOME/fake-cursor-health"
if post_login_output=$(printf 'y\n' |
  script -qec "$CLI setup-connectors --client cursor" /dev/null 2>&1)
then
  fail 'Cursor first-run accepted unknown post-login health'
fi
assert_contains "$post_login_output" \
  'Result: CONNECTOR_HEALTH_UNAVAILABLE'

printf '%s\n' \
  '{"mcpServers":{"atlassian":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}}}' \
  >"$global_cursor_file"

assert_not_contains "$(cat "$CALLS")" 'claude '
assert_not_contains "$(cat "$CALLS")" 'codex '

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-cursor-health"
: >"$CALLS"
if output=$(cd "$HOME" &&
  $CLI setup-connectors --client cursor --non-interactive 2>&1)
then
  fail 'Cursor HOME setup accepted missing authentication'
fi
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$output" 'CONNECTOR_HEALTH_UNAVAILABLE'
if grep '^cursor-agent mcp ' "$CALLS" |
  grep -Ev ' \| /$' >/dev/null
then
  fail 'governance ran Cursor MCP outside the neutral directory'
fi

printf '%s\n' '{"mcpServers":{"atlassian":{"url":"https://example.invalid/mcp"}}}' \
  >"$global_cursor_file"
if output=$($CLI setup-connectors --client cursor --non-interactive 2>&1); then
  fail 'Cursor setup overwrote a conflicting connector'
fi
assert_contains "$output" 'Result: CONNECTOR_MISSING'
assert_contains "$(cat "$global_cursor_file")" 'https://example.invalid/mcp'

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
if output=$($CLI setup-connectors --client cursor --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Connector: PASS'
  fix_wave_contains "$output" 'Authentication: PASS'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'Cursor setup rejected Ready with unavailable tool inventory'
fi
fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
fix_wave_not_contains "$output" 'cursor-agent mcp login atlassian'
fix_wave_not_contains "$output" 'OAuth URL:'
fix_wave_not_contains "$output" 'Tool inventory failed'

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-cursor-health"
: >"$CALLS"
output=$(printf 'y\n' | script -qec "$CLI setup-connectors --client cursor" /dev/null 2>&1)
assert_contains "$output" 'Result: PASS'
assert_contains "$(cat "$CALLS")" 'cursor-agent mcp login atlassian'
assert_contains "$(cat "$CALLS")" 'cursor-agent mcp login atlassian | /'

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
printf '%s\n' 'Managed Cursor user rule test content.' \
  >"$RELEASE_SOURCE/templates/agent-entrypoints/CURSOR-USER-RULE.txt"
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
mkdir -p "$XDG_CONFIG_HOME/beroka-ai-governance"
printf '%s\n' \
  "VERSION=$RELEASE_VERSION" \
  "COMMIT=$RELEASE_COMMIT" \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/active-release"
printf '%s\n' codex,cursor \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"
mkdir -p "$HOME/.codex"
cp "$RELEASE_DIR/templates/agent-entrypoints/AGENTS.md" \
  "$HOME/.codex/AGENTS.md"
git --git-dir=/dev/null hash-object --no-filters \
  "$RELEASE_DIR/templates/agent-entrypoints/CURSOR-USER-RULE.txt" \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"
cp "$CLI" "$BEROKA_GOV_BIN_DIR/beroka-governance"
chmod 755 "$BEROKA_GOV_BIN_DIR/beroka-governance"
jq -nc --arg cli "$BEROKA_GOV_BIN_DIR/beroka-governance" '
  {hooks:{
    sessionStart:[{command:($cli + " cursor-hook sessionStart")}],
    beforeSubmitPrompt:[{command:($cli + " cursor-hook beforeSubmitPrompt")}],
    preCompact:[{command:($cli + " cursor-hook preCompact")}],
    beforeMCPExecution:[{command:($cli + " cursor-hook beforeMCPExecution"),failClosed:true}],
    beforeShellExecution:[{command:($cli + " cursor-hook beforeShellExecution"),failClosed:true}]
  }}' >"$HOME/.cursor/hooks.json"

git -C "$CONSUMER" init -q
git -C "$CONSUMER" config user.name 'Beroka Test'
git -C "$CONSUMER" config user.email 'test@example.invalid'
printf '%s\n' '# Consumer' >"$CONSUMER/README.md"
git -C "$CONSUMER" add README.md
git -C "$CONSUMER" commit -qm 'test consumer'
git -C "$CONSUMER" remote add origin \
  https://github.com/beroka-vn/consumer.git

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

printf '%s\n' healthy-empty-tools >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI doctor "$CONSUMER" --client codex)
assert_contains "$output" 'Connector: PASS'
assert_contains "$output" 'Authentication: PASS'
assert_contains "$output" 'Result: PASS'
assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$output" 'codex mcp login atlassian'

for unusable_tool_map in \
  healthy-array-tools \
  healthy-null-tools \
  healthy-missing-tools
do
  printf '%s\n' "$unusable_tool_map" >"$XDG_CONFIG_HOME/fake-codex-health"
  output=$($CLI doctor "$CONSUMER" --client codex)
  assert_contains "$output" 'Connector: PASS'
  assert_contains "$output" 'Authentication: PASS'
  assert_contains "$output" 'Result: PASS'
  assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$output" 'codex mcp login atlassian'
  assert_not_contains "$output" 'OAuth URL:'
done

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

printf '%s\n' ready-tools-failed >"$XDG_CONFIG_HOME/fake-cursor-health"
if output=$($CLI doctor "$CONSUMER" --client cursor 2>&1)
then
  fix_wave_contains "$output" 'Connector: PASS'
  fix_wave_contains "$output" 'Authentication: PASS'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'Cursor Doctor rejected Ready with unavailable tool inventory'
fi
fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
fix_wave_not_contains "$output" 'cursor-agent mcp login atlassian'
fix_wave_not_contains "$output" 'OAuth URL:'
fix_wave_not_contains "$output" 'Tool inventory failed'

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
grep -F 'enroll another client there.' "$ROOT/README.md" >/dev/null ||
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
