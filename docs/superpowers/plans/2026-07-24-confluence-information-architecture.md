# Confluence Information Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Beroka Backend and Frontend governance surface enforce the approved capability Registry, globally unique Folder names, one-page/one-Capability-ID cardinality, and FE module indexes.

**Architecture:** Keep machine-readable contracts in Backend repositories, add one cross-Epic Backend Capability Registry, and make Epic Integration Hubs and Frontend module indexes reference Registry rows. Implement this as central documentation/runtime rules plus a focused POSIX shell contract test; do not change the CLI, routing schema, live Confluence, OAuth, or release tags.

**Tech Stack:** Markdown governance documents, POSIX shell assertions, existing Beroka runtime profiles and templates.

## Global Constraints

- Native Folder titles are globally unique and use `<Scope> — <Domain> — <Transport>` or `<Scope> — <Domain> — <Capability group> — <Transport>`.
- Scope is exactly `Shared`, `Derivatives`, or `Underlying`; domain is exactly `Market` or `User`; transport is exactly `API` or `WebSocket`.
- Exactly one semantic capability, one transport, one Registry row, and one canonical Confluence page own each immutable Capability ID.
- `Market Indices` stays under Market; its API and WebSocket navigation Folders have distinct full names and no Capability ID.
- Confluence links repository schemas and may contain sanitized examples/deltas, but never copies an authoritative OpenAPI, JSON Schema, or event schema.
- Contract version belongs to the canonical repository artifact; document revision belongs to the Confluence page.
- Epic Integration Hubs reference Registry rows and own only Epic-specific mapping and handoff state.
- Frontend module indexes link exact Backend content IDs and versions without copying payloads.
- No legacy Capability-ID alias, compatibility registry, or live migration is created.
- Missing Registry, parent, scope, domain, transport, or exact content identity fails closed with existing governance results.
- Published `v1.0.0` is never moved, replaced, or deleted.

---

### Task 1: Core and Runtime Rules

**Files:**
- Create: `tests/documentation-architecture.sh`
- Modify: `governance.md`
- Modify: `workflow.md`
- Modify: `runtime/rules/general.md`
- Modify: `runtime/profiles/backend.md`
- Modify: `runtime/profiles/frontend.md`
- Modify: `runtime/integrations/beroka-be-fe.md`

**Interfaces:**
- Produces: mandatory information-architecture rules loaded by human readers and agent runtime profiles.
- Consumes: existing results `ROUTING_REQUIRED`, `FOLDER_CREATION_REQUIRED`, `DOC_HIERARCHY_FAILED`, and `MAPPING_CONFLICT`.

- [ ] **Step 1: Add the focused failing test**

Create `tests/documentation-architecture.sh`:

```sh
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
require_text governance.md 'Payload references, sanitized examples, and documented delta'
require_text workflow.md 'Registry row'
reject_text governance.md 'The Hub row is the canonical mapping'

require_text runtime/rules/general.md 'Confluence content ID'
require_text runtime/profiles/backend.md 'Backend Capability Registry'
require_text runtime/profiles/backend.md 'globally unique Folder'
require_text runtime/profiles/frontend.md 'Capability Index'
require_text runtime/integrations/beroka-be-fe.md 'Registry rows'
require_text runtime/integrations/beroka-be-fe.md 'Integration Hub'

printf '%s\n' 'Documentation architecture tests: PASS'
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```sh
sh tests/documentation-architecture.sh
```

Expected: `FAIL: missing [Backend Capability Registry] in governance.md`.

- [ ] **Step 3: Update core governance**

Replace Hub-owned capability definitions in `governance.md` with these rules:

```markdown
- `Backend Capability Registry` is the canonical cross-Epic mapping of one
  Capability ID to scope, domain, transport, repository artifact/version/commit,
  Confluence content ID, base Capability ID, and owner.
- Exactly one semantic capability, one transport, one Registry row, and one
  canonical Confluence page own each immutable Capability ID.
- Epic Integration Hubs reference Registry rows and own only Epic-specific Jira
  relationships, consumers, handoff states, and acknowledgements.
