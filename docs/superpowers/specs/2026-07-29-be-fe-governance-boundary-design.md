# BE/FE Governance Boundary Design

Status: Approved

## Problem

The verified release is installed once per user and client, but planning starts
from the repository open in the IDE. A full-stack request can therefore begin
in Frontend context and later create Backend work without first loading the
Backend profile. The published catalog also lacks active records for the
canonical Beroka Backend and Frontend repositories, so both can fall back to
standalone routing.

Detailed GitHub and Jira work-item rules currently live mainly in templates.
They are not part of the compact runtime context, so an enrolled client can
still miss ownership, classification, or hierarchy requirements.

This design applies only to the official Beroka Backend and Frontend boundary.
It does not enroll or govern unrelated repositories or roles.

## Canonical boundary

The active release recognizes these exact repositories:

- `cuongngo1801-beroka/Beroka_Backend`
- `cuongngo1801-beroka/Beroka_Frontend`

Backend routes to Jira `BB`, board `34`, and Confluence space `Berokaback`
under page `65962274`. Frontend routes to Jira `BF`, board `35`, and
Confluence space `Berokafron` under page `65831203`.

Both records use the `beroka-be-fe` integration profile and
`profile-controlled` cross-repository policy. Cross-repository writes remain
blocked until an exact counterpart and workflow mapping is reviewed; the
catalog records do not authorize automatic writes to both repositories.

The transferred legacy slug `hungnx77/Beroka_Backend` is not retained as an
alias because it could later identify a different repository. Existing clones
must use the canonical remote URL.

## Repository and planning context

The user-level client instruction must require a fresh
`beroka-governance context` call when:

- the IDE workspace or current Git repository changes;
- a request introduces work in another repository; or
- a plan changes from Frontend-only or Backend-only to shared/full-stack.

Before planning or creating records, the agent classifies the work as
Frontend, Backend, or shared. Shared work requires exact target repositories
and one confirmed primary tracking repository. Each target receives its own
context lookup. Missing or unknown targets stop the dependent scope instead of
being inferred from repository names or the current IDE workspace.

## GitHub issue metadata

Every created issue has one primary human owner. An explicitly requested
assignee wins. Otherwise the requesting developer is assigned when their
GitHub identity is known; for a human-owned OAuth session, the authenticated
creator is the fallback. A bot or service account is never selected as the
default owner. Unresolved ownership stops creation.

Classification adapts to GitHub ownership:

- Organization repositories use native Issue Type (`Bug`, `Feature`, or
  `Task`) and do not require a duplicate `type:*` label.
- Personal-account repositories use exactly one fallback label:
  `type:bug`, `type:feature`, or `type:technical`.
- Both use at least one `area:*` label and exactly one `priority:*` label.

If required fallback labels are unavailable, creation stops with
`LABEL_CONFIGURATION_REQUIRED`; governance does not silently create
repository labels. After creation, the agent reads back owner, native type or
fallback type label, area, priority, and primary Jira linkage before reporting
success.

## Jira hierarchy

For every proposed `Feature`, `Story`, `Task`, or `Bug`, the agent searches
active Epics in the selected project before creation:

1. A clearly related active Epic is the required parent.
2. An ambiguous parent produces an evidence-backed candidate list and waits
   for the developer.
3. A distinct outcome large enough to own several work items requires a new
   Epic plus at least one initial `Feature`, `Story`, `Task`, or `Bug`.
4. A truly unrelated one-off or hotfix may be standalone only after explicit
   confirmation and must record `Parent Epic: N/A`, the standalone reason,
   reviewed Epic candidates, owner, priority, and GitHub issue.

A `Subtask` is never parented directly under an Epic. A standalone exception
is traceable work, not an implicit orphan. Missing evidence or an unclear
classification stops creation.

After creation, readback verifies project, issue type, parent or approved
standalone reason, assignee, and traceability. A failed check is not `PASS`.

## Runtime delivery

A compact BE/FE work-item rules file is included in the verified release and
emitted by `context` only for repositories whose exact catalog record selects
the `beroka-be-fe` integration profile. The detailed governance, workflow, and
templates remain the durable references.

The existing technical enforcement boundary remains explicit: the CLI
hard-enforces release integrity, routing, connector health, and preflight.
Work-item payload conformance remains instruction-driven unless GitHub or Jira
platform automation is separately authorized.

## Verification

- Release validation accepts both exact catalog records and rejects an
  unlisted repository.
- Backend context emits the Backend profile and compact BE/FE work-item rules.
- Frontend context emits the Frontend profile and the same shared boundary.
- User instructions require re-context on repository/workspace change.
- The existing shell suite remains green.
- A manual Cursor pressure test covers FE-only, BE-only, shared planning,
  organization Issue Type, personal-repository type-label fallback, normal
  Epic parenting, and the explicit standalone/hotfix exception.

## Out of scope

- Automatic governance enrollment for unrelated repositories or roles.
- Wildcard repository routing.
- Automatic cross-repository writes.
- Silent creation of GitHub labels or Jira hierarchy configuration.
- Jira or GitHub platform automation in application repositories.
