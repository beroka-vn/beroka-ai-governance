# General Repository Governance

- Work only in the registered repository, issue, branch, and file scope.
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
- AI may not approve or merge without explicit human confirmation for the exact
  pull request and reviewed commit.
- Report failed or unverified checks as blocked for their dependent scope;
  never report them as PASS.
