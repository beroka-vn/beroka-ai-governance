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

fix_wave_not_contains() {
  case "$1" in
    *"$2"*) fix_wave_fail "did not expect [$2] in [$1]" ;;
    *) ;;
  esac
}

cat >"$FAKE_BIN/sleep" <<'EOF'
#!/bin/sh
set -eu
if [ "${FAKE_CODEX_WAIT_FOR_UTF8_SPLIT:-0}" = 1 ]; then
  split_polls=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-split-polls" 2>/dev/null || :)
  split_polls=${split_polls:-0}
  split_polls=$((split_polls + 1))
  printf '%s\n' "$split_polls" >"$XDG_CONFIG_HOME/fake-codex-split-polls"
  if [ "$split_polls" -eq 1 ]; then split_marker=$XDG_CONFIG_HOME/fake-codex-split-first
  else split_marker=$XDG_CONFIG_HOME/fake-codex-split-complete
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
fi
exit 0
EOF

cat >"$FAKE_BIN/codex" <<'EOF'
#!/bin/sh
set -eu
printf 'codex %s\n' "$*" >>"$CALLS"
case "$*" in
  '--version') printf 'codex %s\n' "${FAKE_CODEX_VERSION:-1.0.0}" ;;
  'mcp login --help'|'app-server --help') ;;
  'mcp get atlassian --json')
    [ -f "$XDG_CONFIG_HOME/fake-codex-configured" ] || exit 1
    printf '%s\n' '{"name":"atlassian","url":"https://mcp.atlassian.com/v1/mcp/authv2"}'
    ;;
  'mcp login atlassian')
    printf '%s\n' "${FAKE_CODEX_OAUTH_HEALTH:-healthy-all}" \
      >"$XDG_CONFIG_HOME/fake-codex-health"
    ;;
  'app-server --stdio')
    while IFS= read -r input; do
      case "$input" in
      *'mcpServerStatus/list'*)
        health=$(sed -n '1p' "$XDG_CONFIG_HOME/fake-codex-health" 2>/dev/null || :)
        case "$health" in
          healthy-all)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-rpc-extensions)
            printf '%s\n' '{"jsonrpc":"2.0","id":1,"trace-id":"abc","key with space":true,"escaped\u002dextension":null,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
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
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
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
            printf '%s\n' '{"id":1,"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          duplicate-rpc-result)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]},"result":{}}'
            ;;
          duplicate-rpc-error)
            printf '%s\n' '{"id":1,"error":null,"error":{"code":-32603,"message":"failed"}}'
            ;;
          escaped-id-one-result)
            printf '%s\n' '{"\u0069\u0064":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          escaped-result-only)
            printf '%s\n' '{"id":1,"\u0072esult":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          escaped-error-with-result)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]},"e\u0072ror":null}'
            ;;
          escaped-id-conflict-with-result)
            printf '%s\n' '{"id":1,"i\u0064":2,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          escaped-result-with-error)
            printf '%s\n' '{"id":1,"\u0072esult":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]},"error":null}'
            ;;
          semantic-duplicate-result)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]},"r\u0065sult":{}}'
            ;;
          semantic-duplicate-error)
            printf '%s\n' '{"id":1,"error":null,"e\u0072ror":{"code":-32603,"message":"failed"}}'
            ;;
          escaped-wrapper-keys)
            printf '%s\n' '{"id":1,"result":{"d\u0061ta":[{"n\u0061me":"atlassian","t\u006fols":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authSt\u0061tus":"oAuth"}]}}'
            ;;
          semantic-duplicate-data)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}],"d\u0061ta":[]}}'
            ;;
          semantic-duplicate-name)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","n\u0061me":"other","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          semantic-duplicate-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"t\u006fols":{},"authStatus":"oAuth"}]}}'
            ;;
          semantic-duplicate-auth-status)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"searchJiraIssuesUsingJql":{},"getJiraProjectIssueTypesMetadata":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth","authSt\u0061tus":"notLoggedIn"}]}}'
            ;;
          raw-nul-response)
            printf '%s\000%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' \
              'after","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          escaped-nul-text)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before\u0000after","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          nested-extension-before-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","extension":{"nested":[{"text":"close } open { square ] [ escaped \" quote and \\ backslash"},["}",{"deeper":"{ [ ] }"}]]},"tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          malformed-nested-extension-before-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","extension":{"nested":[{"text":"invalid\qescape"}]},"tools":{"createJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          valid-raw-unicode)
            printf '%s\302\242\342\202\254\360\220\215\210%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","note":"ASCII ' \
              '","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          split-utf8-3)
            printf '%s\342' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before'
            : >"$XDG_CONFIG_HOME/fake-codex-split-first"
            /bin/sleep 0.08
            printf '\202\254%s\n' 'after","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            : >"$XDG_CONFIG_HOME/fake-codex-split-complete"
            ;;
          invalid-utf8-continuation)
            printf '%s\200%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"createJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-ff-fe)
            printf '%s\377\376%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"createJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-overlong)
            printf '%s\300\200%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"createJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-surrogate)
            printf '%s\355\240\200%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"createJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-too-high)
            printf '%s\364\220\200\200%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"createJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          invalid-utf8-truncated)
            printf '%s\342\202%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","note":"before' 'after","tools":{"createJiraIssue":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-empty-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{},"authStatus":"oAuth"}]}}'
            ;;
          healthy-array-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":[],"authStatus":"oAuth"}]}}'
            ;;
          healthy-null-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":null,"authStatus":"oAuth"}]}}'
            ;;
          healthy-missing-tools)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","authStatus":"oAuth"}]}}'
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
          healthy-valid-nested-tool-values)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{"metadata":{"description":"brace } and escaped \" quote","values":[1,-2.5e+3,true,false,null,{"nested":[]}]}},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-valid-del-string)
            printf '%s\177%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{"metadata":{"description":"before' \
              'after"}},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-valid-json-whitespace)
            printf '%s \t\r%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{"metadata":' \
              '{"enabled":true}},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-malformed-tool-value)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":"not-an-object","getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-malformed-nested-tool-object)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{"metadata":,},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-malformed-nested-tool-array)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{"metadata":[1,,2]},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-invalid-c0-string)
            printf '%s\037%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{"metadata":{"description":"before' \
              'after"}},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-nested-vertical-tab-whitespace)
            printf '%s\013%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{"metadata":' \
              '{"enabled":true}},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-nested-form-feed-whitespace)
            printf '%s\014%s\n' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{"metadata":' \
              '{"enabled":true}},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-duplicate-required-tool)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-escaped-duplicate-required-tool)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"create\u004airaIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-missing-jira-metadata)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-missing-confluence-read)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-missing-resource-discovery)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          healthy-missing-jql)
            printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
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
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}'
            ;;
          dual-result-error|dual-result-error-null|\
          dual-result-error-string|dual-result-error-array|\
          dual-result-error-number|dual-result-error-bool)
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
          auth-required|'')
            printf '%s\n' \
              '{"method":"mcpServer/startupStatus/updated","params":{"name":"atlassian","failureReason":"reauthenticationRequired"}}' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{},"authStatus":"oAuth"}]}}'
            ;;
          refresh-token-invalid)
            printf '%s\n' \
              '2026-07-31T03:04:05.000Z ERROR codex_rmcp_client::oauth::refresh_transaction: error=failed to refresh OAuth tokens for server atlassian: OAuth token refresh failed: Server returned error response: unauthorized_client: refresh_token is invalid' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{},"authStatus":"oAuth"}]}}'
            ;;
          refresh-token-invalid-other-server)
            printf '%s\n' \
              '2026-07-31T03:04:05.000Z ERROR codex_rmcp_client::oauth::refresh_transaction: error=failed to refresh OAuth tokens for server github: OAuth token refresh failed: Server returned error response: unauthorized_client: refresh_token is invalid' \
              '{"id":1,"result":{"data":[{"name":"atlassian","tools":{},"authStatus":"oAuth"}]}}'
            ;;
          auth-401) printf '%s\n' 'server atlassian: 401 Unauthorized' ;;
          auth-403) printf '%s\n' 'server atlassian: 403 Forbidden' ;;
          *) exit 1 ;;
        esac
        ;;
        *) ;;
      esac
    done
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$FAKE_BIN/ssh" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = -G ] && [ "$2" = github.com-work ]; then
  printf '%s\n' 'hostname github.com'
  exit 0
