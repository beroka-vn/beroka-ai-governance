# BE/FE Governance Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the verified governance release recognize the exact Beroka Backend and Frontend repositories, reload context when repository scope changes, and deliver compact GitHub/Jira work-item rules in both routed contexts.

**Architecture:** Reuse the existing exact-slug catalog and `render_routing_context` path. Add two catalog records plus one compact shared rules document, emit that document only for the existing `beroka-be-fe` integration profile, and keep work-item conformance instruction-driven.

**Tech Stack:** POSIX shell, Markdown, GitHub repository catalog, existing shell test suite.

## Global Constraints

- Govern only `cuongngo1801-beroka/Beroka_Backend` and `cuongngo1801-beroka/Beroka_Frontend`; do not add wildcard or legacy-slug routing.
- Backend routes to Jira `BB`, board `34`, Confluence `Berokaback`, root page `65962274`.
- Frontend routes to Jira `BF`, board `35`, Confluence `Berokafron`, root page `65831203`.
- Cross-repository writes remain blocked without an exact reviewed counterpart and workflow mapping.
- Organization repositories use native Issue Type; personal repositories use exactly one configured `type:*` fallback label.
- Do not create missing labels automatically.
- Jira standalone work requires explicit confirmation and traceability; a `Subtask` is never directly under an Epic.
- Add no dependency or platform-side enforcement.

---

### Task 1: Exact BE/FE routing and compact runtime rules

**Files:**
- Create: `runtime/repositories/cuongngo1801-beroka/Beroka_Backend.conf`
- Create: `runtime/repositories/cuongngo1801-beroka/Beroka_Frontend.conf`
- Create: `runtime/rules/work-items.md`
- Modify: `runtime/integrations/beroka-be-fe.repositories`
- Modify: `bin/beroka-governance`
- Test: `tests/routing.sh`

**Interfaces:**
- Consumes: existing schema-1 catalog parsing and `ROUTE_INTEGRATION_PROFILE`.
- Produces: exact Backend/Frontend `ROUTING_ACTIVE` contexts and conditional `# BE/FE Work Items` output.

- [ ] **Step 1: Write failing routing tests**

Add real Backend and Frontend test repositories/remotes and assertions equivalent to:

```sh
backend_output=$($CLI context "$backend_repo")
assert_contains "$backend_output" 'Repository: cuongngo1801-beroka/Beroka_Backend'
assert_contains "$backend_output" 'Jira project: BB'
assert_contains "$backend_output" 'Jira board: 34'
assert_contains "$backend_output" 'Confluence root content: 65962274'
assert_contains "$backend_output" '# BE/FE Work Items'

frontend_output=$($CLI context "$frontend_repo")
assert_contains "$frontend_output" 'Repository: cuongngo1801-beroka/Beroka_Frontend'
assert_contains "$frontend_output" 'Jira project: BF'
assert_contains "$frontend_output" 'Jira board: 35'
assert_contains "$frontend_output" 'Confluence root content: 65831203'
assert_contains "$frontend_output" '# BE/FE Work Items'

assert_not_contains "$unknown_output" '# BE/FE Work Items'
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `sh tests/routing.sh`

Expected: FAIL because the exact catalog records and compact rules output do not exist.

- [ ] **Step 3: Add the minimal catalog and runtime implementation**

Create the Backend record:

```text
SCHEMA_VERSION=1
PROFILE=backend
JIRA_PROJECT_KEY=BB
JIRA_BOARD_ID=34
CONFLUENCE_SPACE_KEY=Berokaback
CONFLUENCE_ROOT_CONTENT_ID=65962274
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=beroka-be-fe
CROSS_REPO_POLICY=profile-controlled
```

Create the Frontend record with `PROFILE=frontend`, Jira `BF`, board `35`,
Confluence `Berokafron`, and root page `65831203`. Replace the integration
inventory with only these canonical rows:

```text
cuongngo1801-beroka/Beroka_Backend	backend
cuongngo1801-beroka/Beroka_Frontend	frontend
```

Add `runtime/rules/work-items.md` with the approved scope classification,
ownership/type/label rules, Jira Epic/standalone rules, and readback gates.
Add it to `validate_release_checkout`, then reuse the existing condition in
`render_routing_context`:

```sh
if [ "$ROUTE_INTEGRATION_PROFILE" = beroka-be-fe ]; then
  cat "$RELEASE_DIR/runtime/rules/work-items.md" ||
    die GOVERNANCE_NOT_READY 'Cannot read BE/FE work-item rules'
