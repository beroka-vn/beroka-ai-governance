# AI Agent Assignment, Review, and Handoff Templates

Use this document for Codex, Claude, Cursor, Gemini, Kimi, or an equivalent AI
agent. Repository-specific instructions and the linked issue take precedence.

## Operating rules

- Read the issue, repository rules, and linked documentation before editing.
- Work only in the assigned repository, branch, and file scope.
- Keep one primary writer per branch at a time.
- Do not invent requirements, priority, ownership, dependencies, or labels.
- Add issue/PR labels when the mapping is clear. If classification is confusing,
  ask the human/manager and wait for the decision.
- Classify work as Frontend, Backend, or shared before planning. Shared work
  requires exact targets, one primary tracking repository, and fresh governance
  context for each target.
- Every GitHub issue needs one primary human owner. An explicit assignee wins;
  otherwise use the requesting developer when known, then the authenticated
  human creator. Never default to a bot or service account.
- If any requirement, scope, ownership, dependency, label, or documentation
  destination is confusing, ask the developer and wait instead of guessing.
- Route Backend Jira items to project `BB` at
  https://beroka.atlassian.net/jira/software/projects/BB/boards/34/backlog and
  Frontend Jira items to project `BF` at
  https://beroka.atlassian.net/jira/software/projects/BF/boards/35/backlog.
- Follow [Jira and Confluence Template](jira-confluence.md) for Jira content and
  hierarchy. For Story/Task/Bug/Feature, validate the parent Epic. If it is
  missing, invalid, inactive, or ambiguous, list related active Epics and wait
  for the developer to choose; never create an orphan item or create it in both
  projects.
- For a new Epic, require at least one initial child of type `Feature`, `Story`,
  `Task`, or `Bug` before any external write. Never parent a `Subtask` directly under an Epic.
  Create/read back the Epic first, then create the child with the returned Epic
  key as parent and leave Sprint unset unless requested.
- A truly unrelated one-off or hotfix may be standalone only after explicit
  confirmation. Record `Parent Epic: N/A`, standalone reason, reviewed Epic
  candidates, owner, priority, and GitHub issue.
- After the same-project duplicate check, scan the other Jira project for a
  real dependency or the same capability: BF creation scans BB and BB creation
  scans BF. Similar titles are candidates only; show evidence and wait for the
  developer before aligning names, linking records, or updating the Hub.
- A Frontend-only Epic or child creates no BB link or record. If BE relevance is
  unclear, ask the developer. If a dependency is confirmed but the counterpart
  is absent, use `MAPPING_INCOMPLETE`; do not invent or silently create BB work.
- For a BF child with BE dependency, resolve its BF parent, paired BB Epic,
  exact BB work item, link type, Capability ID, Backend Capability Registry
  row, Hub reference, and contract/handoff state before reporting the dependent
  scope Ready.
- Automatically classify the request as `planning-only` or `execution`. A
  request to plan and then implement uses `execution`; ask one mode question
  only when intent cannot be determined from the request.
- Before executing a Jira Story/Task/Bug/Feature, compare the requesting
  developer and current Jira assignee by `accountId`, not display name.
- If the item is assigned to someone else or is unassigned, warn the developer
  and wait for explicit confirmation. Reassign, read the item back, and verify
  the new assignee before implementation. A failed reassignment is a blocker.
- After creating any Jira item, read it back and verify project, issue type,
  status, parent, assignee, base board-filter membership, backlog enablement,
  and status mapping. Do not claim backlog completion until this gate passes.
- If the item exists but is not visible in the expected backlog/Epic panel, do
  not create a duplicate or change board settings without explicit authority.
- The assignee gate applies to the exact executable Jira item, not its parent
  Epic or a coordination item. Jira reassignment does not transfer an active
  Git branch; branch handoff remains required.
- Route Backend GitHub Issues and Pull Requests to
  https://github.com/beroka-vn/Beroka_Backend and Frontend work to
  https://github.com/beroka-vn/Beroka_Frontend.
