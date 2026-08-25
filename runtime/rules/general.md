# General Repository Governance

- Work only in the current repository, issue, branch, and file scope.
- Read existing linked records before asking for information or creating work.
- Do not guess a Jira project, Confluence location, repository, dependency,
  counterpart, parent, assignee, permission, or integration mapping.
- Resolve existing Confluence content by exact Confluence content ID, never by
  title similarity; a rename or move updates the same content.
- One issue has one primary owner, branch, and pull request.
- Repository-local rules and task instructions may narrow this authority but
  may not broaden it or bypass a stop condition.
- Current-repository source, branch, commit, push, Issue, and pull-request work
  does not require Atlassian OAuth.
- Every routing-dependent external write requires a fresh successful
  `beroka-governance preflight`.
- Routed Backend and Frontend profiles must match the stored GitHub
  Team-verified role; a mismatch returns `ROLE_SCOPE_DENIED`.
- An eligible preflight revalidates that role before connector login or an
  external write.
- AI may not approve or merge without explicit human confirmation for the exact
  pull request and reviewed commit.
- Report failed or unverified checks as blocked for their dependent scope;
  never report them as PASS.
- Before Jira creation, resolve exact project create metadata and search for the
  intended existing record. Create once, then read back the returned key and
  validate project, issue type, summary, and required linkage.
- If create status is indeterminate, return `CREATION_STATUS_UNKNOWN`; never retry automatically
  or create a second record.
- Confluence creation uses exact trusted space/root routing and reads back the
  created content and parent. Ordinary create/move use
  `confluence-page-parent-write`. Targets not listed as `UNACTIVATED` in the
  governance release are writable by default.
- Ordinary Confluence create, update, or move uses `confluence-write` and
  cannot publish cross-team readiness. Missing its existing Jira/GitHub
  handoff delta markers returns `HANDOFF_DELTA_REQUIRED`.
- A cross-team handoff is a self-contained Confluence page, not a link to an
  opposite-team repository. Team-local repositories remain private and may
  retain their own canonical artifacts and GitHub links; the consumer-facing
  page contains the complete public API and WebSocket contract, omissions,
  owner, effective date, supersession metadata, and FE acknowledgment path.
- Before a cross-team Confluence create or update, run
  `beroka-governance preflight REPO --client CLIENT --operation confluence-handoff-write --non-interactive --confluence-action create|update --target-content-id new|ID --expected-parent-id ACTIVE_FOLDER_ID --handoff-body-file FILE`.
  The parent must be one exact reviewed `ACTIVE Folder`; root, page,
  `UNACTIVATED`, and untracked parents return `FOLDER_CREATION_REQUIRED`.
  Cross-team Jira intake or acknowledgment text uses `jira-intake-write` or
  `jira-handoff-write` with the exact body and never an opposite-team GitHub
  link; use Jira keys and Confluence references only.
- Create is DRAFT-only. `READY_FOR_FE` is update-only and may be reported only
  after a fresh `beroka-governance preflight REPO --client CLIENT --operation confluence-handoff-verify --non-interactive --confluence-action update --target-content-id ID --expected-parent-id ID --handoff-body-file FILE --readback-parent-id ID --readback-space-key KEY --readback-title TITLE --readback-version POSITIVE_INTEGER --readback-owner-account-id ACCOUNT_ID` passes. A pre-write PASS authorizes only the write. Jira remains in its governed lifecycle state independently.
- A content ID or parent ID listed as `UNACTIVATED` in the pinned release
  inventory returns `DOCS_UNACTIVATED` (only a reviewed governance release PR
  can change that list). A transport mismatch on a reviewed drifted row returns
  `MAPPING_CONFLICT`; ask the user and wait.
- Confluence hierarchy guidance is optional. Use read-only
  `beroka-governance confluence-discover` and optional
  `confluence-bootstrap-*` to improve Scope—Domain—Transport discoverability.
  Bootstrap is not a write gate. Never invent an `UNACTIVATED` row in a user
  session.
- When creating a Jira work item from Cursor, call Atlassian MCP
  `createJiraIssue` with official fields only: `projectKey`, `issueTypeName`,
  `parent` (or standalone reason in description), `assignee_account_id`,
  `additional_fields.priority` as `{ "name": "Highest"|"High"|"Medium"|"Low" }`,
  and `description` that starts with `Work-item language: English` plus
  `GitHub: <url>` or `GitHub: N/A`. Do not invent top-level `issue_type`,
  string `priority`, `assignee`, or `github` keys — Atlassian rejects unknown
  properties and governance accepts the official aliases. If the hook denies
  with `WORK_ITEM_TEMPLATE_REQUIRED`, read `agent_message` for `Missing: …`,
  fix those fields once, and retry; never tell the user raw governance codes.
  On FULL_STACK Backend+Frontend multi-root, always name exactly one of BB/BF
  via `projectKey` or parent/epic key so target selection can proceed; never ask
  the user to close a workspace folder for that.
- Before any Jira field, description, comment, or status update, read the
  authenticated and current-assignee Atlassian `accountId`. A mismatch or
  unassigned item returns `ASSIGNEE_CONFIRMATION_REQUIRED` and waits for exact
  user authorization.
- Cross-team intake and handoff text must not contain opposite-team private
  GitHub links. Return `CROSS_TEAM_LINK_SCOPE_DENIED` and use an accessible
  exact Confluence page instead.
- `Closes #<issue>` normally closes the GitHub Issue. If it remains open, an
  agent may close it only after exact merge/link readback proves the delivered commit
  and the close write is authorized; otherwise report the issue as
  blocked. After `Closes #<issue>` automatically closes the current primary GitHub Issue,
  or after an agent completes an authorized manual close under
  this gate, resolve the exact linked Jira item, verify the authenticated
  account against the current assignee, run a fresh `jira-write` preflight,
  and transition the item to `In Review`; an item already in `In Review` is
  idempotently complete. Then resolve related documentation only by exact
  Confluence content ID. If the page, parent, or required change is missing or
  ambiguous, ask the user and wait. Otherwise run a fresh target-bound
  Confluence preflight, update the documentation, and read it back. After
  documentation readback Jira remains in `In Review`; do not move it to `Done`
  automatically. After successful documentation readback, report the GitHub, Jira, and Confluence outcomes separately.
  Report a blocked Jira or Confluence step separately and do not reopen the GitHub Issue.
