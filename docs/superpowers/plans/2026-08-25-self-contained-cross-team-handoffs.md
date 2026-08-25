# Self-Contained Cross-Team Handoffs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reject orphaned or repository-dependent cross-team handoffs and permit `READY_FOR_FE` only for a complete, self-contained Confluence contract under an exact reviewed `ACTIVE` Folder with successful readback evidence.

**Architecture:** Add an explicit `confluence-handoff-write` preflight that validates the actual Markdown body and an `ACTIVE` Folder before connector inspection. Extend `confluence-handoff-verify` to validate exact readback metadata and the read-back body. Reuse the same body and repository-isolation helpers from Cursor hooks so Codex, Claude, and Cursor receive equivalent decisions while ordinary Confluence writes remain unchanged.

**Tech Stack:** POSIX shell, `awk`, `grep`, `sed`, `jq`, existing shell test harness.

**Spec:** `docs/superpowers/specs/2026-08-25-self-contained-cross-team-handoffs-design.md`

## Global Constraints

- Cross-team coordination contains Jira and Confluence identities only; no GitHub URL, Git remote, branch, commit, or repository-dependent instruction.
- A handoff parent must match exactly one routed repository row with record type `folder`, state `ACTIVE`, and parent equal to the catalog Confluence root.
- `DRAFT` may omit only sections named by `Missing sections`; `READY_FOR_FE` is update-only and requires a complete body.
- All body, target, and readback failures occur before connector inspection.
- Ordinary `confluence-write` remains allow-by-default except for its existing hard stops.
- Do not mutate Jira, Confluence, incident page `85360641`, or publish a governance release during implementation validation.
- Do not add dependencies or background services.

---

### Task 1: Actual-body handoff contract

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/routing.sh`
- Create: `tests/fixtures/handoffs/draft.md`
- Create: `tests/fixtures/handoffs/ready-api.md`
- Create: `tests/fixtures/handoffs/ready-websocket.md`
- Create: `tests/fixtures/handoffs/ready-api-websocket.md`
- Create: `tests/fixtures/handoffs/ready-no-impact.md`
- Create: `tests/fixtures/handoffs/incident-85360641.md`

**Interfaces:**
- Consumes: existing `cmd_preflight`, `die`, and Confluence target globals.
- Produces: `CONFLUENCE_HANDOFF_BODY_FILE`; `handoff_header_value FILE LABEL`; `reject_cross_team_repository_references FILE`; `validate_handoff_body FILE ACTION TARGET`; operation `confluence-handoff-write`; results `HANDOFF_BODY_REQUIRED`, `HANDOFF_BODY_INVALID`, and `CROSS_TEAM_LINK_SCOPE_DENIED`.

- [ ] **Step 1: Add representative body fixtures**

Create complete API-only, WebSocket-only, combined, and explicit-no-impact READY bodies. Each uses the exact header from the spec, numeric content ID/version, `Missing sections: None`, all common sections, and all applicable transport subsections. Create a valid DRAFT body with `Confluence content ID: new`, `page version: pending`, and a non-empty `Missing sections`. Model incident `85360641` with root-era GitHub links, summary-only payload information, and `READY_FOR_FE`.

- [ ] **Step 2: Write failing routing tests for body-file safety and state rules**

Add calls shaped as:

```sh
if output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-handoff-write --non-interactive \
  --confluence-action create --target-content-id new \
  --expected-parent-id 900002 2>&1)
then
  fail 'handoff write passed without the actual body'