- Stay within the stored GitHub Team-verified `FE`, `BE`, or `FULL_STACK` role;
  `ROLE_SCOPE_DENIED` blocks a mismatched repository profile.
- Unrelated repositories require an exact catalog record. For shared work,
  confirm one primary tracking repository instead of duplicating the Issue.
- Route Frontend documentation to
  https://beroka.atlassian.net/wiki/spaces/Berokafron and Backend documentation
  to https://beroka.atlassian.net/wiki/spaces/Berokaback/overview. Durable
  capability pages use globally unique `<Scope> — <Domain> — <Transport>`
  Folders. Epic-specific pages use `<Epic key> — <Epic summary>`.
- If the native Epic Folder is missing or cannot be created through the
  connector, return `FOLDER_CREATION_REQUIRED`. Never fall back to a parent page
  or space root. Verify page `parentId` and `parentType = Folder` after writes;
  otherwise return `DOC_HIERARCHY_FAILED`.
- For BE work consumed by FE, use one confirmed Epic Integration Hub linked
  from both Jira projects and exact Backend Capability Registry rows. Keep the
  team-local canonical OpenAPI/JSON Schema/event-schema artifact in BE. The
  consumer contract is the self-contained Confluence handoff page; never make
  FE reconstruct it from issue descriptions or private repository links.
- Pair project-local BB/BF Epics with `Relates`. Map one Backend Feature to one
  or more BF items using `Blocks` plus one exact immutable Capability ID in the
  canonical Registry row; title similarity is never mapping evidence.
- A BF item and its FE `<Module> — Capability Index` must link the Registry row
  and shared Hub. If FE cannot open the owning BE Folder/Hub, return
  `CROSS_SPACE_ACCESS_REQUIRED`; do not duplicate the contract in FE
  Confluence.
- Do not report a BE → FE handoff as `READY_FOR_FE` until the page has passed
  post-write readback with its exact Confluence content ID/version, parent,
  space, title, and owner. Create is `DRAFT` only; Jira stays in its own
  governed lifecycle state. Notify the linked FE Jira item and record
  acknowledgement.
- Never expose credentials, tokens, private payloads, or sensitive topology.
- Do not perform destructive or production actions without explicit authority.
- Run relevant validation before claiming completion.
- Report failures and unverified items as such; never represent them as passes.
- You may review any change type, including security, database, public API, and
  production-related changes.
- Do not approve or merge a PR without explicit human confirmation for that
  exact PR and commit SHA.

## Planning Request Intake Template

Use this when the developer asks only for planning or Jira decomposition.
Planning does not authorize Jira creation unless the developer explicitly asks
for that external write.

```text
Prepare a plan without implementation.

REQUEST
- Requesting developer: <name and Jira accountId if known>
- Outcome/requirement: <observable outcome>
- Work area: <Frontend | Backend | Shared/cross-service | infer from context>
- Requested item type: <Epic | Story | Task | Bug | Feature | propose one>
- Supplied Epic: <key/name | not provided>
- Cross-project relevance: <dependency | same capability | Frontend-only | unknown>
- Known counterpart: <BB/BF key and URL | not provided>
- Initial child for a new Epic: <Feature/Story/Task/Bug summary, scope, priority,
  assignee intent | not applicable>
- Relevant inputs: <URLs/paths | none>

OUTPUT
- Validate the Jira project and parent Epic.
- Run symmetric counterpart discovery for every new Epic. For an existing Epic
  child, run it when dependency/capability relevance is present or unclear.
  Never create a link from title similarity alone.
- If Epic is missing, invalid, inactive, or ambiguous, use the Active Epic
  Confirmation Template and stop before creating child items.
- Return a draft only unless Jira creation was explicitly requested.
- If creation was requested, use the Jira Creation Verification Template before
  reporting completion.
- For a new Epic, stop before external creation until at least one valid initial
  child is supplied.
```

## Active Epic Confirmation Template

