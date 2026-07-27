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
require_text handbook.md 'globally unique Folder'
reject_text templates/jira-confluence.md 'The Hub row is canonical'

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

printf '%s\n' 'Documentation architecture tests: PASS'
