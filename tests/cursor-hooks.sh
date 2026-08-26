#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLI=$ROOT/bin/beroka-governance
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-cursor-hooks.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
export TMPDIR=$TMP_ROOT
CONNECTOR_CALLS=$TMP_ROOT/connector-calls
export CONNECTOR_CALLS

export HOME=$TMP_ROOT/home
export XDG_DATA_HOME=$TMP_ROOT/data
export XDG_CONFIG_HOME=$TMP_ROOT/config
export XDG_STATE_HOME=$TMP_ROOT/state
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
git config --global advice.detachedHead false

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "expected [$2] in [$1]" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "unexpected [$2] in [$1]" ;; esac; }
assert_denied() { assert_contains "$1" '"permission":"deny"'; assert_contains "$1" "$2"; }
assert_no_cursor_body_stage() {
  stage=$(find "$TMPDIR" -maxdepth 1 -type d \
    -name 'beroka-governance-cursor-body.*' -print -quit)
  [ -z "$stage" ] || fail 'Cursor left a staged cross-team body behind'
}

new_repo() {
  mkdir -p "$1"
  git -C "$1" init -qb trunk
  git -C "$1" config user.name test-user
  git -C "$1" config user.email test@example.invalid
}

source_repo=$TMP_ROOT/source
new_repo "$source_repo"
mkdir -p "$source_repo/bin"
cp -R "$ROOT/runtime" "$source_repo/runtime"
cp -R "$ROOT/templates" "$source_repo/templates"
cp "$ROOT/bin/beroka-governance" "$source_repo/bin/beroka-governance"
# The Cursor fixture uses this real ACTIVE Folder ID with Shared/Market data.
sed 's/Derivatives — Market — API\tDerivatives\tMarket\tAPI\t65962274/Shared — Market — API\tShared\tMarket\tAPI\t65962274/' \
  "$source_repo/runtime/integrations/beroka-be-fe.confluence-targets" \
  >"$source_repo/runtime/integrations/beroka-be-fe.confluence-targets.next"
mv "$source_repo/runtime/integrations/beroka-be-fe.confluence-targets.next" \
  "$source_repo/runtime/integrations/beroka-be-fe.confluence-targets"
# Positive Cursor update fixtures need reviewed target ancestry; production
# inventory intentionally has no synthetic page 900001.
printf '%b\n' \
  'beroka-vn/Beroka_Backend\tpage\tACTIVE\t900001\tTest handoff page\tShared\tMarket\tAPI\t76808195\tMARKET-TEST-HANDOFF-API\t76808196' \
  >>"$source_repo/runtime/integrations/beroka-be-fe.confluence-targets"
for file in governance.md handbook.md workflow.md; do cp "$ROOT/$file" "$source_repo/$file"; done
printf '%s\n' v1.1.0 >"$source_repo/VERSION"
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'test: create cursor release'
git -C "$source_repo" tag -a v1.1.0 -m v1.1.0
release_commit=$(git -C "$source_repo" rev-parse 'v1.1.0^{commit}')
release=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.1.0
mkdir -p "$(dirname -- "$release")"
git clone -q "$source_repo" "$release"
git -C "$release" checkout -q --detach v1.1.0
git -C "$release" remote set-url origin https://github.com/beroka-vn/beroka-ai-governance.git
mkdir -p "$XDG_CONFIG_HOME/beroka-ai-governance"
printf '%s\n' "VERSION=v1.1.0" "COMMIT=$release_commit" \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/active-release"
printf '%s\n' BE >"$XDG_CONFIG_HOME/beroka-ai-governance/github-role"

known_repo=$TMP_ROOT/known-repository
new_repo "$known_repo"
printf '%s\n' '# known' >"$known_repo/README.md"
git -C "$known_repo" add README.md
git -C "$known_repo" commit -qm 'test: initialize known repository'
git -C "$known_repo" remote add origin https://github.com/beroka-vn/Beroka_Backend.git

other_repo=$TMP_ROOT/other-repository
new_repo "$other_repo"
printf '%s\n' '# other' >"$other_repo/README.md"
git -C "$other_repo" add README.md
git -C "$other_repo" commit -qm 'test: initialize other repository'
git -C "$other_repo" remote add origin https://github.com/beroka-vn/Beroka_Frontend.git

base_input=$(jq -nc --arg workspace "$known_repo" '{conversation_id:"conversation-1",generation_id:"generation-1",workspace_roots:[$workspace]}')
hook() { printf '%s\n' "$2" | "$CLI" cursor-hook "$1"; }

session=$(hook sessionStart "$base_input")
assert_contains "$session" '"additional_context"'
assert_contains "$session" 'beroka-vn/Beroka_Backend'
assert_contains "$session" 'Version: v1.1.0'
assert_contains "$session" 'Routing: ROUTING_ACTIVE'

unstarted_base=$(jq -nc --arg workspace "$known_repo" \
  '{conversation_id:"conversation-unstarted",generation_id:"generation-unstarted",workspace_roots:[$workspace]}')
unstarted_prompt=$(printf '%s\n' "$unstarted_base" | jq -c \
  '. + {prompt:"Work-item language: English"}')
unstarted_submit=$(hook beforeSubmitPrompt "$unstarted_prompt")
case "$unstarted_submit" in
  *'"continue":false'*) fail 'fresh beforeSubmitPrompt required manual session start' ;;
esac
unstarted_receipt=$(printf '%s' 'conversation-unstarted' | shasum -a 256 | awk '{print $1}')
unstarted_receipt_file=$XDG_STATE_HOME/beroka-ai-governance/cursor/$unstarted_receipt.json
[ -f "$unstarted_receipt_file" ] || fail 'fresh Cursor receipt was not created'
assert_contains "$(jq -r .language "$unstarted_receipt_file")" en

prompt_vi=$(printf '%s\n' "$base_input" | jq -c '. + {prompt:"Work-item language: Vietnamese"}')
hook beforeSubmitPrompt "$prompt_vi" >/dev/null
base_receipt=$(printf '%s' 'conversation-1' | shasum -a 256 | awk '{print $1}')
receipt=$XDG_STATE_HOME/beroka-ai-governance/cursor/$base_receipt.json
assert_contains "$(jq -r .language "$receipt")" vi
generation_two=$(printf '%s\n' "$base_input" | jq -c '.generation_id="generation-2"')
hook beforeSubmitPrompt "$generation_two" >/dev/null
assert_contains "$(jq -r .language "$receipt")" en

