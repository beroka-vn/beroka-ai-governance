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

base_input=$(jq -nc --arg workspace "$known_repo" '{conversation_id:"conversation-1",generation_id:"generation-1",workspace_roots:[$workspace]}')
hook() { printf '%s\n' "$2" | "$CLI" cursor-hook "$1"; }

session=$(hook sessionStart "$base_input")
assert_contains "$session" '"additional_context"'
assert_contains "$session" 'beroka-vn/Beroka_Backend'
assert_contains "$session" 'Version: v1.1.0'
assert_contains "$session" 'Routing: ROUTING_ACTIVE'

prompt_vi=$(printf '%s\n' "$base_input" | jq -c '. + {prompt:"Work-item language: Vietnamese"}')
hook beforeSubmitPrompt "$prompt_vi" >/dev/null
receipt=$(find "$XDG_STATE_HOME/beroka-ai-governance/cursor" -type f)
assert_contains "$(jq -r .language "$receipt")" vi
generation_two=$(printf '%s\n' "$base_input" | jq -c '.generation_id="generation-2"')
hook beforeSubmitPrompt "$generation_two" >/dev/null
assert_contains "$(jq -r .language "$receipt")" en

hook preCompact "$generation_two" >/dev/null
output=$(hook beforeMCPExecution "$(printf '%s\n' "$generation_two" | jq -c '. + {tool_name:"github.create_issue", url:"https://github.com", tool_input:{body:"Work-item language: English"}}')")
assert_denied "$output" GOVERNANCE_CONTEXT_REQUIRED

for invalid in '{' \
  "$(jq -nc --arg workspace "$TMP_ROOT/not-git" '{conversation_id:"bad",generation_id:"bad",workspace_roots:[$workspace]}')" \
  "$(jq -nc --arg workspace "$known_repo" '{conversation_id:"bad",generation_id:"bad",workspace_roots:[$workspace,$workspace]}')"; do
  if output=$(hook sessionStart "$invalid" 2>&1); then fail 'invalid session input passed'; fi
  assert_contains "$output" 'GOVERNANCE_CONTEXT_REQUIRED'
done

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

printf '%s\n' 'PASS: Cursor hook runtime'
