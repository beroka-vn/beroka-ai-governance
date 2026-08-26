# Trusted Handoff Boundary Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the final two issue #81 blockers by permitting Confluence create/update only from a trusted actual-body boundary and binding every handoff's scope/domain to its reviewed ACTIVE Folder.

**Architecture:** The CLI starts with no trusted-body authority. Only the in-process Cursor MCP hook may set a private runtime flag after extracting and staging the exact tool-call body; direct Codex, Claude, and Cursor preflights fail closed for Confluence create/update while target-only moves remain available. The handoff header carries exact `Scope` and `Domain` values, and the shared Folder gate compares them directly with the selected inventory row.

**Tech Stack:** POSIX shell, `awk`, `grep`, `jq`, existing shell test harness.

**Spec:** `docs/superpowers/specs/2026-08-25-self-contained-cross-team-handoffs-design.md`

## Global Constraints

- Do not add an Atlassian MCP proxy, dependency, daemon, or sidecar manifest.
- Never trust an environment variable or caller-provided body file as proof of the actual MCP body.
- Preserve Cursor ordinary team-local Confluence writes and target-only moves.
- Codex and Claude Confluence create/update must return `CLIENT_BODY_GATE_REQUIRED` before connector inspection.
- Cross-team bodies remain English and repository-independent.
- Do not push, create a PR, publish a release, mutate Jira/Confluence, or modify incident page `85360641`.

---

### Task 1: Enforce the trusted actual-body client boundary

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/routing.sh`
- Modify: `tests/cursor-hooks.sh`

**Interfaces:**
- Consumes: `cmd_preflight`, `cursor_confluence_preflight`, `cursor_stage_exact_body`, and `cursor_staged_preflight`.
- Produces: process-local `CONFLUENCE_BODY_TRUSTED=0|1` and `require_trusted_confluence_body_gate CLIENT ACTION`.

- [ ] **Step 1: Add direct-client RED regressions**

In `tests/routing.sh`, add a helper that runs ordinary and handoff create/update preflights for `codex`, `claude`, and direct `cursor`. For every case assert:

```sh
assert_contains "$output" 'Result: CLIENT_BODY_GATE_REQUIRED'
[ ! -s "$CALLS" ] || fail 'untrusted Confluence body gate inspected a connector'
```

Keep one Codex and one Claude `confluence-write --confluence-action move` case and assert their existing capability outcome is not `CLIENT_BODY_GATE_REQUIRED`.

- [ ] **Step 2: Run routing tests and verify RED**

Run:

```sh
sh tests/routing.sh
```

Expected: FAIL because valid direct create/update preflights still reach connector capability checks or return `PASS`.

- [ ] **Step 3: Add Cursor-boundary RED regressions**

In `tests/cursor-hooks.sh`, retain the existing cross-team and ordinary create/update hook inputs and add assertions that neither returns `CLIENT_BODY_GATE_REQUIRED`. Add a direct `preflight --client cursor --operation confluence-write` create case and assert it is denied with that result.

- [ ] **Step 4: Run Cursor tests and verify RED**

Run:

```sh
sh tests/cursor-hooks.sh
```

Expected: FAIL because direct Cursor and hook-driven Cursor currently have the same authority.

- [ ] **Step 5: Implement the minimal process-local gate**

In `bin/beroka-governance`, initialize the flag from a literal, never the environment:

```sh
CONFLUENCE_BODY_TRUSTED=0