hook preCompact "$generation_two" >/dev/null
output=$(hook beforeMCPExecution "$(printf '%s\n' "$generation_two" | jq -c '. + {tool_name:"github.create_issue", url:"https://github.com", tool_input:{body:"Work-item language: English"}}')")
assert_denied "$output" GOVERNANCE_CONTEXT_REQUIRED

for invalid in '{' \
  "$(jq -nc --arg workspace "$TMP_ROOT/not-git" '{conversation_id:"bad",generation_id:"bad",workspace_roots:[$workspace]}')" \
  "$(jq -nc '{conversation_id:"bad",generation_id:"bad",workspace_roots:[]}')"; do
  if output=$(hook sessionStart "$invalid" 2>&1); then fail 'invalid session input passed'; fi
  assert_contains "$output" 'GOVERNANCE_CONTEXT_REQUIRED'
done

# A non-Git root is ignored when there is one unambiguous Git root.
multi_root=$(jq -nc --arg a "$TMP_ROOT/not-git" --arg b "$known_repo" \
  '{conversation_id:"conversation-1",generation_id:"generation-1",workspace_roots:[$a,$b]}')
multi_root_session=$(hook sessionStart "$multi_root")
assert_contains "$multi_root_session" 'beroka-vn/Beroka_Backend'
assert_contains "$multi_root_session" 'Routing: ROUTING_ACTIVE'

same_repo_roots=$(jq -nc --arg a "$known_repo" --arg b "$known_repo/." \
  '{conversation_id:"same-repository",generation_id:"same-repository",workspace_roots:[$a,$b]}')
same_repo_session=$(hook sessionStart "$same_repo_roots")
assert_contains "$same_repo_session" 'beroka-vn/Beroka_Backend'

# Distinct Git roots fail closed unless FULL_STACK opens the exact BE+FE pair.
ambiguous_roots=$(jq -nc --arg a "$known_repo" --arg b "$other_repo" \
  '{conversation_id:"ambiguous",generation_id:"ambiguous",workspace_roots:[$a,$b]}')
if output=$(hook sessionStart "$ambiguous_roots" 2>&1); then
  fail 'BE role accepted Backend+Frontend multi-root'
fi
assert_contains "$output" 'GOVERNANCE_CONTEXT_REQUIRED'

# Browser and other non-governed MCP tools must not be blanket-denied solely by
# an ambiguous multi-root shape.
browser_ambiguous=$(printf '%s\n' "$ambiguous_roots" | jq -c \
  '. + {tool_name:"browser_navigate",url:"https://example.com",tool_input:{}}')
assert_contains "$(hook beforeMCPExecution "$browser_ambiguous")" '"permission":"allow"'
jira_ambiguous=$(printf '%s\n' "$ambiguous_roots" | jq -c \
  '. + {tool_name:"jira.create_issue",url:"https://example.atlassian.net",tool_input:{body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$jira_ambiguous")" GOVERNANCE_CONTEXT_REQUIRED

printf '%s\n' FULL_STACK >"$XDG_CONFIG_HOME/beroka-ai-governance/github-role"
fullstack_roots=$(jq -nc --arg a "$known_repo" --arg b "$other_repo" \
  '{conversation_id:"fullstack",generation_id:"fullstack",workspace_roots:[$a,$b]}')
fullstack_session=$(hook sessionStart "$fullstack_roots")
assert_contains "$fullstack_session" 'Multi-root mode: FULL_STACK'
assert_contains "$fullstack_session" 'beroka-vn/Beroka_Backend'
assert_contains "$fullstack_session" 'beroka-vn/Beroka_Frontend'
assert_contains "$fullstack_session" 'Jira project: BB'
assert_contains "$fullstack_session" 'Jira project: BF'
fullstack_browser=$(printf '%s\n' "$fullstack_roots" | jq -c \
  '. + {tool_name:"browser_navigate",url:"https://example.com",tool_input:{}}')
assert_contains "$(hook beforeMCPExecution "$fullstack_browser")" '"permission":"allow"'
fullstack_jira_untargeted=$(printf '%s\n' "$fullstack_roots" | jq -c \
  '. + {tool_name:"jira.create_issue",url:"https://example.atlassian.net",tool_input:{body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$fullstack_jira_untargeted")" TARGET_REQUIRED
fullstack_jira_parent=$(printf '%s\n' "$fullstack_roots" | jq -c \
  '. + {tool_name:"jira.create_issue",url:"https://example.atlassian.net",tool_input:{parent:"BB-34",body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$fullstack_jira_parent")" WORK_ITEM_TEMPLATE_REQUIRED
fullstack_jira_bb=$(printf '%s\n' "$fullstack_roots" | jq -c \
  '. + {tool_name:"jira.create_issue",url:"https://example.atlassian.net",tool_input:{projectKey:"BB",body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$fullstack_jira_bb")" WORK_ITEM_TEMPLATE_REQUIRED

# Real developer clones use product folder names in workspace_roots. Those path
# substrings must not force TARGET_REQUIRED when tool_input names one project.
product_backend=$TMP_ROOT/Beroka_Backend
product_frontend=$TMP_ROOT/Beroka_Frontend
new_repo "$product_backend"
printf '%s\n' '# backend' >"$product_backend/README.md"
git -C "$product_backend" add README.md
git -C "$product_backend" commit -qm 'test: initialize product backend'
git -C "$product_backend" remote add origin https://github.com/beroka-vn/Beroka_Backend.git
new_repo "$product_frontend"
printf '%s\n' '# frontend' >"$product_frontend/README.md"
git -C "$product_frontend" add README.md
git -C "$product_frontend" commit -qm 'test: initialize product frontend'
git -C "$product_frontend" remote add origin https://github.com/beroka-vn/Beroka_Frontend.git
product_roots=$(jq -nc --arg a "$product_backend" --arg b "$product_frontend" \
  '{conversation_id:"product-folders",generation_id:"product-folders",workspace_roots:[$a,$b]}')
hook sessionStart "$product_roots" >/dev/null
product_untargeted=$(printf '%s\n' "$product_roots" | jq -c \
  '. + {tool_name:"createJiraIssue",url:"https://example.atlassian.net",tool_input:{body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$product_untargeted")" TARGET_REQUIRED
product_bb=$(printf '%s\n' "$product_roots" | jq -c '
  . + {
    tool_name:"createJiraIssue",
    url:"https://example.atlassian.net",
    tool_input:{
      cloudId:"cloud",
      projectKey:"BB",
      issueTypeName:"Bug",
      parent:"BB-34",
      assignee_account_id:"712020:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      summary:"Pending wait for opaque SID rotation",
      description:"Work-item language: English\n\nGitHub: N/A\n\nRelated: Beroka_Frontend layout.",
      additional_fields:{priority:{name:"Highest"}}
    }
  }')
product_bb_output=$(hook beforeMCPExecution "$product_bb")
assert_not_contains "$product_bb_output" 'TARGET_REQUIRED'
assert_not_contains "$product_bb_output" 'WORK_ITEM_TEMPLATE_REQUIRED'
assert_not_contains "$product_bb_output" 'Missing:'
# Cursor IDE may stringify tool_input; parse it so structured BB fields still win.
product_bb_string=$(printf '%s\n' "$product_bb" | jq -c '
  .tool_input = (.tool_input | tojson)
')
product_bb_string_output=$(hook beforeMCPExecution "$product_bb_string")
assert_not_contains "$product_bb_string_output" 'TARGET_REQUIRED'
assert_not_contains "$product_bb_string_output" 'WORK_ITEM_TEMPLATE_REQUIRED'
assert_not_contains "$product_bb_string_output" 'Missing:'
# Opposite-team private link in tool_input still denied after target selection.
product_cross=$(printf '%s\n' "$product_bb" | jq -c \
  '.tool_input.description += "\nhttps://github.com/beroka-vn/Beroka_Frontend/issues/1"')
assert_denied "$(hook beforeMCPExecution "$product_cross")" CROSS_TEAM_LINK_SCOPE_DENIED

# Hook PATH without ~/.local/bin must still find bootstrap-installed cursor-agent.
mkdir -p "$HOME/.local/bin"
printf '%s\n' \
  '#!/bin/sh' \
  'case "$*" in' \
  '  --version) printf "cursor-agent 1.0.0\n" ;;' \
  '  "mcp list") printf "%s\n" "$*" >>"$CONNECTOR_CALLS"; printf "atlassian: Ready\n" ;;' \
  '  "mcp list-tools atlassian") printf "%s\n" "$*" >>"$CONNECTOR_CALLS"; printf "%s\n" "- createConfluencePage ()" "- getAccessibleAtlassianResources ()" "- getConfluencePage ()" "- updateConfluencePage ()" ;;' \
  'esac' \
  >"$HOME/.local/bin/cursor-agent"
chmod 755 "$HOME/.local/bin/cursor-agent"
path_create='gh issue create --title "Fix opaque session" --body "Work-item language: English" --label area:governance --label priority:p1 --label Task --repo beroka-vn/beroka-ai-governance'
path_shell=$(jq -nc --arg command "$path_create" --arg a "$product_backend" --arg b "$product_frontend" \
  '{conversation_id:"shell-path",generation_id:"shell-path",workspace_roots:[$a,$b],command:$command}')
path_output=$(PATH="/usr/bin:/bin" hook beforeShellExecution "$path_shell")
assert_not_contains "$path_output" 'DEPENDENCY_MISSING'
assert_not_contains "$path_output" 'WORK_ITEM_TEMPLATE_REQUIRED'

printf '%s\n' BE >"$XDG_CONFIG_HOME/beroka-ai-governance/github-role"

hook sessionStart "$base_input" >/dev/null
github_write=$(printf '%s\n' "$base_input" | jq -c '. + {tool_name:"github.create_issue",url:"https://github.com",tool_input:{body:"Work-item language: English"}}')
github_read=$(printf '%s\n' "$base_input" | jq -c '. + {tool_name:"github.get_issue",url:"https://github.com",tool_input:{}}')
assert_contains "$(hook beforeMCPExecution "$github_read")" '"permission":"allow"'
hook beforeSubmitPrompt "$prompt_vi" >/dev/null
assert_denied "$(hook beforeMCPExecution "$github_write")" WORK_ITEM_LANGUAGE_REQUIRED
hook beforeSubmitPrompt "$base_input" >/dev/null
for invalid in \
  "$(printf '%s\n' "$github_write" | jq -c '.generation_id="other"')" \
  "$(printf '%s\n' "$github_write" | jq -c '.workspace_roots=["/tmp/other"]')"; do
  output=$(hook beforeMCPExecution "$invalid")
  assert_denied "$output" GOVERNANCE_CONTEXT_REQUIRED
done
receipt_backup=$TMP_ROOT/receipt-backup
cp "$receipt" "$receipt_backup"
for field in version repository; do
  jq --arg field "$field" '.[$field] = "mismatch"' "$receipt_backup" >"$receipt"
  assert_denied "$(hook beforeMCPExecution "$github_write")" GOVERNANCE_CONTEXT_REQUIRED
  cp "$receipt_backup" "$receipt"
done

jira_write=$(printf '%s\n' "$base_input" | jq -c '. + {tool_name:"jira.create_issue",url:"https://example.atlassian.net",tool_input:{body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$jira_write")" WORK_ITEM_TEMPLATE_REQUIRED

# Official Atlassian MCP createJiraIssue shape must pass template checks.
atlassian_create=$(printf '%s\n' "$base_input" | jq -c '
  . + {
    tool_name:"createJiraIssue",
    url:"https://example.atlassian.net",
    tool_input:{
      cloudId:"cloud",
      projectKey:"BB",
      issueTypeName:"Bug",
      parent:"BB-34",
      assignee_account_id:"712020:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      summary:"Pending wait for in-flight opaque SID rotation",
      description:"Work-item language: English\n\nGitHub: N/A\n\nFix concurrent refresh cookie clear.",
      additional_fields:{priority:{name:"Highest"}}
    }
  }')
atlassian_create_output=$(hook beforeMCPExecution "$atlassian_create")
assert_not_contains "$atlassian_create_output" 'WORK_ITEM_TEMPLATE_REQUIRED'
assert_not_contains "$atlassian_create_output" 'Missing:'

atlassian_missing_assignee=$(printf '%s\n' "$atlassian_create" | jq -c 'del(.tool_input.assignee_account_id)')
atlassian_missing_output=$(hook beforeMCPExecution "$atlassian_missing_assignee")
assert_denied "$atlassian_missing_output" WORK_ITEM_TEMPLATE_REQUIRED
assert_contains "$atlassian_missing_output" 'Missing:'
assert_contains "$atlassian_missing_output" 'assignee_account_id|assignee|owner'

jira_update_by_key=$(printf '%s\n' "$base_input" | jq -c \
  '. + {tool_name:"jira.update_issue",url:"https://example.atlassian.net",tool_input:{issueKey:"BB-123",body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$jira_update_by_key")" CLIENT_INSTRUCTION_REQUIRED
cross_team_update_by_key=$(printf '%s\n' "$jira_update_by_key" | jq -c \
  '.tool_input.issueKey="BF-123"')
assert_denied "$(hook beforeMCPExecution "$cross_team_update_by_key")" ROUTING_REQUIRED
intake_base=$(printf '%s\n' "$base_input" | jq -c \
  '. + {tool_name:"jira.create_issue",url:"https://example.atlassian.net",tool_input:{projectKey:"BF",issue_type:"Task",requester:"requester-account",priority:"P2",github:"N/A",body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$intake_base" | jq -c '.tool_input.assignee="frontend-developer"')")" WORK_ITEM_TEMPLATE_REQUIRED
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$intake_base" | jq -c '.tool_input.parent="BF-1"')")" WORK_ITEM_TEMPLATE_REQUIRED
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$intake_base" | jq -c 'del(.tool_input.requester)')")" WORK_ITEM_TEMPLATE_REQUIRED
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$intake_base" | jq -c '.tool_input.projectKey="XX"')")" ROUTING_REQUIRED
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$intake_base" | jq -c '.tool_name="jira.update_issue"')")" ROUTING_REQUIRED
ordinary_unassigned=$(printf '%s\n' "$intake_base" | jq -c '.tool_input.projectKey="BB"')
assert_denied "$(hook beforeMCPExecution "$ordinary_unassigned")" WORK_ITEM_TEMPLATE_REQUIRED
for private_repo in Beroka_Backend Beroka_Frontend; do
  private_link_intake=$(printf '%s\n' "$intake_base" | jq -c \
    --arg link "https://github.com/beroka-vn/$private_repo/issues/138" \
    '.tool_input.body += ("\n" + $link)')
  assert_denied "$(hook beforeMCPExecution "$private_link_intake")" CROSS_TEAM_LINK_SCOPE_DENIED
done
same_team_private_link=$(printf '%s\n' "$jira_write" | jq -c \
  '.tool_input.github="https://github.com/beroka-vn/Beroka_Backend/issues/138"')
assert_denied "$(hook beforeMCPExecution "$same_team_private_link")" WORK_ITEM_TEMPLATE_REQUIRED
for opposite_private_link in \
  'https://github.com/beroka-vn/Beroka_Frontend/issues/138' \
  'git@github.com:beroka-vn/Beroka_Frontend.git' \
  'beroka-vn/Beroka_Frontend/issues/138'
do
  opposite_team_private_link=$(printf '%s\n' "$jira_write" | jq -c \
    --arg link "$opposite_private_link" '.tool_input.github=$link')
  assert_denied "$(hook beforeMCPExecution "$opposite_team_private_link")" \
    CROSS_TEAM_LINK_SCOPE_DENIED
done

printf '%s\n' cursor >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"
git --git-dir=/dev/null hash-object --no-filters \
  "$release/templates/agent-entrypoints/CURSOR-USER-RULE.txt" \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"
jira_transition=$(printf '%s\n' "$base_input" | jq -c '. + {
  tool_name:"jira.transition_issue",
  url:"https://example.atlassian.net",
  tool_input:{
    issueKey:"BB-123",
    status:"In Review",
    body:"Work-item language: English"
  }}')
assert_denied "$(hook beforeMCPExecution "$jira_transition")" GITHUB_AUTH_REQUIRED
jira_cross_team_transition=$(printf '%s\n' "$jira_transition" | jq -c \
  '.tool_input.issueKey="BF-123"')
assert_denied "$(hook beforeMCPExecution "$jira_cross_team_transition")" ROUTING_REQUIRED

jira_cross_team_body=$(printf '%s\n' \
  'Work-item language: English' \
  'GitHub: N/A' \
  'Provider Jira: BB-42' \
  'Consumer Jira: BF-69' \
  'Confluence content ID: 900001')
cursor_intake=$(printf '%s\n' "$intake_base" | jq -c --arg body "$jira_cross_team_body" \
  '.tool_input.body=$body | .tool_input.github="N/A"')
cursor_handoff_update=$(printf '%s\n' "$jira_update_by_key" | jq -c \
  --arg body "$jira_cross_team_body" '.tool_input.body=$body')
for cursor_jira_request in "$cursor_intake" "$cursor_handoff_update"; do
  cursor_jira_output=$(hook beforeMCPExecution "$cursor_jira_request")
  assert_not_contains "$cursor_jira_output" CROSS_TEAM_LINK_SCOPE_DENIED
  assert_denied "$cursor_jira_output" GITHUB_AUTH_REQUIRED
  for forbidden_body in \
    'https://github.com/example/private' \
    'git@github.com:example/private.git' \
    'Repository: use the provider repository as contract evidence'
  do
    assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$cursor_jira_request" | \
      jq -c --arg body "$forbidden_body" '.tool_input.body += ("\n" + $body)')")" \
      CROSS_TEAM_LINK_SCOPE_DENIED
  done
done
assert_no_cursor_body_stage

# A malformed/empty cross-team marker still classifies the update as a
# handoff, and every accepted text-bearing field participates in isolation.
cursor_malformed_handoff=$(printf '%s\n' "$jira_update_by_key" | jq -c '
  .tool_input.body="Work-item language: English\n* pRoViDeR JiRa :"
  | .tool_input.github="https://github.com/example/private"
')
assert_denied "$(hook beforeMCPExecution "$cursor_malformed_handoff")" \
  CROSS_TEAM_LINK_SCOPE_DENIED
for jira_text_field in description comment content github summary; do
  cursor_field_bypass=$(printf '%s\n' "$cursor_handoff_update" | jq -c \
    --arg field "$jira_text_field" \
    '.tool_input[$field]="Repository: use the provider repository as contract evidence"')
  assert_denied "$(hook beforeMCPExecution "$cursor_field_bypass")" \
    CROSS_TEAM_LINK_SCOPE_DENIED
done
cursor_summary_github_bypass=$(printf '%s\n' "$cursor_handoff_update" | jq -c \
  '.tool_input.summary="https://github.com/example/private"')
assert_denied "$(hook beforeMCPExecution "$cursor_summary_github_bypass")" \
  CROSS_TEAM_LINK_SCOPE_DENIED
cursor_summary_intent=$(printf '%s\n' "$jira_update_by_key" | jq -c '
  .tool_input.summary="## Provider Jira"
  | .tool_input.github="https://github.com/example/private"
')
assert_denied "$(hook beforeMCPExecution "$cursor_summary_intent")" \
  CROSS_TEAM_LINK_SCOPE_DENIED
cursor_github_bypass=$(printf '%s\n' "$cursor_intake" | jq -c \
  '.tool_input.github="https://github.com/example/private"')
assert_denied "$(hook beforeMCPExecution "$cursor_github_bypass")" \
  CROSS_TEAM_LINK_SCOPE_DENIED

# Plain acknowledgment language plus Confluence evidence is cross-team even
# without the new handoff labels, and every textual input value is isolated.
cursor_plain_ack=$(printf '%s\n' "$jira_update_by_key" | jq -c '
  .tool_input.body="Work-item language: English\nAcknowledged Confluence page 900001 version 3 for review."
  | .tool_input.metadata={evidence:"https://github.com/example/private"}
')
assert_denied "$(hook beforeMCPExecution "$cursor_plain_ack")" \
  CROSS_TEAM_LINK_SCOPE_DENIED
cursor_pair_ack=$(printf '%s\n' "$jira_update_by_key" | jq -c '
  .tool_input.body="Work-item language: English\nBB-42 and BF-69 are aligned on Confluence content 900001."
  | .tool_input.custom_text="Repository: use the provider repository as evidence"
')
assert_denied "$(hook beforeMCPExecution "$cursor_pair_ack")" \
  CROSS_TEAM_LINK_SCOPE_DENIED
assert_no_cursor_body_stage

team_local_github=$(printf '%s\n' "$atlassian_create" | jq -c \
  '.tool_input.description="Work-item language: English\n\nGitHub: N/A"
   | .tool_input.github="https://github.com/beroka-vn/Beroka_Backend/issues/138"')
team_local_output=$(hook beforeMCPExecution "$team_local_github")
assert_not_contains "$team_local_output" CROSS_TEAM_LINK_SCOPE_DENIED
assert_denied "$team_local_output" GITHUB_AUTH_REQUIRED

# Any new handoff header routes the exact MCP body through the shared validator.
cursor_handoff_input() {
  chi_fixture=$1 chi_action=$2 chi_target=$3 chi_parent=$4
  chi_body=$(cat "$chi_fixture")
  printf '%s\n' "$base_input" | jq -c \
    --arg body "$chi_body" --arg target "$chi_target" --arg parent "$chi_parent" \
    --arg action "$chi_action" '
      . + {
        tool_name:(if $action == "create" then "createConfluencePage" else "confluence.update_page" end),
        url:"https://beroka.atlassian.net/wiki",
        tool_input:({parentId:$parent, body:$body} +
          if $action == "create" then {title:"Handoff — BB-42 — quotes"}
          else {pageId:$target} end)
      }'
}

cursor_handoff_dir=$TMP_ROOT/cursor-handoffs
mkdir -p "$cursor_handoff_dir"
cp "$ROOT/tests/fixtures/handoffs/draft.md" "$cursor_handoff_dir/draft.md"
cp "$ROOT/tests/fixtures/handoffs/ready-no-impact.md" "$cursor_handoff_dir/ready.md"
cp "$ROOT/tests/fixtures/handoffs/ready-api.md" "$cursor_handoff_dir/ready-api.md"
cp "$ROOT/tests/fixtures/handoffs/ready-websocket.md" "$cursor_handoff_dir/ready-websocket.md"
cp "$ROOT/tests/fixtures/handoffs/incident-85360641.md" "$cursor_handoff_dir/incident.md"

assert_denied "$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/incident.md" update 85360641 76808195)")" \
  CROSS_TEAM_LINK_SCOPE_DENIED
printf '%s\n' 'Handoff schema: 1' >"$cursor_handoff_dir/partial.md"
assert_denied "$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/partial.md" create new 76808195)")" HANDOFF_BODY_INVALID
assert_denied "$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/draft.md" create new 65962274)")" FOLDER_CREATION_REQUIRED

: >"$CONNECTOR_CALLS"
for cursor_header_case in missing-scope missing-domain scope-before-consumer \
  domain-before-scope duplicate-scope duplicate-domain scope-mismatch domain-mismatch
do
  cursor_header_file=$cursor_handoff_dir/$cursor_header_case.md
  case "$cursor_header_case" in
    missing-scope) sed '/^Scope: Shared$/d' "$cursor_handoff_dir/ready.md" >"$cursor_header_file" ;;
    missing-domain) sed '/^Domain: Market$/d' "$cursor_handoff_dir/ready.md" >"$cursor_header_file" ;;
    scope-before-consumer)
      sed '/^Scope: Shared$/d; /^Provider Jira: BB-42$/a\Scope: Shared' \
        "$cursor_handoff_dir/ready.md" >"$cursor_header_file"
      ;;
    domain-before-scope)
      sed '/^Domain: Market$/d; /^Consumer Jira: BF-69$/a\Domain: Market' \
        "$cursor_handoff_dir/ready.md" >"$cursor_header_file"
      ;;
    duplicate-scope) sed '/^Domain: Market$/a\Scope: Shared' "$cursor_handoff_dir/ready.md" >"$cursor_header_file" ;;
    duplicate-domain) sed '/^Domain: Market$/a\Domain: Market' "$cursor_handoff_dir/ready.md" >"$cursor_header_file" ;;
    scope-mismatch) sed 's/^Scope: Shared$/Scope: Product/' "$cursor_handoff_dir/ready.md" >"$cursor_header_file" ;;
    domain-mismatch) sed 's/^Domain: Market$/Domain: Broker accounts/' "$cursor_handoff_dir/ready.md" >"$cursor_header_file" ;;
  esac
  case "$cursor_header_case" in
    scope-mismatch|domain-mismatch) cursor_header_result=FOLDER_CREATION_REQUIRED ;;
    *) cursor_header_result=HANDOFF_BODY_INVALID ;;
  esac
  assert_denied "$(hook beforeMCPExecution "$(cursor_handoff_input \
    "$cursor_header_file" update 900001 76808195)")" "$cursor_header_result"
