# Jira, GitHub, and Confluence Operating Workflow

## Governance installation boundary

The Central repository catalog supplies exact routing for the user-owned active release. Catalog changes require an explicitly authorized governance-repository task; application repositories do not configure governance releases.

`Application repository changes: NONE`

`Legacy repository metadata: PRESENT_IGNORED`

Legacy tracked governance files remain ignored until repository owners request
separate cleanup. Cursor Individual uses a one-time User Rule confirmation in
Cursor Settings > Rules. CLI hard-enforces installation, release integrity,
catalog routing, connector, authentication, and operation preflight. Technical artifacts default to English across clients; chat language does not select artifact language, and another language requires `Work-item language:
<language>` for the current generation. Run a fresh operation-specific
preflight immediately before each write. Agent instructions govern workflow behavior unless CI, hooks, branch protection, or platform policy provides hard enforcement.

## 1. System responsibilities

| System | Must contain | Must not replace |
| --- | --- | --- |
| Jira | Outcome, context, priority, coordination owner, timeline, status, links | Implementation detail or commit tracking |
| GitHub Issue | Technical contract sufficient to start implementation | Long-lived operational documentation |
| Branch/commit | Changes for exactly one issue | Unrelated work |
| Pull Request | Diff, review, validation, approval, and merge evidence | The Issue or Confluence |
| Confluence | Delivered behavior, decisions, guides, and limitations | Daily status tracking |
| Backend Capability Registry | Cross-Epic Capability ID, canonical content, artifact/version, and owner | Epic-specific handoff state |

## 2. Standard lifecycle

### Integration preflight

Follow [Integration Handbook](handbook.md) before reading or writing GitHub,
Jira, or Confluence. Required providers must return `PASS`. On missing tools,
authentication, account, or permission, return `INTEGRATION_BLOCKED` and stop
only the dependent scope. Never create a live record solely to test a connector.

### Step 0 — Select planning or execution mode

| Mode | Request | Required preflight |
| --- | --- | --- |
| `planning-only` | Plan, decompose, or draft Jira work | Outcome, unknown work area, active Epic confirmation |
| `execution` | Implement, fix, test, commit, or open a PR | Exact Jira item, requester/assignee match, Definition of Ready, branch ownership |

“Plan and then implement” uses `execution`. If intent is still ambiguous, ask
one question. Do not request information already present in linked records.

### Step 1 — Create high-level Jira work

- Backend uses project `BB`, board `34`; Frontend uses project `BF`, board `35`.
- Apply the Jira summary contract before duplicate search or creation:
  - Epic: `<Domain or module> — <Business outcome>`
  - Feature: `<Capability> — <Observable outcome>`
  - Task: `<Action verb> <Outcome or deliverable>`
  - Bug: `<Actual symptom> when <condition>`
- Use English sentence case, no trailing punctuation, and no Jira key or
  issue-type prefix.
- Follow [Jira and Confluence Templates](templates/jira-confluence.md).
- Validate the parent active Epic before creating Story/Task/Bug/Feature.
- If the Epic is missing, invalid, inactive, or ambiguous, list relevant active
  Epics with key, summary, status, owner, URL, and evidence; wait for selection.
- Before a new Epic, show same-project duplicate candidates and require at least
  one initial `Feature`, `Story`, `Task`, or `Bug`. Never create a direct
  `Subtask` under an Epic.
- A truly unrelated one-off or hotfix may be standalone only after explicit
  confirmation. Record `Parent Epic: N/A`, the standalone reason, reviewed
  Epic candidates, owner, priority, and GitHub issue.
- For a new BF Epic, scan active BB Epics after the BF duplicate check. For a
  new BB Epic, scan BF the same way. Candidates require developer confirmation;
  fuzzy titles never authorize rename or links.
- Frontend-only work creates no BB link or record. A confirmed pair may align
  its base name, link Epics with `Relates`, and resolve one Capability
  ID/Registry row plus Hub reference.
- A BF child with BE dependency must resolve its paired BB Epic, exact BB work
  item, link type, Capability ID, Registry row, Hub reference, and
  contract/handoff state. Show candidates and ask when any mapping is
  unresolved.
- Shared work uses one confirmed primary project/parent; never create the same
  item in both projects automatically.
- Planning-only returns a draft unless an external write is explicitly requested.

