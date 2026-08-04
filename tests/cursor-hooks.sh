#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLI=$ROOT/bin/beroka-governance
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-cursor-hooks.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

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
unstarted_receipt=$(printf '%s' 'conversation-unstarted' | sha256sum | awk '{print $1}')
unstarted_receipt_file=$XDG_STATE_HOME/beroka-ai-governance/cursor/$unstarted_receipt.json
[ -f "$unstarted_receipt_file" ] || fail 'fresh Cursor receipt was not created'
assert_contains "$(jq -r .language "$unstarted_receipt_file")" en

prompt_vi=$(printf '%s\n' "$base_input" | jq -c '. + {prompt:"Work-item language: Vietnamese"}')
hook beforeSubmitPrompt "$prompt_vi" >/dev/null
base_receipt=$(printf '%s' 'conversation-1' | sha256sum | awk '{print $1}')
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
assert_denied "$(hook beforeMCPExecution "$fullstack_jira_untargeted")" GOVERNANCE_CONTEXT_REQUIRED
fullstack_jira_bb=$(printf '%s\n' "$fullstack_roots" | jq -c \
  '. + {tool_name:"jira.create_issue",url:"https://example.atlassian.net",tool_input:{projectKey:"BB",body:"Work-item language: English"}}')
assert_denied "$(hook beforeMCPExecution "$fullstack_jira_bb")" WORK_ITEM_TEMPLATE_REQUIRED
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
    '.tool_input.github=$link')
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
confluence_update=$(printf '%s\n' "$base_input" | jq -c '. + {
  tool_name:"confluence.update_page",
  url:"https://beroka.atlassian.net/wiki",
  tool_input:{
    pageId:"70713366",
    parentId:"71303169",
    body:"Capability ID: MARKET-FU-INDEX-API\nRegistry content ID: 900003\nScope: Shared\nDomain: Market\nTransport: API\nConfluence content ID: 70713366\nExpected parent ID: 71303169"
  }}')
assert_denied "$(hook beforeMCPExecution "$confluence_update")" MAPPING_CONFLICT
bulleted_confluence_body=$(printf '%s\n' "$confluence_update" |
  jq -r '.tool_input.body' | sed 's/^/- /')
bulleted_confluence_update=$(printf '%s\n' "$confluence_update" | jq -c \
  --arg body "$bulleted_confluence_body" '.tool_input.body=$body')
assert_denied "$(hook beforeMCPExecution "$bulleted_confluence_update")" \
  MAPPING_CONFLICT
confluence_private_link=$(printf '%s\n' "$confluence_update" | jq -c \
  '.tool_input.body += "\nRelated repository: git@github.com:beroka-vn/Beroka_Frontend.git"')
assert_denied "$(hook beforeMCPExecution "$confluence_private_link")" \
  CROSS_TEAM_LINK_SCOPE_DENIED
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$confluence_update" | jq -c 'del(.tool_input.parentId)')")" MAPPING_CONFLICT
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$confluence_update" | jq -c '.tool_input.parentId="71303170"')")" MAPPING_CONFLICT
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$confluence_update" | jq -c '.tool_name="confluence.move_page"')")" MAPPING_CONFLICT
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$confluence_update" | jq -c '.tool_input.body += "\nRegistry content ID: 900004"')")" ROUTING_REQUIRED
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$confluence_update" | jq -c '.tool_input.body |= sub("Confluence content ID: 70713366"; "Confluence content ID: 70713367")')")" MAPPING_CONFLICT
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
stale_receipt=$(printf '%s' 'conversation-stale' | sha256sum | awk '{print $1}')
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

printf '%s\n' 'PASS: Cursor hook runtime'