done
[ ! -s "$CONNECTOR_CALLS" ] || fail 'invalid handoff scope/domain inspected a connector'

cp "$cursor_handoff_dir/ready.md" "$cursor_handoff_dir/github.md"
printf '\nhttps://github.com/example/private\n' >>"$cursor_handoff_dir/github.md"
assert_denied "$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/github.md" update 900001 76808195)")" \
  CROSS_TEAM_LINK_SCOPE_DENIED
sed '/^## Affected API inventory$/d' "$cursor_handoff_dir/ready-api.md" \
  >"$cursor_handoff_dir/missing-api.md"
assert_denied "$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/missing-api.md" update 900001 76808195)")" HANDOFF_BODY_INVALID
sed '/^## Affected WebSocket inventory$/d' "$cursor_handoff_dir/ready-websocket.md" \
  >"$cursor_handoff_dir/missing-websocket.md"
assert_denied "$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/missing-websocket.md" update 900001 76808195)")" HANDOFF_BODY_INVALID
for cursor_readiness_claim in \
  READY_FOR_FE 'Ready for FE' ready_for_fe '**Ready-for-FE**'
do
  cp "$cursor_handoff_dir/draft.md" "$cursor_handoff_dir/false-ready.md"
  printf '\n%s\n' "$cursor_readiness_claim" \
    >>"$cursor_handoff_dir/false-ready.md"
  assert_denied "$(hook beforeMCPExecution "$(cursor_handoff_input \
    "$cursor_handoff_dir/false-ready.md" create new 76808195)")" \
    HANDOFF_BODY_INVALID
