# Governance for Developers and AI Agents

## Governance installation boundary

The active verified release and enabled clients are user-owned. The Central repository catalog resolves routing from the canonical GitHub origin; catalog changes require an explicitly authorized governance-repository task.

`Application repository changes: NONE`

`Legacy repository metadata: PRESENT_IGNORED`

Legacy tracked governance files stay untouched and have no effect on active
release selection or routing. Repository cleanup is separate owner-authorized
work. Cursor Individual users add the printed rule once in Cursor Settings > Rules and confirm it; the CLI does not edit Cursor's internal settings.

CLI hard-enforces installation, release integrity, catalog routing, connector, authentication, and operation preflight. Technical artifacts default to English across clients; chat language does not select artifact language, and another language requires `Work-item language: <language>` for the current generation. Run a fresh operation-specific preflight immediately before each write. Agent instructions govern workflow behavior unless CI, hooks, branch protection, or platform policy provides hard enforcement.

## Roles and accountability

| Role | Primary responsibility |
| --- | --- |
| Manager/Coordinator | Prioritize Jira work, approve decomposition, resolve scope/dependency conflicts, and decide approval/merge authority |
| Issue Owner | Sole primary owner of the issue, branch, PR, validation evidence, and completion links |
| Contributor | Assist within assigned scope and hand work back to the Issue Owner |
| Reviewer | Compare the issue, diff, acceptance criteria, and validation evidence |
| Validator | Optionally perform independent verification when required |

One person may hold multiple roles. Do not create a new role when an existing
role already owns the responsibility.

## Automatic request classification

| Mode | Signal | Allowed result |
| --- | --- | --- |
| `planning-only` | Plan, decompose, or draft Jira work without code/test/commit/PR | Collect minimum input, confirm the parent Epic, and return a draft. Write to Jira only when explicitly requested. |
| `execution` | Implement, fix, test, commit, open a PR, or perform a task | Verify Jira assignee, Definition of Ready, and branch ownership before editing. |

“Plan and then implement” uses `execution`. If intent remains ambiguous, ask
exactly one question: `Do you want a plan only, or should I execute the task?`

Planning requires the outcome and work area when context cannot establish them.
Execution requires a Jira key/URL or a request to list work assigned to the
requester. Read existing fields and links; do not ask the developer to re-enter
scope, acceptance criteria, repository, or validation already recorded.

## Ownership and concurrency

- One issue has one primary owner, one branch, and one PR.
- An explicit human assignee wins. Otherwise assign the requesting developer
  when their GitHub identity is known, then the authenticated human creator.
  Never default ownership to a bot or service account; unresolved ownership
  blocks creation.
- One branch has one primary writer at a time.
- Another contributor or agent becomes writer only after explicit handoff.
- A reviewer does not edit the branch unless the owner asks; edits invalidate
  the previous review state.
- Never overwrite unclear ownership or include unrelated work in the same PR.
- Every handoff states the current commit, changed files, validation, and next
  action.

## Definition of Ready

- [ ] Primary Jira item and relevant documentation links.
- [ ] Issue type and observable objective.
- [ ] In scope, out of scope, and behavior that must remain unchanged.
- [ ] One primary owner.
- [ ] Dependencies and expected inputs/outputs.
- [ ] Pass/fail acceptance criteria.
- [ ] Appropriate automated and manual validation plan.
- [ ] Native Issue Type for an organization repository, or exactly one
      configured `type:*` fallback for a personal repository.
- [ ] At least one `area:*` and exactly one `priority:*` label.
- [ ] Branch name.
- [ ] AI allowed actions, approval-required actions, and stop conditions.
- [ ] For executable Jira work, the assignee is the requesting developer.
- [ ] For FE work that depends on BE, the Backend Capability Registry row, Hub,
      linked BE item, and handoff state exist; dependent work is Ready only
      after `READY_FOR_FE` and the FE owner has `ACKNOWLEDGED` the exact
      Confluence content ID and page version.

If a required item is missing, the issue is not Ready. Ask the responsible
owner instead of inventing an assumption that changes scope or priority.

## Definition of Done

