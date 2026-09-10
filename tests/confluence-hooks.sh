#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-confluence-hooks.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
# macOS TMPDIR may start with /var -> /private/var; use the physical fixture root.
TEST_ROOT=$(CDPATH= cd -- "$TEST_ROOT" && pwd -P)
export HOME=$TEST_ROOT/home XDG_CONFIG_HOME=$TEST_ROOT/home/config
export XDG_DATA_HOME=$TEST_ROOT/home/data XDG_STATE_HOME=$TEST_ROOT/home/state
export TMPDIR=$TEST_ROOT/tmp BEROKA_GOV_BIN_DIR=$TEST_ROOT/home/bin
export CODEX_HOME=$TEST_ROOT/codex-config
mkdir -p "$TMPDIR" "$CODEX_HOME"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/beroka-ai-governance" "$BEROKA_GOV_BIN_DIR"
CLI=$BEROKA_GOV_BIN_DIR/beroka-governance
cp "$ROOT/bin/beroka-governance" "$CLI"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { case "$1" in *"$2"*) ;; *) fail "expected $2 in $1" ;; esac; }
new_repo() {
  git init -q "$1"
  git -C "$1" config user.email test@example.invalid
  git -C "$1" config user.name Test
}
source_repo=$TEST_ROOT/source
new_repo "$source_repo"
cp -R "$ROOT/runtime" "$ROOT/templates" "$source_repo/"
mkdir "$source_repo/bin"
cp "$CLI" "$source_repo/bin/"
cp "$ROOT/governance.md" "$ROOT/handbook.md" "$ROOT/workflow.md" "$source_repo/"
printf '%s\n' v1.1.0 >"$source_repo/VERSION"
sed 's/Derivatives — Market — API\tDerivatives\tMarket\tAPI\t65962274/Shared — Market — API\tShared\tMarket\tAPI\t65962274/' "$source_repo/runtime/integrations/beroka-be-fe.confluence-targets" >"$TEST_ROOT/targets"
mv "$TEST_ROOT/targets" "$source_repo/runtime/integrations/beroka-be-fe.confluence-targets"
printf '%b\n' 'beroka-vn/Beroka_Backend\tpage\tACTIVE\t900001\tTest handoff\tShared\tMarket\tAPI\t76808195\tMARKET-TEST-HANDOFF-API\t76808196' >>"$source_repo/runtime/integrations/beroka-be-fe.confluence-targets"
git -C "$source_repo" add .
git -C "$source_repo" commit -qm fixture
git -C "$source_repo" tag -a v1.1.0 -m fixture
release=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.1.0
mkdir -p "$(dirname "$release")"
git clone -q "$source_repo" "$release"
git -C "$release" checkout -q --detach v1.1.0
git -C "$release" remote set-url origin https://github.com/beroka-vn/beroka-ai-governance.git
printf 'VERSION=v1.1.0\nCOMMIT=%s\n' "$(git -C "$source_repo" rev-parse HEAD)" >"$XDG_CONFIG_HOME/beroka-ai-governance/active-release"
printf '%s\n' BE >"$XDG_CONFIG_HOME/beroka-ai-governance/github-role"
printf '%s\n' codex,claude,cursor >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"
mkdir -p "$CODEX_HOME" "$HOME/.claude" "$HOME/.cursor"
cp "$ROOT/templates/agent-entrypoints/AGENTS.md" "$CODEX_HOME/AGENTS.md"
cp "$ROOT/templates/agent-entrypoints/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
git --git-dir=/dev/null hash-object --no-filters "$ROOT/templates/agent-entrypoints/CURSOR-USER-RULE.txt" >"$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"
printf '%s\n' '{"mcpServers":{"atlassian":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}}}' >"$HOME/.cursor/mcp.json"
repo=$TEST_ROOT/backend
new_repo "$repo"
git -C "$repo" remote add origin https://github.com/beroka-vn/Beroka_Backend.git

# Only external CLI authentication/inventory are simulated; release verification,
# native hook envelopes, routing, body validation and receipts run production code.
cat >"$BEROKA_GOV_BIN_DIR/gh" <<'EOF'
#!/bin/sh
case "$*" in
  'api --paginate /user/teams') printf '%s\n' '[{"slug":"backend","organization":{"login":"beroka-vn"}}]' ;;
  *) exit 0 ;;