done

cp "$cursor_handoff_dir/ready.md" "$cursor_handoff_dir/private-identity.md"
printf '\nProvider source: Beroka_Backend\n' \
  >>"$cursor_handoff_dir/private-identity.md"
cursor_private_identity_output=$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/private-identity.md" update 900001 76808195)")
assert_denied "$cursor_private_identity_output" CROSS_TEAM_LINK_SCOPE_DENIED
assert_not_contains "$cursor_private_identity_output" Beroka_Backend

assert_denied "$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/ready-websocket.md" update 900004 76808195)")" \
  FOLDER_CREATION_REQUIRED

# The exact legacy incident shape must never fall back to ordinary
# confluence-write merely because it predates the schema-1 labels.
legacy_incident_body=$(printf '%s\n' \
  'Jira: BB-42' \
  'GitHub: https://github.com/beroka-vn/Beroka_Backend/issues/217' \
  'State: READY_FOR_FE' \
  'Provider Jira: BB-42' \
  'Consumer Jira: BF-69' \
  '' \
  '## Handoff — BB-42' \
  '' \
  'Summary-only payload guidance.')
legacy_incident=$(printf '%s\n' "$base_input" | jq -c --arg body "$legacy_incident_body" '. + {
  tool_name:"confluence.update_page",
  url:"https://beroka.atlassian.net/wiki",
  tool_input:{pageId:"85360641",parentId:"65962274",body:$body}
}')
assert_denied "$(hook beforeMCPExecution "$legacy_incident")" \
  CROSS_TEAM_LINK_SCOPE_DENIED