fi
if [ "$1" = -G ]; then
  printf '%s\n' 'hostname git.example.invalid'
  exit 0
fi
exit 64
EOF
chmod +x "$FAKE_BIN/ssh"

cat >"$FAKE_BIN/claude" <<'EOF'
#!/bin/sh
set -eu
printf 'claude %s\n' "$*" >>"$CALLS"
case "$*" in
  '--version')
    printf '%s (Claude Code)\n' "${FAKE_CLAUDE_VERSION:-1.2.3}"
    ;;
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
  '--version')
    printf 'cursor-agent %s\n' "${FAKE_CURSOR_VERSION:-1.0.0}"
    ;;
  'mcp login --help') ;;
  'mcp login atlassian')
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
    ;;
  'mcp list')
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-cursor-health" 2>/dev/null || :)" in
      empty|healthy|description-prefixes|legacy-free-text|missing|prose-only|ready-tools-failed|similar|trailing-prose)
        printf '%s\n' 'atlassian: Ready'
        ;;
      auth-required|'') printf '%s\n' 'atlassian: Authentication required' ;;
      *) printf '%s\n' 'atlassian: Failed' ;;
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
      description-prefixes)
        printf '%s\n' \
          'createJiraIssue is configured for another server' \
          'getAccessibleAtlassianResources: configuration only' \
          'getJiraIssue: configuration example only' \
          'getJiraIssueTypeMetaWithFields is mentioned in prose' \
          'getJiraProjectIssueTypesMetadata: description only' \
          'searchJiraIssuesUsingJql is mentioned in prose' \
          'searchConfluenceUsingCql(query)'
        ;;
      empty) : ;;
      prose-only)
        printf '%s\n' \
          'No tools are declared' \
          'Configuration is empty'
        ;;
      legacy-free-text)
        printf '%s\n' \
          'createConfluencePage(spaceKey, title)' \
          'description: createJiraIssue then getJiraIssue' \
          'getConfluencePage(pageId)' \
          'getJiraIssueTypeMetaWithFields(projectKey, issueType)' \
          'getJiraProjectIssueTypesMetadata(projectKey)'
        ;;
      similar)
        printf '%s\n' \
          'createJiraIssuePreview(projectKey)' \
          'description: call getJiraIssue after creation'
        ;;
      trailing-prose)
        printf '%s\n' \
          '- createJiraIssue (projectKey, issueType, summary) creates an issue' \
          '- getAccessibleAtlassianResources () lists sites' \
          '- getJiraIssue (issueKey) reads an issue' \
          '- getJiraIssueTypeMetaWithFields (projectKey, issueType) lists fields' \
          '- getJiraProjectIssueTypesMetadata (projectKey) lists issue types' \
          '- searchJiraIssuesUsingJql (cloudId, jql) searches issues'
        ;;
      missing) printf '%s\n' 'getJiraIssue(issueKey)' ;;
      ready-tools-failed)
        printf '%s\n' 'Tool inventory failed'
        exit 1
        ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$FAKE_BIN/gh" <<'EOF'
#!/bin/sh
set -eu
printf 'gh %s\n' "$*" >>"$CALLS"
case "$*" in
  'auth status --help'|'auth login --help'|'api --help') exit 0 ;;
  'auth status --hostname github.com')
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-github-health" 2>/dev/null || :)" in
      healthy) exit 0 ;;
      unknown)
        printf '%s\n' 'network unavailable' >&2
        exit 1
        ;;
      *)
        printf '%s\n' 'You are not logged into any GitHub hosts.' >&2
        exit 1
        ;;
    esac
    ;;
  'auth login --hostname github.com --web')
    printf '%s\n' 'OAuth URL: https://github.com/login/device'
    printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-github-health"
    ;;
  'api --paginate /user/teams')
    case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-github-teams" 2>/dev/null || :)" in
      frontend)
        printf '%s\n' \
          '[{"slug":"frontend","organization":{"login":"beroka-vn"}}]'
        ;;
      backend)
        printf '%s\n' \
          '[{"slug":"backend","organization":{"login":"beroka-vn"}}]'
        ;;
      both)
        printf '%s\n' \
          '[{"slug":"frontend","organization":{"login":"beroka-vn"}},{"slug":"backend","organization":{"login":"beroka-vn"}}]'
        ;;
      neither) printf '%s\n' '[]' ;;
      malformed-json) printf '%s\n' '{' ;;
      non-array) printf '%s\n' '{}' ;;
      missing-login)
        printf '%s\n' '[{"slug":"frontend","organization":{}}]'
        ;;
      non-string-login)
        printf '%s\n' \
          '[{"slug":"frontend","organization":{"login":29}}]'
        ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
