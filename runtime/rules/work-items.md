# BE/FE Work Items

- AI-generated Jira and GitHub work items and technical artifacts default to
  English. Chat language does not select artifact language. Use another language
  only when the user explicitly supplies `Work-item language: <language>` for
  the current generation.
- Jira summaries use English sentence case, no trailing punctuation, and
  no Jira key or `[Epic]`, `[Feature]`, `[Task]`, or `[Bug]` prefix:
  - Epic: `<Domain or module> — <Business outcome>`
  - Feature: `<Capability> — <Observable outcome>`
  - Task: `<Action verb> <Outcome or deliverable>`
  - Bug: `<Actual symptom> when <condition>`
- Classify work as Frontend, Backend, or shared before planning or record
  creation. Shared work requires exact target repositories, one confirmed
  primary tracking repository, and fresh context for every target. Do not infer
  a target from the IDE workspace or repository name.
- Cross-team intake is symmetric for Frontend → Backend and Backend → Frontend.
  Use `jira-intake-write` from the requesting repository only when preflight
  returns the exact receiving profile and Jira project. The private receiving
  repository identity remains internal to governance routing.
- The requester/reporter remains distinct from the executor/assignee. Intake
  starts with Sprint unset and no receiving-project parent selected. An exact
  receiving-team account may be assigned only after the user or receiving team
  confirms that accountId; otherwise leave assignee unset and return
  `ASSIGNEE_CONFIRMATION_REQUIRED`. The receiving team owns triage, issue type,
  active Epic, final priority, Sprint, readiness, assignment, and technical
  delivery.
- Assignment alone does not authorize a GitHub Issue. Create exactly one
  receiving-repository Issue only after
  `Accepted + Ready + Assigned + Definition of Ready PASS` and a search proves
  there is no existing primary GitHub Issue.
- Missing supported intake state or equivalent field returns
  `INTAKE_CONFIGURATION_REQUIRED`. Intake handling is
  agent-driven; there is no event listener.
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
- FE owns updates to BF items and BE owns updates to BB items. Cross-team
  `Task`, `Bug`, and `Feature` intake is allowed; opposite-project `Epic`
  creation requires receiving-team confirmation. Cross-team Jira descriptions,
  comments, and acknowledgments use `jira-intake-write` or `jira-handoff-write`
  with Jira keys and exact Confluence references only; team-local GitHub links
  remain local to their owning team.
- Provider status follows `To Do -> In Progress` when accepted work starts and
  `In Progress -> In Review` when a human marks the provider PR ready for
  review.
- Cross-team updates containing opposite-team private GitHub links return
  `CROSS_TEAM_LINK_SCOPE_DENIED`; use the exact accessible Confluence page.