cursor_draft_output=$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/draft.md" create new 76808195)")
assert_not_contains "$cursor_draft_output" HANDOFF_DELTA_REQUIRED
assert_not_contains "$cursor_draft_output" HANDOFF_BODY_INVALID
assert_not_contains "$cursor_draft_output" CLIENT_BODY_GATE_REQUIRED
assert_denied "$cursor_draft_output" GITHUB_AUTH_REQUIRED
cursor_ready_output=$(hook beforeMCPExecution "$(cursor_handoff_input \
  "$cursor_handoff_dir/ready.md" update 900001 76808195)")
assert_not_contains "$cursor_ready_output" HANDOFF_DELTA_REQUIRED
assert_not_contains "$cursor_ready_output" HANDOFF_BODY_INVALID
assert_not_contains "$cursor_ready_output" CLIENT_BODY_GATE_REQUIRED
assert_denied "$cursor_ready_output" GITHUB_AUTH_REQUIRED
assert_no_cursor_body_stage

# A parser exit must not strand the already-staged body.
cursor_parser_failure=$(cursor_handoff_input \
  "$cursor_handoff_dir/ready.md" update --bad 76808195)
assert_denied "$(hook beforeMCPExecution "$cursor_parser_failure")" MAPPING_CONFLICT
assert_no_cursor_body_stage