esac
EOF
cat >"$BEROKA_GOV_BIN_DIR/codex" <<'EOF'
#!/bin/sh
case "$*" in
  'mcp get atlassian --json') printf '%s\n' '{"name":"atlassian","url":"https://mcp.atlassian.com/v1/mcp/authv2"}' ;;
  'app-server --stdio')
    while IFS= read -r line; do
      case "$line" in
        *'"method":"initialize"'*) printf '%s\n' '{"id":0,"result":{}}' ;;
        *'mcpServerStatus/list'*) printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","authStatus":"oAuth","tools":{"createConfluencePage":{},"updateConfluencePage":{},"getConfluencePage":{},"getAccessibleAtlassianResources":{}}}],"nextCursor":null}}' ;;
      esac
    done ;;
esac
EOF
cat >"$BEROKA_GOV_BIN_DIR/claude" <<'EOF'
#!/bin/sh
case "$*" in
  'mcp get atlassian') printf 'atlassian:\n  Type: http\n  URL: https://mcp.atlassian.com/v1/mcp/authv2\n' ;;
  'mcp list') printf '%s\n' 'atlassian: Connected' ;;
esac
EOF
cat >"$BEROKA_GOV_BIN_DIR/cursor-agent" <<'EOF'
#!/bin/sh
case "$*" in
  'mcp list') printf '%s\n' 'atlassian: ready' ;;
  'mcp list-tools atlassian') printf '%s\n' 'createConfluencePage' 'updateConfluencePage' 'getConfluencePage' 'getAccessibleAtlassianResources' ;;
esac
EOF
chmod +x "$BEROKA_GOV_BIN_DIR/gh" "$BEROKA_GOV_BIN_DIR/codex" "$BEROKA_GOV_BIN_DIR/claude" "$BEROKA_GOV_BIN_DIR/cursor-agent"
export PATH=$BEROKA_GOV_BIN_DIR:$PATH

