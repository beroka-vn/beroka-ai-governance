# Cross-Team Jira Intake Implementation Plan

> **Issue:** [#40](https://github.com/beroka-vn/beroka-ai-governance/issues/40)
> **Design:** [Cross-team Jira intake](../specs/2026-07-31-cross-team-jira-intake-design.md)

**Goal:** Add a narrow, symmetric FE-to-BE and BE-to-FE Jira intake path while
leaving ordinary repository role enforcement unchanged.

**Boundary:** Reuse the current shell CLI, routing catalog, Team membership,
Atlassian connector, and capability checks. No daemon, service, Jira workflow
mutation, application-repository change, or release metadata change.

---

### Task 1: Add failing preflight regressions

**File:** `tests/routing.sh`

1. Prove an FE role in the exact Frontend repository can request
   `jira-intake-write` only to canonical Backend/`BB`.
2. Prove the symmetric BE-to-Frontend/`BF` route.
3. Prove missing, duplicate, malformed, alias-only, standalone, same-profile,
   or `explicit-only` intake mappings fail before connector inspection.
4. Re-run the existing ordinary FE-to-Backend and BE-to-Frontend
   `ROLE_SCOPE_DENIED` checks to prove `jira-write` is not broadened.
5. Run `sh tests/routing.sh` and confirm the new operation is rejected before
   implementation.

### Task 2: Add the minimum exact intake inventory and resolver

**Files:**

- `runtime/integrations/beroka-be-fe.intake`
- `bin/beroka-governance`

1. Add exactly two canonical source-to-target records:
   Frontend → Backend/`BB` and Backend → Frontend/`BF`.
2. Parse one exact record for the current repository and validate the target
   slug against its catalog record, opposite profile, receiving Jira project,
   shared integration profile, and `profile-controlled` policy.
3. Store only the resolved target repository, profile, and Jira project.
4. Return `ROUTING_REQUIRED` before client inspection when resolution is not
   exact.

### Task 3: Add the dedicated preflight operation

**Files:**

- `bin/beroka-governance`
- `tests/routing.sh`

1. Allow `jira-intake-write` in the existing operation switch.
2. Resolve its exact intake target and use the existing
   `jira-issue-write` capability.
3. Verify the source repository role and live Team membership exactly as today.
4. Print the source repository plus receiving repository/project so the
   subsequent governed write cannot guess its target.
5. Keep `jira-write`, `cross-repo-write`, and the role matrix unchanged.
6. Run `sh tests/routing.sh` and confirm the focused routing cases pass.

### Task 4: Route local Cursor Jira intake safely

**Files:**

- `bin/beroka-governance`
- `tests/cursor-hooks.sh`

1. Resolve the exact Jira project from structured `project` or `projectKey`
   input.
2. Select ordinary `jira-write` when it matches the current project and
   `jira-intake-write` only when it matches the exact resolved intake target.
3. For intake creation require reporter/requester, leave assignee and Sprint
   unset, and reject a selected parent; retain the language, priority, and
   traceability markers.
4. Keep ordinary Jira and GitHub hook validation unchanged.
5. Add focused hook regressions for project selection and intake ownership
   fields, then run `sh tests/cursor-hooks.sh`.

### Task 5: Publish the lifecycle contract

**Files:**

- `governance.md`
- `workflow.md`
- `runtime/rules/work-items.md`
- `runtime/integrations/beroka-be-fe.md`
- `templates/jira-confluence.md`
- `tests/documentation-architecture.sh`

1. Define symmetric requester/reporter intake and receiving-team triage
   ownership.
2. Remove the rule that reassigns execution to a cross-team requester.
3. Require `Accepted + Ready + Assigned + Definition of Ready PASS` and no
   existing primary GitHub Issue before technical Issue creation.
4. Preserve separate BB/BF records, same-project parents, and
   `Blocks`/`Relates` semantics.
5. Require create metadata and supported intake state/equivalent-field evidence;
   return configuration remediation when absent.
6. State that automation is agent-driven, not an event listener.
7. Add exact documentation assertions and run
   `sh tests/documentation-architecture.sh`.

### Task 6: Verify and commit

1. Run `git diff --check`.
2. Run every `tests/*.sh` script and report unverified results accurately.
3. Confirm `VERSION`, tags, ordinary role enforcement, and release metadata are
   unchanged.
4. Commit the tested implementation with:

   ```bash
   git commit -m "feat(governance): add cross-team Jira intake"
   ```