# Signal the hook after stage creation but before jq writes the body.
slow_bin=$TMP_ROOT/slow-bin
mkdir -p "$slow_bin"
printf '%s\n' \
  '#!/bin/sh' \
  'if [ "${SLOW_STAGE_JQ:-0}" = 1 ] && [ "${1:-}" = -jr ]; then' \
  '  : >"$STAGE_WRITE_MARKER"' \
  '  sleep 5' \
  'fi' \
  'exec /usr/bin/jq "$@"' \
  >"$slow_bin/jq"
chmod 755 "$slow_bin/jq"
STAGE_WRITE_MARKER=$TMP_ROOT/stage-write-started
export STAGE_WRITE_MARKER
SLOW_STAGE_JQ=1
export SLOW_STAGE_JQ
printf '%s\n' "$cursor_intake" |
  PATH="$slow_bin:$PATH" "$CLI" cursor-hook beforeMCPExecution \
  >"$TMP_ROOT/stage-signal-output" 2>&1 &
stage_hook_pid=$!
stage_waits=0
while [ ! -f "$STAGE_WRITE_MARKER" ] && [ "$stage_waits" -lt 100 ]; do
  sleep 0.01
  stage_waits=$((stage_waits + 1))
done
[ -f "$STAGE_WRITE_MARKER" ] || fail 'Cursor did not begin staged body write'
kill -TERM "$stage_hook_pid"
wait "$stage_hook_pid" 2>/dev/null || :
unset SLOW_STAGE_JQ STAGE_WRITE_MARKER
assert_no_cursor_body_stage

confluence_handoff_body=$(printf '%s\n' \
  'Jira: BB-11' \
  'GitHub: N/A' \
  '' \
  '## Handoff — BB-11' \
  '' \
  'Delta for FE.')
confluence_update=$(printf '%s\n' "$base_input" | jq -c --arg body "$confluence_handoff_body" '. + {
  tool_name:"confluence.update_page",
  url:"https://beroka.atlassian.net/wiki",
  tool_input:{
    pageId:"70713366",
    parentId:"71303169",
    body:$body
  }}')
confluence_update_out=$(hook beforeMCPExecution "$confluence_update")
assert_not_contains "$confluence_update_out" HANDOFF_DELTA_REQUIRED
assert_not_contains "$confluence_update_out" DOCS_UNACTIVATED
assert_not_contains "$confluence_update_out" CLIENT_BODY_GATE_REQUIRED
# Handoff markers clear the docs gate; harness still lacks gh auth for role check.
assert_denied "$confluence_update_out" GITHUB_AUTH_REQUIRED
confluence_private_link=$(printf '%s\n' "$confluence_update" | jq -c \
  '.tool_input.body += "\nRelated repository: git@github.com:beroka-vn/Beroka_Frontend.git"')
assert_denied "$(hook beforeMCPExecution "$confluence_private_link")" \
  CROSS_TEAM_LINK_SCOPE_DENIED
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$confluence_update" | jq -c '.tool_input.body="missing handoff markers"')")" \
  HANDOFF_DELTA_REQUIRED
