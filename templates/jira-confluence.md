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
- Use the matching Epic, Story, or Task template. For Bug, Feature, or another
  type, preserve the native type and use the nearest high-level structure.
- Before creating a child, establish work area, type, and parent Epic. An active
  Epic belongs to the correct project, is not archived, and has
  `statusCategory != Done`.
- If the Epic is missing, invalid, inactive, or ambiguous, list active candidates
  and wait. Never select a parent, create an orphan, or duplicate across projects.
- Before a new Epic, show duplicates and require an initial Feature/Story/Task/Bug.
  Never create a direct Subtask under an Epic.
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
- Developer decision: choose an Epic | create a new Epic | cancel
```

If Jira cannot be read, report access failure. Never invent an Epic list.

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
- Capability ID / Integration Hub row: <exact values | Pending | N/A>
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
- A Backend Feature may `Blocks` BF items. All records share one immutable
  uppercase-kebab-case Capability ID.
- Non-blocking same-capability children use `Relates`; dependencies use `Blocks`
  provider → consumer.
- The Hub row is canonical. Read back the ID and links before `PASS`.
- Pending counterparts return `MAPPING_INCOMPLETE`; missing/duplicate IDs or
  conflicting links return `MAPPING_CONFLICT`. Never map by title similarity.

```text
CROSS-TEAM MAPPING
- Capability ID: exact uppercase kebab-case value
- Backend Epic and Feature: Jira keys and URLs
- Frontend Epic: Jira key and URL
- Frontend work items: one or more Jira keys/URLs or Pending with owner
- Epic link: Relates readback result
- Child links: Blocks | Relates | None, with readback result
- Integration Hub row: URL and exact row readback result
- Result: PASS | NO_BACKEND_DEPENDENCY | MAPPING_INCOMPLETE | MAPPING_CONFLICT | FAILED_READBACK
```

## Confluence documentation location

- Frontend use cases/services:
  [Beroka-frontend](https://beroka.atlassian.net/wiki/spaces/Berokafron).
- Backend use cases/services:
  [Beroka-backend](https://beroka.atlassian.net/wiki/spaces/Berokaback/overview).
- Each Epic uses one native Folder named `<Epic key> — <Epic summary>`; all Epic
  pages belong under it.
- If unavailable, return `FOLDER_CREATION_REQUIRED`; never use a page/root fallback.
- After write/move, read back `parentId` and `parentType = Folder`; otherwise
  return `DOC_HIERARCHY_FAILED`.
- Ask the developer about ambiguous shared work, space, Folder, or interpretation.
- One shared Hub lives in the owning space. The FE Folder contains a
  `Frontend Index` linking the Hub and FE docs; never duplicate the contract.
- BF items and the Index must open the Hub; otherwise return
  `CROSS_SPACE_ACCESS_REQUIRED` rather than copying content.
- Do not create empty BF Epics, FE Folders, or subpages.

```text
Documentation location confirmation
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
- Required native Folder title: Jira Epic key — Epic summary
- Required parent location: exact space parent
- Required action: developer creates the native Folder and returns URL/ID
- Work that may continue safely: explicit independent scope or None
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
- Capability ID / Epic Integration Hub: <exact values | Pending | N/A>
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
- Capability ID / Epic Integration Hub: <exact values | Pending | N/A>
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
- Capability ID / Epic Integration Hub: <exact values | Pending | N/A>
- Contract version / handoff state: <exact values | Pending | N/A>
- Related Jira items:

## Delivery links

- GitHub Issues: Pending
- Merged PRs: Pending
- Completion document: Pending
```

## Jira Completion Links Block

Add this block before the Jira item moves to `Done`:

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
- Final contract artifact/version: <link/version | N/A>
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
- Coordinator:
- Backend Epic/Folder:
- Frontend Epic/Folder:
- Frontend Index:
- Completion document: Pending

## Epic mapping

| Relationship | Source | Target | Jira link/readback |
| --- | --- | --- | --- |
| Paired Epics | <BB Epic> | <BF Epic or Pending with owner> | Relates: <result> |

## Capability mapping

| Capability ID | BE Jira item | BF Jira item(s) | Contract artifact/version | Handoff state | Owners | Breaking |
| --- | --- | --- | --- | --- | --- | --- |
| <UPPERCASE-KEBAB-ID> | <BB Feature and link> | <one or more BF links or Pending with owner> | <repo URL/path, version, commit/hash> | DRAFT | <BE owner / BF owner> | No |

## Shared decisions

| Decision | Reason | Owner | Related issue/PR |
| --- | --- | --- | --- |

## Known limitations

- <limitation and linked follow-up>

## Contract changelog

| Date/time | Contract version | State change | BE record | FE acknowledgement |
| --- | --- | --- | --- | --- |
```

## BE → FE Handoff Block

Copy this block into the BE Jira/GitHub Issue or PR when `Frontend impact != None`:

```markdown
## BE → FE handoff

- Capability ID:
- Epic Integration Hub:
- Paired Backend Epic:
- Paired Frontend Epic:
- Backend Jira/GitHub issue and merged PR:
- Frontend Jira/GitHub issue(s):
- Epic `Relates` readback:
- BE-to-BF `Blocks` readback for every BF item:
- Integration Hub mapping-row readback:
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
path. FE records `ACKNOWLEDGED` for the exact version. A version change marks
the old handoff `SUPERSEDED`, updates the changelog, and notifies FE again.

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