```text
Active Epic confirmation required
- Requested item: <Story | Task | Bug | Feature | new Epic>
- Proposed project: <BB | BF>
- Supplied Epic: <key/name | not provided>
- Validation result: missing | invalid | inactive | ambiguous | similar Epic exists
- Related active Epics:
  1. <key> — <summary> — <status> — <owner> — <URL> — <why related>
  2. <key> — <summary> — <status> — <owner> — <URL> — <why related>
- Proposed parent: <key | none>
- Decision required: choose an Epic | create a new Epic | cancel
```

If Jira cannot be read, report the missing access. Never invent an Epic list
from memory or chat context.

## Cross-Project Counterpart Confirmation Template

Use this after the project-local parent/duplicate check. A candidate is not a
mapping until the developer confirms it.

```text
Cross-project counterpart confirmation
- Requested project/item: <BB | BF> / <Epic | Feature | Story | Task | Bug>
- Validated project-local parent: <key/summary/URL | N/A for new Epic>
- Cross-project relevance: dependency | same capability | Frontend-only | unclear
- Candidates:
  1. <key/type/summary/status/owner/URL> — <evidence>
  2. <key/type/summary/status/owner/URL> — <evidence>
- Proposed aligned base name: <name | keep requested name | N/A>
- Proposed Epic link: Relates | None
- Proposed child link: Blocks | Relates | None
- Capability ID / Registry row / Integration Hub: <exact values | Pending | N/A>
- Developer decision: pair existing | Frontend-only | Pending with owner | cancel
- Result: PASS | NO_BACKEND_DEPENDENCY | MAPPING_INCOMPLETE | MAPPING_CONFLICT | FAILED_READBACK
```

`Frontend-only` performs no BB write. `Pending with owner` permits creation of a
BF backlog item after explicit confirmation, but its dependent scope is not
Ready. Never auto-create the missing counterpart.

## Jira Creation Verification Template

```text
Jira creation verification
- Created item: <key and URL>
- Project / issue type: <expected> — PASS | FAIL
- Parent Epic: <expected> — PASS | FAIL | N/A
- Initial child: <key/type/summary> — PASS | FAIL | N/A
- Sprint: <unset | requested Sprint> — PASS | FAIL
- Assignee: <expected accountId> — PASS | FAIL
- Status: <status>
- Target board/backlog: <BB/34 | BF/35>
- Base board filter match: PASS | FAIL
- Backlog enabled and status mapped: PASS | FAIL
- Visible location: Backlog | Epic panel | requested Sprint | Not visible
- Result: PASS | EPIC_CREATED_CHILD_FAILED | CREATED_BUT_NOT_VISIBLE | FAILED_READBACK
```

Leave Sprint unset unless the developer requested one. Verify through the base
board filter or board/backlog API, not a personal quick filter. If the item was
created but is not visible, report the created key and exact failed check; do
not create another item or modify board configuration without authority.
If an Epic exists but its initial child fails creation/readback, report
`EPIC_CREATED_CHILD_FAILED` and reuse that Epic on retry.

## Implementation Assignment Template

