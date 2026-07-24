# GitHub Issue Templates

## Usage rules

- Choose exactly one variant: Feature, Bug, or Technical Task.
- Each issue has one primary Jira item, owner, branch, and PR.
- Complete Scope, Acceptance criteria, and Validation before accepting work.
- Apply exactly one `type:*`, at least one `area:*`, and one `priority:*` label.
- AI applies labels only when mapping is clear; otherwise ask the human/manager.
- If FE consumes BE output, link the FE issue and Hub; FE never reconstructs
  the contract from multiple issue descriptions.

## Labels

```text
Type:     type:feature | type:bug | type:technical
Area:     area:frontend | area:backend | area:shared
Priority: priority:p0 | priority:p1 | priority:p2 | priority:p3
State:    status:blocked (only while blocked)
```

## Cross-Team Dependency and Handoff Block

Add this block to any Feature/Bug/Technical issue with BE → FE impact. Keep the
canonical contract in the BE repository; record only the delta and version.

```markdown
## Cross-team dependency

- Frontend impact: None | Handoff required
- Epic Integration Hub:
- Paired Backend Jira/GitHub issue:
- Paired Frontend Jira/GitHub issue(s):
- Dependency direction: BE blocks FE | FE blocks BE | parallel

## BE → FE handoff

- Canonical contract artifact/version/commit:
- Behavior delivered:
- Authentication/permissions:
- Error and edge cases:
- Test environment and sanitized evidence:
- Breaking/migration impact:
- Known limitations/unverified items:
- State: DRAFT | READY_FOR_FE | ACKNOWLEDGED | BLOCKED | SUPERSEDED
- Ready/acknowledged by and at:
```

`READY_FOR_FE` requires a merged BE PR, published artifact, and working test
path. FE acknowledges the exact version. If impact is `None`, record the reason.

## Documentation Change Block

Add this block whenever the issue creates or updates canonical documentation:

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

Several Jira items may reference the same canonical page, but this GitHub Issue
still has exactly one primary Jira item. Update existing content by exact
content ID; never create a replacement because its title or FE consumer changed.

## Feature Issue

```markdown
# [Feature] <Observable outcome>

## Traceability

- Jira task:
- Product/design/Confluence docs:
- Related/dependency issues:

## Classification

- Labels: type:feature, area:<frontend|backend|shared>, priority:<p0-p3>
- Primary owner:
- Branch: feature/<issue-number>-<slug>
- AI involvement: none | implement | assist | review | validate

> If labels are unclear or conflict with Jira, ask the human/manager before starting.

## Context and problem

<Current problem, affected users/systems, and why it must be solved>

## Objective

<One observable outcome>

## User story / use case

As a <persona>, I want <capability> so that <value>.

## Scope

### In scope

- <Behavior/module/interface allowed to change>

### Out of scope

- <Behavior/module/interface outside this issue>

## Required behavior

- <Required behavior or scenario>

## Behavior that must remain unchanged

- <Contract, flow, data, or UX that must not regress>

## Dependencies and interfaces

- Inputs/dependencies:
- Expected outputs:
- Public/API/data/UI impact:
- Frontend impact: None | Handoff required

## Acceptance criteria

- [ ] <Pass/fail outcome 1>
- [ ] <Pass/fail outcome 2>
- [ ] Existing behavior named above remains unchanged.

## Validation

### Automated

```bash
<exact command>
```

### Manual/runtime

1. <Exact check and expected result>

### Evidence required

- Frontend: screenshots/video, viewport/browser, and relevant states.
- Backend: contract/data impact and sanitized samples when useful.

## AI authority

- Allowed actions:
- Approval-required actions:
- Stop conditions:
- Required handoff:
```

## Bug Issue

```markdown
# [Bug] <Actual symptom> when <condition>

## Traceability

- Jira task:
- Incident/support report:
- Relevant docs:
- Related/dependency issues:

## Classification

- Labels: type:bug, area:<frontend|backend|shared>, priority:<p0-p3>
- Primary owner:
- Branch: fix/<issue-number>-<slug>
- AI involvement: none | diagnose | implement | assist | review | validate

> If labels are unclear or conflict with Jira, ask the human/manager before starting.

## Environment

- Environment/version/commit:
- Browser/device or service/runtime:
- Frequency: always | intermittent | once
- First observed at:

## Reproduction

1. <Step>
2. <Step>

## Actual behavior

<Observed behavior; do not state assumptions as facts>

## Expected behavior

<Correct observable behavior>

## Evidence

- Sanitized logs/error:
- Screenshot/video/request ID:
- Minimal sample input:

## Impact

- Affected users/flows/data:
- Workaround:
- Data/security/availability impact:

## Suspected cause (optional)

<Hypothesis and evidence; state that this is not a confirmed root cause>

## Scope

### In scope

- Diagnose root cause and fix the failing shared path.
- Add the smallest meaningful regression check.

### Out of scope

- <Unrelated cleanup/refactor>

## Behavior that must remain unchanged

- <Sibling callers/contracts/flows that must not regress>

## Acceptance criteria

- [ ] Original reproduction fails before the fix and passes after it.
- [ ] Root cause is established by evidence.
- [ ] A regression check protects the failed behavior.
- [ ] Named unchanged behavior still passes.

## Validation

### Automated

```bash
<exact regression and focused test commands>
```

### Manual/runtime

1. Reproduce on <environment>.
2. Confirm <expected result>.

## AI authority

- Allowed actions:
- Approval-required actions:
- Stop conditions:
- Required handoff:
```

## Technical Task Issue

```markdown
# [Technical] <Observable technical outcome>

## Traceability

- Jira task:
- Architecture/Confluence docs:
- Related/dependency issues:

## Classification

- Labels: type:technical, area:<frontend|backend|shared>, priority:<p0-p3>
- Primary owner:
- Branch: <docs|refactor|test|chore|ci>/<issue-number>-<slug>
- AI involvement: none | implement | assist | review | validate

> If labels are unclear or conflict with Jira, ask the human/manager before starting.

## Context and current state

<Current limitation or operational need>

## Objective

<One observable technical outcome>

## Scope

### In scope

- <Owned modules/files/interfaces>

### Out of scope

- <Explicit exclusions>

## Constraints and behavior that must remain unchanged

- <Compatibility, dependency, performance, security, or operational boundary>

## Dependencies and interfaces

- Inputs/dependencies:
- Outputs consumed by:
- Migration/version impact:

## Acceptance criteria

- [ ] <Pass/fail technical outcome 1>
- [ ] <Pass/fail technical outcome 2>
- [ ] Named constraints remain satisfied.

## Validation

### Automated

```bash
<exact command>
```

### Manual/runtime

1. <Exact check and expected result>

## AI authority

- Allowed actions:
- Approval-required actions:
- Stop conditions:
- Required handoff:
```

## Stop conditions chung

Stop the dependent scope and ask the Issue Owner/Manager when:

- Jira, Scope, owner, or Acceptance criteria conflict;
- labels cannot be established from evidence;
- a required dependency/credential/environment is missing;
- write scope overlaps another issue/agent;
- a destructive, irreversible, or production action is unauthorized;
- validation cannot run or repeated failure has no known root cause;
- FE dependency lacks a Hub, paired issue, exact contract version, or required
  handoff is not `READY_FOR_FE`/`ACKNOWLEDGED`.