- Native Folder titles are globally unique. Use `Shared — Market — API` style
  names; never create generic `Market`, `User`, `API`, or `WebSocket` Folders.
- Confluence uses `Payload references, sanitized examples, and documented
  delta`; authoritative schemas remain in the Backend repository.
```

Add the exact Backend tree and the write/read-back sequence from the approved
spec to `governance.md`. Update `workflow.md` so planning resolves Registry rows
before Hub mapping, and post-merge updates the Registry row before referencing
Hubs and FE indexes.

- [ ] **Step 4: Update runtime profiles**

Add to `runtime/rules/general.md`:

```markdown
- Resolve existing Confluence content by exact content ID, never by title
  similarity; a rename or move updates the same content.
```

Add to `runtime/profiles/backend.md`:

```markdown
- Canonical capability pages use the reviewed Backend Capability Registry and
  globally unique Folder hierarchy.
- One capability page owns one immutable Capability ID and links the exact
  repository artifact/version/commit.
```

Add to `runtime/profiles/frontend.md`:

```markdown
- Frontend `<Module> — Capability Index` pages link exact Backend Registry rows
  and content IDs; they never copy request, response, command, event, or schema
  payloads.
```

Add to `runtime/integrations/beroka-be-fe.md`:

```markdown
- Integration Hubs reference exact Backend Capability Registry rows; they do
  not own or redefine canonical capabilities.
- One Registry capability may be referenced by several Epics and Frontend
  module indexes.
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```sh
sh tests/documentation-architecture.sh
```

Expected: `Documentation architecture tests: PASS`.

- [ ] **Step 6: Commit**

```bash
git add tests/documentation-architecture.sh governance.md workflow.md runtime
git commit -m "docs: enforce capability documentation architecture"
```

### Task 2: Templates and Reader Guidance

**Files:**
- Modify: `tests/documentation-architecture.sh`
- Modify: `templates/jira-confluence.md`
- Modify: `templates/github-issue.md`
- Modify: `templates/pull-request.md`
- Modify: `README.md`
- Modify: `handbook.md`

**Interfaces:**
- Consumes: Registry and hierarchy rules from Task 1.
- Produces: copy-ready Jira, Confluence, Issue, and PR fields that preserve exact document and contract traceability.

- [ ] **Step 1: Extend the test and verify RED**

Append before the final PASS line in `tests/documentation-architecture.sh`:

```sh
require_text templates/jira-confluence.md 'Backend Capability Registry Template'
require_text templates/jira-confluence.md 'Shared — Market — Market Indices — API'
require_text templates/jira-confluence.md 'Document revision:'
require_text templates/jira-confluence.md 'Client → Server Commands'
require_text templates/jira-confluence.md 'Server → Client Events'
require_text templates/github-issue.md 'Capability Registry reference:'
require_text templates/github-issue.md 'Change class: docs-only | contract-compatible | contract-breaking'
require_text templates/pull-request.md 'Canonical document content ID/path:'
require_text templates/pull-request.md 'Document revision:'
require_text README.md 'Backend Capability Registry'
require_text handbook.md 'globally unique Folder'
reject_text templates/jira-confluence.md 'The Hub row is canonical'
```

Run:

```sh
sh tests/documentation-architecture.sh
```

Expected: FAIL on the first missing template requirement.

- [ ] **Step 2: Replace the Confluence hierarchy and Hub templates**

In `templates/jira-confluence.md`:

- distinguish durable canonical capability pages from Epic-owned pages;
- include the exact unique Folder patterns and Market Indices Folder examples;
- add a `Backend Capability Registry Template` with one row per Capability ID;
- change the Integration Hub table to reference Registry rows;
- add a `<Module> — Capability Index` table;
- add canonical page metadata and WebSocket section templates;
- preserve the existing Folder capability gate and read-back results.

Use this documentation-change block:

```text
Canonical document content ID/path:
Capability ID:
Capability Registry reference:
Sections changed:
Change class: docs-only | contract-compatible | contract-breaking
Contract artifact/version/commit: <before → after | N/A>
Document revision: <before → after | N/A for repository files>
Additional related Jira items:
```

