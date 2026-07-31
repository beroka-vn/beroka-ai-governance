#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_text() {
  file=$1 text=$2
  grep -F "$text" "$ROOT/$file" >/dev/null ||
    fail "missing [$text] in $file"
}

reject_text() {
  file=$1 text=$2
  if grep -F "$text" "$ROOT/$file" >/dev/null; then
    fail "forbidden [$text] in $file"
  fi
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
require_text PACKAGE-DESIGN.md 'provider-owned evidence'
require_text PACKAGE-DESIGN.md 'schema-1 compatibility'
require_text PACKAGE-DESIGN.md 'cross-client adapters'
require_text PACKAGE-DESIGN.md 'Workflow rules are instruction-driven'
require_text runtime/profiles/backend.md 'Backend Capability Registry'
require_text runtime/profiles/backend.md 'globally unique Folder'
require_text runtime/profiles/frontend.md 'Capability Index'
require_text runtime/integrations/beroka-be-fe.md 'Registry rows'
require_text runtime/integrations/beroka-be-fe.md 'Integration Hub'
require_text runtime/rules/work-items.md 'LABEL_CONFIGURATION_REQUIRED'
require_text runtime/rules/work-items.md 'Parent Epic: N/A'
require_text runtime/rules/work-items.md \
  'AI-generated Jira and GitHub work items and technical artifacts default to'
require_text runtime/rules/work-items.md \
  'English. Chat language does not select artifact language.'
require_text runtime/rules/work-items.md \
  'Work-item language: <language>'
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
require_text README.md 'Backend Capability Registry'
require_text README.md 'setup-connectors'
require_text handbook.md 'globally unique Folder'
reject_text templates/jira-confluence.md 'The Hub row is canonical'
require_text README.md 'Bootstrap does not infer repository context'
require_text PACKAGE-DESIGN.md 'Bootstrap does not infer repository context'
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
require_text README.md 'documented global local hooks'
require_text README.md 'Instruction: USER_CONFIRMED'
require_text README.md 'Runtime hook: INSTALLED'
require_text README.md 'enforcement: PASS'
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