chmod 755 "$FAKE_BIN/sleep" "$FAKE_BIN/codex" "$FAKE_BIN/claude" \
  "$FAKE_BIN/cursor-agent" "$FAKE_BIN/gh"
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
catalog=$source_repo/runtime/repositories/beroka-vn
mkdir -p "$catalog"
cat >"$catalog/routing-consumer.conf" <<'EOF'
SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only
EOF
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
git -c advice.detachedHead=false clone -q --depth 1 --branch v1.1.0 \
  https://github.com/beroka-vn/beroka-ai-governance.git "$release_dir"
release_commit=$(git -C "$release_dir" rev-parse HEAD)
mkdir -p "$XDG_CONFIG_HOME/beroka-ai-governance"
printf '%s\n' \
  'VERSION=v1.1.0' \
  "COMMIT=$release_commit" \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/active-release"
printf '%s\n' codex,claude,cursor \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"
mkdir -p "$HOME/.codex" "$HOME/.claude"
cp "$release_dir/templates/agent-entrypoints/AGENTS.md" \
  "$HOME/.codex/AGENTS.md"
cp "$release_dir/templates/agent-entrypoints/CLAUDE.md" \
  "$HOME/.claude/CLAUDE.md"
git --git-dir=/dev/null hash-object --no-filters \
  "$release_dir/templates/agent-entrypoints/CURSOR-USER-RULE.txt" \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"

consumer=$TEST_ROOT/consumer
new_repo "$consumer"
git -C "$consumer" remote add upstream \
  https://github.com/beroka-vn/routing-consumer.git
git -C "$consumer" fetch -q upstream trunk
git -C "$consumer" switch -qc trunk FETCH_HEAD

before=$(snapshot_repo "$consumer")
output=$($CLI context "$consumer")
after=$(snapshot_repo "$consumer")

[ "$before" = "$after" ] ||
  fail 'context changed application repository state'
assert_contains "$output" 'Routing: ROUTING_ACTIVE'
assert_contains "$output" 'Routing source: central catalog'

unknown_repo=$TEST_ROOT/unknown-repo
new_repo "$unknown_repo"
printf '%s\n' '# unknown' >"$unknown_repo/README.md"
git -C "$unknown_repo" add README.md
git -C "$unknown_repo" commit -qm 'test: initialize unknown application'
git -C "$unknown_repo" remote add origin \
  https://github.com/beroka-vn/unknown-repo.git
unknown_output=$($CLI context "$unknown_repo")
assert_contains "$unknown_output" 'Routing: ROUTING_REQUIRED'
assert_contains "$unknown_output" 'Dependency state: NO_DEPENDENCY_DECLARED'
assert_contains "$unknown_output" 'Cross-repository policy: explicit-only'
assert_not_contains "$unknown_output" '# BE/FE Work Items'

backend_repo=$TEST_ROOT/backend-repo
new_repo "$backend_repo"
git -C "$backend_repo" remote add origin \
  https://github.com/cuongngo1801-beroka/Beroka_Backend.git
role_file=$XDG_CONFIG_HOME/beroka-ai-governance/github-role
printf '%s\n' FULL_STACK >"$role_file"
backend_output=$($CLI context "$backend_repo")
assert_contains "$backend_output" \
  'Repository: cuongngo1801-beroka/Beroka_Backend'
assert_contains "$backend_output" 'Routing: ROUTING_ACTIVE'
assert_contains "$backend_output" 'Profile: backend'
assert_contains "$backend_output" 'Jira project: BB'
assert_contains "$backend_output" 'Jira board: 34'
assert_contains "$backend_output" 'Confluence space: Berokaback'
assert_contains "$backend_output" 'Confluence root content: 65962274'
assert_contains "$backend_output" '# BE/FE Work Items'

frontend_repo=$TEST_ROOT/frontend-repo
new_repo "$frontend_repo"
git -C "$frontend_repo" remote add origin \
  https://github.com/cuongngo1801-beroka/Beroka_Frontend.git
frontend_output=$($CLI context "$frontend_repo")
assert_contains "$frontend_output" \
  'Repository: cuongngo1801-beroka/Beroka_Frontend'
assert_contains "$frontend_output" 'Routing: ROUTING_ACTIVE'
assert_contains "$frontend_output" 'Profile: frontend'
assert_contains "$frontend_output" 'Jira project: BF'
assert_contains "$frontend_output" 'Jira board: 35'
assert_contains "$frontend_output" 'Confluence space: Berokafron'
assert_contains "$frontend_output" 'Confluence root content: 65831203'
assert_contains "$frontend_output" '# BE/FE Work Items'

canonical_backend=$TEST_ROOT/canonical-backend
new_repo "$canonical_backend"
git -C "$canonical_backend" remote add origin \
  https://github.com/beroka-vn/Beroka_Backend.git
canonical_backend_output=$($CLI context "$canonical_backend")
assert_contains "$canonical_backend_output" \
  'Repository: beroka-vn/Beroka_Backend'
assert_contains "$canonical_backend_output" 'Routing: ROUTING_ACTIVE'
assert_contains "$canonical_backend_output" 'Jira project: BB'

canonical_frontend=$TEST_ROOT/canonical-frontend
new_repo "$canonical_frontend"
git -C "$canonical_frontend" remote add origin \
  https://github.com/beroka-vn/Beroka_Frontend.git
canonical_frontend_output=$($CLI context "$canonical_frontend")
assert_contains "$canonical_frontend_output" \
  'Repository: beroka-vn/Beroka_Frontend'
assert_contains "$canonical_frontend_output" 'Routing: ROUTING_ACTIVE'
assert_contains "$canonical_frontend_output" 'Jira project: BF'

printf '%s\n' FE >"$role_file"
if output=$($CLI context "$canonical_backend" 2>&1); then
  fail 'FE role loaded Backend routing'