```text
Execute the assigned GitHub issue as the named role.

IDENTITY
- Role: <implementer | contributor | reviewer | validator>
- Requesting developer: <name>
- Requester Jira accountId: <accountId | verification needed>
- Current Jira assignee: <name and accountId | Unassigned>
- Jira assignee verified as requester: <yes | no>
- Human manager/coordinator: <name>
- AI agent: <agent/account>

TRACEABILITY
- Jira task: <key and URL>
- GitHub issue: <URL>
- Relevant documentation: <URLs/paths>

JIRA ROUTING
- Work area: <Frontend | Backend | Shared/cross-service>
- Project/backlog: <BF/board 35 | BB/board 34 | developer decision needed>
- Issue type: <Epic | Story | Task | Bug | Feature | other>
- Parent hierarchy: <confirmed Epic key | none for Epic | developer decision needed>

EXECUTION PREFLIGHT
- Request mode: execution
- Exact executable Jira item: <key and URL>
- Assignment state: matched | mismatch | unassigned
- Reassignment confirmation: <not needed | exact developer confirmation>
- Reassignment readback: <verified accountId | blocked>
- GitHub primary owner/branch writer: <name; matched | handoff needed>
- Definition of Ready: <pass | missing fields>

WORKSPACE
- Repository: <exact URL/path; developer confirmation required if unclear>
- Base branch: <branch>
- Task branch: <type>/<issue-number>-<slug>
- Primary writer: <name/agent>

OBJECTIVE
- Observable outcome: <one outcome>

SCOPE
- Owned files/modules: <exact paths or modules>
- Allowed behavior changes: <exact behavior>
- Forbidden/out-of-scope changes: <exact exclusions>
- Behavior that must remain unchanged: <contracts/flows/data>

DEPENDENCIES AND INTERFACES
- Required inputs/dependencies: <items and versions/links>
- Expected outputs/consumers: <interfaces/artifacts>

CROSS-TEAM HANDOFF
- Frontend impact: <None and reason | Handoff required>
- Cross-project relevance: <dependency | same capability | Frontend-only | N/A>
- Counterpart confirmation: <developer decision and evidence | N/A>
- Capability ID: <exact uppercase kebab-case value | N/A>
- Epic Integration Hub: <URL | N/A>
- Paired Backend Epic: <key/URL | N/A>
- Paired Frontend Epic: <key/URL | Pending with owner | N/A>
- Provider Jira / Consumer Jira: <BB/BF key and URL | Pending with owner | N/A>
- Confluence handoff content ID/version: <ID/version | Pending with owner | N/A>
- Epic `Relates` readback: <pass | fail | N/A>
- Child link type/readback: <Blocks | Relates | None> — <pass | fail | pending | N/A>
- Hub mapping-row readback: <pass | fail | pending | N/A>
- Mapping result: <PASS | NO_BACKEND_DEPENDENCY | MAPPING_INCOMPLETE | MAPPING_CONFLICT | FAILED_READBACK | N/A>
- Handoff state: <DRAFT | READY_FOR_FE | ACKNOWLEDGED | BLOCKED | SUPERSEDED>
- FE acknowledgement: <owner, exact Confluence content ID/page version, timestamp | pending | N/A>

DOCUMENTATION ROUTING
- Work area: <Frontend | Backend | Shared/cross-service>
- Use case/service: <name>
- Target space: <Beroka-frontend | Beroka-backend | developer decision needed>
- Jira Epic and required native Folder title: <key — summary>
- Native Folder URL/ID: <URL/ID | FOLDER_CREATION_REQUIRED>
- Page parent readback: <parentId and parentType = Folder | DOC_HIERARCHY_FAILED>
- Frontend Index: <URL | Pending with owner | N/A>
- Cross-space access: <pass | CROSS_SPACE_ACCESS_REQUIRED | N/A>

CLASSIFICATION
- Repository owner: <organization | personal account>
- Required type: <native Feature/Bug/Task | type:feature/type:bug/type:technical fallback>
- Required area label(s): <area:frontend | area:backend | area:shared>
- Required priority label: <priority:p0 | priority:p1 | priority:p2 | priority:p3>
- Primary human owner: <explicit assignee | requesting developer | authenticated creator>
- PR must copy these labels: yes

ACCEPTANCE CRITERIA
- <observable pass/fail criterion>
- <observable pass/fail criterion>

VALIDATION
- Automated commands: <exact commands>
- Manual/runtime checks: <exact checks and expected results>
- Required evidence: <screenshots/log summary/request-response/etc.>

AUTHORITY
- Allowed actions: <read/edit/test/commit/open PR/etc.>
- Approval-required actions: <production/destructive/external writes/etc.>
- AI review authority: all change types
- AI PR approval authority: none unless separately confirmed by a human
- AI merge authority: none unless separately confirmed by a human

STOP CONDITIONS
- <unclear contract, ownership conflict, missing credential, destructive target,
  assignment mismatch without confirmation, failed reassignment/readback,
  validation environment mismatch, confusing documentation destination,
  missing Integration Hub/paired issue/contract version for FE dependency, or
  other exact boundary>

HANDOFF
- Required output: changed files, behavior changed/unchanged, exact
  commands/results, unverified items, residual risks, labels, and next action.
```

