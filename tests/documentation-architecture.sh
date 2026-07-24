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
require_text runtime/profiles/backend.md 'Backend Capability Registry'
require_text runtime/profiles/backend.md 'globally unique Folder'
require_text runtime/profiles/frontend.md 'Capability Index'
require_text runtime/integrations/beroka-be-fe.md 'Registry rows'
require_text runtime/integrations/beroka-be-fe.md 'Integration Hub'

printf '%s\n' 'Documentation architecture tests: PASS'