fi
assert_contains "$output" 'Result: ROLE_SCOPE_DENIED'
assert_not_contains "$output" 'Jira project: BB'
assert_contains "$($CLI context "$canonical_frontend")" 'Jira project: BF'

printf '%s\n' BE >"$role_file"
if output=$($CLI context "$canonical_frontend" 2>&1); then
  fail 'BE role loaded Frontend routing'
fi
assert_contains "$output" 'Result: ROLE_SCOPE_DENIED'
assert_not_contains "$output" 'Jira project: BF'
assert_contains "$($CLI context "$canonical_backend")" 'Jira project: BB'

rm -f "$role_file"
if output=$($CLI context "$canonical_backend" 2>&1); then
  fail 'Backend routing loaded without a GitHub role'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_REQUIRED'

for cross_repo_role in missing FE FULL_STACK; do
  case "$cross_repo_role" in
    missing) rm -f "$role_file" ;;
    *) printf '%s\n' "$cross_repo_role" >"$role_file" ;;
  esac
  : >"$CALLS"
  if output=$($CLI preflight "$canonical_backend" --client codex \
    --operation cross-repo-write --non-interactive 2>&1)
  then
    fail "cross-repo write passed with $cross_repo_role role"
  fi
  assert_contains "$output" 'Result: ROUTING_REQUIRED'
  [ ! -s "$CALLS" ] ||
    fail "cross-repo routing inspected a client with $cross_repo_role role"
done

printf '%s\n' FULL_STACK >"$role_file"
printf '%s\n' both >"$XDG_CONFIG_HOME/fake-github-teams"

git -C "$consumer" remote set-url upstream \
  git@github.com-work:beroka-vn/routing-consumer.git
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_ACTIVE'
assert_contains "$output" 'Routing source: central catalog'
git -C "$consumer" remote set-url upstream \
  git@github.com-not-work:beroka-vn/routing-consumer.git
if output=$($CLI context "$consumer" 2>&1); then
  fail 'SSH alias resolving outside github.com was accepted'
fi
assert_contains "$output" 'Result: REMOTE_MISMATCH'
git -C "$consumer" remote set-url upstream \
  git@github.com-work:beroka-vn/routing-consumer.git

rm -f "$XDG_CONFIG_HOME/fake-github-health"
: >"$CALLS"
if output=$($CLI preflight "$consumer" --client codex \
  --operation github-write --non-interactive 2>&1)
then
  fail 'non-interactive GitHub preflight accepted missing auth'
fi
assert_contains "$output" 'Provider: github'
assert_contains "$output" 'Result: GITHUB_AUTH_REQUIRED'
assert_contains "$output" \
  'Remediation: gh auth login --hostname github.com --web'
assert_not_contains "$(cat "$CALLS")" \
  'gh auth login --hostname github.com --web'

printf '%s\n' unknown >"$XDG_CONFIG_HOME/fake-github-health"
if output=$($CLI preflight "$consumer" --client codex \
  --operation github-write --non-interactive 2>&1)
then
  fail 'GitHub preflight accepted unknown auth health'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_UNAVAILABLE'

rm -f "$XDG_CONFIG_HOME/fake-github-health"
: >"$CALLS"
output=$(printf 'y\n' | script -qec \
  "$CLI preflight $consumer --client codex --operation github-write" \
  /dev/null 2>&1)
assert_contains "$output" 'OAuth URL: https://github.com/login/device'
assert_contains "$output" 'Result: PASS'
[ "$(grep -Fxc 'gh auth login --hostname github.com --web' "$CALLS")" -eq 1 ] ||
  fail 'interactive GitHub preflight did not invoke login exactly once'
if rg -l -F 'github.com/login/device' \
  "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" >/dev/null 2>&1
then
  fail 'Governance persisted the GitHub OAuth URL'
fi

: >"$CALLS"
output=$($CLI preflight "$consumer" --client codex \
  --operation github-write --non-interactive)
assert_contains "$output" 'Authentication: PASS'
assert_contains "$output" 'Result: PASS'
assert_not_contains "$(cat "$CALLS")" \
  'gh auth login --hostname github.com --web'

printf '%s\n' FE >"$role_file"
printf '%s\n' backend >"$XDG_CONFIG_HOME/fake-github-teams"
: >"$CALLS"
if output=$($CLI preflight "$canonical_frontend" --client codex \
  --operation github-write --non-interactive 2>&1)
then
  fail 'GitHub preflight accepted stale FE eligibility'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'mcp '

printf '%s\n' FULL_STACK >"$role_file"
printf '%s\n' frontend >"$XDG_CONFIG_HOME/fake-github-teams"
: >"$CALLS"
if output=$($CLI preflight "$consumer" --client codex \
  --operation github-write --non-interactive 2>&1)
then
  fail 'GitHub preflight accepted Full-stack without both Teams'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_REQUIRED'

printf '%s\n' unavailable >"$XDG_CONFIG_HOME/fake-github-teams"
: >"$CALLS"
if output=$($CLI preflight "$consumer" --client codex \
  --operation github-write --non-interactive 2>&1)
then
  fail 'GitHub preflight accepted unavailable Team verification'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_UNAVAILABLE'

for malformed_team_response in \
  malformed-json \
  non-array \
  missing-login \
  non-string-login
do
  printf '%s\n' "$malformed_team_response" \
    >"$XDG_CONFIG_HOME/fake-github-teams"
  if output=$($CLI preflight "$consumer" --client codex \
    --operation github-write --non-interactive 2>&1)
  then
    fail "$malformed_team_response Team response passed preflight"
  fi
  assert_contains "$output" 'Result: GITHUB_ROLE_UNAVAILABLE'
done

printf '%s\n' FULL_STACK >"$role_file"
printf '%s\n' both >"$XDG_CONFIG_HOME/fake-github-teams"

publish_routing() {
  pr_content=$1
  printf '%s\n' "$pr_content" >"$catalog/routing-consumer.conf"
  PUBLISH_SERIAL=$((PUBLISH_SERIAL + 1))
  pin_test_release "v1.2.$PUBLISH_SERIAL"
}

assert_catalog_invalid() {
  publish_routing "$1"
  if output=$($CLI context "$consumer" 2>&1); then
    fail 'invalid catalog record passed release validation'
  fi
  assert_contains "$output" 'Result: VERSION_MISMATCH'
  assert_contains "$output" 'Invalid repository catalog record'
}