## Jira Assignment Mismatch Template

```text
Jira assignment mismatch
- Task: <key and summary>
- Requesting developer: <name and accountId>
- Current assignee: <name and accountId | Unassigned>
- Proposed assignee: <requesting developer>
- Impact: ownership will change before AI implementation starts.

Confirm required:
“I confirm ownership of <key>, reassign it to me, and continue execution.”
```

After confirmation, assign the exact Jira item, read it back, and verify the
requester's `accountId`. Add a short Jira comment recording old/new assignee and
the explicit request. If assignment or readback fails, stop implementation and
ask the developer to self-assign. Do not reassign a parent Epic or coordination
item solely because a child implementation request was made.

## BE → FE Handoff Template

```text
Handoff schema: 1
Handoff state: READY_FOR_FE
Provider Jira: {{PROVIDER_JIRA}}
Consumer Jira: {{CONSUMER_JIRA}}
Scope: {{SCOPE}}
Domain: {{DOMAIN}}
Confluence content ID: {{CONTENT_ID}}
Confluence page version: {{PAGE_VERSION}}
Owner account ID: {{OWNER_ACCOUNT_ID}}
Effective date: {{EFFECTIVE_DATE}}
Supersedes: {{SUPERSEDES}}
Superseded by: {{SUPERSEDED_BY}}
API impact: affected
WebSocket impact: affected
Missing sections: None

## Purpose and delivered behavior

The quote contract supports both snapshots and live changes.

## Affected user flows, assumptions, and non-goals

Quote detail screens read once and then subscribe; history is unchanged.

## Authentication and authorization

Authenticated users with quote-read permission may use both transports.

## Public data types and compatibility

Both transports use the same additive quote type.

## State and delivery semantics

Snapshots are current and stream delivery is at least once.

## Errors and edge cases

Unknown symbols have stable errors on both transports.

## Frontend implementation guidance

Load a snapshot before subscribing for later changes.

## Sanitized examples and validation evidence

Public sample values were exercised by contract tests.

## Known limitations and unverified items

Exchange outages can delay updates.

## FE acknowledgment

Frontend acknowledgment is pending. Respond on {{CONSUMER_JIRA}} with Confluence content ID {{CONTENT_ID}} version {{PAGE_VERSION}}.

## Affected API inventory

GET /v1/quotes/{symbol}

## API operation: GET /v1/quotes/{symbol}

Public quote lookup.

### Permissions

quote-read permission is required.

### Headers

Accept: application/json.

### Path parameters

symbol is the public market symbol.

### Query parameters

None are accepted.

### Request payload

No request body is accepted.

### Success status and payload

200 returns a quote object.

### Stable public errors

404 is returned for an unknown symbol.

### Pagination

This single-resource operation is not paginated.

### Idempotency

GET is idempotent.

### Retry

Retry transient 503 responses with bounded backoff.

### Cache

Clients may cache the response for one second.

### Timestamp semantics

observedAt is an ISO-8601 UTC timestamp.

### Sanitized request/response examples

GET /v1/quotes/ABC returns {"symbol":"ABC"}.

## Unaffected API inventory

All other public API operations are unchanged.

## Affected WebSocket inventory

wss://api.example.test/v1/quotes

## WebSocket contract: wss://api.example.test/v1/quotes

Public quote change stream.

### Public connection URL and authentication

Connect with the documented user session.

### Subscribe and unsubscribe requests

Subscribe and unsubscribe with the public symbol.

### Event envelope and affected message payloads

Events contain type, eventId, observedAt, and quote payload.

### Ordering

Ordering is guaranteed per symbol.

### Deduplication

Deduplicate by eventId.

### Replay/resume

Resume from the last acknowledged eventId.

### Reconnect

Reconnect with bounded exponential backoff.

### Heartbeat

The server sends a heartbeat every 30 seconds.

### Timeout

Reconnect after 90 seconds without a heartbeat.

### Backpressure

Render the newest quote when behind.

### Error events

Invalid subscriptions emit a stable error event.

### Close codes

4010 indicates an expired user session.

### Sanitized message examples

{"type":"quote","eventId":"evt-1","symbol":"ABC"}

## Unaffected WebSocket inventory

All other public WebSocket streams are unchanged.
```

