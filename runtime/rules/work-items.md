# BE/FE Work Items

- Classify work as Frontend, Backend, or shared before planning or record
  creation. Shared work requires exact target repositories, one confirmed
  primary tracking repository, and fresh context for every target. Do not infer
  a target from the IDE workspace or repository name.
- Every GitHub issue has one primary human owner. An explicit assignee wins;
  otherwise use the requesting developer when known, then the authenticated
  human creator. Never default to a bot or service account. Stop if ownership
  is unresolved.
- In organization repositories use native Issue Type `Bug`, `Feature`, or
  `Task` without a duplicate `type:*` label. In personal repositories use
  exactly one configured fallback label: `type:bug`, `type:feature`, or
  `type:technical`. Both require at least one `area:*` and exactly one
  `priority:*`. Missing required fallback labels returns
  `LABEL_CONFIGURATION_REQUIRED`; never create labels silently.
- Before creating a Jira `Feature`, `Story`, `Task`, or `Bug`, search active
  Epics in the selected project. Use a clearly related Epic; present ambiguous
  candidates and wait. A distinct multi-item outcome requires a new Epic plus
  an initial child. Never parent a `Subtask` directly under an Epic.
- A truly unrelated one-off or hotfix may stand alone only after explicit
  developer confirmation. Record `Parent Epic: N/A`, the standalone reason,
  reviewed Epic candidates, owner, priority, and GitHub issue.
- After creation, read back GitHub owner, type or fallback label, area,
  priority, and primary Jira linkage; read back Jira project, type, parent or approved
  standalone reason, assignee, and GitHub link. A failed readback is not
  `PASS`.
