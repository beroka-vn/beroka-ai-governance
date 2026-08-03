# Backend–Frontend Integration

- BB and BF use separate project-local Jira items and exact verified links.
- A shared capability uses one verified Backend Capability Registry row.
- Integration Hubs reference exact Registry rows; they do not own or redefine
  canonical capabilities.
- One Registry capability may be referenced by several Epics and Frontend
  module indexes.
- Backend publishes the canonical contract artifact; Frontend consumes its
  exact version and does not reconstruct it from issue descriptions.
- Similar names produce candidates only and never authorize links or writes.
- Counterpart and handoff discovery requires exact Jira, Hub, or contract
  evidence plus developer confirmation where the mapping is not unique.
- Cross-repository writes require `CROSS_REPO_POLICY=profile-controlled`.
- `explicit-only` narrows this pack and disables automatic counterpart use.
- Frontend → Backend and Backend → Frontend intake use the exact canonical
  mappings in `beroka-be-fe.intake` through `jira-intake-write`. This authorizes
  only a new intake record in the returned Jira project; it does not grant
  receiving-repository execution authority.
- The requester/reporter stays separate from the receiving executor/assignee.
  Assignment alone never creates a GitHub Issue; the receiving team must verify
  Accepted, Ready, Assigned, Definition of Ready PASS, and no existing primary
  Issue. An assignee update requires the authenticated accountId to match the
  current assignee or explicit confirmation; otherwise return
  `ASSIGNEE_CONFIRMATION_REQUIRED`.
- Task, Bug, and Feature intake is symmetric. Opposite-project Epic creation
  requires receiving-team confirmation. FE owns BF updates and BE owns BB
  updates; the other team reviews its own item through the exact accessible
  Confluence handoff.
- Before a Confluence handoff, run target-bound `confluence-handoff-verify`.
  Unknown targets return `ROUTING_REQUIRED` and wait. Opposite-team private
  GitHub links return `CROSS_TEAM_LINK_SCOPE_DENIED`; use Confluence instead.
- Provider status is `To Do -> In Progress` when work starts, `In Progress ->
  In Review` when a human marks the PR ready, and `In Review -> Done` after
  merge and documentation readback.
- Missing supported intake workflow evidence returns
  `INTAKE_CONFIGURATION_REQUIRED`. Intake is agent-driven, not an event
  listener.
- General `cross-repo-write` remains `ROUTING_REQUIRED` before client
  inspection.