fi
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `sh tests/routing.sh`

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add bin/beroka-governance runtime tests/routing.sh
git commit -m "fix: route canonical BE FE governance"
```

### Task 2: Repository-switch and work-item instructions

**Files:**
- Modify: `runtime/entrypoint.md`
- Modify: `templates/agent-entrypoints/AGENTS.md`
- Modify: `templates/agent-entrypoints/CLAUDE.md`
- Modify: `templates/agent-entrypoints/CURSOR-USER-RULE.txt`
- Modify: `governance.md`
- Modify: `workflow.md`
- Modify: `templates/github-issue.md`
- Modify: `templates/ai-agent-assignment.md`
- Modify: `templates/jira-confluence.md`
- Test: `tests/documentation-architecture.sh`

**Interfaces:**
- Consumes: the compact runtime rules from Task 1.
- Produces: matching durable instructions for user-level clients and detailed templates.

- [ ] **Step 1: Write failing documentation assertions**

Add assertions for the behavioral contract:

```sh
require_text runtime/entrypoint.md 'IDE workspace or current Git repository changes'
require_text templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  'IDE workspace or current Git repository changes'
require_text runtime/rules/work-items.md 'LABEL_CONFIGURATION_REQUIRED'
require_text runtime/rules/work-items.md 'Parent Epic: N/A'
require_text governance.md 'native Issue Type'
require_text workflow.md 'standalone reason'
reject_text runtime/integrations/beroka-be-fe.repositories \
  'hungnx77/Beroka_Backend'
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `sh tests/documentation-architecture.sh`

Expected: FAIL on the new assertions.

- [ ] **Step 3: Update user-level and durable rules**

Require fresh context when the workspace/repository changes, another repository
enters scope, or a plan becomes shared. Document:

- one human owner, with explicit assignee then requesting developer then authenticated human creator fallback;
- native Issue Type for organization repositories, configured `type:*` fallback for personal repositories, plus `area:*` and `priority:*`;
- `LABEL_CONFIGURATION_REQUIRED` when fallback labels are absent;
- active Epic lookup, explicit standalone confirmation with `Parent Epic: N/A`,
  and no direct Epic-to-Subtask parenting;
- post-create readback of ownership, classification, priority, parent/exception,
  and GitHub/Jira linkage.

Keep the existing detailed capability/Confluence material unchanged except
where the new rules or canonical Backend URL directly replace stale text.

- [ ] **Step 4: Run documentation and routing tests**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/routing.sh
```

Expected: both PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add runtime/entrypoint.md templates governance.md workflow.md tests/documentation-architecture.sh
git commit -m "docs: enforce BE FE work item boundaries"
```

### Task 3: Prepare the immutable corrective release

**Files:**
- Modify: `VERSION`
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `PACKAGE-DESIGN.md`
- Modify: `tests/release.sh`

**Interfaces:**
- Consumes: the completed runtime behavior and documentation.
- Produces: a repository state ready to tag as `v1.0.2` after merge.

- [ ] **Step 1: Write failing release assertions**

Change the expected supported version to `v1.0.2` and require the canonical
Backend/Frontend slugs and repository-switch behavior in release-facing docs.

- [ ] **Step 2: Run the release test and verify RED**

Run: `sh tests/release.sh`

Expected: FAIL because `VERSION` and release docs still name `v1.0.1`.

- [ ] **Step 3: Update release metadata and user documentation**

Set `VERSION` to `v1.0.2`, update the supported-release statements and
one-command examples, document the exact BE/FE boundary, and replace
`hungnx77/Beroka_Backend` with
`cuongngo1801-beroka/Beroka_Backend`.

- [ ] **Step 4: Run the complete verification suite**

Run:

```bash
sh -n bin/beroka-governance bootstrap.sh release/bootstrap.sh.in
for test in tests/*.sh; do sh "$test"; done
git diff --check origin/main...HEAD
```

Expected: all commands PASS.

- [ ] **Step 5: Commit Task 3**

```bash
git add VERSION README.md handbook.md PACKAGE-DESIGN.md tests/release.sh
git commit -m "chore(release): prepare v1.0.2"
```

### Task 4: Publish for review

**Files:**
- Modify: GitHub issue `#25`
- Create: draft pull request from `agent/issue-25-be-fe-boundary`

**Interfaces:**
- Consumes: verified commits from Tasks 1–3.
- Produces: traceable issue state and a reviewable draft PR; no merge or release.

- [ ] **Step 1: Update issue #25**

After a fresh `github-write` preflight, keep assignee
`cuongngo1801-beroka`, set native Issue Type `Bug` when supported, and replace
the body with the approved exact boundary, acceptance criteria, and links to
the design/implementation plan. Do not create missing repository labels.

- [ ] **Step 2: Push the implementation branch**

After a fresh `github-write` preflight:

```bash
git push -u origin agent/issue-25-be-fe-boundary
```

- [ ] **Step 3: Open a draft pull request**

After another fresh `github-write` preflight, create a draft PR targeting
`main`, link `Fixes #25`, list the three behavioral changes, and include the
complete test evidence.

- [ ] **Step 4: Read back issue and PR**

Verify issue owner/type/labels and PR base/head/draft state. Report any
unsupported native Issue Type or missing label taxonomy explicitly instead of
claiming PASS.