After creation, read back key, project, type, status, parent, and assignee, then
verify the correct board base filter and backlog visibility. An unsprinted child
must appear in unranked Backlog.

Epic creation is one bundle: read back the Epic, create the initial child with
that exact parent, leave Sprint unset unless requested, and verify backlog UI.
Return `EPIC_CREATED_CHILD_FAILED` if the child fails and reuse the Epic. Return
`CREATED_BUT_NOT_VISIBLE` if visibility cannot be verified; never duplicate the
item or edit board settings automatically.

Cross-project mapping is a separate result. Pure FE returns
`NO_BACKEND_DEPENDENCY`. A confirmed dependency with no counterpart may enter
the BF backlog after explicit confirmation as `Pending` with owner, but returns
`MAPPING_INCOMPLETE` and is not Ready for dependent execution.

#### Cross-team Jira intake

Frontend → Backend and Backend → Frontend requesters use
`jira-intake-write` from their own routed repository. Create only in the exact
opposite-team project returned by preflight. The requester/reporter leaves
Sprint and parent unset; an exact receiving-team account may be assigned only
after its Atlassian `accountId` is confirmed by the user or receiving team.
Otherwise leave assignee unset and return `ASSIGNEE_CONFIRMATION_REQUIRED`.
Requested priority is not a receiving-team commitment.

The receiving team owns duplicate checks, issue type, active Epic,
accept/reject, final priority, Sprint, readiness, executor assignment, and
technical delivery. Assignment alone does not authorize a GitHub Issue. Create
one receiving-repository Issue only after
`Accepted + Ready + Assigned + Definition of Ready PASS` and no existing
primary GitHub Issue is found.

Return `INTAKE_CONFIGURATION_REQUIRED` if create metadata cannot prove a
supported intake state or equivalent field. Intake is agent-driven; there is no
event listener. Task, Bug, and Feature intake is symmetric; opposite-project
Epic creation requires receiving-team confirmation. FE owns BF updates and BE
owns BB updates. Opposite-team private GitHub links in cross-team Jira or
handoff text return `CROSS_TEAM_LINK_SCOPE_DENIED`; use the exact accessible
Confluence page. Keep separate BB/BF items, same-project parents, `Blocks`
provider → consumer, and `Relates` for non-blocking same-capability work.

### Step 2 — Decompose into GitHub Issues