fi
assert_contains "$output" 'Result: HANDOFF_BODY_REQUIRED'
[ ! -s "$CALLS" ] || fail 'missing handoff body inspected a connector'
```

Cover missing, symlinked, directory, empty, and outside-safe-root body paths;
GitHub URL/Git remote/repository instruction rejection; malformed or duplicate
headers; same-project Jira pairs; DRAFT without declared omissions; create with
`READY_FOR_FE`; update with `new` or `pending`; unresolved placeholders; and
incident fixture rejection. For each required common/API/WebSocket section,
remove that section from a copied positive fixture and assert
`HANDOFF_BODY_INVALID`. Assert all five positive fixtures reach the existing
connector result.

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```sh
sh tests/routing.sh
```

Expected: FAIL because `confluence-handoff-write` and
`--handoff-body-file` are not accepted.

- [ ] **Step 4: Add the operation and shared actual-body validator**

Add `CONFLUENCE_HANDOFF_BODY_FILE` to the global state and parse exactly one
`--handoff-body-file`. Permit it only for `confluence-handoff-write` and
`confluence-handoff-verify`. Validate a regular non-symlink file inside the
physical home or temp root, consistent with `assert_safe_user_path`.

Implement exact single-value header extraction with `awk`. Implement a shared
repository-isolation check that rejects case-insensitive `github.com`,
`git@github`, `.git` remotes, and instructions naming a repository, branch, PR,
or commit as contract evidence. Do not print matched content.

Implement `validate_handoff_body FILE ACTION TARGET` in this order:

```text
safe file -> forbidden references -> exact header -> Jira pair -> state/action
-> common sections -> impact-specific sections -> placeholder/leakage patterns
```

Use exact Markdown headings and section boundaries rather than substring-only
presence. `DRAFT` requires non-`None` omissions and rejects readiness claims.
`READY_FOR_FE` requires update, numeric target/content ID, positive version,
`Missing sections: None`, and every required section.

Map `confluence-handoff-write` create/update to the same write capabilities as
ordinary Confluence create/update. Run body validation from
`require_operation_routing` before GitHub role or connector inspection.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```sh
sh tests/routing.sh
sh -n bin/beroka-governance tests/routing.sh
```

Expected: PASS.

- [ ] **Step 6: Commit the body contract**

```sh
git add bin/beroka-governance tests/routing.sh tests/fixtures/handoffs
git commit -m "feat: validate cross-team handoff bodies"
```

---

### Task 2: ACTIVE Folder-only parent gate

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/routing.sh`

**Interfaces:**
- Consumes: `CONFLUENCE_TARGET_PARENT_ID`, routed repository/root fields, optional scope/domain/transport, and the reviewed target inventory.
- Produces: `require_active_handoff_folder FILE`; stable `FOLDER_CREATION_REQUIRED` before connector inspection.

- [ ] **Step 1: Write failing parent matrix tests**

Using the valid DRAFT fixture, assert rejection for:

```text
65962274  catalog homepage/root
71237633  LEGACY Folder
900001    ACTIVE page
990001    UNACTIVATED Folder
999999    untracked content
```

Add duplicate ACTIVE Folder rows in one fixture and assert ambiguity fails.
Supply mismatched scope/domain/transport for an otherwise ACTIVE Folder and
assert failure. Assert exact ACTIVE Folder `900002` passes. Every negative
asserts `$CALLS` remains empty.

- [ ] **Step 2: Run the focused tests and verify RED**

Run `sh tests/routing.sh`.

Expected: root, LEGACY, page, and untracked parent cases incorrectly pass under
the old allow-by-default resolver.

- [ ] **Step 3: Implement exact ACTIVE Folder resolution**

Add `require_active_handoff_folder FILE` that counts exact rows for the routed
repository and parent ID. Require one row with type `folder`, state `ACTIVE`,
its own parent equal to `ROUTE_CONFLUENCE_ROOT_CONTENT_ID`, and matching
scope/domain/transport when supplied. Explicitly reject the route root before
inventory lookup. Call `die_folder_creation_required` for every missing,
non-Folder, non-ACTIVE, unrelated, duplicate, or mismatched result.

Call this helper only for `confluence-handoff-write` and
`confluence-handoff-verify`; do not change `resolve_confluence_target` for
ordinary writes.

- [ ] **Step 4: Run focused and regression tests**

Run:

```sh
sh tests/routing.sh
sh tests/documentation-architecture.sh
```

Expected: PASS, including existing ordinary minimal create tests.

- [ ] **Step 5: Commit the parent gate**

```sh
git add bin/beroka-governance tests/routing.sh
git commit -m "fix: require active folders for handoffs"
```

---

### Task 3: Exact post-write readback gate

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/routing.sh`

**Interfaces:**
- Consumes: validated handoff body and exact readback options.
- Produces: readback globals; `validate_handoff_readback`; result `HANDOFF_READBACK_REQUIRED`; extended `confluence-handoff-verify` PASS output.

- [ ] **Step 1: Write failing readback tests**

Extend positive verification with:

```sh
output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-handoff-verify --non-interactive \
  --confluence-action update --target-content-id 900001 \
  --expected-parent-id 900002 \
  --handoff-body-file "$ready_api" \
  --readback-parent-id 900002 --readback-space-key Berokaback \
  --readback-title 'Handoff — BB-42 — broker-account-reconnect' \
  --readback-version 3 \
  --readback-owner-account-id '712020:owner')