- [ ] Acceptance criteria pass.
- [ ] Author self-review is complete.
- [ ] Exact validation commands/results are recorded in the PR.
- [ ] Unverified items and residual risks are declared.
- [ ] Blocking feedback is resolved or explicitly accepted.
- [ ] PR links Jira, uses `Closes #<issue>`, and has correct labels.
- [ ] Approval and merge follow the authority for that PR.
- [ ] PR is merged and the branch is deleted.
- [ ] Confluence is updated or Jira says `Documentation: N/A — <reason>`.
- [ ] When `Frontend impact != None`, the contract is published, its Registry
      row and referencing Hubs are updated, and the linked FE item has received
      the handoff.

## BE → FE contract and documentation handoff

Use a hybrid model:

- The Backend repository owns team-local canonical machine-readable OpenAPI,
  JSON Schema, or event-schema artifacts. A consumer-facing cross-team handoff
  is instead a self-contained Confluence page with the complete public contract.
- `Backend Capability Registry` is the canonical cross-Epic mapping of one
  Capability ID to scope, domain, transport, Confluence content ID/version,
  base Capability ID, and owner. Team-local artifact details stay in the
  owning repository.
- Each cross-team Epic has exactly one `Epic Integration Hub` as the readable
  current-state index, linked from both `BB` and `BF`. It references Registry
  rows and owns only Epic-specific Jira relationships, consumers, handoff
  states, and acknowledgements.
- Each BE issue/PR contains only a short delta, Confluence content ID/page
  version, test path,
  limitations, and linked FE item.
- FE consumes the self-contained Confluence page by exact content ID and
  version; it never needs an opposite-team GitHub repository or reconstructs a
  contract from issue descriptions.

BB and BF use separate project-local Epics linked with `Relates`; never use a
shared implementation item or cross-project parent. Exactly one semantic capability, one transport, one Registry row, and one canonical Confluence
page own each immutable Capability ID. A Backend Feature may `Blocks` one or
more BF items. One Registry capability may be referenced by several Epics and
FE modules. Title similarity is not mapping evidence.

Discovery is symmetric: BF creation scans BB and BB creation scans BF.
Candidates require developer confirmation and never create links automatically.
Pure Frontend work writes nothing to BB and may record
`Backend dependency: None — <reason>` on the BF item.

Return `PASS` only after parents, `Relates`/`Blocks`, Capability ID, Registry
row, and Hub references read back correctly. A missing counterpart with a
named owner is `MAPPING_INCOMPLETE`. Duplicate Registry rows, one ID assigned
to different capabilities, or conflicting Jira/content links are
`MAPPING_CONFLICT` and block only the dependent scope.

Ownership:

- BE Issue Owner publishes the contract, updates the Registry row and
  referencing Hub changelogs, and sends the handoff.
- FE Issue Owner acknowledges the exact Confluence content ID/page version and
  owns UI integration/usage notes without changing the BE contract definition.
- Manager/Coordinator owns Hub placement and resolves conflicting mapping or
  readiness claims.

| State | Meaning |
| --- | --- |
| `DRAFT` | Contract is under discussion and is not a finalized dependency |
| `READY_FOR_FE` | The self-contained page passes post-write readback and a test path works |
| `ACKNOWLEDGED` | FE owner confirms the exact Confluence content ID/page version |
| `BLOCKED` | Contract, environment, permission, or required evidence is missing |
| `SUPERSEDED` | A newer version replaces this handoff |

For every cross-team handoff, pair provider and consumer Jira keys with the
Confluence content ID and version; use `GitHub: N/A` in consumer-facing Jira
text. The handoff page includes complete API/WS sections when affected,
declared omissions, owner, effective date, supersession metadata, and the FE
acknowledgment path. Create only `DRAFT`; report `READY_FOR_FE` only after the
exact page, parent, space, title, owner, and version read back successfully.

A BE issue may close after its outcome and required handoff are complete; it
does not wait for FE implementation. An Epic is Done only after required BE and
FE outcomes complete. A change after acknowledgement publishes a new version,
marks the previous handoff `SUPERSEDED`, and notifies FE again. Never silently
rewrite an acknowledged version.

BE work with no FE impact records `Frontend impact: None — <reason>` and needs
no handoff. Multiple FE items or Epics reuse the Registry row and exact
Confluence content ID/page version.

## Canonical capability documentation