body='Jira: BB-64
GitHub: N/A
## Handoff — BB-64
PPSE documentation.
Owner: BE_Cuong'
envelope() {
  jq -nc --arg client "$client" --arg repo "$repo" --arg session "$session" \
    --arg tool "$1" --arg id "$2" --argjson args "$3" --argjson response "${4:-null}" '
    (if $response == null or $response.isError == true then $response
      else {content:[{type:"text",text:($response|tojson)}]} end) as $result |
    {tool_use_id:$id,tool_input:$args} +
    if $client == "cursor" then
      {conversation_id:$session,generation_id:"generation",workspace_roots:[$repo],tool_name:("MCP:"+$tool),tool_output:($result|tojson)}
    else {cwd:$repo,session_id:$session,tool_name:(if $client == "codex" then "mcp__codex_apps__atlassian_rovo__"+($tool|ascii_downcase) else "mcp__atlassian__"+$tool end),tool_response:$result} end'
}
hook() {
  case "$client" in
    codex) hook_config=$CODEX_HOME/hooks.json ;;
    claude) hook_config=$HOME/.claude/settings.json ;;
    cursor) hook_config=$HOME/.cursor/hooks.json ;;
  esac
  hook_command=$(jq -r --arg phase "$1" --arg client "$client" '
    [.hooks[][] | if $client == "cursor" then . else .hooks[] end |
      .command | select(endswith(" confluence-hook " + $client + " " + $phase))] |
    if length == 1 then .[0] else error("managed command") end' "$hook_config")
  printf '%s\n' "$2" | sh -c "$hook_command"
}
denied() {
  if output=$(hook "$1" "$2" 2>&1); then
    [ "$client" = cursor ] || fail "hook allowed $3"
    case "$output" in *'"permission":"deny"'*|*'"isError":true'*|*'"followup_message"'*) ;; *) fail "Cursor hook allowed $3: $output" ;; esac
  fi
  contains "$output" "$3"
}
seed_space() {
  space_args='{"cloudId":"https://beroka.atlassian.net","keys":["Berokaback"]}'
  hook post "$(envelope getConfluenceSpaces spaces "$space_args" '{"results":[{"id":"123","key":"Berokaback"}]}')" >/dev/null
}
page_result() {
  jq -nc --arg body "$1" '{id:"900001",parentId:"76808195",spaceId:"123",status:"current",version:{number:3},body:{markdown:{value:($body|gsub("BE_Cuong"; "BE\\_Cuong"))}}}'
}
verify_write() {
  write_tool=$1
  request=$(envelope "$write_tool" write-1 "$args")
  contains "$(hook pre "$request")" WRITE_VALIDATED
  denied stop "$(envelope ignored stop '{}')" HANDOFF_READBACK_REQUIRED
  contains "$(hook post "$(envelope "$write_tool" write-1 "$args" '{"id":"900001","version":{"number":3}}')")" WRITE_RECORDED
  read_args='{"cloudId":"https://beroka.atlassian.net","pageId":"900001","contentFormat":"markdown"}'
  hook pre "$(envelope getConfluencePage read-1 "$read_args")" >/dev/null
  contains "$(hook post "$(envelope getConfluencePage read-1 "$read_args" "$(page_result "$expected_body")")")" READBACK_VERIFIED
  hook stop "$(envelope ignored stop '{}')" >/dev/null
}
for client in codex claude cursor; do
  "$CLI" setup-documentation-hooks --client "$client" >/dev/null
  session=$client-stop-no-write
  hook stop "$(envelope ignored stop '{}' | jq -c --arg cwd "$HOME" '.cwd=$cwd | del(.workspace_roots)')" >/dev/null
  ordinary_args=$(jq -nc --arg body "$body" '{cloudId:"https://beroka.atlassian.net",spaceId:"123",parentId:"76808195",title:"PPSE",body:$body,contentFormat:"markdown"}')
  for scenario in ordinary-create ordinary-update draft ready; do
    session=$client-$scenario
    seed_space
    args=$ordinary_args expected_body=$body write_tool=createConfluencePage
    case "$scenario" in
      ordinary-update)
        write_tool=updateConfluencePage
        args=$(printf '%s\n' "$args" | jq -c '.pageId="900001" | del(.parentId,.spaceId)')
        denied pre "$(envelope "$write_tool" write-1 "$args")" ROUTING_REQUIRED
        read_args='{"cloudId":"https://beroka.atlassian.net","pageId":"900001","contentFormat":"markdown"}'
        hook post "$(envelope getConfluencePage initial-read "$read_args" "$(page_result "$body")")" >/dev/null
        ;;
      draft|ready)
        fixture=draft
        [ "$scenario" != ready ] || { fixture=ready-no-impact; write_tool=updateConfluencePage; }
        expected_body=$(sed "s/^Confluence page version: 1$/Confluence page version: 3/" "$ROOT/tests/fixtures/handoffs/$fixture.md")
        args=$(printf '%s\n' "$args" | jq -c --arg body "$expected_body" '.body=$body')
        [ "$scenario" != ready ] || args=$(printf '%s\n' "$args" | jq -c '.pageId="900001"')
        ;;
    esac
    verify_write "$write_tool"
    if [ "$scenario" = ordinary-update ]; then
      # Root reads without parents remain readable, but cannot seed an update.
      hook post "$(envelope getConfluencePage root-read "$read_args" '{"id":"900001","spaceId":"123"}')" >/dev/null
      denied pre "$(envelope "$write_tool" write-2 "$args")" ROUTING_REQUIRED
    fi
  done
  if [ "$client" = cursor ]; then
    session=cursor-workspaces
    seed_space
    args=$ordinary_args
    contains "$(hook pre "$(envelope createConfluencePage write-1 "$args" | jq -c '.workspace_roots += .workspace_roots')")" WRITE_VALIDATED
    denied pre "$(envelope createConfluencePage write-2 "$args" | jq -c --arg root "$source_repo" '.workspace_roots += [$root]')" CLIENT_BODY_GATE_REQUIRED
  fi
  session=$client-bad
  args=$ordinary_args
  denied pre "$(envelope createConfluencePage write-1 "$args")" ROUTING_REQUIRED
  seed_space
  denied pre "$(envelope createConfluencePage write-1 "$(printf '%s\n' "$args" | jq -c '.spaceId="666"')")" ROUTING_REQUIRED
  denied pre "$(envelope createConfluencePage write-1 "$(printf '%s\n' "$args" | jq -c '.body="No evidence"')")" HANDOFF_DELTA_REQUIRED
  denied pre "$(envelope createConfluencePage write-1 "$(printf '%s\n' "$args" | jq -c '.contentFormat="adf"')")" CLIENT_BODY_GATE_REQUIRED
  denied pre "$(envelope createConfluencePage write-1 "$args" | jq -c '.tool_name="mcp__atlassian__unreviewed__createConfluencePage"')" CLIENT_BODY_GATE_REQUIRED
  printf '%s\n' FE >"$XDG_CONFIG_HOME/beroka-ai-governance/github-role"
  denied pre "$(envelope createConfluencePage write-1 "$args")" ROLE_SCOPE_DENIED
  printf '%s\n' BE >"$XDG_CONFIG_HOME/beroka-ai-governance/github-role"
  for scenario in mismatch write-failure read-failure read-mismatch stale-read; do
    session=$client-$scenario
    seed_space
    request=$(envelope createConfluencePage write-1 "$args")
    contains "$(hook pre "$request")" WRITE_VALIDATED
    case "$scenario" in
      mismatch)
        changed=$(printf '%s\n' "$args" | jq -c '.body += "changed"')
        denied post "$(envelope createConfluencePage write-1 "$changed" '{"id":"900001","version":{"number":3}}')" CONFLUENCE_BODY_MISMATCH
        ;;
      write-failure)
        denied post "$(envelope createConfluencePage write-1 "$args" '{"isError":true,"content":[{"type":"text","text":"Forbidden"}]}')" CONFLUENCE_RESULT_UNVERIFIED
        ;;
      *)
        read_args='{"cloudId":"https://beroka.atlassian.net","pageId":"900001","contentFormat":"markdown"}'
        [ "$scenario" != stale-read ] || hook pre "$(envelope getConfluencePage read-1 "$read_args")" >/dev/null
        contains "$(hook post "$(envelope createConfluencePage write-1 "$args" '{"id":"900001","version":{"number":3}}')")" WRITE_RECORDED
        [ "$scenario" = stale-read ] || hook pre "$(envelope getConfluencePage read-1 "$read_args")" >/dev/null
        response=$(page_result "$body")
        case "$scenario" in
          read-failure) response='{"isError":true}'; expected=CONFLUENCE_RESULT_UNVERIFIED ;;
          read-mismatch)
            for mutation in '.id="42"' '.parentId="42"' '.spaceId="42"' '.version.number=42' 'del(.body)'; do
              bad_response=$(printf '%s\n' "$response" | jq -c "$mutation")
              denied post "$(envelope getConfluencePage read-1 "$read_args" "$bad_response")" HANDOFF_READBACK_REQUIRED
            done
            response=$(page_result changed); expected=HANDOFF_READBACK_REQUIRED ;;
          stale-read) expected=HANDOFF_READBACK_REQUIRED ;;
        esac
        denied post "$(envelope getConfluencePage read-1 "$read_args" "$response")" "$expected"
        ;;
    esac
    denied stop "$(envelope ignored stop '{}')" HANDOFF_READBACK_REQUIRED
    hook stop "$(envelope ignored stop '{}' | jq -c '.stop_hook_active=true | .loop_count=1')" >/dev/null
  done
  session=$client-rejected
  seed_space
  contains "$(hook pre "$(envelope createConfluencePage write-1 "$args")")" WRITE_VALIDATED
  denied post "$(envelope createConfluencePage write-1 "$args" '{"isError":true,"statusCode":403}')" CONFLUENCE_WRITE_REJECTED
  hook stop "$(envelope ignored stop '{}')" >/dev/null
  session=$client-crlf
  seed_space
  crlf_body=$(sed 's/$/\r/' "$ROOT/tests/fixtures/handoffs/ready-no-impact.md")
  crlf_args=$(printf '%s\n' "$ordinary_args" | jq -c --arg body "$crlf_body" '.body=$body | .pageId="900001"')
  denied pre "$(envelope updateConfluencePage write-1 "$(printf '%s\n' "$crlf_args" | jq -c '.status="draft"')")" HANDOFF_BODY_INVALID
  contains "$(hook pre "$(envelope updateConfluencePage write-1 "$crlf_args")")" WRITE_VALIDATED
  denied post "$(envelope updateConfluencePage write-1 "$crlf_args" '{"id":"900001","version":{"number":99}}')" CREATION_STATUS_UNKNOWN
done
# Custom CODEX_HOME remains confined to managed files and rejects symlinks.
mv "$CODEX_HOME/hooks.json" "$CODEX_HOME/hooks.saved"
ln -s "$CODEX_HOME/hooks.saved" "$CODEX_HOME/hooks.json"
if "$CLI" setup-documentation-hooks --client codex >"$TEST_ROOT/unsafe.log" 2>&1; then
  fail 'accepted symlinked custom Codex hook config'
fi
contains "$(cat "$TEST_ROOT/unsafe.log")" 'Symlinked'
rm "$CODEX_HOME/hooks.json"
mv "$CODEX_HOME/hooks.saved" "$CODEX_HOME/hooks.json"
# Hooks must never persist staged body text after preflight.
[ -z "$(find "$TMPDIR" -maxdepth 1 -type d -name 'beroka-governance-cursor-body.*' -print)" ] || fail 'staged body leaked'
printf '%s\n' 'PASS: native Confluence hooks (simulated connectors)'