confluence_create=$(printf '%s\n' "$base_input" | jq -c --arg body "$confluence_handoff_body" '. + {
  tool_name:"createConfluencePage",
  url:"https://beroka.atlassian.net/wiki",
  tool_input:{
    parentId:"76808195",
    title:"New docs page",
    body:$body
  }}')
for malformed_handoff_marker in \
  'Handoff schema : 1' \
  '- handoff STATE: DRAFT' \
  '* handoff state : DRAFT' \
  '## Handoff schema: 1' \
  '> Provider Jira: BB-42' \
  '  Provider jira : BB-42' \
  '1. Consumer Jira : BF-69' \
  '### FE acknowledgment' \
  '- CONSUMER JIRA:'
do
  confluence_marker_bypass=$(printf '%s\n' "$confluence_create" | jq -c \
    --arg marker "$malformed_handoff_marker" \
    '.tool_input.body += ("\n" + $marker)')
  assert_denied "$(hook beforeMCPExecution "$confluence_marker_bypass")" \
    HANDOFF_BODY_INVALID
done
for ordinary_handoff_prose in \
  'This paragraph explains how the provider Jira remains linked.' \
  'This paragraph discusses API impact without declaring a header.'
do
  confluence_prose=$(printf '%s\n' "$confluence_create" | jq -c \
    --arg prose "$ordinary_handoff_prose" \
    '.tool_input.body += ("\n" + $prose)')
  confluence_prose_out=$(hook beforeMCPExecution "$confluence_prose")
  assert_not_contains "$confluence_prose_out" HANDOFF_BODY_INVALID
  assert_denied "$confluence_prose_out" GITHUB_AUTH_REQUIRED
done
for restored_handoff_marker in \
  '> ## Confluence content ID : new' \
  '- 1. Confluence page version : pending' \
  '+ Owner account ID : account-123' \
  '* Effective date : 2026-08-25' \
  '2) Supersedes : N/A' \
  '## > Superseded by : N/A' \
  '> - API impact : none' \
  '3. WebSocket impact : none' \
  '### Missing sections : FE acknowledgment'
do
  confluence_restored_marker=$(printf '%s\n' "$confluence_create" | jq -c \
    --arg marker "$restored_handoff_marker" \
    '.tool_input.body += ("\n" + $marker)')
  assert_denied "$(hook beforeMCPExecution "$confluence_restored_marker")" \
    HANDOFF_BODY_INVALID
done
assert_no_cursor_body_stage
confluence_create_out=$(hook beforeMCPExecution "$confluence_create")
assert_not_contains "$confluence_create_out" HANDOFF_DELTA_REQUIRED
assert_not_contains "$confluence_create_out" DOCS_UNACTIVATED
assert_not_contains "$confluence_create_out" CLIENT_BODY_GATE_REQUIRED
assert_denied "$confluence_create_out" GITHUB_AUTH_REQUIRED
if direct_cursor_preflight=$($CLI preflight "$known_repo" --client cursor \
  --operation confluence-write --non-interactive \
  --confluence-action create --target-content-id new \
  --expected-parent-id 76808195 2>&1)
then
  fail 'direct Cursor Confluence create passed without a trusted body'
fi
assert_contains "$direct_cursor_preflight" 'Result: CLIENT_BODY_GATE_REQUIRED'
confluence_create_no_handoff=$(printf '%s\n' "$confluence_create" | jq -c \
  '.tool_input.body="create without handoff"')
assert_denied "$(hook beforeMCPExecution "$confluence_create_no_handoff")" \
  HANDOFF_DELTA_REQUIRED
confluence_bad_jira=$(printf '%s\n' "$confluence_create" | jq -c \
  --arg body "$(printf '%s\n' 'Jira: TBD' 'GitHub: N/A' '' '## Handoff — BB-11' '' 'x')" \
  '.tool_input.body=$body')
assert_denied "$(hook beforeMCPExecution "$confluence_bad_jira")" HANDOFF_DELTA_REQUIRED
confluence_child_no_canonical=$(printf '%s\n' "$base_input" | jq -c '. + {
  tool_name:"createConfluencePage",
  url:"https://beroka.atlassian.net/wiki",
  tool_input:{
    parentId:"76808195",
    title:"Handoff — BB-11 — e2e",
    body:"Jira: BB-11\nGitHub: N/A\nHandoff form: child-page\n"
  }}')
assert_denied "$(hook beforeMCPExecution "$confluence_child_no_canonical")" \
  HANDOFF_DELTA_REQUIRED
confluence_child_ok=$(printf '%s\n' "$confluence_child_no_canonical" | jq -c \
  '.tool_input.body += "Canonical: 76808195\n"')
confluence_child_ok_out=$(hook beforeMCPExecution "$confluence_child_ok")
assert_not_contains "$confluence_child_ok_out" HANDOFF_DELTA_REQUIRED
assert_denied "$confluence_child_ok_out" GITHUB_AUTH_REQUIRED
confluence_move=$(printf '%s\n' "$base_input" | jq -c '. + {
  tool_name:"confluence.move_page",
  url:"https://beroka.atlassian.net/wiki",
  tool_input:{
    pageId:"70713366",
    parentId:"76808195"
  }}')
confluence_move_out=$(hook beforeMCPExecution "$confluence_move")
assert_not_contains "$confluence_move_out" HANDOFF_DELTA_REQUIRED
assert_denied "$confluence_move_out" GITHUB_AUTH_REQUIRED
confluence_move_no_parent=$(printf '%s\n' "$confluence_move" | jq -c \
  'del(.tool_input.parentId)')
assert_denied "$(hook beforeMCPExecution "$confluence_move_no_parent")" \
  ROUTING_REQUIRED