Backend capability documentation follows one reviewed hierarchy under
`Backend Contracts`:

```text
Backend Capability Registry
Shared — Conventions
Shared — Market — API
Shared — Market — WebSocket
Shared — User — API
Shared — User — WebSocket
Derivatives — Market — API
Derivatives — Market — WebSocket
Derivatives — User — API
Derivatives — User — WebSocket
Underlying — Market — API
Underlying — Market — WebSocket
Underlying — User — API
Underlying — User — WebSocket
```

Native Folder titles are globally unique. A capability-group Folder uses
`<Scope> — <Domain> — <Capability group> — <Transport>`, including
`Shared — Market — Market Indices — API` and
`Shared — Market — Market Indices — WebSocket`. Never create generic repeated
Folders such as `Market`, `User`, `API`, or `WebSocket`.

One capability page owns one Capability ID. Market Indices is only a navigation
group; its pages use distinct IDs such as `MARKET-INDEX-SNAPSHOT`,
`MARKET-INDEX-HISTORY`, and `MARKET-INDEX-STREAM`. WebSocket pages distinguish
`Client → Server Commands` from `Server → Client Events`.

Confluence uses `Payload references, sanitized examples, and documented delta`
within complete public contract sections. Team-local authoritative artifacts
retain their own version; the consumer-facing handoff page has its own
Confluence content ID and version.

Durable FE pages use `<Module> — Capability Index`, such as
`HomePage — Capability Index`, `Portfolio — Capability Index`, or
`Quote — Capability Index`. They link exact Registry rows and Confluence
content IDs/page versions without copying payloads. UI layout, route,
component, or page-title changes update the FE index only.

## Review, approval, and merge authority

- Humans and AI may review every change category.
- Independent review is not mandatory by category in the initial phase.
- Authors may self-review and state `Self-review completed — ready to merge`.
- GitHub does not allow a PR author to use native Approve on their own PR.
- AI must not approve or merge without explicit human confirmation for the
  exact PR and reviewed commit SHA.
- A new commit invalidates the previous confirmation.

| Action | Human | AI agent |
| --- | --- | --- |
| Create/update issues and labels | Allowed | Allowed in scope; Jira reassignment uses the confirmation gate |
| Implement and commit | Allowed in owned scope | Allowed in assigned scope |
| Review and comment | Allowed | Allowed for every change type |
| Record self-review | Allowed | Allowed |
| Approve PR | Per team/repository settings | Only after explicit human confirmation |
| Merge PR | Per team/repository settings | Only after explicit human confirmation |
| Destructive/production action | Requires proper authority | Only with explicit human target/action authority |

Human authorization must name PR, full reviewed SHA, agent, allowed action,
merge method, conditions, authorizer, and timestamp. Otherwise AI may only
review/comment.

## Issue classification governance

- Organization repository type: native Issue Type `Feature`, `Bug`, or `Task`;
  do not duplicate it with a `type:*` label.
- Personal repository type: exactly one configured fallback label:
  `type:feature`, `type:bug`, or `type:technical`.
- Area: at least one of `area:frontend`, `area:backend`, `area:shared`.
- Priority: exactly one of `priority:p0`, `priority:p1`, `priority:p2`, `priority:p3`.
- Exception: `status:blocked` only while genuinely blocked.

Read repository ownership, Jira, objective, and owned scope before
classification. If required fallback labels are missing, return
`LABEL_CONFIGURATION_REQUIRED`; never create them silently. If more than one
mapping is plausible, show candidate values and evidence and ask the
human/manager. Read back owner, type, area, priority, and Jira linkage before
reporting success.

## Jira routing and creation clarification

- Backend work uses project `BB`, board `34`.
- Frontend work uses project `BF`, board `35`.
- Jira summaries use English sentence case, no trailing punctuation, and no
  Jira key or issue-type prefix:
  - Epic: `<Domain or module> — <Business outcome>`
  - Feature: `<Capability> — <Observable outcome>`
  - Task: `<Action verb> <Outcome or deliverable>`
  - Bug: `<Actual symptom> when <condition>`
- Follow [Jira and Confluence Templates](templates/jira-confluence.md).
- Validate work area, issue type, and parent Epic before creating a child.
- An active Epic belongs to the correct project, is not archived, and has
  `statusCategory != Done`.
