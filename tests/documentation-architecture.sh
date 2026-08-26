#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_text() {
  file=$1 text=$2
  grep -F -- "$text" "$ROOT/$file" >/dev/null ||
    fail "missing [$text] in $file"
}

reject_text() {
  file=$1 text=$2
  if grep -F -- "$text" "$ROOT/$file" >/dev/null; then
    fail "forbidden [$text] in $file"
  fi
}

require_count() {
  file=$1 text=$2 expected=$3
  actual=$(grep -F -c -- "$text" "$ROOT/$file" || :)
  [ "$actual" -eq "$expected" ] ||
    fail "expected [$text] $expected time(s) in $file, found $actual"
}

has_repository_governance_mutation() {
  file=$1
  awk '
    BEGIN { RS = "" }
    {
      carry_install = 0
      carry_target = 0
      sentences = split(tolower($0) " ", sentence, /[.!?][[:space:]]+/)
      for (s = 1; s <= sentences; s++) {
        install = carry_install
        target = carry_target
        carry_install = 0
        carry_target = 0
        sentence_install = 0
        sentence_target = 0
        denied = 0
        clauses = split(sentence[s], clause, /[;:]/)
        for (i = 1; i <= clauses; i++) {
          clause_install = clause[i] ~ /(governance[[:space:]]+(install|upgrade|bootstrap)|(install|upgrade|bootstrap)[[:space:]]+governance)/
          clause_target = clause[i] ~ /application[[:space:]]+(repository|repo)/ ||
            (clause[i] ~ /application/ && clause[i] ~ /(pull request|(^|[[:space:]])pr([^[:alpha:]]|$))/)
          action = clause[i] ~ /(^|[[:space:]])(pin|diff|add|commit|push)([^[:alpha:]]|$)/ ||
            clause[i] ~ /git[[:space:]]+(add|commit|push)/ ||
            clause[i] ~ /(add|write|create|commit).*\.beroka-governance\.lock/ ||
            clause[i] ~ /(open|create).*(pull request|[[:space:]]pr([^[:alpha:]]|$))/
          denial = clause[i] ~ /(does not|do not|never|ignore|ignores|ignored|without).*(pin|diff|add|commit|push|change|changes|changed|changing|\.beroka-governance\.lock|pull request|[[:space:]]pr([^[:alpha:]]|$))/
          if (denial) {
            install = 0
            target = 0
            denied = 1
            continue
          }
          sentence_install = sentence_install || clause_install
          sentence_target = sentence_target || clause_target
          install = install || clause_install
          target = target || clause_target
          if (install && target && action) {
            found = 1
            exit
          }
        }
        if (!denied) {
          carry_install = sentence_install
          carry_target = sentence_target
        }
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

require_text governance.md 'Backend Capability Registry'
require_text governance.md 'Shared — Market — API'
require_text governance.md 'globally unique'
require_text governance.md 'one semantic capability, one transport'
require_text governance.md \
  'Payload references, sanitized examples, and documented delta'
require_text workflow.md 'Registry row'

for file in templates/agent-entrypoints/AGENTS.md \
  templates/agent-entrypoints/CLAUDE.md \
  templates/agent-entrypoints/CURSOR-USER-RULE.txt; do
  require_text "$file" 'allow-by-default'
  require_text "$file" 'DOCS_UNACTIVATED'
  require_text "$file" 'ASSIGNEE_CONFIRMATION_REQUIRED'
  require_text "$file" 'opposite-team private GitHub links'
  require_text "$file" 'self-contained Jira-and-Confluence-only'
  require_text "$file" 'confluence-handoff-verify'
done
for file in runtime/rules/general.md governance.md workflow.md \
  templates/jira-confluence.md; do
  require_text "$file" 'confluence-handoff-verify'
  require_text "$file" 'MAPPING_CONFLICT'
done
for file in runtime/rules/work-items.md runtime/integrations/beroka-be-fe.md \
  governance.md workflow.md templates/jira-confluence.md; do
  require_text "$file" 'ASSIGNEE_CONFIRMATION_REQUIRED'
  require_text "$file" 'CROSS_TEAM_LINK_SCOPE_DENIED'
  require_text "$file" 'In Review'
done
for file in runtime/rules/general.md governance.md workflow.md \
  templates/jira-confluence.md; do
  require_text "$file" 'closes the current primary GitHub Issue'
  require_text "$file" 'exact linked Jira item'
  require_text "$file" 'already in `In Review`'
  require_text "$file" 'exact Confluence content ID'
  require_text "$file" 'ask the user'
  require_text "$file" 'documentation readback'
  require_text "$file" 'remains in `In Review`'
  require_text "$file" \
    'report the GitHub, Jira, and Confluence outcomes separately'
  require_text "$file" 'Report a blocked Jira or Confluence step separately'
  require_text "$file" 'do not reopen the GitHub Issue'
  reject_text "$file" 'In Review -> Done'
done
for file in runtime/rules/general.md governance.md workflow.md; do
  require_text "$file" '`Closes #<issue>` normally closes the GitHub Issue'
  require_text "$file" 'exact merge/link readback proves the delivered commit'
  require_text "$file" 'the close write is authorized'
done
for file in runtime/rules/work-items.md \
  runtime/integrations/beroka-be-fe.md; do
  reject_text "$file" 'closes the current primary GitHub Issue'
  reject_text "$file" \
    'report the GitHub, Jira, and Confluence outcomes separately'
done
reject_text templates/jira-confluence.md 'Frontend Jira/GitHub issue(s):'
require_text workflow.md 'requester/reporter may differ from executor/assignee'
require_text workflow.md \
  'Receiving-team executor and current assignee accountId are confirmed'
require_text workflow.md 'reads available Jira transitions first'
require_text workflow.md 'reads back the new Jira status'
require_text workflow.md 'status mismatch returns a failure'
require_text templates/jira-confluence.md 'provider-owned completion records'
require_text templates/jira-confluence.md 'consumer-facing cross-team handoff'
require_text templates/jira-confluence.md 'accessible Jira keys'
require_text templates/jira-confluence.md \
  'never opposite-team private GitHub links'
reject_text workflow.md 'Execution assignee matches requester by accountId'
reject_text governance.md 'The Hub row is the canonical mapping'

require_text runtime/rules/general.md 'Confluence content ID'
require_text runtime/rules/general.md 'CREATION_STATUS_UNKNOWN'
require_text runtime/rules/general.md 'Create once, then read back the returned key'
require_text runtime/rules/general.md 'never retry automatically'
require_text runtime/entrypoint.md 'sole routing source'
require_text runtime/entrypoint.md 'authorized governance-repository task'
require_text runtime/entrypoint.md \
  'IDE workspace or current Git repository changes'
require_text templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  'IDE workspace or current Git repository changes'
require_text templates/agent-entrypoints/AGENTS.md \
  'IDE workspace or current Git repository changes'
require_text templates/agent-entrypoints/CLAUDE.md \
  'IDE workspace or current Git repository changes'
reject_text runtime/entrypoint.md 'default-branch routing'
reject_text runtime/entrypoint.md 'Pending local routing'
reject_text runtime/rules/general.md 'registered repository'
reject_text runtime/profiles/standalone.md 'registered repository'
require_text governance.md 'CREATION_STATUS_UNKNOWN'
require_text governance.md 'Create once, then read back the returned key'
require_text governance.md 'never retry automatically'
require_text handbook.md 'provider-owned evidence'
require_text handbook.md 'schema-1 compatibility'
require_text handbook.md 'cross-client adapters'
require_text handbook.md 'Workflow rules are instruction-driven'
require_text handbook.md 'allow-by-default'
require_text handbook.md 'DOCS_UNACTIVATED'
require_text handbook.md 'HANDOFF_DELTA_REQUIRED'
require_text README.md '## Add another client'
require_text README.md 'sh -s -- --client claude'
require_text README.md 'Codex remains enrolled'
require_text README.md \
  'Do not pass `--upgrade` when adding a client to the active release.'
require_text README.md \
  'If the installed release is older than the latest published release, upgrade it first.'
reject_text README.md '### v1.0.11 release'
reject_text README.md '### v1.0.11 upgrade'
require_text handbook.md 'README.md#upgrade'
reject_text handbook.md 'README.md#v1011-upgrade'
require_text README.md '### Downgrade'
require_text README.md '### Uninstall'
require_text README.md 'beroka-governance uninstall --force'
require_text handbook.md '### Downgrade'
require_text handbook.md '### Uninstall'
require_text handbook.md 'beroka-governance uninstall --force'
require_text runtime/integrations/beroka-be-fe.confluence-targets 'UNACTIVATED'
require_text PACKAGE-DESIGN.md 'provider-owned evidence'
require_text PACKAGE-DESIGN.md 'schema-1 compatibility'
require_text PACKAGE-DESIGN.md 'cross-client adapters'
require_text PACKAGE-DESIGN.md 'Workflow rules are instruction-driven'
require_text runtime/profiles/backend.md 'Backend Capability Registry'
require_text runtime/profiles/backend.md 'globally unique Folder'
require_text runtime/profiles/frontend.md 'Capability Index'
require_text runtime/integrations/beroka-be-fe.md 'Registry rows'
require_text runtime/integrations/beroka-be-fe.md 'Integration Hub'
for file in governance.md workflow.md runtime/rules/work-items.md \
  runtime/integrations/beroka-be-fe.md templates/jira-confluence.md; do
  require_text "$file" 'jira-intake-write'
  require_text "$file" 'Frontend → Backend'
  require_text "$file" 'Backend → Frontend'
done
require_text runtime/rules/work-items.md \
  'requester/reporter remains distinct from the executor/assignee'
require_text runtime/rules/work-items.md \
  'Assignment alone does not authorize a GitHub Issue.'
require_text runtime/rules/work-items.md \
  'Accepted + Ready + Assigned + Definition of Ready PASS'
require_text runtime/rules/work-items.md \
  'no existing primary GitHub Issue'
require_text runtime/rules/work-items.md 'INTAKE_CONFIGURATION_REQUIRED'
require_text runtime/rules/work-items.md \
  'agent-driven; there is no event listener'
reject_text workflow.md 'reassign to the requester'
reject_text governance.md 'assign the requester'
require_text workflow.md \
  'Receiving-team executor ownership'
require_text governance.md \
  'Receiving-team executor ownership'
require_text templates/jira-confluence.md \
  'Cross-team Jira intake request'
require_text templates/jira-confluence.md \
  'Receiving-team triage decision'
require_text runtime/rules/work-items.md 'LABEL_CONFIGURATION_REQUIRED'
require_text runtime/rules/work-items.md 'Parent Epic: N/A'
require_text runtime/rules/work-items.md \
  'AI-generated Jira and GitHub work items and technical artifacts default to'
require_text runtime/rules/work-items.md \
  'English. Chat language does not select artifact language.'
require_text runtime/rules/work-items.md \
  'Work-item language: <language>'
for file in governance.md workflow.md runtime/rules/work-items.md \
  templates/jira-confluence.md; do
  require_text "$file" 'Epic: `<Domain or module> — <Business outcome>`'
  require_text "$file" 'Feature: `<Capability> — <Observable outcome>`'
  require_text "$file" 'Task: `<Action verb> <Outcome or deliverable>`'
  require_text "$file" 'Bug: `<Actual symptom> when <condition>`'
done
require_text runtime/rules/work-items.md 'English sentence case'
require_text runtime/rules/work-items.md 'no trailing punctuation'
require_text runtime/rules/work-items.md \
  'no Jira key or `[Epic]`, `[Feature]`, `[Task]`, or `[Bug]` prefix'
for example in \
  'Market overview — Faster investment discovery' \
  'Portfolio — Clear real-time performance visibility' \
  'Market data — Reliable real-time price delivery' \
  'Order management — Consistent trade execution' \
  'Market charts — Display continuous historical price trends' \
  'Watchlist — Reflect live price changes without manual refresh' \
  'Historical candles API — Return complete time-bucketed market data' \
  'Order events WebSocket — Publish deterministic order status updates' \
  'Add empty-state guidance to the market watchlist' \
  'Validate chart rendering across supported time ranges' \
  'Add idempotency protection to order submission' \
  'Validate trading sessions before candle aggregation' \
  'Chart shows duplicate candles when the WebSocket reconnects' \
  'Watchlist loses selected symbols when the page refreshes' \
  'Order submission creates duplicates when clients retry timed-out requests' \
  'Candle API omits the latest interval when the market session crosses midnight'
do
  require_text templates/jira-confluence.md "$example"
done
require_text templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  'Technical artifacts default to English; chat language does not select artifact language.'
require_text templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  'Work-item language: <language>'
require_text templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  'configured MCP tools and never direct `gh` write commands'
require_text governance.md 'native Issue Type'
require_text workflow.md 'standalone reason'
reject_text runtime/integrations/beroka-be-fe.repositories \
  'hungnx77/Beroka_Backend'

for file in README.md handbook.md PACKAGE-DESIGN.md governance.md workflow.md \
  templates/ai-agent-assignment.md; do
  reject_text "$file" 'cuongngo1801-beroka/Beroka_Backend'
  reject_text "$file" 'cuongngo1801-beroka/Beroka_Frontend'
done
require_text handbook.md 'GITHUB_ROLE_REQUIRED'
require_text runtime/rules/general.md 'ROLE_SCOPE_DENIED'
require_text governance.md 'GitHub Team membership'

require_text templates/jira-confluence.md \
  'Backend Capability Registry Template'
require_text templates/jira-confluence.md \
  'Shared — Market — Market Indices — API'
require_text templates/jira-confluence.md 'Document revision:'
require_text templates/jira-confluence.md 'Client → Server Commands'
require_text templates/jira-confluence.md 'Server → Client Events'
require_text templates/github-issue.md 'Capability Registry reference:'
require_text templates/github-issue.md \
  'Change class: docs-only | contract-compatible | contract-breaking'
require_text templates/pull-request.md 'Canonical document content ID/path:'
require_text templates/pull-request.md 'Document revision:'
require_text templates/ai-agent-assignment.md \
  'Backend Capability Registry row'
require_text templates/ai-agent-assignment.md \
  '<Module> — Capability Index'
require_text handbook.md 'globally unique Folder'
reject_text templates/jira-confluence.md 'The Hub row is canonical'
require_text README.md 'Bootstrap does not infer repository context'
require_text PACKAGE-DESIGN.md 'Bootstrap does not infer repository context'
require_text handbook.md 'Project MCP: PRESENT_IGNORED'
require_text PACKAGE-DESIGN.md \
  'Non-interactive Cursor first-run does not write global MCP configuration'
reject_text README.md 'renders context when a Git repository is present'
reject_text PACKAGE-DESIGN.md \
  'renders context if a Git repository is present'

reject_text examples/homepage-market-overview-epic-packet.md \
  'HOME-MARKET-INDEX-CHART'
require_text examples/homepage-market-overview-epic-packet.md \
  'MARKET-INDEX-SNAPSHOT'
require_text examples/homepage-market-overview-epic-packet.md \
  'MARKET-INDEX-HISTORY'
require_text examples/homepage-market-overview-epic-packet.md \
  'MARKET-INDEX-STREAM'

DOC_TEST_TMP=$(mktemp -d)
trap 'rm -rf "$DOC_TEST_TMP"' EXIT HUP INT TERM

extract_advertised_handoff_body() {
  template=$1 output=$2 occurrence=${3:-1}
  awk -v occurrence="$occurrence" '
    $0 == "Handoff schema: 1" { seen++ }
    seen == occurrence && $0 == "Handoff schema: 1" { copy = 1 }
    copy && $0 == "```" { exit }
    copy { print }
  ' "$ROOT/$template" >"$output"
  [ -s "$output" ] || fail "missing advertised handoff body in $template"
}

render_advertised_handoff_body() {
  template=$1 rendered=$2 occurrence=${3:-1} raw=$DOC_TEST_TMP/raw.md
  extract_advertised_handoff_body "$template" "$raw" "$occurrence"
  sed \
    -e 's/{{PROVIDER_JIRA}}/BB-42/g' \
    -e 's/{{CONSUMER_JIRA}}/BF-69/g' \
    -e 's/{{SCOPE}}/Shared/g' \
    -e 's/{{DOMAIN}}/Market/g' \
    -e 's/{{CONTENT_ID}}/900001/g' \
    -e 's/{{PAGE_VERSION}}/1/g' \
    -e 's/{{OWNER_ACCOUNT_ID}}/account-123/g' \
    -e 's/{{EFFECTIVE_DATE}}/2026-08-25/g' \
    -e 's/{{SUPERSEDES}}/N\/A/g' \
    -e 's/{{SUPERSEDED_BY}}/N\/A/g' \
    "$raw" >"$rendered"
  if grep -Eq '{{[A-Z_]+}}' "$rendered"; then
    fail "rendered handoff body in $template has unresolved tokens"
  fi
}

has_untrusted_body_file_guidance() {
  awk '
    {
      text = tolower($0)
      sentences = split(text, sentence, /[.!?][[:space:]]*/)
      for (i = 1; i <= sentences; i++) {
        if (sentence[i] ~ /(codex|claude)/ &&
            sentence[i] ~ /(temporary|caller-provided)[[:space:]]+body[[:space:]]+file/ &&
            sentence[i] ~ /(proof|prove)/ && sentence[i] ~ /atlassian/ &&
            sentence[i] !~ /(do not|must not|never)/) {
          found = 1
        }
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

has_untrusted_body_file_guidance_text() {
  printf '%s\n' "$1" | has_untrusted_body_file_guidance
}

has_untrusted_body_file_guidance_file() {
  case $1 in
    /*) guidance_file=$1 ;;
    *) guidance_file=$ROOT/$1 ;;
  esac
  has_untrusted_body_file_guidance <"$guidance_file"
}

for template in templates/ai-agent-assignment.md templates/jira-confluence.md; do
  advertised_body=$DOC_TEST_TMP/$(basename "$template").md
  extract_advertised_handoff_body "$template" "$advertised_body"
  for token in PROVIDER_JIRA CONSUMER_JIRA CONTENT_ID PAGE_VERSION \
    OWNER_ACCOUNT_ID EFFECTIVE_DATE SUPERSEDES SUPERSEDED_BY SCOPE DOMAIN
  do
    require_text "$template" "{{$token}}"
  done
  require_text "$template" 'Frontend acknowledgment is pending. Respond on {{CONSUMER_JIRA}} with Confluence content ID {{CONTENT_ID}} version {{PAGE_VERSION}}.'
  render_advertised_handoff_body "$template" "$DOC_TEST_TMP/rendered-$(basename "$template").md"
  grep -F -- 'Scope: Shared' "$DOC_TEST_TMP/rendered-$(basename "$template").md" >/dev/null ||
    fail "rendered handoff body in $template lacks Scope"
  grep -F -- 'Domain: Market' "$DOC_TEST_TMP/rendered-$(basename "$template").md" >/dev/null ||
    fail "rendered handoff body in $template lacks Domain"
  advertised_draft=$DOC_TEST_TMP/draft-$(basename "$template").md
  render_advertised_handoff_body "$template" "$advertised_draft" 2
  grep -F -- 'Handoff state: DRAFT' "$advertised_draft" >/dev/null ||
    fail "rendered DRAFT body in $template lacks DRAFT state"
  grep -F -- 'Confluence content ID: new' "$advertised_draft" >/dev/null ||
    fail "rendered DRAFT body in $template lacks new content ID"
  grep -F -- 'Confluence page version: pending' "$advertised_draft" >/dev/null ||
    fail "rendered DRAFT body in $template lacks pending version"
  if grep -F -- 'READY_FOR_FE' "$advertised_draft" >/dev/null; then
    fail "rendered DRAFT body in $template claims readiness"
  fi
  require_text "$template" \
    'Verification is update-only; never use create/new options with `confluence-handoff-verify`.'
  reject_text "$template" \
    'For a DRAFT create, use `--confluence-action create --target-content-id new`.'
done

awk '
  /Trusted post-tool proof event: FUTURE_RUNTIME_ONLY/ { proof=NR }
  /^## 5[.] Frontend Issue/ { execution=NR }
  END { exit !(proof && execution && proof < execution) }
' "$ROOT/examples/end-to-end-traceability.md" ||
  fail 'recipient execution lacks an earlier explicit future trusted proof event'

for file in runtime/rules/general.md governance.md workflow.md \
  templates/agent-entrypoints/AGENTS.md \
  templates/agent-entrypoints/CLAUDE.md \
  templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  templates/ai-agent-assignment.md templates/jira-confluence.md; do
  require_text "$file" \
    'Codex and Claude Confluence create/update require a trusted actual-body boundary'
done
require_text templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  'confluence-handoff-write'
if ! has_untrusted_body_file_guidance_text \
  'Codex may use a caller-provided body file as proof of the Atlassian request. Never expose credentials.'
then
  fail 'affirmative caller-provided body-file guidance was accepted'
fi
if has_untrusted_body_file_guidance_text \
  'Codex must not use a caller-provided body file as proof of the Atlassian request.'
then
  fail 'negative caller-provided body-file guidance was rejected'
fi
file_guidance_fixture=$DOC_TEST_TMP/untrusted-body-file-guidance.md
printf '%s\n' \
  'Codex may use a caller-provided body file as proof of the Atlassian request. Never expose credentials.' \
  >"$file_guidance_fixture"
if ! has_untrusted_body_file_guidance_file "$file_guidance_fixture"; then
  fail 'affirmative caller-provided body-file file guidance was accepted'
fi
for file in runtime/rules/general.md governance.md workflow.md \
  templates/agent-entrypoints/AGENTS.md \
  templates/agent-entrypoints/CLAUDE.md \
  templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  templates/ai-agent-assignment.md templates/jira-confluence.md; do
  if has_untrusted_body_file_guidance_file "$file"; then
    fail "untrusted temporary body-file guidance in $file"
  fi
done

reject_text governance.md '`confluence-write` or `confluence-handoff-verify`'
reject_text governance.md 'include `Jira:`, `GitHub:`, and a handoff delta'
reject_text examples/end-to-end-traceability.md 'Repository artifact'
reject_text examples/end-to-end-traceability.md 'Canonical contract artifact/version/commit'
for file in runtime/rules/general.md workflow.md templates/jira-confluence.md \
  templates/agent-entrypoints/AGENTS.md \
  templates/agent-entrypoints/CLAUDE.md \
  templates/agent-entrypoints/CURSOR-USER-RULE.txt; do
  require_text "$file" 'in-process Cursor hook'
  reject_text "$file" '--client cursor --operation confluence-handoff-write'
  require_text "$file" '--operation confluence-handoff-verify'
  require_text "$file" \
    '--confluence-action update --target-content-id ID --expected-parent-id ID --handoff-body-file FILE'
  reject_text "$file" '--readback-parent-id'
  require_text "$file" 'read capability only'
done
for file in templates/ai-agent-assignment.md templates/jira-confluence.md; do
  require_text "$file" \
    'createConfluencePage'
  require_text "$file" \
    'updateConfluencePage'
  require_text "$file" \
    'in-process Cursor hook'
  reject_text "$file" \
    'beroka-governance preflight {{REPOSITORY}} --client cursor --operation confluence-handoff-write'
  require_text "$file" \
    '--operation confluence-handoff-verify --non-interactive --confluence-action update --target-content-id {{CONTENT_ID}} --expected-parent-id {{ACTIVE_FOLDER_ID}} --handoff-body-file {{HANDOFF_BODY_FILE}}'
  reject_text "$file" '--readback-parent-id'
done
for file in workflow.md runtime/profiles/frontend.md templates/jira-confluence.md; do
  reject_text "$file" 'artifact/version'
  reject_text "$file" 'repository/path'
done

render_context() {
  profile=$1 integration=${2:-none}
  cat "$ROOT/runtime/rules/general.md" "$ROOT/runtime/profiles/$profile.md"
  if [ "$integration" = beroka-be-fe ]; then
    cat "$ROOT/runtime/rules/work-items.md" \
      "$ROOT/runtime/integrations/beroka-be-fe.md"
  fi
}

for context in standalone backend frontend integration; do
  case "$context" in
    standalone) render_context standalone ;;
    backend) render_context backend ;;
    frontend) render_context frontend ;;
    integration) render_context backend beroka-be-fe ;;
  esac >"$DOC_TEST_TMP/$context.md"
  actual=$(grep -F -c 'confluence-handoff-write' "$DOC_TEST_TMP/$context.md" || :)
  [ "$actual" -eq 1 ] || fail "$context context has $actual handoff writes"
  actual=$(grep -F -c 'confluence-handoff-verify' "$DOC_TEST_TMP/$context.md" || :)
  [ "$actual" -eq 1 ] || fail "$context context has $actual handoff verifies"
  actual=$(grep -F -c -- 'Readback: CAPABILITY_ONLY' "$DOC_TEST_TMP/$context.md" || :)
  [ "$actual" -eq 1 ] || fail "$context context has $actual capability-only readbacks"
done

# Cross-team handoffs have one universal lifecycle in generated context. Profile
# and integration rules add ownership only, so they cannot dilute the contract.
for file in runtime/rules/general.md; do
  require_text "$file" 'confluence-handoff-write'
  require_text "$file" '--handoff-body-file FILE'
  require_text "$file" 'ACTIVE Folder'
  require_text "$file" 'self-contained Confluence page'
  require_text "$file" 'DRAFT-only'
  require_text "$file" 'confluence-handoff-verify'
  require_text "$file" 'Readback: CAPABILITY_ONLY'
  reject_text "$file" '--readback-parent-id'
  require_text "$file" 'Jira remains in its governed lifecycle state independently'
  require_count "$file" 'confluence-handoff-write' 1
done
for file in runtime/profiles/backend.md runtime/profiles/frontend.md \
  runtime/integrations/beroka-be-fe.md; do
  reject_text "$file" 'confluence-handoff-write'
done
for file in runtime/profiles/backend.md runtime/profiles/frontend.md \
  runtime/integrations/beroka-be-fe.md; do
  require_text "$file" 'team-local'
done

reject_text runtime/profiles/backend.md 'Confluence never copies its schema.'
reject_text runtime/profiles/frontend.md \
  'they never copy request, response, command, event, or schema payloads.'
reject_text governance.md 'Confluence does not copy it.'
reject_text templates/jira-confluence.md \
  'Copy this block into the BE Jira/GitHub Issue or PR'
for file in governance.md workflow.md templates/jira-confluence.md; do
  require_text "$file" 'self-contained Confluence page'
  require_text "$file" 'Confluence content ID and version'
  require_text "$file" 'GitHub: N/A'
done
for file in templates/ai-agent-assignment.md templates/jira-confluence.md; do
  require_text "$file" 'Handoff schema: 1'
  require_text "$file" 'Provider Jira:'
  require_text "$file" 'Consumer Jira:'
  require_text "$file" 'API operation: GET /v1/quotes/{symbol}'
  require_text "$file" 'Affected WebSocket inventory'
  require_text "$file" 'FE acknowledgment'
  require_text "$file" 'Superseded by:'
done
for file in templates/github-issue.md templates/pull-request.md; do
  require_text "$file" 'team-local GitHub Issue/PR section'
done
require_text bin/beroka-governance 'Handoff operations:'
require_text examples/homepage-market-overview-epic-packet.md \
  'Backend Capability Registry'
require_text examples/end-to-end-traceability.md 'PORTFOLIO-SUMMARY'
require_text examples/end-to-end-traceability.md 'Registry reference'

for file in README.md handbook.md PACKAGE-DESIGN.md governance.md workflow.md; do
  require_text "$file" 'Application repository changes: NONE'
  require_text "$file" 'Legacy repository metadata: PRESENT_IGNORED'
  require_text "$file" 'Central repository catalog'
  require_text "$file" 'Cursor Settings > Rules'
  reject_text "$file" 'Repository pull request: REQUIRED'
  reject_text "$file" 'register /path/to/repo'
  reject_text "$file" 'update /path/to/repo'
  reject_text "$file" 'rollback /path/to/repo'
  reject_text "$file" 'unregister /path/to/repo'
  if has_repository_governance_mutation "$ROOT/$file"; then
    fail "repository governance mutation guidance in $file"
  fi
done

guidance_fixture=$(mktemp "$ROOT/tests/.repository-governance-guidance.XXXXXX")
trap 'rm -f "$guidance_fixture"' EXIT HUP INT TERM
printf '%s\n' \
  'For governance installation, add .beroka-governance.lock to the application repository.' \
  >"$guidance_fixture"
has_repository_governance_mutation "$guidance_fixture" ||
  fail 'repository governance check accepted a lock instruction'
printf '%s\n' \
  'For governance installation, add the files, commit them, and open an application governance PR.' \
  >"$guidance_fixture"
has_repository_governance_mutation "$guidance_fixture" ||
  fail 'repository governance check accepted an alternate mutation instruction'
printf '%s\n' \
  'For governance upgrade, pin governance in the application repository, review the diff, git add and commit it, git push it, and open an application governance PR.' \
  >"$guidance_fixture"
has_repository_governance_mutation "$guidance_fixture" ||
  fail 'repository governance check accepted upgrade mutation guidance'
printf '%s\n' \
  'During governance upgrade, the CLI ignores legacy .beroka-governance.lock and does not add, commit, or push application repository files.' \
  >"$guidance_fixture"
if has_repository_governance_mutation "$guidance_fixture"; then
  fail 'repository governance check rejected legacy migration guidance'
fi
printf '%s\n' \
  'Governance directs normal application workflow: commit application changes and open a PR.' \
  >"$guidance_fixture"
if has_repository_governance_mutation "$guidance_fixture"; then
  fail 'repository governance check rejected ordinary application workflow'
fi
printf '%s\n' \
  'For governance installation in an application repository: add the governance lock and commit it.' \
  >"$guidance_fixture"
has_repository_governance_mutation "$guidance_fixture" ||
  fail 'repository governance check accepted contextual mutation guidance'
printf '%s\n' \
  'Governance installation applies to the application repository. Add the governance files and commit them.' \
  >"$guidance_fixture"
has_repository_governance_mutation "$guidance_fixture" ||
  fail 'repository governance check accepted two-sentence mutation guidance'
printf '%s\n' \
  'Governance installation never changes application repositories. Commit application code through the normal PR workflow.' \
  >"$guidance_fixture"
if has_repository_governance_mutation "$guidance_fixture"; then
  fail 'repository governance check carried denied installation context into ordinary workflow'
fi
printf '%s\n' \
  'Application repository behavior differs during governance installation.' \
  >"$guidance_fixture"
if has_repository_governance_mutation "$guidance_fixture"; then
  fail 'repository governance check rejected non-action wording'
fi
printf '%s\n' \
  'During governance upgrade, do not delete legacy files; add and commit the governance lock in the application repository.' \
  >"$guidance_fixture"
has_repository_governance_mutation "$guidance_fixture" ||
  fail 'repository governance check accepted mixed denial and mutation guidance'
rm -f "$guidance_fixture"
trap - EXIT HUP INT TERM

require_text governance.md \
  'CLI hard-enforces installation, release integrity, catalog routing, connector, authentication, and operation preflight.'
require_text governance.md 'Technical artifacts default to English across clients'
require_text governance.md 'operation-specific preflight immediately before each write'
require_text workflow.md \
  'Agent instructions govern workflow behavior unless CI, hooks, branch protection, or platform policy provides hard enforcement.'
require_text workflow.md 'Technical artifacts default to English across clients'
require_text workflow.md 'preflight immediately before each write'
require_text handbook.md 'Runtime hook: INSTALLED'
require_text handbook.md 'Runtime enforcement: PASS'
require_text handbook.md 'Work-item language: <language>'
require_text PACKAGE-DESIGN.md 'atomic JSON merge'
require_text PACKAGE-DESIGN.md 'personal hooks are preserved'
require_text PACKAGE-DESIGN.md 'Security hooks fail closed'
require_text PACKAGE-DESIGN.md 'XDG_STATE_HOME/beroka-ai-governance/cursor'
require_text PACKAGE-DESIGN.md 'runtime-enforcement canary'
require_text PACKAGE-DESIGN.md 'local-agent threat model'
for file in README.md handbook.md PACKAGE-DESIGN.md governance.md workflow.md; do
  reject_text "$file" 'USER_CONFIRMED`, not verified runtime behavior'
done

printf '%s\n' 'Documentation architecture tests: PASS'
