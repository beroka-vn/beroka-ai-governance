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