assert_contains "$output" 'Readback: VERIFIED'
assert_contains "$output" 'Result: PASS'
```

One at a time, omit or mismatch content ID, parent, space, title, version,
owner, and body header identity. Assert `HANDOFF_READBACK_REQUIRED` and no
connector probe for malformed local evidence. Assert create/new cannot verify.

- [ ] **Step 2: Run the focused tests and verify RED**

Run `sh tests/routing.sh`.

Expected: usage failure because readback options do not exist.

- [ ] **Step 3: Parse and validate exact readback metadata**

Add one-seen guards and globals for all readback options. Permit them only for
`confluence-handoff-verify`. Require numeric target, exact expected/readback
parent equality, routed space equality, non-empty title and owner, positive
version, and body content ID/version equality. Re-run body and ACTIVE Folder
validation before selecting `confluence-page-read` capability.

Print only normalized identity fields and `Readback: VERIFIED`; do not echo the
body or account ID.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```sh
sh tests/routing.sh
sh -n bin/beroka-governance tests/routing.sh
```

Expected: PASS.

- [ ] **Step 5: Commit the readback gate**

```sh
git add bin/beroka-governance tests/routing.sh
git commit -m "feat: verify handoff readback evidence"
```

---

### Task 4: Cursor and cross-team Jira enforcement

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/cursor-hooks.sh`
- Modify: `tests/routing.sh`

**Interfaces:**
- Consumes: `validate_handoff_body` and `reject_cross_team_repository_references` from Task 1.
- Produces: Cursor handoff classification using the exact MCP body; operation `jira-handoff-write` requiring `--handoff-body-file`; cross-team Jira body isolation; equivalent stable failure results across clients.

- [ ] **Step 1: Write failing Cursor Confluence tests**

Build MCP create/update inputs from each fixture. Assert the incident body,
partial handoff header, root parent, GitHub URL, missing API/WS sections, and
false READY body are denied with their exact stable result. Assert valid DRAFT
under ACTIVE Folder and valid READY update reach the preflight PASS path.

Repeat the positive and representative negative CLI preflights with
`--client codex`, `--client claude`, and `--client cursor`; assert identical
result classes.

- [ ] **Step 2: Write failing cross-team Jira isolation tests**

For `jira-intake-write`, `jira-handoff-write`, and Cursor Jira intake/update inputs, assert any GitHub
URL, Git remote, or repository-dependent contract instruction returns
`CROSS_TEAM_LINK_SCOPE_DENIED`. Assert `GitHub: N/A`, paired Jira keys, and an
exact Confluence content ID pass the isolation gate. Preserve team-local Jira
write tests containing the team's own GitHub link.

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```sh
sh tests/cursor-hooks.sh
sh tests/routing.sh
```

Expected: Cursor falls back to legacy marker validation and CLI Jira intake
does not inspect supplied cross-team body evidence.

- [ ] **Step 4: Reuse the validators from actual MCP input**

In `cursor_confluence_preflight`, detect a cross-team handoff when any handoff
schema/header marker is present. Write the exact extracted MCP body to a safe
temporary regular file under `PERSONAL_STAGE_ROOT`, pass it to
`confluence-handoff-write`, and clean it through the existing cleanup trap.
A partial/malformed handoff marker must never fall back to ordinary
`confluence-write`.

For cross-team Jira intake/acknowledgment, extract the actual description,
comment, or body and invoke only the repository-isolation portion of the shared
validator. Extend CLI `jira-intake-write` with `--handoff-body-file` and add
`jira-handoff-write` for updates/comments in the routed team's own Jira
project; both require the exact proposed text and map to `jira-issue-write`
only after isolation validation. Codex and Claude use these operations before
their corresponding MCP calls. Keep ordinary team-local `jira-write`
unchanged.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```sh
sh tests/cursor-hooks.sh
sh tests/routing.sh
```

Expected: PASS.

- [ ] **Step 6: Commit cross-client enforcement**

```sh
git add bin/beroka-governance tests/cursor-hooks.sh tests/routing.sh
git commit -m "fix: enforce handoff contracts across clients"
```

---

### Task 5: Align generated rules and templates