This consumer-facing page contains Jira and Confluence references only. Keep
GitHub URLs in team-local Issue/PR sections. The BE owner updates the Registry
and Hub after merge; the FE owner acknowledges the exact Confluence content ID/page version.

Resolve every `{{TOKEN}}` from exact user or readback evidence before preflight;
never send an unresolved token. Cursor is the only trusted Confluence
create/update boundary in this release. Codex and Claude Confluence create/update require a trusted actual-body boundary and must stop with
`CLIENT_BODY_GATE_REQUIRED`; do not treat a temporary or caller-provided body
file as proof of the Atlassian request. Jira operations, Confluence moves, and
capability-only readback retain their existing governed paths. For this READY
page, Cursor runs:

```sh
beroka-governance preflight {{REPOSITORY}} --client cursor --operation confluence-handoff-write --non-interactive --confluence-action update --target-content-id {{CONTENT_ID}} --expected-parent-id {{ACTIVE_FOLDER_ID}} --handoff-body-file {{HANDOFF_BODY_FILE}}
```

Before the read, prove connector capability. This returns
`Readback: CAPABILITY_ONLY`, not post-write proof; without trusted client
post-tool write/read results, report unverified and do not report
`READY_FOR_FE`:

```sh
beroka-governance preflight {{REPOSITORY}} --client {{CLIENT}} --operation confluence-handoff-verify --non-interactive --confluence-action update --target-content-id {{CONTENT_ID}} --expected-parent-id {{ACTIVE_FOLDER_ID}} --handoff-body-file {{HANDOFF_BODY_FILE}}
```

For a DRAFT create, use `--confluence-action create --target-content-id new`.

## Cross-Team Capability Mapping Template

Use one exact immutable Capability ID and one canonical Backend Capability
Registry row. Each Epic Integration Hub references that row.
Stop with `MAPPING_INCOMPLETE` when required records are still pending with a
named owner. Stop with `MAPPING_CONFLICT` when the ID is missing, duplicated, or
disagrees with Jira links; title similarity is not mapping evidence.

Discovery is symmetric: BF creation scans BB and BB creation scans BF. Pure FE
work returns `NO_BACKEND_DEPENDENCY` without creating a BB link or Hub row. For
confirmed mappings, Epic pairs use `Relates`; child dependencies use `Blocks`
from provider to consumer, while non-blocking same-capability children use
`Relates`.

```text
CROSS-TEAM MAPPING
- Capability ID: exact uppercase kebab-case value
- Backend Capability Registry row: exact URL/content ID and readback
- Backend Epic and Feature: Jira keys and URLs
- Frontend Epic: Jira key and URL
- Frontend work items: one or more Jira keys/URLs or Pending with owner
- Epic link: Relates readback result
- Child links: Blocks | Relates | None, with readback result
- Integration Hub Registry reference: URL and exact readback result
- Result: PASS | NO_BACKEND_DEPENDENCY | MAPPING_INCOMPLETE | MAPPING_CONFLICT | FAILED_READBACK
```

## Native Epic Folder Templates

Use this result when the required native Confluence Folder is missing or the
connector cannot create it. Do not create a page at the space root or under a
page as a fallback.

```text
FOLDER_CREATION_REQUIRED
- Jira Epic: exact key and summary
- Confluence space: exact key and URL
- Required native Folder title: <Scope> — <Domain> — <Transport> or
  Jira Epic key — Epic summary
- Required parent location: exact catalog Confluence root for capability folders
- Required action: confluence-discover → confluence-bootstrap-plan → human
  confirm → MCP create → capture → verify → reviewed inventory PR
- Work that may continue safely: explicit independent scope or None
```

After the Folder exists, verify every created or moved page with this block:

```text
EPIC FOLDER HIERARCHY VERIFICATION
- Jira Epic and required Folder title: <key — summary>
- Native Folder URL/ID: <URL/ID | FOLDER_CREATION_REQUIRED>
- Page URL/ID: <URL/ID>
- Page parent readback: <parentId and parentType = Folder | DOC_HIERARCHY_FAILED>
- Shared Integration Hub: <URL and access PASS | CROSS_SPACE_ACCESS_REQUIRED>
- Frontend Capability Index: <URL and Registry/Hub link readback | Pending with owner | N/A>
- Result: <PASS | FOLDER_CREATION_REQUIRED | CROSS_SPACE_ACCESS_REQUIRED |
  DOC_HIERARCHY_FAILED | FAILED_READBACK>
```

## Label Clarification Template

Use this instead of guessing when any label is confusing:

```text
Label clarification needed
- Record: <issue/PR URL>
- Clear labels: <confirmed labels>
- Confusing field: type | area | priority
- Candidate values: <option A>, <option B>
- Evidence: <why both are plausible>
- Decision needed from: <human/manager>
- Work that can continue safely while waiting: <scope or none>
```

## General Clarification Template

Use this whenever any material task detail is confusing:

```text
Clarification needed
- Record/task: <URL or key>
- Confusing topic: requirement | scope | ownership | dependency | label |
  Jira project/issue type/parent hierarchy | documentation location | other
- What is already clear: <confirmed facts>
- Candidate interpretations or locations: <option A>, <option B>
- Evidence: <why the task is ambiguous>
- Decision needed from: <developer>
- Work that can continue safely while waiting: <scope or none>
```

## Blocked Report

```markdown
## Blocked

- Issue/PR:
- Current branch/commit:
- Blocked scope:
- Evidence:
- What was attempted:
- Decision or input needed:
- Decision owner:
- Work that can continue safely:
- Next action after unblock:
```

## Implementation Handoff

```markdown
## Implementation handoff

- Jira/issue:
- Branch/current commit:
- Changed files:
- Behavior changed:
- Behavior intentionally unchanged:
- Labels applied to issue/PR:
- Validation commands/results:
- Manual/runtime result:
- Unverified items and exact blockers:
- Residual risks:
- Frontend impact: None | Handoff required
- Epic Integration Hub / Confluence content ID/page version / handoff state:
- Linked FE issue acknowledgement:
- Recommended next action:
```

## Review Assignment Template

```text
Review the linked PR against its GitHub issue and current commit.

- Jira task: <key and URL>
- GitHub issue: <URL>
- Pull request: <URL>
- Commit SHA to review: <full SHA>
- Repository rules/docs: <paths/URLs>
- Review scope: correctness, acceptance criteria, regression risk, validation
  evidence, security/data/contract impact, and label consistency.
- Do not modify the branch unless the issue owner explicitly asks you to.
- You may review any change type.
- Without explicit human authorization, provide comments and a recommendation
  only; do not submit approval or merge.
```

## Review Handoff

```markdown
## Review handoff

- PR/reviewed commit:
- Reviewer:
- Issue scope result: pass | fail
- Acceptance criteria result: pass | fail | partially verified
- Validation evidence checked:
- Label consistency: pass | clarification needed
- Blocking findings:
- Non-blocking findings:
- Unverified items:
- Recommendation: approve | request changes | comment only
- Human authorization present for AI approval/merge: yes | no
- Re-review trigger:
```

## Human Authorization for AI Approval or Merge

The human must provide all fields. Authorization expires when the PR commit
changes.

```text
AI authorization
- PR: <URL or #number>
- Reviewed commit: <full SHA>
- Agent: <agent/account>
- Allowed action: approve | merge | approve and merge
- Merge method: squash | merge | rebase
- Conditions: <none or exact conditions>
- Authorized by: <human name>
- Authorized at: <timestamp with timezone>
```

If the PR, full SHA, agent, or allowed action is missing, the AI may only
review and comment. It must ask the human before it can approve or merge.