pin_test_release() {
  ptr_version=$1
  printf '%s\n' "$ptr_version" >"$source_repo/VERSION"
  git -C "$source_repo" add VERSION runtime/compatibility/atlassian.tsv \
    runtime/repositories
  git -C "$source_repo" commit -qm "test: create $ptr_version release"
  git -C "$source_repo" tag -a "$ptr_version" -m "$ptr_version"
  ptr_release=$XDG_DATA_HOME/beroka-ai-governance/releases/$ptr_version
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$ptr_version" \
    https://github.com/beroka-vn/beroka-ai-governance.git "$ptr_release"
  ptr_commit=$(git -C "$ptr_release" rev-parse HEAD)
  printf '%s\n' \
    "VERSION=$ptr_version" \
    "COMMIT=$ptr_commit" \
    >"$XDG_CONFIG_HOME/beroka-ai-governance/active-release"
}

PUBLISH_SERIAL=0

: >"$CALLS"
output=$($CLI preflight "$consumer" --client codex \
  --operation github-write --non-interactive)
assert_contains "$output" 'Result: PASS'
assert_not_contains "$(cat "$CALLS")" 'mcp '

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
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$(cat "$CALLS")" 'gh api --paginate /user/teams'

printf '%s\n' healthy-rpc-extensions \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'valid JSON-RPC extension keys blocked Jira preflight'
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
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fix_wave_contains "$output" 'Capability state: SUPPORTED'
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
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fix_wave_fail "$unrelated_only passed Jira preflight"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  assert_not_contains "$output" 'Capability state: SUPPORTED'
  assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$output" 'codex mcp login atlassian'
  assert_not_contains "$output" 'OAuth URL:'
done

for duplicate_rpc_member in \
  duplicate-rpc-id \
  duplicate-rpc-result \
  duplicate-rpc-error
do
  printf '%s\n' "$duplicate_rpc_member" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fix_wave_fail "$duplicate_rpc_member passed Jira preflight"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  assert_not_contains "$output" 'Capability state: SUPPORTED'
  assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$output" 'codex mcp login atlassian'
  assert_not_contains "$output" 'OAuth URL:'
done

printf '%s\n' escaped-id-one-result \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'escaped semantic id=1 did not select Jira inventory'
fi

printf '%s\n' escaped-result-only \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'escaped semantic result did not select Jira inventory'
fi

for rejected_escaped_rpc in \
  escaped-error-with-result \
  escaped-id-conflict-with-result \
  escaped-result-with-error \
  semantic-duplicate-result \
  semantic-duplicate-error
do
  printf '%s\n' "$rejected_escaped_rpc" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fix_wave_fail "$rejected_escaped_rpc passed Jira preflight"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  fix_wave_not_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
  fix_wave_not_contains "$output" 'createJiraIssue'
done

printf '%s\n' escaped-wrapper-keys \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'escaped semantic wrapper keys did not select Jira inventory'
fi

for rejected_wrapper in \
  semantic-duplicate-data \
  semantic-duplicate-name \
  semantic-duplicate-tools \
  semantic-duplicate-auth-status \
  raw-nul-response
do
  printf '%s\n' "$rejected_wrapper" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fix_wave_fail "$rejected_wrapper passed Jira preflight"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  fix_wave_not_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
  fix_wave_not_contains "$output" 'createJiraIssue'
done

printf '%s\n' escaped-nul-text \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'escaped JSON NUL text did not select Jira inventory'
fi

printf '%s\n' valid-raw-unicode \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'valid raw UTF-8 did not select Jira inventory'
fi

for invalid_utf8 in \
  invalid-utf8-continuation \
  invalid-utf8-ff-fe \
  invalid-utf8-overlong \
  invalid-utf8-surrogate \
  invalid-utf8-too-high \
  invalid-utf8-truncated
do
  printf '%s\n' "$invalid_utf8" >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fix_wave_fail "$invalid_utf8 passed Jira preflight"
  else
    fix_wave_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  fi
  fix_wave_not_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  fix_wave_not_contains "$output" 'codex mcp login atlassian'
  fix_wave_not_contains "$output" 'OAuth URL:'
  fix_wave_not_contains "$output" 'createJiraIssue'
done

export FAKE_CODEX_WAIT_FOR_UTF8_SPLIT=1
rm -f "$XDG_CONFIG_HOME"/fake-codex-split-*
printf '%s\n' split-utf8-3 >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'split UTF-8 corrupted Jira inventory'
fi
unset FAKE_CODEX_WAIT_FOR_UTF8_SPLIT

printf '%s\n' nested-extension-before-tools \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fix_wave_contains "$output" 'Capability state: SUPPORTED'
  fix_wave_contains "$output" 'Result: PASS'
else
  fix_wave_fail 'nested extension corrupted Jira inventory extraction'
fi
fix_wave_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
fix_wave_not_contains "$output" 'codex mcp login atlassian'
fix_wave_not_contains "$output" 'OAuth URL:'
fix_wave_not_contains "$output" 'createJiraIssue'

printf '%s\n' healthy-empty-tools >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI doctor "$consumer" --client codex)
assert_contains "$output" 'Connector: PASS'
assert_contains "$output" 'Authentication: PASS'
assert_contains "$output" 'Result: PASS'
assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$output" 'codex mcp login atlassian'
assert_not_contains "$output" 'OAuth URL:'

if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'authenticated empty Codex inventory passed Jira preflight'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$output" 'codex mcp login atlassian'
assert_not_contains "$output" 'OAuth URL:'
assert_not_contains "$output" 'createJiraIssue'

for unusable_tool_map in \
  healthy-array-tools \
  healthy-null-tools \
  healthy-missing-tools
do
  printf '%s\n' "$unusable_tool_map" >"$XDG_CONFIG_HOME/fake-codex-health"
  output=$($CLI doctor "$consumer" --client codex)
  assert_contains "$output" 'Connector: PASS'
  assert_contains "$output" 'Authentication: PASS'
  assert_contains "$output" 'Result: PASS'
  assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$output" 'codex mcp login atlassian'
  assert_not_contains "$output" 'OAuth URL:'

  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fail "$unusable_tool_map passed Jira preflight"
  fi
  assert_contains "$output" 'Capability state: UNKNOWN'
  assert_contains "$output" 'Runtime inventory: UNAVAILABLE'
  assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
  assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$output" 'codex mcp login atlassian'
  assert_not_contains "$output" 'OAuth URL:'
  assert_not_contains "$output" 'createJiraIssue'