**Files:**
- Modify: `runtime/rules/general.md`
- Modify: `runtime/rules/work-items.md`
- Modify: `runtime/profiles/backend.md`
- Modify: `runtime/profiles/frontend.md`
- Modify: `runtime/integrations/beroka-be-fe.md`
- Modify: `governance.md`
- Modify: `workflow.md`
- Modify: `templates/ai-agent-assignment.md`
- Modify: `templates/github-issue.md`
- Modify: `templates/jira-confluence.md`
- Modify: `templates/pull-request.md`
- Modify: `tests/documentation-architecture.sh`

**Interfaces:**
- Consumes: command/result contracts implemented in Tasks 1–4.
- Produces: one normative generated rule and aligned explanatory/template copies without contradictory repository-only schema guidance.

- [ ] **Step 1: Write failing documentation architecture assertions**

Assert generated Backend, Frontend, standalone, and integration contexts contain
the new handoff operation, ACTIVE Folder requirement, no-GitHub isolation,
self-contained contract rule, and readback requirement exactly once where
normative. Reject the old statements that Confluence never copies schemas or
that a repository artifact is sufficient for cross-team consumers.

- [ ] **Step 2: Run documentation tests and verify RED**

Run `sh tests/documentation-architecture.sh`.

Expected: FAIL on missing new rules and retained repository-only guidance.

- [ ] **Step 3: Update the normative runtime rule once**

Place the universal cross-team handoff lifecycle in
`runtime/rules/general.md`. Keep profile files focused on ownership and add only
profile-specific wording. State that cross-team public contract snapshots are
self-contained in Confluence, while team-local repositories remain private and
may retain their own canonical artifacts.

Replace generic handoff commands with `confluence-handoff-write` and the exact
body/readback options. State explicitly that create is DRAFT-only, readiness is
reported only after verification, and Jira remains in its governed lifecycle
state independently.

- [ ] **Step 4: Update templates and explanatory copies**

Replace repository-link canonical blocks in consumer-facing handoff templates
with Jira pair, Confluence ID/version, complete API/WS sections, omissions,
owner/effective/supersession metadata, and FE acknowledgment path. Keep GitHub
fields only in team-local Issue/PR sections and use `GitHub: N/A` in cross-team
Jira examples.

- [ ] **Step 5: Run documentation tests and verify GREEN**

Run:

```sh
sh tests/documentation-architecture.sh
sh tests/routing.sh
sh tests/cursor-hooks.sh
```

Expected: PASS.

- [ ] **Step 6: Commit rule and template alignment**

```sh
git add runtime governance.md workflow.md templates tests/documentation-architecture.sh
git commit -m "docs: require self-contained cross-team contracts"
```

---

### Task 6: Whole-branch verification and review handoff

**Files:**
- Modify only files required to fix failures introduced by Tasks 1–5.

**Interfaces:**
- Consumes: all prior task commits.
- Produces: clean branch evidence suitable for a reviewed PR; no release or live Atlassian mutation.

- [ ] **Step 1: Run syntax and focused checks**

```sh
sh -n bin/beroka-governance tests/*.sh
sh tests/documentation-architecture.sh
sh tests/cursor-hooks.sh
sh tests/routing.sh
```

Expected: PASS.

- [ ] **Step 2: Run the full repository suite**

```sh
for test_file in tests/*.sh; do sh "$test_file"; done
```

Expected: all repository test groups PASS.

- [ ] **Step 3: Run hygiene checks**

```sh
git diff origin/main...HEAD --check
git status --short
git log --oneline origin/main..HEAD
```

Expected: no whitespace errors, no uncommitted files, and only issue #81
commits.

- [ ] **Step 4: Qualify the source-pinned negative case without writing**

Build an isolated source-pinned pilot from the final branch. Run
`confluence-handoff-write` with incident fixture `85360641`, parent `65962274`,
and no Atlassian mutation. Expected:

```text
Result: CROSS_TEAM_LINK_SCOPE_DENIED
```

Run valid DRAFT under one exact reviewed ACTIVE Folder. Expected preflight
capability outcome is PASS when the live connector inventory is healthy. Do
not create or update a page.

- [ ] **Step 5: Request independent review**

Review the complete diff against issue #81 and the design spec. Treat any
Critical or Important finding as blocking; fix it with a failing regression
test first and rerun Steps 1–3.

- [ ] **Step 6: Prepare the PR handoff**

Report exact final SHA, validation commands/results, source-pinned pilot
results, security-sensitive decisions, and explicitly unverified live-write
scope. Do not push, create a PR, publish a release, or remediate incident page
`85360641` without the corresponding user authorization and fresh governance
preflight.
