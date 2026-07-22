# Team Development AI Workflow

Merge this block into the repository-root `AGENTS.md`; do not replace stricter
repository-specific safety, architecture, ownership, or validation rules.

## Required routing

Before Jira, GitHub, Confluence, planning, or implementation work:

1. Read the repository rules and exact assigned issue first.
2. Read `docs/team-dev-ai-workflow/handbook.md` and pass the required integration
   preflight before using an external provider.
3. Read `docs/team-dev-ai-workflow/governance.md` for authority, ownership,
   readiness, cross-project mapping, and stop conditions.
4. Read the relevant lifecycle steps in
   `docs/team-dev-ai-workflow/workflow.md`.
5. Load only the relevant file under `docs/team-dev-ai-workflow/templates/`;
   do not load every template into context by default.

## Request modes

- `planning-only`: collect the minimum missing input, validate the project and
  active parent Epic, run counterpart discovery, and return a draft. Do not
  write externally unless the developer explicitly requests creation/update.
- `execution`: require an exact executable Jira item, verify requester/assignee
  by Jira `accountId`, Definition of Ready, repository, branch, worktree, and
  primary writer before editing.
- A request to plan and then implement uses `execution` gates.

## Non-negotiable gates

- Never guess a Jira project, parent Epic, counterpart, repository, assignee,
  Capability ID, Hub row, documentation location, or permission.
- A new Epic requires at least one initial `Feature`, `Story`, `Task`, or `Bug`;
  never create an empty Epic or a direct `Subtask` under an Epic.
- Cross-project candidates require developer confirmation. Similar titles are
  discovery evidence only and never authorize a link.
- Pure Frontend work creates no Backend Jira link or record.
- Read back created/updated records and report the exact workflow result; never
  convert missing access, failed validation, or invisible backlog state to PASS.
- Preserve one Jira item, one primary owner, one branch/worktree, and one PR for
  an implementation unit unless stricter repository rules require more.
- Human authorization remains required for destructive/production actions and
  AI approval or merge as defined by repository rules and governance.

Repository rules and the exact issue may narrow this workflow. They must not be
used to silently broaden authority or bypass a workflow stop condition.
