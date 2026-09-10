# Jira and Confluence Templates

## Required boundary

| Jira | Confluence | GitHub |
| --- | --- | --- |
| Manage high-level work | Store durable knowledge and completion docs | Manage technical implementation |
| Outcome, context, priority, owner, timeline, status | Decisions, usage/operations, limitations | Scope, acceptance, code, review, validation |
| Link Issues, PRs, completion docs | Link Jira, Issues, merged PRs | Link Jira and relevant docs |

Jira does not describe files/classes, algorithms, or implementation. Those
belong in the GitHub Issue. Confluence does not replace Jira status or PR evidence.

## Jira creation location

- Backend Epic/Story/Task/Bug/Feature: project `BB` at
  [Beroka Backend backlog](https://beroka.atlassian.net/jira/software/projects/BB/boards/34/backlog).
- Frontend Epic/Story/Task/Bug/Feature: project `BF` at
  [Beroka Frontend backlog](https://beroka.atlassian.net/jira/software/projects/BF/boards/35/backlog).
- Use the matching Epic, Story, Task, Feature, or Bug guidance below. Preserve
  any other native type and use the nearest high-level structure.
- Before creating a child, establish work area, type, and parent Epic. An active
  Epic belongs to the correct project, is not archived, and has
  `statusCategory != Done`.
- If the Epic is missing, invalid, inactive, or ambiguous, list active candidates
  and wait. Never select a parent, create an orphan, or duplicate across projects.
- Before a new Epic, show duplicates and require an initial Feature/Story/Task/Bug.
  Never create a direct Subtask under an Epic.
- A truly unrelated one-off or hotfix may be standalone only after explicit
  confirmation. Record `Parent Epic: N/A`, the standalone reason, reviewed
  active Epic candidates, owner, priority, and GitHub issue.
- BF creation scans BB after BF duplicate checks; BB creation scans BF. Similar
  names are candidates only and never authorize links.
- A BF child needs BB mapping only for a BE dependency or paired Epic. Pure FE
  creates no BB link. Ask when dependency/counterpart is unclear.
- Planning-only returns a draft unless an external write is explicit.
- After creation, read back fields, board filter, backlog, and status mapping.
- Unsprinted children belong in unranked Backlog. Create the initial child from
  the read-back Epic key and leave Sprint unset unless requested.
- If an existing item is hidden, return `CREATED_BUT_NOT_VISIBLE`; do not
  duplicate it or edit board settings.

```text
Active Epic confirmation required
- Requested item: <Story | Task | Bug | Feature | new Epic>
- Work area: <Frontend | Backend | Shared/cross-service>
- Proposed project: <BB | BF>
- Supplied Epic: <key/name | not provided>
- Validation result: missing | invalid | inactive | ambiguous | similar Epic exists
- Related active Epics:
  1. <key> — <summary> — <status> — <owner> — <URL> — <why related>
  2. <key> — <summary> — <status> — <owner> — <URL> — <why related>
- Proposed parent: <key | none>
- Developer decision: choose an Epic | create a new Epic | confirm standalone | cancel
```

If Jira cannot be read, report access failure. Never invent an Epic list.

## Cross-team Jira intake

Frontend → Backend and Backend → Frontend use `jira-intake-write` from the
requesting repository. The preflight result must name the exact receiving
repository and Jira project. Missing supported intake state or equivalent-field
evidence returns `INTAKE_CONFIGURATION_REQUIRED`.

```text
Cross-team Jira intake request
- Direction: Frontend → Backend | Backend → Frontend
- Requester/reporter accountId:
- Receiving repository/project: <exact preflight values>
- Requested outcome and business reason:
- Requested priority: <input, not commitment>
- Duplicate search:
- Create metadata and intake state/equivalent field: VERIFIED | MISSING
- Assignee: Unassigned unless receiving-team accountId is explicitly confirmed
- Sprint: Unset
- Parent: Unset — receiving team selects
- Work-item language:
- Result: PASS | INTAKE_CONFIGURATION_REQUIRED | ROUTING_REQUIRED
```

```text
Receiving-team triage decision
- Intake Jira item:
- Decision: Accepted | Rejected
- Duplicate resolution:
- Final issue type and active parent Epic:
- Final priority and Sprint:
- Executor/assignee accountId:
- Readiness: Ready | Not Ready
- Definition of Ready: PASS | FAIL
- Existing primary GitHub Issue search: NONE | <issue>
- Receiving-repository GitHub Issue/readback: <issue | Pending>
- Result: PASS | NOT_READY | DUPLICATE
```

Assignment alone does not authorize a GitHub Issue. Creation requires
`Accepted + Ready + Assigned + Definition of Ready PASS` and no existing
primary GitHub Issue. The requester/reporter remains distinct from the
executor/assignee. Intake is agent-driven; there is no event listener.

An exact receiving-team account may be assigned only after the user or
receiving team confirms its Atlassian `accountId`; otherwise return
`ASSIGNEE_CONFIRMATION_REQUIRED`. FE owns BF updates and BE owns BB updates.
Task, Bug, and Feature intake is symmetric; opposite-project Epic creation
requires receiving-team confirmation. Opposite-team private GitHub links in
cross-team Jira or handoff text return `CROSS_TEAM_LINK_SCOPE_DENIED`; use the
exact accessible Confluence page.

```text
CROSS-TEAM CONFLUENCE HANDOFF
- Provider Jira: <BB-KEY>
- Consumer Jira: <BF-KEY>
- GitHub: N/A
- Confluence content ID and version: new/pending | <numeric ID>/<positive integer>
- Expected parent ID: <exact reviewed ACTIVE Folder ID>
- Pre-write arguments: --confluence-action create|update --target-content-id new|ID --expected-parent-id ACTIVE_FOLDER_ID --handoff-body-file FILE
- Read capability: confluence-handoff-verify --confluence-action update --target-content-id ID --expected-parent-id ID --handoff-body-file FILE
- Post-write proof: trusted client post-tool write result plus subsequent read result; caller assertions are not evidence
- Result: PASS | FOLDER_CREATION_REQUIRED | HANDOFF_BODY_INVALID |
  CROSS_TEAM_LINK_SCOPE_DENIED | HANDOFF_READBACK_REQUIRED
```

Ordinary Confluence writes are allow-by-default. A cross-team handoff is a
self-contained Confluence page under an exact reviewed ACTIVE Folder; it never
uses an opposite-team repository link as its consumer contract. Create is
`DRAFT` only. Report `READY_FOR_FE` only after the exact page readback; Jira
remains in its governed lifecycle state independently. An `UNACTIVATED` content
ID or parent in the governance release inventory returns `DOCS_UNACTIVATED` and
can change only through a reviewed governance release PR. A transport mismatch
on a reviewed drifted row returns `MAPPING_CONFLICT` and must not inspect or
write the connector. Provider status is `To Do -> In Progress` when work starts
and `In Progress -> In Review` when a human marks the provider PR ready for
review. `Closes #<issue>`
normally closes the GitHub Issue. If it remains open, an agent may close it only
after exact merge/link readback proves the delivered commit and the close write
is authorized; otherwise report the issue as blocked. After `Closes #<issue>` automatically closes the current primary GitHub Issue,
or after an agent
completes an authorized manual close under this gate, resolve the exact linked Jira item,
verify the authenticated account against the current assignee, run a
fresh `jira-write` preflight, and transition the item to `In Review`; an item
already in `In Review` is idempotently complete. Then resolve related
documentation only by exact Confluence content ID. If the page, parent, or
required change is missing or ambiguous, ask the user and wait. Otherwise run
a fresh target-bound Confluence preflight, update the documentation, and read
it back. After documentation readback Jira remains in `In Review`; do not move
it to `Done` automatically. After successful documentation readback, report the GitHub, Jira, and Confluence outcomes separately.
Report a blocked Jira or Confluence step separately and do not reopen the GitHub Issue.

## Jira Summary Contract

Use English sentence case, no trailing punctuation, and no Jira key or
`[Epic]`, `[Feature]`, `[Task]`, or `[Bug]` prefix.

- Epic: `<Domain or module> — <Business outcome>`
  - Frontend: `Market overview — Faster investment discovery`
  - Frontend: `Portfolio — Clear real-time performance visibility`
  - Backend: `Market data — Reliable real-time price delivery`
  - Backend: `Order management — Consistent trade execution`
- Feature: `<Capability> — <Observable outcome>`
  - Frontend: `Market charts — Display continuous historical price trends`
  - Frontend: `Watchlist — Reflect live price changes without manual refresh`
  - Backend: `Historical candles API — Return complete time-bucketed market data`
  - Backend: `Order events WebSocket — Publish deterministic order status updates`
- Task: `<Action verb> <Outcome or deliverable>`
  - Frontend: `Add empty-state guidance to the market watchlist`
  - Frontend: `Validate chart rendering across supported time ranges`
  - Backend: `Add idempotency protection to order submission`
  - Backend: `Validate trading sessions before candle aggregation`
- Bug: `<Actual symptom> when <condition>`
  - Frontend: `Chart shows duplicate candles when the WebSocket reconnects`
  - Frontend: `Watchlist loses selected symbols when the page refreshes`
  - Backend: `Order submission creates duplicates when clients retry timed-out requests`
  - Backend: `Candle API omits the latest interval when the market session crosses midnight`

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

`Frontend-only` creates or changes nothing in BB. `Pending with owner` requires
a confirmed dependency and means the BF dependent scope is not Ready.

```text
Jira creation verification
- Created item: <key and URL>
- Project / issue type: <expected> — PASS | FAIL
- Parent Epic: <expected> — PASS | FAIL | N/A
- Standalone reason and reviewed Epic candidates: <evidence | N/A> — PASS | FAIL
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

Return `PASS` only when an initial child and backlog UI read back correctly. On
child failure, return `EPIC_CREATED_CHILD_FAILED` and reuse the Epic.

## Cross-team Capability mapping

- BB and BF use separate Epics linked with `Relates`; never cross-parent items.
- Discovery is symmetric and every candidate requires developer confirmation.
- Pure FE returns `NO_BACKEND_DEPENDENCY` without a BB link/Hub row.
- A Backend Feature may `Blocks` BF items. Each semantic capability and
  transport has one immutable uppercase-kebab-case Capability ID and one
  Backend Capability Registry row.
- Non-blocking same-capability children use `Relates`; dependencies use `Blocks`
  provider → consumer.
- The Registry row is canonical. Epic Hubs reference it and own only
  Epic-specific Jira relationships, consumers, handoff states, and
  acknowledgements.
- Pending counterparts return `MAPPING_INCOMPLETE`; missing/duplicate IDs or
  conflicting links return `MAPPING_CONFLICT`. Never map by title similarity.

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

## Confluence documentation location

- Frontend use cases/services:
  [Beroka-frontend](https://beroka.atlassian.net/wiki/spaces/Berokafron).
- Backend use cases/services:
  [Beroka-backend](https://beroka.atlassian.net/wiki/spaces/Berokaback/overview).
- Durable Backend capability pages live under `Backend Contracts`, not an Epic
  Folder. Native Folder names are globally unique:
  `<Scope> — <Domain> — <Transport>` or
  `<Scope> — <Domain> — <Capability group> — <Transport>`.
- Valid examples are `Shared — Market — API`,
  `Derivatives — User — WebSocket`,
  `Shared — Market — Market Indices — API`, and
  `Shared — Market — Market Indices — WebSocket`. Never create generic
  repeated `Market`, `User`, `API`, or `WebSocket` Folders.
- Each Epic still uses one native Folder named
  `<Epic key> — <Epic summary>` for Epic-specific planning, decisions,
  completion pages, and its Integration Hub.
- If unavailable, return `FOLDER_CREATION_REQUIRED`; never use a page/root fallback.
- After write/move, read back `parentId` and `parentType = Folder`; otherwise
  return `DOC_HIERARCHY_FAILED`.
- Ask the developer about ambiguous shared work, space, Folder, or interpretation.
- One shared Hub lives in the owning Epic Folder and references Registry rows.
  Durable FE pages use `<Module> — Capability Index` and link exact Backend
  content IDs; never duplicate the contract.
- BF items and the Index must open the Hub; otherwise return
  `CROSS_SPACE_ACCESS_REQUIRED` rather than copying content.
- Do not create empty BF Epics, FE Folders, or subpages.
- Missing Registry, scope, domain, transport, exact parent, Capability ID, or
  content ID returns `ROUTING_REQUIRED`; never guess by title.

```text
Documentation location confirmation
- Backend Capability Registry content ID/URL:
- Capability ID and Registry row:
- Documentation class: canonical capability | FE Capability Index | Epic-specific
- Jira Epic and required native Folder title:
- Use case/service:
- Proposed Confluence space and URL:
- Native Folder URL/ID: <URL/ID | FOLDER_CREATION_REQUIRED>
- Required parent location:
- Page parent readback: <parentId and parentType = Folder | DOC_HIERARCHY_FAILED>
- Shared Integration Hub: <URL and access PASS | CROSS_SPACE_ACCESS_REQUIRED>
- Frontend Index: <URL and Hub link readback | Pending with owner | N/A>
- Reason:
- Confirmation needed from: <developer>
- Result: <PASS | FOLDER_CREATION_REQUIRED | CROSS_SPACE_ACCESS_REQUIRED |
  DOC_HIERARCHY_FAILED | FAILED_READBACK>
```

```text
FOLDER_CREATION_REQUIRED
- Jira Epic: exact key and summary
- Confluence space: exact key and URL
- Required native Folder title: <Scope> — <Domain> — <Transport> (capability)
  or Jira Epic key — Epic summary (Epic-only planning folder)
- Required parent location: exact catalog Confluence root for capability folders
- Required action: run beroka-governance confluence-discover REPO, then
  confluence-bootstrap-plan with exact scope/domain/transport; obtain human
  confirmation; create via governed MCP; capture and verify returned IDs; open a
  reviewed governance inventory PR. Do not infer a location or identifier.
- Work that may continue safely: explicit independent scope or None
```

## Canonical Backend capability documentation

Exactly one semantic capability, one transport, one Registry row, and one
canonical Confluence page own each Capability ID. Navigation Folders such as
Market Indices have no Capability ID.

Canonical page metadata:

```text
Capability ID:
Base Capability ID: <ID | N/A>
Capability Registry reference:
Scope: Shared | Derivatives | Underlying
Domain: Market | User
Transport: API | WebSocket
Team-local artifact revision: <version | N/A>
Document revision:
Owner:
Frontend consumers:
Confluence content ID:
```

Every WebSocket capability page contains:

```text
Connection and authorization
Client → Server Commands
Server → Client Events
Payload references, sanitized examples, and documented delta
Ordering, replay, and idempotency
Error and reconnect behavior
Contract version and changelog
```

Team-local Backend artifacts retain their own authoritative schema. The
consumer-facing cross-team handoff page is self-contained and records its exact
Confluence content ID and version with complete public API/WS detail.

## Backend Capability Registry Template

```markdown
# Backend Capability Registry

| Capability ID | Scope | Domain | Transport | Confluence content ID/version | Base Capability ID | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| <UPPERCASE-KEBAB-ID> | <Shared/Derivatives/Underlying> | <Market/User> | <API/WebSocket> | <content ID/version> | <ID/N/A> | <owner> |
```

One Registry row maps one Capability ID to one page. Team-local artifacts keep
their own revision records; the shared Registry exposes only the self-contained
Confluence page identity.

## Frontend Capability Index Template

```markdown
# <Module> — Capability Index

| FE feature/use | Capability ID | Product scope | Transport | Confluence content ID/page version | FE owner |
| --- | --- | --- | --- | --- | --- |
```

The Index may reference capabilities used by several FE modules and never
copies request, response, command, event, or schema payloads.

## Documentation Change Block

```text
Canonical document content ID/path:
Capability ID:
Capability Registry reference:
Sections changed:
Change class: docs-only | contract-compatible | contract-breaking
Team-local artifact revision: <before → after | N/A>
Document revision: <before → after | N/A for repository files>
Additional related Jira items:
```

## Jira Epic Template

```markdown
# <Epic name>

## Business goal

<Goal or value to deliver>

## Success indicators

- <Success indicator or observable outcome 1>
- <Success indicator or observable outcome 2>

## High-level scope

### In scope

- <Capability group or user outcome>

### Out of scope

- <Scope not delivered by this Epic>

## Ownership and timeline

- Owner/coordinator:
- Priority: Highest | High | Medium | Low | Lowest
- Target period:
- Stakeholders:

## Links

- Confluence context/spec:
- Cross-project relevance: dependency | same capability | Frontend-only | unclear
- Paired Epic: <BB/BF key and URL | Pending with owner | N/A>
- Capability ID / Registry row / Epic Integration Hub: <exact values | Pending | N/A>
- Required initial child:
  - Type: Feature | Story | Task | Bug
  - Summary:
  - Scope:
  - Priority:
  - Assignee intent:
- GitHub tracking: Pending
```

## Jira Story Template

```markdown
# As a <user/persona>, I want <capability> so that <business value>

## Context

<Business/product user problem or need>

## Expected outcome

<Observable result when the Story is complete>

## High-level acceptance

- [ ] <User outcome 1>
- [ ] <User outcome 2>

## Scope boundary

- In scope:
- Out of scope:

## Ownership and timeline

- Parent Epic:
- Jira assignee:
- Priority:
- Sprint/target date:

## Links

- Input Confluence/Figma:
- Paired Backend Epic: <key/URL | Pending with owner | N/A>
- Backend counterpart item: <key/type/URL | Pending with owner | N/A>
- Relationship: Blocks | Relates | None
- Capability ID / Registry row / Epic Integration Hub: <exact values | Pending | N/A>
- Contract version / handoff state: <exact values | Pending | N/A>
- GitHub Issues: Pending
- Merged PRs: Pending
- Completion document: Pending
```

## Jira High-Level Task Template

```markdown
# <Outcome-oriented task title>

## Objective

<Required result; do not describe implementation>

## Context

<Why this task is required>

## Expected outcome

- <Observable outcome 1>
- <Observable outcome 2>

## Scope boundary

- In scope:
- Out of scope:

## Ownership and timeline

- Parent Epic:
- Jira assignee:
- Priority:
- Sprint/target date:

## Input links

- Confluence/Figma/reference:
- Paired Backend Epic: <key/URL | Pending with owner | N/A>
- Backend counterpart item: <key/type/URL | Pending with owner | N/A>
- Relationship: Blocks | Relates | None
- Capability ID / Registry row / Epic Integration Hub: <exact values | Pending | N/A>
- Contract version / handoff state: <exact values | Pending | N/A>
- Related Jira items:

## Delivery links

- GitHub Issues: Pending
- Merged PRs: Pending
- Completion document: Pending
```

## Jira Completion Links Block

Add this block before the Jira item moves to `Done`:

These provider-owned completion records may retain provider-owned Jira/GitHub
links. A consumer-facing cross-team handoff uses accessible Jira keys and exact
Confluence references. Consumer-facing cross-team handoff: never opposite-team private GitHub links.
Provider private delivery links stay in provider-owned records only.

```markdown
## Delivery evidence

### GitHub Issues

- <repository>#<issue> — <title> — Closed

### Merged Pull Requests

- <repository>#<PR> — <title> — <merge commit>

### Completion documentation

- Confluence: <page title and URL>
- Documentation status: Updated | N/A — <reason>

### Cross-team integration

- Epic Integration Hub: <URL | N/A>
- Final Confluence content ID/page version: <ID/version | N/A>
- Required BE → FE handoffs: ACKNOWLEDGED | N/A

### Final status

- Delivered outcome:
- Known limitations:
- Follow-up Jira/GitHub items:
```

## Epic Integration Hub Template

Create this page during planning when an outcome requires BE and FE. It is a
current-state index, not a completion document or contract copy.

```markdown
# <Epic/business outcome> — Integration Hub

## Ownership and links

- Owning Confluence space/native Epic Folder:
- Backend Capability Registry:
- Coordinator:
- Backend Epic/Folder:
- Frontend Epic/Folder:
- Frontend Index:
- Completion document: Pending

## Epic mapping

| Relationship | Source | Target | Jira link/readback |
| --- | --- | --- | --- |
| Paired Epics | <BB Epic> | <BF Epic or Pending with owner> | Relates: <result> |

## Capability Registry references

| Registry row | BE Jira item | BF Jira item(s) | Handoff state | Owners | Breaking |
| --- | --- | --- | --- | --- | --- |
| <Capability ID and Registry row URL> | <BB Feature and link> | <one or more BF links or Pending with owner> | DRAFT | <BE owner / BF owner> | No |

## Shared decisions

| Decision | Reason | Owner | Related issue/PR |
| --- | --- | --- | --- |

## Known limitations

- <limitation and linked follow-up>

## Contract changelog

| Date/time | Contract version | State change | BE record | FE acknowledgement |
| --- | --- | --- | --- | --- |
```

## BE → FE Handoff Page Template

Use this complete body for the consumer-facing Confluence page when `Frontend
impact != None`. Keep GitHub links only in team-local Issue/PR sections.

```markdown
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

For an initial create, use this separate DRAFT body:

```markdown
Handoff schema: 1
Handoff state: DRAFT
Provider Jira: {{PROVIDER_JIRA}}
Consumer Jira: {{CONSUMER_JIRA}}
Scope: {{SCOPE}}
Domain: {{DOMAIN}}
Confluence content ID: new
Confluence page version: pending
Owner account ID: {{OWNER_ACCOUNT_ID}}
Effective date: {{EFFECTIVE_DATE}}
Supersedes: {{SUPERSEDES}}
Superseded by: {{SUPERSEDED_BY}}
API impact: none
WebSocket impact: none
Missing sections: Purpose and delivered behavior, Authentication and authorization, Public data types and compatibility, State and delivery semantics, Errors and edge cases, Frontend implementation guidance, Sanitized examples and validation evidence, Known limitations and unverified items, FE acknowledgment

## Affected user flows, assumptions, and non-goals

Recipient execution remains out of scope until a later verified update.

## API impact rationale

No public API operation changes.

## WebSocket impact rationale

No public WebSocket contract changes.
```

`confluence-handoff-verify` proves read capability only and prints
`Readback: CAPABILITY_ONLY`. Unless the installed native post-tool hook has observed the
actual write and subsequent read results directly, report the handoff
unverified and do not report `READY_FOR_FE`. FE records `ACKNOWLEDGED` only for
the exact proven Confluence content ID and version. A
version change marks the old handoff `SUPERSEDED`, updates the changelog, and
notifies FE again.

Resolve every `{{TOKEN}}` from exact user or readback evidence before preflight;
never send an unresolved token. Codex, Claude and Cursor use native Confluence tool hooks.
Codex and Claude Confluence create/update require a trusted actual-body boundary,
provided by the installed native pre/post hooks; missing hooks return
`CLIENT_BODY_GATE_REQUIRED` with setup instructions; do not treat a temporary or caller-provided body
file as proof of the Atlassian request. Jira operations, Confluence moves, and
capability-only readback retain their existing governed paths. For this READY
update, use the selected client's configured Atlassian MCP `updateConfluencePage` tool with
the READY body, `{{CONTENT_ID}}`, and `{{ACTIVE_FOLDER_ID}}`. For a DRAFT
create, use `createConfluencePage` with the separate DRAFT body and the
reviewed ACTIVE Folder. The in-process native tool hook stages the actual tool-call body and runs
`confluence-handoff-write`; a standalone preflight cannot prove the Atlassian
request.

Before the read, prove connector capability:

```sh
beroka-governance preflight {{REPOSITORY}} --client {{CLIENT}} --operation confluence-handoff-verify --non-interactive --confluence-action update --target-content-id {{CONTENT_ID}} --expected-parent-id {{ACTIVE_FOLDER_ID}} --handoff-body-file {{HANDOFF_BODY_FILE}}
```

Verification is update-only; never use create/new options with `confluence-handoff-verify`.

## Confluence Completion Document Template

```markdown
# <Jira key> — <Delivered outcome>

## Metadata

| Field | Value |
| --- | --- |
| Jira | <key and URL> |
| Owners | <names> |
| Completed at | <timestamp with timezone> |
| Confluence space/native Epic Folder | <confirmed space and Folder URL/ID> |
| GitHub Issues | <links> |
| Merged PRs | <links> |
| Epic Integration Hub | <link | N/A> |
| Audience | <developers/operators/product/users> |

## Summary

<Delivered result and value>

## Delivered scope

- <Capability/behavior delivered>

## Intentionally not delivered

- <Out-of-scope or deferred item with linked task when applicable>

## Usage or operational flow

1. <Usage or operation step 1>
2. <Step 2>

## Decisions

| Decision | Reason | Trade-off | Related record |
| --- | --- | --- | --- |
| <Decision> | <Why> | <Accepted limitation> | <Issue/PR> |

## Validation evidence

- Automated checks:
- Manual/runtime checks:
- Evidence links:

## Known limitations and follow-ups

- <Limitation> — <linked Jira/GitHub item or accepted state>

## Support and ownership

- Owning team/person:
- Logs/dashboard/runbook:
- Escalation channel:

## Change history

| Date | Author | Change | Related issue/PR |
| --- | --- | --- | --- |
| <date> | <name> | Initial completion document | <links> |
```

## Update rules

- Update Jira links when Issues/PRs are created or merged.
- Create/update completion docs after implementation; never use them as daily status trackers.
- The planning-time Hub contains only current contract links, paired readiness,
  shared decisions, and contract changelog.
- Keep canonical contracts in BE; never copy their body into the Hub or FE items.
- Write pages only after confirming the native Folder and space; never guess or
  fall back to a page/space root.
- If no completion doc is needed, Jira records `Documentation: N/A — <reason>`.
- A new post-Done requirement gets a new Jira/GitHub item.

## Anti-patterns

- Copy the entire GitHub Issue into Jira.
- Put implementation detail in Jira and leave the GitHub Issue empty.
- Use Confluence to track commits or review comments.
- Move Jira to `Done` before merge or while delivery links are `Pending`.
- Create an unlinked completion document.
- Duplicate the Hub in BE and FE spaces.
- Make FE reconstruct the contract from multiple BE issue descriptions.
- Map BB/BF items by similar titles instead of Capability ID and read-back links.
- Create a page fallback when the native Epic Folder is missing.
