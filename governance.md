# Governance for Developers and AI Agents

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
- [ ] Exactly one `type:*`, at least one `area:*`, and exactly one `priority:*` label.
- [ ] Branch name.
- [ ] AI allowed actions, approval-required actions, and stop conditions.
- [ ] For executable Jira work, the assignee is the requesting developer.
- [ ] For FE work that depends on BE, the Backend Capability Registry row, Hub,
      linked BE item, and handoff state exist; dependent work is Ready only
      after `READY_FOR_FE` and the FE owner has `ACKNOWLEDGED` the exact
      contract version.

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

- The Backend repository owns the canonical machine-readable OpenAPI, JSON
  Schema, or event schema. Confluence does not copy it.
- `Backend Capability Registry` is the canonical cross-Epic mapping of one
  Capability ID to scope, domain, transport, repository
  artifact/version/commit, Confluence content ID, base Capability ID, and
  owner.
- Each cross-team Epic has exactly one `Epic Integration Hub` as the readable
  current-state index, linked from both `BB` and `BF`. It references Registry
  rows and owns only Epic-specific Jira relationships, consumers, handoff
  states, and acknowledgements.
- Each BE issue/PR contains only a short delta, contract version, test path,
  limitations, and linked FE item.
- FE consumes the artifact linked by the Registry and never reconstructs a
  contract from multiple issue descriptions.

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
- FE Issue Owner acknowledges the exact version and owns UI integration/usage
  notes without changing the BE contract definition.
- Manager/Coordinator owns Hub placement and resolves conflicting mapping or
  readiness claims.

| State | Meaning |
| --- | --- |
| `DRAFT` | Contract is under discussion and is not a finalized dependency |
| `READY_FOR_FE` | BE PR is merged, artifact is published, and a test path works |
| `ACKNOWLEDGED` | FE owner confirms receipt of the exact contract version |
| `BLOCKED` | Contract, environment, permission, or required evidence is missing |
| `SUPERSEDED` | A newer version replaces this handoff |

A BE issue may close after its outcome and required handoff are complete; it
does not wait for FE implementation. An Epic is Done only after required BE and
FE outcomes complete. A change after acknowledgement publishes a new version,
marks the previous handoff `SUPERSEDED`, and notifies FE again. Never silently
rewrite an acknowledged version.

BE work with no FE impact records `Frontend impact: None — <reason>` and needs
no handoff. Multiple FE items or Epics reuse the Registry row and exact
artifact version.

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

Confluence uses `Payload references, sanitized examples, and documented delta`.
It never copies an authoritative OpenAPI, JSON Schema, or event schema. Contract
version belongs to the exact repository artifact; document revision belongs to
the Confluence page.

Durable FE pages use `<Module> — Capability Index`, such as
`HomePage — Capability Index`, `Portfolio — Capability Index`, or
`Quote — Capability Index`. They link exact Registry rows, Backend content IDs,
and artifact versions without copying payloads. UI layout, route, component, or
page-title changes update the FE index only.

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

## Label governance

- Type: exactly one of `type:feature`, `type:bug`, `type:technical`.
- Area: at least one of `area:frontend`, `area:backend`, `area:shared`.
- Priority: exactly one of `priority:p0`, `priority:p1`, `priority:p2`, `priority:p3`.
- Exception: `status:blocked` only while genuinely blocked.

Read Jira, objective, and owned scope before labeling. If more than one mapping
is plausible, show candidate values and evidence and ask the human/manager.
Never guess or create labels that duplicate native Issue/PR states.

## Jira routing and creation clarification

- Backend work uses project `BB`, board `34`.
- Frontend work uses project `BF`, board `35`.
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
- contract version and handoff state when FE consumes a BE contract.

If a required BB record cannot be resolved, show candidates and wait for one of
four decisions: Frontend-only, pair an existing BB record, record `Pending` with
owner, or cancel. Frontend-only creates no BB link. A confirmed dependency with
a pending counterpart is `MAPPING_INCOMPLETE`: the BF item may enter the backlog
after explicit confirmation, but dependent scope is not Ready. Never create a
BB item without an explicit write request.

The same discovery applies when BB work is created after BF. Epic pairs use
`Relates`. Child dependencies use `Blocks` provider → consumer; non-blocking
same-capability children use `Relates`.

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

## Jira execution ownership and reassignment

The gate applies to the executable Story/Task/Bug/Feature, not its Epic. Resolve
the requester by Jira `accountId`, not display name. If assignee differs or is
unset, warn and wait for exact confirmation:

`I confirm ownership of <key>, reassign it to me, and continue execution.`

After confirmation, assign the requester, read back the accountId, record an
old/new assignee comment, check Definition of Ready and branch ownership, then
start implementation. Failed permission, mapping, or readback blocks execution.
Jira reassignment does not transfer a branch owned by another writer.

## GitHub repository routing

- Backend Issues/PRs: [hungnx77/Beroka_Backend](https://github.com/hungnx77/Beroka_Backend).
- Frontend Issues/PRs: the exact task-specific repository in
  [cuongngo1801-beroka](https://github.com/cuongngo1801-beroka?tab=repositories).
- The Frontend URL is only a repository list. If no exact repository is given,
  ask before creating an Issue/PR.
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
- If the Folder is missing or cannot be created, return
  `FOLDER_CREATION_REQUIRED`; never fall back to a page or space root.
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