- Base query:
  `project = <BB|BF> AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`.
- Rank candidates by exact key, exact normalized summary, component/label, and
  summary/description keywords. Never use fuzzy matching to select a parent.
- If the Epic is missing, invalid, inactive, or ambiguous, list active
  candidates with key, summary, status, owner, URL, and relevance; wait for the
  developer. Never create an orphan or duplicate across projects.
- Before creating a new Epic, show similar active Epics and require one initial
  `Feature`, `Story`, `Task`, or `Bug`. Never parent a `Subtask` directly under
  an Epic.
- A truly unrelated one-off or hotfix may be standalone only after explicit
  developer confirmation. Record `Parent Epic: N/A`, the standalone reason,
  reviewed active Epic candidates, owner, priority, and GitHub issue.
- A valid active key or one exact unique summary does not need redundant
  confirmation.
- If Jira cannot be read, report access failure; never invent an Epic list from
  memory or chat.
- Before Jira creation, resolve exact project create metadata and search for the
  intended existing record. Create once, then read back the returned key and
  validate project, issue type, summary, and required linkage.
- If create status is indeterminate, return `CREATION_STATUS_UNKNOWN`; never retry automatically
  or create a second record.
- Confluence creation uses exact trusted space/root routing and reads back the
  created content and parent. Folder routing remains blocked without isolated
  pilot evidence.

## Cross-project counterpart discovery

Same-project parent validation always happens before counterpart discovery.

### New Frontend Epic

1. Search active BF Epics for same-project duplicates.
2. Search active BB Epics using exact links/keys, normalized summary, shared
   component/label, contract/API/data dependency, or an existing Hub record.
3. Show candidates and wait for `pair existing`, `Frontend-only`, or `cancel`.
4. If paired, ask whether to align the base name, link Epics with `Relates`,
   and resolve the exact Capability ID/Registry row plus Hub reference.
5. Require an initial child whether paired or Frontend-only.

Similar names create candidates only. They never authorize rename, `Relates`,
Capability ID, or Hub updates.

### New Frontend child in an existing Epic

When the child has a BE dependency or its BF Epic is paired, require:

- BF parent and paired BB Epic;
- exact BB Feature/Story/Task/Bug counterpart when it exists;
- dependency direction and `Blocks` or `Relates` link type;
- immutable Capability ID, Registry row, and Hub reference;
- Confluence content ID/page version and handoff state when FE consumes a BE contract.

If a required BB record cannot be resolved, show candidates and wait for one of
four decisions: Frontend-only, pair an existing BB record, record `Pending` with
owner, or cancel. Frontend-only creates no BB link. A confirmed dependency with
a pending counterpart is `MAPPING_INCOMPLETE`: the BF item may enter the backlog
after explicit confirmation, but dependent scope is not Ready. Never create a
BB item without an explicit write request.

The same discovery applies when BB work is created after BF. Epic pairs use
`Relates`. Child dependencies use `Blocks` provider → consumer; non-blocking
same-capability children use `Relates`.

## Cross-team Jira intake

Frontend → Backend and Backend → Frontend use the same constrained lifecycle.
The requester runs a fresh `jira-intake-write` preflight from their own exact
repository. Only the receiving profile and Jira project returned by preflight
may receive the intake; governance does not disclose the opposite private
repository identity. Ordinary `jira-write`, repository role checks, and
`cross-repo-write` remain unchanged.

The requester/reporter creates only the intake record. Leave Sprint and the
receiving-project parent unset. An exact receiving-team account may be assigned
only after that accountId is confirmed by the user or receiving team; otherwise
leave it unset and return `ASSIGNEE_CONFIRMATION_REQUIRED`. The receiving team
exclusively owns duplicate resolution, issue type, active Epic,
acceptance/rejection, final priority, Sprint, readiness, executor/assignee, and
GitHub delivery.

Assignment alone does not authorize a GitHub Issue. The receiving-team agent
creates exactly one Issue in its repository only after
`Accepted + Ready + Assigned + Definition of Ready PASS` and an idempotency
search proves there is no existing primary GitHub Issue. Read back its executor
and primary Jira link.