- [ ] **Step 3: Update GitHub templates**

Add the documentation-change block to `templates/github-issue.md` and
`templates/pull-request.md`. Keep one primary Jira item and `Closes #...`
unchanged. Explicitly say that several Jira items may reference the same
canonical page, but one GitHub Issue still has one primary Jira item.

- [ ] **Step 4: Update README and handbook**

Update the source-of-truth and traceability sections to show:

```text
Backend Capability Registry → canonical capability page/artifact
Epic Integration Hub → Registry references + Epic-specific handoff
Frontend Capability Index → Registry references consumed by one FE module
```

Document that generic repeated Folder names are invalid on the tenant and that
missing exact Registry/parent identity returns `ROUTING_REQUIRED` rather than
creating a fallback page.

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```sh
sh tests/documentation-architecture.sh
```

Expected: `Documentation architecture tests: PASS`.

- [ ] **Step 6: Commit**

```bash
git add tests/documentation-architecture.sh templates README.md handbook.md
git commit -m "docs: add capability traceability templates"
```

### Task 3: Canonical Examples and Full Verification

**Files:**
- Modify: `tests/documentation-architecture.sh`
- Modify: `examples/homepage-market-overview-epic-packet.md`
- Modify: `examples/end-to-end-traceability.md`

**Interfaces:**
- Consumes: Registry, Hub, FE Index, and documentation-change templates.
- Produces: examples that teach only the prospective standard and contain no legacy UI/outcome Capability ID.

- [ ] **Step 1: Add example assertions and verify RED**

Append before the final PASS line:

```sh
reject_text examples/homepage-market-overview-epic-packet.md 'HOME-MARKET-INDEX-CHART'
require_text examples/homepage-market-overview-epic-packet.md 'MARKET-INDEX-SNAPSHOT'
require_text examples/homepage-market-overview-epic-packet.md 'MARKET-INDEX-HISTORY'
require_text examples/homepage-market-overview-epic-packet.md 'MARKET-INDEX-STREAM'
require_text examples/homepage-market-overview-epic-packet.md 'Backend Capability Registry'
require_text examples/end-to-end-traceability.md 'PORTFOLIO-SUMMARY'
require_text examples/end-to-end-traceability.md 'Registry reference'
```

Run:

```sh
sh tests/documentation-architecture.sh
```

Expected: FAIL because the HomePage example still contains
`HOME-MARKET-INDEX-CHART`.

- [ ] **Step 2: Correct the HomePage example**

Replace the UI/outcome ID with these three canonical capabilities:

```text
MARKET-INDEX-SNAPSHOT
MARKET-INDEX-HISTORY
MARKET-INDEX-STREAM
```

Make its Hub reference Registry rows rather than define capability rows.
Document that the exact live Registry content ID is required before external
writes; the example update does not migrate live Confluence.

- [ ] **Step 3: Correct the end-to-end example**

Use `PORTFOLIO-SUMMARY` as the canonical Registry Capability ID. Add exact
Registry, canonical content ID, artifact/version/commit, Hub reference, and
`Portfolio — Capability Index` links through the traceability chain.

- [ ] **Step 4: Run all tests and static checks**

Run:

```sh
sh -n tests/documentation-architecture.sh
sh tests/documentation-architecture.sh
sh tests/bootstrap.sh
sh tests/smoke.sh
sh tests/connectors.sh
git diff --check
test "$(git rev-parse v1.0.0^{tag})" = \
  1f2db6bd75cf9d9a68d501c351fb2455448e04e1
```

Run `tests/routing.sh` in an isolated clone after deleting only the unpublished
local `v1.1.0` candidate tag from that clone. Expected: every test prints PASS,
the published tag object is unchanged, and the worktree is clean after commit.

- [ ] **Step 5: Commit**

```bash
git add tests/documentation-architecture.sh examples
git commit -m "docs: align capability traceability examples"
```

- [ ] **Step 6: Final branch check**

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean `agent/confluence-information-architecture` with the approved
design, implementation plan, core rules, templates, and corrected examples.