require_trusted_confluence_body_gate() {
  rtcbg_client=$1 rtcbg_action=$2
  [ "$rtcbg_action" = move ] && return 0
  [ "$rtcbg_client" = cursor ] &&
    [ "$CONFLUENCE_BODY_TRUSTED" -eq 1 ] && return 0
  die CLIENT_BODY_GATE_REQUIRED \
    'Confluence create/update requires a trusted actual-body client boundary'
}
```

Call it for `confluence-write` and `confluence-handoff-write` after their local
body/Folder/target validation but before connector inspection. This preserves
specific local validation failures without granting write authority to an
untrusted body. Do not apply it to `confluence-handoff-verify`, which is
read-only.

In `cursor_confluence_preflight`, set `CONFLUENCE_BODY_TRUSTED=1` only after exactly one body has been extracted from `CURSOR_TOOL_INPUT` and only around the in-process `cmd_preflight` call. Reset it to `0` in the existing cleanup path on success, parser failure, and signals. Do not read a similarly named exported variable.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```sh
sh -n bin/beroka-governance tests/*.sh
sh tests/cursor-hooks.sh
sh tests/routing.sh
```

Expected: all PASS; direct create/update is denied before connector inspection, hook-driven Cursor continues through the existing body validation path, and moves retain their prior behavior.

- [ ] **Step 7: Commit Task 1**

```sh
git add bin/beroka-governance tests/routing.sh tests/cursor-hooks.sh
git commit -m "fix: require trusted Confluence body boundary"
```

---

### Task 2: Bind body scope and domain to the ACTIVE Folder

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/fixtures/handoffs/draft.md`
- Modify: `tests/fixtures/handoffs/ready-api.md`
- Modify: `tests/fixtures/handoffs/ready-websocket.md`
- Modify: `tests/fixtures/handoffs/ready-api-websocket.md`
- Modify: `tests/fixtures/handoffs/ready-no-impact.md`
- Modify: `tests/fixtures/handoffs/incident-85360641.md`
- Modify: `tests/routing.sh`
- Modify: `tests/cursor-hooks.sh`

**Interfaces:**
- Consumes: exact handoff header parsing in `validate_handoff_body` and Folder inventory parsing in `require_active_handoff_folder`.
- Produces: validated globals `vhb_scope` and `vhb_domain`, each bound exactly to `rahf_scope` and `rahf_domain`.

- [ ] **Step 1: Add header and Folder RED regressions**

Update one Cursor-hook test body to include:

```text
Scope: Shared
Domain: Market
```

Then derive four negative bodies from it: missing `Scope`, missing `Domain`, `Scope: Product`, and `Domain: Broker accounts`. Assert missing fields return `HANDOFF_BODY_INVALID`; mismatches under Folder `900002` return `FOLDER_CREATION_REQUIRED`; none may inspect a connector.

Add exact-header ordering/duplicate cases for both fields to the Cursor hook
matrix and assert `HANDOFF_BODY_INVALID` before connector inspection. Keep
direct routing negatives for existing body/Folder failures; valid direct
preflights must terminate at `CLIENT_BODY_GATE_REQUIRED`.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```sh
sh tests/cursor-hooks.sh
sh tests/routing.sh
```

Expected: FAIL because the current parser does not require the two header fields and the Folder gate copies its own scope/domain into the request.

- [ ] **Step 3: Extend the exact body header**

In `validate_handoff_body`, read `Scope` and `Domain` immediately after the provider/consumer Jira fields:

```sh
vhb_scope=$(handoff_header_value "$vhb_file" Scope) ||
  die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
vhb_domain=$(handoff_header_value "$vhb_file" Domain) ||
  die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
```

Require each to be non-empty, single-line header content and reject the validator's existing unresolved-token vocabulary. Update the contiguous exact-header check so `Scope` and `Domain` occupy fixed positions between `Consumer Jira` and `Confluence content ID`.

- [ ] **Step 4: Bind the Folder row to body values**

Replace optional-only scope/domain comparison in `require_active_handoff_folder` with exact body comparison:

```sh
[ "$rahf_scope" = "$vhb_scope" ] ||
  die_folder_creation_required \
    'The handoff body scope does not match the ACTIVE Folder'
[ "$rahf_domain" = "$vhb_domain" ] ||
  die_folder_creation_required \
    'The handoff body domain does not match the ACTIVE Folder'
```

If `--scope` or `--domain` was also supplied, require it to equal the body value; never overwrite the body value from inventory. After all checks pass, expose the reviewed row through the existing `CONFLUENCE_TARGET_*` output variables.

- [ ] **Step 5: Update canonical fixtures**

Add `Scope: Shared` and `Domain: Market` after `Consumer Jira` in every `tests/fixtures/handoffs/*.md` file. Preserve all other body content and the incident's unsafe repository reference.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```sh
sh -n bin/beroka-governance tests/*.sh
sh tests/cursor-hooks.sh
sh tests/routing.sh
```

Expected: all PASS; missing/mismatched scope/domain fails before connector inspection and matching bodies reach the trusted Cursor path.

- [ ] **Step 7: Commit Task 2**

```sh
git add bin/beroka-governance tests/fixtures/handoffs tests/routing.sh tests/cursor-hooks.sh
git commit -m "fix: bind handoffs to Folder scope and domain"
```

---

### Task 3: Align generated guidance and qualify the branch

**Files:**
- Modify: `runtime/rules/general.md`
- Modify: `governance.md`
- Modify: `workflow.md`
- Modify: `templates/agent-entrypoints/AGENTS.md`
- Modify: `templates/agent-entrypoints/CLAUDE.md`
- Modify: `templates/agent-entrypoints/CURSOR-USER-RULE.txt`
- Modify: `templates/ai-agent-assignment.md`
- Modify: `templates/jira-confluence.md`
- Modify: `tests/documentation-architecture.sh`

**Interfaces:**
- Consumes: `CLIENT_BODY_GATE_REQUIRED`, the 15-line handoff header, and Cursor-only trusted create/update behavior from Tasks 1–2.
- Produces: generated context and copyable templates that cannot instruct Codex/Claude to bypass the actual-body gate.

- [ ] **Step 1: Add documentation RED assertions**

In `tests/documentation-architecture.sh`, render `{{SCOPE}}` as `Shared` and `{{DOMAIN}}` as `Market`, require both tokens in each advertised handoff template, and require all generated client guidance to state:

```text
Codex and Claude Confluence create/update require a trusted actual-body boundary
```

Require Cursor guidance to retain `confluence-handoff-write`, and reject text that tells Codex or Claude to use a temporary body file as proof of the Atlassian request.

- [ ] **Step 2: Run documentation tests and verify RED**

Run:

```sh
sh tests/documentation-architecture.sh
```

Expected: FAIL because templates lack `Scope`/`Domain` and current guidance advertises direct Codex/Claude handoff writes.

- [ ] **Step 3: Update rules and templates minimally**

Add `Scope: {{SCOPE}}` and `Domain: {{DOMAIN}}` to both advertised bodies. Change shared and client entrypoint guidance to say that Cursor is the only trusted Confluence create/update boundary in this release; Codex/Claude must stop with `CLIENT_BODY_GATE_REQUIRED`, while Jira operations and Confluence moves retain their existing governed paths. Keep the readback wording capability-only.

- [ ] **Step 4: Run focused and full verification**

Run:

```sh
sh -n bin/beroka-governance tests/*.sh
sh tests/documentation-architecture.sh
sh tests/cursor-hooks.sh
sh tests/routing.sh
for test_file in tests/*.sh; do sh "$test_file"; done
git diff origin/main...HEAD --check
git status --short
```

Expected: every test group PASS, no whitespace errors, and only planned files modified before the final commit.

- [ ] **Step 5: Commit Task 3**

```sh
git add runtime/rules/general.md governance.md workflow.md \
  templates/agent-entrypoints templates/ai-agent-assignment.md \
  templates/jira-confluence.md tests/documentation-architecture.sh
git commit -m "docs: route handoffs through trusted clients"
```

- [ ] **Step 6: Request independent review**

Review `a265e149c9107178836b6169cfb4a69d174cde65..HEAD` against the approved spec and this plan. Treat any Critical or Important finding as blocking. Do not push, create a PR, publish a release, or run a live Atlassian mutation.