Before intake creation, resolve Jira create metadata and verify a supported
intake state or equivalent field. Otherwise return
`INTAKE_CONFIGURATION_REQUIRED` with configuration remediation. The lifecycle
is agent-driven; there is no event listener.

Task, Bug, and Feature intake is symmetric. Opposite-project Epic creation
requires receiving-team confirmation. FE owns BF updates and BE owns BB
updates. Cross-team Jira or handoff text containing opposite-team private
GitHub links returns `CROSS_TEAM_LINK_SCOPE_DENIED`; use the exact accessible
Confluence page instead.

Ordinary Confluence create, update, and move use `confluence-write`; they do
not publish cross-team readiness. Every cross-team handoff uses the dedicated
`confluence-handoff-write` preflight with its exact body and reviewed ACTIVE
Folder, then a fresh `confluence-handoff-verify` preflight with the exact body.
That second preflight proves read capability only, never a completed write/read;
without trusted post-tool evidence, report the handoff unverified and do not
report `READY_FOR_FE`. Consumer-facing content uses the provider/consumer Jira pair
and Confluence content ID/version only—never a GitHub, repository, branch, or
commit reference. An `UNACTIVATED` content ID or parent returns
`DOCS_UNACTIVATED` and can change only through a reviewed governance release
PR. A transport mismatch on a reviewed drifted row returns `MAPPING_CONFLICT`,
and the agent asks the user and waits. Hierarchy bootstrap remains optional
guidance, not a write gate.

Provider status remains `To Do -> In Progress` when the receiving assignee
starts accepted, ready work and `In Progress -> In Review` when a human marks
the provider PR ready for review. `Closes #<issue>` normally closes the GitHub Issue.
If it remains open, an agent may close it only after exact merge/link readback proves the delivered commit
and the close write is authorized;
otherwise report the issue as blocked. After `Closes #<issue>` automatically closes the current primary GitHub Issue,
or after an agent completes an
authorized manual close under this gate, resolve the exact linked Jira item,
verify the authenticated account against the current assignee, run a fresh
`jira-write` preflight, and transition the item to `In Review`; an item already in `In Review` is idempotently complete.
Then resolve related documentation
only by exact Confluence content ID. If the page, parent, or required change is
missing or ambiguous, ask the user and wait. Otherwise run a fresh target-bound
Confluence preflight, update the documentation, and read it back. After
documentation readback Jira remains in `In Review`; do not move it to `Done`
automatically. After successful documentation readback, report the GitHub, Jira, and Confluence outcomes separately.
Report a blocked Jira or Confluence step separately and do not reopen the GitHub Issue.
The provider updates only its own project item; the consumer reviews through the
exact Confluence handoff and updates its own item.

## Jira post-create readback and backlog verification

Creation completes only after the agent:

1. reads the item by key and verifies project, type, status, parent, and assignee;
2. verifies the correct board base filter, enabled backlog, and status mapping;
3. verifies unsprinted Story/Task/Bug/Feature items are in unranked Backlog;
4. creates the initial child from the read-back Epic key with Sprint unset unless requested;
5. returns `PASS` only when the child parent and backlog membership read back correctly.

Do not set Sprint unless requested. Use board/backlog APIs or the base filter,
not a personal quick filter. If child creation fails after Epic creation, return
`EPIC_CREATED_CHILD_FAILED` and reuse the Epic. If an item exists but is hidden,
return `CREATED_BUT_NOT_VISIBLE`; never create a duplicate or change board
settings without authority.

## Receiving-team executor ownership

The gate applies to the executable Story/Task/Bug/Feature, not its Epic. Resolve
the requester/reporter and executor/assignee separately by Jira `accountId`, not
display name. If assignee differs from the confirmed executor or is unset, warn
and wait for exact receiving-team confirmation:

`I confirm <executor accountId> owns <key>; assign it and continue execution.`

After confirmation, assign only that executor, read back the accountId, record
an old/new assignee comment, check Definition of Ready and branch ownership,
then start implementation. The requester may be the executor for same-team work,
but cross-team intake stays with its receiving-team executor. Failed permission,
mapping, or readback blocks execution. Jira reassignment does not transfer a
branch owned by another writer.

## GitHub repository routing