done

printf '%s\n' healthy-valid-nested-tool-values \
  >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'

printf '%s\n' healthy-valid-del-string \
  >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
assert_not_contains "$output" 'createJiraIssue'
assert_not_contains "$output" 'metadata'

printf '%s\n' healthy-valid-json-whitespace \
  >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'

LF_CODEX_RESPONSE=$(printf '%s\n%s\n' \
  '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{"metadata":' \
  '{"enabled":true}},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}')
LF_RELEASE_DIR=$release_dir
export LF_CODEX_RESPONSE LF_RELEASE_DIR
lf_capability=$(
  {
    sed '$d' "$CLI"
    printf '%s\n' \
      'connector_probe() {' \
      '  CONNECTOR_PROBE_OUTPUT=$LF_CODEX_RESPONSE' \
      '}' \
      'RELEASE_DIR=$LF_RELEASE_DIR' \
      'resolve_provider_capability codex jira-issue-write' \
      'printf "%s|%s\n" "$CAPABILITY_STATE" "$CAPABILITY_INVENTORY_STATE"'
  } | sh
)
unset LF_CODEX_RESPONSE LF_RELEASE_DIR
[ "$lf_capability" = 'SUPPORTED|COMPLETE' ] ||
  fail "valid JSON LF whitespace resolved as $lf_capability"

for invalid_tool_map in \
  healthy-malformed-tool-value \
  healthy-duplicate-required-tool \
  healthy-escaped-duplicate-required-tool
do
  printf '%s\n' "$invalid_tool_map" >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fail "$invalid_tool_map supplied the Atlassian inventory"
  fi
  assert_contains "$output" 'Capability state: UNKNOWN'
  assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
  assert_not_contains "$output" 'Capability state: SUPPORTED'
  assert_not_contains "$output" 'createJiraIssue'
  assert_not_contains "$output" 'metadata'
done

for invalid_tool_json in \
  healthy-malformed-nested-tool-object \
  healthy-malformed-nested-tool-array \
  healthy-invalid-c0-string \
  healthy-nested-vertical-tab-whitespace \
  healthy-nested-form-feed-whitespace
do
  printf '%s\n' "$invalid_tool_json" >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fail "$invalid_tool_json supplied the Atlassian inventory"
  fi
  assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  assert_not_contains "$output" 'Capability state: SUPPORTED'
  assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$output" 'codex mcp login atlassian'
  assert_not_contains "$output" 'OAuth URL:'
  assert_not_contains "$output" 'createJiraIssue'
  assert_not_contains "$output" 'metadata'
done

printf '%s\n' healthy-missing-resource-discovery \
  >"$XDG_CONFIG_HOME/fake-codex-health"
for missing_resource_operation in jira-write confluence-write; do
  if output=$($CLI preflight "$consumer" \
    --client codex --operation "$missing_resource_operation" \
    --non-interactive 2>&1)
  then
    fail "$missing_resource_operation passed without resource discovery"
  fi
  assert_contains "$output" 'Capability state: UNSUPPORTED'
  assert_contains "$output" 'Runtime inventory: COMPLETE'
  assert_not_contains "$output" 'getAccessibleAtlassianResources'
  assert_not_contains "$output" 'searchJiraIssuesUsingJql'
done

printf '%s\n' healthy-missing-jql >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'jira-write passed without JQL search'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_not_contains "$output" 'getAccessibleAtlassianResources'
assert_not_contains "$output" 'searchJiraIssuesUsingJql'

printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"
mkdir -p "$HOME/.cursor"
printf '%s\n' \
  '{"mcpServers":{"atlassian":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}}}' \
  >"$HOME/.cursor/mcp.json"
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
output=$($CLI preflight "$consumer" \
  --client cursor --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'

for cursor_health in \
  empty prose-only description-prefixes similar trailing-prose missing
do
  printf '%s\n' "$cursor_health" >"$XDG_CONFIG_HOME/fake-cursor-health"
  if output=$($CLI preflight "$consumer" \
    --client cursor --operation jira-write --non-interactive 2>&1)
  then
    fail "Cursor $cursor_health inventory passed"
  fi
  assert_contains "$output" 'Capability state: UNSUPPORTED'
done

printf '%s\n' \
  '# schema=1' \
  '# client	version	endpoint	toolset	tested_on	capability	state' \
  'codex	1.0.0	https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,createJiraIssue,getConfluencePage,getJiraIssue	2026-07-23	jira-issue-write	SUPPORTED' \
  'codex	1.0.0	https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,createJiraIssue,getConfluencePage,getJiraIssue	2026-07-23	confluence-page-parent-write	SUPPORTED' \
  'cursor	1.0.0	https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,createJiraIssue,getConfluencePage,getJiraIssue	2026-07-23	jira-issue-write	SUPPORTED' \
  >"$source_repo/runtime/compatibility/atlassian.tsv"
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

FAKE_CODEX_VERSION=99.77.55
export FAKE_CODEX_VERSION
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'schema-1 compatibility matched a different Codex version'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
unset FAKE_CODEX_VERSION

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

printf '%s\n' legacy-free-text >"$XDG_CONFIG_HOME/fake-cursor-health"
output=$($CLI preflight "$consumer" \
  --client cursor --operation jira-write --non-interactive)
assert_contains "$output" 'Client: cursor'
assert_contains "$output" 'Capability state: SUPPORTED'

if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-board-verify --non-interactive 2>&1)
then
  fail 'board verification passed without a catalog board'
fi
assert_contains "$output" 'Result: ROUTING_REQUIRED'

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
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
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
  assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  assert_not_contains "$output" 'Capability state: SUPPORTED'
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
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fail "$malformed_response supplied the Atlassian inventory"
  fi
  assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  assert_not_contains "$output" 'Capability state: SUPPORTED'
  assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$output" 'codex mcp login atlassian'
  assert_not_contains "$output" 'OAuth URL:'
  assert_not_contains "$output" 'createJiraIssue'
done

for malformed_reauth in \
  malformed-reauth-missing-comma \
  malformed-reauth-illegal-escape \
  malformed-reauth-trailing-member \
  malformed-reauth-trailing-token