- Backend:
  [beroka-vn/Beroka_Backend](https://github.com/beroka-vn/Beroka_Backend).
- Frontend:
  [beroka-vn/Beroka_Frontend](https://github.com/beroka-vn/Beroka_Frontend).
- Use only the routed profiles allowed by the stored GitHub Team-verified role;
  eligible preflights revalidate membership before writes.
- Unrelated repositories require an exact catalog record.
- Shared work uses one confirmed primary tracking repository.

Use [GitHub Issue Templates](templates/github-issue.md). Every issue links one
primary Jira item; states objective, scope, unchanged behavior, dependencies,
acceptance criteria, validation, owner, labels, AI authority, and stop
conditions. Keep independently deployable FE and BE work in separate issues.
An explicit assignee wins; otherwise use the requesting developer, then the
authenticated human creator. Unresolved human ownership blocks creation.

For an outcome requiring both teams:

1. scan the other project regardless of which side exists first and obtain
   developer confirmation;
2. create/reuse separate BB and BF Epics and link them with `Relates`;
3. resolve one immutable Capability ID in one canonical Registry row;
4. create separate Jira/GitHub items; a BE provider may `Blocks` BF consumers;
5. link each Epic Hub to the Registry row and record its BE/BF items, state,
   consumers, and acknowledgements;
6. read back parents, links, Capability ID, Registry row, and Hub references
   before `PASS`.

Pure FE skips mapping. A missing approved counterpart is `MAPPING_INCOMPLETE`.
Duplicate Registry rows, one ID assigned to different capabilities, or
conflicting links are `MAPPING_CONFLICT` and block the dependent scope. Never
use a shared GitHub Issue or duplicate Hub to bypass cross-project handoff.

### Step 3 — Apply classification and Definition of Ready

- Organization repositories use native Issue Type `Feature`, `Bug`, or `Task`
  without a duplicate `type:*` label.
- Personal repositories use exactly one configured fallback:
  `type:feature`, `type:bug`, or `type:technical`.
- At least one `area:frontend`, `area:backend`, or `area:shared`.
- Exactly one `priority:p0`, `priority:p1`, `priority:p2`, or `priority:p3`.
- `status:blocked` only while actually blocked.

Apply classification only when evidence has one clear mapping. Missing
fallback labels return `LABEL_CONFIGURATION_REQUIRED`; do not create them
silently. Ask when scope, priority, or type is ambiguous. Read back owner,
type, area, priority, and Jira link, then check
[Definition of Ready](governance.md#definition-of-ready). FE dependent scope is
Ready only after `READY_FOR_FE`, an exact contract version, and FE
`ACKNOWLEDGED`. Independent FE scope may continue.

### Step 4 — Create the branch and implement

#### Receiving-team executor ownership

Before editing for a Story/Task/Bug/Feature:

The requester/reporter may differ from executor/assignee. Resolve both by Jira
`accountId`; the current assignee owns execution only after the receiving team
confirms that account.

1. resolve the requester/reporter and executor/assignee separately by Jira
   `accountId`;
2. read the current assignee and confirm that person owns the technical GitHub
   work;
3. if mismatched or unassigned, return `ASSIGNEE_CONFIRMATION_REQUIRED`, show a
   warning, and wait for exact receiving-team confirmation;
4. assign only the confirmed executor and read back;
5. verify Definition of Ready and GitHub writer ownership.

Failure to reassign/read back blocks implementation. Do not reassign the parent
Epic, assign cross-team work back to its requester, or transfer an active branch
implicitly.

Branch format: `<type>/<issue-number>-<short-slug>`, where type is `feature`,
`fix`, `hotfix`, `docs`, `refactor`, `test`, `chore`, or `ci`.

Commit format: `<type>(<scope>): <imperative subject>`.

### Step 5 — Open a Pull Request

Open a Draft PR early when discussion helps. Mark Ready only when acceptance
criteria, self-review, validation results, and unverified items are recorded.
The PR links Jira, uses `Closes #<issue>`, and copies Issue labels. If Frontend
impact is not None, include a DRAFT handoff block, contract path/version, linked
FE item, and Hub. Use [Pull Request Template](templates/pull-request.md).

### Step 6 — Review and approval

Humans and AI may review every change category against issue scope, criteria,
diff, and evidence. Resolve or explicitly accept blocking findings. AI must not
approve or merge without human confirmation for the exact PR and SHA. See
[review authority](governance.md#review-approval-and-merge-authority).

### Step 7 — Merge, publish handoff, and close

Prefer squash merge. For BE changes with FE impact, publish the contract after
merge, update the Registry row, update every referencing Hub changelog to
`READY_FOR_FE`, and comment on the linked FE item with the exact version. FE
records `ACKNOWLEDGED` before dependent work.

After merge:

1. confirm `Closes #<issue>` closed the Issue;
2. confirm required handoff or `Frontend impact: None`;
3. delete the task branch;
4. add merged PR/handoff links to Jira;
5. create completion documentation.

### Step 8 — Update Confluence and Jira

Use [Jira and Confluence Templates](templates/jira-confluence.md). Store
Frontend docs in Beroka-frontend and Backend docs in Beroka-backend. Shared
work uses one confirmed owning space and never duplicates documentation.

Durable Backend capability pages use the reviewed globally unique hierarchy:
`<Scope> — <Domain> — <Transport>`, with an optional capability group before
transport. Never create generic repeated `Market`, `User`, `API`, or
`WebSocket` Folders. Market Indices uses
`Shared — Market — Market Indices — API` and
`Shared — Market — Market Indices — WebSocket`.

Every Jira Epic still owns one native Folder named
`<Epic key> — <Epic summary>` for Epic-specific pages and its Hub. The Hub
references exact Registry rows. Durable Frontend pages use
`<Module> — Capability Index` and link exact Backend content IDs and artifact
versions without copying payloads. Create pages only when content and an owner
exist.

Prefer creating Epic Folders when hierarchy guidance calls for them; ordinary
page writes remain allow-by-default unless the target is `UNACTIVATED` in the
governance release (`DOCS_UNACTIVATED`). After write/move, verify `parentId` and
`parentType = Folder`, otherwise return `DOC_HIERARCHY_FAILED`. If FE cannot
open the BE Hub, return `CROSS_SPACE_ACCESS_REQUIRED`. Before every Confluence
create or update, include handoff delta markers (`Jira:`, `GitHub:`, and a
`## Handoff —` section or `Handoff form: child-page` with `Canonical:`). Run
`confluence-write` or
`confluence-handoff-verify`; a transport mismatch on a reviewed drifted row
returns `MAPPING_CONFLICT`.

Maintain provider status as `To Do -> In Progress` when accepted work starts,
`In Progress -> In Review` when a human marks the provider PR ready for review,
and `In Review -> Done` only after merge and exact Confluence delivery/readback.
The provider updates only its own project item; the consumer reviews the exact
Confluence handoff and updates its own item.
For every Jira status update, the agent reads available Jira transitions first,
performs only an allowed transition, and reads back the new Jira status. An
absent transition or status mismatch returns a failure and blocks dependent
work.
`Closes #<issue>` normally closes the GitHub Issue. If it remains open, an agent
may close it only after exact merge/link readback proves the delivered commit
and the close write is authorized; otherwise report the issue as blocked.

Before Jira Done, link all Issues, merged PRs, and completion docs, or record
`Documentation: N/A — <reason>`.

## 3. Traceability requirements

| Record | Must link to |
| --- | --- |
| Jira item | GitHub Issues, merged PRs, completion document |
| GitHub Issue | Primary Jira item and relevant inputs |
| Branch | GitHub Issue number in the branch name |
| Pull Request | Jira, `Closes #<issue>`, Hub/handoff when needed, related docs |
| Backend Capability Registry | Capability ID, canonical content ID, artifact/version/commit, scope/domain/transport, owner |
| Epic Integration Hub | Registry rows, paired items, Epic Folders, states, consumers, PRs |
| Frontend Capability Index | Registry rows, Backend content IDs, artifact versions, FE usage/owner |
| Completion page | Jira, Issues, PRs, Hub, owning Folder |

Use `Pending` with an owner only while a link does not exist. No placeholder may
remain when the record reaches Done/Merged.

## 4. Exceptions

- **Blocked:** add `status:blocked` and use the Blocked Report. Remove it only
  after resolution or approved rescope.
- **Scope change:** stop out-of-scope work, update issue/criteria/validation,
  and obtain owner confirmation.
- **Validation failure:** keep the PR Draft and record the exact failure; fix
  root cause rather than rewriting evidence.
- **Multiple PRs:** split independently reviewable outcomes into separate issues.
- **Old acceptance failure:** reopen the old issue; create a linked issue only
  for a new requirement.
- **Unavailable dependency:** do not accept dependent execution; record owner
  and expected input. Independent scope may be split out.

## 5. Initial-phase validation

Every PR records exact commands, results, environment, focused checks, secret
scan, affected entrypoint/smoke path, and `Not run` reasons.

- Frontend: before/after evidence, viewport/browser, loading/empty/error/
  permission states, and keyboard/accessibility basics.
- Backend: relevant unit/integration/smoke checks, contract compatibility,
  database/data/rollback impact, and sanitized request/response evidence.

## 6. Quick checklists

### When accepting work

- [ ] Correct BB/BF project, issue type, active parent, and hierarchy.
- [ ] Ambiguous Epic was selected from an evidence-backed active list.
- [ ] New Epic has a read-back initial child and no direct Subtask.
- [ ] Backlog visibility/readback passed or the exact failure is reported.
- [ ] Counterpart discovery ran when relevant and every link was confirmed.
- [ ] Pure FE created no BB link; unclear dependency was escalated.
- [ ] Receiving-team executor and current assignee accountId are confirmed;
      requester/reporter may differ.
- [ ] Objective, scope, criteria, dependencies, owner, labels, and validation are Ready.
- [ ] Registry row, Hub references, contract version, and handoff state are exact.
- [ ] AI authority and stop conditions are explicit.

### Before Ready for review

- [ ] PR contains only linked issue scope.
- [ ] Jira, `Closes`, and labels are present.
- [ ] Self-review, validation, and unverified items are recorded.
- [ ] FE/BE evidence and required handoff fields are complete.

### Before Jira Done

- [ ] Required Issues are closed and PRs merged; branches are deleted.
- [ ] No unresolved blocking feedback.
- [ ] Confluence is updated or documentation has an N/A reason.
- [ ] Completion page is in the confirmed space/Folder.
- [ ] Registry and Hub references show the current version and no required DRAFT/BLOCKED state.
- [ ] Jira contains Issue, PR, and documentation links.