unknown_write=$(printf '%s\n' "$base_input" | jq -c '. + {tool_name:"create_record",url:"https://github.com",tool_input:{body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$unknown_write")" WORK_ITEM_TEMPLATE_REQUIRED

for command in \
  'gh issue create --title x' 'gh issue edit 1 --title x' \
  'gh pr create --title x' 'gh pr edit 1 --title x' \
  'gh api -X POST repos/o/r/issues' 'gh api --method PATCH repos/o/r/pulls/1' \
  'gh api --method DELETE repos/o/r/issues/comments/1'; do
  output=$(hook beforeShellExecution "$(jq -nc --arg command "$command" '{conversation_id:"shell",generation_id:"shell",workspace_roots:["/tmp/none"],command:$command}')")
  assert_denied "$output" WORK_ITEM_TEMPLATE_REQUIRED
done
for command in 'gh issue view 1' 'git status'; do
  output=$(hook beforeShellExecution "$(jq -nc --arg command "$command" '{conversation_id:"shell",generation_id:"shell",workspace_roots:["/tmp/none"],command:$command}')")
  assert_contains "$output" '"permission":"allow"'
done
# Templated gh issue create advances past the template gate when workspace roots
# resolve; further connector auth may still deny.
templated_create='gh issue create --title "Fix opaque session" --body "Work-item language: English" --label area:governance --label priority:p1 --label type:technical --repo beroka-vn/Beroka_Backend'
templated_shell=$(jq -nc --arg command "$templated_create" --arg workspace "$known_repo" \
  '{conversation_id:"shell-template",generation_id:"shell-template",workspace_roots:[$workspace],command:$command}')
templated_output=$(hook beforeShellExecution "$templated_shell")
assert_denied "$templated_output" GITHUB_AUTH_REQUIRED
assert_not_contains "$templated_output" WORK_ITEM_TEMPLATE_REQUIRED
quoted_create='gh issue create --title "Fix opaque session" --body "Work-item language: English" --label "area:governance" --label "priority:p1" --label "Task" --repo beroka-vn/Beroka_Backend'
quoted_shell=$(jq -nc --arg command "$quoted_create" --arg workspace "$known_repo" \
  '{conversation_id:"shell-quoted",generation_id:"shell-quoted",workspace_roots:[$workspace],command:$command}')
quoted_output=$(hook beforeShellExecution "$quoted_shell")
assert_denied "$quoted_output" GITHUB_AUTH_REQUIRED
assert_not_contains "$quoted_output" WORK_ITEM_TEMPLATE_REQUIRED

# beforeSubmitPrompt blocks a malformed Work-item language directive by emitting
# {"continue":false} with exit 0 (not a non-zero exit, which Cursor fails open).
selfheal_base=$(jq -nc --arg workspace "$known_repo" \
  '{conversation_id:"conversation-heal",generation_id:"generation-heal",workspace_roots:[$workspace]}')
hook sessionStart "$selfheal_base" >/dev/null
malformed_prompt=$(printf '%s\n' "$selfheal_base" | jq -c '. + {prompt:"Work-item language: 日本語"}')
malformed_submit=$(hook beforeSubmitPrompt "$malformed_prompt")
assert_contains "$malformed_submit" '"continue":false'
assert_contains "$malformed_submit" 'WORK_ITEM_LANGUAGE_REQUIRED'
wellformed_prompt=$(printf '%s\n' "$selfheal_base" | jq -c '. + {prompt:"Work-item language: English"}')
case "$(hook beforeSubmitPrompt "$wellformed_prompt")" in
  *'"continue":false'*) fail 'well-formed prompt was blocked' ;;
esac

# After preCompact clears the receipt, a fresh beforeSubmitPrompt re-establishes
# it within the same conversation so governed writes are not permanently locked.
selfheal_read=$(printf '%s\n' "$selfheal_base" | jq -c \
  '. + {tool_name:"github.get_issue",url:"https://github.com",tool_input:{}}')
assert_contains "$(hook beforeMCPExecution "$selfheal_read")" '"permission":"allow"'
hook preCompact "$selfheal_base" >/dev/null
assert_denied "$(hook beforeMCPExecution "$selfheal_read")" GOVERNANCE_CONTEXT_REQUIRED
hook beforeSubmitPrompt "$wellformed_prompt" >/dev/null
assert_contains "$(hook beforeMCPExecution "$selfheal_read")" '"permission":"allow"'

# A stale receipt from a previous release must self-heal on beforeSubmitPrompt
# so an upgrade does not force the user to open a new Cursor chat.
stale_base=$(jq -nc --arg workspace "$known_repo" \
  '{conversation_id:"conversation-stale",generation_id:"generation-stale",workspace_roots:[$workspace]}')
hook sessionStart "$stale_base" >/dev/null
stale_receipt=$(printf '%s' 'conversation-stale' | shasum -a 256 | awk '{print $1}')
stale_receipt_file=$XDG_STATE_HOME/beroka-ai-governance/cursor/$stale_receipt.json
[ -f "$stale_receipt_file" ] || fail 'stale-upgrade receipt was not created'
jq '.version = "v1.0.6" | .commit = "0000000000000000000000000000000000000000"' \
  "$stale_receipt_file" >"$TMP_ROOT/stale-receipt.json"
mv "$TMP_ROOT/stale-receipt.json" "$stale_receipt_file"
stale_prompt=$(printf '%s\n' "$stale_base" | jq -c \
  '. + {prompt:"Work-item language: English"}')
case "$(hook beforeSubmitPrompt "$stale_prompt")" in
  *'"continue":false'*) fail 'stale receipt blocked beforeSubmitPrompt after upgrade' ;;
esac
assert_contains "$(jq -r .version "$stale_receipt_file")" v1.1.0
assert_contains "$(jq -r .commit "$stale_receipt_file")" "$release_commit"
stale_read=$(printf '%s\n' "$stale_base" | jq -c \
  '. + {tool_name:"github.get_issue",url:"https://github.com",tool_input:{}}')
assert_contains "$(hook beforeMCPExecution "$stale_read")" '"permission":"allow"'

# A successful staged preflight also removes its private body directory.
printf '%s\n' \
  '#!/bin/sh' \
  'case "$*" in' \
  '  --version|"auth status --help"|"api --help") ;;' \
  '  "auth status --hostname github.com") exit 0 ;;' \
  '  "api --paginate /user/teams") printf "[{\"slug\":\"backend\",\"organization\":{\"login\":\"beroka-vn\"}}]\n" ;;' \
  'esac' \
  >"$HOME/.local/bin/gh"
chmod 755 "$HOME/.local/bin/gh"
mkdir -p "$HOME/.cursor"
printf '%s\n' \
  '{"mcpServers":{"atlassian":{"url":"https://mcp.atlassian.com/v1/mcp/authv2"}}}' \
  >"$HOME/.cursor/mcp.json"
hook beforeSubmitPrompt "$base_input" >/dev/null
cursor_allow_output=$(PATH="$HOME/.local/bin:/usr/bin:/bin" \
  hook beforeMCPExecution "$(cursor_handoff_input \
    "$cursor_handoff_dir/draft.md" create new 76808195)")
assert_contains "$cursor_allow_output" '"permission":"allow"'
assert_no_cursor_body_stage

printf '%s\n' 'PASS: Cursor hook runtime'