do
  printf '%s\n' "$malformed_reauth" >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fail "$malformed_reauth passed Jira preflight"
  fi
  assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  assert_not_contains "$output" 'Capability state: SUPPORTED'
  assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$output" 'codex mcp login atlassian'
  assert_not_contains "$output" 'OAuth URL:'
  assert_not_contains "$output" 'reauthenticationRequired'
done

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
  printf '%s\n' "$terminal_error_response" \
    >"$XDG_CONFIG_HOME/fake-codex-health"
  if output=$($CLI preflight "$consumer" \
    --client codex --operation jira-write --non-interactive 2>&1)
  then
    fail "$terminal_error_response passed Jira preflight"
  fi
  assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
  assert_not_contains "$output" 'Capability state: SUPPORTED'
  assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
  assert_not_contains "$output" 'codex mcp login atlassian'
  assert_not_contains "$output" 'OAuth URL:'
  assert_not_contains "$output" 'createJiraIssue'
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
  assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
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

printf '%s\n' refresh-token-invalid \
  >"$XDG_CONFIG_HOME/fake-codex-health"
: >"$CALLS"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'Codex refresh-token failure passed Jira preflight'
fi
assert_contains "$output" 'Remediation: codex mcp login atlassian'
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$output" 'CONNECTOR_CAPABILITY_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'codex mcp login atlassian'

printf '%s\n' refresh-token-invalid-other-server \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'authenticated empty inventory passed Jira preflight'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'

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

printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-codex-health"
export FAKE_CODEX_OAUTH_HEALTH=healthy-nested-metadata
if output=$(printf 'y\n' | script -qec \
  "$CLI preflight $consumer --client codex --operation jira-write" \
  /dev/null 2>&1)
then
  fail 'preflight accepted unclassifiable health after OAuth'
fi
assert_contains "$output" 'Connector: HEALTH_UNAVAILABLE'
assert_contains "$output" 'Result: CONNECTOR_HEALTH_UNAVAILABLE'
unset FAKE_CODEX_OAUTH_HEALTH
printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"

: >"$CALLS"
output=$($CLI doctor "$consumer" --client codex)
assert_contains "$output" 'Connector: PASS'
assert_contains "$output" 'Authentication: PASS'
assert_contains "$output" 'Result: PASS'
$CLI context "$consumer" >/dev/null
assert_not_contains "$(cat "$CALLS")" 'mcp login atlassian'

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
  '# schema=2' \
  '# endpoint	required_tools	tested_on	capability	evidence	state' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getAccessibleAtlassianResources,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata,searchJiraIssuesUsingJql	2026-07-27	jira-issue-write	official-contract	SUPPORTED' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,getAccessibleAtlassianResources,getConfluencePage	2026-07-27	confluence-page-parent-write	official-contract	SUPPORTED' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getAccessibleAtlassianResources,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata,searchJiraIssuesUsingJql	2026-07-27	jira-board-verification	official-contract	SUPPORTED' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,getAccessibleAtlassianResources,getConfluencePage	2026-07-27	confluence-folder-parent-write	official-contract	SUPPORTED' \
  >"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.2
printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Capability evidence: PROVIDER_CONTRACT'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_contains "$output" 'Result: PASS'
assert_not_contains "$output" 'createJiraIssue'
assert_not_contains "$output" 'getAccessibleAtlassianResources'
assert_not_contains "$output" 'getJiraIssueTypeMetaWithFields'
assert_not_contains "$output" 'searchJiraIssuesUsingJql'

if output=$($CLI preflight "$consumer" \
  --client codex --operation confluence-write --non-interactive 2>&1)
then
  fail 'provider evidence enabled folder-parent writes'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

page_config='SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
publish_routing "$page_config"
printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI preflight "$consumer" \
  --client codex --operation confluence-write --non-interactive)
assert_contains "$output" 'Confluence root type: page'
assert_contains "$output" 'Capability: confluence-page-parent-write'
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Result: PASS'

printf '%s\n' healthy-missing-confluence-read \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation confluence-write --non-interactive 2>&1)
then
  fail 'complete inventory missing getConfluencePage passed'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

board_config='SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
JIRA_BOARD_ID=12
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
publish_routing "$board_config"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-board-verify --non-interactive 2>&1)
then
  fail 'provider evidence enabled board verification'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

FAKE_CODEX_VERSION=99.77.55
export FAKE_CODEX_VERSION
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
unset FAKE_CODEX_VERSION

printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
output=$($CLI preflight "$consumer" \
  --client claude --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Capability evidence: PROVIDER_CONTRACT'
assert_contains "$output" 'Runtime inventory: UNAVAILABLE'
assert_not_contains "$output" 'createJiraIssue'
assert_not_contains "$output" 'getAccessibleAtlassianResources'
assert_not_contains "$output" 'getJiraIssueTypeMetaWithFields'
assert_not_contains "$output" 'searchJiraIssuesUsingJql'

FAKE_CLAUDE_VERSION=88.66.44
export FAKE_CLAUDE_VERSION
output=$($CLI preflight "$consumer" \
  --client claude --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
unset FAKE_CLAUDE_VERSION

printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
output=$($CLI preflight "$consumer" \
  --client cursor --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Capability evidence: PROVIDER_CONTRACT'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_not_contains "$output" 'createJiraIssue'
assert_not_contains "$output" 'getAccessibleAtlassianResources'
assert_not_contains "$output" 'getJiraIssueTypeMetaWithFields'
assert_not_contains "$output" 'searchJiraIssuesUsingJql'

printf '%s\n' ready-tools-failed >"$XDG_CONFIG_HOME/fake-cursor-health"
if output=$($CLI preflight "$consumer" \
  --client cursor --operation jira-write --non-interactive 2>&1)
then
  fail 'Cursor provider preflight passed with unavailable tool inventory'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Capability evidence: NONE'
assert_contains "$output" 'Runtime inventory: UNAVAILABLE'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
assert_not_contains "$output" 'ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$output" 'cursor-agent mcp login atlassian'
assert_not_contains "$output" 'OAuth URL:'
assert_not_contains "$output" 'Tool inventory failed'
assert_not_contains "$output" 'createJiraIssue'

FAKE_CURSOR_VERSION=77.55.33
export FAKE_CURSOR_VERSION
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
output=$($CLI preflight "$consumer" \
  --client cursor --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
unset FAKE_CURSOR_VERSION

printf '%s\n' healthy-missing-jira-metadata >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'complete inventory missing a required provider tool passed'
fi
assert_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Capability evidence: RUNTIME_INVENTORY'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
assert_not_contains "$output" 'createJiraIssue'
assert_not_contains "$output" 'getAccessibleAtlassianResources'
assert_not_contains "$output" 'getJiraIssueTypeMetaWithFields'
assert_not_contains "$output" 'searchJiraIssuesUsingJql'

printf '%s\n' healthy-all >"$XDG_CONFIG_HOME/fake-codex-health"
printf '%s\n' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getAccessibleAtlassianResources,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata,searchJiraIssuesUsingJql	2026-07-27	jira-issue-write	official-contract	SUPPORTED' \
  >>"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.3
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'duplicate provider evidence passed'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

compatibility_temp=$(mktemp \
  "$source_repo/runtime/compatibility/atlassian.tsv.XXXXXX")
awk -F '\t' '$4 != "jira-issue-write"' \
  "$source_repo/runtime/compatibility/atlassian.tsv" >"$compatibility_temp"
mv "$compatibility_temp" "$source_repo/runtime/compatibility/atlassian.tsv"
printf '%s\n' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,createJiraIssue,getAccessibleAtlassianResources,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata,searchJiraIssuesUsingJql	2026-07-27	jira-issue-write	official-contract	SUPPORTED' \
  >>"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.4
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'malformed provider toolset passed'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

compatibility_temp=$(mktemp \
  "$source_repo/runtime/compatibility/atlassian.tsv.XXXXXX")
awk -F '\t' '$4 != "jira-issue-write"' \
  "$source_repo/runtime/compatibility/atlassian.tsv" >"$compatibility_temp"
mv "$compatibility_temp" "$source_repo/runtime/compatibility/atlassian.tsv"
printf '%s\n' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getAccessibleAtlassianResources,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata,searchJiraIssuesUsingJql	2026-07-27	jira-issue-write	unrecognized	SUPPORTED' \
  >>"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.5
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'unrecognized provider evidence passed'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

compatibility_temp=$(mktemp \
  "$source_repo/runtime/compatibility/atlassian.tsv.XXXXXX")
awk -F '\t' '$4 != "jira-issue-write"' \
  "$source_repo/runtime/compatibility/atlassian.tsv" >"$compatibility_temp"
mv "$compatibility_temp" "$source_repo/runtime/compatibility/atlassian.tsv"
printf '%s\n' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getAccessibleAtlassianResources,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata,searchJiraIssuesUsingJql	2025-02-29	jira-issue-write	official-contract	SUPPORTED' \
  >>"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.6
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'impossible provider date passed'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

printf '%s\n' \
  '# schema=2' \
  '# endpoint	required_tools	tested_on	capability	evidence	state' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getAccessibleAtlassianResources,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata,searchJiraIssuesUsingJql	2026-07-27	jira-issue-write	official-contract	SUPPORTED' \
  'https://mcp.atlassian.com/v1/mcp/authv2	getConfluencePage,getAccessibleAtlassianResources,createConfluencePage	2026-07-27	confluence-page-parent-write	official-contract	SUPPORTED' \
  >"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.7
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'unrelated noncanonical provider row passed'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

printf '%s\n' \
  '# schema=2' \
  '# endpoint	required_tools	tested_on	capability	evidence	state' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getAccessibleAtlassianResources,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata,searchJiraIssuesUsingJql	2026-07-27	jira-issue-write	official-contract	SUPPORTED' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,getAccessibleAtlassianResources,getConfluencePage	2026-07-27	confluence-page-parent-write	official-contract	SUPPORTED' \
  'https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,getAccessibleAtlassianResources,getConfluencePage	2026-07-27	confluence-page-parent-write	isolated-pilot	UNSUPPORTED' \
  >"$source_repo/runtime/compatibility/atlassian.tsv"
pin_test_release v1.1.8
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'duplicate provider pair outside requested capability passed'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

invalid_config='SCHEMA_VERSION=1
PROFILE=standalone
PROFILE=backend
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
assert_catalog_invalid "$invalid_config"

unknown_key_config='SCHEMA_VERSION=1
PROFILE=standalone
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only
UNKNOWN=value'
assert_catalog_invalid "$unknown_key_config"

unsupported_schema_config='SCHEMA_VERSION=2
PROFILE=standalone
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
assert_catalog_invalid "$unsupported_schema_config"

invalid_board_config='SCHEMA_VERSION=1
PROFILE=standalone
JIRA_BOARD_ID=0
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
assert_catalog_invalid "$invalid_board_config"

standalone_integration_config='SCHEMA_VERSION=1
PROFILE=standalone
INTEGRATION_PROFILE=beroka-be-fe
CROSS_REPO_POLICY=profile-controlled'
assert_catalog_invalid "$standalone_integration_config"

profile_controlled_none_config='SCHEMA_VERSION=1
PROFILE=backend
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=profile-controlled'
assert_catalog_invalid "$profile_controlled_none_config"

rm "$catalog/routing-consumer.conf"
ln -s ../../rules/general.md "$catalog/routing-consumer.conf"
pin_test_release v1.3.0
if output=$($CLI context "$consumer" 2>&1); then
  fail 'symlinked catalog record passed release validation'
fi
assert_contains "$output" 'Result: VERSION_MISMATCH'
assert_contains "$output" 'Repository catalog contains a symlink'

printf '%s\n' 'PASS: routing state'

grep -F 'beroka-governance preflight' "$ROOT/README.md" >/dev/null ||
  fail 'README does not document preflight'
grep -F 'CONNECTOR_CAPABILITY_REQUIRED' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document capability remediation'

[ "$(sed -n '1p' "$ROOT/VERSION")" = v1.0.4 ] ||
  fix_wave_fail 'root VERSION does not select v1.0.4'
grep -F -- 'gh release download' "$ROOT/README.md" >/dev/null ||
  fix_wave_fail 'README does not select the authenticated release launcher'

[ "$FIX_WAVE_FAILURES" -eq 0 ] ||
  fail "$FIX_WAVE_FAILURES fix-wave regressions remain"
