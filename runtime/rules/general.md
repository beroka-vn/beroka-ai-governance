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
  created content and parent. Folder routing remains blocked without isolated
  pilot evidence.
- Before a Confluence create, update, move, or handoff, resolve the exact
  content ID, Capability ID, scope, domain, transport, parent ID, and Registry
  content ID; run target-bound `confluence-write` or
  `confluence-handoff-verify`. Unknown or ambiguous targets return
  `ROUTING_REQUIRED`; a target or transport mismatch returns
  `MAPPING_CONFLICT`; ask the user and wait.
- Confluence documentation has three phases. Use read-only
  `beroka-governance confluence-discover` first. When the inventory is
  legacy-only or missing an ACTIVE folder/Registry, run authorized bootstrap
  (`confluence-bootstrap-plan` → human-confirmed MCP create →
  `confluence-bootstrap-capture` → `confluence-bootstrap-verify`) and open a
  reviewed governance inventory PR. Only after ACTIVE folder rows exist, use
  ordinary target-bound documentation updates. Never guess Capability ID,
  Registry ID, parent ID, or title similarity.
- Before any Jira field, description, comment, or status update, read the
  authenticated and current-assignee Atlassian `accountId`. A mismatch or
  unassigned item returns `ASSIGNEE_CONFIRMATION_REQUIRED` and waits for exact
  user authorization.
- Cross-team intake and handoff text must not contain opposite-team private
  GitHub links. Return `CROSS_TEAM_LINK_SCOPE_DENIED` and use an accessible
  exact Confluence page instead.