- Backend Issues/PRs:
  [beroka-vn/Beroka_Backend](https://github.com/beroka-vn/Beroka_Backend).
- Frontend Issues/PRs:
  [beroka-vn/Beroka_Frontend](https://github.com/beroka-vn/Beroka_Frontend).
- Bootstrap derives the stored `FE`, `BE`, or `FULL_STACK` role from exact
  `beroka-vn` GitHub Team membership. A routed profile outside that role
  returns `ROLE_SCOPE_DENIED`; eligible preflights revalidate membership.
  `FULL_STACK` may use the exact Backend+Frontend Cursor multi-root pair;
  governed writes name one BB/BF project, parent/epic key, or repository
  target. Workspace folder path substrings alone do not force `TARGET_REQUIRED`.
- Unrelated repositories are outside this boundary and require an exact
  catalog record; never infer one from the current workspace.
- Shared work uses one confirmed primary tracking repository; never duplicate
  the same issue across repositories.

## Documentation routing and clarification

- Frontend documentation: [Beroka-frontend](https://beroka.atlassian.net/wiki/spaces/Berokafron).
- Backend documentation: [Beroka-backend](https://beroka.atlassian.net/wiki/spaces/Berokaback/overview).
- Durable canonical capability pages live under the globally unique Backend
  hierarchy and Registry, not inside an Epic Folder.
- Each Jira Epic has one native Folder named `<Epic key> — <Epic summary>` for
  Epic-specific planning, decisions, completion pages, and its Integration Hub.
- The Hub references Registry rows. Durable FE module Capability Indexes link
  exact Registry rows and Backend content IDs; never copy the BE contract.
- Create no empty subpages.
- Prefer creating Epic Folders when hierarchy guidance calls for them; do not
  treat a missing preferred Folder as a hard deny for ordinary page writes.
  Release-hardcoded `UNACTIVATED` targets return `DOCS_UNACTIVATED` instead.
- A page passes only when readback shows the correct `parentId` and
  `parentType = Folder`; otherwise return `DOC_HIERARCHY_FAILED`.
- If FE cannot open the owning BE Folder/Hub, return
  `CROSS_SPACE_ACCESS_REQUIRED`; never duplicate the Hub to bypass permissions.
- Missing or ambiguous Registry, scope, domain, transport, parent, Capability
  ID, or content ID returns `ROUTING_REQUIRED`; never guess by title.
- Ask the developer whenever service, scope, ownership, labels, dependency, or
  location is ambiguous.

## AI agent operating principles

- Read the issue, repository rules, and linked docs before editing.
- Work only in the assigned repository, branch, and file scope.
- Do not invent requirements, dependencies, services, or abstractions.
- Do not edit the default branch unless explicitly allowed.
- Never overwrite unclear human/agent ownership.
- Never expose secrets in source, prompts, commands, logs, screenshots, or PRs.
- Do not run destructive or production actions without explicit authority.
- Validate before claiming completion; never report `Not run` or failure as pass.
- When blocked, report evidence and the required decision.
- Do not approve or merge without human confirmation for the exact PR/SHA.

## Stop conditions

Stop the dependent scope for conflicting objective/ownership/contracts/criteria,
overlapping writers, missing permissions, unconfirmed destructive/production
targets, unavailable dependencies/environments, missing FE handoff evidence,
`MAPPING_CONFLICT`, unconfirmed counterpart candidates, missing Folder/Hub
access, missing Registry identity, ambiguous labels/project/type/parent/
repository/location, failed Jira readback/backlog membership, an empty Epic,
assignee mismatch without confirmation, failed reassignment, or repeated tests
whose root cause is unknown. Independent in-scope work may continue.

## Standard reports

Use the exact Blocked, Implementation Handoff, Review Handoff, authorization,
counterpart, creation verification, and folder hierarchy blocks from
[AI Agent Assignment Templates](templates/ai-agent-assignment.md).

## Conflict and escalation

- Scope conflict: Manager/Coordinator decides ownership before coding resumes.
- Technical disagreement: record options, evidence, and trade-offs; the Issue
  Owner or Manager decides under published authority.
- Priority conflict: Manager decides Jira priority; synchronize GitHub labels.
- Review conflict: keep the PR unmerged until the decision owner accepts risk or
  requests a change.
- New requirement: create a linked issue unless it is required for the current
  acceptance criteria.
